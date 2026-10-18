-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0181 — A MERCHANT DOES NOT SAIL FOR NOTHING  (with nothing paying on any loop she waits in port; a
--        BUY limit is priced as she arrives; a sound hull is not sent to the yard)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER'S WORDS ───────────────────────────────────────────────────────────────────────────
-- 2026-10-18: *"redesign the routes that are like this, and also that gives negative cash"* — the
-- merchant laps that close at zero or less (0142, 0150 and 0180 were earlier slices of the same order).
--
-- ── WHAT PROD SHOWED (read-only, 2026-10-18 07:29–09:30 UTC, head 0180; docs/dev-log/2026-10-18-no-empty-laps.md)
-- * ~76 % of short merchant laps closed at ≤ 0, and ~60 % of them PLANNED NO BUY: a zero lap is a
--   planned-empty lap — it sails, pays its stores (net −14 … −26) and buys nothing. At 09:16, 283 of the
--   837 merchant routes carried no BUY line at all; 281 of them are 2- or 3-stop loops of < 4,000 nm.
-- * WHY NO BUY (60 such routes, 140 legs, every ranked good put through the leg planner's own filters
--   with the stable authorities it calls): 48 legs have no good the ranking calls profitable at all;
--   on 52 the best good fails because the sink takes nothing above cost × (1 + npc_sell_margin) —
--   short legs whose distance premium is below spread + tax; 22 are held by npc_buyers_per_good
--   (three other merchant routes already buy every paying good there); 13 by the BUY ceiling.
--   The loop choice is not broken: at a lap start every loop on offer (her own and up to 15
--   candidates from where she lies) is priced, and a loop that pays is taken. What is wrong is the
--   ELSE: when no loop pays, 0115 has her sail her own loop in ballast, "never parked", paying stores.
-- * LINES THAT DIE LATER: of 1,681 live BUY lines at 09:20, 694 would be refused if executed at the
--   ask of that moment; 345 of those only by the limit written at plan time (the ask had passed it,
--   while her next stop's bid still paid ≥ npc_min_return_pct over it), 349 because the parcel no
--   longer pays at all.
-- * REPAIR E_UNAVAILABLE (2,407 of the 3,789 refusals in laps closed 07:30–09:30): every one is
--   "nothing aboard needs repair". npc_plan writes REPAIR at the first shipyard of every loop (0142 —
--   never at a yardless port: 0 E_NO_YARD), and cmd.standing_route_lines wrote the line whether or not
--   anything was worn. Harmless, but it is a refusal on almost every lap.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- (1) SHE WAITS IN PORT. public.npc_plan, at a lap start (her fleet docked at her stop 0, no open
--     lap, planned alone), when the loop she would sail has NO paying parcel — every loop on offer was
--     priced and none carries one — and she carries nothing: she is laid up where she lies
--     ('laid_up', through cmd.standing_route_pause_for — written once; a lay-up already standing is
--     not written again) and counted `waiting`. cmd.run_standing_route already stops a lap that its
--     plan paused (0114), so the lap is never opened and no store is bought. public.npc_tend_route
--     lifts 'laid_up' at every tend (hourly, public.tick_reconcile) by re-planning her from where she
--     lies; a plan that lays her up again leaves her waiting (counted `waiting`), a plan that pays
--     resumes her through the same door as before. With cargo aboard she still sails her loop, so her
--     SELLs and 0142's cut-loss can clear it; mid-lap, off her loop or on the switch's pass nothing
--     changes. The client already names the state ("Laid up", src/live/merchantWords.ts).
-- (2) A BUY LIMIT IS PRICED AS SHE ARRIVES. public.npc_buy_ceiling is now THE ask at the quay now
--     (world.quote, one unit) × (1 + patience) — no longer the ask carried to the stock the port is
--     SUPPOSED to hold, which under target sat below the ask itself. cmd.standing_route_lines, as she
--     arrives, reads it LIVE for a merchant's BUY instead of the limit stored at plan time, and still
--     never above what her next stop's bid lets her pay (0114's npc_min_return_pct bound). The planner
--     stores the same reading at plan time (0180's "never born refused" now drops only a parcel whose
--     own size walks the price past her patience).
-- (3) REPAIR ONLY WHEN DUE. public.fleet_repair_due(fleet, to %) is THE reading of what a repair would
--     mend (hull points, the worst hull's per cent, and — 0158, while gear wear bites — the gear and
--     its price), lifted out of cmd.do_repair, which now reads it. cmd.standing_route_lines writes
--     REPAIR at a stop marked for it only when something is due, as it writes PROVISION only below the
--     keep level. For a player's route as for a merchant's.
-- (4) The receipts count `waiting` (npc_plan, npc_tend_route; npc_tend_sum adds it).
--
-- ── NOT THE OWNER'S — CONFIRM ───────────────────────────────────────────────────────────────────
-- * Waiting replaces 0115's "a merchant is never parked" for the empty-handed lap start only, and she
--   is re-planned at each hourly tend (not at every market drift).
-- * The ceiling's patience is measured from the ask NOW, not from the port's target stock: at a drawn-
--   down maker she pays up to her patience over today's ask, bounded by what her next stop pays.
-- * A REPAIR line is not written for a fleet with nothing to mend (players' routes too).
--
-- ── LOCKS AND TIME ──────────────────────────────────────────────────────────────────────────────
-- CREATE FUNCTION ×1, CREATE OR REPLACE FUNCTION ×8 by hunks. The probes run on one merchant's own
-- rows inside sub-transactions rolled back whole (asserted). No LOCK TABLE, no set role, no set local,
-- no begin. Timings are notices only.
-- SUPERSEDES, by hunks sliced from the LIVE bodies (prod head 0180, LF-normalised, each asserted to
-- occur exactly once and to reverse to its pre-image, ACL unchanged): public.npc_plan,
-- public.npc_tend_route, public.npc_tend_sum, public.npc_tend (comment), public.npc_leg_lines
-- (comment), public.npc_buy_ceiling, cmd.standing_route_lines, cmd.do_repair.
-- ROLLBACK: a forward slice restores the eight bodies (each hunk's OLD text is here verbatim) and
-- drops public.fleet_repair_due. Routes laid up by it are lifted by the next tend.
-- VERSION: 0181 (provisional; renumbered to head + 1 at deploy). Applies on prod head 0180.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
end $guard$;

-- ── 0. HELPERS (pg_temp, gone at commit) ───────────────────────────────────────────────────────
create or replace function pg_temp.occurs_0181(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 1. THE PRE-IMAGES ──────────────────────────────────────────────────────────────────────────
create temp table defs_before_0181 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl
  from (values ('public.npc_plan(timestamp with time zone,uuid)'),
               ('public.npc_tend_route(timestamp with time zone,uuid,uuid,bigint)'),
               ('public.npc_tend_sum(jsonb,jsonb)'),
               ('public.npc_tend(timestamp with time zone,uuid)'),
               ('public.npc_leg_lines(uuid,uuid,uuid,numeric,integer,numeric)'),
               ('public.npc_buy_ceiling(uuid,uuid,numeric)'),
               ('cmd.standing_route_lines(uuid,integer,uuid)'),
               ('cmd.do_repair(uuid,jsonb)')) f(fn);

do $$
begin
  if (select count(*) from defs_before_0181 where def is not null) <> 8 then
    raise exception '0181 self-assert FAIL: % of the 8 bodies found', (select count(*) from defs_before_0181 where def is not null);
  end if;
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'fleet_repair_due') then
    raise exception '0181 self-assert FAIL: public.fleet_repair_due exists already';
  end if;
end $$;

-- the old renderer under a pg_temp name, for the side-by-side probe (positive control)
do $$
declare
  v_def text := replace((select def from defs_before_0181 where fn like 'cmd.standing_route_lines%'),
                        'CREATE OR REPLACE FUNCTION cmd.standing_route_lines(', 'CREATE OR REPLACE FUNCTION pg_temp.standing_route_lines_old_0181(');
begin
  if v_def not like '%pg_temp.standing_route_lines_old_0181(%' then
    raise exception '0181 self-assert FAIL: the old copy of cmd.standing_route_lines was not renamed';
  end if;
  execute v_def;
end $$;

-- ── 2. THE READER OF WHAT A REPAIR WOULD MEND ──────────────────────────────────────────────────
create function public.fleet_repair_due(p_fleet uuid, p_to numeric default 100)
returns table (points numeric, pct numeric, gear jsonb)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0181: THE reading of what a repair of p_fleet to p_to % would mend, lifted out of cmd.do_repair
  -- (0067's walk over her hulls): the hull points short of p_to % of each class's durability, the
  -- worst hull's shortfall in per cent, and (0158, S13) while gear_wear_bite is on her worn gear and
  -- its price (public.gear_repair_quote; null when nothing is worn or wear is dark). Read by
  -- cmd.do_repair (E_UNAVAILABLE: nothing due) and by cmd.standing_route_lines (REPAIR only when due).
  select coalesce(sum(greatest(c.durability * p_to / 100 - s.durability, 0)), 0),
         coalesce(max(greatest(c.durability * p_to / 100 - s.durability, 0) / nullif(c.durability, 0) * 100), 0),
         case when public.gear_wear_on() then public.gear_repair_quote(p_fleet) end
    from public.ships s join public.ship_classes c on c.id = s.class_id
   where s.fleet_id = p_fleet
$$;
comment on function public.fleet_repair_due(uuid, numeric) is
  '0181: what a repair of this fleet to p_to % would mend (points, worst per cent, gear). Server-only.';
revoke all on function public.fleet_repair_due(uuid, numeric) from public, anon, authenticated;

-- ── 3. THE HUNKS (sliced from the live bodies; each occurs once; each body reverses; ACL unchanged)
create temporary table hunks_0181 (fn text not null, n int not null, old text not null, new text not null,
                                   primary key (fn, n)) on commit drop;
insert into hunks_0181 values
-- (1) npc_plan: she waits in port
('public.npc_plan(timestamp with time zone,uuid)', 1,
$h$--   * Nothing pays on any leg of the loop written: it is written as it stands — SELL at a profit at
--     every stop and no BUY — and she sails it in ballast (0115). Counted `ballast`.
$h$,
$h$--   * Nothing pays on any leg of the loop written: it is written as it stands — SELL at a profit at
--     every stop and no BUY. Counted `ballast`. Mid-lap, off her loop, on the switch's pass or with
--     cargo aboard she sails it in ballast (0115). 0181: AT HER LAP START, WITH NOTHING ABOARD, SHE
--     WAITS IN PORT — laid up ('laid_up', written once) and counted `waiting`; public.npc_tend_route
--     re-plans her at every tend and resumes her on the first loop that pays.
$h$),
('public.npc_plan(timestamp with time zone,uuid)', 2,
$h$  v_cands   int := 0;
$h$,
$h$  v_cands   int := 0;
  v_waiting int := 0;      -- 0181: laid up at her lap start, nothing paying on any loop
  v_aboard  numeric;       -- 0181: the tuns she carries now (public.ship_cargo_tuns)
$h$),
('public.npc_plan(timestamp with time zone,uuid)', 3,
$h$      v_hold  := v_hold + public.fleet_free_hold(r.fleet_id);
$h$,
$h$      v_aboard := v_hold;   -- 0181: what she carries, before her free hold is added
      v_hold  := v_hold + public.fleet_free_hold(r.fleet_id);
$h$),
('public.npc_plan(timestamp with time zone,uuid)', 4,
$h$      -- 0115: A MERCHANT IS NEVER PARKED. Nothing pays: the loop is written as it stands — SELL
      -- at a profit at every stop and no BUY — and she sails it in ballast. Counted `ballast`.
      if not v_any then
        v_laid := v_laid + 1;
      end if;
      v_res := cmd.standing_route_save_for(sr.player_id, sr.id, null, v_stops, null, null, v_pace);
      if not coalesce((v_res->>'ok')::boolean, false) then
        raise exception 'npc_plan: the save door refused % — %', sr.name, v_res->>'error_message';
      end if;
      v_planned := v_planned + 1;
$h$,
$h$      -- 0115: Nothing pays: the loop is written as it stands — SELL at a profit at every stop and no
      -- BUY. Counted `ballast`.
      if not v_any then
        v_laid := v_laid + 1;
      end if;
      v_res := cmd.standing_route_save_for(sr.player_id, sr.id, null, v_stops, null, null, v_pace);
      if not coalesce((v_res->>'ok')::boolean, false) then
        raise exception 'npc_plan: the save door refused % — %', sr.name, v_res->>'error_message';
      end if;
      v_planned := v_planned + 1;
      -- 0181: AT HER LAP START, WITH NOTHING ABOARD, SHE WAITS IN PORT instead of sailing a lap that
      -- pays only its stores (the owner, 2026-10-18: "redesign the routes ... that gives negative
      -- cash"). Every loop on offer was priced above and none carries a paying parcel: she is laid
      -- up where she lies, once (a lay-up already standing is not written again), and counted
      -- `waiting`. cmd.run_standing_route does not open a lap its plan paused (0114), and
      -- public.npc_tend_route re-plans her at every tend. With cargo aboard she sails (her SELLs and
      -- 0142's cut-loss clear it); mid-lap, off her loop or on the switch's pass, as before.
      if not v_any and v_choose and not v_off and coalesce(v_aboard, 0) <= 0 then
        v_waiting := v_waiting + 1;
        if sr.paused_reason is distinct from 'laid_up' then
          v_res := cmd.standing_route_pause_for(sr.player_id, sr.id, true, 'laid_up',
                     'No cargo pays on any leg of her loops at present; she waits in port.');
          if not coalesce((v_res->>'ok')::boolean, false) then
            raise exception 'npc_plan: the pause door refused % — %', sr.name, v_res->>'error_message';
          end if;
        end if;
      end if;
$h$),
('public.npc_plan(timestamp with time zone,uuid)', 5,
$h$                            'chosen', v_chosen, 'candidates', v_cands,
$h$,
$h$                            'chosen', v_chosen, 'candidates', v_cands, 'waiting', v_waiting,   -- 0181
$h$),
-- (1) npc_tend_route: a waiting merchant is not resumed
('public.npc_tend_route(timestamp with time zone,uuid,uuid,bigint)', 1,
$h$  v_built   int := 0;   -- 0180 (d): hulls she laid down this hour
$h$,
$h$  v_built   int := 0;   -- 0180 (d): hulls she laid down this hour
  v_waiting int := 0;   -- 0181: laid up in port, nothing on her loops paying
$h$),
('public.npc_tend_route(timestamp with time zone,uuid,uuid,bigint)', 2,
$h$        if coalesce((v_res->>'planned')::int, 0) = 0 then
          v_notes := v_notes || jsonb_build_object('route', sr.name, 'not_planned', coalesce(sr.paused_reason, 'unstarted'));
          continue;
        end if;
$h$,
$h$        if coalesce((v_res->>'planned')::int, 0) = 0 then
          v_notes := v_notes || jsonb_build_object('route', sr.name, 'not_planned', coalesce(sr.paused_reason, 'unstarted'));
          continue;
        end if;
        -- 0181: SHE WAITS IN PORT. The plan priced every loop on offer from where she lies and none
        -- pays, so it laid her up (or kept her laid up): she is not resumed; the next tend asks again.
        if coalesce((v_res->>'waiting')::int, 0) > 0 then
          v_waiting := v_waiting + 1;
          continue;
        end if;
$h$),
('public.npc_tend_route(timestamp with time zone,uuid,uuid,bigint)', 3,
$h$                            'built', v_built,   -- 0180 (d)
$h$,
$h$                            'built', v_built,   -- 0180 (d)
                            'waiting', v_waiting,   -- 0181
$h$),
('public.npc_tend_sum(jsonb,jsonb)', 1,
$h$                             'built', 'ceiling', 'ceiling_given'] loop   -- 0145: donated; 0180: built, ceiling, ceiling_given
$h$,
$h$                             'built', 'ceiling', 'ceiling_given', 'waiting'] loop   -- 0145: donated; 0180: built, ceiling, ceiling_given; 0181: waiting
$h$),
('public.npc_tend(timestamp with time zone,uuid)', 1,
$h$--   paused dark/losing/reserve/edited/laid_up -> planned, then resumed, at once (0115: a lay-up is
--     legacy — nothing writes one any more); whether THIS call re-planned her is read off the
$h$,
$h$--   paused dark/losing/reserve/edited/laid_up -> planned, then resumed, at once — 0181: unless the
--     plan lays her up again (nothing on her loops pays: she waits); whether THIS call re-planned her is read off the
$h$),
-- (2) the ceiling: the ask now × (1 + patience)
('public.npc_leg_lines(uuid,uuid,uuid,numeric,integer,numeric)', 1,
$h$                 -- 0180: A LINE IS NEVER BORN REFUSED. The ceiling is the ask at the stock the maker is
                 -- supposed to hold × (1 + patience); under target the ask is dearer than that, and a line
                 -- whose limit is below the parcel's own priced ask is refused E_PRICE_LIMIT on arrival.
                 -- Such a parcel is not kept; the ranking's next good is tried.
$h$,
$h$                 -- 0180: A LINE IS NEVER BORN REFUSED. A line whose limit is below the parcel's own priced
                 -- ask is refused E_PRICE_LIMIT on arrival; such a parcel is not kept, and the ranking's
                 -- next good is tried. 0181: the ceiling is the quay's ask now × (1 + patience), so this
                 -- drops only a parcel whose own size walks the price past her patience.
$h$),
('public.npc_buy_ceiling(uuid,uuid,numeric)', 1,
$h$-- The ask now, carried to the stock the port is SUPPOSED to hold, times (1 + patience). Composed of
-- the two price authorities' own answers (world.quote for the ask with its spread and tax,
-- world.mid_price for the stock term); no spread, tax or elasticity is restated. At stock = target
-- the ceiling IS the ask × (1 + patience), to the cent (asserted below). Null = no honest ceiling
-- (nothing to quote), and the planner then does not buy that good.
declare
  q        record;
  v_stock  numeric;
  v_target numeric;
  v_now    numeric;
  v_norm   numeric;
begin
  select pg.stock, pg.stock_target into v_stock, v_target
    from public.port_goods pg where pg.port_id = p_port and pg.good_id = p_good;
  if v_target is null then return null; end if;
  select * into q from world.quote(p_port, p_good, 1, 'buy', null, null);
  v_now  := world.mid_price(p_port, p_good, v_stock);
  v_norm := world.mid_price(p_port, p_good, v_target);
  if q.units is null or q.units <= 0 or q.avg_price is null or v_now is null or v_now <= 0 then
    return null;
  end if;
  return round(q.avg_price * v_norm / v_now * (1 + coalesce(p_patience, 0)), 2);
$h$,
$h$-- 0181: THE ASK NOW, times (1 + patience) — the most a merchant pays a unit at this quay: the quote
-- authority's own answer for one unit (world.quote, its spread and tax), nothing restated. Read by
-- the planner (public.npc_leg_lines: a parcel whose own priced ask is above it is not kept) and, live
-- as she arrives, by the route's renderer (cmd.standing_route_lines), under what her next stop's bid
-- lets her pay. Null = nothing to quote, and the planner does not buy that good. (0097–0180 carried
-- the ask to the stock the port is SUPPOSED to hold; under target that sat below the ask itself, and
-- as rivals drew a maker down a line written at plan time died before she arrived.)
declare
  q        record;
begin
  select * into q from world.quote(p_port, p_good, 1, 'buy', null, null);
  if q.units is null or q.units <= 0 or q.avg_price is null then
    return null;
  end if;
  return round(q.avg_price * (1 + coalesce(p_patience, 0)), 2);
$h$),
-- (2) + (3) the renderer: the BUY limit live, REPAIR only when due
('cmd.standing_route_lines(uuid,integer,uuid)', 1,
$h$  v_aff   record;    -- 0129
$h$,
$h$  v_aff   record;    -- 0129
  v_patience numeric; -- 0181: her house's patience (null on a player's route)
$h$),
('cmd.standing_route_lines(uuid,integer,uuid)', 2,
$h$  v_npc := exists (select 1 from public.standing_routes r join public.players p on p.id = r.player_id and p.is_npc
                    where r.id = p_route);   -- 0114
$h$,
$h$  v_npc := exists (select 1 from public.standing_routes r join public.players p on p.id = r.player_id and p.is_npc
                    where r.id = p_route);   -- 0114
  select h.patience into v_patience
    from public.standing_routes r join public.npc_houses h on h.player_id = r.player_id
   where r.id = p_route;   -- 0181
$h$),
('cmd.standing_route_lines(uuid,integer,uuid)', 3,
$h$  -- 3. REPAIR (to 100%, the grammar's default).
  if st.repair then
$h$,
$h$  -- 3. REPAIR (to 100%, the grammar's default) — 0181: only when something aboard is due one
  --    (public.fleet_repair_due, the reading cmd.do_repair refuses E_UNAVAILABLE by), as PROVISION
  --    above is written only below the keep level. A sound fleet was sent to the yard and refused on
  --    almost every merchant lap (2,407 refusals in two hours on prod, 2026-10-18).
  if st.repair and exists (select 1 from public.fleet_repair_due(p_fleet, 100) d
                            where d.points > 0 or d.gear is not null) then
$h$),
('cmd.standing_route_lines(uuid,integer,uuid)', 4,
$h$      ln.price_limit := least(coalesce(ln.price_limit, v_cap), v_cap);
$h$,
$h$      -- 0181: THE LIMIT IS PRICED AS SHE ARRIVES — her patience over the quay's ask now
      -- (public.npc_buy_ceiling, read live, not the limit the planner stored), never above what her
      -- next stop's bid lets her pay. Rivals drawing the maker down and the market's drift had moved
      -- the ask past the stored limit on 345 of 1,681 live lines (prod, 2026-10-18 09:20).
      ln.price_limit := least(coalesce(public.npc_buy_ceiling(st.port_id, ln.good_id, v_patience), v_cap), v_cap);
$h$),
-- (3) do_repair reads the one reading
('cmd.do_repair(uuid,jsonb)', 1,
$h$  r        record;
$h$,
$h$  -- 0181: the walk over her hulls (r record) is public.fleet_repair_due's
$h$),
('cmd.do_repair(uuid,jsonb)', 2,
$h$  for r in select s.id, s.durability, c.durability as maxd
             from public.ships s join public.ship_classes c on c.id = s.class_id
            where s.fleet_id = p_fleet loop
    if r.durability < r.maxd * v_to / 100 then
      v_points := v_points + (r.maxd * v_to / 100 - r.durability);
      v_pct    := greatest(v_pct, (r.maxd * v_to / 100 - r.durability) / r.maxd * 100);
    end if;
  end loop;
  -- 0158 (S13): THE GEAR. While gear_wear_bite is on, a repair also repairs every worn fitting of the fleet
  -- (public.gear_repair_quote: public.unit_repair_cost, the one price). Off, nothing is read.
  if public.gear_wear_on() then
    v_gear := public.gear_repair_quote(p_fleet);
  end if;
$h$,
$h$  -- 0181: WHAT A REPAIR TO v_to % WOULD MEND — the hulls' points, the worst hull's per cent and
  -- (0158, S13) while gear_wear_bite is on the fleet's worn gear and its price — read once, from
  -- public.fleet_repair_due, the reading the route's renderer asks too.
  select d.points, d.pct, d.gear into v_points, v_pct, v_gear from public.fleet_repair_due(p_fleet, v_to) d;
$h$);

do $$
declare
  d     record;
  h     record;
  v_def text;
  v_rev text;
begin
  for d in select * from defs_before_0181 order by fn loop
    v_def := d.def;
    for h in select * from hunks_0181 where fn = d.fn order by n loop
      if pg_temp.occurs_0181(v_def, h.old) <> 1 then
        raise exception '0181 self-assert FAIL: hunk % of % occurs % time(s), not once — the deployed body is not what this file was written against',
          h.n, d.fn, pg_temp.occurs_0181(v_def, h.old);
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    if v_def = d.def then
      raise exception '0181 self-assert FAIL: no hunk for %', d.fn;
    end if;
    execute v_def;
    v_rev := replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '');
    for h in select * from hunks_0181 where fn = d.fn order by n desc loop
      if pg_temp.occurs_0181(v_rev, h.new) <> 1 then
        raise exception '0181 self-assert FAIL: hunk % of % is not in the new body once', h.n, d.fn;
      end if;
      v_rev := replace(v_rev, h.new, h.old);
    end loop;
    if v_rev <> d.def then
      raise exception '0181 self-assert FAIL: % does not reverse to its pre-image', d.fn;
    end if;
    if coalesce((select p.proacl::text from pg_proc p where p.oid = d.fn::regprocedure), '') <> d.acl then
      raise exception '0181 self-assert FAIL: the ACL of % moved', d.fn;
    end if;
  end loop;
end $$;

-- ── 4. THE PROBES (one merchant's own rows; every one rolled back whole) ───────────────────────
create temp table probe_0181 (k text primary key, j jsonb) on commit drop;

-- (i) SHE WAITS IN PORT. Her preconditions are her own: the routes and the merchants on, NOTHING PAYS on
-- any leg (npc_buyers_per_good 0 — the planner's own filter strikes every good), and she lies docked at
-- her stop 0 between laps with nothing aboard. Her lap-start plan lays her up and opens no lap; the
-- tend keeps her waiting without writing the lay-up twice; the arrivals path opens nothing; and with
-- cargo aboard (the positive control) the tend resumes her.
do $$
declare
  v_f    record;
  v_r    jsonb;
  v_ev0  int;
  v_lap0 int;
  v_t0   timestamptz;
  v_out  jsonb := '{}'::jsonb;
begin
  begin
    update public.world_config set value = 'true'::jsonb where key in ('standing_routes_enabled', 'npc_traders_enabled');
    update public.world_config set value = to_jsonb(0) where key = 'npc_buyers_per_good';
    select nf.fleet_id, nf.route_id, nf.player_id,
           (select s.port_id from public.standing_route_stops s where s.route_id = nf.route_id and s.ord = 0) as home
      into v_f
      from public.npc_fleets nf
     where (select count(*) from public.standing_route_stops s where s.route_id = nf.route_id) >= 2
     order by nf.roster_ord limit 1;
    if v_f.fleet_id is null then
      raise exception '0181 self-assert FAIL: no merchant route of two stops to probe';
    end if;
    update public.voyages set status = 'ABORTED' where fleet_id = v_f.fleet_id and status = 'SAILING';
    update public.orders set status = 'cancelled' where fleet_id = v_f.fleet_id and status in ('pending', 'active', 'failed');
    update public.fleets set status = 'DOCKED', port_id = v_f.home, lat = null, lon = null, busy_until = null where id = v_f.fleet_id;
    update public.ships set cargo = '{}'::jsonb where fleet_id = v_f.fleet_id;
    update public.standing_route_laps set closed_at = now() where route_id = v_f.route_id and closed_at is null;
    update public.standing_routes set fleet_id = v_f.fleet_id, lap_id = null, stop_cursor = 0, paused_reason = null,
                                      hold_until = null
     where id = v_f.route_id;
    select lap_no into v_lap0 from public.standing_routes where id = v_f.route_id;
    select count(*) into v_ev0 from public.events e where e.player_id = v_f.player_id and e.kind = 'ROUTE_PAUSED';

    v_t0 := clock_timestamp();
    v_r := public.npc_plan(now(), v_f.route_id);
    v_out := v_out || jsonb_build_object('plan', v_r - 'notes', 'plan_ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000),
      'reason', (select paused_reason from public.standing_routes where id = v_f.route_id),
      'lap_moved', (select lap_no from public.standing_routes where id = v_f.route_id) - v_lap0,
      'lap_open', (select lap_id is not null from public.standing_routes where id = v_f.route_id),
      'status', (select status from public.fleets where id = v_f.fleet_id),
      'pending', (select count(*) from public.orders where fleet_id = v_f.fleet_id and status = 'pending'),
      'buys', (select count(*) from public.standing_route_lines where route_id = v_f.route_id and kind = 'BUY'),
      'events', (select count(*) from public.events e where e.player_id = v_f.player_id and e.kind = 'ROUTE_PAUSED') - v_ev0);

    v_r := public.npc_tend_route(now(), v_f.fleet_id, v_f.route_id, 1);
    v_out := v_out || jsonb_build_object('tend', v_r - 'notes',
      'reason2', (select paused_reason from public.standing_routes where id = v_f.route_id),
      'events2', (select count(*) from public.events e where e.player_id = v_f.player_id and e.kind = 'ROUTE_PAUSED') - v_ev0,
      'run', cmd.run_standing_route(v_f.fleet_id, now()),
      'lap_moved2', (select lap_no from public.standing_routes where id = v_f.route_id) - v_lap0);

    -- POSITIVE CONTROL: one unit of a good aboard — she sails her loop to sell it, so the tend resumes her
    update public.ships set cargo = jsonb_build_object((select g.code from public.goods g order by g.code limit 1), 1)
     where id = (select s.id from public.ships s where s.fleet_id = v_f.fleet_id order by s.name limit 1);
    v_r := public.npc_tend_route(now(), v_f.fleet_id, v_f.route_id, 1);
    v_out := v_out || jsonb_build_object('tend3', v_r - 'notes',
      'reason3', (select paused_reason from public.standing_routes where id = v_f.route_id),
      'sum', public.npc_tend_sum(jsonb_build_object('waiting', 1), jsonb_build_object('waiting', 2)));
    raise exception 'PROBE_ROLLBACK_0181:%', v_out::text;
  exception when others then
    if sqlerrm not like 'PROBE_ROLLBACK_0181:%' then raise; end if;
    insert into probe_0181 values ('wait', substr(sqlerrm, length('PROBE_ROLLBACK_0181:') + 1)::jsonb);
  end;
end $$;

-- (ii) REPAIR ONLY WHEN DUE. Her fleet docked at a shipyard, gear wear dark (her own precondition):
-- sound, her stop marked for repair renders no REPAIR (the old renderer did: positive control) and
-- cmd.do_repair still refuses E_UNAVAILABLE; one hull at half, the line is written and cmd.do_repair
-- mends exactly the points public.fleet_repair_due reads (and the probe recomputes by hand).
do $$
declare
  v_f    record;
  v_yard uuid;
  v_d1   record;
  v_d2   record;
  v_want numeric;
  v_err  text := 'none';
  v_rep  jsonb;
  v_out  jsonb := '{}'::jsonb;
begin
  begin
    update public.world_config set value = 'false'::jsonb where key = 'gear_wear_bite';
    select nf.fleet_id, nf.route_id, nf.player_id into v_f
      from public.npc_fleets nf
     where (select count(*) from public.standing_route_stops s where s.route_id = nf.route_id) >= 2
     order by nf.roster_ord limit 1;
    select b.port_id into v_yard from public.port_buildings b join public.ports p on p.id = b.port_id
     where b.kind = 'shipyard' and p.kind = 'HARBOUR' order by p.code limit 1;
    update public.voyages set status = 'ABORTED' where fleet_id = v_f.fleet_id and status = 'SAILING';
    update public.fleets set status = 'DOCKED', port_id = v_yard, lat = null, lon = null, busy_until = null where id = v_f.fleet_id;
    update public.ships s set durability = c.durability from public.ship_classes c where c.id = s.class_id and s.fleet_id = v_f.fleet_id;
    update public.standing_route_stops set repair = true where route_id = v_f.route_id and ord = 0;
    select * into v_d1 from public.fleet_repair_due(v_f.fleet_id, 100);
    v_out := v_out || jsonb_build_object(
      'sound_line', 'REPAIR' = any(cmd.standing_route_lines(v_f.route_id, 0, v_f.fleet_id)),
      'sound_line_old', 'REPAIR' = any(pg_temp.standing_route_lines_old_0181(v_f.route_id, 0, v_f.fleet_id)),
      'sound_points', v_d1.points, 'sound_gear', v_d1.gear);
    begin
      perform cmd.do_repair(v_f.fleet_id, '{}'::jsonb);
    exception when others then
      v_err := split_part(sqlerrm, ':', 1);
    end;
    v_out := v_out || jsonb_build_object('sound_err', v_err);
    update public.ships s set durability = c.durability * 0.5 from public.ship_classes c
     where c.id = s.class_id and s.id = (select s2.id from public.ships s2 where s2.fleet_id = v_f.fleet_id order by s2.name limit 1);
    select coalesce(sum(greatest(c.durability - s.durability, 0)), 0) into v_want
      from public.ships s join public.ship_classes c on c.id = s.class_id where s.fleet_id = v_f.fleet_id;
    select * into v_d2 from public.fleet_repair_due(v_f.fleet_id, 100);
    v_out := v_out || jsonb_build_object('worn_line', 'REPAIR' = any(cmd.standing_route_lines(v_f.route_id, 0, v_f.fleet_id)));
    perform public.credit(v_f.player_id, 'PROBE_0181', 1000000);
    v_rep := cmd.do_repair(v_f.fleet_id, '{}'::jsonb);
    v_out := v_out || jsonb_build_object(
      'worn_points', v_d2.points, 'worn_pct', v_d2.pct, 'want', v_want, 'repair', v_rep,
      'mended', (select bool_and(s.durability >= c.durability) from public.ships s join public.ship_classes c on c.id = s.class_id
                  where s.fleet_id = v_f.fleet_id));
    raise exception 'PROBE_ROLLBACK_0181:%', v_out::text;
  exception when others then
    if sqlerrm not like 'PROBE_ROLLBACK_0181:%' then raise; end if;
    insert into probe_0181 values ('repair', substr(sqlerrm, length('PROBE_ROLLBACK_0181:') + 1)::jsonb);
  end;
end $$;

-- (iii) THE BUY LIMIT IS PRICED AS SHE ARRIVES. Her stop 0 → stop 1 market hand-set (her maker at 3 ×
-- target, her sink starved), her stop 0 written through the save door with BUY <good> 5 AT 0.01 — a
-- limit far under the ask, as a plan-time limit is once the ask has moved past it. The old renderer
-- writes AT ≤ 0.01 (refused on arrival: positive control); the new one her patience over the ask NOW
-- (public.npc_buy_ceiling, live), under her next stop's bid — never under the ask she meets.
do $$
declare
  v_f     record;
  v_g     record;
  v_new   text;
  v_old   text;
  v_lim   numeric;
  v_qty   numeric;
  v_cap   numeric;
  q       record;
  v_res   jsonb;
  v_out   jsonb := '{}'::jsonb;
begin
  begin
    select nf.fleet_id, nf.route_id, nf.player_id, h.patience,
           (select s.port_id from public.standing_route_stops s where s.route_id = nf.route_id and s.ord = 0) as a,
           (select s.port_id from public.standing_route_stops s where s.route_id = nf.route_id and s.ord = 1) as b
      into v_f
      from public.npc_fleets nf join public.npc_houses h on h.player_id = nf.player_id
     where (select count(*) from public.standing_route_stops s where s.route_id = nf.route_id) >= 2
     order by nf.roster_ord limit 1;
    select pg.good_id, g.code into v_g
      from public.port_goods pg join public.goods g on g.id = pg.good_id
     where pg.port_id = v_f.a and public.port_offers(v_f.a, pg.good_id) and pg.stock_target >= 100
       and exists (select 1 from public.port_goods x where x.port_id = v_f.b and x.good_id = pg.good_id)
       and not public.culture_refuses((select culture from public.ports where id = v_f.b), g.culture_mask)
     order by g.code limit 1;
    if v_g.good_id is null then
      raise exception '0181 self-assert FAIL: her stop 0 offers no good her stop 1 trades';
    end if;
    update public.port_goods set stock = stock_target * 3 where port_id = v_f.a and good_id = v_g.good_id;
    update public.port_goods set stock = greatest(1, round(stock_target * 0.05)) where port_id = v_f.b and good_id = v_g.good_id;
    perform public.credit(v_f.player_id, 'PROBE_0181', 1000000);
    v_res := cmd.standing_route_save_for(v_f.player_id, v_f.route_id, null,
      (select jsonb_agg(jsonb_build_object('port', p.code, 'course', s.course, 'repair', false, 'crew_up', true,
                'lines', case when s.ord = 0
                              then jsonb_build_array(jsonb_build_object('kind', 'SELL', 'at_profit', true),
                                                     jsonb_build_object('kind', 'BUY', 'good', v_g.code, 'qty', 5, 'price_limit', 0.01))
                              else jsonb_build_array(jsonb_build_object('kind', 'SELL', 'at_profit', true)) end) order by s.ord)
         from public.standing_route_stops s join public.ports p on p.id = s.port_id where s.route_id = v_f.route_id),
      null, null, 0);
    if not coalesce((v_res->>'ok')::boolean, false) then
      raise exception '0181 self-assert FAIL: the save door refused the probe''s lines: %', v_res;
    end if;
    select x into v_new from unnest(cmd.standing_route_lines(v_f.route_id, 0, v_f.fleet_id)) x where x like 'BUY ' || v_g.code || ' %';
    select x into v_old from unnest(pg_temp.standing_route_lines_old_0181(v_f.route_id, 0, v_f.fleet_id)) x where x like 'BUY ' || v_g.code || ' %';
    v_lim := substring(v_new from ' AT ([0-9.]+)$')::numeric;
    v_qty := split_part(v_new, ' ', 3)::numeric;
    select * into q from world.quote(v_f.b, v_g.good_id, 5, 'sell', null, null);
    v_cap := floor(q.total / q.units / (1 + public.wc_num('npc_min_return_pct') / 100) * 100) / 100;
    v_out := v_out || jsonb_build_object('good', v_g.code, 'new', v_new, 'old', v_old, 'limit', v_lim, 'qty', v_qty,
      'old_limit', substring(v_old from ' AT ([0-9.]+)$')::numeric,
      'ask', (select qq.avg_price from world.quote(v_f.a, v_g.good_id, v_qty, 'buy', null, null) qq),
      'ceiling', public.npc_buy_ceiling(v_f.a, v_g.good_id, v_f.patience),
      'ceiling_want', (select round(qq.avg_price * (1 + v_f.patience), 2) from world.quote(v_f.a, v_g.good_id, 1, 'buy', null, null) qq),
      'cap', v_cap, 'patience', v_f.patience);
    raise exception 'PROBE_ROLLBACK_0181:%', v_out::text;
  exception when others then
    if sqlerrm not like 'PROBE_ROLLBACK_0181:%' then raise; end if;
    insert into probe_0181 values ('limit', substr(sqlerrm, length('PROBE_ROLLBACK_0181:') + 1)::jsonb);
  end;
end $$;

-- ── 5. THE SELF-ASSERT ──────────────────────────────────────────────────────────────────────────
do $$
declare
  w jsonb := (select j from probe_0181 where k = 'wait');
  r jsonb := (select j from probe_0181 where k = 'repair');
  l jsonb := (select j from probe_0181 where k = 'limit');
begin
  if exists (select 1 from public.ledger where kind = 'PROBE_0181') then
    raise exception '0181 self-assert FAIL: a probe''s money survived its rolled-back block';
  end if;
  -- (i)
  if (w->'plan'->>'planned')::int <> 1 or (w->'plan'->>'waiting')::int <> 1 or w->>'reason' <> 'laid_up'
     or (w->>'lap_moved')::int <> 0 or (w->>'lap_open')::boolean or w->>'status' <> 'DOCKED'
     or (w->>'pending')::int <> 0 or (w->>'buys')::int <> 0 or (w->>'events')::int <> 1 then
    raise exception '0181 self-assert FAIL: with nothing paying, her lap-start plan did not lay her up in port with no lap opened: %', w;
  end if;
  if (w->'tend'->>'waiting')::int <> 1 or (w->'tend'->>'resumed')::int <> 0 or w->>'reason2' <> 'laid_up'
     or (w->>'events2')::int <> 1 or (w->>'run')::int <> 0 or (w->>'lap_moved2')::int <> 0 then
    raise exception '0181 self-assert FAIL: the tend did not keep her waiting (once), or the arrivals path opened a lap: %', w;
  end if;
  if (w->'tend3'->>'waiting')::int <> 0 or (w->'tend3'->>'resumed')::int <> 1 or w->>'reason3' is not null then
    raise exception '0181 self-assert FAIL: with cargo aboard the tend did not resume her (positive control): %', w;
  end if;
  if (w->'sum'->>'waiting')::int <> 3 then
    raise exception '0181 self-assert FAIL: npc_tend_sum does not add waiting: %', w->'sum';
  end if;
  -- (ii)
  if (r->>'sound_line')::boolean or not (r->>'sound_line_old')::boolean or (r->>'sound_points')::numeric <> 0
     or r->'sound_gear' <> 'null'::jsonb or r->>'sound_err' <> 'E_UNAVAILABLE' then
    raise exception '0181 self-assert FAIL: a sound fleet: REPAIR written %, by the old renderer % (want false, true), points %, gear %, do_repair %',
      r->>'sound_line', r->>'sound_line_old', r->>'sound_points', r->'sound_gear', r->>'sound_err';
  end if;
  if not (r->>'worn_line')::boolean or (r->>'worn_points')::numeric <= 0 or (r->>'worn_points')::numeric <> (r->>'want')::numeric
     or round((r->>'worn_pct')::numeric) <> 50 or (r->'repair'->>'points')::numeric <> round((r->>'want')::numeric, 1)
     or not (r->>'mended')::boolean then
    raise exception '0181 self-assert FAIL: a hull at half: REPAIR written %, due % (by hand %), worst % %%, do_repair %, mended %',
      r->>'worn_line', r->>'worn_points', r->>'want', r->>'worn_pct', r->'repair', r->>'mended';
  end if;
  -- (iii)
  if l->>'new' is null or (l->>'limit')::numeric < (l->>'ask')::numeric
     or (l->>'limit')::numeric <> least(coalesce((l->>'ceiling')::numeric, (l->>'cap')::numeric), (l->>'cap')::numeric) then
    raise exception '0181 self-assert FAIL: the live limit: % (ask %, ceiling %, cap %)', l->>'new', l->>'ask', l->>'ceiling', l->>'cap';
  end if;
  if (l->>'ceiling')::numeric is distinct from (l->>'ceiling_want')::numeric then
    raise exception '0181 self-assert FAIL: npc_buy_ceiling % is not the ask now × (1 + %) = %', l->>'ceiling', l->>'patience', l->>'ceiling_want';
  end if;
  if l->>'old' is null or (l->>'old_limit')::numeric > 0.01 then
    raise exception '0181 self-assert FAIL: the positive control: the old renderer wrote % (want AT <= 0.01)', l->>'old';
  end if;

  raise notice '0181 self-assert ok: A MERCHANT DOES NOT SAIL FOR NOTHING. (i) WAIT: nothing paying on any of her % loop(s), her lap-start plan laid her up DOCKED at her stop 0, no lap opened, no order written, one ROUTE_PAUSED (% ms); the tend kept her waiting without writing it twice and the arrivals path opened nothing; one unit aboard, the tend resumed her (positive control). (ii) REPAIR: sound, no REPAIR written (the old renderer wrote one) and do_repair still refuses E_UNAVAILABLE; one hull at half, REPAIR written, % points due = % by hand, worst % %%, do_repair mended %. (iii) LIMIT: BUY % stored AT 0.01 — the old renderer wrote %, the new one % (ask %, her patience % over the ask now = %, her next stop lets her pay %). Bodies reverse, ACLs unchanged.',
    w->'plan'->>'candidates', w->>'plan_ms', round((r->>'worn_points')::numeric, 1), round((r->>'want')::numeric, 1),
    round((r->>'worn_pct')::numeric), r->'repair'->>'points',
    l->>'good', l->>'old', l->>'new', l->>'ask', l->>'patience', l->>'ceiling', round((l->>'cap')::numeric, 2);
end $$;
