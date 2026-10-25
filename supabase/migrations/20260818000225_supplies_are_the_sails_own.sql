-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0225 — SUPPLIES ARE THE SAIL'S OWN  (every SAIL buys the stores its leg asks; the standing order, its book and
--        the keep level are retired; the board says what the supplies cost and whether they fit)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER (docs/OWNER_REQUESTS.md, 2026-10-25) ───────────────────────────────────────────────────────────────
-- * 203: *"in fleet tab, what is this 'keep supply at'? this is useless i mean... come on. i can't play this game"*
-- * 194: *"this game must be playable, yet it is hard to do so with just whats in the plan page"* — the test: a new
--   player makes a whole buy → sail → sell trip from the Plan (now Trade) page alone.
-- * 190: *"i can only plan on buying but not for selling"*. Design: docs/COMMAND_REDESIGN.md, slice R1.
--
-- ── WHAT THIS FILE DOES ──────────────────────────────────────────────────────────────────────────────────────────
-- (1) ONE RULE FOR THE STORES A LEG ASKS. public.supply_need(fleet, nm): for a passage of nm miles at the speed she
--     sails at now, the days the sail door asks (voyage.stores_need_days — THE one measure of endurance_margin,
--     0203), the days a PROVISION for that leg takes on (public.npc_leg_days: those days rounded up, one day spare —
--     the preset a leg asked under 0142, now the SAIL's own top-up), what those stores cost her now (every hull
--     through public.stores_topup as cmd.do_provision tops it, priced by public.stores_cost; 0 when her casks
--     already cover it) and whether, topped up, her casks would carry the leg beside the cargo she holds (`fits`:
--     the days she then holds, voyage.endurance_mult applied, against the door's need). Nothing here is a second
--     copy: every figure is one of those functions' answers.
-- (2) THE SAIL BUYS THEM. cmd.do_sail, docked, after it has MEASURED the course and before voyage.sail_refusal's
--     endurance gate, calls supply_need for the leg and, when the stores fit and there are tuns to take on, cmd.do_provision in
--     DAYS mode to the days supply_need named — the one provisioning rule, paying through public.credit
--     (PROVISION, so it shows in the books). It buys NOTHING when her casks already cover the leg, and NOTHING when
--     the stores would not fit: the gate then refuses E_ENDURANCE as before, with nothing spent. A purse that cannot
--     pay refuses the SAIL with do_provision's own E_INSUFFICIENT_FUNDS. Every SAIL — typed, queued, a plan's Go, a
--     route's — runs do_sail (asserted: no other live body calls voyage.depart); merchants' SAILs too, where their
--     planner's own PROVISION lines leave nothing to buy.
-- (3) THE OLD PATH IS CUT, NOT LEFT BESIDE IT (docs/NO_SPAGHETTI.md §5): the cmd.run_standing_provision call is
--     sliced out of voyage.settle's arrival arm; a route lap's RESUPPLY line (cmd.standing_route_lines) no longer
--     reads a keep level — it writes PROVISION DAYS to supply_need's days for the leg sailed from that stop, before
--     the BUYs, so a lap's stores are aboard before its cargo (merchants and players alike); cmd.standing_route_assign
--     no longer asks for a keep level (E_NO_KEEP is gone); cmd.provision_preset_save / _apply / _delete and
--     world.provision_presets are revoked from anon and authenticated and leave public.client_rpc_entry_points();
--     every human company's fleets.provision_preset_id is nulled, the old values kept in
--     public.provision_preset_backup_0225 for rollback. Merchants' preset rows stay: their planner (0120/0142/0203)
--     still writes them as its own record of a loop's days; R6 drops the table, the column, the backup and
--     cmd.run_standing_provision together once nothing reads them.
-- (4) THE BOARD SAYS WHAT THE SUPPLIES COST. world.good_board's buy and sell rows gain `supplies` {days, cost, fits}
--     from supply_need for the row's longest leg (null when the row has no passage), the sell rows gain `profit`
--     (= net − supplies.cost, null when either is unknown), and a row's `sailable` reads `fits` instead of her
--     casks as they stand now — because the SAIL will fill them, the question is no longer "do her casks cover the
--     leg" but "can her hold carry what the leg asks". Every other key of the board is its pre-image (asserted).
--
-- ── NOT THE OWNER'S — CONFIRM ────────────────────────────────────────────────────────────────────────────────────
-- * The top-up buys to public.npc_leg_days (the door's days rounded up, one day spare), not to the door's days
--   exactly: a hull laden with the stores sails a shade slower (ship_speed's load term), so a top-up to the exact
--   figure can be refused by dust at the gate. The one-day spare is the chain's existing answer to the same
--   question for merchants (0142).
-- * supply_need takes miles, not days (the design said days): the speed she sails at is read once, here, so the
--   board and the SAIL cannot measure the same leg at two speeds.
-- * `sailable` now reads `fits`. The design added `supplies` without naming this; without it the board would mark
--   every leg longer than a new player's starting casks "shut" while the SAIL would sail it.
--
-- ── LOCKS AND TIME ───────────────────────────────────────────────────────────────────────────────────────────────
-- CREATE FUNCTION ×1, CREATE TABLE ×1 (the backup), one UPDATE of public.fleets (human companies' preset column),
-- REVOKE ×4, CREATE OR REPLACE FUNCTION ×N by hunks. The probes run on their own company inside a sub-block that is
-- rolled back whole; only their rows are counted. No LOCK TABLE, no set role, no set local, no begin. Timings are
-- notices only.
-- SUPERSEDES, by hunks sliced from the LIVE bodies (prod head 0220, LF-normalised, each asserted to occur exactly
-- once and to reverse to its pre-image, ACL unchanged): see hunks_0225 below.
-- ROLLBACK: a forward slice reverses the hunks (each OLD text is here verbatim), re-grants the four doors and the
-- registry rows, and restores fleets.provision_preset_id from public.provision_preset_backup_0225. supply_need is
-- then unread and may be dropped.
-- VERSION: 0225 (renumber to the prod head + 1 at push; applies on 0220).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
end $guard$;

create or replace function pg_temp.occurs_0225(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

create temp table t0_0225 on commit drop as select clock_timestamp() as t0;

-- ── 1. THE ONE RULE: WHAT A LEG ASKS, WHAT IT COSTS, WHETHER IT FITS ────────────────────────────────────────────
create function public.supply_needs(p_fleet uuid, p_nms numeric[])
returns table (nm numeric, days numeric, need numeric, tons numeric, cost bigint, fits boolean)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0225: THE STORES EACH OF SEVERAL PASSAGES ASKS OF THIS FLEET, at the speed she sails at now — one row per distinct
-- length in p_nms (a null length: nothing is asked, and nothing fits). The fleet's facts are read ONCE (her speed, her
-- endurance multiplier, each hull's crew, casks, room and full mark) and every leg is answered from them, so a board
-- of 240 rows asks for her hulls once, not 240 times.
--   need  the days of stores the sail door asks (voyage.stores_need_days — the one measure of endurance_margin)
--   days  the days the SAIL tops her up to: public.npc_leg_days (need rounded up, one day spare — what a leg's
--         PROVISION asked under 0142; a hull laden with the stores sails a shade slower, so the exact figure can be
--         refused by dust at the gate)
--   tons  the stores that top-up takes on, in tuns (0 when her casks cover it) — what the hold must keep free for them
--   cost  what that top-up costs her now: every hull through public.stores_topup (THE top-up, as cmd.do_provision
--         places it: her hold less her cargo is the room) priced by public.stores_cost; 0 when her casks cover it
--   fits  whether, topped up, she holds `need`: the shortest hull's days times voyage.endurance_mult (the reading
--         voyage.endurance_days makes), against need less the numeric(10,3) dust (0034's 0.01)
-- Composes four existing authorities and adds no arithmetic of its own. Read by public.supply_need (one leg: cmd.do_sail)
-- and by world.good_board (every row's `supplies`, the card's "Supplies −N"), so what the card shows and what the SAIL
-- spends have one author. Server-only.
declare
  v_speed  numeric := greatest(voyage.fleet_speed(p_fleet), 0.1);
  v_mult   numeric := voyage.endurance_mult(p_fleet);
  v_player uuid;
  v_hulls  jsonb;
  v_water  numeric;
  v_food   numeric;
  v_days   numeric;
  x        numeric;
begin
  select f.player_id into v_player from public.fleets f where f.id = p_fleet;
  select coalesce(jsonb_agg(jsonb_build_object(
           'crew', s.crew, 'water', s.water_t, 'food', s.food_t,
           'room', public.ship_hold_capacity(s.id) - public.ship_cargo_tuns(s.id),
           'full', public.ship_hold_capacity(s.id) * s.store_ratio)), '[]'::jsonb)
    into v_hulls
    from public.ships s where s.fleet_id = p_fleet;
  for x in select distinct u.v from unnest(p_nms) u(v) loop
    nm := x;
    if nm is null then
      need := null; days := null; tons := null; cost := null; fits := false;
      return next;
      continue;
    end if;
    need := voyage.stores_need_days(nm, v_speed);
    days := public.npc_leg_days(nm, v_speed);
    select sum(t.water_t), sum(t.food_t), min(t.days)
      into v_water, v_food, v_days
      from jsonb_to_recordset(v_hulls) h(crew numeric, water numeric, food numeric, room numeric, "full" numeric)
     cross join lateral public.stores_topup(h.crew, h.water, h.food, h.room, days, h."full") t;
    tons := coalesce(v_water, 0) + coalesce(v_food, 0);
    cost := case when v_player is null then 0 else public.stores_cost(v_player, coalesce(v_water, 0), coalesce(v_food, 0)) end;
    fits := coalesce(v_days, 0) * v_mult >= need - 0.01;
    return next;
  end loop;
end $$;
revoke all on function public.supply_needs(uuid, numeric[]) from public, anon, authenticated;
comment on function public.supply_needs(uuid, numeric[]) is
  '0225: the stores each of several passages asks of a fleet — the door''s days, the top-up''s days, their tuns and cost now, '
  'whether they fit — her facts read once. Read by public.supply_need and world.good_board. Server-only.';

-- ONE LEG: cmd.do_sail's reading, the set's answer for one length (no second arithmetic)
create function public.supply_need(p_fleet uuid, p_nm numeric)
returns table (days numeric, need numeric, tons numeric, cost bigint, fits boolean)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select n.days, n.need, n.tons, n.cost, n.fits from public.supply_needs(p_fleet, array[p_nm]) n
$$;
revoke all on function public.supply_need(uuid, numeric) from public, anon, authenticated;
comment on function public.supply_need(uuid, numeric) is
  '0225: the stores ONE passage asks of a fleet — public.supply_needs for one length. Read by cmd.do_sail (buys) and '
  'world.good_board''s buy rows. Server-only.';

-- ── 2. THE OLD DOORS SHUT ────────────────────────────────────────────────────────
revoke all on function cmd.provision_preset_save(uuid, text, integer) from public, anon, authenticated;
revoke all on function cmd.provision_preset_apply(uuid, uuid) from public, anon, authenticated;
revoke all on function cmd.provision_preset_delete(uuid) from public, anon, authenticated;
revoke all on function world.provision_presets() from public, anon, authenticated;


-- ── 3. THE PRE-IMAGES ───────────────────────────────────────────────────────────────────────────────────────────
create temp table defs_before_0225 on commit drop as
select f.ord, f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg,
       (select p.proowner from pg_proc p where p.oid = f.fn::regprocedure) as owner
  from (values (1, 'cmd.do_sail(uuid,jsonb)'),
               (2, 'voyage.settle(uuid,timestamptz)'),
               (3, 'cmd.standing_route_lines(uuid,integer,uuid)'),
               (4, 'cmd.standing_route_assign_for(uuid,uuid,uuid)'),
               (5, 'public.client_rpc_entry_points()'),
               (6, 'world.good_board(uuid,uuid,uuid,numeric)')) f(ord, fn);

create temp table before_0225 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select count(*) from public.fleets f join public.players pl on pl.id = f.player_id
         where not pl.is_npc and f.provision_preset_id is not null) as human_kept;

-- ── 3b. THE COLUMN NULLED, BACKED UP ───────────────────────────────────────────────────────────────────────────
create table public.provision_preset_backup_0225 (
  fleet_id  uuid primary key,
  preset_id uuid not null,
  nulled_at timestamptz not null default now()
);
revoke all on table public.provision_preset_backup_0225 from public, anon, authenticated;
alter table public.provision_preset_backup_0225 enable row level security;   -- no policy: nobody but the server reads it (proof 03)
comment on table public.provision_preset_backup_0225 is
  '0225: every human company fleet''s provision_preset_id as it stood when the standing order was retired. For a rollback '
  'only; dropped with provision_presets in R6.';
insert into public.provision_preset_backup_0225 (fleet_id, preset_id)
select f.id, f.provision_preset_id
  from public.fleets f join public.players pl on pl.id = f.player_id
 where f.provision_preset_id is not null and not pl.is_npc;
update public.fleets f
   set provision_preset_id = null
  from public.players pl
 where pl.id = f.player_id and not pl.is_npc and f.provision_preset_id is not null;

create temp table hunks_0225 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0225 values
-- cmd.do_sail: the stores the leg asks are bought before the gate judges them
('cmd.do_sail(uuid,jsonb)', 1,
$h$  v_voyage uuid;
begin
$h$,
$h$  v_voyage uuid;
  v_need   record;    -- 0225: what the leg asks of her stores (public.supply_need)
begin
$h$),
('cmd.do_sail(uuid,jsonb)', 2,
$h$  v_gate := voyage.sail_refusal(p_fleet, v_dest, v_point, v_nm, v_course);   -- 0216: + the course (the sea conditions judge it)
$h$,
$h$  -- 0225 (owner row 203): SUPPLIES ARE THE SAIL'S OWN. Docked, the stores this leg asks are bought HERE, before the
  -- gate judges them — public.supply_need (the one rule: the door's days, the top-up's days, the cost, whether they
  -- fit) and cmd.do_provision in DAYS mode (the one top-up, paid as PROVISION). Nothing is bought when her casks
  -- already cover the leg, and nothing when the stores would not fit beside her cargo: the gate then refuses
  -- E_ENDURANCE as before, with nothing spent. A purse that cannot pay refuses with do_provision's own words.
  if f.status = 'DOCKED' then
    select * into v_need from public.supply_need(p_fleet, v_nm);
    if v_need.fits and v_need.tons > 0 then   -- tuns, not ducats: a top-up priced at 0 d. (stores ÷5, a short leg at speed ×3) is still a top-up
      perform cmd.do_provision(p_fleet, jsonb_build_object('mode', 'DAYS', 'days', v_need.days));
    end if;
  end if;

  v_gate := voyage.sail_refusal(p_fleet, v_dest, v_point, v_nm, v_course);   -- 0216: + the course (the sea conditions judge it)
$h$),
-- voyage.settle: the arrival no longer fires a standing order
('voyage.settle(uuid,timestamptz)', 1,
$h$    -- 0034 STANDING ORDER: fires HERE, the one place a fleet makes port — after she docks,
    -- before her queued orders run, so a queued onward SAIL departs provisioned.
    perform cmd.run_standing_provision(p_fleet);
    perform cmd.advance(p_fleet, p_now);
$h$,
$h$    -- 0225: the standing order (0034) no longer fires here — every SAIL buys its own stores (cmd.do_sail).
    perform cmd.advance(p_fleet, p_now);
$h$),
-- cmd.standing_route_lines: a route's lap writes no PROVISION to a keep level
('cmd.standing_route_lines(uuid,integer,uuid)', 1,
$h$  -- 2. RESUPPLY to the 0034 keep level — a REFERENCE to the preset, read now, never a copy.
  select pr.days into v_days
    from public.fleets f join public.provision_presets pr on pr.id = f.provision_preset_id
   where f.id = p_fleet;
  if v_days is not null and not public.keep_level_met(p_fleet, v_days) then
    v_out := v_out || format('PROVISION DAYS %s', v_days);
  end if;
$h$,
$h$  -- 2. RESUPPLY for the leg she sails from here (0225): the days public.supply_need names for this stop's course —
  --    the one rule cmd.do_sail buys by — written as the lap's own PROVISION before the BUYs, so the stores are aboard
  --    before the cargo (a hold filled first leaves them no room: the SAIL would then refuse E_ENDURANCE). Skipped
  --    when her casks already hold them (public.keep_level_met, as before). No keep level, no preset, is read.
  select n.days::int into v_days from public.supply_need(p_fleet, st.course_nm) n;
  if v_days is not null and not public.keep_level_met(p_fleet, v_days) then
    v_out := v_out || format('PROVISION DAYS %s', v_days);
  end if;
$h$),
-- cmd.standing_route_assign_for: no keep level is asked
('cmd.standing_route_assign_for(uuid,uuid,uuid)', 1,
$h$    if f.provision_preset_id is null then
      return cmd.standing_route_refusal('E_NO_KEEP', 'Set how many days of supplies to keep first.',
        '(set the supplies to keep for this fleet)');
    end if;
$h$,
$h$    -- 0225: no keep level is asked (E_NO_KEEP is gone) — her supplies are every SAIL's own.
$h$),
-- public.client_rpc_entry_points: the four doors leave the registry
('public.client_rpc_entry_points()', 1,
$h$      ('world',       'provision_presets',   ''),
$h$,
$h$      -- 0225: ('world', 'provision_presets', '') left with the standing order
$h$),
('public.client_rpc_entry_points()', 2,
$h$      ('cmd',         'provision_preset_save',   'uuid, text, int'),
      ('cmd',         'provision_preset_delete', 'uuid'),
      ('cmd',         'provision_preset_apply',  'uuid, uuid'),
$h$,
$h$      -- 0225: cmd.provision_preset_save / _delete / _apply left with the standing order
$h$),
-- world.good_board: every row says what its passage asks of her stores; `sailable` reads whether they fit
('world.good_board(uuid,uuid,uuid,numeric)', 1,
$h$           'sailable', coalesce((select x.nm is not null and v_speed > 0 and voyage.stores_need_days(x.max_leg, v_speed) /* 0203 */ <= v_end
                                   from reach x where x.port_id = s.id), false),
           'longest_leg', (select jsonb_build_object('miles', round(x.max_leg), 'days', round(x.max_leg / v_speed / 24, 2))
                             from reach x where x.port_id = s.id and x.max_leg is not null and v_speed > 0),
$h$,
$h$           -- 0225: her casks as they stand no longer gate a row — the SAIL fills them. A leg is sailable when what it asks
           -- FITS her hold (public.supply_need, the rule cmd.do_sail buys by); `supplies` is that rule's reading.
           'sailable', coalesce((select x.nm is not null and v_speed > 0 and sn.fits
                                   from (select * from reach x0 where x0.port_id = s.id) x
                                  cross join lateral public.supply_need(p_fleet, x.max_leg) sn), false),
           'longest_leg', (select jsonb_build_object('miles', round(x.max_leg), 'days', round(x.max_leg / v_speed / 24, 2))
                             from reach x where x.port_id = s.id and x.max_leg is not null and v_speed > 0),
           'supplies', (select jsonb_build_object('days', round(sn.days, 1), 'cost', sn.cost, 'fits', sn.fits)
                          from (select * from reach x0 where x0.port_id = s.id and x0.max_leg is not null and v_speed > 0) x
                         cross join lateral public.supply_need(p_fleet, x.max_leg) sn),
$h$),
('world.good_board(uuid,uuid,uuid,numeric)', 2,
$h$  ), ranked as materialized (
    -- 0188: the dearest cities she can REACH are priced first; one no passage within her reach gets to ranks last
    select c.*, row_number() over (order by (c.nm is null), c.mid desc, c.nm nulls last, c.code) as rk from cand c
$h$,
$h$  ), needs as materialized (
    -- 0225: what every candidate's longest leg asks of her stores — public.supply_needs, ONE call for every distinct
    -- length (her hulls read once), joined back by length; a row with no leg joins the null answer (fits false)
    select * from public.supply_needs(p_fleet, (select array_agg(c.max_leg) from cand c))
  ), free as materialized (
    -- 0225: the capacity basis's own measure of her room, read ONCE (every sell row's `units_fit` subtracts its stores from it)
    select public.fleet_free_hold(p_fleet) as t
  ), ranked as materialized (
    -- 0188: the dearest cities she can REACH are priced first; one no passage within her reach gets to ranks last
    select c.*, n.days as sn_days, n.tons as sn_tons, n.cost as sn_cost, n.fits as sn_fits,   -- 0225
           row_number() over (order by (c.nm is null), c.mid desc, c.nm nulls last, c.code) as rk
      from cand c left join needs n on n.nm is not distinct from c.max_leg
$h$),
('world.good_board(uuid,uuid,uuid,numeric)', 3,
$h$           'sailable', coalesce(r.nm is not null and r.max_leg is not null and v_speed > 0
                                and voyage.stores_need_days(r.max_leg, v_speed) /* 0203 */ <= v_end, false),
           'longest_leg', case when r.max_leg is not null and v_speed > 0
                               then jsonb_build_object('miles', round(r.max_leg), 'days', round(r.max_leg / v_speed / 24, 2)) end,
$h$,
$h$           'sailable', coalesce(r.nm is not null and r.max_leg is not null and v_speed > 0 and r.sn_fits, false),   -- 0225: they fit
           'longest_leg', case when r.max_leg is not null and v_speed > 0
                               then jsonb_build_object('miles', round(r.max_leg), 'days', round(r.max_leg / v_speed / 24, 2)) end,
           'supplies', case when r.max_leg is not null and v_speed > 0
                            then jsonb_build_object('days', round(r.sn_days, 1), 'cost', r.sn_cost, 'fits', r.sn_fits,
                                   -- the units of the good that fit beside those stores (the capacity basis's own measure,
                                   -- public.fleet_free_hold, less their tuns): what a BUY may load and still sail this leg
                                   'units_fit', case when v_basis <> 'on_board' then greatest(0, floor(((select t from free) - r.sn_tons) / g.bulk)) end) end,   -- 0225
           'profit', case when p.id is not null and p.cost is not null and p.wages is not null and r.max_leg is not null and v_speed > 0
                          then p.proceeds - p.cost - p.tax - p.wages - r.sn_cost end,   -- 0225: the net less the supplies
$h$);

-- the pre-image under a pg_temp name, for the parity proof and the positive control
do $$
begin
  if (select count(*) from defs_before_0225 where def is not null) <> 6 then
    raise exception '0225 self-assert FAIL: % of the 6 bodies found', (select count(*) from defs_before_0225 where def is not null);
  end if;
  execute replace((select def from defs_before_0225 where ord = 6),
                  'CREATE OR REPLACE FUNCTION world.good_board(', 'CREATE OR REPLACE FUNCTION pg_temp.good_board_old_0225(');
end $$;

-- ── 4. THE NEW BODIES ───────────────────────────────────────────────────────────────────────────────────────────
do $$
declare
  d     record;
  h     record;
  p     record;
  v_def text;
  v_rev text;
  v_n   int := 0;
begin
  for d in select * from defs_before_0225 order by ord loop
    v_def := d.def;
    for h in select * from hunks_0225 where fn = d.fn order by n loop
      if pg_temp.occurs_0225(v_def, h.old) <> 1 then
        raise exception '0225 self-assert FAIL: % hunk % occurs % time(s), not once — the deployed body is not what this file was written against',
          d.fn, h.n, pg_temp.occurs_0225(v_def, h.old);
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    if v_def = d.def then
      raise exception '0225 self-assert FAIL: % has no hunk', d.fn;
    end if;
    execute v_def;
    v_rev := replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '');
    for h in select * from hunks_0225 where fn = d.fn order by n desc loop
      if pg_temp.occurs_0225(v_rev, h.new) <> 1 then
        raise exception '0225 self-assert FAIL: % new hunk % is not in the live body once', d.fn, h.n;
      end if;
      v_rev := replace(v_rev, h.new, h.old);
    end loop;
    if v_rev <> d.def then
      raise exception '0225 self-assert FAIL: % does not reverse to its pre-image', d.fn;
    end if;
    select coalesce(pr.proacl::text, '') as acl, pr.provolatile as vol, pr.prosecdef as secdef,
           coalesce(pr.proconfig::text, '') as cfg, pr.proowner as owner
      into p from pg_proc pr where pr.oid = d.fn::regprocedure;
    if p.acl <> d.acl or p.vol <> d.vol or p.secdef <> d.secdef or p.cfg <> d.cfg or p.owner <> d.owner then
      raise exception '0225 self-assert FAIL: % changed its ACL (% → %), owner, volatility, definer or config (% → %)', d.fn, d.acl, p.acl, d.cfg, p.cfg;
    end if;
    v_n := v_n + 1;
  end loop;
  if v_n <> 6 then
    raise exception '0225 self-assert FAIL: % bodies re-cut, not 6', v_n;
  end if;
  -- the registry: the four doors are gone and nothing else moved; every door it names is still granted
  if (select count(*) from public.client_rpc_entry_points()) <> (select entry_points from before_0225) - 4
     or exists (select 1 from public.client_rpc_entry_points() e
                 where e.function_name in ('provision_presets', 'provision_preset_save', 'provision_preset_delete', 'provision_preset_apply'))
     or exists (select 1 from public.client_rpc_entry_points() e where e.fn is null or not has_function_privilege('authenticated', e.fn, 'execute')) then
    raise exception '0225 self-assert FAIL: the registry is not the pre-image less the four preset doors';
  end if;
  if has_function_privilege('authenticated', 'cmd.provision_preset_save(uuid, text, integer)'::regprocedure, 'execute')
     or has_function_privilege('authenticated', 'cmd.provision_preset_apply(uuid, uuid)'::regprocedure, 'execute')
     or has_function_privilege('authenticated', 'cmd.provision_preset_delete(uuid)'::regprocedure, 'execute')
     or has_function_privilege('authenticated', 'world.provision_presets()'::regprocedure, 'execute')
     or has_function_privilege('anon', 'world.provision_presets()'::regprocedure, 'execute')
     or has_function_privilege('authenticated', 'public.supply_need(uuid, numeric)'::regprocedure, 'execute') then
    raise exception '0225 self-assert FAIL: a preset door, or supply_need, is still executable by a client role';
  end if;
  -- the column: every human company's fleet is under no order, and every value is in the backup
  if exists (select 1 from public.fleets f join public.players pl on pl.id = f.player_id where not pl.is_npc and f.provision_preset_id is not null)
     or (select count(*) from public.provision_preset_backup_0225) <> (select human_kept from before_0225) then
    raise exception '0225 self-assert FAIL: the preset column was not nulled for every human fleet, or the backup is short';
  end if;
  -- ONE PATH: no live body but cmd.do_sail departs a voyage, and nothing calls the standing executor any more
  if exists (select 1 from pg_proc pp join pg_namespace n on n.oid = pp.pronamespace
              where n.nspname in ('public', 'cmd', 'voyage', 'world')
                and pp.prosrc like '%voyage.depart(%' and not (n.nspname = 'voyage' and pp.proname = 'depart')
                and not (n.nspname = 'cmd' and pp.proname = 'do_sail')) then
    raise exception '0225 self-assert FAIL: a live body other than cmd.do_sail calls voyage.depart: %',
      (select string_agg(n.nspname || '.' || pp.proname, ', ') from pg_proc pp join pg_namespace n on n.oid = pp.pronamespace
        where n.nspname in ('public', 'cmd', 'voyage', 'world') and pp.prosrc like '%voyage.depart(%'
          and not (n.nspname = 'voyage' and pp.proname = 'depart') and not (n.nspname = 'cmd' and pp.proname = 'do_sail'));
  end if;
  if exists (select 1 from pg_proc pp join pg_namespace n on n.oid = pp.pronamespace
              where n.nspname in ('public', 'cmd', 'voyage', 'world')
                and pp.prosrc like '%cmd.run_standing_provision(%' and not (n.nspname = 'cmd' and pp.proname = 'run_standing_provision')) then
    raise exception '0225 self-assert FAIL: a live body still calls cmd.run_standing_provision';
  end if;
  -- ONE MEASURE (0203's guard, kept): no live body but voyage.stores_need_days applies endurance_margin
  if exists (select 1 from pg_proc pp join pg_namespace n on n.oid = pp.pronamespace
              where n.nspname in ('public', 'cmd', 'voyage', 'world')
                and pp.prosrc ~ '\*\s*(v_margin|v_emargin|public\.wc_num\(''endurance_margin''\))' and pp.proname <> 'stores_need_days') then
    raise exception '0225 self-assert FAIL: a copy of the stores measure appeared';
  end if;
end $$;

-- ── 5. THE PROBES: one company of this file's own, inside a sub-block that is rolled back whole ─────────────────
do $$
declare
  c_auth    constant uuid := '00000000-0225-4000-8000-000000000001';
  v_player  uuid;
  v_fleet   uuid;
  v_lis     uuid;
  v_dest    uuid;
  v_dcode   text;
  v_course  jsonb;
  v_good    uuid;
  v_gcode   text;
  v_bulk    numeric;
  v_res     jsonb;
  v_board   jsonb;
  v_old     jsonb;
  v_row     jsonb;
  v_orow    jsonb;
  v_cost    bigint;
  v_card    bigint;
  v_exp     bigint;
  v_purse0  bigint;
  v_purse1  bigint;
  v_prov0   int;
  v_prov1   int;
  v_nm      numeric;
  v_need    numeric;
  v_end     numeric;
  v_fits    boolean;
  v_sail_old boolean;
  v_sail_new boolean;
  v_ms      numeric[] := '{}';
  v_ms_old  numeric[] := '{}';
  v_ms_set  numeric;
  v_t       timestamptz;
  v_hazard  jsonb;
  k         int;
  -- what the sub-block learnt, carried out past its rollback
  r_a text; r_b text; r_c text; r_d text; r_e text; r_f text;
begin
  select value into v_hazard from public.world_config where key = 'hazard_p_max';
  begin
    -- THE PRECONDITIONS THIS PROBE OWNS: no weather lottery, a company of its own at Lisbon, casks run dry, a
    -- destination with a held course out of Lisbon (public.npc_courses, the chain's own roster legs; the nearest)
    update public.world_config set value = to_jsonb(0.0) where key = 'hazard_p_max';
    select id into v_lis from public.ports where code = 'LIS';
    v_player := public.new_house(c_auth, 'Probe 0225', 'PRT');
    select id into v_fleet from public.fleets where player_id = v_player;
    if (select port_id from public.fleets where id = v_fleet) <> v_lis then
      raise exception '0225 self-assert FAIL: the probe company was not founded at Lisbon';
    end if;
    update public.ships set water_t = 0, food_t = 0 where fleet_id = v_fleet;
    -- the LONGEST held course out of Lisbon her captain may sail (within nav_leg_nm_base, a new company's reach: the
    -- knob the gate reads): a leg whose stores cost ducats (at speed ×3 the nearest leg's two days of stores price at
    -- 0 d. — bought all the same, but a purse that does not move proves less)
    select c.to_port, p.code, c.course, c.nm into v_dest, v_dcode, v_course, v_nm
      from public.npc_courses c join public.ports p on p.id = c.to_port
     where c.from_port = v_lis and c.nm <= public.wc_num('nav_leg_nm_base')
     order by c.nm desc, p.code limit 1;
    if v_dest is null then
      raise exception '0225 self-assert FAIL: public.npc_courses holds no course out of Lisbon';
    end if;
    select g.id, g.code, g.bulk into v_good, v_gcode, v_bulk
      from public.port_goods pg join public.goods g on g.id = pg.good_id
     where pg.port_id = v_lis and pg.stock > 0 and public.port_offers(v_lis, g.id)
     order by g.code limit 1;
    if v_good is null then
      raise exception '0225 self-assert FAIL: Lisbon offers no good in stock';
    end if;
    perform cmd.assume_identity(c_auth);

    -- (e) THE CARD'S FIGURE, before the SAIL: the board's row for the destination, and the pre-image's; timed
    for k in 1 .. 6 loop
      v_t := clock_timestamp();
      v_board := world.good_board(v_good, v_fleet, null, null);
      v_ms := v_ms || round(extract(epoch from clock_timestamp() - v_t) * 1000, 1);
    end loop;
    v_t := clock_timestamp();
    perform count(*) from public.supply_needs(v_fleet, (select array_agg(x::numeric) from generate_series(100, 5000, 20) x));
    v_ms_set := round(extract(epoch from clock_timestamp() - v_t) * 1000, 1);
    v_old := pg_temp.good_board_old_0225(v_good, v_fleet, null, null);
    for k in 1 .. 3 loop   -- the pre-image, timed beside it (the same session, the same company)
      v_t := clock_timestamp();
      v_old := pg_temp.good_board_old_0225(v_good, v_fleet, null, null);
      v_ms_old := v_ms_old || round(extract(epoch from clock_timestamp() - v_t) * 1000, 1);
    end loop;
    select e into v_row  from jsonb_array_elements(v_board->'sell') e where e->>'port' = v_dcode;
    select e into v_orow from jsonb_array_elements(v_old->'sell')   e where e->>'port' = v_dcode;
    if v_row is null or v_orow is null then
      raise exception '0225 self-assert FAIL: the board has no sell row for %', v_dcode;
    end if;
    v_card := (v_row->'supplies'->>'cost')::bigint;
    v_fits := (v_row->'supplies'->>'fits')::boolean;
    v_sail_old := (v_orow->>'sailable')::boolean;
    v_sail_new := (v_row->>'sailable')::boolean;
    if v_card is null or v_card <= 0 or v_fits is not true then
      raise exception '0225 self-assert FAIL: with empty casks the % row serves supplies % — a cost > 0 that fits was expected', v_dcode, v_row->'supplies';
    end if;
    if (v_row->>'profit')::bigint is distinct from (v_row->>'net')::bigint - v_card then
      raise exception '0225 self-assert FAIL: profit % is not net % less the supplies %', v_row->>'profit', v_row->>'net', v_card;
    end if;
    if (v_row->'supplies'->>'units_fit')::numeric is null or (v_row->'supplies'->>'units_fit')::numeric > (v_board->'qty'->>'units')::numeric then
      raise exception '0225 self-assert FAIL: units_fit % is not at most the capacity basis %', v_row->'supplies'->>'units_fit', v_board->'qty'->>'units';
    end if;
    -- (f) THE BOARD MINUS WHAT THIS FILE ADDED IS ITS PRE-IMAGE, row for row (sailable is the one key whose rule moved)
    if (select jsonb_agg(e - 'supplies' - 'profit' - 'sailable') from jsonb_array_elements(v_board->'sell') e)
         <> (select jsonb_agg(e - 'sailable') from jsonb_array_elements(v_old->'sell') e)
       or (select jsonb_agg(e - 'supplies' - 'sailable') from jsonb_array_elements(v_board->'buy') e)
         <> (select jsonb_agg(e - 'sailable') from jsonb_array_elements(v_old->'buy') e)
       or (v_board - 'buy' - 'sell') <> (v_old - 'buy' - 'sell') then
      raise exception '0225 self-assert FAIL: the board is not its pre-image plus supplies, profit and the new sailable';
    end if;
    -- `supplies` follows `longest_leg`, the pre-image's own key (a row the reach table measures carries both; one it
    -- does not carries neither)
    if exists (select 1 from jsonb_array_elements(v_board->'sell') e
                where (jsonb_typeof(e->'longest_leg') = 'object') <> (jsonb_typeof(e->'supplies') = 'object'))
       or exists (select 1 from jsonb_array_elements(v_board->'buy') e
                where (jsonb_typeof(e->'longest_leg') = 'object') <> (jsonb_typeof(e->'supplies') = 'object')) then
      raise exception '0225 self-assert FAIL: a row''s supplies do not follow its longest_leg';
    end if;
    r_e := format('the %s row serves supplies {days %s, cost %s, fits %s, units_fit %s of a capacity of %s}; profit = net − cost; the board minus supplies/profit/sailable is its pre-image; good_board timed %s ms over 6 calls (the pre-image: %s ms over 3; supply_needs over 246 legs %s ms; %s buy rows)',
                  v_dcode, v_row->'supplies'->>'days', v_card, v_fits, v_row->'supplies'->>'units_fit', v_board->'qty'->>'units', array_to_string(v_ms, ', '), array_to_string(v_ms_old, ', '), v_ms_set, jsonb_array_length(v_board->'buy'));
    r_f := format('with empty casks the pre-image marked %s sailable=%s, the new board sailable=%s (the stores fit her hold)', v_dcode, v_sail_old, v_sail_new);
    if v_sail_old is true or v_sail_new is not true then
      raise exception '0225 self-assert FAIL: %', r_f;
    end if;

    -- THE CARD AND THE SAIL ARE ONE AUTHOR: the card prices the row's longest leg as the reach table measures it, the
    -- SAIL the course it sails (public.npc_courses holds that course's own measure, as cmd.do_sail measures it); each is
    -- supply_need's answer for its miles, and they differ only when the two measures straddle a day of stores
    v_exp := (select cost from public.supply_need(v_fleet, v_nm));
    if v_card <> (select cost from public.supply_need(v_fleet, (v_row->'longest_leg'->>'miles')::numeric)) then
      raise exception '0225 self-assert FAIL: the card''s supplies.cost % is not supply_need''s answer for its longest leg of % nm', v_card, v_row->'longest_leg'->>'miles';
    end if;

    -- (a) EMPTY CASKS: the SAIL buys the leg's stores, one PROVISION row, the purse moves by the same, and she departs
    select ducats into v_purse0 from public.players where id = v_player;
    select count(*) into v_prov0 from public.ledger where player_id = v_player and kind = 'PROVISION';
    v_res := cmd.issue(v_fleet, 'SAIL TO ' || v_dcode, null, v_course);
    if coalesce((v_res->>'ok')::boolean, false) is not true then
      raise exception '0225 self-assert FAIL: the SAIL was refused: %', v_res;
    end if;
    select ducats into v_purse1 from public.players where id = v_player;
    select count(*) into v_prov1 from public.ledger where player_id = v_player and kind = 'PROVISION';
    select -l.ducats_delta into v_cost from public.ledger l
     where l.player_id = v_player and l.kind = 'PROVISION' order by l.created_at desc, l.id desc limit 1;
    if v_prov1 - v_prov0 <> 1 or v_cost <= 0 or v_purse0 - v_purse1 <> v_cost then
      raise exception '0225 self-assert FAIL: the SAIL wrote % PROVISION row(s) (cost %), the purse moved %', v_prov1 - v_prov0, v_cost, v_purse0 - v_purse1;
    end if;
    if (select status from public.fleets where id = v_fleet) <> 'SAILING' then
      raise exception '0225 self-assert FAIL: she did not depart';
    end if;
    select v.total_nm into v_nm from public.voyages v where v.fleet_id = v_fleet and v.status = 'SAILING';
    v_need := voyage.stores_need_days(v_nm, voyage.fleet_speed(v_fleet));
    v_end  := voyage.endurance_days(v_fleet);
    if v_end < v_need - 0.01 then
      raise exception '0225 self-assert FAIL: she sailed with % days against a need of %', round(v_end, 2), round(v_need, 2);
    end if;
    if v_cost <> v_exp then
      raise exception '0225 self-assert FAIL: the SAIL paid % but supply_need said % for its % nm', v_cost, v_exp, round(v_nm);
    end if;
    r_a := format('SAIL LIS -> %s (course %s nm): one PROVISION row of %s d. = the purse change = supply_need''s answer for that course; the card said %s d. for the reach table''s %s-nm longest leg; she holds %s days against the door''s %s',
                  v_dcode, round(v_nm), v_cost, v_card, v_row->'longest_leg'->>'miles', round(v_end, 2), round(v_need, 2));

    -- (d) THE ARRIVAL BUYS NOTHING (the pre-image's settle did: the hunk was there to cut)
    for k in 1 .. 12 loop
      exit when (select status from public.fleets where id = v_fleet) <> 'SAILING';
      update public.voyages set departed_at = departed_at - (eta - now()) - interval '1 minute', eta = now() - interval '1 minute'
       where fleet_id = v_fleet and status = 'SAILING';
      perform voyage.settle(v_fleet, now());
    end loop;
    if (select port_id from public.fleets where id = v_fleet) is distinct from v_dest then
      raise exception '0225 self-assert FAIL: she did not make %', v_dcode;
    end if;
    select count(*) into v_prov0 from public.ledger where player_id = v_player and kind = 'PROVISION';
    if v_prov0 <> v_prov1 then
      raise exception '0225 self-assert FAIL: the arrival bought stores (% PROVISION rows, was %)', v_prov0, v_prov1;
    end if;
    if strpos((select def from defs_before_0225 where ord = 2), 'perform cmd.run_standing_provision(p_fleet);') = 0 then
      raise exception '0225 self-assert FAIL: positive control — the pre-image settle did not call the standing executor';
    end if;
    r_d := format('warped to %s: PROVISION rows %s before and after the arrival (the pre-image settle called cmd.run_standing_provision; this one does not)', v_dcode, v_prov0);

    -- (b) STOCKED: a SAIL buys nothing
    perform cmd.do_provision(v_fleet, jsonb_build_object('mode', 'DAYS', 'days', 30));
    select count(*) into v_prov0 from public.ledger where player_id = v_player and kind = 'PROVISION';
    v_res := cmd.issue(v_fleet, 'SAIL TO LIS', null,
               (select jsonb_agg(t.e order by t.ord desc) from jsonb_array_elements(v_course) with ordinality t(e, ord)));
    if coalesce((v_res->>'ok')::boolean, false) is not true then
      raise exception '0225 self-assert FAIL: the stocked SAIL was refused: %', v_res;
    end if;
    select count(*) into v_prov1 from public.ledger where player_id = v_player and kind = 'PROVISION';
    if v_prov1 <> v_prov0 then
      raise exception '0225 self-assert FAIL: a stocked fleet bought stores at the SAIL';
    end if;
    r_b := format('stocked to 30 days, the SAIL back bought nothing (%s PROVISION rows before and after)', v_prov1);
    for k in 1 .. 12 loop
      exit when (select status from public.fleets where id = v_fleet) <> 'SAILING';
      update public.voyages set departed_at = departed_at - (eta - now()) - interval '1 minute', eta = now() - interval '1 minute'
       where fleet_id = v_fleet and status = 'SAILING';
      perform voyage.settle(v_fleet, now());
    end loop;

    -- (c) A FULL HOLD: casks empty, the hold full of the good — the SAIL is refused E_ENDURANCE and buys nothing
    update public.ships s
       set water_t = 0, food_t = 0,
           cargo = jsonb_build_object(v_gcode, floor(public.ship_hold_capacity(s.id) / greatest(v_bulk, 0.001)))
     where s.fleet_id = v_fleet;
    select count(*) into v_prov0 from public.ledger where player_id = v_player and kind = 'PROVISION';
    v_board := world.good_board(v_good, v_fleet, null, null);
    select e into v_row from jsonb_array_elements(v_board->'sell') e where e->>'port' = v_dcode;
    if (v_row->'supplies'->>'fits')::boolean is not false or (v_row->>'sailable')::boolean is not false then
      raise exception '0225 self-assert FAIL: with a full hold the board still says the stores fit: %', v_row->'supplies';
    end if;
    v_res := cmd.issue(v_fleet, 'SAIL TO ' || v_dcode, null, v_course);
    select count(*) into v_prov1 from public.ledger where player_id = v_player and kind = 'PROVISION';
    if coalesce((v_res->>'ok')::boolean, false) or v_res->>'error_code' <> 'E_ENDURANCE' or v_prov1 <> v_prov0 then
      raise exception '0225 self-assert FAIL: a full hold answered % with % new PROVISION row(s); E_ENDURANCE and none were expected', v_res, v_prov1 - v_prov0;
    end if;
    r_c := format('a hold full of %s: the board says fits=false / sailable=false, the SAIL is refused E_ENDURANCE and buys nothing', v_gcode);

    raise exception 'ROLLBACK_0225';
  exception when others then
    if sqlerrm <> 'ROLLBACK_0225' then
      raise;
    end if;
  end;
  -- the sub-block rolled back: the probe company, its rows and the knob are gone
  if exists (select 1 from public.players where id = v_player) or exists (select 1 from public.ledger where player_id = v_player)
     or (select value from public.world_config where key = 'hazard_p_max') <> v_hazard then
    raise exception '0225 self-assert FAIL: the probe did not roll back whole';
  end if;
  raise notice '0225 probe (a): %', r_a;
  raise notice '0225 probe (b): %', r_b;
  raise notice '0225 probe (c): %', r_c;
  raise notice '0225 probe (d): %', r_d;
  raise notice '0225 probe (e): %', r_e;
  raise notice '0225 probe (f): %', r_f;
  raise notice '0225 self-assert ok: SUPPLIES ARE THE SAIL''S OWN. cmd.do_sail buys what its leg asks through public.supply_need; voyage.settle, the route lap and the route assign no longer read a keep level; the four preset doors are revoked and out of the registry; every human fleet is under no order (backed up); world.good_board rows carry supplies and profit, and sailable reads fits. % s.',
    round(extract(epoch from clock_timestamp() - (select t0 from t0_0225)), 1);
end $$;

