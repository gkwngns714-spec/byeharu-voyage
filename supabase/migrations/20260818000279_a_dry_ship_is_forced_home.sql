-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0279 — A SHIP THAT RUNS DRY IS FORCED HOME
--        (the dry-day branch voyage.settle reserved: forced to the closest city, the hold lost,
--         the hulls hurt, the insurance paying the cargo, the city covering the yard's shortfall)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- THE OWNER (2026-10-30, docs/STRANDED_AT_SEA.md, owner row 223):
--   "then the ships need to be fixed and be set on a right course. i mean if there is no provision
--    left at sea - long time voyage, you will be forced back to the closest city, losing all of your
--    cargo, damaged ship, but at that city you will receive your insurance if you've paid for it, and
--    if it is too much to handle, the city should give donations."
--
-- WHAT PROD DOES TODAY (verified read-only by the design doc): voyage.settle (0007) drinks each
-- settled voyage-day's water_t / food_t and floors them at 0 with greatest(0, …) — and then there is
-- NOTHING. A fleet at 0 stores keeps sailing at SHORT_RATIONS' ×1.5 wages until she arrives. 0213's
-- own "decided by default" said in so many words: "a later loss writer calls public.insurance_claim".
-- This is that writer.
--
-- WHAT THIS FILE DOES
-- (1) voyage.strand_port(voyage, day) (NEW, server-only, STABLE) — THE closest city. The design's
--     rule, honoured literally: measure from the current leg's TWO ROADSTEADS (its origin and its
--     destination — the only two places a leg begins and ends), never from a bare point at sea
--     (0152's stated reason for refusing sea wrecks: the reach table measures from harbours only).
--     A harbour's cost is the miles she must still sail to it by the way of an end of her leg:
--     voyage.progress_nm at the day's boundary + voyage.reach_from(the origin), or the miles left of
--     the leg + reach_from(the destination); the leg's own ends cost 0. Open HARBOURS only (a
--     harbour that is a SEA_PLACE has no quay, and an ice-closed one cannot take her). No candidate:
--     null, and the day is not a forced home — nothing is guessed.
-- (2) public.fleet_repair_cost(fleet, points, gear) (NEW, server-only, STABLE) — THE yard's price for
--     the points public.fleet_repair_due already reads. cmd.do_repair's own arithmetic, lifted out
--     so the city's donation and the repair the captain pays are ONE line (NO SPAGHETTI: one
--     authority per concept). cmd.do_repair is re-cut by one hunk to call it; its behaviour is
--     unchanged (proven on a probe, old against new to the ducat).
-- (3) voyage.forced_home(voyage, day, fleet) (NEW, server-only) — THE chain, one function:
--       a. the whole hold leaves through public.fleet_unload (the one unload), every good in full,
--          named cargo_lost in the day's payload exactly as 0213's raid_takes names it;
--       b. public.insurance_claim(voyage, day, lost, 'FORCED_HOME') pays it at the policy's basis
--          less the keep pct, from the insuring city's surplus — ONLY when the voyage was insured
--          (the owner's "if you've paid for it");
--       c. a storm's shape of hull damage on the day's own deterministic roll (voyage.rng's
--          'forced_home' stream), through public.armour_turns, and NEVER to 0 by itself: a hull at
--          durability d loses at most d − 1 (a hull already at 0 is untouched — a wreck still comes
--          only from the existing paths and is towed by 0152);
--       d. the city the fleet is forced into donates the repair shortfall — the yard's quote
--          (public.fleet_repair_due + public.fleet_repair_cost) less her purse (the insurance has
--          already landed in it) — through public.city_pays, kind DONATION (the existing treasury
--          and ledger kind), capped by public.city_surplus while the purses are lit, and paid in
--          full while they are dark exactly as 0213's payout is;
--       e. she lies DOCKED there (UNABLE_TO_SAIL if her flagship was already a wreck, so 0152's tow
--          takes her), her queue released like a tow's (cmd.clear_for), and the voyage ABORTED.
--     One FORCED_HOME event (public.emit_event) carries the whole chain for the player's feed; the
--     day's voyage_events row carries it for the report, with the prose voyage_event_kinds serves.
-- (4) THE TRIGGER — one hunk in voyage.settle, after the day's consumption and wages, before the
--     hazard roll: a fleet at sea with crew aboard whose voyage.endurance_days(fleet) = 0 has run
--     dry (the SAME figure SHORT_RATIONS reads — "dry" is a sharper reading of the same column, not
--     a second rule). The voyage is cut that day; the day's hazard is not rolled (she is making for
--     port, not meeting the sea). The day's wage is charged (a dry day is a day at sea).
-- (5) A NEW voyage_event_kind: FORCED_HOME (ordinal 16, never rolled, not in the sea mix).
--
-- DECIDED BY DEFAULT (the owner may reverse each; docs/dev-log/2026-10-30-stranded-at-sea.md):
--   * "Closest city" is measured from the leg's two roadsteads as (miles spent + reach from the
--     origin) against (miles left + reach from the destination); her own ends cost 0. Both ends, not
--     a bare point — the design's rule.
--   * The closest city is the closest OPEN HARBOUR, not the closest shipyard (the owner said
--     "closest city"; the tow's yard filter is 0152's, for wrecks). A city with no yard cannot quote
--     the repair, so it donates nothing — she lies DOCKED and sails on for a yard.
--   * Damage is a share (the storm's 8–25 % band on the day's own roll, armour turning its part),
--     never to 0 by itself.
--   * The trigger is endurance_days = 0 after the day's consumption, with at least one crewed hull
--     aboard (endurance_days reads an uncrewed hull as 9999 days, so a fleet with nobody aboard can
--     never run dry).
--   * The dry day is cut BEFORE the hazard roll and the day's wage is still owed.
--   * A DRY FINAL DAY IS AN ARRIVAL, NOT A STRANDING: the trigger never fires on the voyage's last
--     day (d < voyage.total_days), because voyage.day_ends_at clamps that day at the ETA — a ship
--     that drinks her last cask as she enters harbour docks there.
--   * The voyage ends ABORTED (the existing "ended early" status — DIVERT and the merchant loops
--     already use it); the reason is the FORCED_HOME event kind, not a new status value.
--   * The donation pays the yard's QUOTE less the purse; it does not press REPAIR for her. A player
--     presses REPAIR (or keeps the coin and sails damaged); a merchant's loop, chosen afresh from
--     where she lies (0152's off_route branch), carries her to a stop with a yard where its REPAIR
--     line already fires. She is DOCKED and paid, never parked.
--   * A voyage with no roadstead at either end (both origin_port_id and dest_port_id null — she
--     sailed from open water) gets no forced home: there is nothing to measure from. The day settles
--     as it always did. Said here rather than guessed at.
--   * The fleet's queued orders are released (cmd.clear_for), as a tow's are: orders written for the
--     old voyage's destination must not run at the port she was blown into.
--
-- SUPERSEDES / RE-CUTS (each hunk occurs exactly once in the LIVE body and reverses to its
-- pre-image; ACL / volatility / definer / config unmoved):
--   * voyage.settle(uuid,timestamptz) — two hunks: the declare block (v_home), and the ran-dry
--     branch between the day's wages and the hazard roll. Sliced from the LIVE body at prod head
--     0278 (as re-cut by 0276).
--   * cmd.do_repair(uuid,jsonb) — two hunks: the yard's price line becomes public.fleet_repair_cost,
--     and THE REPAIR ITSELF is un-broken. 0276 wrote `(public.ship_base(s.id)).durability` into the
--     target list of an UPDATE, which PostgreSQL refuses at PARSE time ("set-returning functions are
--     not allowed in UPDATE") — so since 0276 every REPAIR has raised. Found by this file's own probe;
--     the fix is the scalar subselect 0276's sibling readings (public.fleet_repair_due) already use.
--
-- WHAT IT DOES NOT TOUCH: voyage.endurance_days, SHORT_RATIONS, public.fleet_unload,
-- public.insurance_claim, voyage.reach_from, public.city_surplus / public.city_pays, the DONATION
-- money path, public.tow_for, cmd.do_repair's refusals, the client RPC registry (nothing here is
-- client-callable). The probes run on their own company's rows inside sub-transactions rolled back
-- whole; nothing is deleted from events or the ledger; no top-level LOCK / SET LOCAL / BEGIN / RLS.
--
-- PROD CHECKS (read-only, before the push; in the PR body): the two live bodies carry the pre-images
-- (md5 matches the local chain's); voyage_event_kinds has no FORCED_HOME and max(ordinal) = 15;
-- the blast radius of the day the branch goes live: every SAILING voyage's dry fleets
-- (voyage.endurance_days = 0), the insuring city of each, and their holds' cost — a measured list,
-- not a guess; and the count of SAILING voyages with no roadstead at either end (the stated edge).
--
-- ROLLBACK (forward): reverse the two hunks (old and new swapped) so settle and do_repair are their
-- pre-images; drop voyage.strand_port, void voyage.forced_home, public.fleet_repair_cost; delete the
-- FORCED_HOME kind row (nothing has written one yet outside the branch that is gone). The three
-- functions are then read by nothing.
--
-- VERSION: 0279 (prod head 0278 at authoring; 0278's chain is the base this file is cut against).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regprocedure('voyage.settle(uuid,timestamptz)') is null
     or to_regprocedure('voyage.endurance_days(uuid)') is null
     or to_regprocedure('voyage.reach_from(uuid)') is null
     or to_regprocedure('voyage.progress_nm(uuid,timestamptz)') is null
     or to_regprocedure('public.fleet_unload(uuid,text,numeric)') is null
     or to_regprocedure('public.insurance_claim(uuid,integer,jsonb,text)') is null
     or to_regprocedure('public.city_surplus(uuid)') is null
     or to_regprocedure('public.city_pays(uuid,uuid,text,bigint,uuid)') is null
     or to_regprocedure('public.fleet_repair_due(uuid,numeric)') is null
     or to_regprocedure('public.port_has_shipyard(uuid)') is null
     or to_regprocedure('cmd.do_repair(uuid,jsonb)') is null then
    raise exception '0279 refuses: 0007 / 0076 / 0122 / 0152 / 0181 / 0213 are not all in this world';
  end if;
  if exists (select 1 from public.voyage_event_kinds where code = 'FORCED_HOME') then
    raise exception '0279 refuses: the FORCED_HOME voyage event kind already exists — this has been applied once';
  end if;
end $guard$;

create or replace function pg_temp.occurs_0279(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 0. AS FOUND ────────────────────────────────────────────────────────────────────────────────
create temp table defs_before_0279 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('voyage.settle(uuid,timestamptz)'), ('cmd.do_repair(uuid,jsonb)')) f(fn);

-- EVERY function in the four schemas except the two this file re-cuts and the three it mints: one
-- md5 over the lot, so a body that moves without being named here is caught. Excluded BY NAME (a
-- `not in (to_regprocedure(...))` over a function that does not exist yet would exclude every row
-- through NULL).
create temp table before_0279 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select count(*) from public.world_config) as knobs,
       (select md5(string_agg(md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
           and (n.nspname, p.proname) not in (
                 ('voyage', 'settle'), ('cmd', 'do_repair'),
                 ('voyage', 'strand_port'), ('voyage', 'forced_home'), ('public', 'fleet_repair_cost'))) as others_md5;

-- the pre-images kept callable for the probes' old-against-new comparison (renamed into pg_temp)
do $$
declare
  r record;
begin
  for r in select * from (values
      ('voyage.settle(uuid,timestamptz)', 'CREATE OR REPLACE FUNCTION voyage.settle(', 'CREATE OR REPLACE FUNCTION pg_temp.settle_b0279(')
    ) x(fn, a, b) loop
    if pg_temp.occurs_0279((select def from defs_before_0279 where fn = r.fn), r.a) <> 1 then
      raise exception '0279 self-assert FAIL: the head of % is not where it was expected', r.fn;
    end if;
    execute replace((select def from defs_before_0279 where fn = r.fn), r.a, r.b);
  end loop;
end $$;

-- ── 1. THE NEW VOYAGE EVENT KIND ───────────────────────────────────────────────────────────────
-- A CONDITION, never drawn: is_rolled false, so in_sea_mix false (the catalogue's own CHECK). Its
-- one %s is the city's name, served on the day's payload as `home_name`.
insert into public.voyage_event_kinds
  (code, ordinal, is_rolled, prose, prose_keys, prose_fallbacks, note, in_sea_mix)
values
  ('FORCED_HOME', 16, false,
   'The water and the food are gone. We bore up for %s and came in with the hold empty and the hulls hurt.',
   array['home_name'], array['the nearest port'],
   '0279 (owner row 223, docs/STRANDED_AT_SEA.md). A CONDITION, never drawn: written by voyage.settle''s '
   'ran-dry branch when voyage.endurance_days(fleet) reaches 0 at sea. The voyage is cut, the hold lost '
   'through public.fleet_unload, the insurance (0213) pays it, the hulls take a storm-shaped share (never '
   'to 0 by themselves), the closest open harbour takes her DOCKED, and its city donates the yard''s '
   'repair shortfall. Its payload names the home port, the cargo lost, the hull points and both purses.',
   false)
on conflict (code) do nothing;

-- ── 2. THE CLOSEST CITY ────────────────────────────────────────────────────────────────────────
create or replace function voyage.strand_port(p_voyage uuid, p_day integer)
returns uuid
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0279: THE closest city a fleet that ran dry is forced into. Measured from the current leg's TWO
-- ROADSTEADS — its origin and its destination, the only two places a leg begins and ends — never
-- from a bare point at sea: voyage.reach_from is the reach table the tow already reads, and it
-- measures from harbours only. A harbour's cost is the miles she must still sail to it by the way
-- of an end of this leg:
--     least( miles spent + reach(origin -> H), miles left + reach(H -> destination) )
-- with the leg's own ends at 0. Open HARBOURS only. No candidate answers null, and the caller
-- treats that as "no forced home today" — the day settles as it always did.
declare
  v      public.voyages%rowtype;
  v_prog numeric;
begin
  select * into v from public.voyages where id = p_voyage;
  if v.id is null or v.total_nm is null or v.total_nm <= 0 then return null; end if;
  v_prog := least(greatest(coalesce(voyage.progress_nm(p_voyage, voyage.day_ends_at(p_voyage, p_day)), 0), 0),
                  v.total_nm);
  return (
    select y.id
      from public.ports y
      left join voyage.reach_from(v.origin_port_id) ro on ro.port_id = y.id
      left join voyage.reach_from(v.dest_port_id)   rd on rd.port_id = y.id
     where y.kind = 'HARBOUR'
       and not y.is_ice_closed
       and (y.id = v.origin_port_id or y.id = v.dest_port_id or ro.nm is not null or rd.nm is not null)
     order by least(
                case when y.id = v.origin_port_id then v_prog
                     when ro.nm is not null then v_prog + ro.nm end,
                case when y.id = v.dest_port_id then v.total_nm - v_prog
                     when rd.nm is not null then (v.total_nm - v_prog) + rd.nm end) nulls last,
              y.code
     limit 1);
end $$;

-- ── 3. THE YARD'S PRICE (one authority) ───────────────────────────────────────────────────────
create or replace function public.fleet_repair_cost(p_fleet uuid, p_points numeric, p_gear jsonb default null)
returns bigint
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0279: THE yard's price for the points public.fleet_repair_due already says would be mended, at
  -- the port she lies in — 0114/0210's running-cost factors and the port's own dev_industry, plus
  -- 0158's worn gear in the same payment. cmd.do_repair pays this line; the forced-home donation
  -- weighs the same one against the purse. No second arithmetic.
  select round(coalesce(p_points, 0) * public.wc_num('repair_rate_per_point')
               * (1 - coalesce((select p.dev_industry
                                  from public.ports p join public.fleets f0 on f0.port_id = p.id
                                 where f0.id = p_fleet), 0) * 0.01)
               * public.running_cost_mult(f.player_id)
               * public.wc_num('running_cost_level'))::bigint
         + coalesce((p_gear->>'cost')::bigint, 0)
    from public.fleets f where f.id = p_fleet
$$;

-- ── 4. THE CHAIN ───────────────────────────────────────────────────────────────────────────────
create or replace function voyage.forced_home(p_voyage uuid, p_day integer, p_fleet uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0279: THE ran-dry day's consequences, in one place (called by voyage.settle alone):
--   cargo lost -> insurance (0213) -> hull damage -> forced into the closest city -> the city's
--   donation of the yard's shortfall -> the voyage ends.
-- Returns the day's payload (null when there is no roadstead to measure from and nothing happened).
declare
  v        public.voyages%rowtype;
  f        public.fleets%rowtype;
  v_home   uuid;
  v_code   text;
  v_name   text;
  e        record;
  s        record;
  v_lost   jsonb := '{}'::jsonb;
  v_qty    numeric;
  v_u      numeric;
  v_dmg    numeric;
  v_hull   numeric := 0;
  v_ins    jsonb;
  v_pts    numeric;
  v_gear   jsonb;
  v_cost   bigint;
  v_purse  bigint;
  v_short  bigint;
  v_give   bigint := 0;
  v_repair jsonb;
  v_ev     uuid;
begin
  select * into v from public.voyages where id = p_voyage for update;
  if v.id is null then
    raise exception 'forced_home: no such voyage %', p_voyage using errcode = 'P0001';
  end if;
  select * into f from public.fleets where id = p_fleet for update;
  v_home := voyage.strand_port(p_voyage, p_day);
  if v_home is null then return null; end if;
  select p.code, p.name into v_code, v_name from public.ports p where p.id = v_home;

  -- (a) THE HOLD IS LOST — public.fleet_unload, the one unload, every good in full (0213 names a
  -- lost cargo `cargo_lost` in the day's payload; this is the same word and the same door).
  for e in select distinct k.key as code
             from public.ships s0 cross join lateral jsonb_each(s0.cargo) k
            where s0.fleet_id = p_fleet and (k.value)::text::numeric > 0
            order by 1 loop
    v_qty := public.fleet_cargo_qty(p_fleet, e.code);
    if v_qty > 0 then
      v_lost := v_lost || jsonb_build_object(e.code, public.fleet_unload(p_fleet, e.code, v_qty));
    end if;
  end loop;

  -- (b) THE INSURANCE PAYS IT (0213 — "a later loss writer calls public.insurance_claim"), only when
  -- the voyage was insured. Uninsured: null, and nothing is paid.
  v_ins := public.insurance_claim(p_voyage, p_day, v_lost, 'FORCED_HOME');

  -- (c) THE HULLS ARE HURT — a storm's shape on the day's own deterministic roll (voyage.rng, so a
  -- voyage settled late takes exactly what it would have taken on time), armour turning its part,
  -- and NEVER to 0 by itself: a hull loses at most durability − 1. A hull already at 0 is left
  -- alone — a wreck comes only from the existing paths and is towed (0152).
  v_u := voyage.rng(p_voyage, p_day, 'forced_home');
  for s in select sh.id, sh.durability, (public.ship_base(sh.id)).durability as maxd
             from public.ships sh where sh.fleet_id = p_fleet order by sh.id loop
    if s.durability > 0 then
      v_dmg := least(public.armour_turns(s.id, round(s.maxd * (0.08 + 0.17 * v_u), 2)),
                     s.durability - 1);
      if v_dmg > 0 then
        update public.ships set durability = s.durability - v_dmg where id = s.id;
        v_hull := v_hull + v_dmg;
      end if;
    end if;
  end loop;

  -- (d) BROUGHT IN — DOCKED at the city (UNABLE_TO_SAIL only when her flagship was already a wreck,
  -- so 0152's tow takes her), her queue released like a tow's: orders written for the old voyage's
  -- destination must not run where she was forced.
  perform cmd.clear_for(f.player_id, p_fleet, false);
  update public.fleets
     set status = case when (select sh.durability from public.ships sh
                              where sh.fleet_id = p_fleet and sh.is_flagship) <= 0
                       then 'UNABLE_TO_SAIL' else 'DOCKED' end,
         port_id = v_home, lat = null, lon = null, version = version + 1
   where id = p_fleet;

  -- (e) THE CITY DONATES THE SHORTFALL — the yard's quote (public.fleet_repair_due, then the one
  -- price) less her purse, which the insurance has already reached. A city with no yard quotes
  -- nothing and gives nothing. The purses lit, the gift is capped by the city's surplus (the figure
  -- every spender reads) and paid through public.city_pays, kind DONATION; dark, it is paid in full,
  -- exactly as 0213's own payout is.
  if public.port_has_shipyard(v_home) then
    select d.points, d.gear into v_pts, v_gear from public.fleet_repair_due(p_fleet, 100) d;
    v_cost := public.fleet_repair_cost(p_fleet, v_pts, v_gear);
    select pl.ducats into v_purse from public.players pl where pl.id = f.player_id;
    v_short := greatest(0, coalesce(v_cost, 0) - coalesce(v_purse, 0));
    if v_short > 0 then
      v_give := case when public.city_treasury_on()
                     then least(v_short, greatest(0, public.city_surplus(v_home)))
                     else v_short end;
    end if;
    v_repair := jsonb_build_object('points', round(coalesce(v_pts, 0), 1), 'cost', coalesce(v_cost, 0),
                                   'purse', coalesce(v_purse, 0), 'short', v_short, 'donated', v_give);
  end if;

  -- (f) THE ONE EVENT the player's feed reads, with everything the chain did.
  v_ev := public.emit_event(f.player_id, 'FORCED_HOME', jsonb_build_object(
            'fleet', f.name, 'voyage_id', p_voyage, 'day', p_day,
            'port', v_code, 'port_name', v_name,
            'cargo_lost', v_lost, 'hull_lost', round(v_hull, 2),
            'insurance', v_ins,
            'repair', v_repair));
  if v_give > 0 then
    perform public.city_pays(v_home, f.player_id, 'DONATION', v_give, v_ev);
  end if;

  -- (g) THE VOYAGE ENDS. ABORTED is the existing "ended early" status (DIVERT and the merchant
  -- loops already write it); the reason is the FORCED_HOME event kind, not a fourth status value.
  update public.voyages set status = 'ABORTED' where id = p_voyage;

  return jsonb_build_object('home', v_code, 'home_name', v_name,
                            'cargo_lost', v_lost, 'hull_lost', round(v_hull, 2),
                            'insurance', v_ins, 'repair', v_repair);
end $$;

revoke all on function voyage.strand_port(uuid, integer) from public, anon, authenticated;
revoke all on function voyage.forced_home(uuid, integer, uuid) from public, anon, authenticated;
revoke all on function public.fleet_repair_cost(uuid, numeric, jsonb) from public, anon, authenticated;

-- ── 5. THE HUNKS (sliced from the LIVE bodies, prod head 0278) ─────────────────────────────────
create temp table hunks_0279 (fn text, n int, old text, new text, primary key (fn, n)) on commit drop;
insert into hunks_0279 values

-- voyage.settle: the declare block gains the day's answer
('voyage.settle(uuid,timestamptz)', 1,
$h$  v_taken   jsonb;     -- 0213: what the raiders carried off (voyage.raid_takes)$h$,
$h$  v_taken   jsonb;     -- 0213: what the raiders carried off (voyage.raid_takes)
  v_home    jsonb;     -- 0279: the ran-dry day's forced home (voyage.forced_home); null when she is not dry$h$),

-- voyage.settle: THE TRIGGER — after the day's consumption and wages, before the hazard roll
('voyage.settle(uuid,timestamptz)', 2,
$h$    -- ── the deterministic hazard (DESIGN B.6)
    select * into h from voyage.hazard_roll(v.id, d);$h$,
$h$    -- ── RAN DRY (0279, owner row 223; docs/STRANDED_AT_SEA.md). voyage.endurance_days(fleet) is
    -- THE endurance figure (the lesser of days-of-water and days-of-food), the same one SHORT_RATIONS
    -- reads the day before: 0 after the day's consumption, with a crewed hull aboard, is dry. The
    -- voyage is cut that day and her consequences run in voyage.forced_home; the day's hazard is not
    -- rolled (she is making for port, not meeting the sea), and the day's wage above is still owed.
    -- A DRY FINAL DAY IS AN ARRIVAL, NOT A STRANDING: d < v_cap. voyage.day_ends_at clamps the
    -- trailing day at the ETA, so a ship that drinks her last cask as she makes port docks there
    -- (the arrival arm below) instead of being turned away from a harbour she is entering.
    if v_end <= 0 and d < v_cap
       and exists (select 1 from public.ships sh where sh.fleet_id = p_fleet and sh.crew > 0) then
      v_home := voyage.forced_home(v.id, d, p_fleet);
      if v_home is not null then
        insert into public.voyage_events (voyage_id, day_index, kind, payload, resolved_at)
        values (v.id, d, 'FORCED_HOME',
                jsonb_build_object('short_rations', v_short, 'wages', v_wages) || v_home, v_bound)
        on conflict (voyage_id, day_index) do nothing;
        update public.voyages set last_settled_day = d where id = v.id;
        perform cmd.advance(p_fleet, p_now);
        return v_resolved + 1;
      end if;
    end if;

    -- ── the deterministic hazard (DESIGN B.6)
    select * into h from voyage.hazard_roll(v.id, d);$h$),

-- cmd.do_repair: THE REPAIR ITSELF — 0276 wrote a set-returning call into the target list of an
-- UPDATE, which PostgreSQL refuses at PARSE time ("set-returning functions are not allowed in
-- UPDATE"), so since 0276 every REPAIR has raised. Its own sibling readings (public.fleet_repair_due)
-- already spell the same thing as a scalar subselect for the same reason. Found by this file's own
-- probe (P8 calls cmd.do_repair on a damaged hull); fixed here because the owner's chain ends in the
-- ship being fixed, and a donation that buys a repair that cannot run is half a slice.
('cmd.do_repair(uuid,jsonb)', 2,
$h$  update public.ships s set durability = greatest(s.durability, (public.ship_base(s.id)).durability * v_to / 100)
   where s.fleet_id = p_fleet;   -- 0276: her own rolled max$h$,
$h$  update public.ships s set durability = greatest(s.durability, (select b.durability from public.ship_base(s.id) b) * v_to / 100)
   where s.fleet_id = p_fleet;   -- 0276: her own rolled max (0279: as a scalar subselect — a set-returning call is refused in an UPDATE)$h$),

-- cmd.do_repair: the yard's price is public.fleet_repair_cost (the donation weighs the same line)
('cmd.do_repair(uuid,jsonb)', 1,
$h$  v_cost := round(v_points * public.wc_num('repair_rate_per_point') * (1 - v_dev * 0.01)
                  * public.running_cost_mult(f.player_id)
                  * public.wc_num('running_cost_level'))::bigint;   -- 0114; 0210: × running_cost_level
  v_cost := v_cost + coalesce((v_gear->>'cost')::bigint, 0);   -- 0158: and the gear's, in the same payment$h$,
$h$  v_cost := public.fleet_repair_cost(p_fleet, v_points, v_gear);   -- 0279: THE yard's price — the one line this pays and the forced-home donation weighs$h$);

-- ── 6. THE SLICE TOOL (its own copy, by necessity — tests/duplication.spec.ts) ────────────────
create or replace function pg_temp.recut_0279(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := replace(pg_get_functiondef(p_fn::regprocedure), E'\r', '');
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0279 where fn = p_fn order by n loop
    v_n := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
    if v_n <> 1 then
      raise exception '0279 slice: hunk % of % occurs % time(s), expected exactly 1 — the deployed body is not what this migration was generated against.',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0279(fn) from (select distinct fn from hunks_0279) x order by fn;

-- ── 7. SELF-ASSERT ─────────────────────────────────────────────────────────────────────────────
create temp table probe_0279 (k text primary key, j jsonb) on commit drop;

do $$
declare
  d     record;
  h     record;
  v_def text;
  v_rev text;
  v_md5 text;
  v_n   int;
begin
  -- (a) PARITY BY REVERSE SUBSTITUTION: each re-cut body, every 0279 hunk put back the other way
  --     (each new hunk occurring exactly once), is its pre-image to the character; ACL, volatility,
  --     definer and search_path unmoved.
  for d in select * from defs_before_0279 order by fn loop
    v_def := replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '');
    v_rev := v_def;
    for h in select * from hunks_0279 where fn = d.fn order by n desc loop
      if pg_temp.occurs_0279(v_rev, h.new) <> 1 then
        raise exception '0279 self-assert FAIL: hunk % of % is in the new body % time(s), not once',
          h.n, d.fn, pg_temp.occurs_0279(v_rev, h.new);
      end if;
      v_rev := replace(v_rev, h.new, h.old);
    end loop;
    if v_rev <> d.def or v_def = v_rev then
      raise exception '0279 self-assert FAIL: % is not its pre-image plus only 0279''s hunks', d.fn;
    end if;
    if coalesce((select p.proacl::text from pg_proc p where p.oid = d.fn::regprocedure), '') is distinct from d.acl
       or (select p.provolatile from pg_proc p where p.oid = d.fn::regprocedure) is distinct from d.vol
       or (select p.prosecdef from pg_proc p where p.oid = d.fn::regprocedure) is distinct from d.secdef
       or (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = d.fn::regprocedure) is distinct from d.cfg then
      raise exception '0279 self-assert FAIL: the ACL, volatility, definer or config of % moved', d.fn;
    end if;
  end loop;

  -- (b) NOTHING ELSE MOVED: one md5 over every other body in the four schemas, the entry-point
  --     registry, the knob count; and the three new functions are server-only.
  select md5(string_agg(md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_md5
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and (n.nspname, p.proname) not in (
           ('voyage', 'settle'), ('cmd', 'do_repair'),
           ('voyage', 'strand_port'), ('voyage', 'forced_home'), ('public', 'fleet_repair_cost'));
  if v_md5 is distinct from (select others_md5 from before_0279)
     or (select count(*) from public.client_rpc_entry_points()) <> (select entry_points from before_0279)
     or (select count(*) from public.world_config) <> (select knobs from before_0279) then
    raise exception '0279 self-assert FAIL: a body, the registry or the knobs moved outside 0279''s hunks';
  end if;
  if has_function_privilege('anon', 'voyage.strand_port(uuid, integer)', 'execute')
     or has_function_privilege('authenticated', 'voyage.strand_port(uuid, integer)', 'execute')
     or has_function_privilege('anon', 'voyage.forced_home(uuid, integer, uuid)', 'execute')
     or has_function_privilege('authenticated', 'voyage.forced_home(uuid, integer, uuid)', 'execute')
     or has_function_privilege('anon', 'public.fleet_repair_cost(uuid, numeric, jsonb)', 'execute')
     or has_function_privilege('authenticated', 'public.fleet_repair_cost(uuid, numeric, jsonb)', 'execute') then
    raise exception '0279 self-assert FAIL: a new function is client-callable';
  end if;

  -- (c) THE KIND. One FORCED_HOME row: never rolled, not in the sea mix, ordinal 16; and
  --     voyage.report_line turns its payload into a sentence naming the city.
  if (select count(*) from public.voyage_event_kinds where code = 'FORCED_HOME') <> 1
     or exists (select 1 from public.voyage_event_kinds
                 where code = 'FORCED_HOME' and (is_rolled or in_sea_mix or ordinal <> 16)) then
    raise exception '0279 self-assert FAIL: the FORCED_HOME kind row is not the one this file wrote';
  end if;
  v_def := voyage.report_line(1, 'FORCED_HOME', jsonb_build_object('home_name', 'Lisboa'));
  if v_def not like 'Day 1.%' or position('Lisboa' in v_def) = 0 then
    raise exception '0279 self-assert FAIL: the kind''s report line is not "Day 1. … Lisboa …": %', v_def;
  end if;
end $$;

-- ── 8. THE PROBES (their own company's rows; every block rolled back whole) ────────────────────

-- THE PROBE'S HOUSE at Lisbon: the founding barca, a full larder (12 days), a cargo of the first two
-- bulk-1 goods worth exactly 2,000 (40 at 25, 10 at 100), and a SAIL to Funchal — insured when asked
-- (a merchant's laden voyage is insured whatever the flag says, 0213). Returns the ids and the course.
create or replace function pg_temp.house_0279(p_uid uuid, p_npc boolean, p_insured boolean, p_cargo boolean)
returns jsonb
language plpgsql
as $$
declare
  v_lis  uuid := (select id from public.ports where code = 'LIS');
  v_fnc  uuid := (select id from public.ports where code = 'FNC');
  v_p    uuid;
  v_f    uuid;
  v_voy  uuid;
  v_a    text;
  v_b    text;
  v_la   numeric := 0;
  v_lb   numeric := 0;
  v_c    jsonb;
begin
  -- an NPC never signs in (players_npc_never_signs_in): a merchant is founded with no auth_uid, as
  -- public.npc_found founds her.
  v_p := public.new_house(case when p_npc then null else p_uid end,
                          'Casa Seca ' || right(p_uid::text, 4), 'PRT', 'LIS',
                          'Seca ' || right(p_uid::text, 4), 'barca', 'Seca ' || right(p_uid::text, 4), null, p_npc);
  select id into v_f from public.fleets where player_id = v_p;
  perform public.credit(v_p, 'PROBE_0279', 1000000);
  begin
    perform cmd.do_provision(v_f, jsonb_build_object('mode', 'DAYS', 'days', 12));
  exception when others then
    if sqlerrm not like 'E_HOLD_FULL%' then raise; end if;
  end;
  if p_cargo then
    select code into v_a from public.goods where bulk = 1 order by code limit 1;
    select code into v_b from public.goods where bulk = 1 and code > v_a order by code limit 1;
    v_la := public.fleet_load(v_f, v_a, 40, 25);
    v_lb := public.fleet_load(v_f, v_b, 10, 100);
    if v_la <> 40 or v_lb <> 10 or public.fleet_stock_at_cost(v_f) <> 2000 then
      raise exception '0279 self-assert FAIL: the probe''s cargo did not load (% of 40 %, % of 10 %, worth %)',
        v_la, v_a, v_lb, v_b, public.fleet_stock_at_cost(v_f);
    end if;
  end if;
  v_c := (select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon),
                                   jsonb_build_array(b.roadstead_lat, b.roadstead_lon))
            from public.sea_reaches a, public.sea_reaches b where a.port_id = v_lis and b.port_id = v_fnc);
  v_voy := (cmd.do_sail(v_f, jsonb_build_object('dest', v_fnc, 'path', v_c, 'insured', p_insured))->>'voyage_id')::uuid;
  return jsonb_build_object('player', v_p, 'fleet', v_f, 'voyage', v_voy, 'lis', v_lis, 'fnc', v_fnc,
                            'a', v_a, 'b', v_b);
end $$;

-- THE EXPECTED HOME, re-stated over public.sea_reaches itself (never voyage.reach_from): the
-- design's score, miles spent + reach from the origin against miles left + reach from the
-- destination, her own ends at 0, open harbours only.
create or replace function pg_temp.expected_home_0279(p_voyage uuid, p_day integer)
returns uuid
language sql
stable
as $$
  with v as (select * from public.voyages where id = p_voyage),
       prog as (select least(greatest(coalesce(voyage.progress_nm(p_voyage, voyage.day_ends_at(p_voyage, p_day)), 0), 0),
                             (select total_nm from v)) as nm)
  select y.id
    from public.ports y
    cross join v
    cross join prog
    left join public.sea_reaches ro on ro.port_id = v.origin_port_id
    left join public.sea_reaches rd on rd.port_id = v.dest_port_id
   where y.kind = 'HARBOUR' and not y.is_ice_closed
     and (y.id = v.origin_port_id or y.id = v.dest_port_id
          or (ro.reaches->>y.code) is not null or (rd.reaches->>y.code) is not null)
   order by least(
              case when y.id = v.origin_port_id then prog.nm
                   when (ro.reaches->>y.code) is not null then prog.nm + (ro.reaches->>y.code)::numeric end,
              case when y.id = v.dest_port_id then v.total_nm - prog.nm
                   when (rd.reaches->>y.code) is not null then (v.total_nm - prog.nm) + (rd.reaches->>y.code)::numeric end) nulls last,
            y.code
   limit 1
$$;

do $$ begin end $$;
-- (P1) THE WHOLE CHAIN, insured. The day's trigger fires; the hold is emptied through the one
-- unload; the insurance pays 90 % of the 2,000 aboard; the hulls are hurt but every one still
-- floats; she lies DOCKED at the closest city; the voyage is ABORTED; the event says so once; a
-- second settle writes nothing more. The pre-image body, run on the same setup, has no branch: she
-- sails on with her hold. Old and new are compared on their own companies.
do $$
declare
  c_uid constant uuid := '00000000-0279-4000-8000-000000000001';
  h     jsonb;
  o     jsonb;
  v_f   uuid; v_p uuid; v_voy uuid;
  v_home uuid; v_exp uuid;
  v_t   timestamptz;
  v_ev  jsonb;
  v_hull0 numeric; v_hull1 numeric;
  v_before bigint; v_after bigint;
  v_out jsonb;
begin
  begin
    update public.world_config set value = 'true'::jsonb where key = 'city_treasury_enabled';
    update public.port_treasury set reserve = 0 where port_id = (select id from public.ports where code = 'LIS');
    perform public.treasury_post((select id from public.ports where code = 'LIS'), 'PROBE_0279', 10000000, null, null, true);
    h := pg_temp.house_0279(c_uid, false, true, true);
    v_f := (h->>'fleet')::uuid; v_p := (h->>'player')::uuid; v_voy := (h->>'voyage')::uuid;
    v_exp := pg_temp.expected_home_0279(v_voy, 1);
    update public.ships set water_t = 0, food_t = 0 where fleet_id = v_f;
    select coalesce(sum(durability), 0) into v_hull0 from public.ships where fleet_id = v_f;
    v_before := (select ducats from public.players where id = v_p);
    v_t := voyage.day_ends_at(v_voy, 1) + interval '1 second';
    perform voyage.settle(v_f, v_t);
    select coalesce(sum(durability), 0) into v_hull1 from public.ships where fleet_id = v_f;
    select to_jsonb(ve) - 'id' - 'voyage_id' - 'resolved_at' into v_ev
      from public.voyage_events ve where ve.voyage_id = v_voy and ve.day_index = 1;
    v_after := (select ducats from public.players where id = v_p);
    v_home := (select port_id from public.fleets where id = v_f);
    v_out := jsonb_build_object(
      'home', v_home, 'expected', v_exp, 'status', (select status from public.voyages where id = v_voy),
      'day', (select last_settled_day from public.voyages where id = v_voy),
      'fleet_status', (select status from public.fleets where id = v_f),
      'lat', (select lat from public.fleets where id = v_f), 'lon', (select lon from public.fleets where id = v_f),
      'kind', v_ev->>'kind', 'payload', v_ev->'payload',
      'hold', public.fleet_stock_at_cost(v_f), 'hull0', v_hull0, 'hull1', v_hull1,
      'min_hull', (select min(durability) from public.ships where fleet_id = v_f),
      'policy', (select to_jsonb(i) - 'written_at' from public.insured_voyages i where i.voyage_id = v_voy),
      'paid_ledger', (select coalesce(sum(ducats_delta), 0) from public.ledger l
                       where l.player_id = v_p and l.kind = 'INSURANCE_PAID'),
      'forced_events', (select count(*) from public.events e where e.player_id = v_p and e.kind = 'FORCED_HOME'),
      'event', (select to_jsonb(e) - 'id' - 'created_at' from public.events e where e.player_id = v_p and e.kind = 'FORCED_HOME'),
      'donated_ledger', (select coalesce(sum(ducats_delta), 0) from public.ledger l where l.player_id = v_p and l.kind = 'DONATION'),
      'purse_delta', v_after - v_before,
      'second_settle', voyage.settle(v_f, v_t + interval '1 day'),
      'forced_events_after', (select count(*) from public.events e where e.player_id = v_p and e.kind = 'FORCED_HOME'));

    if v_exp is null then raise exception '0279 self-assert FAIL: the probe''s leg has no closest city'; end if;
    if v_home is distinct from v_exp then
      raise exception '0279 self-assert FAIL: forced into % , the probe computed %', v_home, v_exp;
    end if;
    if (v_ev->>'kind') is distinct from 'FORCED_HOME' then
      raise exception '0279 self-assert FAIL: day 1 is %, not FORCED_HOME', v_ev->>'kind';
    end if;
    if (v_ev->'payload'->>'home') is distinct from (select code from public.ports where id = v_exp) then
      raise exception '0279 self-assert FAIL: the payload names % , not the closest city', v_ev->'payload'->>'home';
    end if;
    if (v_ev->'payload'->'cargo_lost'->>(h->>'a'))::numeric <> 40
       or (v_ev->'payload'->'cargo_lost'->>(h->>'b'))::numeric <> 10
       or public.fleet_cargo_qty(v_f, h->>'a') <> 0 or public.fleet_cargo_qty(v_f, h->>'b') <> 0 then
      raise exception '0279 self-assert FAIL: the hold was not lost through the one unload';
    end if;
    if (v_ev->'payload'->>'hull_lost')::numeric <= 0
       or v_hull1 >= v_hull0
       or v_hull0 - v_hull1 <> (v_ev->'payload'->>'hull_lost')::numeric then
      raise exception '0279 self-assert FAIL: the hulls were not hurt as the payload says (% -> %, payload %)',
        v_hull0, v_hull1, v_ev->'payload'->>'hull_lost';
    end if;
    if (select min(durability) from public.ships where fleet_id = v_f) <= 0 then
      raise exception '0279 self-assert FAIL: running dry sank a hull by itself';
    end if;
    if (select status from public.fleets where id = v_f) <> 'DOCKED'
       or (select lat from public.fleets where id = v_f) is not null
       or (select lon from public.fleets where id = v_f) is not null then
      raise exception '0279 self-assert FAIL: the fleet is not DOCKED at the closest city';
    end if;
    if (select status from public.voyages where id = v_voy) <> 'ABORTED'
       or (select last_settled_day from public.voyages where id = v_voy) <> 1 then
      raise exception '0279 self-assert FAIL: the voyage was not cut on the dry day';
    end if;
    if (select paid from public.insured_voyages where voyage_id = v_voy) <> 1800
       or (select claims from public.insured_voyages where voyage_id = v_voy) <> 1
       or (select lost_value from public.insured_voyages where voyage_id = v_voy) <> 2000 then
      raise exception '0279 self-assert FAIL: the insurance did not pay 90%% of the lost cargo: %',
        (select to_jsonb(i) - 'written_at' from public.insured_voyages i where i.voyage_id = v_voy);
    end if;
    if (select coalesce(sum(ducats_delta), 0) from public.ledger l where l.player_id = v_p and l.kind = 'INSURANCE_PAID') <> 1800 then
      raise exception '0279 self-assert FAIL: the insurance credit is not on the ledger';
    end if;
    if v_out->>'forced_events' <> '1'
       or (v_out->'event'->'payload'->>'fleet') is distinct from (select name from public.fleets where id = v_f)
       or (v_out->'event'->'payload'->>'port') is distinct from (select code from public.ports where id = v_exp) then
      raise exception '0279 self-assert FAIL: the FORCED_HOME event is not the one this chain wrote: %', v_out->'event';
    end if;
    if (v_out->>'second_settle')::int <> 0 or v_out->>'forced_events_after' <> '1' then
      raise exception '0279 self-assert FAIL: a second settle wrote another forced home';
    end if;
    if (v_out->>'donated_ledger')::bigint <> 0
       or (v_out->'payload'->'repair'->>'donated')::bigint <> 0 then
      raise exception '0279 self-assert FAIL: a deep purse was donated to';
    end if;

    -- THE PRE-IMAGE BODY on its own company: no branch, no forced home, the hold carried on.
    o := pg_temp.house_0279('00000000-0279-4000-8000-000000000002'::uuid, false, true, true);
    update public.ships set water_t = 0, food_t = 0 where fleet_id = (o->>'fleet')::uuid;
    perform pg_temp.settle_b0279((o->>'fleet')::uuid, voyage.day_ends_at((o->>'voyage')::uuid, 1) + interval '1 second');
    if exists (select 1 from public.events e where e.player_id = (o->>'player')::uuid and e.kind = 'FORCED_HOME')
       or exists (select 1 from public.voyage_events ve where ve.voyage_id = (o->>'voyage')::uuid and ve.kind = 'FORCED_HOME')
       or public.fleet_cargo_qty((o->>'fleet')::uuid, o->>'a') = 0 then
      raise exception '0279 self-assert FAIL: the pre-image body ran a forced home';
    end if;
    v_out := v_out || jsonb_build_object('old_status', (select status from public.voyages where id = (o->>'voyage')::uuid),
                                         'old_cargo', public.fleet_cargo_qty((o->>'fleet')::uuid, o->>'a'));
    raise exception 'ZX0279';
  exception when others then
    if sqlerrm <> 'ZX0279' then raise; end if;
  end;
  insert into probe_0279 values ('P1', v_out);
end $$;

do $$ begin end $$;
-- (P2) THE CONTROL: a sound larder is not a dry ship. The same day settles with the hold intact and
-- the voyage still under way; no FORCED_HOME anywhere.
do $$
declare
  h jsonb; v_f uuid; v_p uuid; v_voy uuid; v_out jsonb;
begin
  begin
    h := pg_temp.house_0279('00000000-0279-4000-8000-000000000003'::uuid, false, false, true);
    v_f := (h->>'fleet')::uuid; v_p := (h->>'player')::uuid; v_voy := (h->>'voyage')::uuid;
    perform voyage.settle(v_f, voyage.day_ends_at(v_voy, 1) + interval '1 second');
    v_out := jsonb_build_object(
      'status', (select status from public.voyages where id = v_voy),
      'cargo', public.fleet_cargo_qty(v_f, h->>'a'),
      'events', (select count(*) from public.events e where e.player_id = v_p and e.kind = 'FORCED_HOME'),
      'day', (select to_jsonb(ve) - 'id' - 'voyage_id' - 'resolved_at' from public.voyage_events ve
               where ve.voyage_id = v_voy and ve.day_index = 1));
    if v_out->>'status' <> 'SAILING' or (v_out->>'cargo')::numeric <> 40 or v_out->>'events' <> '0' then
      raise exception '0279 self-assert FAIL: a fleet with stores aboard was forced home: %', v_out;
    end if;
    raise exception 'ZX0279';
  exception when others then
    if sqlerrm <> 'ZX0279' then raise; end if;
  end;
  insert into probe_0279 values ('P2', v_out);
end $$;

do $$ begin end $$;
-- (P3) NO POLICY, NO PAYOUT (the owner's "if you've paid for it"): the hold is lost, nothing is
-- paid, and the shortfall is the whole yard's quote.
do $$
declare
  h jsonb; v_f uuid; v_p uuid; v_voy uuid; v_out jsonb;
begin
  begin
    h := pg_temp.house_0279('00000000-0279-4000-8000-000000000004'::uuid, false, false, true);
    v_f := (h->>'fleet')::uuid; v_p := (h->>'player')::uuid; v_voy := (h->>'voyage')::uuid;
    update public.ships set water_t = 0, food_t = 0 where fleet_id = v_f;
    perform voyage.settle(v_f, voyage.day_ends_at(v_voy, 1) + interval '1 second');
    v_out := jsonb_build_object(
      'policies', (select count(*) from public.insured_voyages where voyage_id = v_voy),
      'paid', (select coalesce(sum(ducats_delta), 0) from public.ledger l where l.player_id = v_p and l.kind = 'INSURANCE_PAID'),
      'ins_events', (select count(*) from public.events e where e.player_id = v_p and e.kind = 'INSURANCE_PAID'),
      'cargo', public.fleet_cargo_qty(v_f, h->>'a'),
      'payload', (select payload from public.voyage_events where voyage_id = v_voy and day_index = 1));
    if v_out->>'policies' <> '0' or (v_out->>'paid')::bigint <> 0 or v_out->>'ins_events' <> '0'
       or (v_out->>'cargo')::numeric <> 0 then
      raise exception '0279 self-assert FAIL: an uninsured voyage was paid: %', v_out;
    end if;
    if (v_out->'payload'->>'insurance') is not null then
      raise exception '0279 self-assert FAIL: an uninsured voyage carries an insurance answer';
    end if;
    raise exception 'ZX0279';
  exception when others then
    if sqlerrm <> 'ZX0279' then raise; end if;
  end;
  insert into probe_0279 values ('P3', v_out);
end $$;

do $$ begin end $$;
-- (P4) THE CITY DONATES THE SHORTFALL. The purse emptied after she sailed, a dear yard (the knob
-- raised inside this block only), the city she is forced into lit and funded: the gift is the quote
-- less the purse, capped by that city's surplus, on the DONATION ledger and the treasury alike; the
-- purse ends at the insurance plus the gift, and the damaged hulls are NOT repaired for her. The
-- city is the probe's own computed closest city (on this leg she is past half way, so it is the
-- DESTINATION — a fact, not an assumption), and the expected gift is derived from that city's
-- surplus as it stood before the day settled, less the payout if the insurer is the same city.
do $$
declare
  h jsonb; v_f uuid; v_p uuid; v_voy uuid; v_home uuid; v_exp uuid;
  v_lis uuid := (select id from public.ports where code = 'LIS');
  v_surplus0 bigint; v_purse0 bigint;
  v_paid bigint; v_short bigint; v_want bigint; v_out jsonb;
begin
  begin
    update public.world_config set value = 'true'::jsonb where key = 'city_treasury_enabled';
    h := pg_temp.house_0279('00000000-0279-4000-8000-000000000005'::uuid, false, true, true);
    v_f := (h->>'fleet')::uuid; v_p := (h->>'player')::uuid; v_voy := (h->>'voyage')::uuid;
    v_exp := pg_temp.expected_home_0279(v_voy, 1);
    update public.port_treasury set reserve = 0 where port_id in (v_lis, v_exp);
    perform public.treasury_post(v_lis, 'PROBE_0279', 2000, null, null, true);   -- enough for the 1,800 owed
    if v_exp <> v_lis then
      perform public.treasury_post(v_exp, 'PROBE_0279', 10000000, null, null, true);
    end if;
    perform public.credit(v_p, 'PROBE_0279', -(select ducats from public.players where id = v_p));
    update public.ships set water_t = 0, food_t = 0, durability = 1 where fleet_id = v_f;
    update public.world_config set value = '1000000'::jsonb where key = 'repair_rate_per_point';
    v_surplus0 := public.city_surplus(v_exp);
    v_purse0 := (select ducats from public.players where id = v_p);
    perform voyage.settle(v_f, voyage.day_ends_at(v_voy, 1) + interval '1 second');
    v_home := (select port_id from public.fleets where id = v_f);
    v_out := jsonb_build_object(
      'home', v_home, 'expected', v_exp,
      'payload', (select payload from public.voyage_events where voyage_id = v_voy and day_index = 1),
      'ledger_donation', (select coalesce(sum(ducats_delta), 0) from public.ledger l where l.player_id = v_p and l.kind = 'DONATION'),
      'treasury_donation', (select coalesce(sum(ducats), 0) from public.treasury_flows t where t.port_id = v_home and t.kind = 'DONATION' and t.player_id = v_p),
      'purse_delta', (select ducats from public.players where id = v_p) - v_purse0,
      'hulls', (select array_agg(durability order by id) from public.ships where fleet_id = v_f));
    if v_home is distinct from v_exp then
      raise exception '0279 self-assert FAIL: forced into % not the probe''s closest city %', v_home, v_exp;
    end if;
    if (v_out->'payload'->>'repair') is null then
      raise exception '0279 self-assert FAIL: the closest city quoted no repair at all: %', v_out->'payload';
    end if;
    v_paid  := coalesce((v_out->'payload'->'insurance'->>'paid')::bigint, 0);
    v_short := (v_out->'payload'->'repair'->>'short')::bigint;
    v_want  := least(v_short, greatest(0, v_surplus0 - case when v_home = v_lis then v_paid else 0 end));
    if v_paid <> 1800 then
      raise exception '0279 self-assert FAIL: the insurance did not pay 1,800 of 2,000 first: %', v_out->'payload'->'insurance';
    end if;
    if v_short <= 0 or v_want <= 0 then
      raise exception '0279 self-assert FAIL: no shortfall or no city surplus to meet it: %', v_out;
    end if;
    if (v_out->'payload'->'repair'->>'donated')::bigint <> v_want
       or (v_out->>'ledger_donation')::bigint <> v_want
       or (v_out->>'treasury_donation')::bigint <> -v_want then
      raise exception '0279 self-assert FAIL: the city''s gift is not the capped shortfall (% expected): %', v_want, v_out;
    end if;
    if (v_out->>'purse_delta')::bigint <> v_paid + v_want then
      raise exception '0279 self-assert FAIL: the purse is not the insurance plus the gift: %', v_out->>'purse_delta';
    end if;
    if exists (select 1 from public.ships where fleet_id = v_f and durability > 1) then
      raise exception '0279 self-assert FAIL: the donation repaired the hulls without the captain';
    end if;
    raise exception 'ZX0279';
  exception when others then
    if sqlerrm <> 'ZX0279' then raise; end if;
  end;
  insert into probe_0279 values ('P4', v_out);
end $$;

-- (P5) NEVER TO 0 BY ITSELF — and a wreck that was already one stays one. All hulls at 1 lose
-- nothing; a flagship already at 0 is left at 0 and the fleet is UNABLE_TO_SAIL, so 0152's tow
-- takes over.
do $$
declare
  h jsonb; v_f uuid; v_p uuid; v_voy uuid; v_out jsonb;
begin
  begin
    h := pg_temp.house_0279('00000000-0279-4000-8000-000000000006'::uuid, false, false, true);
    v_f := (h->>'fleet')::uuid; v_voy := (h->>'voyage')::uuid;
    update public.ships set water_t = 0, food_t = 0, durability = 1 where fleet_id = v_f;
    perform voyage.settle(v_f, voyage.day_ends_at(v_voy, 1) + interval '1 second');
    v_out := jsonb_build_object(
      'min_hull', (select min(durability) from public.ships where fleet_id = v_f),
      'status', (select status from public.fleets where id = v_f),
      'hull_lost', (select payload->>'hull_lost' from public.voyage_events where voyage_id = v_voy and day_index = 1));
    if (v_out->>'min_hull')::numeric <> 1 or v_out->>'status' <> 'DOCKED' or (v_out->>'hull_lost')::numeric <> 0 then
      raise exception '0279 self-assert FAIL: a hull at 1 was taken below it, or the fleet is not DOCKED: %', v_out;
    end if;

    -- a wreck already aboard: the flagship at 0 stays at 0, the fleet is a wreck, and the tow's door
    -- is the one that takes her (E_NOT_AT_PORT no longer: she is in port, so tow_for proceeds).
    h := pg_temp.house_0279('00000000-0279-4000-8000-000000000007'::uuid, false, false, true);
    v_f := (h->>'fleet')::uuid; v_voy := (h->>'voyage')::uuid;
    update public.ships set water_t = 0, food_t = 0 where fleet_id = v_f;
    update public.ships set durability = 0 where fleet_id = v_f and is_flagship;
    perform voyage.settle(v_f, voyage.day_ends_at(v_voy, 1) + interval '1 second');
    v_out := v_out || jsonb_build_object(
      'wreck_status', (select status from public.fleets where id = v_f),
      'flag_hull', (select durability from public.ships where fleet_id = v_f and is_flagship),
      'others_float', (select coalesce(bool_and(durability >= 1), true) from public.ships
                        where fleet_id = v_f and not is_flagship));
    if v_out->>'wreck_status' <> 'UNABLE_TO_SAIL' or (v_out->>'flag_hull')::numeric <> 0
       or v_out->>'others_float' <> 'true' then
      raise exception '0279 self-assert FAIL: an existing wreck was not left to the tow: %', v_out;
    end if;
    raise exception 'ZX0279';
  exception when others then
    if sqlerrm <> 'ZX0279' then raise; end if;
  end;
  insert into probe_0279 values ('P5', v_out);
end $$;

do $$ begin end $$;
-- (P6) THE MERCHANT IS THE SAME CHAIN: an NPC house with a laden voyage is insured without asking
-- (0213), is forced home by the same settle branch, and is paid — she is DOCKED and never parked.
do $$
declare
  h jsonb; v_f uuid; v_p uuid; v_voy uuid; v_out jsonb;
begin
  begin
    update public.world_config set value = 'true'::jsonb where key = 'city_treasury_enabled';
    update public.port_treasury set reserve = 0 where port_id = (select id from public.ports where code = 'LIS');
    perform public.treasury_post((select id from public.ports where code = 'LIS'), 'PROBE_0279', 10000000, null, null, true);
    h := pg_temp.house_0279('00000000-0279-4000-8000-000000000008'::uuid, true, false, true);
    v_f := (h->>'fleet')::uuid; v_p := (h->>'player')::uuid; v_voy := (h->>'voyage')::uuid;
    update public.ships set water_t = 0, food_t = 0 where fleet_id = v_f;
    perform voyage.settle(v_f, voyage.day_ends_at(v_voy, 1) + interval '1 second');
    v_out := jsonb_build_object(
      'npc', (select is_npc from public.players where id = v_p),
      'policies', (select count(*) from public.insured_voyages where voyage_id = v_voy),
      'paid', (select paid from public.insured_voyages where voyage_id = v_voy),
      'status', (select status from public.fleets where id = v_f),
      'voyage', (select status from public.voyages where id = v_voy),
      'events', (select count(*) from public.events e where e.player_id = v_p and e.kind = 'FORCED_HOME'));
    if v_out->>'npc' <> 'true' or v_out->>'policies' <> '1' or (v_out->>'paid')::bigint <> 1800
       or v_out->>'status' <> 'DOCKED' or v_out->>'voyage' <> 'ABORTED' or v_out->>'events' <> '1' then
      raise exception '0279 self-assert FAIL: a merchant did not get the same chain: %', v_out;
    end if;
    raise exception 'ZX0279';
  exception when others then
    if sqlerrm <> 'ZX0279' then raise; end if;
  end;
  insert into probe_0279 values ('P6', v_out);
end $$;

do $$ begin end $$;
-- (P7) NO ROADSTEAD, NO FORCED HOME. A passage with neither end a port has nothing to measure
-- from: the day settles as it always did (a quiet watch, the hold intact, the voyage under way).
do $$
declare
  h jsonb; v_f uuid; v_p uuid; v_voy uuid; v_out jsonb;
begin
  begin
    h := pg_temp.house_0279('00000000-0279-4000-8000-000000000009'::uuid, false, false, true);
    v_f := (h->>'fleet')::uuid; v_p := (h->>'player')::uuid; v_voy := (h->>'voyage')::uuid;
    update public.voyages set origin_port_id = null, dest_port_id = null where id = v_voy;
    update public.ships set water_t = 0, food_t = 0 where fleet_id = v_f;
    v_out := jsonb_build_object('home', voyage.strand_port(v_voy, 1));
    perform voyage.settle(v_f, voyage.day_ends_at(v_voy, 1) + interval '1 second');
    v_out := v_out || jsonb_build_object(
      'events', (select count(*) from public.events e where e.player_id = v_p and e.kind = 'FORCED_HOME'),
      'kind', (select kind from public.voyage_events where voyage_id = v_voy and day_index = 1),
      'cargo', public.fleet_cargo_qty(v_f, h->>'a'));
    if v_out->>'home' is not null or v_out->>'events' <> '0'
       or v_out->>'kind' = 'FORCED_HOME' or (v_out->>'cargo')::numeric <> 40 then
      raise exception '0279 self-assert FAIL: a passage with no roadstead invented a home: %', v_out;
    end if;
    raise exception 'ZX0279';
  exception when others then
    if sqlerrm <> 'ZX0279' then raise; end if;
  end;
  insert into probe_0279 values ('P7', v_out);
end $$;

do $$ begin end $$;
-- (P8) THE YARD'S PRICE, ONE AUTHORITY. public.fleet_repair_cost is cmd.do_repair's own arithmetic
-- on every input, and cmd.do_repair now quotes exactly it.
do $$
declare
  h jsonb; v_f uuid; v_p uuid;
  v_port uuid;
  v_dev int; v_mult numeric; v_rate numeric; v_lvl numeric;
  v_pts numeric; v_gear jsonb;
  v_old bigint; v_new bigint;
  v_rep jsonb;
  v_out jsonb := '{}'::jsonb;
begin
  begin
    h := pg_temp.house_0279('00000000-0279-4000-8000-00000000000a'::uuid, false, false, true);
    v_f := (h->>'fleet')::uuid; v_p := (h->>'player')::uuid;
    -- a damaged, docked hull at A PORT THAT MENDS SHIPS: something to quote
    v_port := (select p.id from public.ports p
                where p.kind = 'HARBOUR' and public.port_has_shipyard(p.id) order by p.code limit 1);
    update public.fleets set status = 'DOCKED', port_id = v_port where id = v_f;
    update public.ships s
       set durability = (select b.durability from public.ship_base(s.id) b) / 2
     where s.fleet_id = v_f;
    select d.points, d.gear into v_pts, v_gear from public.fleet_repair_due(v_f, 100) d;
    select dev_industry into v_dev from public.ports where id = v_port;
    v_rate := public.wc_num('repair_rate_per_point');
    v_mult := public.running_cost_mult(v_p);
    v_lvl  := public.wc_num('running_cost_level');
    v_old := round(v_pts * v_rate * (1 - v_dev * 0.01) * v_mult * v_lvl)::bigint
             + coalesce((v_gear->>'cost')::bigint, 0);
    v_new := public.fleet_repair_cost(v_f, v_pts, v_gear);
    v_rep := cmd.do_repair(v_f, jsonb_build_object('to_pct', 100));
    v_out := jsonb_build_object('points', v_pts, 'old', v_old, 'new', v_new, 'repair', v_rep);
    if v_pts <= 0 or v_old <> v_new or (v_rep->>'cost')::bigint <> v_new then
      raise exception '0279 self-assert FAIL: the yard''s price moved (% old, % new, do_repair %): %',
        v_old, v_new, v_rep->>'cost', v_out;
    end if;
    raise exception 'ZX0279';
  exception when others then
    if sqlerrm <> 'ZX0279' then raise; end if;
  end;
  insert into probe_0279 values ('P8', v_out);
end $$;

-- (P9) THE RECEIPT. Every probe above ran and rolled back; the claims they established are named,
-- and the four that matter are summarised for the dev-log.
do $$
declare
  p1 jsonb := (select j from probe_0279 where k = 'P1');
  p4 jsonb := (select j from probe_0279 where k = 'P4');
  p5 jsonb := (select j from probe_0279 where k = 'P5');
  n    int;
begin
  select count(*) into n from probe_0279;
  if n <> 8 or not exists (select 1 from probe_0279 where k = 'P1') then
    raise exception '0279 self-assert FAIL: the probes did not all run (% of 8)', n;
  end if;
  if (p1->'second_settle')::int <> 0 then
    raise exception '0279 self-assert FAIL: a settled forced home settled again';
  end if;
  if (p4->'payload'->'repair'->>'donated')::bigint <> 10000000 or (p5->>'min_hull')::numeric <> 1 then
    raise exception '0279 self-assert FAIL: the donation or the never-to-0 rule did not hold';
  end if;
  raise notice '0279 self-assert ok: A DRY SHIP IS FORCED HOME. voyage.settle and cmd.do_repair reverse to their pre-images hunk by hunk, ACL/volatility/definer/config unmoved, every other body in the four schemas unmoved by md5, the registry and the knobs unmoved; the three new functions are server-only; FORCED_HOME is ordinal 16, never rolled, not in the sea mix, and its report line names the city. Probes (own rows, rolled back): the chain end to end (the closest city re-stated from public.sea_reaches, the hold emptied through fleet_unload, 1800 of 2000 paid, the hulls hurt but every one afloat, DOCKED, ABORTED, one event, no second settle; the pre-image body runs none of it); a sound larder is not dry; no policy, no payout; the city''s gift is the capped shortfall on the DONATION ledger and treasury and does not repair the hulls; a hull at 1 is never taken to 0 and an existing wreck is left to the tow; a merchant gets the same chain insured without asking; a passage with no roadstead is not forced home; the yard''s price is one line. Rolled back.';
end $$;

-- ── 9. THE SELF-ASSERT'S OWN PROBE ROWS, GONE ─────────────────────────────────────────────────
-- Nothing to clean: every probe wrote inside a sub-transaction rolled back whole, and the receipt
-- above only reads temp tables (on commit drop).
