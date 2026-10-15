-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0128 — WAGES ARE PAID FROM PROFIT
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER'S WORDS ───────────────────────────────────────────────────────────────────────────
-- 2026-10-15: *"because of wages, ships are losing too much money. pay wages only when a profit is
-- made."* — the same rule as his earlier "tax or any fees only when a profit is made" (0122's
-- public.profit_tax), now for the crew. Wages are DEFERRED to a profit, never dodged: hopping from
-- port to port without selling does not wipe them.
--
-- ── WHAT WAS FOUND (prod, since 0122 set npc_cost_mult 1 at 06:00 UTC) ──────────────────────────
-- ~90 % of merchant laps lose: a lap sells ~3,300, buys ~2,900 and pays ~300-430 in wages
-- (public.standing_route_laps). voyage.settle charged the day's wage on EVERY sea-day whatever the
-- passage earned, so a thin margin became a loss. As a stopgap npc_cost_mult was set to 0 on prod.
--
-- ── THE RULE (one authority, every ship — a player's and a merchant's by the same lines) ────────
--   * A SEA-DAY PAYS NO WAGE. voyage.settle hands the day's wage — the same figure as before,
--     public.crew_wages × public.running_cost_mult, still written into the day's payload — to
--     public.owe_wages (NEW), which adds it to public.fleet_wages.owed (NEW side table). Nothing
--     leaves the purse at sea.
--   * THE DEBT CARRIES OVER from passage to passage, capped at wages_owed_cap_days (knob, 30) of
--     that day's wage: what lies above the cap is forgiven, so a chronically losing ship is not
--     buried. Nothing else forgives it.
--   * IT IS PAID ONLY OUT OF PROFIT, AT A PORT VISIT. cmd.do_sell, after 0122's profit tax, hands
--     the sale's after-tax profit (signed; null when the cost is unknown) to public.pay_wages (NEW,
--     THE ONE MOVER), which keeps the visit's running NET after-tax profit and pays
--       public.wages_from_profit(owed, least(this sale's profit, visit net − already paid this visit))
--     = never more than this sale's profit (a sale never becomes a loss) and never more than the
--     visit's net (a losing sale at the same port reduces what can be paid). A visit is the span
--     between two sea-days: owe_wages, which runs only at sea, starts a fresh visit. The payment is
--     public.pay_city(..., 'WAGES', ...) — a WAGES ledger row, and lit, a WAGES flow INTO THE CITY OF
--     THE SALE. do_sell's result carries `wages`; its `net` is after tax and wages.
--   * SUPPLIES AND REPAIRS STAY AS THEY ARE: they are purchases, paid when made (0122's PROVISION /
--     REPAIR rows, × running_cost_mult for a merchant), not wages.
--   * THE LAP (cmd.standing_route_close_lap) books `wages` = Σ of its SELLs' paid `wages` — what left
--     her purse, as sold / bought / taxes are — instead of the wage owed per sea-day. Net formula
--     unchanged.
--   * THE PLANNER (public.npc_leg_lines) keeps a parcel when it pays after the profit tax (and
--     npc_min_return_pct), no longer only when it beats the whole leg's wage bill; the leg's
--     `profit` is its profit less public.wages_from_profit(leg wages, profit) — the same rule the
--     sale pays by, so npc_plan never refuses a loop that pays.
--   * npc_cost_mult goes back to 1 (the owner's full-cost decision stands; the rule protects merchants).
--
-- ── WHAT IT DOES NOT DO ─────────────────────────────────────────────────────────────────────────
-- No new entry point, no client write, no cron. voyages.wages_paid (0122) is kept and no longer added
-- to; the arrival still posts what it holds (days paid before this file). A fleet at sea at deploy
-- time owes only the days settled after it. world.crew_cost and the Inn's per-day quote are
-- unchanged (the day's wage is the same figure; when it is paid moved). voyage.depart is untouched.
--
-- ── LOCKS, AND THE PROBES ───────────────────────────────────────────────────────────────────────
-- lock_timeout 5 s; no LOCK TABLE, no set role, no begin/commit (db push runs the file as one
-- implicit transaction). fleet_wages.fleet_id references fleets ON DELETE CASCADE: creating that FK
-- takes SHARE ROW EXCLUSIVE on fleets until commit (the file's run, seconds) — the arrivals sweep's
-- fleet writes wait that long. The self-assert's player and merchant are its own (new_house,
-- npc_found), rolled back; no live merchant fleet, route or house is written; the planner probe
-- only READS live routes; the sales use a good no merchant route trades at LIS / FNC, so no live
-- merchant line waits on the probe's market rows.
--
-- ── ROLLBACK ────────────────────────────────────────────────────────────────────────────────────
-- npc_cost_mult 0 by knob (instant). The code: one forward migration re-cutting the six bodies —
-- every OLD hunk is in this file verbatim (hunks_0128.old) and the self-assert proves each live body
-- reverses to its pre-image by them; then drop owe_wages, pay_wages, wages_from_profit, fleet_wages.
--
-- SUPERSEDES: voyage.settle (0114 as cut by 0122/0123/0125/0127), cmd.do_sell (0122),
-- public.npc_leg_lines (0120 as cut by 0122), cmd.standing_route_close_lap (0116 as cut by
-- 0121/0122), public.running_cost_mult and public.route_earnings (comment lines only) — hunks sliced
-- from the LIVE bodies (LF-normalised), each asserted to occur exactly once. Self-asserts hold AS
-- FOUND; every probe rolls back.
-- VERSION: 0128. Applies on prod head 0127. Its voyage.settle hunks are all in the per-sea-day wage
-- charge (the declaration, the charge, the day's UPDATE): clear of 0125's delay arms and of 0127's
-- arrival arm; the arrival's wages-to-harbour block is left as it is (it still posts, at arrival,
-- wages a passage paid BEFORE this file; nothing for a passage begun after it).

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);   -- 0127's posture: never queue the arrivals sweep for long
end $guard$;

-- ── 1. THE PRE-IMAGES ──────────────────────────────────────────────────────────────────────────
create temp table defs_before_0128 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl
  from unnest(array['voyage.settle(uuid, timestamptz)',
                    'cmd.do_sell(uuid, jsonb)',
                    'public.npc_leg_lines(uuid, uuid, uuid, numeric, integer, numeric)',
                    'cmd.standing_route_close_lap(uuid, timestamptz)',
                    'public.running_cost_mult(uuid)',
                    'public.route_earnings(uuid)']) f(fn);

create temp table before_0128 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       public.wc('npc_cost_mult') as npc_cost_mult,
       (select count(*) from public.world_config where key = 'wages_owed_cap_days') as knobs_found;

-- ── 2. THE KNOB AND THE BOOK ───────────────────────────────────────────────────────────────────
insert into public.world_config (key, value, description) values
  ('wages_owed_cap_days', to_jsonb(30),
   '0128: a fleet carries unpaid wages from passage to passage up to this many days of her day''s wage '
   '(public.owe_wages); what lies above is forgiven.')
on conflict (key) do nothing;

create table if not exists public.fleet_wages (
  fleet_id   uuid   primary key references public.fleets(id) on delete cascade,
  owed       bigint not null default 0 check (owed >= 0),
  visit_net  bigint not null default 0,
  visit_paid bigint not null default 0 check (visit_paid >= 0)
);
comment on table public.fleet_wages is
  '0128: what a fleet''s crew are owed and not yet paid, carried from passage to passage (capped at '
  'wages_owed_cap_days of the day''s wage), and the current port visit''s running net after-tax profit and '
  'wages paid. Written by public.owe_wages (each sea-day; starts a fresh visit) and public.pay_wages (each '
  'sale) alone. No row = nothing owed.';
alter table public.fleet_wages enable row level security;
revoke all on table public.fleet_wages from public, anon, authenticated;
comment on column public.voyages.wages_paid is
  '0122: Σ of the WAGES this voyage''s house paid per settled sea-day. 0128: no longer written — a sea-day '
  'pays no wage (what a voyage held before 0128 still reaches its harbour at arrival); wages are paid out of '
  'a sale''s profit (public.fleet_wages, public.pay_wages).';

-- ── 3. THE RULE, THE DEBT AND THE MOVER ────────────────────────────────────────────────────────
create or replace function public.wages_from_profit(p_owed numeric, p_profit numeric)
returns numeric
language sql
immutable
set search_path = public, pg_temp
as $$
  -- 0128: THE RULE. Of what she owes her crew, a profit pays at most itself: nothing on a loss, a
  -- break-even, or a profit the game cannot know (null). public.pay_wages pays by it; the planner
  -- (npc_leg_lines) prices a leg by it.
  select case when p_owed > 0 and p_profit > 0 then least(p_owed, p_profit) else 0 end
$$;

create or replace function public.owe_wages(p_fleet uuid, p_wage bigint)
returns bigint
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0128: A SEA-DAY'S WAGE IS OWED. Added to what the fleet already owes (carried from passage to
-- passage), capped at wages_owed_cap_days × this day's wage — the rest is forgiven. A sea-day ends
-- any port visit, so the visit's figures start afresh. Called by voyage.settle alone. Returns owed.
declare
  v_owed bigint;
begin
  if coalesce(p_wage, 0) <= 0 then
    return null;
  end if;
  insert into public.fleet_wages as w (fleet_id, owed)
  values (p_fleet, least(p_wage, public.wc_int('wages_owed_cap_days') * p_wage))
  on conflict (fleet_id) do update
     set owed = least(w.owed + excluded.owed, public.wc_int('wages_owed_cap_days') * p_wage),
         visit_net = 0, visit_paid = 0
  returning w.owed into v_owed;
  return v_owed;
end $$;

create or replace function public.pay_wages(p_fleet uuid, p_port uuid, p_profit bigint, p_event uuid default null)
returns bigint
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0128: THE ONE MOVER of a crew's pay. p_profit is this sale's profit after the profit tax (signed;
-- null when the hold did not know the cost). The visit's net is kept; the pay is
-- wages_from_profit(owed, least(this sale's profit, visit net − paid this visit)) — never more than
-- the sale's own profit, never more than the visit's net. Then the house pays the city of the sale
-- (public.pay_city: a WAGES ledger row; lit, a WAGES flow). A merchant's and a player's are paid by
-- these lines. Returns what was paid.
declare
  w      public.fleet_wages%rowtype;
  v_pay  bigint;
  v_player uuid;
begin
  select * into w from public.fleet_wages where fleet_id = p_fleet for update;
  if w.fleet_id is null then
    return 0;   -- she has never owed a wage
  end if;
  w.visit_net := w.visit_net + coalesce(p_profit, 0);
  v_pay := case when p_profit is null then 0
                else round(public.wages_from_profit(w.owed, least(p_profit, w.visit_net - w.visit_paid)))::bigint end;
  update public.fleet_wages
     set owed = w.owed - v_pay, visit_net = w.visit_net, visit_paid = w.visit_paid + v_pay
   where fleet_id = p_fleet;
  if v_pay > 0 then
    select f.player_id into v_player from public.fleets f where f.id = p_fleet;
    perform public.pay_city(v_player, p_port, 'WAGES', v_pay, p_event);
  end if;
  return v_pay;
end $$;

revoke all on function public.wages_from_profit(numeric, numeric)     from public, anon, authenticated;
revoke all on function public.owe_wages(uuid, bigint)                 from public, anon, authenticated;
revoke all on function public.pay_wages(uuid, uuid, bigint, uuid)     from public, anon, authenticated;

-- ── 4. THE HUNKS (old = verbatim from the live bodies; new = what replaces it) ─────────────────
create temp table hunks_0128 (fn text, n int, old text, new text) on commit drop;

insert into hunks_0128 values
-- voyage.settle: the day's wage is OWED, not paid
('voyage.settle(uuid, timestamptz)', 1,
$h$  v_wages   bigint;
  v_paid    bigint;   -- 0122: what the house actually paid this sea-day
$h$,
$h$  v_wages   bigint;
$h$),
('voyage.settle(uuid, timestamptz)', 2,
$h$    if v_wages > 0 then
      -- A house that cannot pay does not vanish: the wages are still owed and the purse floors at
      -- zero rather than the transaction dying halfway through a settled day.
      v_paid := least(v_wages, (select ducats from public.players where id = f.player_id));
      perform public.credit(f.player_id, 'WAGES', -v_paid);
    end if;
$h$,
$h$    if v_wages > 0 then
      -- 0128: OWED, NOT PAID (owner, 2026-10-15: "pay wages only when a profit is made"). The day's
      -- wage joins what the fleet owes her crew (public.owe_wages: carried, capped); cmd.do_sell pays
      -- it out of profit (public.pay_wages).
      perform public.owe_wages(p_fleet, v_wages);
    end if;
$h$),
('voyage.settle(uuid, timestamptz)', 3,
$h$    update public.voyages set last_settled_day = d,
           wages_paid = wages_paid + case when v_wages > 0 then v_paid else 0 end   -- 0122
     where id = v.id;
$h$,
$h$    update public.voyages set last_settled_day = d where id = v.id;   -- 0128: a sea-day pays no wage
$h$),

-- cmd.do_sell: the crew are paid out of the profit, after the tax
('cmd.do_sell(uuid, jsonb)', 1,
$h$  v_fit     numeric;
begin
  select * into f from public.fleets where id = p_fleet;
$h$,
$h$  v_fit     numeric;
  v_wages   bigint := 0;   -- 0128: the wages this sale pays out of its profit
begin
  select * into f from public.fleets where id = p_fleet for update;   -- 0128: one sale of hers at a time pays her crew
$h$),
('cmd.do_sell(uuid, jsonb)', 2,
$h$    perform public.pay_city(f.player_id, f.port_id, 'TAX', v_tax, null);
  end if;
$h$,
$h$    perform public.pay_city(f.player_id, f.port_id, 'TAX', v_tax, null);
  end if;
  -- 0128: then the crew, out of what the tax left (the visit's net, never past this sale's profit).
  v_wages := public.pay_wages(p_fleet, f.port_id, v_profit - v_tax, null);
$h$),
('cmd.do_sell(uuid, jsonb)', 3,
$h$                            'tax', v_tax, 'net', q.total - v_tax,
$h$,
$h$                            'tax', v_tax, 'wages', v_wages, 'net', q.total - v_tax - v_wages,
$h$),

-- public.npc_leg_lines: a parcel that pays is kept; the leg earns its profit less the wages it pays
('public.npc_leg_lines(uuid, uuid, uuid, numeric, integer, numeric)', 1,
$h$--      left. KEEP only if the two quotes at that size beat the leg's wages (running_cost_mult) and
$h$,
$h$--      left. KEEP only if the two quotes at that size pay after the profit tax (0128: the leg's
--      wages, running_cost_mult, come out of its profit — public.wages_from_profit) and
$h$),
('public.npc_leg_lines(uuid, uuid, uuid, numeric, integer, numeric)', 2,
$h$      continue when v_net - v_wages <= 0
$h$,
$h$      -- 0128: wages are paid out of the profit and never past it, so a parcel that pays is kept.
      continue when v_net <= 0
$h$),
('public.npc_leg_lines(uuid, uuid, uuid, numeric, integer, numeric)', 3,
$h$  return jsonb_build_object('lines', v_lines, 'profit', v_profit, 'nm', v_nm, 'any', v_any);
$h$,
$h$  -- 0128: what the leg LEAVES her — its profit less the wages it pays, by the rule the sale pays by.
  return jsonb_build_object('lines', v_lines, 'profit', v_profit - public.wages_from_profit(v_wages, v_profit),
                            'nm', v_nm, 'any', v_any);
$h$),

-- cmd.standing_route_close_lap: the lap books the wages its sales paid
('cmd.standing_route_close_lap(uuid, timestamptz)', 1,
$h$  -- The wage OWED per settled sea-day (0086 writes it into every day's payload). The purse floor
  -- may have charged less; the lap reports what the crew earned.
  select coalesce(round(sum((ve.payload->>'wages')::numeric)), 0) into v_wages
    from public.voyage_events ve
   where ve.voyage_id in (select (o.result->>'voyage_id')::uuid from public.orders o
                           where o.route_lap_id = l.id and o.status = 'done' and o.verb = 'SAIL')
     and ve.payload ? 'wages';
$h$,
$h$  -- 0128: THE WAGES HER SALES PAID (cmd.do_sell's `wages`, out of their profit) — what left her
  -- purse, as sold / bought / taxes are. A sea-day only adds to what she owes.
  select coalesce(round(sum((o.result->>'wages')::numeric)), 0) into v_wages
    from public.orders o
   where o.route_lap_id = l.id and o.status = 'done' and o.verb = 'SELL';
$h$),

-- comment lines that would otherwise say the opposite
('public.running_cost_mult(uuid)', 1,
$h$  -- (wages in voyage.settle, cmd.do_provision, cmd.do_repair) and into npc_plan's wage estimate.
$h$,
$h$  -- (wages OWED in voyage.settle — paid from profit since 0128 —, cmd.do_provision, cmd.do_repair)
  -- and into npc_plan's wage estimate.
$h$),
('public.route_earnings(uuid)', 1,
$h$  -- own sums (sold, bought, supplies, repairs, wages OWED, net); the ledger is per company and is
$h$,
$h$  -- own sums (sold, bought, supplies, repairs, wages paid from profit (0128), net); the ledger is per company and is
$h$);

-- ── 5. THE RE-CUTS ─────────────────────────────────────────────────────────────────────────────
create or replace function pg_temp.recut_0128(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := replace(pg_get_functiondef(p_fn::regprocedure), E'\r', '');
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0128 where fn = p_fn order by n loop
    v_n := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
    if v_n <> 1 then
      raise exception '0128 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0128(fn) from defs_before_0128 order by fn;

-- ── 6. THE OWNER'S FULL-COST DECISION STANDS: merchants pay full running costs again ───────────
update public.world_config set value = to_jsonb(1) where key = 'npc_cost_mult';

-- the probes' reading and setting of what a fleet owes (pg_temp: dropped with the session).
create or replace function pg_temp.owed_0128(p_fleet uuid) returns bigint language sql
as $$ select coalesce((select w.owed from public.fleet_wages w where w.fleet_id = p_fleet), 0) $$;
create or replace function pg_temp.set_owed_0128(p_fleet uuid, p_owed bigint) returns void language sql
as $$ insert into public.fleet_wages (fleet_id, owed) values (p_fleet, p_owed)
      on conflict (fleet_id) do update set owed = excluded.owed $$;
-- a good no merchant route trades at the port, offered there with stock, under the house's cap.
create or replace function pg_temp.probe_good_0128(p_port uuid, p_player uuid, p_fleet uuid)
returns table (id uuid, code text) language sql
as $$
  select g1.id, g1.code
    from public.port_goods pg
    join public.goods g1 on g1.id = pg.good_id
    join public.ports pr on pr.id = pg.port_id
   where pg.port_id = p_port and pg.stock >= 40 and public.port_offers(p_port, g1.id)
     and not public.culture_refuses(pr.culture, g1.culture_mask)
     and world.daily_cap_remaining(p_player, p_port, g1.id) >= 60
     and public.fleet_free_hold(p_fleet) >= 10 * g1.bulk
     and not exists (select 1 from public.standing_route_lines l
                       join public.standing_route_stops s on s.route_id = l.route_id and s.ord = l.stop_ord
                      where l.good_id = g1.id and s.port_id = p_port)
   order by g1.bulk, g1.code limit 1
$$;
-- sell 10 of a good she was just given at a chosen profit (cost = the quote's total − p_profit).
create or replace function pg_temp.sell_at_0128(p_fleet uuid, p_port uuid, p_good uuid, p_code text, p_profit bigint)
returns jsonb language plpgsql
as $$
declare q record;
begin
  update public.ships set cargo = '{}'::jsonb, cargo_basis = '{}'::jsonb where fleet_id = p_fleet;
  select * into q from world.quote(p_port, p_good, 10, 'sell', null, p_fleet);
  perform public.fleet_load(p_fleet, p_code, 10, greatest(0, q.total - p_profit) / 10.0);
  return cmd.do_sell(p_fleet, jsonb_build_object('good', p_good, 'qty', 10));
end $$;

-- ── 7. SELF-ASSERT ─────────────────────────────────────────────────────────────────────────────
do $$
declare
  c_uid      constant uuid := '00000000-0128-4000-8000-000000000001';
  v_fn       text;
  v_def      text;
  v_back     text;
  h          record;
  v_n        int;
  v_list     text[];
  v_player   uuid;
  v_fleet    uuid;
  v_voy      uuid;
  v_voy2     uuid;
  v_lis      uuid;
  v_fnc      uuid;
  v_leg      jsonb;
  v_back_c   jsonb;
  v_good     uuid;
  v_code     text;
  v_owed     bigint;
  v_days     bigint;
  v_r        jsonb;
  v_r2       jsonb;
  v_rows     bigint;
  v_cap      bigint;
  v_m        uuid;
  v_mfleet   uuid;
  v_mgood    uuid;
  v_mcode    text;
  v_route    uuid;
  v_lap      public.standing_route_laps%rowtype;
  v_from     uuid;
  v_to       uuid;
  v_cheap    jsonb;
  v_dear     jsonb;
  v_legs     int := 0;
  v_notes    text := '';
begin
  -- (a) PARITY BY REVERSE SUBSTITUTION; ACLs unmoved; each hunk in its new body exactly once.
  for v_fn in select fn from defs_before_0128 loop
    v_def := replace(pg_get_functiondef(v_fn::regprocedure), E'\r', '');
    v_back := v_def;
    for h in select * from hunks_0128 where fn = v_fn order by n desc loop
      v_n := (length(v_back) - length(replace(v_back, h.new, ''))) / length(h.new);
      if v_n <> 1 then
        raise exception '0128 self-assert FAIL: hunk % of % is in the new body % time(s), not once', h.n, v_fn, v_n;
      end if;
      v_back := replace(v_back, h.new, h.old);
    end loop;
    if v_back <> (select def from defs_before_0128 where fn = v_fn) or v_def = v_back then
      raise exception '0128 self-assert FAIL: % is not its pre-image plus only 0128''s hunks', v_fn;
    end if;
    if coalesce((select p.proacl::text from pg_proc p where p.oid = v_fn::regprocedure), '')
       is distinct from (select acl from defs_before_0128 where fn = v_fn) then
      raise exception '0128 self-assert FAIL: the re-cut moved the ACL of %', v_fn;
    end if;
  end loop;

  -- (b) ONE AUTHORITY. Positive control: settle's pre-image charged WAGES through credit(). Now the
  --     ONLY live body that charges a house WAGES is pay_wages; the only writers of fleet_wages are
  --     owe_wages and pay_wages; settle owes through owe_wages, the sale pays through pay_wages, the
  --     mover and the planner read the one rule; nothing of it tells a merchant from a player.
  if strpos((select def from defs_before_0128 where fn = 'voyage.settle(uuid, timestamptz)'), $q$public.credit(f.player_id, 'WAGES'$q$) = 0 then
    raise exception '0128 self-assert FAIL: the scan''s positive control — settle''s pre-image did not charge WAGES';
  end if;
  select array_agg(n.nspname || '.' || p.proname order by n.nspname || '.' || p.proname) into v_list
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage')
     and p.prosrc ~ $q$(credit|pay_city)\([^;]*'WAGES'$q$;
  if v_list is distinct from array['public.pay_wages'] then
    raise exception '0128 self-assert FAIL: the live bodies that charge a house WAGES are %, not pay_wages alone', v_list;
  end if;
  select array_agg(n.nspname || '.' || p.proname order by n.nspname || '.' || p.proname) into v_list
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage')
     and p.prosrc ~* '(insert into|update|delete from)\s+public\.fleet_wages';
  if v_list is distinct from array['public.owe_wages', 'public.pay_wages'] then
    raise exception '0128 self-assert FAIL: the live writers of fleet_wages are %, not owe_wages / pay_wages', v_list;
  end if;
  if strpos(pg_get_functiondef('voyage.settle(uuid, timestamptz)'::regprocedure), 'public.owe_wages(p_fleet, v_wages)') = 0
     or strpos(pg_get_functiondef('voyage.settle(uuid, timestamptz)'::regprocedure), 'running_cost_mult(f.player_id)') = 0
     or strpos(pg_get_functiondef('cmd.do_sell(uuid, jsonb)'::regprocedure), 'public.pay_wages(p_fleet, f.port_id, v_profit - v_tax, null)') = 0
     or strpos(pg_get_functiondef('public.pay_wages(uuid, uuid, bigint, uuid)'::regprocedure), 'public.wages_from_profit(') = 0
     or strpos(pg_get_functiondef('public.npc_leg_lines(uuid, uuid, uuid, numeric, integer, numeric)'::regprocedure),
               'public.wages_from_profit(v_wages, v_profit)') = 0
     or exists (select 1 from pg_proc p where p.proname in ('pay_wages', 'owe_wages', 'wages_from_profit')
                   and p.pronamespace = 'public'::regnamespace and strpos(p.prosrc, 'is_npc') > 0) then
    raise exception '0128 self-assert FAIL: settle, the sale, the mover or the planner does not compose the one rule, or it reads is_npc';
  end if;
  if not exists (select 1 from pg_constraint c where c.conrelid = 'public.fleet_wages'::regclass and c.contype = 'f'
                   and c.confrelid = 'public.fleets'::regclass and c.confdeltype = 'c') then
    raise exception '0128 self-assert FAIL: fleet_wages does not go with its fleet (ON DELETE CASCADE)';
  end if;

  -- (c) THE WALL: the new functions and the table are server-only; no new entry point; no client write.
  if has_function_privilege('authenticated', 'public.pay_wages(uuid, uuid, bigint, uuid)', 'execute')
     or has_function_privilege('anon', 'public.pay_wages(uuid, uuid, bigint, uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.owe_wages(uuid, bigint)', 'execute')
     or has_function_privilege('anon', 'public.owe_wages(uuid, bigint)', 'execute')
     or has_function_privilege('authenticated', 'public.wages_from_profit(numeric, numeric)', 'execute')
     or has_function_privilege('anon', 'public.wages_from_profit(numeric, numeric)', 'execute')
     or has_table_privilege('authenticated', 'public.fleet_wages', 'select')
     or has_table_privilege('anon', 'public.fleet_wages', 'select') then
    raise exception '0128 self-assert FAIL: a wage function or the book is client-reachable';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> (select entry_points from before_0128)
     or exists (select 1 from public.client_rpc_entry_points() e
                 where e.fn is null or not has_function_privilege('authenticated', e.fn, 'execute'))
     or (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0128 self-assert FAIL: the registry, the grant wall or the read wall';
  end if;

  -- (d) THE RULE, on its grid; the knobs.
  if public.wages_from_profit(500, -10) <> 0 or public.wages_from_profit(500, 0) <> 0
     or public.wages_from_profit(500, null) <> 0 or public.wages_from_profit(500, 200) <> 200
     or public.wages_from_profit(500, 800) <> 500 or public.wages_from_profit(0, 800) <> 0
     or public.wages_from_profit(null, 800) <> 0 then
    raise exception '0128 self-assert FAIL: wages_from_profit is not min(owed, profit) above zero';
  end if;
  if public.wc_num('npc_cost_mult') <> 1 or (select knobs_found from before_0128) <> 0
     or public.wc_int('wages_owed_cap_days') <> 30 then
    raise exception '0128 self-assert FAIL: npc_cost_mult is not 1, or wages_owed_cap_days is not this file''s 30';
  end if;

  -- (e) THE PROBES, rolled back.
  select id into v_lis from public.ports where code = 'LIS';
  select id into v_fnc from public.ports where code = 'FNC';
  select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon),
                           jsonb_build_array(b.roadstead_lat, b.roadstead_lon))
    into v_leg from public.sea_reaches a, public.sea_reaches b
   where a.port_id = v_lis and b.port_id = v_fnc;
  v_back_c := jsonb_build_array(v_leg->1, v_leg->0);
  begin
    -- A PLAYER'S PASSAGE OWES, AND PAYS NOTHING AT SEA.
    v_player := public.new_house(c_uid, 'Casa do Soldo', 'PRT');
    select id into v_fleet from public.fleets where player_id = v_player;
    perform public.credit(v_player, 'PROBE_0128', 1000000);
    update public.ships set cargo = '{}'::jsonb, cargo_basis = '{}'::jsonb where fleet_id = v_fleet;
    select count(*) into v_rows from public.ledger where player_id = v_player and kind = 'WAGES';
    v_voy := voyage.depart(v_fleet, voyage.segments_from_course(v_leg), v_lis, v_fnc, now() - interval '60 days');
    perform voyage.settle(v_fleet, now() - interval '40 days');
    if (select status from public.voyages where id = v_voy) <> 'ARRIVED'
       or (select status from public.fleets where id = v_fleet) <> 'DOCKED' then
      raise exception '0128 self-assert FAIL: the probe passage did not arrive';
    end if;
    select coalesce(sum((ve.payload->>'wages')::bigint), 0), count(*) into v_days, v_n
      from public.voyage_events ve where ve.voyage_id = v_voy and ve.payload ? 'wages';
    v_owed := pg_temp.owed_0128(v_fleet);
    if v_days <= 0 or v_owed <> v_days
       or (select count(*) from public.ledger where player_id = v_player and kind = 'WAGES') <> v_rows
       or (select wages_paid from public.voyages where id = v_voy) <> 0 then
      raise exception '0128 self-assert FAIL: % sea-day(s) owing % d. left % owed, or paid a wage at sea', v_n, v_days, v_owed;
    end if;
    v_notes := v_notes || format('a %s-day passage owed %s d. and paid none at sea; ', v_n, v_owed);

    -- HOPPING DOES NOT DODGE THEM: she sells nothing at FNC, sails on to LIS, and the carried wages
    -- of BOTH passages are paid out of LIS's profit.
    v_voy2 := voyage.depart(v_fleet, voyage.segments_from_course(v_back_c), v_fnc, v_lis, now() - interval '30 days');
    perform voyage.settle(v_fleet, now() - interval '10 days');
    if (select status from public.voyages where id = v_voy2) <> 'ARRIVED' then
      raise exception '0128 self-assert FAIL: the hop did not arrive';
    end if;
    select v_owed + coalesce(sum((ve.payload->>'wages')::bigint), 0) into v_days
      from public.voyage_events ve where ve.voyage_id = v_voy2 and ve.payload ? 'wages';
    if pg_temp.owed_0128(v_fleet) <> v_days then
      raise exception '0128 self-assert FAIL: the hop did not carry the first passage''s % d. (owes %, expected %)',
        v_owed, pg_temp.owed_0128(v_fleet), v_days;
    end if;
    select g.id, g.code into v_good, v_code from pg_temp.probe_good_0128(v_lis, v_player, v_fleet) g;
    if v_good is null then
      raise exception '0128 self-assert FAIL: no good at LIS to probe a sale with';
    end if;
    perform public.treasury_post(v_lis, 'SEED', 100000000);   -- lit: a purse that can buy (dark: nothing)
    perform public.treasury_post(v_fnc, 'SEED', 100000000);
    v_r := pg_temp.sell_at_0128(v_fleet, v_lis, v_good, v_code, 100000);
    if (v_r->>'profit')::bigint - (v_r->>'tax')::bigint <= v_days or (v_r->>'wages')::bigint <> v_days
       or pg_temp.owed_0128(v_fleet) <> 0
       or (v_r->>'net')::bigint <> (v_r->>'total')::bigint - (v_r->>'tax')::bigint - (v_r->>'wages')::bigint
       or not exists (select 1 from public.ledger where player_id = v_player and kind = 'WAGES' and ducats_delta = -v_days) then
      raise exception '0128 self-assert FAIL: the hop''s carried % d. were not paid out of LIS''s profit: %', v_days, v_r;
    end if;
    if public.city_treasury_on()
       and not exists (select 1 from public.treasury_flows tf where tf.port_id = v_lis and tf.kind = 'WAGES'
                        and tf.ducats = v_days) then
      raise exception '0128 self-assert FAIL: lit, the wages were not paid into the city of the sale';
    end if;
    v_notes := v_notes || format('a hop carried both passages'' %s d. and LIS''s profit paid them; ', v_days);

    -- A LOSS AND A PROFIT AT ONE PORT PAY AT MOST THEIR NET. Owed 1000 at a fresh visit (a sea-day
    -- starts one): a sale at a loss of 50 pays nothing; a sale at a profit of 80 then pays its
    -- after-tax profit less the 50 lost.
    perform voyage.depart(v_fleet, voyage.segments_from_course(v_leg), v_lis, v_fnc, now() - interval '9 days');
    perform voyage.settle(v_fleet, now());
    select g.id, g.code into v_good, v_code from pg_temp.probe_good_0128(v_fnc, v_player, v_fleet) g;
    if v_good is null then
      raise exception '0128 self-assert FAIL: no good at FNC to probe a sale with';
    end if;
    perform pg_temp.set_owed_0128(v_fleet, 1000);
    select count(*) into v_rows from public.ledger where player_id = v_player and kind = 'WAGES';
    v_r := pg_temp.sell_at_0128(v_fleet, v_fnc, v_good, v_code, -50);
    if (v_r->>'profit')::bigint >= 0 or (v_r->>'wages')::bigint <> 0 or pg_temp.owed_0128(v_fleet) <> 1000
       or (select count(*) from public.ledger where player_id = v_player and kind = 'WAGES') <> v_rows then
      raise exception '0128 self-assert FAIL: a sale at a loss paid wages: %', v_r;
    end if;
    v_r2 := pg_temp.sell_at_0128(v_fleet, v_fnc, v_good, v_code, 80);
    if (v_r2->>'profit')::bigint - (v_r2->>'tax')::bigint + (v_r->>'profit')::bigint <= 0 then
      raise exception '0128 self-assert FAIL: the probe pair does not net a profit: % then %', v_r, v_r2;
    end if;
    if (v_r2->>'wages')::bigint <> (v_r2->>'profit')::bigint - (v_r2->>'tax')::bigint + (v_r->>'profit')::bigint
       or pg_temp.owed_0128(v_fleet) <> 1000 - (v_r2->>'wages')::bigint then
      raise exception '0128 self-assert FAIL: a loss (%) and a profit at one port paid % in wages, not their net', v_r->>'profit', v_r2;
    end if;
    -- and a cost the hold does not know pays nothing.
    update public.ships set cargo = '{}'::jsonb, cargo_basis = '{}'::jsonb where fleet_id = v_fleet;
    perform public.fleet_load(v_fleet, v_code, 10, 1);
    update public.ships set cargo_basis = cargo_basis || jsonb_build_object(v_code, null) where fleet_id = v_fleet;
    v_r := cmd.do_sell(v_fleet, jsonb_build_object('good', v_good, 'qty', 10));
    if v_r->>'profit' is not null or (v_r->>'wages')::bigint <> 0 then
      raise exception '0128 self-assert FAIL: a sale of unknown cost paid wages: %', v_r;
    end if;
    v_notes := v_notes || format('a loss of 50 then a profit of %s at one port paid %s; ',
                                 (v_r2->>'profit')::bigint - (v_r2->>'tax')::bigint, v_r2->>'wages');

    -- THE CAP: past 30 days of the day's wage, the rest is forgiven.
    perform pg_temp.set_owed_0128(v_fleet, 0);
    for v_n in 1 .. 45 loop
      perform public.owe_wages(v_fleet, 10);
    end loop;
    v_cap := pg_temp.owed_0128(v_fleet);
    perform public.owe_wages(v_fleet, 10);
    if v_cap <> 300 or pg_temp.owed_0128(v_fleet) <> 300 then
      raise exception '0128 self-assert FAIL: 45 days of 10 d. carried %, not the 30-day cap of 300', v_cap;
    end if;

    -- A MERCHANT IS PAID BY THE SAME LINES. The probe founds ITS OWN merchant (npc_found, as 0126 and
    -- 0127 do), docks her at LIS, and a profitable sale with 5 owed pays 5.
    v_m := public.npc_found(jsonb_build_object(
      'company', 'Casa do Soldo Justo', 'alt_company', 'Casa da Paga', 'nation', 'PRT', 'ink', 'prt',
      'master', 'Capitao Pagador',
      'blurb', 'A probe company founded so its crew can be seen paid out of profit.',
      'capital', 40000, 'patience', 0.20, 'wares', '[]'::jsonb, 'roster_ord', 9128,
      'skills', '{}'::jsonb,
      'fleets', jsonb_build_array(jsonb_build_object(
        'name', 'Pagadora', 'roster_ord', 9128, 'days', 12,
        'ships', jsonb_build_array(jsonb_build_object('class', 'nau', 'name', 'Pagadora')),
        'officers', '[]'::jsonb,
        'stops', jsonb_build_array(jsonb_build_object('port', 'LIS', 'course', v_leg),
                                   jsonb_build_object('port', 'FNC', 'course', v_back_c)),
        'alt_stops', jsonb_build_array(jsonb_build_object('port', 'LIS', 'course', v_leg),
                                       jsonb_build_object('port', 'FNC', 'course', v_back_c))))));
    select nf.fleet_id, nf.route_id into v_mfleet, v_route from public.npc_fleets nf
     where nf.player_id = v_m order by nf.roster_ord limit 1;
    if v_mfleet is null or v_route is null then
      raise exception '0128 self-assert FAIL: the probe merchant was founded without a fleet and a route';
    end if;
    update public.voyages set status = 'ARRIVED' where fleet_id = v_mfleet and status = 'SAILING';
    update public.fleets set status = 'DOCKED', port_id = v_lis, lat = null, lon = null where id = v_mfleet;
    select g.id, g.code into v_mgood, v_mcode from pg_temp.probe_good_0128(v_lis, v_m, v_mfleet) g;
    if v_mgood is null then
      raise exception '0128 self-assert FAIL: no good at LIS for the probe merchant to sell';
    end if;
    perform pg_temp.set_owed_0128(v_mfleet, 5);
    select count(*) into v_rows from public.ledger where player_id = v_m and kind = 'WAGES';
    v_r := pg_temp.sell_at_0128(v_mfleet, v_lis, v_mgood, v_mcode, 1000);
    if (v_r->>'wages')::bigint <> 5 or pg_temp.owed_0128(v_mfleet) <> 0
       or (select count(*) from public.ledger where player_id = v_m and kind = 'WAGES' and ducats_delta = -5) <> 1
       or (select count(*) from public.ledger where player_id = v_m and kind = 'WAGES') <> v_rows + 1 then
      raise exception '0128 self-assert FAIL: a merchant''s profitable sale did not pay her 5 owed through the same lines: %', v_r;
    end if;

    -- THE LAP BOOKS WHAT ITS SALES PAID, not what its sea-days owed (a SAIL whose voyage owed is in it).
    update public.ships set cargo = '{}'::jsonb, cargo_basis = '{}'::jsonb where fleet_id = v_mfleet;
    insert into public.standing_route_laps (route_id, lap_no, started_at)
    values (v_route, 900128, now()) returning * into v_lap;
    update public.standing_routes set lap_id = v_lap.id, lap_no = 900128 where id = v_route;
    insert into public.orders (fleet_id, player_id, seq, raw_text, verb, args, status, result, route_lap_id, executed_at) values
      (v_mfleet, v_m, 9001281, 'SELL', 'SELL', '{}', 'done', jsonb_build_object('qty', 10, 'total', 500, 'tax', 20, 'wages', 30), v_lap.id, now()),
      (v_mfleet, v_m, 9001282, 'SELL', 'SELL', '{}', 'done', jsonb_build_object('qty', 5, 'total', 100, 'tax', 0, 'wages', 0), v_lap.id, now()),
      (v_mfleet, v_m, 9001283, 'SAIL', 'SAIL', '{}', 'done', jsonb_build_object('voyage_id', v_voy), v_lap.id, now());
    perform cmd.standing_route_close_lap(v_route, now());
    select * into v_lap from public.standing_route_laps where id = v_lap.id;
    if v_lap.wages <> 30 or v_lap.taxes <> 20 or v_lap.sold <> 600 then
      raise exception '0128 self-assert FAIL: the lap booked wages % (taxes %, sold %), not the 30 its sales paid', v_lap.wages, v_lap.taxes, v_lap.sold;
    end if;

    -- THE PLANNER DOES NOT REFUSE A PARCEL THAT PAYS: a leg's lines are the same with no crew and
    -- with a ruinous wage bill; with the bill, the leg leaves her nothing — never less.
    for v_route, v_from, v_to in
      select s0.route_id, s0.port_id, s1.port_id
        from public.npc_fleets nf
        join public.standing_route_stops s0 on s0.route_id = nf.route_id and s0.ord = 0
        join public.standing_route_stops s1 on s1.route_id = nf.route_id and s1.ord = 1
       order by nf.player_id = v_m desc, nf.roster_ord, nf.fleet_id limit 12 loop   -- reads only: the planner locks nothing
      v_cheap := public.npc_leg_lines(v_route, v_from, v_to, 400, 0, 6);
      continue when not coalesce((v_cheap->>'any')::boolean, false);
      v_dear := public.npc_leg_lines(v_route, v_from, v_to, 400, 1000000, 6);
      if v_dear->'lines' <> v_cheap->'lines' or v_dear->'any' <> v_cheap->'any'
         or (v_cheap->>'profit')::numeric <= 0 or (v_dear->>'profit')::numeric <> 0 then
        raise exception '0128 self-assert FAIL: the planner''s leg depends on its wage bill (no crew %, ruinous %)', v_cheap, v_dear;
      end if;
      v_legs := v_legs + 1;
      exit when v_legs >= 2;
    end loop;
    if v_legs = 0 then
      raise exception '0128 self-assert FAIL: no merchant leg kept a parcel to probe the planner with';
    end if;

    raise exception 'ROLLBACK_0128';
  exception when others then
    if sqlerrm <> 'ROLLBACK_0128' then raise; end if;
  end;
  if exists (select 1 from public.players where auth_uid = c_uid)
     or exists (select 1 from public.standing_route_laps where lap_no = 900128)
     or exists (select 1 from public.npc_houses where roster_ord = 9128)
     or exists (select 1 from public.fleet_wages) then
    raise exception '0128 self-assert FAIL: the probe world was not rolled back';
  end if;

  raise notice '0128 self-assert ok: WAGES ARE PAID FROM PROFIT. voyage.settle, cmd.do_sell, npc_leg_lines, standing_route_close_lap (and two comment lines) reverse to their pre-images hunk by hunk, ACLs unmoved; public.pay_wages is the ONLY live body that charges a house WAGES (positive control: settle''s pre-image did); fleet_wages is written by owe_wages and pay_wages alone and goes with its fleet; settle owes, the sale pays, the mover and the planner read the one rule public.wages_from_profit; nothing reads is_npc; server-only, no new entry point, no client write. Rule grid: loss / break-even / unknown pay 0, a profit pays min(owed, profit). Probes: %an unknown cost paid 0; 45 days of 10 d. carried the 30-day cap of 300; a merchant owing 5 paid 5 through the same lines; a lap booked the 30 its sales paid; % planner leg(s) kept the same lines with no crew and a ruinous wage bill, leaving 0, never less. npc_cost_mult % -> 1. Rolled back.',
    v_notes, v_legs, (select npc_cost_mult from before_0128);
end $$;
