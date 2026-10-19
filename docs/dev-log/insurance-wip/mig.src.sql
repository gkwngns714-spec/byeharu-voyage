-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0211 — A CARGO CAN BE INSURED  (port insurance for a voyage's cargo; merchants insure in place of the
--        free refound; a plundered hold loses what the day's sentence always said it lost)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- The owner, 2026-10-19 (the idea): port underwriters paid from the city purses; a price set by the voyage's
-- danger; a payout on a cargo loss less a 10 % deductible; merchant houses insure in place of the free refound.
-- Built by default (docs/WORK_QUEUE.md "Proposed, awaiting the owner: Insurance"; the owner may reverse any
-- choice below — each is listed in docs/dev-log/2026-10-19-insurance.md "Decided by default").
--
-- ── WHAT PROD SHOWED (read-only, 2026-10-19, head 0208) ─────────────────────────────────────────
-- * A RAID THAT "PLUNDERS" TAKES NOTHING. Since 0007 the PIRATES arm writes `cargo = case when STRIPPED then
--   '{}' else cargo end`: PLUNDERED leaves the hold as it was, though DESIGN B.6 says "−25…−50 % cargo" and the
--   day's own sentence says "They came aboard and took what they could carry." With the fight lit (0204) a
--   fought raid never ends STRIPPED (0202), so on prod NO cargo has been lost to a raid since 01:20 UTC: 78
--   PLUNDERED of 348 raids, 0 STRIPPED. Insurance against a loss that cannot happen is a price for nothing, so
--   this file makes the sentence true (§3).
-- * THE REFOUND. public.npc_tend_houses tops a merchant whose worth fell under 20 % of her capital back to her
--   capital, from her home city's surplus: 1,372 refounds in the 7 days to 07:00 UTC (186 in one 6-hour
--   window), several million coin a day from city purses into merchant purses, none of it tied to a loss.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- (1) THE RISK A VOYAGE RUNS — voyage.risk_quote(voyage) (NEW). The interface docs/PIRATES_AND_HAVENS.md §2.5 /
--     §7.2 names for insurance (Z7): the expected share of a cargo's value a voyage loses. Today it composes the
--     roll's own authorities and computes nothing the roll does not: for each voyage-day, the hazard chance
--     voyage.hazard_roll reports for that day (`p_hazard`: the sea's hazard_base × the leg's hazard_mult, capped
--     — the roll's OWN column; its outcome columns are not read, so a quote never knows what will happen), times
--     the PIRATES share of that day's sea (voyage.sea_mix, the one reading of what a water breeds), times the
--     share of a cargo one raid carries off (knob insurance_raid_loss: the fight's measured PLUNDERED share on
--     prod since it was lit, 78 / 348 = 0.224, × the mean plunder 0.375 = 0.084). loss = 1 − Π(1 − that).
--     Z1 (sea_danger frozen into the segments) re-cuts this ONE body; insurance does not move.
-- (2) THE PRICE — public.insurance_price(value, loss) (NEW): ⌈value × loss × (1 − insurance_keep_pct) ×
--     (1 + insurance_margin)⌉, at least 1 for a cargo worth anything. The expected payout plus a margin:
--     the city keeps insurance_margin of what it is paid, on average.
-- (3) A PLUNDERED HOLD LOSES ITS CARGO — voyage.raid_takes(voyage, day, fleet, outcome) (NEW), read by the
--     PIRATES arm of voyage.settle in place of its STRIPPED-only line: PLUNDERED takes plunder_share_min +
--     plunder_share_span × voyage.rng(voyage, day, 'plunder') (25–50 %, DESIGN B.6) of every good on board,
--     in whole units; STRIPPED takes all of it. Removed through public.fleet_unload (the one unload: the cost
--     basis leaves with the last unit). A pure function of the voyage, the day and what was on board, so a
--     voyage settled late takes exactly what it would have taken on time (proof 01). The day's payload names
--     what went: `cargo_lost` {good: units}.
-- (4) INSURING A VOYAGE — public.insure_voyage(voyage, wanted) (NEW), called by cmd.do_sail right after the
--     voyage departs (one hunk), so the price is set on the course actually sailed. A player asks with
--     `SAIL <port> INSURED` (cmd.parse, one hunk; cmd.verb_schema serves the word, one hunk). A merchant's
--     cargo is always insured (decided by default). The insurer is the HARBOUR she sails from; it is paid
--     the price through public.pay_city (ledger INSURANCE, treasury INSURANCE) and the policy is written to
--     public.insured_voyages with the cargo and its cost basis at that moment (public.fleet_stock_at_cost,
--     public.fleet_cargo_basis_map — the one cargo-basis authority). Every SAIL's result carries `insurance`:
--     {insured, value, price, …}, so cmd.preview of a SAIL quotes the price without charging it.
--     Refusals: E_NO_INSURER (asked at sea, where no port can write it), E_INSUFFICIENT_FUNDS (the price is
--     more than the purse: "Insuring the cargo costs 120 🪙 and you have 40 🪙."). An empty hold insures
--     nothing and is charged nothing. A merchant who cannot pay sails uninsured.
-- (5) THE PAYOUT — public.insurance_claim(voyage, day, lost, cause) (NEW), read by the PIRATES arm after
--     raid_takes: the units lost that the policy covers (never more than were insured) at the basis written
--     on the policy, less insurance_keep_pct (10 %), paid by the insuring city from its SURPLUS (public.city_surplus,
--     the figure every spender reads) through public.city_pays (ledger and treasury INSURANCE_PAID). What the
--     purse cannot cover is recorded on the policy (`short`) and in the event (INSURANCE_PAID {owed, paid, short}).
--     With the purses dark, the city's part writes nothing and the claim is paid in full (as the refound was).
-- (6) THE REFOUND IS RETIRED. public.npc_tend_houses loses its refound pass (hunks); its two knobs
--     (npc_purse_floor_pct, npc_refound_cooldown_game_days) and public.npc_worth (read by nothing else) go;
--     public.npc_tend_sum stops counting 'refounded' / 'refound_unfunded'. A merchant that is ruined anyway
--     sails on with what she has — the path an unfunded refound already took (0115/0122: never parked) — and
--     her insurance is what stands behind her cargo. The merchant card (world.npc_fleet_card) serves
--     `insurance` {claims, paid, short} in place of `refounded` / `refounded_at`.
-- (7) THE BOOKS ADD UP. standing_route_laps gains `insurance` (what her SAILs paid to insure, less what the
--     insurance paid back on those voyages) and cmd.standing_route_close_lap takes it from the lap's net
--     (hunks). world.books names the two ledger kinds: Insurance · Insurance paid (one hunk).
-- (8) THE READ — world.insurance() (NEW, registered; authenticated only): the caller's insured voyages under
--     way, and the last ones the insurance paid on.
--
-- ── DECIDED BY DEFAULT (the owner may reverse each) ─────────────────────────────────────────────
-- * Cargo only; one voyage per policy (a SAIL). A turn at sea (DIVERT) ends the voyage and its cover.
-- * The insurer is the port the ship sails FROM; nothing is insured from open water.
-- * The price does not read the fleet's guns: the loss share is the fight's measured average over the
--   fleets raided. A per-escort price is Z7's (fight_outcome_shares_by_band) when Z1–Z3 land.
-- * Merchants insure every laden voyage; a player insures by asking (SAIL … INSURED).
-- * PLUNDERED takes 25–50 % of every good (DESIGN B.6). Storms, shoals and wrecks take no cargo in this
--   game today, so they are not claims; a later loss writer calls public.insurance_claim.
-- * A ruined merchant is not refounded and not rescued: she sails on with what she has.
-- * Standing routes of players are not insured in v1.
--
-- ── LOCKS AND TIME ──────────────────────────────────────────────────────────────────────────────
-- CREATE TABLE ×1 (server-only), ALTER TABLE standing_route_laps ADD COLUMN (a default, metadata only),
-- world_config INSERT ×5 / DELETE ×2, CREATE FUNCTION ×7, DROP FUNCTION ×1, CREATE OR REPLACE FUNCTION ×10 by
-- hunks sliced from the LIVE bodies (prod head 0208, LF-normalised), each asserted to occur exactly once and to
-- reverse to its pre-image, ACL / volatility / definer / config unchanged. SUPERSEDES: cmd.parse (0047…),
-- cmd.verb_schema, cmd.do_sail (0076), voyage.settle (0189), public.npc_tend_houses (0203),
-- public.npc_tend_sum (0181), cmd.standing_route_close_lap (0128), world.books (0177),
-- world.npc_fleet_card (0145), public.client_rpc_entry_points (0185). The probes run on their own company's rows
-- (probe ids carry 0211) inside sub-transactions rolled back whole; nothing is deleted from events or the
-- ledger. No top-level LOCK / SET LOCAL / BEGIN / SET ROLE. Timings are notices only.
-- ROLLBACK (a forward migration): reverse the hunks (old text in hunks_0211), restore the two knobs
-- (0.2 / 30) and public.npc_worth (0203's body); the new functions and the table are then unread.
-- VERSION: 0211 (prod head 0208; 0209 / 0210 in flight). It RENUMBERS to the prod head + 1 at push.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regclass('public.insured_voyages') is not null then
    raise exception '0211 refuses: public.insured_voyages already exists — this has been applied once';
  end if;
  if to_regprocedure('voyage.fight_resolve(uuid, integer, numeric, numeric, jsonb)') is null
     or to_regprocedure('public.npc_worth(uuid)') is null
     or not exists (select 1 from public.world_config where key = 'goods_price_level') then
    raise exception '0211 refuses: 0189 (the fight), 0203 (npc_worth) or 0208 is not in this world';
  end if;
end $guard$;

-- ── 0. HELPERS (pg_temp, gone at commit) ───────────────────────────────────────────────────────
create or replace function pg_temp.occurs_0211(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 1. THE PRE-IMAGES ──────────────────────────────────────────────────────────────────────────
create temp table defs_before_0211 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('cmd.parse(uuid, uuid, text)'), ('cmd.verb_schema()'), ('cmd.do_sail(uuid, jsonb)'),
               ('voyage.settle(uuid, timestamp with time zone)'), ('public.npc_tend_houses(timestamp with time zone)'),
               ('public.npc_tend_sum(jsonb, jsonb)'), ('cmd.standing_route_close_lap(uuid, timestamp with time zone)'),
               ('world.books(integer)'), ('world.npc_fleet_card(uuid)'), ('public.client_rpc_entry_points()')) f(fn);

-- the pre-images kept callable for the probes' old-against-new comparisons (renamed into pg_temp)
do $$
declare
  r record;
begin
  for r in select * from (values
      ('cmd.do_sail(uuid, jsonb)', 'CREATE OR REPLACE FUNCTION cmd.do_sail(', 'CREATE OR REPLACE FUNCTION pg_temp.do_sail_b0211('),
      ('voyage.settle(uuid, timestamp with time zone)', 'CREATE OR REPLACE FUNCTION voyage.settle(', 'CREATE OR REPLACE FUNCTION pg_temp.settle_b0211('),
      ('cmd.parse(uuid, uuid, text)', 'CREATE OR REPLACE FUNCTION cmd.parse(', 'CREATE OR REPLACE FUNCTION pg_temp.parse_b0211('),
      ('public.npc_tend_houses(timestamp with time zone)', 'CREATE OR REPLACE FUNCTION public.npc_tend_houses(', 'CREATE OR REPLACE FUNCTION pg_temp.tend_houses_b0211(')
    ) x(fn, a, b) loop
    if pg_temp.occurs_0211((select def from defs_before_0211 where fn = r.fn), r.a) <> 1 then
      raise exception '0211 self-assert FAIL: the head of % is not where it was expected', r.fn;
    end if;
    execute replace((select def from defs_before_0211 where fn = r.fn), r.a, r.b);
  end loop;
end $$;

-- ── 2. THE KNOBS ────────────────────────────────────────────────────────────────────────────────
insert into public.world_config (key, value, description) values
  ('insurance_raid_loss', to_jsonb(0.084),
   '0211: the share of a cargo''s value one raid (a PIRATES day) carries off, on average — the fight''s measured '
   'PLUNDERED share on prod since it was lit (78 of 348 raids, 01:20-07:40 UTC 2026-10-19) × the mean plunder '
   '(plunder_share_min + plunder_share_span / 2 = 0.375). Read by voyage.risk_quote only. Re-measure after Z3.'),
  ('insurance_keep_pct', to_jsonb(0.10),
   '0211 (the owner, 2026-10-19: "a 10 % deductible"): the share of a loss the owner keeps; the insurance pays '
   'the rest. Frozen onto each policy when it is written.'),
  ('insurance_margin', to_jsonb(@@MARGIN@@),
   '0211: what an insurer asks over the expected payout — the price is value × risk × (1 − keep) × (1 + this). '
   'Tuned so the insuring cities roughly break even with a small margin (docs/dev-log/2026-10-19-insurance.md). '
   'NOT the owner''s — confirm.'),
  ('plunder_share_min', to_jsonb(0.25),
   '0211 (DESIGN B.6: PLUNDERED "−25…−50 % cargo"): the least share of every good a plundering raid carries off.'),
  ('plunder_share_span', to_jsonb(0.25),
   '0211: plunder_share_min + this × the day''s own roll (voyage.rng stream ''plunder'') is the share taken.');

-- ── 3. THE TABLE ────────────────────────────────────────────────────────────────────────────────
create table public.insured_voyages (
  voyage_id  uuid primary key references public.voyages(id) on delete cascade,
  fleet_id   uuid not null references public.fleets(id) on delete cascade,
  player_id  uuid not null references public.players(id) on delete cascade,
  port_id    uuid not null references public.ports(id),          -- the insurer: the harbour she sailed from
  cargo      jsonb not null,                                     -- {good code: units} insured
  basis      jsonb not null,                                     -- {good code: cost a unit} when written
  value      bigint not null check (value > 0),
  risk       numeric not null check (risk >= 0 and risk <= 1),  -- voyage.risk_quote's loss share
  price      bigint not null check (price >= 0),
  keep_pct   numeric not null check (keep_pct >= 0 and keep_pct < 1),
  lost       jsonb not null default '{}'::jsonb,                 -- {good code: units} claimed so far
  lost_value bigint not null default 0 check (lost_value >= 0),
  paid       bigint not null default 0 check (paid >= 0),
  short      bigint not null default 0 check (short >= 0),
  claims     int not null default 0 check (claims >= 0),
  written_at timestamptz not null default now()
);
create index insured_voyages_player_0211 on public.insured_voyages (player_id, written_at desc);
create index insured_voyages_fleet_0211 on public.insured_voyages (fleet_id, written_at desc);
alter table public.insured_voyages enable row level security;
revoke all on table public.insured_voyages from public, anon, authenticated;
comment on table public.insured_voyages is
  '0211: one row per insured voyage — what was insured, at what cost basis, for what price, by which city, and '
  'what it has paid. Written by public.insure_voyage and public.insurance_claim only; read by world.insurance, '
  'world.npc_fleet_card (no: events) and cmd.standing_route_close_lap.';

alter table public.standing_route_laps add column insurance bigint not null default 0;
comment on column public.standing_route_laps.insurance is
  '0211: what her SAILs paid to insure the cargo this lap, less what the insurance paid back on those voyages.';

-- ── 4. THE NEW FUNCTIONS ────────────────────────────────────────────────────────────────────────
create or replace function voyage.risk_quote(p_voyage uuid)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0211: THE RISK A VOYAGE RUNS — the expected share of its cargo's value lost to raids (docs/PIRATES_AND_HAVENS.md
  -- §2.5, §7.2: the one interface insurance prices from; Z1 re-cuts THIS body to read the frozen danger). Composes
  -- the roll's own authorities: voyage.hazard_roll's p_hazard for each day (its outcome is never read), the day's
  -- sea's PIRATES share (voyage.sea_mix), and insurance_raid_loss (what one raid carries off, measured).
  with d as (
    select (voyage.leg_at_day(p_voyage, g.d)->>'sea_id')::uuid as sea, h.p_hazard as p
      from generate_series(1, voyage.total_days(p_voyage)) g(d)
     cross join lateral voyage.hazard_roll(p_voyage, g.d) h
  ), s as (
    select x.sea, coalesce((select m.share from voyage.sea_mix(x.sea) m where m.kind_code = 'PIRATES'), 0) as share
      from (select distinct d.sea from d) x
  )
  select round(1 - exp(coalesce(sum(ln(greatest(1e-9, 1 - d.p * s.share * public.wc_num('insurance_raid_loss')))), 0)), 6)
    from d join s on s.sea = d.sea
$$;

create or replace function public.insurance_price(p_value bigint, p_risk numeric)
returns bigint
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0211: THE PRICE of insuring a cargo worth p_value on a voyage that loses p_risk of it on average: the
  -- expected payout (the loss less what the owner keeps) and the insurer's margin. The one place it is reckoned.
  select case when coalesce(p_value, 0) <= 0 then 0::bigint
              else greatest(1, ceil(p_value * coalesce(p_risk, 0) * (1 - public.wc_num('insurance_keep_pct'))
                                    * (1 + public.wc_num('insurance_margin'))))::bigint end
$$;

create or replace function voyage.raid_takes(p_voyage uuid, p_day integer, p_fleet uuid, p_outcome text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0211: WHAT THE RAIDERS CARRY OFF (DESIGN B.6). PLUNDERED: a share of every good on board, in whole units —
-- plunder_share_min + plunder_share_span × the day's own roll (stream 'plunder'), so a voyage settled late takes
-- what it would have taken on time. STRIPPED: all of it. Out through public.fleet_unload, the one unload. Returns
-- {good code: units taken}. Read by voyage.settle's PIRATES arm alone.
declare
  v_share numeric;
  r       record;
  v_take  numeric;
  v_out   jsonb := '{}'::jsonb;
begin
  if p_outcome = 'STRIPPED' then
    v_share := 1;
  elsif p_outcome = 'PLUNDERED' then
    v_share := public.wc_num('plunder_share_min') + public.wc_num('plunder_share_span') * voyage.rng(p_voyage, p_day, 'plunder');
  else
    return v_out;
  end if;
  for r in select e.key as code, sum((e.value)::text::numeric) as qty
             from public.ships s cross join lateral jsonb_each(s.cargo) e
            where s.fleet_id = p_fleet and jsonb_typeof(e.value) = 'number'
            group by e.key having sum((e.value)::text::numeric) > 0
            order by e.key loop
    v_take := case when v_share >= 1 then r.qty else floor(r.qty * v_share) end;
    if v_take > 0 then
      v_take := public.fleet_unload(p_fleet, r.code, v_take);
      v_out := v_out || jsonb_build_object(r.code, v_take);
    end if;
  end loop;
  return v_out;
end $$;

create or replace function public.insure_voyage(p_voyage uuid, p_wanted boolean)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0211: INSURING A VOYAGE'S CARGO, at the moment it departs (cmd.do_sail, right after voyage.depart). The price is
-- public.insurance_price over voyage.risk_quote of the course actually sailed; the insurer is the harbour she sails
-- from, paid through public.pay_city. A merchant's laden voyage is always insured (when her purse can pay); a
-- player's only when asked (p_wanted: SAIL … INSURED). Unasked, it QUOTES — so cmd.preview of a SAIL shows the price.
declare
  v       public.voyages%rowtype;
  pl      public.players%rowtype;
  po      public.ports%rowtype;
  v_fleet text;
  v_value bigint;
  v_risk  numeric;
  v_price bigint;
  v_basis jsonb;
  v_cargo jsonb;
  v_keep  numeric := public.wc_num('insurance_keep_pct');
  v_ev    uuid;
begin
  select * into v from public.voyages where id = p_voyage;
  select * into pl from public.players where id = v.player_id;
  select * into po from public.ports where id = v.origin_port_id;
  select f.name into v_fleet from public.fleets f where f.id = v.fleet_id;
  if po.id is null or po.kind <> 'HARBOUR' then
    if p_wanted and not pl.is_npc then
      perform cmd.refuse('E_NO_INSURER',
        format('%s is not in a port. Cargo is insured in port, before the ship sails.', v_fleet), null);
    end if;
    return jsonb_build_object('insured', false, 'why', 'at_sea');
  end if;
  v_value := public.fleet_stock_at_cost(v.fleet_id);
  if v_value <= 0 then
    return jsonb_build_object('insured', false, 'why', 'no_cargo', 'value', 0, 'price', 0);
  end if;
  v_risk  := voyage.risk_quote(p_voyage);
  v_price := public.insurance_price(v_value, v_risk);
  if not (p_wanted or pl.is_npc) then
    return jsonb_build_object('insured', false, 'why', 'not_asked', 'value', v_value, 'price', v_price,
                              'risk', v_risk, 'keep_pct', v_keep, 'port', po.code);
  end if;
  if pl.ducats < v_price then
    if pl.is_npc then
      return jsonb_build_object('insured', false, 'why', 'purse', 'value', v_value, 'price', v_price, 'risk', v_risk);
    end if;
    perform cmd.refuse('E_INSUFFICIENT_FUNDS',
      format('Insuring the cargo costs %s 🪙 and you have %s 🪙.', v_price, pl.ducats),
      cmd.figures(pl.ducats, v_price, 'ducats'));
  end if;
  v_basis := public.fleet_cargo_basis_map(v.fleet_id);
  select coalesce(jsonb_object_agg(k.code, public.fleet_cargo_qty(v.fleet_id, k.code)), '{}'::jsonb)
    into v_cargo from (select jsonb_object_keys(v_basis) as code) k;
  v_ev := public.emit_event(pl.id, 'INSURED', jsonb_build_object(
    'fleet', v_fleet, 'voyage_id', p_voyage, 'port', po.code,
    'to', (select p2.code from public.ports p2 where p2.id = v.dest_port_id),
    'value', v_value, 'price', v_price, 'keep_pct', v_keep));
  perform public.pay_city(pl.id, po.id, 'INSURANCE', v_price, v_ev);
  insert into public.insured_voyages (voyage_id, fleet_id, player_id, port_id, cargo, basis, value, risk, price, keep_pct)
  values (p_voyage, v.fleet_id, pl.id, po.id, v_cargo, v_basis, v_value, v_risk, v_price, v_keep);
  return jsonb_build_object('insured', true, 'value', v_value, 'price', v_price, 'risk', v_risk,
                            'keep_pct', v_keep, 'port', po.code);
end $$;

create or replace function public.insurance_claim(p_voyage uuid, p_day integer, p_lost jsonb, p_cause text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0211: THE PAYOUT. What was lost (p_lost {good code: units}) that the voyage's policy covers — never more of a good
-- than was insured, less what was already claimed — at the basis written on the policy, less its keep_pct, paid by
-- the insuring city from its surplus (public.city_surplus, the figure every spender reads) through public.city_pays.
-- What the purse cannot cover is recorded as `short` on the policy and in the event. Purses dark: paid in full.
-- Read by voyage.settle's PIRATES arm (after voyage.raid_takes). Returns null when nothing was insured.
declare
  c       public.insured_voyages%rowtype;
  e       record;
  v_take  numeric;
  v_lost  numeric := 0;
  v_owed  bigint;
  v_paid  bigint;
  v_ev    uuid;
begin
  if p_lost is null or p_lost = '{}'::jsonb then return null; end if;
  select * into c from public.insured_voyages where voyage_id = p_voyage for update;
  if c.voyage_id is null then return null; end if;
  for e in select x.key, (x.value)::text::numeric as q from jsonb_each(p_lost) x order by x.key loop
    v_take := least(e.q, greatest(0, coalesce((c.cargo->>e.key)::numeric, 0) - coalesce((c.lost->>e.key)::numeric, 0)));
    if v_take > 0 and jsonb_typeof(c.basis->e.key) = 'number' then
      v_lost := v_lost + v_take * (c.basis->>e.key)::numeric;
      c.lost := c.lost || jsonb_build_object(e.key, coalesce((c.lost->>e.key)::numeric, 0) + v_take);
    end if;
  end loop;
  v_lost := least(round(v_lost), c.value - c.lost_value);
  v_owed := round(v_lost * (1 - c.keep_pct));
  if v_owed <= 0 then
    update public.insured_voyages set lost = c.lost, lost_value = lost_value + v_lost::bigint where voyage_id = p_voyage;
    return jsonb_build_object('owed', 0, 'paid', 0, 'short', 0);
  end if;
  v_paid := case when public.city_treasury_on() then greatest(0, least(v_owed, public.city_surplus(c.port_id))) else v_owed end;
  v_ev := public.emit_event(c.player_id, 'INSURANCE_PAID', jsonb_build_object(
    'fleet', (select f.name from public.fleets f where f.id = c.fleet_id), 'voyage_id', p_voyage, 'day', p_day,
    'cause', p_cause, 'port', (select p.code from public.ports p where p.id = c.port_id),
    'lost', p_lost, 'lost_value', v_lost, 'keep_pct', c.keep_pct, 'owed', v_owed, 'paid', v_paid, 'short', v_owed - v_paid));
  if v_paid > 0 then
    perform public.city_pays(c.port_id, c.player_id, 'INSURANCE_PAID', v_paid, v_ev);
  end if;
  update public.insured_voyages
     set lost = c.lost, lost_value = lost_value + v_lost::bigint, paid = paid + v_paid,
         short = short + (v_owed - v_paid), claims = claims + 1
   where voyage_id = p_voyage;
  return jsonb_build_object('owed', v_owed, 'paid', v_paid, 'short', v_owed - v_paid);
end $$;

create or replace function world.insurance()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0211: THE CALLER'S INSURANCE — the insured voyages under way (what is insured, for what, by which city) and the
-- last ten the insurance paid on. Writes nothing. Registered for authenticated only.
declare
  v_player uuid := public.current_player_id();
begin
  if v_player is null then
    raise exception 'E_NO_PLAYER: there is no company signed in' using errcode = 'P0001';
  end if;
  return jsonb_build_object(
    'keep_pct', public.wc_num('insurance_keep_pct'),
    'active', (select coalesce(jsonb_agg(jsonb_build_object(
                 'voyage_id', i.voyage_id, 'fleet_id', i.fleet_id, 'fleet', f.name, 'port', po.code,
                 'to', pd.code, 'eta', v.eta, 'cargo', i.cargo, 'value', i.value, 'price', i.price,
                 'paid', i.paid, 'short', i.short) order by v.eta, i.voyage_id), '[]'::jsonb)
                 from public.insured_voyages i
                 join public.voyages v on v.id = i.voyage_id and v.status = 'SAILING'
                 join public.fleets f on f.id = i.fleet_id
                 join public.ports po on po.id = i.port_id
                 left join public.ports pd on pd.id = v.dest_port_id
                where i.player_id = v_player),
    'paid', (select coalesce(jsonb_agg(x.j order by x.at desc), '[]'::jsonb) from (
               select jsonb_build_object('voyage_id', i.voyage_id, 'fleet', f.name, 'port', po.code,
                        'lost_value', i.lost_value, 'paid', i.paid, 'short', i.short, 'at', i.written_at) as j, i.written_at as at
                 from public.insured_voyages i
                 join public.fleets f on f.id = i.fleet_id
                 join public.ports po on po.id = i.port_id
                where i.player_id = v_player and i.claims > 0
                order by i.written_at desc limit 10) x));
end $$;

revoke all on function voyage.risk_quote(uuid) from public, anon, authenticated;
revoke all on function public.insurance_price(bigint, numeric) from public, anon, authenticated;
revoke all on function voyage.raid_takes(uuid, integer, uuid, text) from public, anon, authenticated;
revoke all on function public.insure_voyage(uuid, boolean) from public, anon, authenticated;
revoke all on function public.insurance_claim(uuid, integer, jsonb, text) from public, anon, authenticated;
revoke all on function world.insurance() from public, anon, authenticated;
grant execute on function world.insurance() to authenticated;

-- ── 5. THE HUNKS (sliced from the LIVE bodies, prod head 0208) ─────────────────────────────────
create temp table hunks_0211 (fn text, n int, old text, new text, primary key (fn, n)) on commit drop;
insert into hunks_0211 values
-- cmd.parse: SAIL may end in INSURED.
('cmd.parse(uuid, uuid, text)', 1,
$h$    i := i + 1;
    if i <= n then
      raise exception 'E_PARSE: SAIL takes one destination; "%" was left over', t[i] using errcode = 'P0001';$h$,
$h$    i := i + 1;
    -- 0211: SAIL <port> INSURED — insure the cargo for this voyage (public.insure_voyage, at departure).
    if i <= n and upper(cmd.fold(t[i])) = 'INSURED' then
      v_args := v_args || jsonb_build_object('insured', true);
      i := i + 1;
    end if;
    if i <= n then
      raise exception 'E_PARSE: SAIL takes one destination; "%" was left over', t[i] using errcode = 'P0001';$h$),
-- cmd.verb_schema: the word, served.
('cmd.verb_schema()', 1,
$h$       {"name":"dest","type":"place","required":true,"keyword":"TO"}],$h$,
$h$       {"name":"dest","type":"place","required":true,"keyword":"TO"},
       {"name":"insurance","type":"enum","values":["INSURED"],"required":false}],$h$),
-- cmd.do_sail: insure (or quote) at departure.
('cmd.do_sail(uuid, jsonb)', 1,
$h$  return jsonb_build_object('voyage_id', v_voyage, 'total_nm', v_nm,
                            'voyage_days', round((v_nm / v_speed) / 24, 2));$h$,
$h$  -- 0211: THE INSURANCE — written (or, unasked, quoted) on the course actually sailed, the moment she departs.
  return jsonb_build_object('voyage_id', v_voyage, 'total_nm', v_nm,
                            'voyage_days', round((v_nm / v_speed) / 24, 2),
                            'insurance', public.insure_voyage(v_voyage, coalesce((p_args->>'insured')::boolean, false)));$h$),
-- voyage.settle: a plundered hold loses its cargo, and the insurance pays.
('voyage.settle(uuid, timestamp with time zone)', 1,
$h$@@L:voyage.settle:41-41@@$h$,
$h$@@L:voyage.settle:41-41@@
  v_taken   jsonb;     -- 0211: what the raiders carried off (voyage.raid_takes)$h$),
('voyage.settle(uuid, timestamp with time zone)', 2,
$h$        update public.ships set cargo = case when v_outcome = 'STRIPPED' then '{}'::jsonb
                                             else cargo end
         where fleet_id = p_fleet;
      end if;$h$,
$h$        -- 0211: WHAT THEY CARRIED OFF (voyage.raid_takes: PLUNDERED 25–50 % of every good by the day's own roll,
        -- as DESIGN B.6 and the day's sentence say; STRIPPED all of it), and the voyage's insurance pays for it.
        v_taken := voyage.raid_takes(v.id, d, p_fleet, v_outcome);
        perform public.insurance_claim(v.id, d, v_taken, v_outcome);
      end if;$h$),
('voyage.settle(uuid, timestamp with time zone)', 3,
$h$                                                   'surgeon_pct', round(public.crew_pct(p_fleet, null, 'crew_saved') * 100, 2))$h$,
$h$                                                   'surgeon_pct', round(public.crew_pct(p_fleet, null, 'crew_saved') * 100, 2))
                   -- 0211: the units the raiders carried off, when they took any
                   || case when coalesce(v_taken, '{}'::jsonb) = '{}'::jsonb then '{}'::jsonb
                           else jsonb_build_object('cargo_lost', v_taken) end$h$),
('voyage.settle(uuid, timestamp with time zone)', 4,
$h$    v_delay := 0; v_payload := jsonb_build_object('short_rations', v_short, 'wages', v_wages);$h$,
$h$    v_delay := 0; v_payload := jsonb_build_object('short_rations', v_short, 'wages', v_wages);
    v_taken := null;   -- 0211: nothing carried off yet this day$h$),
-- public.npc_tend_houses: the refound is retired.
('public.npc_tend_houses(timestamp with time zone)', 1,
$h$@@L:public.npc_tend_houses:13-20@@$h$,
$h$  v_failed  int := 0;
  v_deferred int := 0;
  -- 0211: the refound is retired (public.insure_voyage is what stands behind a merchant's cargo), and its
  -- counters with it: hh, v_last, v_week, v_refound, v_can, v_unfunded.$h$),
('public.npc_tend_houses(timestamp with time zone)', 2,
$h$@@L:public.npc_tend_houses:32-80@@$h$,
$h$  -- 0211: NO REFOUND. A merchant's cargo is insured at every laden departure (public.insure_voyage) and the
  -- insurance pays what a raid carries off (public.insurance_claim); a house that is ruined anyway sails on
  -- with what she has — the path an unfunded refound already took (0115, 0122: never parked).

  return jsonb_build_object($h$),
-- public.npc_tend_sum: the refound's counts are retired.
('public.npc_tend_sum(jsonb, jsonb)', 1,
$h$  foreach v_k in array array['dark', 'started', 'resumed', 'cleared', 'laid_up', 'refounded', 'refound_unfunded',
                             'invested', 'donated', 'busy', 'failed', 'deferred',$h$,
$h$  foreach v_k in array array['dark', 'started', 'resumed', 'cleared', 'laid_up',   -- 0211: the refound's two retired
                             'invested', 'donated', 'busy', 'failed', 'deferred',$h$),
-- cmd.standing_route_close_lap: the insurance in the lap's books.
('cmd.standing_route_close_lap(uuid, timestamp with time zone)', 1,
$h$  v_taxes  bigint;   -- 0122: the profit tax her sales paid$h$,
$h$  v_taxes  bigint;   -- 0122: the profit tax her sales paid
  v_insure bigint;   -- 0211: what insuring her cargo cost this lap, less what the insurance paid back$h$),
('cmd.standing_route_close_lap(uuid, timestamp with time zone)', 2,
$h$  update public.standing_route_laps
     set closed_at = p_now, sold = v_sold, bought = v_bought, supplies = v_supp, repairs = v_rep,
         wages = v_wages, stock_out = v_out,
         net = v_sold - v_bought - v_supp - v_rep - v_wages + v_out - v_in - v_taxes,$h$,
$h$  -- 0211: THE INSURANCE — what her SAILs paid to insure the cargo (cmd.do_sail's `insurance`) less what the
  -- insurance paid back on those voyages (public.insured_voyages.paid), so a plundered lap's books are true.
  select coalesce(sum(case when (o.result->'insurance'->>'insured')::boolean
                           then (o.result->'insurance'->>'price')::bigint else 0 end), 0)
         - coalesce(sum(i.paid), 0)
    into v_insure
    from public.orders o
    left join public.insured_voyages i on i.voyage_id = (o.result->>'voyage_id')::uuid
   where o.route_lap_id = l.id and o.status = 'done' and o.verb = 'SAIL';
  update public.standing_route_laps
     set closed_at = p_now, sold = v_sold, bought = v_bought, supplies = v_supp, repairs = v_rep,
         wages = v_wages, stock_out = v_out, insurance = v_insure,
         net = v_sold - v_bought - v_supp - v_rep - v_wages + v_out - v_in - v_taxes - v_insure,$h$),
-- world.books: the two kinds under their words.
('world.books(integer)', 1,
$h$    ('HIRE', 'Hired', 9), ('TUITION', 'Tuition', 10), ('DONATION', 'Donations', 11), ('TOW', 'Tows', 12)$h$,
$h$    ('HIRE', 'Hired', 9), ('TUITION', 'Tuition', 10), ('DONATION', 'Donations', 11), ('TOW', 'Tows', 12),
    ('INSURANCE', 'Insurance', 13), ('INSURANCE_PAID', 'Insurance paid', 14)   -- 0211$h$),
-- world.npc_fleet_card: the insurance in place of the retired refound.
('world.npc_fleet_card(uuid)', 1,
$h$      'refounded', (select count(*) from public.events e where e.player_id = p.id and e.kind = 'NPC_REFOUNDED'),
      'refounded_at', (select max(e.created_at) from public.events e where e.player_id = p.id and e.kind = 'NPC_REFOUNDED'),$h$,
$h$      -- 0211: the refound is retired; her insurance stands behind her cargo — the losses it paid, and what
      -- the insuring cities could not.
      'insurance', (select jsonb_build_object('claims', count(*), 'paid', coalesce(sum((e.payload->>'paid')::bigint), 0),
                                              'short', coalesce(sum((e.payload->>'short')::bigint), 0))
                      from public.events e where e.player_id = p.id and e.kind = 'INSURANCE_PAID'),$h$),
-- public.client_rpc_entry_points: the read, registered.
('public.client_rpc_entry_points()', 1,
$h$      ('world',       'price_why',             'uuid, uuid')$h$,
$h$      ('world',       'price_why',             'uuid, uuid'),
      -- 0211: your insured voyages, and what the insurance paid (docs/dev-log/2026-10-19-insurance.md).
      ('world',       'insurance',             '')$h$);

do $$
declare
  d     record;
  h     record;
  v_def text;
  v_rev text;
begin
  for d in select * from defs_before_0211 order by fn loop
    v_def := d.def;
    for h in select * from hunks_0211 where fn = d.fn order by n loop
      if pg_temp.occurs_0211(v_def, h.old) <> 1 then
        raise exception '0211 self-assert FAIL: hunk % of % occurs % time(s), not once — the deployed body is not what this file was written against',
          h.n, d.fn, pg_temp.occurs_0211(v_def, h.old);
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    if v_def = d.def then
      raise exception '0211 self-assert FAIL: no hunk for %', d.fn;
    end if;
    execute v_def;
    v_rev := replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '');
    for h in select * from hunks_0211 where fn = d.fn order by n desc loop
      if pg_temp.occurs_0211(v_rev, h.new) <> 1 then
        raise exception '0211 self-assert FAIL: hunk % of % is not in the new body once', h.n, d.fn;
      end if;
    end loop;
    for h in select * from hunks_0211 where fn = d.fn order by n desc loop
      v_rev := replace(v_rev, h.new, h.old);
    end loop;
    if v_rev <> d.def then
      raise exception '0211 self-assert FAIL: % does not reverse to its pre-image', d.fn;
    end if;
    if (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = d.fn::regprocedure) <> d.acl
       or (select p.provolatile from pg_proc p where p.oid = d.fn::regprocedure) <> d.vol
       or (select p.prosecdef from pg_proc p where p.oid = d.fn::regprocedure) <> d.secdef
       or (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = d.fn::regprocedure) <> d.cfg then
      raise exception '0211 self-assert FAIL: the ACL, volatility, definer or config of % moved', d.fn;
    end if;
  end loop;
end $$;

@@PROBES@@
