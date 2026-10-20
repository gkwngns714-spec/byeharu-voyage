-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0213 — A CARGO CAN BE INSURED  (port insurance for a voyage's cargo; merchants insure in place of the
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
-- world_config INSERT ×5 / DELETE ×2, CREATE FUNCTION ×7, DROP FUNCTION ×1, CREATE OR REPLACE FUNCTION ×11 by
-- hunks sliced from the LIVE bodies (prod head 0208, LF-normalised), each asserted to occur exactly once and to
-- reverse to its pre-image, ACL / volatility / definer / config unchanged. SUPERSEDES: cmd.parse (0047…),
-- cmd.verb_schema, cmd.do_sail (0076), voyage.settle (0189), public.npc_tend_houses (0203),
-- public.npc_tend_sum (0181), cmd.standing_route_close_lap (0128), world.books (0177),
-- world.npc_fleet_card (0145), public.client_rpc_entry_points (0185), public.npc_tend (0137: one comment line
-- that still described the refound). The probes run on their own company's rows
-- (probe ids carry 0213) inside sub-transactions rolled back whole; nothing is deleted from events or the
-- ledger. No top-level LOCK / SET LOCAL / BEGIN / SET ROLE. Timings are notices only.
-- ROLLBACK (a forward migration): reverse the hunks (old text in hunks_0213), restore the two knobs
-- (0.2 / 30) and public.npc_worth (0203's body); the new functions and the table are then unread.
-- VERSION: 0213 (prod head 0211 on 2026-10-20; the hunks re-checked against the live bodies at 0208, 0210 and 0211: 0210 moved one
-- declaration in voyage.settle, outside every hunk here). It RENUMBERS to the prod head + 1 at push.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regclass('public.insured_voyages') is not null then
    raise exception '0213 refuses: public.insured_voyages already exists — this has been applied once';
  end if;
  if to_regprocedure('voyage.fight_resolve(uuid, integer, numeric, numeric, jsonb)') is null
     or to_regprocedure('public.npc_worth(uuid)') is null
     or not exists (select 1 from public.world_config where key = 'goods_price_level') then
    raise exception '0213 refuses: 0189 (the fight), 0203 (npc_worth) or 0208 is not in this world';
  end if;
end $guard$;

-- ── 0. HELPERS (pg_temp, gone at commit) ───────────────────────────────────────────────────────
create or replace function pg_temp.occurs_0213(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 1. THE PRE-IMAGES ──────────────────────────────────────────────────────────────────────────
create temp table defs_before_0213 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('cmd.parse(uuid, uuid, text)'), ('cmd.verb_schema()'), ('cmd.do_sail(uuid, jsonb)'),
               ('voyage.settle(uuid, timestamp with time zone)'), ('public.npc_tend_houses(timestamp with time zone)'),
               ('public.npc_tend_sum(jsonb, jsonb)'), ('cmd.standing_route_close_lap(uuid, timestamp with time zone)'),
               ('world.books(integer)'), ('world.npc_fleet_card(uuid)'), ('public.client_rpc_entry_points()'),
               ('public.npc_tend(timestamp with time zone, uuid)')) f(fn);

-- the pre-images kept callable for the probes' old-against-new comparisons (renamed into pg_temp)
do $$
declare
  r record;
begin
  for r in select * from (values
      ('cmd.do_sail(uuid, jsonb)', 'CREATE OR REPLACE FUNCTION cmd.do_sail(', 'CREATE OR REPLACE FUNCTION pg_temp.do_sail_b0213('),
      ('voyage.settle(uuid, timestamp with time zone)', 'CREATE OR REPLACE FUNCTION voyage.settle(', 'CREATE OR REPLACE FUNCTION pg_temp.settle_b0213('),
      ('cmd.parse(uuid, uuid, text)', 'CREATE OR REPLACE FUNCTION cmd.parse(', 'CREATE OR REPLACE FUNCTION pg_temp.parse_b0213('),
      ('public.npc_tend_houses(timestamp with time zone)', 'CREATE OR REPLACE FUNCTION public.npc_tend_houses(', 'CREATE OR REPLACE FUNCTION pg_temp.tend_houses_b0213(')
    ) x(fn, a, b) loop
    if pg_temp.occurs_0213((select def from defs_before_0213 where fn = r.fn), r.a) <> 1 then
      raise exception '0213 self-assert FAIL: the head of % is not where it was expected', r.fn;
    end if;
    execute replace((select def from defs_before_0213 where fn = r.fn), r.a, r.b);
  end loop;
end $$;

-- ── 2. THE KNOBS ────────────────────────────────────────────────────────────────────────────────
insert into public.world_config (key, value, description) values
  ('insurance_raid_loss', to_jsonb(0.084),
   '0213: the share of a cargo''s value one raid (a PIRATES day) carries off, on average — the fight''s measured '
   'PLUNDERED share on prod since it was lit (78 of 348 raids, 01:20-07:40 UTC 2026-10-19) × the mean plunder '
   '(plunder_share_min + plunder_share_span / 2 = 0.375). Read by voyage.risk_quote only. Re-measure after Z3.'),
  ('insurance_keep_pct', to_jsonb(0.10),
   '0213 (the owner, 2026-10-19: "a 10 % deductible"): the share of a loss the owner keeps; the insurance pays '
   'the rest. Frozen onto each policy when it is written.'),
  ('insurance_margin', to_jsonb(0.10),
   '0213: what an insurer asks over the expected payout — the price is value × risk × (1 − keep) × (1 + this). '
   'Tuned so the insuring cities roughly break even with a small margin (docs/dev-log/2026-10-19-insurance.md). '
   'NOT the owner''s — confirm.'),
  ('plunder_share_min', to_jsonb(0.25),
   '0213 (DESIGN B.6: PLUNDERED "−25…−50 % cargo"): the least share of every good a plundering raid carries off.'),
  ('plunder_share_span', to_jsonb(0.25),
   '0213: plunder_share_min + this × the day''s own roll (voyage.rng stream ''plunder'') is the share taken.');

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
create index insured_voyages_player_0213 on public.insured_voyages (player_id, written_at desc);
create index insured_voyages_fleet_0213 on public.insured_voyages (fleet_id, written_at desc);
alter table public.insured_voyages enable row level security;
revoke all on table public.insured_voyages from public, anon, authenticated;
comment on table public.insured_voyages is
  '0213: one row per insured voyage — what was insured, at what cost basis, for what price, by which city, and '
  'what it has paid. Written by public.insure_voyage and public.insurance_claim only; read by world.insurance, '
  'world.npc_fleet_card (no: events) and cmd.standing_route_close_lap.';

alter table public.standing_route_laps add column insurance bigint not null default 0;
comment on column public.standing_route_laps.insurance is
  '0213: what her SAILs paid to insure the cargo this lap, less what the insurance paid back on those voyages.';

-- ── 4. THE NEW FUNCTIONS ────────────────────────────────────────────────────────────────────────
create or replace function voyage.risk_quote(p_voyage uuid)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0213: THE RISK A VOYAGE RUNS — the expected share of its cargo's value lost to raids (docs/PIRATES_AND_HAVENS.md
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
  -- 0213: THE PRICE of insuring a cargo worth p_value on a voyage that loses p_risk of it on average: the
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
-- 0213: WHAT THE RAIDERS CARRY OFF (DESIGN B.6). PLUNDERED: a share of every good on board, in whole units —
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
-- 0213: INSURING A VOYAGE'S CARGO, at the moment it departs (cmd.do_sail, right after voyage.depart). The price is
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
-- 0213: THE PAYOUT. What was lost (p_lost {good code: units}) that the voyage's policy covers — never more of a good
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
-- 0213: THE CALLER'S INSURANCE — the insured voyages under way (what is insured, for what, by which city) and the
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
create temp table hunks_0213 (fn text, n int, old text, new text, primary key (fn, n)) on commit drop;
insert into hunks_0213 values
-- cmd.parse: SAIL may end in INSURED.
('cmd.parse(uuid, uuid, text)', 1,
$h$    i := i + 1;
    if i <= n then
      raise exception 'E_PARSE: SAIL takes one destination; "%" was left over', t[i] using errcode = 'P0001';$h$,
$h$    i := i + 1;
    -- 0213: SAIL <port> INSURED — insure the cargo for this voyage (public.insure_voyage, at departure).
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
$h$  -- 0213: THE INSURANCE — written (or, unasked, quoted) on the course actually sailed, the moment she departs.
  return jsonb_build_object('voyage_id', v_voyage, 'total_nm', v_nm,
                            'voyage_days', round((v_nm / v_speed) / 24, 2),
                            'insurance', public.insure_voyage(v_voyage, coalesce((p_args->>'insured')::boolean, false)));$h$),
-- voyage.settle: a plundered hold loses its cargo, and the insurance pays.
('voyage.settle(uuid, timestamp with time zone)', 1,
$h$  v_fight     jsonb;     -- 0189: the fight's answer (voyage.fight) while combat_bite is on, else null$h$,
$h$  v_fight     jsonb;     -- 0189: the fight's answer (voyage.fight) while combat_bite is on, else null
  v_taken   jsonb;     -- 0213: what the raiders carried off (voyage.raid_takes)$h$),
('voyage.settle(uuid, timestamp with time zone)', 2,
$h$        update public.ships set cargo = case when v_outcome = 'STRIPPED' then '{}'::jsonb
                                             else cargo end
         where fleet_id = p_fleet;
      end if;$h$,
$h$        -- 0213: WHAT THEY CARRIED OFF (voyage.raid_takes: PLUNDERED 25–50 % of every good by the day's own roll,
        -- as DESIGN B.6 and the day's sentence say; STRIPPED all of it), and the voyage's insurance pays for it.
        v_taken := voyage.raid_takes(v.id, d, p_fleet, v_outcome);
        perform public.insurance_claim(v.id, d, v_taken, v_outcome);
      end if;$h$),
('voyage.settle(uuid, timestamp with time zone)', 3,
$h$                                                   'surgeon_pct', round(public.crew_pct(p_fleet, null, 'crew_saved') * 100, 2))$h$,
$h$                                                   'surgeon_pct', round(public.crew_pct(p_fleet, null, 'crew_saved') * 100, 2))
                   -- 0213: the units the raiders carried off, when they took any
                   || case when coalesce(v_taken, '{}'::jsonb) = '{}'::jsonb then '{}'::jsonb
                           else jsonb_build_object('cargo_lost', v_taken) end$h$),
('voyage.settle(uuid, timestamp with time zone)', 4,
$h$    v_delay := 0; v_payload := jsonb_build_object('short_rations', v_short, 'wages', v_wages);$h$,
$h$    v_delay := 0; v_payload := jsonb_build_object('short_rations', v_short, 'wages', v_wages);
    v_taken := null;   -- 0213: nothing carried off yet this day$h$),
-- public.npc_tend_houses: the refound is retired.
('public.npc_tend_houses(timestamp with time zone)', 1,
$h$  hh        record;
  v_last    timestamptz;
  v_week    int;
  v_refound int := 0;
  v_failed  int := 0;
  v_deferred int := 0;
  v_can      bigint;
  v_unfunded int := 0;$h$,
$h$  v_failed  int := 0;
  v_deferred int := 0;
  -- 0213: the refound is retired (public.insure_voyage is what stands behind a merchant's cargo), and its
  -- counters with it: hh, v_last, v_week, v_refound, v_can, v_unfunded.$h$),
('public.npc_tend_houses(timestamp with time zone)', 2,
$h$  -- REFOUNDS, per company, only while the switch is on.
  if v_on then
    -- 0203: WHAT SHE IS WORTH, NOT WHAT IS IN HER PURSE — public.npc_worth (her purse and her cargo at
    -- cost). Her BUYs spend 90 % of both (npc_buy_budget), so a house that has just bought her parcels
    -- held a tenth in coin and was "refounded" from her city while worth her capital (0197's long laps
    -- kept the parcels aboard for hours: 83 refounds in two hours, none of them broke). `ducats` below is
    -- that worth, so the top-up is to her capital.
    for hh in select h.player_id, h.capital, w.worth as ducats, pl.company_name, h.home_port_id
                from public.npc_houses h join public.players pl on pl.id = h.player_id and pl.is_npc
               cross join lateral (select public.npc_worth(h.player_id) as worth) w
               where w.worth < h.capital * public.wc_num('npc_purse_floor_pct')
               order by h.roster_ord loop
      begin
        select max(ev.created_at), count(*) filter (where ev.created_at > p_now - interval '7 days')
          into v_last, v_week
          from public.events ev where ev.player_id = hh.player_id and ev.kind = 'NPC_REFOUNDED';
        continue when v_last is not null
          and v_last > p_now - make_interval(secs => (public.wc_num('npc_refound_cooldown_game_days')
                                                       * public.wc_num('game_day_seconds'))::double precision);
        -- 0115: NO WEEKLY CAP THAT PARKS A COMPANY. A purse under the floor is refounded (the
        -- cooldown still spaces refounds); the cap's lay-up and loop swap are deleted.
        if not public.city_treasury_on() then
          perform public.credit(hh.player_id, 'NPC_REFOUND', hh.capital - hh.ducats,
            public.emit_event(hh.player_id, 'NPC_REFOUNDED', jsonb_build_object(
              'company', hh.company_name, 'amount', hh.capital - hh.ducats, 'week', coalesce(v_week, 0) + 1)));
          v_refound := v_refound + 1;
        else
          -- 0122: lit, the HOME HARBOUR pays, from its surplus — partially, or not at all. A merchant
          -- whose home cannot pay sails on at her purse floor until it earns (never parked, 0115).
          v_can := greatest(0, least(hh.capital - hh.ducats, public.city_surplus(hh.home_port_id)));
          if v_can > 0 then
            perform public.city_pays(hh.home_port_id, hh.player_id, 'NPC_REFOUND', v_can,
              public.emit_event(hh.player_id, 'NPC_REFOUNDED', jsonb_build_object(
                'company', hh.company_name, 'amount', v_can, 'week', coalesce(v_week, 0) + 1,
                'port', (select p.code from public.ports p where p.id = hh.home_port_id),
                'partial', v_can < hh.capital - hh.ducats)));
            v_refound := v_refound + 1;
          else
            v_unfunded := v_unfunded + 1;
          end if;
        end if;
      exception when others then
        v_failed := v_failed + 1;
        v_notes := v_notes || jsonb_build_object('company', hh.company_name, 'error', sqlerrm);
      end;
    end loop;
  end if;

  return jsonb_build_object('refounded', v_refound, 'refound_unfunded', v_unfunded,$h$,
$h$  -- 0213: NO REFOUND. A merchant's cargo is insured at every laden departure (public.insure_voyage) and the
  -- insurance pays what a raid carries off (public.insurance_claim); a house that is ruined anyway sails on
  -- with what she has — the path an unfunded refound already took (0115, 0122: never parked).

  return jsonb_build_object($h$),
-- public.npc_tend_sum: the refound's counts are retired.
('public.npc_tend_sum(jsonb, jsonb)', 1,
$h$  foreach v_k in array array['dark', 'started', 'resumed', 'cleared', 'laid_up', 'refounded', 'refound_unfunded',
                             'invested', 'donated', 'busy', 'failed', 'deferred',$h$,
$h$  foreach v_k in array array['dark', 'started', 'resumed', 'cleared', 'laid_up',   -- 0213: the refound's two retired
                             'invested', 'donated', 'busy', 'failed', 'deferred',$h$),
-- cmd.standing_route_close_lap: the insurance in the lap's books.
('cmd.standing_route_close_lap(uuid, timestamp with time zone)', 1,
$h$  v_taxes  bigint;   -- 0122: the profit tax her sales paid$h$,
$h$  v_taxes  bigint;   -- 0122: the profit tax her sales paid
  v_insure bigint;   -- 0213: what insuring her cargo cost this lap, less what the insurance paid back$h$),
('cmd.standing_route_close_lap(uuid, timestamp with time zone)', 2,
$h$  update public.standing_route_laps
     set closed_at = p_now, sold = v_sold, bought = v_bought, supplies = v_supp, repairs = v_rep,
         wages = v_wages, stock_out = v_out,
         net = v_sold - v_bought - v_supp - v_rep - v_wages + v_out - v_in - v_taxes,$h$,
$h$  -- 0213: THE INSURANCE — what her SAILs paid to insure the cargo (cmd.do_sail's `insurance`) less what the
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
    ('INSURANCE', 'Insurance', 13), ('INSURANCE_PAID', 'Insurance paid', 14)   -- 0213$h$),
-- world.npc_fleet_card: the insurance in place of the retired refound.
('world.npc_fleet_card(uuid)', 1,
$h$      'refounded', (select count(*) from public.events e where e.player_id = p.id and e.kind = 'NPC_REFOUNDED'),
      'refounded_at', (select max(e.created_at) from public.events e where e.player_id = p.id and e.kind = 'NPC_REFOUNDED'),$h$,
$h$      -- 0213: the refound is retired; her insurance stands behind her cargo — the losses it paid, and what
      -- the insuring cities could not.
      'insurance', (select jsonb_build_object('claims', count(*), 'paid', coalesce(sum((e.payload->>'paid')::bigint), 0),
                                              'short', coalesce(sum((e.payload->>'short')::bigint), 0))
                      from public.events e where e.player_id = p.id and e.kind = 'INSURANCE_PAID'),$h$),
-- public.npc_tend: its header still described the refound (the one other body naming its knob; the
-- READERS assert below scans every body for the retired names, and a stale sentence is a stale rule).
('public.npc_tend(timestamp with time zone, uuid)', 1,
$h$-- Then per company: purse below capital × npc_purse_floor_pct -> refounded (NPC_REFOUND through$h$,
$h$-- Then per company (0213: the refound that stood here is retired; public.insure_voyage stands behind her cargo).$h$),
-- public.client_rpc_entry_points: the read, registered.
('public.client_rpc_entry_points()', 1,
$h$      ('world',       'price_why',             'uuid, uuid')$h$,
$h$      ('world',       'price_why',             'uuid, uuid'),
      -- 0213: your insured voyages, and what the insurance paid (docs/dev-log/2026-10-19-insurance.md).
      ('world',       'insurance',             '')$h$);

do $$
declare
  d     record;
  h     record;
  v_def text;
  v_rev text;
begin
  for d in select * from defs_before_0213 order by fn loop
    v_def := d.def;
    for h in select * from hunks_0213 where fn = d.fn order by n loop
      if pg_temp.occurs_0213(v_def, h.old) <> 1 then
        raise exception '0213 self-assert FAIL: hunk % of % occurs % time(s), not once — the deployed body is not what this file was written against',
          h.n, d.fn, pg_temp.occurs_0213(v_def, h.old);
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    if v_def = d.def then
      raise exception '0213 self-assert FAIL: no hunk for %', d.fn;
    end if;
    execute v_def;
    v_rev := replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '');
    for h in select * from hunks_0213 where fn = d.fn order by n desc loop
      if pg_temp.occurs_0213(v_rev, h.new) <> 1 then
        raise exception '0213 self-assert FAIL: hunk % of % is not in the new body once', h.n, d.fn;
      end if;
    end loop;
    for h in select * from hunks_0213 where fn = d.fn order by n desc loop
      v_rev := replace(v_rev, h.new, h.old);
    end loop;
    if v_rev <> d.def then
      raise exception '0213 self-assert FAIL: % does not reverse to its pre-image', d.fn;
    end if;
    if (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = d.fn::regprocedure) <> d.acl
       or (select p.provolatile from pg_proc p where p.oid = d.fn::regprocedure) <> d.vol
       or (select p.prosecdef from pg_proc p where p.oid = d.fn::regprocedure) <> d.secdef
       or (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = d.fn::regprocedure) <> d.cfg then
      raise exception '0213 self-assert FAIL: the ACL, volatility, definer or config of % moved', d.fn;
    end if;
  end loop;
end $$;

-- ── 6. THE PROBES (their own company's rows; every block rolled back whole) ─────────────────────
create temp table probe_0213 (k text primary key, j jsonb) on commit drop;

-- THE PROBE'S COMPANY at Lisbon: the founding barca, resupplied, with two goods on board at a known cost
-- (40 of the first at 25, 10 of the second at 100 — a cargo worth exactly 2,000), a deep purse, and Lisbon's
-- purse lit with no reserve. Goods: the first two by code whose bulk is 1, so the hold arithmetic is plain.
create or replace function pg_temp.house_0213()
returns jsonb
language plpgsql
as $$
declare
  c_uid  constant uuid := '00000000-0213-4000-8000-000000000001';
  v_lis  uuid := (select id from public.ports where code = 'LIS');
  v_fnc  uuid := (select id from public.ports where code = 'FNC');
  v_p    uuid;
  v_f    uuid;
  v_a    text;
  v_b    text;
  v_la   numeric;
  v_lb   numeric;
begin
  update public.world_config set value = 'true'::jsonb where key = 'city_treasury_enabled';
  v_p := public.new_house(c_uid, 'Casa do Seguro 0213', 'PRT', 'LIS');
  select id into v_f from public.fleets where player_id = v_p;
  perform public.credit(v_p, 'PROBE_0213', 1000000);
  begin   -- full casks already (a founding barca) or topped up now: both are a ship that can make Funchal
      perform cmd.do_provision(v_f, jsonb_build_object('mode', 'DAYS', 'days', 12));
    exception when others then if sqlerrm not like 'E_HOLD_FULL%' then raise; end if; end;
  select code into v_a from public.goods where bulk = 1 order by code limit 1;
  select code into v_b from public.goods where bulk = 1 and code > v_a order by code limit 1;
  v_la := public.fleet_load(v_f, v_a, 40, 25);
  v_lb := public.fleet_load(v_f, v_b, 10, 100);
  if v_la <> 40 or v_lb <> 10 or public.fleet_stock_at_cost(v_f) <> 2000 then
    raise exception '0213 self-assert FAIL: the probe''s cargo did not load (% of 40 %, % of 10 %, worth %)',
      v_la, v_a, v_lb, v_b, public.fleet_stock_at_cost(v_f);
  end if;
  update public.port_treasury set reserve = 0 where port_id in (v_lis, v_fnc);
  perform public.treasury_post(v_lis, 'PROBE_0213', 10000000, null, null, true);
  return jsonb_build_object('player', v_p, 'fleet', v_f, 'lis', v_lis, 'fnc', v_fnc, 'a', v_a, 'b', v_b,
    'course', (select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon),
                                        jsonb_build_array(b.roadstead_lat, b.roadstead_lon))
                 from public.sea_reaches a, public.sea_reaches b where a.port_id = v_lis and b.port_id = v_fnc));
end $$;

-- every day of THIS voyage a raid (its own path's hazard_mult; nothing but PIRATES in any sea's mix; the
-- path's seas at the most raiders a sea breeds, piracy 1), then the voyage set back 30 days so one settle lands her.
-- p_lit: the fight decides, and with no evasion an unarmed barca's crew always surrenders → PLUNDERED (0202).
-- Dark: DESIGN B.6's table, escort ~3 against raiders 20–60 → STRIPPED.
create or replace function pg_temp.raided_0213(p_voyage uuid, p_lit boolean)
returns void
language plpgsql
as $$
begin
  update public.world_config set value = '1'::jsonb where key = 'hazard_p_max';
  update public.world_config set value = to_jsonb(p_lit) where key = 'combat_bite';
  update public.world_config set value = '0'::jsonb where key = 'fight_evade_max';
  -- every other kind OUT of the mix (no band at all, so no draw can land outside PIRATES: no lottery)
  update public.voyage_event_kinds set in_sea_mix = false, is_rolled = false, mix_base = null, mix_danger = null, mix_raiders = null
   where in_sea_mix and code <> 'PIRATES';
  update public.seas s set piracy_index = 1
   where s.id in (select (e->>'sea_id')::uuid from public.voyages v, jsonb_array_elements(v.path) e where v.id = p_voyage);
  update public.voyages vo
     set path = (select jsonb_agg(e || jsonb_build_object('hazard_mult', 1000) order by o)
                   from jsonb_array_elements(vo.path) with ordinality t(e, o)),
         departed_at = departed_at - interval '30 days', eta = eta - interval '30 days'
   where vo.id = p_voyage;
end $$;

-- what the raids should have carried off and what the insurance should have paid, re-derived day by day from the
-- cargo at departure, the knobs and the day's own roll (an independent re-statement of raid_takes / insurance_claim)
create or replace function pg_temp.expected_0213(p_voyage uuid, p_cargo jsonb, p_basis jsonb, p_surplus bigint)
returns jsonb
language plpgsql
as $$
declare
  ve      record;
  e       record;
  v_have  jsonb := p_cargo;
  v_share numeric;
  v_take  numeric;
  v_lostv numeric;
  v_owed  bigint;
  v_pay   bigint;
  v_left  bigint := p_surplus;
  v_days  jsonb := '[]'::jsonb;
  v_sum_owed bigint := 0;
  v_sum_paid bigint := 0;
  v_taken jsonb;
begin
  for ve in select day_index, kind, payload from public.voyage_events where voyage_id = p_voyage and kind = 'PIRATES' order by day_index loop
    v_share := case ve.payload->>'outcome' when 'STRIPPED' then 1
                    when 'PLUNDERED' then public.wc_num('plunder_share_min') + public.wc_num('plunder_share_span') * voyage.rng(p_voyage, ve.day_index, 'plunder')
                    else 0 end;
    v_lostv := 0; v_taken := '{}'::jsonb;
    for e in select key, (value)::text::numeric as q from jsonb_each(v_have) order by key loop
      v_take := case when v_share >= 1 then e.q else floor(e.q * v_share) end;
      if v_take > 0 then
        v_taken := v_taken || jsonb_build_object(e.key, v_take);
        v_have := v_have || jsonb_build_object(e.key, e.q - v_take);
        v_lostv := v_lostv + v_take * (p_basis->>e.key)::numeric;
      end if;
    end loop;
    v_owed := round(round(v_lostv) * (1 - public.wc_num('insurance_keep_pct')));
    v_pay := least(v_owed, greatest(v_left, 0));
    v_left := v_left - v_pay;
    v_sum_owed := v_sum_owed + v_owed;
    v_sum_paid := v_sum_paid + v_pay;
    v_days := v_days || jsonb_build_object('day', ve.day_index, 'outcome', ve.payload->>'outcome', 'taken', v_taken,
                                           'served', coalesce(ve.payload->'cargo_lost', '{}'::jsonb), 'owed', v_owed, 'paid', v_pay);
  end loop;
  return jsonb_build_object('days', v_days, 'owed', v_sum_owed, 'paid', v_sum_paid, 'left', v_have);
end $$;

-- what the record says the insurance paid on a voyage: the events, the ledger and the two cities' books
create or replace function pg_temp.paid_0213(p_voyage uuid, p_player uuid, p_lis uuid, p_fnc uuid)
returns jsonb
language sql
as $$
  select jsonb_build_object(
    'events', (select count(*) from public.events e where e.player_id = p_player and e.kind = 'INSURANCE_PAID' and e.payload->>'voyage_id' = p_voyage::text),
    'ev_paid', (select coalesce(sum((e.payload->>'paid')::bigint), 0) from public.events e where e.player_id = p_player and e.kind = 'INSURANCE_PAID' and e.payload->>'voyage_id' = p_voyage::text),
    'ev_short', (select coalesce(sum((e.payload->>'short')::bigint), 0) from public.events e where e.player_id = p_player and e.kind = 'INSURANCE_PAID' and e.payload->>'voyage_id' = p_voyage::text),
    'ledger', (select coalesce(sum(l.ducats_delta), 0) from public.ledger l where l.player_id = p_player and l.kind = 'INSURANCE_PAID'),
    'lis', (select coalesce(sum(t.ducats), 0) from public.treasury_flows t where t.port_id = p_lis and t.kind = 'INSURANCE_PAID' and t.player_id = p_player),
    'fnc', (select count(*) from public.treasury_flows t where t.port_id = p_fnc and t.kind = 'INSURANCE_PAID' and t.player_id = p_player),
    'policy', (select to_jsonb(i) - 'written_at' from public.insured_voyages i where i.voyage_id = p_voyage),
    'cargo', (select coalesce(jsonb_object_agg(k.key, k.q), '{}'::jsonb) from (select e.key, sum((e.value)::text::numeric) q
                from public.ships s cross join lateral jsonb_each(s.cargo) e
               where s.fleet_id = (select fleet_id from public.voyages where id = p_voyage) group by e.key) k),
    'status', (select status from public.voyages where id = p_voyage))
$$;

-- (P1) A PRICE IS CHARGED ONCE. The preview quotes it and writes nothing; the SAIL charges it, to Lisbon, once;
-- the price is value × risk × 0.9 × (1 + margin), the risk re-derived here from the roll's own figures; the
-- voyage to her arrival (and the queue after it) charges nothing more. An unasked SAIL quotes the same price and
-- charges nothing, and sails the same course as the pre-image body.
do $$
declare
  h      jsonb;
  v_f    uuid; v_p uuid; v_lis uuid;
  v_prev jsonb;
  v_r    jsonb;
  v_q    jsonb;
  v_old  jsonb;
  v_voy  uuid;
  v_d0   bigint; v_t0 bigint;
  v_risk numeric;
  v_out  jsonb;
  v_ins_after_prev int;
  v_t    timestamptz;
  v_ms   jsonb := '[]'::jsonb;
  v_k    int;
begin
  begin
    h := pg_temp.house_0213();
    v_f := (h->>'fleet')::uuid; v_p := (h->>'player')::uuid; v_lis := (h->>'lis')::uuid;
    -- the unasked SAIL and the pre-image body, each thrown away
    begin
      v_q := cmd.do_sail(v_f, jsonb_build_object('dest', h->>'fnc', 'path', h->'course'));
      raise exception 'RB_0213';
    exception when others then if sqlerrm <> 'RB_0213' then raise; end if; end;
    begin
      v_old := pg_temp.do_sail_b0213(v_f, jsonb_build_object('dest', h->>'fnc', 'path', h->'course'));
      raise exception 'RB_0213';
    exception when others then if sqlerrm <> 'RB_0213' then raise; end if; end;
    v_prev := cmd.preview(v_f, 'SAIL FNC INSURED', h->'course');
    v_ins_after_prev := (select count(*) from public.ledger l where l.player_id = v_p and l.kind = 'INSURANCE');
    v_d0 := (select ducats from public.players where id = v_p);
    v_t0 := public.treasury_balance(v_lis);
    v_r := cmd.do_sail(v_f, jsonb_build_object('dest', h->>'fnc', 'path', h->'course', 'insured', true));
    v_voy := (v_r->>'voyage_id')::uuid;
    select round(1 - exp(sum(ln(1 - hr.p_hazard * m.share * public.wc_num('insurance_raid_loss')))), 6) into v_risk
      from generate_series(1, voyage.total_days(v_voy)) g(d)
     cross join lateral voyage.hazard_roll(v_voy, g.d) hr
     cross join lateral (select mx.share from voyage.sea_mix((voyage.leg_at_day(v_voy, g.d)->>'sea_id')::uuid) mx
                          where mx.kind_code = 'PIRATES') m;
    -- the cost of a quote, timed (8 calls, one session)
    for v_k in 1 .. 8 loop
      v_t := clock_timestamp();
      perform voyage.risk_quote(v_voy);
      v_ms := v_ms || to_jsonb(round(extract(epoch from clock_timestamp() - v_t) * 1000, 2));
    end loop;
    v_out := jsonb_build_object('r', v_r, 'q', v_q, 'old', v_old, 'prev', v_prev->'estimate'->'insurance',
      'prev_ok', v_prev->'ok', 'ins_after_prev', v_ins_after_prev, 'risk', v_risk, 'days', voyage.total_days(v_voy),
      'want_price', ceil(2000 * v_risk * (1 - public.wc_num('insurance_keep_pct')) * (1 + public.wc_num('insurance_margin'))),
      'purse_delta', (select ducats from public.players where id = v_p) - v_d0,
      'lis_delta', public.treasury_balance(v_lis) - v_t0,
      'policies', (select count(*) from public.insured_voyages where player_id = v_p),
      'policy', (select to_jsonb(i) - 'written_at' from public.insured_voyages i where i.voyage_id = v_voy),
      'quote_ms', v_ms);
    update public.voyages set departed_at = departed_at - interval '30 days', eta = eta - interval '30 days' where id = v_voy;
    perform voyage.settle(v_f, now());
    perform cmd.advance(v_f, now());
    perform voyage.settle(v_f, now());
    v_out := v_out || jsonb_build_object('status', (select status from public.voyages where id = v_voy),
      'charges', (select count(*) from public.ledger l where l.player_id = v_p and l.kind = 'INSURANCE'),
      'charged', (select coalesce(sum(l.ducats_delta), 0) from public.ledger l where l.player_id = v_p and l.kind = 'INSURANCE'),
      'lis_flows', (select coalesce(sum(t.ducats), 0) from public.treasury_flows t where t.port_id = v_lis and t.kind = 'INSURANCE' and t.player_id = v_p),
      'insured_events', (select count(*) from public.events e where e.player_id = v_p and e.kind = 'INSURED'));
    raise exception 'RB_0213';
  exception when others then if sqlerrm <> 'RB_0213' then raise; end if; end;
  -- written OUTSIDE the rolled-back block (a variable survives the sub-transaction; a row does not)
  insert into probe_0213 values ('once', v_out);
end $$;

-- (P2) A PLUNDERED VOYAGE IS PAID FOR, BY THE CITY THAT INSURED IT. Lit, every day a raid her crew cannot hold:
-- every day PLUNDERED; each takes its share of what is left; the insurance pays the loss at the policy's basis
-- less 10 %, from Lisbon (where she sailed from), never from Funchal.
-- (P3) A SHORTFALL IS RECORDED. The same voyage with Lisbon's surplus set to 50 after she sails.
-- (P4) STRIPPED. Dark, the table strips her on the first raid: all 2,000 lost, 1,800 paid.
create or replace function pg_temp.loss_0213(p_lit boolean, p_surplus bigint)
returns jsonb
language plpgsql
as $$
declare
  h      jsonb;
  v_f    uuid; v_p uuid; v_lis uuid; v_fnc uuid;
  v_r    jsonb;
  v_voy  uuid;
  v_pol  record;
  v_exp  jsonb;
  v_out  jsonb;
  v_sur  bigint;
  v_t    timestamptz;
begin
  begin
    h := pg_temp.house_0213();
    v_f := (h->>'fleet')::uuid; v_p := (h->>'player')::uuid; v_lis := (h->>'lis')::uuid; v_fnc := (h->>'fnc')::uuid;
    v_r := cmd.do_sail(v_f, jsonb_build_object('dest', h->>'fnc', 'path', h->'course', 'insured', true));
    v_voy := (v_r->>'voyage_id')::uuid;
    select * into v_pol from public.insured_voyages where voyage_id = v_voy;
    if p_surplus is not null then
      perform public.treasury_post(v_lis, 'PROBE_0213', p_surplus - public.city_surplus(v_lis), null, null, true);
    end if;
    v_sur := public.city_surplus(v_lis);
    perform pg_temp.raided_0213(v_voy, p_lit);
    v_t := clock_timestamp();
    perform voyage.settle(v_f, now());
    v_out := jsonb_build_object('settle_ms', round(extract(epoch from clock_timestamp() - v_t) * 1000, 1),
      'value', v_pol.value, 'basis', v_pol.basis, 'cargo0', v_pol.cargo, 'surplus', v_sur,
      'days', (select count(*) from public.voyage_events ve where ve.voyage_id = v_voy and ve.day_index <= voyage.total_days(v_voy)),
      'raids', (select count(*) from public.voyage_events ve where ve.voyage_id = v_voy and ve.kind = 'PIRATES'),
      'outcomes', (select jsonb_object_agg(o, n) from (select ve.payload->>'outcome' o, count(*) n from public.voyage_events ve
                     where ve.voyage_id = v_voy and ve.kind = 'PIRATES' group by 1) z),
      'want', pg_temp.expected_0213(v_voy, v_pol.cargo, v_pol.basis, v_sur),
      'got', pg_temp.paid_0213(v_voy, v_p, v_lis, v_fnc));
    raise exception 'RB_0213';
  exception when others then if sqlerrm <> 'RB_0213' then raise; end if; end;
  return v_out;
end $$;

do $$
begin
  insert into probe_0213 values ('plunder', pg_temp.loss_0213(true, null));
  insert into probe_0213 values ('short', pg_temp.loss_0213(true, 50));
  insert into probe_0213 values ('stripped', pg_temp.loss_0213(false, null));
end $$;

-- (P5) A MERCHANT INSURES BY HERSELF, and sails uninsured when her purse cannot pay. The first merchant fleet of the
-- roster (by roster_ord), brought to Lisbon with the same two goods, sails to Funchal with no INSURED word.
do $$
declare
  v_f   uuid;
  v_p   uuid;
  v_lis uuid := (select id from public.ports where code = 'LIS');
  v_fnc uuid := (select id from public.ports where code = 'FNC');
  v_a   text := (select code from public.goods where bulk = 1 order by code limit 1);
  v_crs jsonb := (select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon), jsonb_build_array(b.roadstead_lat, b.roadstead_lon))
                    from public.sea_reaches a, public.sea_reaches b where a.port_id = v_lis and b.port_id = v_fnc);
  v_r   jsonb;
  v_r2  jsonb;
  v_d0  bigint;
  v_out jsonb;
begin
  select nf.fleet_id, nf.player_id into v_f, v_p from public.npc_fleets nf order by nf.roster_ord, nf.fleet_id limit 1;
  if v_f is null then
    raise exception '0213 self-assert FAIL: there is no merchant fleet to probe';
  end if;
  begin
    update public.world_config set value = 'true'::jsonb where key = 'city_treasury_enabled';
    update public.voyages set status = 'ABORTED' where fleet_id = v_f and status = 'SAILING';
    update public.orders set status = 'cancelled' where fleet_id = v_f and status in ('pending', 'active', 'failed');
    update public.fleets set status = 'DOCKED', port_id = v_lis, lat = null, lon = null, busy_until = null where id = v_f;
    update public.ships set cargo = '{}'::jsonb, cargo_basis = '{}'::jsonb where fleet_id = v_f;
    perform public.credit(v_p, 'PROBE_0213', 1000000);
    begin   -- full casks already (a founding barca) or topped up now: both are a ship that can make Funchal
      perform cmd.do_provision(v_f, jsonb_build_object('mode', 'DAYS', 'days', 12));
    exception when others then if sqlerrm not like 'E_HOLD_FULL%' then raise; end if; end;
    perform public.fleet_load(v_f, v_a, 20, 50);
    begin
      perform public.credit(v_p, 'PROBE_0213', -(select ducats from public.players where id = v_p));
      v_r2 := cmd.do_sail(v_f, jsonb_build_object('dest', v_fnc, 'path', v_crs));
      v_r2 := v_r2 || jsonb_build_object('charges', (select count(*) from public.ledger l where l.player_id = v_p and l.kind = 'INSURANCE' and l.created_at >= now()));
      raise exception 'RB_0213';
    exception when others then if sqlerrm <> 'RB_0213' then raise; end if; end;
    v_d0 := (select ducats from public.players where id = v_p);
    v_r := cmd.do_sail(v_f, jsonb_build_object('dest', v_fnc, 'path', v_crs));
    v_out := jsonb_build_object('r', v_r->'insurance', 'broke', v_r2->'insurance', 'broke_charges', v_r2->'charges',
      'purse_delta', (select ducats from public.players where id = v_p) - v_d0,
      'policy', (select count(*) from public.insured_voyages i where i.voyage_id = (v_r->>'voyage_id')::uuid));
    raise exception 'RB_0213';
  exception when others then if sqlerrm <> 'RB_0213' then raise; end if; end;
  insert into probe_0213 values ('merchant', v_out);
end $$;

-- (P6) THE REFOUND NO LONGER RUNS. The first merchant house of the roster, worth nothing (purse 0, holds empty),
-- the traders on, its cooldown off: the PRE-IMAGE body refounds her (the positive control: the probe can see a
-- refound); the new body does not, and moves no coin.
do $$
declare
  v_p   uuid := (select h.player_id from public.npc_houses h order by h.roster_ord, h.player_id limit 1);
  v_old jsonb;
  v_new jsonb;
  v_n0  int;
  v_d0  bigint;
begin
  begin
    update public.world_config set value = 'true'::jsonb where key in ('npc_traders_enabled', 'standing_routes_enabled');
    update public.world_config set value = 'false'::jsonb where key = 'city_treasury_enabled';
    update public.world_config set value = '0'::jsonb where key = 'npc_refound_cooldown_game_days';
    update public.ships s set cargo = '{}'::jsonb, cargo_basis = '{}'::jsonb from public.fleets f where f.id = s.fleet_id and f.player_id = v_p;
    perform public.credit(v_p, 'PROBE_0213', -(select ducats from public.players where id = v_p));
    v_n0 := (select count(*) from public.events where player_id = v_p and kind = 'NPC_REFOUNDED');
    begin
      v_old := pg_temp.tend_houses_b0213(now());
      v_old := jsonb_build_object('refounds', (select count(*) from public.events where player_id = v_p and kind = 'NPC_REFOUNDED') - v_n0,
                                  'purse', (select ducats from public.players where id = v_p));
      raise exception 'RB_0213';
    exception when others then if sqlerrm <> 'RB_0213' then raise; end if; end;
    v_d0 := (select ducats from public.players where id = v_p);
    v_new := public.npc_tend_houses(now()) - 'notes';
    v_new := v_new || jsonb_build_object('refounds', (select count(*) from public.events where player_id = v_p and kind = 'NPC_REFOUNDED') - v_n0,
                                         'purse_delta', (select ducats from public.players where id = v_p) - v_d0,
                                         'any_refound', (select count(*) from public.ledger l where l.kind = 'NPC_REFOUND' and l.created_at >= now()));
    raise exception 'RB_0213';
  exception when others then if sqlerrm <> 'RB_0213' then raise; end if; end;
  insert into probe_0213 values ('refound', jsonb_build_object('old', v_old, 'new', v_new));
end $$;

-- (P7) THE WORD, AND WHAT DID NOT MOVE. cmd.parse reads INSURED and nothing else new; the pre-image parse refused
-- it (the change is seen). Then the no-op proof for every arm of voyage.settle this file did not mean to touch: a
-- passage settled under the OLD body and under the NEW, from the same state, compared to the byte — twice:
--   'weather': a hazard EVERY day with only STORM, CALM and FAIR_WIND in the mix (the delay arms, the hull arm).
--     BOUNDED BY THE CLOCK, not by her arrival: a storm costs 36 h and a calm 24-96 h (voyage.day_delay_hours),
--     so a hazard a day pushes the ETA away faster than the days are settled, and a voyage set back 30 days (as the
--     raided ones are) settles some 10,000 days before the clock catches it — measured 2026-10-20: the first apply
--     of this file ran 70 min in this block. She is set back EIGHT voyage-lengths instead, so settle stops at
--     `day_ends_at > now` after at most ~40 voyage-days of clock, whatever the rolls; she is not asked to arrive.
--   'calm': no hazard at all (hazard_mult 0 on every leg), set back 30 days: she ARRIVES in her own 5-odd days,
--     so the arrival arm — LANDFALL and the VOYAGE_REPORT payload, which hunk 3 appends to — is settled by both
--     bodies too. A raid is the one arm that may differ, and it is in neither passage.
create or replace function pg_temp.noop_0213(p_weather boolean)
returns jsonb
language plpgsql
as $$
declare
  h     jsonb;
  v_f   uuid; v_p uuid;
  v_voy uuid;
  v_a   jsonb; v_b jsonb;
  v_out jsonb;
begin
  begin
    h := pg_temp.house_0213();
    v_f := (h->>'fleet')::uuid; v_p := (h->>'player')::uuid;
    v_voy := (cmd.do_sail(v_f, jsonb_build_object('dest', h->>'fnc', 'path', h->'course', 'insured', true))->>'voyage_id')::uuid;
    if p_weather then
      update public.world_config set value = '1'::jsonb where key = 'hazard_p_max';
      -- no raid: only STORM, CALM and FAIR_WIND in the mix (the rest out, with no band to land in)
      update public.voyage_event_kinds set in_sea_mix = false, is_rolled = false, mix_base = null, mix_danger = null, mix_raiders = null
       where in_sea_mix and code not in ('STORM', 'CALM', 'FAIR_WIND');
      update public.voyages vo
         set path = (select jsonb_agg(e || jsonb_build_object('hazard_mult', 1000) order by o) from jsonb_array_elements(vo.path) with ordinality t(e, o)),
             departed_at = departed_at - (eta - departed_at) * 8, eta = eta - (eta - departed_at) * 8
       where vo.id = v_voy;
    else
      update public.voyages vo
         set path = (select jsonb_agg(e || jsonb_build_object('hazard_mult', 0) order by o) from jsonb_array_elements(vo.path) with ordinality t(e, o)),
             departed_at = departed_at - interval '30 days', eta = eta - interval '30 days'
       where vo.id = v_voy;
    end if;
    begin
      perform pg_temp.settle_b0213(v_f, now());
      v_a := pg_temp.paid_0213(v_voy, v_p, (h->>'lis')::uuid, (h->>'fnc')::uuid) - 'policy'
             || jsonb_build_object('events', (select jsonb_agg(jsonb_build_array(ve.day_index, ve.kind, ve.payload, ve.resolved_at) order by ve.day_index)
                                                from public.voyage_events ve where ve.voyage_id = v_voy),
                                   'ships', (select jsonb_agg(jsonb_build_array(s.durability, s.crew, s.cargo, s.water_t, s.food_t) order by s.id) from public.ships s where s.fleet_id = v_f),
                                   'ducats', (select ducats from public.players where id = v_p),
                                   'report', (select e.payload - 'voyage_id' from public.events e where e.player_id = v_p and e.kind = 'VOYAGE_REPORT' and e.payload->>'voyage_id' = v_voy::text),
                                   'eta', (select eta from public.voyages where id = v_voy));
      raise exception 'RB_0213';
    exception when others then if sqlerrm <> 'RB_0213' then raise; end if; end;
    begin
      perform voyage.settle(v_f, now());
      v_b := pg_temp.paid_0213(v_voy, v_p, (h->>'lis')::uuid, (h->>'fnc')::uuid) - 'policy'
             || jsonb_build_object('events', (select jsonb_agg(jsonb_build_array(ve.day_index, ve.kind, ve.payload, ve.resolved_at) order by ve.day_index)
                                                from public.voyage_events ve where ve.voyage_id = v_voy),
                                   'ships', (select jsonb_agg(jsonb_build_array(s.durability, s.crew, s.cargo, s.water_t, s.food_t) order by s.id) from public.ships s where s.fleet_id = v_f),
                                   'ducats', (select ducats from public.players where id = v_p),
                                   'report', (select e.payload - 'voyage_id' from public.events e where e.player_id = v_p and e.kind = 'VOYAGE_REPORT' and e.payload->>'voyage_id' = v_voy::text),
                                   'eta', (select eta from public.voyages where id = v_voy));
      raise exception 'RB_0213';
    exception when others then if sqlerrm <> 'RB_0213' then raise; end if; end;
    v_out := jsonb_build_object('same', v_a = v_b, 'days', jsonb_array_length(coalesce(v_a->'events', '[]'::jsonb)),
                                'hazard_days', (select count(*) from jsonb_array_elements(coalesce(v_a->'events', '[]'::jsonb)) e where e->>1 <> 'QUIET' and e->>1 <> 'LANDFALL'),
                                'kinds', (select jsonb_agg(distinct e->>1) from jsonb_array_elements(coalesce(v_a->'events', '[]'::jsonb)) e),
                                'status', v_a->>'status', 'report', v_a->'report' is not null,
                                'a', case when v_a = v_b then null else v_a end, 'b', case when v_a = v_b then null else v_b end);
    raise exception 'RB_0213';
  exception when others then if sqlerrm <> 'RB_0213' then raise; end if; end;
  return v_out;
end $$;

do $$
declare
  h     jsonb;
  v_f   uuid; v_p uuid;
  v_out jsonb;
  v_oldp text;
  v_t   timestamptz;
begin
  begin
    h := pg_temp.house_0213();
    v_f := (h->>'fleet')::uuid; v_p := (h->>'player')::uuid;
    begin
      perform pg_temp.parse_b0213(v_p, v_f, 'SAIL FNC INSURED');
      v_oldp := 'accepted';
    exception when others then v_oldp := sqlerrm; end;
    v_out := jsonb_build_object('new', cmd.parse(v_p, v_f, 'SAIL FNC INSURED'), 'plain', cmd.parse(v_p, v_f, 'SAIL FNC'),
                                'plain_old', pg_temp.parse_b0213(v_p, v_f, 'SAIL FNC'), 'old_insured', v_oldp);
    begin
      perform cmd.parse(v_p, v_f, 'SAIL FNC NOW');
      v_out := v_out || jsonb_build_object('bogus', 'accepted');
    exception when others then v_out := v_out || jsonb_build_object('bogus', sqlerrm); end;
    raise exception 'RB_0213';
  exception when others then if sqlerrm <> 'RB_0213' then raise; end if; end;
  insert into probe_0213 values ('word', v_out);
  v_t := clock_timestamp();
  insert into probe_0213 values ('weather', pg_temp.noop_0213(true) || jsonb_build_object('ms', round(extract(epoch from clock_timestamp() - v_t) * 1000)));
  v_t := clock_timestamp();
  insert into probe_0213 values ('calm', pg_temp.noop_0213(false) || jsonb_build_object('ms', round(extract(epoch from clock_timestamp() - v_t) * 1000)));
end $$;

-- ── 7. THE ASSERTS ─────────────────────────────────────────────────────────────────────────────
do $$
declare
  o  jsonb := (select j from probe_0213 where k = 'once');
  pl jsonb := (select j from probe_0213 where k = 'plunder');
  sh jsonb := (select j from probe_0213 where k = 'short');
  st jsonb := (select j from probe_0213 where k = 'stripped');
  m  jsonb := (select j from probe_0213 where k = 'merchant');
  rf jsonb := (select j from probe_0213 where k = 'refound');
  w  jsonb := (select j from probe_0213 where k = 'word');
  we jsonb := (select j from probe_0213 where k = 'weather');
  ca jsonb := (select j from probe_0213 where k = 'calm');
  v_price bigint;
  x  jsonb;
  v_readers text;
begin
  if o is null or pl is null or sh is null or st is null or m is null or rf is null or w is null or we is null or ca is null then
    raise exception '0213 self-assert FAIL: a probe wrote nothing (once % plunder % short % stripped % merchant % refound % word % weather % calm %)',
      o is not null, pl is not null, sh is not null, st is not null, m is not null, rf is not null, w is not null, we is not null, ca is not null;
  end if;

  -- (P1) charged once, at the quoted price, to the city she sailed from
  v_price := (o->'r'->'insurance'->>'price')::bigint;
  if not coalesce((o->'r'->'insurance'->>'insured')::boolean, false) or v_price is null or v_price < 1
     or (o->'r'->'insurance'->>'value')::bigint <> 2000 then
    raise exception '0213 self-assert FAIL: an insured SAIL did not insure the cargo worth 2,000: %', o->'r'->'insurance';
  end if;
  if (o->>'risk')::numeric is null or (o->>'risk')::numeric <= 0
     or (o->'r'->'insurance'->>'risk')::numeric <> (o->>'risk')::numeric or v_price <> (o->>'want_price')::bigint then
    raise exception '0213 self-assert FAIL: the price is not value × risk × (1 − keep) × (1 + margin) on the roll''s own risk: served % (risk %), re-derived % (risk %)',
      v_price, o->'r'->'insurance'->>'risk', o->>'want_price', o->>'risk';
  end if;
  if (o->>'purse_delta')::bigint <> -v_price or (o->>'lis_delta')::bigint <> v_price or (o->>'policies')::int <> 1 then
    raise exception '0213 self-assert FAIL: the price did not move once from her purse to Lisbon''s: purse %, Lisbon %, price %, policies %',
      o->>'purse_delta', o->>'lis_delta', v_price, o->>'policies';
  end if;
  if (o->>'status') <> 'ARRIVED' or (o->>'charges')::int <> 1 or (o->>'charged')::bigint <> -v_price
     or (o->>'lis_flows')::bigint <> v_price or (o->>'insured_events')::int <> 1 then
    raise exception '0213 self-assert FAIL: charged more than once by the voyage''s end (status %, % charge(s) totalling %, Lisbon %, % event(s))',
      o->>'status', o->>'charges', o->>'charged', o->>'lis_flows', o->>'insured_events';
  end if;
  if not coalesce((o->>'prev_ok')::boolean, false) or (o->'prev'->>'price')::bigint <> v_price
     or (o->'prev'->>'insured')::boolean is not true or (o->>'ins_after_prev')::int <> 0 then
    raise exception '0213 self-assert FAIL: the preview did not quote the same price without charging it: %, % charge(s)', o->'prev', o->>'ins_after_prev';
  end if;
  if (o->'q'->'insurance'->>'insured')::boolean is not false or (o->'q'->'insurance'->>'price')::bigint <> v_price
     or (o->'q'->>'total_nm') is distinct from (o->'old'->>'total_nm') or (o->'q'->>'voyage_days') is distinct from (o->'old'->>'voyage_days')
     or ((o->'q') - 'insurance' - 'voyage_id') <> ((o->'old') - 'voyage_id') then   -- (parenthesised: `-` binds before `->`)
    raise exception '0213 self-assert FAIL: an unasked SAIL did not sail as before and quote the price: new %, old %', o->'q', o->'old';
  end if;

  -- (P2) plundered every day; each took its share of what was left; paid at the basis less 10 %, from Lisbon
  if (pl->>'raids')::int < 2 or (pl->>'raids')::int <> (pl->>'days')::int or pl->'outcomes' <> jsonb_build_object('PLUNDERED', (pl->>'raids')::int) then
    raise exception '0213 self-assert FAIL: the probe passage was not a raid a day, every one PLUNDERED (its precondition): % raid(s) in % day(s), %',
      pl->>'raids', pl->>'days', pl->'outcomes';
  end if;
  for x in select * from jsonb_array_elements(pl->'want'->'days') loop
    if x->'taken' <> x->'served' then
      raise exception '0213 self-assert FAIL: day % took % where 25–50 %% by its own roll is %', x->>'day', x->'served', x->'taken';
    end if;
  end loop;
  if (pl->'got'->'cargo') <> (select coalesce(jsonb_object_agg(k, v), '{}'::jsonb) from jsonb_each(pl->'want'->'left') t(k, v) where (v::text)::numeric > 0) then
    raise exception '0213 self-assert FAIL: what is left on board % is not what the raids should have left %', pl->'got'->'cargo', pl->'want'->'left';
  end if;
  if (pl->'got'->>'ledger')::bigint <> (pl->'want'->>'owed')::bigint or (pl->'got'->>'ev_paid')::bigint <> (pl->'want'->>'owed')::bigint
     or (pl->'got'->>'lis')::bigint <> -(pl->'want'->>'owed')::bigint or (pl->'got'->>'fnc')::int <> 0
     or (pl->'got'->'policy'->>'paid')::bigint <> (pl->'want'->>'owed')::bigint or (pl->'got'->'policy'->>'short')::bigint <> 0
     or (pl->'got'->>'events')::int <> jsonb_array_length(pl->'want'->'days') then
    raise exception '0213 self-assert FAIL: the plundered cargo was not paid at its basis less 10 %% by Lisbon: want %, got %', pl->'want'->>'owed', pl->'got';
  end if;

  -- (P3) the shortfall: Lisbon pays what its surplus holds, and the rest is recorded
  if (sh->>'surplus')::bigint <> 50 or (sh->'want'->>'owed')::bigint <= 50 then
    raise exception '0213 self-assert FAIL: the shortfall probe''s precondition: surplus % (want 50), owed % (want more)', sh->>'surplus', sh->'want'->>'owed';
  end if;
  if (sh->'got'->>'ledger')::bigint <> 50 or (sh->'got'->>'lis')::bigint <> -50
     or (sh->'got'->'policy'->>'paid')::bigint <> 50
     or (sh->'got'->'policy'->>'short')::bigint <> (sh->'want'->>'owed')::bigint - 50
     or (sh->'got'->>'ev_short')::bigint <> (sh->'want'->>'owed')::bigint - 50 then
    raise exception '0213 self-assert FAIL: the shortfall was not paid as far as the purse went and the rest recorded: owed %, got %', sh->'want'->>'owed', sh->'got';
  end if;

  -- (P4) stripped: everything lost, 90 % of 2,000 paid
  if (st->'outcomes'->>'STRIPPED')::int < 1 or (st->'got'->>'ledger')::bigint <> 1800 or (st->'got'->'cargo') <> '{}'::jsonb
     or (st->'got'->'policy'->>'lost_value')::bigint <> 2000 then
    raise exception '0213 self-assert FAIL: a stripped hold was not paid 1,800 of 2,000: %', st;
  end if;

  -- (P5) a merchant insures by herself; a broke one sails uninsured
  if (m->'r'->>'insured')::boolean is not true or (m->>'purse_delta')::bigint <> -(m->'r'->>'price')::bigint
     or (m->>'policy')::int <> 1 or (m->'broke'->>'insured')::boolean is not false or (m->'broke'->>'why') <> 'purse'
     or (m->>'broke_charges')::int <> 0 then
    raise exception '0213 self-assert FAIL: the merchant''s insurance: %', m;
  end if;

  -- (P6) the refound no longer runs (and the probe could see one)
  if (rf->'old'->>'refounds')::int <> 1 or (rf->'new'->>'refounds')::int <> 0 or (rf->'new'->>'purse_delta')::bigint <> 0
     or (rf->'new'->>'any_refound')::int <> 0 or rf->'new' ? 'refounded' then
    raise exception '0213 self-assert FAIL: the refound: pre-image % (want 1 refound), new % (want none)', rf->'old', rf->'new';
  end if;

  -- (P7) the word, and the no-op
  if (w->'new'->'args'->>'insured')::boolean is not true or w->'plain' <> w->'plain_old'
     or (w->>'old_insured') not like 'E_PARSE%' or (w->>'bogus') not like 'E_PARSE%' then
    raise exception '0213 self-assert FAIL: the INSURED word: %', w;
  end if;
  -- the no-op: the delay and hull arms (a hazard a day, bounded by the clock), and the arrival arm (no hazard)
  if not (we->>'same')::boolean or (we->>'hazard_days')::int < 5 or not (we->'kinds' ? 'STORM' or we->'kinds' ? 'CALM') then
    raise exception '0213 self-assert FAIL: a passage of storms and calms did not settle the same under the old body and the new (% days, % hazard, kinds %, %): % / %',
      we->>'days', we->>'hazard_days', we->'kinds', we->>'status', we->'a', we->'b';
  end if;
  if not (ca->>'same')::boolean or (ca->>'status') <> 'ARRIVED' or not (ca->>'report')::boolean then
    raise exception '0213 self-assert FAIL: a passage with no hazard did not arrive the same under the old body and the new (%, report %): % / %',
      ca->>'status', ca->>'report', ca->'a', ca->'b';
  end if;

  -- READERS: each new author has the one reader it was written for
  select string_agg(format('%s reads %s', n.nspname || '.' || p.proname, t.f), '; ') into v_readers
    from (values ('voyage.raid_takes', 'voyage.settle'), ('public.insurance_claim', 'voyage.settle'),
                 ('public.insure_voyage', 'cmd.do_sail'), ('voyage.risk_quote', 'public.insure_voyage'),
                 ('public.insurance_price', 'public.insure_voyage')) t(f, owner)
    join pg_proc p on p.prosrc like '%' || t.f || '(%'
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'world', 'cmd', 'voyage') and n.nspname || '.' || p.proname <> t.owner;
  if v_readers is not null then
    raise exception '0213 self-assert FAIL: a second reader: %', v_readers;
  end if;
  if (select count(*) from pg_proc p where p.prosrc like '%voyage.raid_takes(%' and p.oid = 'voyage.settle(uuid, timestamp with time zone)'::regprocedure) <> 1
     or (select count(*) from pg_proc p where p.prosrc like '%public.insure_voyage(%' and p.oid = 'cmd.do_sail(uuid, jsonb)'::regprocedure) <> 1 then
    raise exception '0213 self-assert FAIL: the readers are not wired (settle → raid_takes, do_sail → insure_voyage)';
  end if;

  -- WALLS
  if exists (select 1 from public.client_write_grants() g where g.table_name = 'insured_voyages')
     or exists (select 1 from public.client_executable_writers() w2
                 where w2.function_name in ('insure_voyage', 'insurance_claim', 'raid_takes', 'risk_quote', 'insurance_price', 'insurance'))
     or has_table_privilege('authenticated', 'public.insured_voyages', 'select')
     or not has_function_privilege('authenticated', 'world.insurance()', 'execute')
     or has_function_privilege('anon', 'world.insurance()', 'execute')
     or has_function_privilege('authenticated', 'public.insure_voyage(uuid, boolean)', 'execute')
     or not exists (select 1 from public.client_rpc_entry_points() e where e.fn = 'world.insurance()'::regprocedure) then
    raise exception '0213 self-assert FAIL: the walls — a client can write or read past the one read, or the read is not registered';
  end if;
  -- the knobs
  if public.wc_num('insurance_raid_loss') is null or public.wc_num('insurance_keep_pct') <> 0.10
     or public.wc_num('insurance_margin') is null or public.wc_num('plunder_share_min') <> 0.25 or public.wc_num('plunder_share_span') <> 0.25 then
    raise exception '0213 self-assert FAIL: the knobs';
  end if;

  raise notice '0213 probe timings: risk_quote % ms over % days; settle of a raided passage % / % / % ms (plunder / short / stripped); the no-op passages % / % ms (weather % days / calm % days)',
    o->'quote_ms', o->>'days', pl->>'settle_ms', sh->>'settle_ms', st->>'settle_ms', we->>'ms', ca->>'ms', we->>'days', ca->>'days';
  raise notice '0213 self-assert ok: A CARGO CAN BE INSURED. ONCE: 2,000 insured LIS → FNC over % days at risk % for % (re-derived %), purse −%, Lisbon +%, one charge to the end; the preview quoted it and charged nothing; an unasked SAIL quoted it, charged nothing, sailed as before. PLUNDERED % days: took % of %, paid % (basis less 10 %%) by Lisbon, none by Funchal. SHORT: owed %, Lisbon''s surplus 50 paid 50, % recorded short. STRIPPED: 2,000 lost, 1,800 paid. MERCHANT: insured by herself for %, uninsured when broke. REFOUND: pre-image refounded the broke house (%), the new body none. INSURED parses; the pre-image refused it; a passage of % hazard days (%) and a hazard-free passage to arrival settle to the byte as before. Readers one each; walls hold; % hunks reverse, ACLs unchanged.',
    o->>'days', o->>'risk', v_price, o->>'want_price', v_price, v_price,
    pl->>'raids', pl->'want'->'days'->0->'taken', pl->'cargo0', pl->'want'->>'owed',
    sh->'want'->>'owed', (sh->'want'->>'owed')::bigint - 50,
    m->'r'->>'price', rf->'old'->>'refounds', we->>'hazard_days', we->'kinds', (select count(*) from hunks_0213);
end $$;

-- THE REFOUND'S KNOBS AND npc_worth GO LAST (the probe's positive control read them through the pre-image)
do $$
begin
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname in ('public', 'world', 'cmd', 'voyage')
                and (p.prosrc like '%npc_purse_floor_pct%' or p.prosrc like '%npc_refound_cooldown_game_days%'
                     or (p.prosrc like '%npc_worth%' and p.oid <> 'public.npc_worth(uuid)'::regprocedure))) then
    raise exception '0213 self-assert FAIL: the refound''s knobs or public.npc_worth still have a reader: %',
      (select string_agg(n.nspname || '.' || p.proname, ', ') from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname in ('public', 'world', 'cmd', 'voyage')
          and (p.prosrc like '%npc_purse_floor_pct%' or p.prosrc like '%npc_refound_cooldown_game_days%'
               or (p.prosrc like '%npc_worth%' and p.oid <> 'public.npc_worth(uuid)'::regprocedure)));
  end if;
end $$;
delete from public.world_config where key in ('npc_purse_floor_pct', 'npc_refound_cooldown_game_days');
drop function public.npc_worth(uuid);

