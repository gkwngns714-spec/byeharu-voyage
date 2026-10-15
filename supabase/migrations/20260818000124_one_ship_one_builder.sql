-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0124 — ONE SHIP, ONE BUILDER  (docs/SHIPS_AND_GEAR.md §3.1, step S1)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER'S WORDS ───────────────────────────────────────────────────────────────────────────
-- docs/RESUME.md queue item 3, 2026-10-15: *"Merchant ships: serve slots + combat stats (server
-- change), and make more ship types and more gear"*. This file is the first half of the first
-- clause: a merchant's ship panel shows what your own does.
--
-- ── WHAT WAS FOUND ──────────────────────────────────────────────────────────────────────────────
-- "What one ship is, on the wire" had TWO builders, both inline:
--   * world.fleets() built the player's ship object (0074, as re-cut by 0077): slots, fittings with
--     their slot, the six combat stats, cabins;
--   * world.npc_fleet_card() built a poorer one (0099): no slots, no slot on a fitting, no stats.
-- So a merchant's panel could not match the player's — the client already draws everything it is
-- served (src/live/ShipPanel.tsx). And "a ship's effective stats" was computed one stat at a time:
-- world.ship_stat(ship, stat) ran two queries per call, and world.fleets called it six times a hull.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- (1) world.ship_stats(ship) — THE ONE COMPUTATION of a hull's ten effective stats, in one query:
--     the class's base, plus sum(delta × qty) per stat over what is mounted, with 0074's floors
--     (speed and sighting never below 0.5, the rest never below 0). Server-only.
-- (2) world.ship_stat(ship, stat) — re-cut (one hunk, its whole body, sliced from the LIVE body) to
--     a PROJECTION of ship_stats. Keeps its name, its callers (ship_hold_capacity, ship_speed) and
--     its refusal E_NO_SUCH_STAT in the same words.
-- (3) world.ship_view(ship) — THE ONE SHIP BUILDER. Exactly the keys world.fleets served for a hull,
--     with every value as before, plus `class_code` (so the client stops keeping a name → code
--     map). The six stats come from ONE ship_stats call. Server-only. No `is_npc` in it: a merchant's
--     hull and a player's are built by the same lines.
-- (4) world.fleets and world.npc_fleet_card — re-cut, one hunk each, sliced from the LIVE bodies:
--     the inline ship object becomes a call to world.ship_view. The card strips three keys a
--     stranger is not served — `id` (a handle, as 0099 strips the voyage's), `water_t` and `food_t`
--     (0099's forbidden list: provisioning). The card's ships therefore GAIN slots, fittings[].slot
--     and .code, the six stats, cabins and class_code: class data and what is mounted, the same
--     things the owner's own hull shows. Merchant hulls carry no fittings yet (that is S2, 0125).
--
-- ── ROLLBACK ────────────────────────────────────────────────────────────────────────────────────
-- One forward migration re-cutting the three bodies back: every OLD hunk is in this file, verbatim
-- (hunks_0124.old), and the self-assert below proves each live body reverses to its pre-image by
-- them. Then `drop function world.ship_view(uuid), world.ship_stats(uuid)`.
--
-- ── COST ────────────────────────────────────────────────────────────────────────────────────────
-- world.fleets per hull: six ship_stat calls (twelve queries) → one ship_stats call. The card gains
-- one ship_stats call per ship (~1 ms), read at a tap, never on a beat.
--
-- SUPERSEDES: world.fleets (0099 as live), world.npc_fleet_card (0099 as live), world.ship_stat
-- (0074) — one hunk each, sliced from the LIVE body and asserted to occur exactly once.
-- Self-asserts hold AS FOUND; every probe rolls back. No table, no grant, no new entry point.
-- VERSION: 0124. 0122/0123 are the economy plan's (docs/ECONOMY_LOOP.md); this file depends on
-- neither and applies on 0121 alone.

do $guard$ begin perform set_config('statement_timeout', '20min', true); end $guard$;

-- ── 1. THE PRE-IMAGES ──────────────────────────────────────────────────────────────────────────
create temp table defs_before_0124 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl
  from unnest(array['world.fleets()', 'world.npc_fleet_card(uuid)', 'world.ship_stat(uuid, text)']) f(fn);

create temp table entry_points_before_0124 on commit drop as
select count(*) as n from public.client_rpc_entry_points();

-- ── 2. THE HUNKS (old = verbatim from the live bodies; new = what replaces it) ─────────────────
create temp table hunks_0124 (fn text, n int, old text, new text) on commit drop;

insert into hunks_0124 values
('world.fleets()', 1,
$h$    'ships', (select coalesce(jsonb_agg(jsonb_build_object(
                 'id', s.id, 'name', s.name, 'class', c.name, 'is_flagship', s.is_flagship,
                 'durability', s.durability, 'max_durability', c.durability,
                 'crew', s.crew, 'crew_required', c.crew_required, 'crew_max', c.crew_max,
                 'hold', public.ship_hold_capacity(s.id), 'hold_rated', c.hold,
                 'cargo', s.cargo, 'cargo_tuns', public.ship_cargo_tuns(s.id),
                 'water_t', s.water_t, 'food_t', s.food_t,
                 -- 0074: what she carries, and what it bought her. `speed_rated` beside `speed` is
                 -- the same shape `hold_rated` beside `hold` has had since 0017: the number the
                 -- hull is rated at, and the number she actually makes.
                 'speed', voyage.ship_speed(s.id), 'speed_rated', c.speed_kn,
                 'handling', world.ship_stat(s.id, 'handling'),
                 'armour', world.ship_stat(s.id, 'armour'),
                 'attack', world.ship_stat(s.id, 'attack'),
                 'accuracy', world.ship_stat(s.id, 'accuracy'),
                 'reach', world.ship_stat(s.id, 'reach'),
                 'sighting', world.ship_stat(s.id, 'sighting'),
                 'fittings', (select coalesce(jsonb_agg(jsonb_build_object(
                     'code', ik.code, 'name', ik.name, 'slot', ik.slot, 'qty', sf.qty)
                     order by ik.slot, ik.name), '[]'::jsonb)
                   from public.ship_fittings sf join public.item_kinds ik on ik.code = sf.item_code
                  where sf.ship_id = s.id),
                 -- 0077: class_slots alone. An override used to be appended here that replaced a
                 -- correct weapon count with the cannon column, which is a different number.
                 'slots', (select coalesce(jsonb_object_agg(cs.slot, cs.count), '{}'::jsonb)
                   from public.class_slots cs where cs.class_code = c.code),
                 'cabins', (select cabins from public.class_cabins where class_code = c.code)) order by s.is_flagship desc, s.name), '[]'::jsonb)
                 from public.ships s join public.ship_classes c on c.id = s.class_id
                where s.fleet_id = f.id),
$h$,
$h$    'ships', (select coalesce(jsonb_agg(world.ship_view(s.id)   -- 0124: one ship, one builder
                 order by s.is_flagship desc, s.name), '[]'::jsonb)
                 from public.ships s
                where s.fleet_id = f.id),
$h$),

('world.npc_fleet_card(uuid)', 1,
$h$    'ships', (select coalesce(jsonb_agg(jsonb_build_object(
               'name', s.name, 'class', c.name, 'is_flagship', s.is_flagship,
               'durability', s.durability, 'max_durability', c.durability,
               'crew', s.crew, 'crew_required', c.crew_required, 'crew_max', c.crew_max,
               'hold', public.ship_hold_capacity(s.id), 'hold_rated', c.hold,
               'speed', voyage.ship_speed(s.id), 'speed_rated', c.speed_kn,
               'cargo', s.cargo, 'cargo_tuns', public.ship_cargo_tuns(s.id),
               'fittings', (select coalesce(jsonb_agg(jsonb_build_object('name', ik.name, 'qty', sf.qty)
                                                      order by ik.slot, ik.name), '[]'::jsonb)
                              from public.ship_fittings sf join public.item_kinds ik on ik.code = sf.item_code
                             where sf.ship_id = s.id))
               order by s.is_flagship desc, s.name), '[]'::jsonb)
                from public.ships s join public.ship_classes c on c.id = s.class_id
               where s.fleet_id = f.id),
$h$,
$h$    -- 0124: the ONE ship builder, as your own fleet is served, less what a stranger is not: her id
    -- (a handle) and her water and food (provisioning — 0099's forbidden keys).
    'ships', (select coalesce(jsonb_agg(world.ship_view(s.id) - array['id', 'water_t', 'food_t']
               order by s.is_flagship desc, s.name), '[]'::jsonb)
                from public.ships s
               where s.fleet_id = f.id),
$h$),

('world.ship_stat(uuid, text)', 1,
$h$declare
  v_base  numeric;
  v_delta numeric;
begin
  select case p_stat
           when 'hold'       then c.hold
           when 'speed'      then c.speed_kn
           when 'handling'   then c.handling
           when 'draft'      then c.draft
           when 'durability' then c.durability
           when 'armour'     then c.armour
           when 'attack'     then c.attack
           when 'accuracy'   then c.accuracy
           when 'reach'      then c.reach
           when 'sighting'   then c.sighting
         end
    into v_base
    from public.ships s join public.ship_classes c on c.id = s.class_id
   where s.id = p_ship;
  if v_base is null then
    raise exception 'E_NO_SUCH_STAT: no ship % has a stat called "%"', p_ship, p_stat using errcode = 'P0001';
  end if;

  select coalesce(sum(e.delta * f.qty), 0) into v_delta
    from public.ship_fittings f
    join public.item_effects e on e.item_code = f.item_code and e.stat = p_stat
   where f.ship_id = p_ship;

  -- A FLOOR, NOT A CLAMP AT THE TOP. Fittings that spend a stat must not be able to drive a hull
  -- to zero speed or negative hold - she would become unsailable and there would be no way back
  -- except unfitting, which a player at sea cannot do.
  return greatest(case when p_stat in ('speed', 'sighting') then 0.5 else 0 end, v_base + v_delta);
$h$,
$h$declare
  -- 0124: A PROJECTION of world.ship_stats, the one computation of a hull's stats (the base, what is
  -- mounted, the floors). An unknown stat, or no such ship, reads null there and is refused here.
  v numeric := (world.ship_stats(p_ship) ->> p_stat)::numeric;
begin
  if v is null then
    raise exception 'E_NO_SUCH_STAT: no ship % has a stat called "%"', p_ship, p_stat using errcode = 'P0001';
  end if;
  return v;
$h$);

-- The same hunks as EXPRESSIONS: the `(select …)` after `'ships', `, without the trailing comma.
-- The OLD ones are evaluated for every fleet in the world BEFORE the re-cut (the true pre-image),
-- the NEW ones after it, so the comparison is between the two pieces of text this file swaps.
create or replace function pg_temp.hunk_expr_0124(p_hunk text)
returns text
language sql
immutable
as $$
  select regexp_replace(substr(p_hunk, strpos(p_hunk, '(select coalesce')), ',\s*$', '')
$$;

create or replace function pg_temp.hunk_fns_0124(p_side text)
returns void
language plpgsql
as $$
declare
  h record;
begin
  for h in select * from hunks_0124 where fn <> 'world.ship_stat(uuid, text)' loop
    execute format(
      'create or replace function pg_temp.%I(p_fleet uuid) returns jsonb language sql stable as %L',
      case h.fn when 'world.fleets()' then 'fleets_ships_' else 'card_ships_' end || p_side || '_0124',
      'select ' || pg_temp.hunk_expr_0124(case p_side when 'old' then h.old else h.new end)
        || E'\n  from (select p_fleet as id) f');
  end loop;
end $$;
-- The NEW expressions name world.ship_view, so they are made once it exists (section 6).
select pg_temp.hunk_fns_0124('old');

-- The OLD bodies kept under pg_temp names for the probe below (0099's method). The old fleets body
-- reads its six stats through the OLD ship_stat, so its answer is the pre-image to the digit.
do $$
declare
  v_def text;
begin
  v_def := (select def from defs_before_0124 where fn = 'world.ship_stat(uuid, text)');
  execute replace(v_def, 'CREATE OR REPLACE FUNCTION world.ship_stat(', 'CREATE OR REPLACE FUNCTION pg_temp.ship_stat_before_0124(');
  v_def := (select def from defs_before_0124 where fn = 'world.fleets()');
  v_def := replace(v_def, 'CREATE OR REPLACE FUNCTION world.fleets()', 'CREATE OR REPLACE FUNCTION pg_temp.fleets_before_0124()');
  execute replace(v_def, 'world.ship_stat(', 'pg_temp.ship_stat_before_0124(');
  v_def := (select def from defs_before_0124 where fn = 'world.npc_fleet_card(uuid)');
  execute replace(v_def, 'CREATE OR REPLACE FUNCTION world.npc_fleet_card(', 'CREATE OR REPLACE FUNCTION pg_temp.card_before_0124(');
end $$;

-- THE PRE-IMAGE OF EVERY HULL AND EVERY FLEET IN THE WORLD, merchants included, taken now.
create temp table stats_before_0124 on commit drop as
select s.id as ship_id, st.stat, world.ship_stat(s.id, st.stat)::text as v
  from public.ships s
 cross join unnest(array['hold', 'speed', 'handling', 'draft', 'durability',
                         'armour', 'attack', 'accuracy', 'reach', 'sighting']) st(stat);

create temp table ships_before_0124 on commit drop as
select f.id as fleet_id,
       pg_temp.fleets_ships_old_0124(f.id) as fleets_ships,
       pg_temp.card_ships_old_0124(f.id) as card_ships
  from public.fleets f;

-- ── 3. THE ONE COMPUTATION ─────────────────────────────────────────────────────────────────────
create or replace function world.ship_stats(p_ship uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0124: A HULL'S TEN EFFECTIVE STATS, ONE QUERY. The class's base, plus sum(delta × qty) per stat
  -- over what is mounted. A FLOOR, NOT A CLAMP AT THE TOP (0074): fittings that spend a stat must
  -- not drive a hull to zero speed or negative hold — she would become unsailable, and a player at
  -- sea cannot unfit. A stat the class does not carry reads null; no such ship reads null.
  with d as (
    select e.stat, sum(e.delta * f.qty) as delta
      from public.ship_fittings f
      join public.item_effects e on e.item_code = f.item_code
     where f.ship_id = p_ship
     group by e.stat
  )
  select jsonb_object_agg(b.stat,
           case when b.base is null then null
                else greatest(case when b.stat in ('speed', 'sighting') then 0.5 else 0 end,
                              b.base + coalesce(d.delta, 0)) end)
    from public.ships s
    join public.ship_classes c on c.id = s.class_id
   cross join lateral (values ('hold',       c.hold::numeric),
                              ('speed',      c.speed_kn::numeric),
                              ('handling',   c.handling::numeric),
                              ('draft',      c.draft::numeric),
                              ('durability', c.durability::numeric),
                              ('armour',     c.armour::numeric),
                              ('attack',     c.attack::numeric),
                              ('accuracy',   c.accuracy::numeric),
                              ('reach',      c.reach::numeric),
                              ('sighting',   c.sighting::numeric)) b(stat, base)
    left join d on d.stat = b.stat
   where s.id = p_ship
$$;
comment on function world.ship_stats(uuid) is
  '0124: THE one computation of a hull''s ten effective stats (base + mounted, floored). '
  'world.ship_stat projects it; world.ship_view serves six of them. Server-only.';
revoke all on function world.ship_stats(uuid) from public, anon, authenticated;

-- ── 4. THE RE-CUTS ─────────────────────────────────────────────────────────────────────────────
create or replace function pg_temp.recut_0124(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := replace(pg_get_functiondef(p_fn::regprocedure), E'\r', '');
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0124 where fn = p_fn order by n loop
    v_n := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
    if v_n <> 1 then
      raise exception '0124 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

-- ship_stat first: ship_view below reads it (through ship_hold_capacity and ship_speed).
select pg_temp.recut_0124('world.ship_stat(uuid, text)');

-- ── 5. THE ONE SHIP BUILDER ────────────────────────────────────────────────────────────────────
create or replace function world.ship_view(p_ship uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0124: WHAT ONE SHIP IS, ON THE WIRE — for your own fleet (world.fleets) and a merchant's card
  -- (world.npc_fleet_card, which strips what a stranger is not served). The keys world.fleets
  -- served since 0074/0077, every value as before, plus `class_code`. One ship_stats call for the
  -- six combat stats. Nothing here tells a merchant from a player: the same lines build both.
  select jsonb_build_object(
           'id', s.id, 'name', s.name, 'class', c.name, 'class_code', c.code, 'is_flagship', s.is_flagship,
           'durability', s.durability, 'max_durability', c.durability,
           'crew', s.crew, 'crew_required', c.crew_required, 'crew_max', c.crew_max,
           'hold', public.ship_hold_capacity(s.id), 'hold_rated', c.hold,
           'cargo', s.cargo, 'cargo_tuns', public.ship_cargo_tuns(s.id),
           'water_t', s.water_t, 'food_t', s.food_t,
           -- `speed_rated` beside `speed`: the number the hull is rated at, and the one she makes.
           'speed', voyage.ship_speed(s.id), 'speed_rated', c.speed_kn,
           'handling', x.st->'handling',
           'armour', x.st->'armour',
           'attack', x.st->'attack',
           'accuracy', x.st->'accuracy',
           'reach', x.st->'reach',
           'sighting', x.st->'sighting',
           'fittings', (select coalesce(jsonb_agg(jsonb_build_object(
               'code', ik.code, 'name', ik.name, 'slot', ik.slot, 'qty', sf.qty)
               order by ik.slot, ik.name), '[]'::jsonb)
             from public.ship_fittings sf join public.item_kinds ik on ik.code = sf.item_code
            where sf.ship_id = s.id),
           -- 0077: class_slots alone.
           'slots', (select coalesce(jsonb_object_agg(cs.slot, cs.count), '{}'::jsonb)
             from public.class_slots cs where cs.class_code = c.code),
           'cabins', (select cabins from public.class_cabins where class_code = c.code))
    from public.ships s
    join public.ship_classes c on c.id = s.class_id
   cross join lateral (select world.ship_stats(s.id) as st) x
   where s.id = p_ship
$$;
comment on function world.ship_view(uuid) is
  '0124: THE one ship builder — one hull as world.fleets serves it (+ class_code). Read by '
  'world.fleets and world.npc_fleet_card. Server-only.';
revoke all on function world.ship_view(uuid) from public, anon, authenticated;

select pg_temp.recut_0124(fn) from (values ('world.fleets()'), ('world.npc_fleet_card(uuid)')) x(fn);

-- ── 6. SELF-ASSERT ─────────────────────────────────────────────────────────────────────────────
select pg_temp.hunk_fns_0124('new');

-- A card ship (post) brought back to the pre-0124 card's shape: the pre's keys, fittings as name/qty.
create or replace function pg_temp.card_ship_old_shape_0124(p_pre jsonb, p_post jsonb)
returns jsonb
language sql
immutable
as $$
  select coalesce(jsonb_object_agg(k,
           case when k = 'fittings'
                then (select coalesce(jsonb_agg(jsonb_build_object('name', ff->'name', 'qty', ff->'qty') order by o), '[]'::jsonb)
                        from jsonb_array_elements(p_post->'fittings') with ordinality z(ff, o))
                else p_post->k end), '{}'::jsonb)
    from jsonb_object_keys(p_pre) k
$$;

create or replace function pg_temp.strip_class_code_0124(p_fleets jsonb)
returns jsonb
language sql
immutable
as $$
  select coalesce(jsonb_agg(
           fl || jsonb_build_object('ships',
             (select coalesce(jsonb_agg(sh - 'class_code' order by so), '[]'::jsonb)
                from jsonb_array_elements(fl->'ships') with ordinality y(sh, so)))
           order by fo), '[]'::jsonb)
    from jsonb_array_elements(p_fleets) with ordinality x(fl, fo)
$$;

do $$
declare
  c_uid      constant uuid := '00000000-0124-4000-8000-000000000001';
  c_card_keys constant text[] := array['accuracy', 'armour', 'attack', 'cabins', 'cargo', 'cargo_tuns', 'class',
    'class_code', 'crew', 'crew_max', 'crew_required', 'durability', 'fittings', 'handling', 'hold', 'hold_rated',
    'is_flagship', 'max_durability', 'name', 'reach', 'sighting', 'slots', 'speed', 'speed_rated'];
  v_fn       text;
  v_def      text;
  v_back     text;
  h          record;
  v_n        int;
  v_bad      bigint;
  v_hulls    bigint;
  v_fleets   bigint;
  v_err      text;
  v_player   uuid;
  v_fleet    uuid;
  v_pship    uuid;
  v_mfleet   uuid;
  v_mship    uuid;
  v_buy      text;
  v_spend    text;
  v_spend_st text;
  v_floor    numeric;
  v_before   jsonb;
  v_after    jsonb;
  v_cb       jsonb;
  v_ca       jsonb;
  v_ship     jsonb;
  v_t0       timestamptz;
  v_ms       numeric;
begin
  -- (a) PARITY BY REVERSE SUBSTITUTION; ACLs unmoved; each hunk in its new body exactly once.
  for v_fn in select fn from defs_before_0124 loop
    v_def := replace(pg_get_functiondef(v_fn::regprocedure), E'\r', '');
    v_back := v_def;
    for h in select * from hunks_0124 where fn = v_fn order by n desc loop
      v_n := (length(v_back) - length(replace(v_back, h.new, ''))) / length(h.new);
      if v_n <> 1 then
        raise exception '0124 self-assert FAIL: hunk % of % is in the new body % time(s), not once', h.n, v_fn, v_n;
      end if;
      v_back := replace(v_back, h.new, h.old);
    end loop;
    if v_back <> (select def from defs_before_0124 where fn = v_fn) or v_def = v_back then
      raise exception '0124 self-assert FAIL: % is not its pre-image plus only 0124''s hunk', v_fn;
    end if;
    if coalesce((select p.proacl::text from pg_proc p where p.oid = v_fn::regprocedure), '')
       is distinct from (select acl from defs_before_0124 where fn = v_fn) then
      raise exception '0124 self-assert FAIL: the re-cut moved the ACL of %', v_fn;
    end if;
  end loop;

  -- (b) ONE BUILDER: neither reader still builds a ship inline (positive control: both pre-images
  --     did, so the scan can see the token); no `is_npc` in the builder or the computation.
  if (select count(*) from defs_before_0124
       where fn in ('world.fleets()', 'world.npc_fleet_card(uuid)') and strpos(def, '''fittings'', (select') > 0) <> 2 then
    raise exception '0124 self-assert FAIL: the scan''s positive control — a pre-image did not build fittings inline';
  end if;
  if strpos(pg_get_functiondef('world.fleets()'::regprocedure), '''fittings'', (select') > 0
     or strpos(pg_get_functiondef('world.npc_fleet_card(uuid)'::regprocedure), '''fittings'', (select') > 0 then
    raise exception '0124 self-assert FAIL: a reader still builds a ship inline';
  end if;
  if strpos(pg_get_functiondef('world.ship_view(uuid)'::regprocedure), 'is_npc') > 0
     or strpos(pg_get_functiondef('world.ship_stats(uuid)'::regprocedure), 'is_npc') > 0 then
    raise exception '0124 self-assert FAIL: the ship builder or the stat computation tells a merchant from a player';
  end if;

  -- (c) THE WALL: the two new functions are server-only; no new entry point; no client write.
  if has_function_privilege('anon', 'world.ship_view(uuid)', 'execute')
     or has_function_privilege('authenticated', 'world.ship_view(uuid)', 'execute')
     or has_function_privilege('anon', 'world.ship_stats(uuid)', 'execute')
     or has_function_privilege('authenticated', 'world.ship_stats(uuid)', 'execute') then
    raise exception '0124 self-assert FAIL: world.ship_view or world.ship_stats is client-callable';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> (select n from entry_points_before_0124)
     or exists (select 1 from public.client_rpc_entry_points() e
                 where e.fn is null or not has_function_privilege('authenticated', e.fn, 'execute'))
     or (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0124 self-assert FAIL: the registry, the grant wall or the read wall';
  end if;

  -- (d) EVERY HULL × TEN STATS: the projection reads what the old computation read, to the digit.
  select count(distinct ship_id) into v_hulls from stats_before_0124;
  select count(*) into v_bad from stats_before_0124 b
   where b.v is distinct from world.ship_stat(b.ship_id, b.stat)::text;
  if v_bad > 0 or v_hulls = 0 then
    raise exception '0124 self-assert FAIL: % hull-stat(s) of % hulls read differently through ship_stats', v_bad, v_hulls;
  end if;
  if (select count(*) from public.ships s where (select count(*) from jsonb_object_keys(world.ship_stats(s.id))) <> 10) > 0 then
    raise exception '0124 self-assert FAIL: a hull''s ship_stats does not carry exactly ten stats';
  end if;
  foreach v_fn in array array['nonsense', null] loop
    v_err := null;
    begin
      perform world.ship_stat(case when v_fn is null then gen_random_uuid() else (select id from public.ships limit 1) end,
                              coalesce(v_fn, 'hold'));
    exception when sqlstate 'P0001' then
      v_err := sqlerrm;
    end;
    if v_err is null or v_err not like 'E_NO_SUCH_STAT: no ship % has a stat called "%"' then
      raise exception '0124 self-assert FAIL: an unknown stat / ship did not refuse E_NO_SUCH_STAT (%)', v_err;
    end if;
  end loop;

  -- (e) EVERY FLEET IN THE WORLD, merchants included: world.fleets' ships, through the new hunk,
  --     equal the pre-image once class_code is stripped — as TEXT, so a scale (8.0 vs 8) cannot hide;
  --     and the card's ships, brought back to the old card's shape, equal the old card's.
  select count(*) into v_fleets from ships_before_0124;
  select count(*) into v_bad from ships_before_0124 b
   where (select coalesce(jsonb_agg(sh - 'class_code' order by o), '[]'::jsonb)
            from jsonb_array_elements(pg_temp.fleets_ships_new_0124(b.fleet_id)) with ordinality x(sh, o))::text
         is distinct from b.fleets_ships::text;
  if v_bad > 0 or v_fleets = 0 then
    raise exception '0124 self-assert FAIL: % of % fleets'' ships changed in world.fleets', v_bad, v_fleets;
  end if;
  select count(*) into v_bad from ships_before_0124 b
   where (select coalesce(jsonb_agg(pg_temp.card_ship_old_shape_0124(b.card_ships->(o::int - 1), sh) order by o), '[]'::jsonb)
            from jsonb_array_elements(pg_temp.card_ships_new_0124(b.fleet_id)) with ordinality x(sh, o))::text
         is distinct from b.card_ships::text
      or exists (select 1 from jsonb_array_elements(pg_temp.card_ships_new_0124(b.fleet_id)) sh
                  where array(select jsonb_object_keys(sh) order by 1) <> c_card_keys);
  if v_bad > 0 then
    raise exception '0124 self-assert FAIL: % of % fleets'' card ships changed, or a card ship''s key set is not exactly %',
      v_bad, v_fleets, c_card_keys;
  end if;

  -- (f) THE PROBES, rolled back: a player and a merchant, each hull carrying one fitting that buys a
  --     stat and one mounted ×99 that drives a stat through its floor (positive control for the
  --     floor and the delta). The whole reads, old body against new.
  select e.item_code into v_buy from public.item_effects e where e.delta > 0 order by e.item_code, e.stat limit 1;
  select e.item_code, e.stat into v_spend, v_spend_st from public.item_effects e
   where e.delta < 0 and e.item_code <> v_buy order by (e.stat = 'speed') desc, e.item_code, e.stat limit 1;
  if v_buy is null or v_spend is null then
    raise exception '0124 self-assert FAIL: no fitting to probe with (item_effects)';
  end if;
  select nf.fleet_id into v_mfleet from public.npc_fleets nf order by nf.roster_ord, nf.fleet_id limit 1;
  if v_mfleet is null then
    raise exception '0124 self-assert FAIL: no merchant fleet to probe';
  end if;
  select s.id into v_mship from public.ships s where s.fleet_id = v_mfleet order by s.is_flagship desc, s.name limit 1;

  begin
    update public.world_config set value = 'true'::jsonb where key in ('npc_traders_enabled', 'standing_routes_enabled');
    v_player := public.new_house(c_uid, 'Casa do Casco', 'PRT');
    select id into v_fleet from public.fleets where player_id = v_player;
    select s.id into v_pship from public.ships s where s.fleet_id = v_fleet order by s.is_flagship desc, s.name limit 1;
    insert into public.ship_fittings (ship_id, item_code, qty) values
      (v_pship, v_buy, 1), (v_pship, v_spend, 99), (v_mship, v_buy, 1), (v_mship, v_spend, 99)
    on conflict (ship_id, item_code) do update set qty = excluded.qty;

    -- ten stats, old computation against new, on both fitted hulls; the floor was reached.
    select count(*) into v_bad
      from unnest(array[v_pship, v_mship]) sh(id)
     cross join unnest(array['hold', 'speed', 'handling', 'draft', 'durability',
                             'armour', 'attack', 'accuracy', 'reach', 'sighting']) st(stat)
     where pg_temp.ship_stat_before_0124(sh.id, st.stat)::text is distinct from world.ship_stat(sh.id, st.stat)::text;
    v_floor := case when v_spend_st in ('speed', 'sighting') then 0.5 else 0 end;
    if v_bad > 0 or world.ship_stat(v_pship, v_spend_st) <> v_floor or world.ship_stat(v_mship, v_spend_st) <> v_floor then
      raise exception '0124 self-assert FAIL: on fitted hulls % stat(s) moved, or the floor of % was not reached', v_bad, v_spend_st;
    end if;

    -- the player's whole world.fleets(), old body against new (class_code stripped).
    perform cmd.assume_identity(c_uid);
    v_before := pg_temp.fleets_before_0124();
    v_after  := world.fleets();
    v_ship   := v_after->0->'ships'->0;
    if pg_temp.strip_class_code_0124(v_after)::text is distinct from v_before::text
       or jsonb_array_length(v_after) < 1
       or v_ship->>'class_code' is distinct from (select c.code from public.ships s join public.ship_classes c on c.id = s.class_id where s.id = v_pship)
       or jsonb_array_length(v_ship->'fittings') <> 2 then
      raise exception '0124 self-assert FAIL: world.fleets changed: before % after %', left(v_before::text, 500), left(v_after::text, 500);
    end if;

    -- the merchant's whole card, old body against new: everything but the ships identical; her ships
    -- the old ones plus the new keys; slots served, her fittings with their slot, the six stats.
    v_cb := pg_temp.card_before_0124(v_mfleet);
    v_t0 := clock_timestamp();
    v_ca := world.npc_fleet_card(v_mfleet);
    v_ms := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
    v_ship := v_ca->'ships'->0;
    if (v_ca - 'ships')::text is distinct from (v_cb - 'ships')::text
       or (select coalesce(jsonb_agg(pg_temp.card_ship_old_shape_0124(v_cb->'ships'->(o::int - 1), sh) order by o), '[]'::jsonb)
             from jsonb_array_elements(v_ca->'ships') with ordinality x(sh, o))::text is distinct from (v_cb->'ships')::text
       or (select coalesce(sum(value::int), 0) from jsonb_each_text(v_ship->'slots')) < 1
       or jsonb_array_length(v_ship->'fittings') <> 2
       or exists (select 1 from jsonb_array_elements(v_ship->'fittings') ff where ff->>'slot' is null)
       or exists (select 1 from unnest(array['attack', 'accuracy', 'reach', 'armour', 'handling', 'sighting']) k
                   where jsonb_typeof(v_ship->k) <> 'number')
       or (v_spend_st in ('attack', 'accuracy', 'reach', 'armour', 'handling', 'sighting')
           and (v_ship->>v_spend_st)::numeric <> v_floor) then
      raise exception '0124 self-assert FAIL: the merchant''s card: before % after %', left(v_cb::text, 500), left(v_ca::text, 500);
    end if;
    -- the forbidden-key scan, deep, with its positive control: the player's own fleets DO carry water_t.
    if not exists (select 1 from jsonb_path_query(v_after, 'strict $.**') v(j),
                     jsonb_object_keys(case when jsonb_typeof(v.j) = 'object' then v.j else '{}'::jsonb end) k
                    where k = 'water_t')
       or exists (select 1 from jsonb_path_query(v_ca, 'strict $.**') v(j),
                    jsonb_object_keys(case when jsonb_typeof(v.j) = 'object' then v.j else '{}'::jsonb end) k
                   where k in ('queue', 'orders', 'cargo_basis', 'version', 'reserve', 'ducats', 'ledger',
                               'provision', 'water_t', 'food_t', 'endurance_days')) then
      raise exception '0124 self-assert FAIL: the card serves a forbidden key';
    end if;
    if exists (select 1 from jsonb_array_elements(v_ca->'ships') sh where sh ? 'id') then
      raise exception '0124 self-assert FAIL: the card serves a ship''s id';
    end if;

    raise exception 'ROLLBACK_0124 %', v_ms;
  exception when others then
    if sqlerrm not like 'ROLLBACK_0124 %' then raise; end if;
    v_ms := split_part(sqlerrm, ' ', 2)::numeric;
  end;
  if exists (select 1 from public.players where auth_uid = c_uid) then
    raise exception '0124 self-assert FAIL: the probe world was not rolled back';
  end if;

  raise notice '0124 self-assert ok: ONE SHIP, ONE BUILDER. world.fleets, world.npc_fleet_card and world.ship_stat reverse to their pre-images hunk by hunk, ACLs unmoved; neither reader builds a ship inline (positive control: both pre-images did); no is_npc in ship_view or ship_stats; both server-only, no new entry point, no client write. % hull(s) × ten stats read the same through ship_stats to the digit; unknown stat / ship refuse E_NO_SUCH_STAT. % fleet(s): world.fleets'' ships equal the pre-image as text with class_code stripped, and every card''s ships brought back to the old shape equal the old card''s, key set exact. Probes on fitted hulls (one buy, one ×99 through the % floor): ten stats agree; a player''s whole world.fleets() and a merchant''s whole card equal their old bodies; the card serves slots, fittings with their slot and the six stats, no id, no forbidden key; card read % ms. Rolled back.',
    v_hulls, v_fleets, v_spend_st, v_ms;
end $$;
