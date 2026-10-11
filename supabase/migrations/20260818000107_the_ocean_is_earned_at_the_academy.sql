-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0107 — THE OCEAN IS EARNED AT THE ACADEMY
--        Owner rows 113 and 117 (docs/OWNER_REQUESTS.md). docs/NPC_FLEET_SCALE.md slice G.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE ASK ─────────────────────────────────────────────────────────────────────────────────────
-- The owner, 2026-10-10: *"set levels, requirements, skills, ships, captain traits, and all. Make
-- it so that there are restrictions based on length of trade route, how many you can carry, the
-- entering of different regions and such."* Restated 2026-10-11 (row 117) with routes as the first
-- gate: *"set levels (requirements)."*
--
-- Row 113 wrote the design down so it could not drift, and this file is that design. Nothing in it
-- is a new progression system: the parts already exist and are not re-invented.
--
--   `public.player_progress` (0069) derives TRADING and EXPLORATION levels from the append-only
--   record every time it is asked — never stored, so it cannot be inflated and is retroactively
--   right for voyages sailed before it existed.
--   `public.player_skills` (0016) holds SEAMANSHIP / NAVIGATION / ACCOUNTING / HAGGLING to
--   `skill_max_level` 5. NO ROW IS LEVEL 0 — the absence is the level, by that file's own ruling.
--   `public.assert_house_caps` (0021) already enforces ship and fleet counts, on a trigger, so
--   every future writer inherits the rule instead of copying it.
--
-- What 0107 adds is ONE predicate and one column, and turns three flat numbers into earned ones.
--
-- ── THE ONE PREDICATE ───────────────────────────────────────────────────────────────────────────
-- `public.passage_gate(player, nm, destination)` answers in `voyage.sail_refusal`'s own shape: a
-- `cmd.refusal` — {code, sentence, figures} — or null when the passage is clear.
--
-- THIS PARAGRAPH SAID THE OPPOSITE FOR ONE RUN OF THE CHAIN. I read 0047's cut of
-- `voyage.sail_refusal`, saw `returns text`, and wrote that row 113's design had drifted from the
-- code and the code won. It had not: 0050 — "a refusal is two numbers and a verb" — re-cut that
-- function to return a `cmd.refusal`, and the apply said so plainly ("invalid input syntax for
-- type json: Token E_LEG_TOO_FAR is invalid ... while casting return value to function's return
-- type"). The design was right and I was wrong, which is recorded here rather than quietly fixed,
-- because the next person to read 0047 will make the same mistake.
--
-- And the refusal is the better shape for its own reason: 0050's whole point is that a refusal
-- carries FIGURES a face can draw. Both gates have two numbers — the leg against the reach, the
-- level asked against the level held — so both carry them.
--
-- It is called in TWO places and nowhere else:
--   `voyage.sail_refusal` — so a passage beyond her captain is refused before a hull moves;
--   `cmd.standing_route_save_for` — so a ROUTE is refused when it is WRITTEN, which is the whole
--   point of row 117. A standing route that is discovered to be illegal at sea is a route that
--   pauses in a strange harbour at three in the morning.
--
-- ── (a) THE LENGTH OF A LEG IS EARNED ───────────────────────────────────────────────────────────
-- A leg longer than `nav_leg_nm_base × 2^(NAVIGATION−1)` is refused `E_LEG_TOO_FAR`. At the base
-- (900 nm) a captain who has never studied navigation may work a coast and the near Atlantic;
-- each level DOUBLES her reach, so level 5 is 14,400 nm and the whole world is open. Doubling and
-- not adding, because the map's own distances are geometric — Lisbon to Funchal is 600 nm and
-- Lisbon to Nagasaki is 13,000 — and a linear ladder would spend four of its five rungs inside
-- Europe.
--
-- ── (b) HOW MANY SHE CAN CARRY IS EARNED ────────────────────────────────────────────────────────
-- Two caps, moving in opposite directions, and both are stated plainly because one of them is a
-- restriction the owner asked for and the other is a reward:
--
--   PER FLEET, TIGHTER: `fleet_ship_base + SEAMANSHIP` under the flat `fleet_ship_max` (8). At
--   SEAMANSHIP 0 that is TWO hulls in one fleet where the flat rule allowed eight — the
--   "how many you can carry" restriction, in the one place the design named. It binds from the
--   first day and it is meant to.
--
--   PER HOUSE, LOOSER: `fleet_max_base + TRADING level`, never below the flat `fleet_max` (2). At
--   level 1 that is two fleets — exactly what a house may keep today — and it grows with the
--   ledger. A cap that only ever tightened would be a nerf dressed as a progression; "the fleet
--   count follows the trading level" (row 113) is followed upward.
--
-- `ship_max` (4, the house-wide hull count) is deliberately NOT touched. The design did not name
-- it, and moving three caps at once when two were asked for is how a slice stops being reviewable.
--
-- ── (c) A REGION IS ENTERED WHEN IT HAS BEEN EARNED ─────────────────────────────────────────────
-- `public.regions.min_exploration_level`, DERIVED and never authored by hand: each region's level
-- comes from the SAILED distance from the founding frame to its nearest harbour — Lisbon's own
-- `sea_reaches.reaches` row, the same water the game measures everything else on, not a great
-- circle through continents. `1 + floor(nearest_nm / region_level_nm_step)`, capped at
-- `region_level_max`. So Iberia is open to a captain on her first day and the Indies are not, and
-- nobody can quietly open their favourite sea: the derivation is re-run and asserted below, and a
-- hand-set value would be seen.
--
-- ── MERCHANTS ARE EXEMPT, BY THE ONE PREDICATE ──────────────────────────────────────────────────
-- `players.is_npc`. The gates are a PLAYER's progression and the world's own traders are not
-- playing it: a merchant company founded with a 13,000 nm carreira has no academy to go to, and
-- 0098's roster would refuse to found itself. The exemption reads `is_npc` exactly as the crew
-- floor (0097) and the fortnight's rest (0101) do.
--
-- ── WHAT THIS SUPERSEDES ────────────────────────────────────────────────────────────────────────
-- `voyage.sail_refusal` (0036, re-cut by 0047), `cmd.standing_route_save_for` (0096, re-cut by
-- 0106) and `public.assert_house_caps` (0021) — each by hunks, each proven below to be its
-- pre-image plus only this file's hunks with its ACL unmoved.
--
-- WHEN THE NEW INPUT IS ABSENT NOTHING MOVES, and that is what makes this landable: a merchant is
-- exempt, and a captain inside her earned reach gets byte-identical answers from all three. The
-- only behaviour that changes is a refusal where there was none — which is the ask. A fleet that
-- ALREADY holds more hulls than its captain has earned is not retroactively broken: the caps are a
-- trigger on write, so she keeps what she has and may not add to it, and that is said here rather
-- than discovered.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

insert into public.world_config (key, value, description) values
  ('nav_leg_nm_base', to_jsonb(900),
   '0107 (owner row 113a): the longest single leg a captain with NO navigation may sail, nautical '
   'miles. Each NAVIGATION level doubles it — nav_leg_nm_base x 2^(NAVIGATION-1) — so level 5 is '
   '14,400 nm and the world is open. Doubling, because the map''s own distances are geometric.'),
  ('fleet_ship_base', to_jsonb(2),
   '0107 (owner row 113b): hulls one fleet may sail before any SEAMANSHIP, the earned per-fleet '
   'cap being fleet_ship_base + SEAMANSHIP under the flat fleet_ship_max. This TIGHTENS the old '
   'flat 8 and is meant to: it is the owner''s "how many you can carry".'),
  ('fleet_max_base', to_jsonb(1),
   '0107 (owner row 113b): fleets a house may keep is fleet_max_base + its TRADING level, never '
   'below the flat fleet_max. At level 1 that is today''s 2, and it grows with the ledger — a cap '
   'that only tightened would be a nerf dressed as a progression.'),
  ('region_level_nm_step', to_jsonb(2500),
   '0107 (owner row 113c): nautical miles of sailed distance from the founding frame per step of '
   'a region''s required EXPLORATION level. The level is 1 + floor(nearest_nm / step), capped at '
   'region_level_max, DERIVED from Lisbon''s own sea_reaches row and never authored by hand.'),
  ('region_level_max', to_jsonb(5),
   '0107: the highest EXPLORATION level any region may ask for. A ceiling, so the far side of the '
   'world is a long voyage and not an unreachable one.');

-- ── 1. A REGION'S PRICE OF ENTRY, DERIVED ──────────────────────────────────────────────────────
alter table public.regions add column min_exploration_level int not null default 1
  constraint regions_min_exploration_level_sane check (min_exploration_level between 1 and 20);

comment on column public.regions.min_exploration_level is
  '0107 (owner row 113c): the EXPLORATION level a captain needs to make a harbour in this region. '
  'DERIVED from the SAILED distance from the founding frame (Lisbon''s sea_reaches row) to the '
  'region''s nearest harbour: 1 + floor(nearest_nm / region_level_nm_step), capped at '
  'region_level_max. Re-derived and asserted by 0107, so a hand-set value would be seen.';

do $$
declare
  v_lis   uuid;
  v_step  numeric := public.wc_num('region_level_nm_step');
  v_cap   int     := public.wc_int('region_level_max');
  v_rows  int;
  v_dist  text;
begin
  select id into v_lis from public.ports where code = 'LIS';
  if v_lis is null then
    raise exception '0107: the founding frame''s harbour (LIS) is not in this world';
  end if;

  with nearest as (
    -- The region's nearest harbour, by the water the game itself measures. Lisbon's own row holds
    -- a sailed figure to every other place; her own region reads 0 because she is in it.
    select p.region_id,
           min(case when p.id = v_lis then 0
                    else (select (sr.reaches->>p.code)::numeric
                            from public.sea_reaches sr where sr.port_id = v_lis) end) as nm
      from public.ports p
     where p.kind = 'HARBOUR' and p.region_id is not null
     group by p.region_id)
  update public.regions r
     set min_exploration_level = greatest(1, least(v_cap, 1 + floor(n.nm / v_step)::int))
    from nearest n
   where n.region_id = r.id and n.nm is not null;
  v_rows := (select count(*) from public.regions where min_exploration_level > 1);

  select string_agg(format('%s=%s', x.min_exploration_level, x.n), ' ' order by x.min_exploration_level)
    into v_dist
    from (select min_exploration_level, count(*)::int as n from public.regions
           group by min_exploration_level) x;
  raise notice '0107: % of % region(s) ask more than level 1; the spread is %',
    v_rows, (select count(*) from public.regions), v_dist;
end $$;

-- ── 2. WHAT A CAPTAIN HAS EARNED ───────────────────────────────────────────────────────────────
create or replace function public.skill_level(p_player uuid, p_code text)
returns int
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0107: a house's level in one skill, and ZERO where there is no row — 0016's own ruling that
  -- "the absence of a row is level 0", read in one place instead of joined by hand at each gate.
  select coalesce((select ps.level from public.player_skills ps
                     join public.skills sk on sk.id = ps.skill_id
                    where ps.player_id = p_player and sk.code = p_code), 0)
$$;

comment on function public.skill_level(uuid, text) is
  '0107: THE reading of a house''s level in one skill, 0 where it has never studied it (0016: the '
  'absence of a row IS the level). Server-only.';

create or replace function public.earned_caps(p_player uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0107 (owner row 113b): the two structural caps, EARNED. Per fleet the earned figure is the
  -- TIGHTER of itself and the flat cap; per house it is the LOOSER, so a house never keeps fewer
  -- fleets than the flat rule already allowed. A merchant is not playing this and gets the flat
  -- numbers: her roster is founded with the hulls the generator measured.
  select case when exists (select 1 from public.players p where p.id = p_player and p.is_npc)
    then jsonb_build_object('fleet_max', public.wc_int('fleet_max'),
                            'fleet_ship_max', public.wc_int('fleet_ship_max'),
                            'earned', false)
    else jsonb_build_object(
      'fleet_max', greatest(public.wc_int('fleet_max'),
                            public.wc_int('fleet_max_base')
                            + ((public.player_progress(p_player)->'trading'->>'level')::int)),
      'fleet_ship_max', least(public.wc_int('fleet_ship_max'),
                              public.wc_int('fleet_ship_base')
                              + public.skill_level(p_player, 'SEAMANSHIP')),
      'earned', true) end
$$;

comment on function public.earned_caps(uuid) is
  '0107 (owner row 113b): {fleet_max, fleet_ship_max, earned} for one house — the per-fleet hull '
  'cap tightened by SEAMANSHIP and the fleet count lifted by the TRADING level. THE one reading, '
  'called by public.assert_house_caps, so the trigger and any face that prints a cap cannot '
  'disagree. A merchant gets the flat numbers (earned false). Server-only.';

-- ── 3. THE ONE PREDICATE ───────────────────────────────────────────────────────────────────────
create or replace function public.passage_gate(p_player uuid, p_nm numeric, p_dest uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0107 (owner rows 113a, 113c): may this house sail THIS passage? Null when she may; otherwise a
-- cmd.refusal — {code, sentence, figures} — which is voyage.sail_refusal's own shape (0050), so it
-- slots into the one "may she sail?" authority with no translation and no second shape for a client
-- to learn. Both gates carry their two FIGURES, which is what 0050 exists for.
--
-- Two gates, and both read what playing has already earned rather than a stored counter:
--   the LENGTH of the leg against nav_leg_nm_base x 2^(NAVIGATION-1);
--   the DESTINATION's region against her EXPLORATION level.
-- A destination that is not a harbour has no region and is gated on length alone — open water
-- belongs to nobody, which is the same ruling 0047 made about draft and ice.
--
-- MERCHANTS ARE EXEMPT (players.is_npc). So is a null player: the gate is asked by server paths
-- that may be acting for nobody, and a gate that refused "nobody" would refuse the world's own
-- housekeeping.
declare
  v_nav     int;
  v_reach   numeric;
  v_level   int;
  v_need    int;
  v_region  text;
begin
  if p_player is null
     or exists (select 1 from public.players p where p.id = p_player and p.is_npc) then
    return null;
  end if;

  if coalesce(p_nm, 0) > 0 then
    v_nav := public.skill_level(p_player, 'NAVIGATION');
    v_reach := public.wc_num('nav_leg_nm_base') * power(2::numeric, greatest(0, v_nav - 1));
    if p_nm > v_reach then
      return cmd.refusal('E_LEG_TOO_FAR',
               format('that leg is %s nm and your navigation carries you %s nm — study navigation',
                      round(p_nm), round(v_reach)),
               jsonb_build_object('nm', round(p_nm), 'reach_nm', round(v_reach), 'navigation', v_nav));
    end if;
  end if;

  if p_dest is not null then
    select r.name, r.min_exploration_level into v_region, v_need
      from public.ports po join public.regions r on r.id = po.region_id
     where po.id = p_dest and po.kind = 'HARBOUR';
    if v_need is not null then
      v_level := (public.player_progress(p_player)->'exploration'->>'level')::int;
      if v_level < v_need then
        return cmd.refusal('E_REGION_CLOSED',
                 format('%s asks exploration level %s and yours is %s — sail farther first',
                        v_region, v_need, v_level),
                 jsonb_build_object('needs', v_need, 'has', v_level, 'region', v_region));
      end if;
    end if;
  end if;

  return null;
end $$;

comment on function public.passage_gate(uuid, numeric, uuid) is
  '0107 (owner rows 113a/113c): THE earned-passage predicate — null, or a cmd.refusal in '
  'voyage.sail_refusal''s own shape (0050), carrying the two figures each gate turns on. '
  'Gates the LENGTH of a leg on NAVIGATION and the '
  'DESTINATION''s region on EXPLORATION. Called by voyage.sail_refusal (before a hull moves) and '
  'by cmd.standing_route_save_for (so a route is refused when it is WRITTEN, owner row 117). '
  'Merchants and a null player are exempt. Server-only.';

-- ── 4. THE THREE DOORS, RE-CUT ─────────────────────────────────────────────────────────────────
create temporary table hunks_0107 (fn text not null, n int not null, old text not null, new text not null);
create temporary table defs_before_0107 (fn text primary key, def text not null, acl text not null);

insert into hunks_0107 values
-- (i) THE SEA. The gate goes in beside the draft and ice checks — after the fleet exists and is
--     docked, so "there is no such fleet" still beats "you cannot sail that far", and before the
--     stores arithmetic, so a passage she may not make is refused for the reason she can act on.
('voyage.sail_refusal(uuid, uuid, jsonb, numeric)', 1,
$h$  if p_dest is not null then
    select kind into v_kind from public.ports where id = p_dest;$h$,
$h$  -- 0107 (owner row 113): WHAT HER CAPTAIN HAS EARNED, asked of the one predicate. Before the
  -- berth facts below, because a passage beyond her navigation is refused wherever it ends.
  v_gate := public.passage_gate(f.player_id, p_nm, p_dest);
  if v_gate is not null then
    return v_gate;
  end if;

  if p_dest is not null then
    select kind into v_kind from public.ports where id = p_dest;$h$),
('voyage.sail_refusal(uuid, uuid, jsonb, numeric)', 2,
$h$  v_back  numeric := 0;
begin$h$,
$h$  v_back  numeric := 0;
  v_gate  jsonb;     -- 0107: the earned-passage refusal (cmd.refusal), or null
begin$h$),
-- (ii) THE ROUTE'S OWN DOOR. 0106 measures every leg here already, so the gate is asked of the
--      figure that was just measured — one measurement, two uses, and no second arithmetic.
('cmd.standing_route_save_for(uuid, uuid, text, jsonb, bigint, integer, integer)', 1,
$h$      insert into public.standing_route_stops (route_id, ord, port_id, course, repair, crew_up, course_nm)$h$,
$h$      -- 0107 (owner row 117): A ROUTE IS REFUSED WHEN IT IS WRITTEN. The leg was measured one
      -- statement ago, so the gate is asked of that very figure; a route discovered to be illegal
      -- at sea is a route that pauses in a strange harbour at three in the morning. The refusal
      -- carries the server's own sentence through this door's own refusal shape.
      v_gate := public.passage_gate(p_player, v_leg_nm, v_port.id);
      if v_gate is not null then
        return cmd.standing_route_refusal(v_gate->>'code', v_gate->>'sentence',
                                          '(shorten the route or study)');
      end if;
      insert into public.standing_route_stops (route_id, ord, port_id, course, repair, crew_up, course_nm)$h$),
('cmd.standing_route_save_for(uuid, uuid, text, jsonb, bigint, integer, integer)', 2,
$h$  v_leg_nm numeric;   -- 0106: the leg's measured length, stored on the stop$h$,
$h$  v_leg_nm numeric;   -- 0106: the leg's measured length, stored on the stop
  v_gate   jsonb;     -- 0107: the earned-passage refusal for that leg (cmd.refusal), or null$h$),
-- (iii) THE CAPS. Both flat reads become the earned ones, from the ONE reading.
('public.assert_house_caps(uuid, uuid)', 1,
$h$  select count(*) into v_fleets from public.fleets where player_id = p_player;
  if v_fleets > public.wc_int('fleet_max') then
    raise exception 'E_FLEET_MAX: the house may keep % fleet(s) and this would make %',
      public.wc_int('fleet_max'), v_fleets using errcode = 'P0001';
  end if;$h$,
$h$  -- 0107 (owner row 113b): the caps are EARNED. public.earned_caps lifts the fleet count with the
  -- TRADING level (never below the flat cap) and tightens the per-fleet hull count with SEAMANSHIP
  -- (never above it). One reading, so this trigger and any face that prints a cap agree.
  v_caps := public.earned_caps(p_player);
  select count(*) into v_fleets from public.fleets where player_id = p_player;
  if v_fleets > (v_caps->>'fleet_max')::int then
    raise exception 'E_FLEET_MAX: the house may keep % fleet(s) and this would make %',
      (v_caps->>'fleet_max')::int, v_fleets using errcode = 'P0001';
  end if;$h$),
('public.assert_house_caps(uuid, uuid)', 2,
$h$    if v_in_fleet > public.wc_int('fleet_ship_max') then
      raise exception 'E_FLEET_SHIP_MAX: a fleet sails % ship(s) at most and this would make %',
        public.wc_int('fleet_ship_max'), v_in_fleet using errcode = 'P0001';
    end if;$h$,
$h$    if v_in_fleet > (v_caps->>'fleet_ship_max')::int then
      raise exception 'E_FLEET_SHIP_MAX: a fleet sails % ship(s) at most and this would make %',
        (v_caps->>'fleet_ship_max')::int, v_in_fleet using errcode = 'P0001';
    end if;$h$),
('public.assert_house_caps(uuid, uuid)', 3,
$h$  v_in_fleet int;
begin$h$,
$h$  v_in_fleet int;
  v_caps     jsonb;   -- 0107: what this house has earned
begin$h$);

insert into defs_before_0107
select f.fn, replace(pg_get_functiondef(f.fn::regprocedure), E'\r', ''),
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '')
  from (select distinct fn from hunks_0107) as f(fn);

create or replace function pg_temp.recut_0107(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := (select def from defs_before_0107 where fn = p_fn);
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0107 where fn = p_fn order by n loop
    v_n := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
    if v_n <> 1 then
      raise exception '0107: hunk % of % matches the pre-image % time(s), not once', h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0107(fn) from (select distinct fn from hunks_0107) x order by fn;

-- ── 5. GRANTS ──────────────────────────────────────────────────────────────────────────────────
revoke all on function public.skill_level(uuid, text)                from public, anon, authenticated;
revoke all on function public.earned_caps(uuid)                      from public, anon, authenticated;
revoke all on function public.passage_gate(uuid, numeric, uuid)      from public, anon, authenticated;

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  c_auth    constant uuid := '00000000-0107-4000-8000-0000000000a1';
  v_fn      text;
  v_def     text;
  v_back    text;
  h         record;
  v_n       int;
  v_base    int;
  v_me      uuid;
  v_fleet   uuid;
  v_lis     uuid;
  v_fnc     uuid;
  v_nag     uuid;
  v_leg     jsonb;
  v_back_c  jsonb;
  v_res     jsonb;
  v_gate    jsonb;
  v_caps    jsonb;
  v_lvl     int;
  v_need    int;
  v_nm      numeric;
  v_regions int;
  v_drift   int;
  v_merch   uuid;
  v_err     text;
  v_sk      uuid;
begin
  -- (a) EVERY RE-CUT IS ITS PRE-IMAGE PLUS ONLY THIS FILE'S HUNKS, ACLs UNMOVED.
  for v_fn in select distinct fn from hunks_0107 loop
    v_def := replace(pg_get_functiondef(v_fn::regprocedure), E'\r', '');
    v_back := v_def;
    for h in select * from hunks_0107 where fn = v_fn order by n desc loop
      v_n := (length(v_back) - length(replace(v_back, h.new, ''))) / length(h.new);
      if v_n <> 1 then
        raise exception '0107 self-assert FAIL: hunk % of % is in the new body % time(s), not once', h.n, v_fn, v_n;
      end if;
      v_back := replace(v_back, h.new, h.old);
    end loop;
    if v_back <> (select def from defs_before_0107 where fn = v_fn) or v_def = v_back then
      raise exception '0107 self-assert FAIL: % is not its pre-image plus only 0107''s hunks', v_fn;
    end if;
    if coalesce((select p.proacl::text from pg_proc p where p.oid = v_fn::regprocedure), '')
       is distinct from (select acl from defs_before_0107 where fn = v_fn) then
      raise exception '0107 self-assert FAIL: the re-cut moved the ACL of %', v_fn;
    end if;
  end loop;

  -- (b) THE NEW READINGS ARE REACHABLE BY NOBODY, and the walls still read zero.
  if has_function_privilege('authenticated', 'public.passage_gate(uuid, numeric, uuid)', 'execute')
     or has_function_privilege('anon', 'public.passage_gate(uuid, numeric, uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.earned_caps(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.skill_level(uuid, text)', 'execute') then
    raise exception '0107 self-assert FAIL: a gate or a cap reading is reachable by a client';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0107 self-assert FAIL: the grant wall or the read wall';
  end if;

  -- (c) A REGION'S PRICE OF ENTRY IS THE DERIVATION, re-run here off the sailed water.
  select id into v_lis from public.ports where code = 'LIS';
  select count(*),
         count(*) filter (where r.min_exploration_level <> greatest(1, least(
                   public.wc_int('region_level_max'),
                   1 + floor(n.nm / public.wc_num('region_level_nm_step'))::int)))
    into v_regions, v_drift
    from public.regions r
    join (select p.region_id,
                 min(case when p.id = v_lis then 0
                          else (select (sr.reaches->>p.code)::numeric
                                  from public.sea_reaches sr where sr.port_id = v_lis) end) as nm
            from public.ports p
           where p.kind = 'HARBOUR' and p.region_id is not null
           group by p.region_id) n on n.region_id = r.id;
  if v_regions < 10 or v_drift <> 0 then
    raise exception '0107 self-assert FAIL: % of % region level(s) disagree with the derivation', v_drift, v_regions;
  end if;
  -- IBERIA IS OPEN ON DAY ONE and the far side of the world is not — the point of the ladder.
  if (select r.min_exploration_level from public.regions r
       join public.ports p on p.region_id = r.id where p.code = 'LIS') <> 1 then
    raise exception '0107 self-assert FAIL: the founding frame''s own region is not open at level 1';
  end if;
  if (select max(min_exploration_level) from public.regions) < 3
     or (select count(distinct min_exploration_level) from public.regions) < 3 then
    raise exception '0107 self-assert FAIL: the region ladder is flat (max %, % distinct level(s))',
      (select max(min_exploration_level) from public.regions),
      (select count(distinct min_exploration_level) from public.regions);
  end if;

  -- (d) THE GATES THEMSELVES, on a probe house, rolled back.
  select count(*) into v_base from public.players;
  begin
    update public.world_config set value = to_jsonb(0.0) where key = 'hazard_p_max';
    update public.world_config set value = 'true'::jsonb where key = 'standing_routes_enabled';
    select id into v_fnc from public.ports where code = 'FNC';
    select id into v_nag from public.ports where code = 'NAG';
    v_me := public.new_house(c_auth, 'Casa do Limite', 'PRT');
    select id into v_fleet from public.fleets where player_id = v_me;
    update public.fleets set port_id = v_lis, status = 'DOCKED' where id = v_fleet;

    -- (d1) A NEW HOUSE HAS EARNED THE BASE AND NOTHING MORE.
    v_caps := public.earned_caps(v_me);
    if (v_caps->>'earned')::boolean is not true
       or (v_caps->>'fleet_ship_max')::int <> public.wc_int('fleet_ship_base')
       or (v_caps->>'fleet_max')::int <> greatest(public.wc_int('fleet_max'),
                                                  public.wc_int('fleet_max_base') + 1) then
      raise exception '0107 self-assert FAIL: a new house''s earned caps are %', v_caps;
    end if;
    if public.skill_level(v_me, 'SEAMANSHIP') <> 0 then
      raise exception '0107 self-assert FAIL: a house that has studied nothing reads SEAMANSHIP %',
        public.skill_level(v_me, 'SEAMANSHIP');
    end if;
    -- ...and STUDYING MOVES IT. The positive control on the whole cap half: one skill row, and the
    -- per-fleet cap goes up by one.
    select id into v_sk from public.skills where code = 'SEAMANSHIP';
    insert into public.player_skills (player_id, skill_id, level) values (v_me, v_sk, 3);
    if (public.earned_caps(v_me)->>'fleet_ship_max')::int <> public.wc_int('fleet_ship_base') + 3 then
      raise exception '0107 self-assert FAIL: SEAMANSHIP 3 did not lift the per-fleet cap (%)',
        public.earned_caps(v_me)->>'fleet_ship_max';
    end if;
    -- and it never exceeds the flat ceiling, whatever she studies
    update public.player_skills set level = 20 where player_id = v_me and skill_id = v_sk;
    if (public.earned_caps(v_me)->>'fleet_ship_max')::int <> public.wc_int('fleet_ship_max') then
      raise exception '0107 self-assert FAIL: the earned per-fleet cap passed the flat ceiling (%)',
        public.earned_caps(v_me)->>'fleet_ship_max';
    end if;
    delete from public.player_skills where player_id = v_me and skill_id = v_sk;

    -- (d2) THE LENGTH GATE. Funchal is inside a beginner's reach and Nagasaki is not.
    v_nm := (select (sr.reaches->>'FNC')::numeric from public.sea_reaches sr where sr.port_id = v_lis);
    if public.passage_gate(v_me, v_nm, v_fnc) is not null then
      raise exception '0107 self-assert FAIL: Lisbon to Funchal (% nm) was refused a beginner: %',
        round(v_nm), public.passage_gate(v_me, v_nm, v_fnc);
    end if;
    v_nm := (select (sr.reaches->>'NAG')::numeric from public.sea_reaches sr where sr.port_id = v_lis);
    v_gate := public.passage_gate(v_me, v_nm, v_nag);
    if v_gate is null or v_gate->>'code' <> 'E_LEG_TOO_FAR' then
      raise exception '0107 self-assert FAIL: Lisbon to Nagasaki in one leg (% nm) was not refused on length: %',
        round(v_nm), coalesce(v_gate::text, '(allowed)');
    end if;
    -- 0050's point: the refusal carries the two numbers it turned on, so a face can draw them.
    if (v_gate->'figures'->>'nm')::numeric <> round(v_nm)
       or (v_gate->'figures'->>'reach_nm')::numeric <> round(public.wc_num('nav_leg_nm_base')) then
      raise exception '0107 self-assert FAIL: the length refusal does not carry its own two figures: %', v_gate;
    end if;
    -- POSITIVE CONTROL: five levels of navigation and the same leg is allowed, because the reach
    -- DOUBLES. If it did not, the ladder would be decoration.
    insert into public.player_skills (player_id, skill_id, level)
    select v_me, sk.id, 5 from public.skills sk where sk.code = 'NAVIGATION';
    if public.skill_level(v_me, 'NAVIGATION') <> 5 then
      raise exception '0107 self-assert FAIL: the probe could not be given NAVIGATION 5 — the catalogue reads %',
        public.skill_level(v_me, 'NAVIGATION');
    end if;
    -- The claim is about the LENGTH gate alone: at NAVIGATION 5 that gate opens. Nagasaki's REGION
    -- is still priced at level 5 and still closes it, which is the other gate doing its own job and
    -- is proven on its own below — so this asserts the length refusal is GONE, not that the
    -- passage is clear. (The first cut asserted the passage was clear and read back
    -- "E_REGION_CLOSED: Japan & the Ryukyus asks exploration level 5 and yours is 1": two gates
    -- conflated in one control, which is exactly what a control is for.)
    if public.wc_num('nav_leg_nm_base') * 16 < v_nm then
      raise exception '0107 self-assert FAIL: NAVIGATION 5 reaches only % nm and the leg is % nm, so the control cannot say anything',
        public.wc_num('nav_leg_nm_base') * 16, round(v_nm);
    end if;
    if coalesce(public.passage_gate(v_me, v_nm, v_nag)->>'code', '') = 'E_LEG_TOO_FAR' then
      raise exception '0107 self-assert FAIL: NAVIGATION 5 reaches % nm and the leg is % nm, yet the LENGTH gate still refused it: %',
        public.wc_num('nav_leg_nm_base') * 16, round(v_nm), public.passage_gate(v_me, v_nm, v_nag);
    end if;
    -- and on a harbour in a region she HAS earned, the same reach is simply clear
    if public.passage_gate(v_me, v_nm, (select p.id from public.ports p
                                          join public.regions r on r.id = p.region_id
                                         where p.kind = 'HARBOUR' and r.min_exploration_level = 1
                                         order by p.code limit 1)) is not null then
      raise exception '0107 self-assert FAIL: NAVIGATION 5 on a % nm leg into an open region was still refused: %',
        round(v_nm), public.passage_gate(v_me, v_nm, (select p.id from public.ports p
                                                       join public.regions r on r.id = p.region_id
                                                      where p.kind = 'HARBOUR' and r.min_exploration_level = 1
                                                      order by p.code limit 1));
    end if;
    delete from public.player_skills ps using public.skills sk
     where ps.skill_id = sk.id and ps.player_id = v_me and sk.code = 'NAVIGATION';

    -- (d3) THE REGION GATE, on a leg short enough that length cannot be the reason. A region the
    --      derivation prices above level 1 is refused a house that has sailed nowhere.
    select p.id, r.min_exploration_level into v_nag, v_need
      from public.ports p join public.regions r on r.id = p.region_id
     where p.kind = 'HARBOUR' and r.min_exploration_level > 1
     order by r.min_exploration_level desc, p.code limit 1;
    v_gate := public.passage_gate(v_me, 1, v_nag);
    if v_gate is null or v_gate->>'code' <> 'E_REGION_CLOSED'
       or (v_gate->'figures'->>'needs')::int <> v_need then
      raise exception '0107 self-assert FAIL: a region priced at level % was not closed to a house at level %: %',
        v_need, (public.player_progress(v_me)->'exploration'->>'level')::int, coalesce(v_gate::text, '(allowed)');
    end if;
    -- POSITIVE CONTROL: the SAME harbour on the SAME leg opens once the region is priced at 1, so
    -- it was the level that closed it and not the harbour, the draft or the leg.
    update public.regions set min_exploration_level = 1
     where id = (select region_id from public.ports where id = v_nag);
    if public.passage_gate(v_me, 1, v_nag) is not null then
      raise exception '0107 self-assert FAIL: the same harbour stayed closed with its region priced at 1: %',
        public.passage_gate(v_me, 1, v_nag);
    end if;

    -- (d4) MERCHANTS ARE EXEMPT, and a null player is too.
    select p.id into v_merch from public.players p where p.is_npc limit 1;
    if v_merch is null then
      raise exception '0107 self-assert FAIL: there is no merchant company to test the exemption on';
    end if;
    update public.regions set min_exploration_level = public.wc_int('region_level_max')
     where id = (select region_id from public.ports where id = v_nag);
    if public.passage_gate(v_merch, 999999, v_nag) is not null then
      raise exception '0107 self-assert FAIL: the gate refused a merchant company: %',
        public.passage_gate(v_merch, 999999, v_nag);
    end if;
    if public.passage_gate(null, 999999, v_nag) is not null then
      raise exception '0107 self-assert FAIL: the gate refused a null player';
    end if;
    if (public.earned_caps(v_merch)->>'earned')::boolean is not false
       or (public.earned_caps(v_merch)->>'fleet_ship_max')::int <> public.wc_int('fleet_ship_max') then
      raise exception '0107 self-assert FAIL: a merchant does not get the flat caps: %', public.earned_caps(v_merch);
    end if;

    -- (d5) THROUGH THE DOORS, which is the whole point: refused where it is WRITTEN and where she
    --      would SAIL, not discovered at sea.
    v_leg := (select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon),
                                       jsonb_build_array(b.roadstead_lat, b.roadstead_lon))
                from public.sea_reaches a, public.sea_reaches b
               where a.port_id = v_lis and b.port_id = v_fnc);
    v_back_c := jsonb_build_array(v_leg->1, v_leg->0);
    -- a route inside her reach still saves, exactly as before this file
    if coalesce((cmd.standing_route_save_for(v_me, null, 'Perto',
                   jsonb_build_array(jsonb_build_object('port', 'LIS', 'course', v_leg),
                                     jsonb_build_object('port', 'FNC', 'course', v_back_c)),
                   null, null, 0)->>'ok')::boolean, false) is not true then
      raise exception '0107 self-assert FAIL: a route inside her reach was refused: %',
        cmd.standing_route_save_for(v_me, null, 'Perto2',
          jsonb_build_array(jsonb_build_object('port', 'LIS', 'course', v_leg),
                            jsonb_build_object('port', 'FNC', 'course', v_back_c)), null, null, 0);
    end if;
    -- ...and the SAME route is refused the moment her reach is cut under it, through the door
    update public.world_config set value = to_jsonb(10) where key = 'nav_leg_nm_base';
    v_res := cmd.standing_route_save_for(v_me, null, 'Longe',
               jsonb_build_array(jsonb_build_object('port', 'LIS', 'course', v_leg),
                                 jsonb_build_object('port', 'FNC', 'course', v_back_c)),
               null, null, 0);
    if coalesce((v_res->>'ok')::boolean, true) is not false
       or v_res->>'error_code' <> 'E_LEG_TOO_FAR' then
      raise exception '0107 self-assert FAIL: the save door accepted a leg beyond her navigation: %', v_res;
    end if;
    -- and the SEA's own door says the same thing about the same water
    v_gate := voyage.sail_refusal(v_fleet, v_fnc, null,
                (select (sr.reaches->>'FNC')::numeric from public.sea_reaches sr where sr.port_id = v_lis));
    if v_gate is null or v_gate->>'code' <> 'E_LEG_TOO_FAR' then
      raise exception '0107 self-assert FAIL: voyage.sail_refusal did not refuse the same leg: %',
        coalesce(v_gate::text, '(allowed)');
    end if;
    update public.world_config set value = to_jsonb(900) where key = 'nav_leg_nm_base';
    -- ...and with her reach back, that door answers exactly what it answered before this file:
    -- a fleet with no stores is refused on STORES, not on her captain.
    v_gate := voyage.sail_refusal(v_fleet, v_fnc, null,
                (select (sr.reaches->>'FNC')::numeric from public.sea_reaches sr where sr.port_id = v_lis));
    if v_gate is not null and v_gate->>'code' = 'E_LEG_TOO_FAR' then
      raise exception '0107 self-assert FAIL: her own reach still refused her: %', v_gate;
    end if;

    raise exception 'ROLLBACK_0107';
  exception when others then
    if sqlerrm <> 'ROLLBACK_0107' then raise; end if;
  end;

  if (select count(*) from public.players) <> v_base
     or public.wc_int('nav_leg_nm_base') <> 900 then
    raise exception '0107 self-assert FAIL: the probe did not leave the world as it found it';
  end if;

  raise notice '0107 self-assert ok: THE OCEAN IS EARNED AT THE ACADEMY. voyage.sail_refusal, '
    'cmd.standing_route_save_for and public.assert_house_caps are each their pre-image plus only '
    'this file''s hunks with ACLs unmoved; passage_gate, earned_caps and skill_level are reachable '
    'by nobody and the grant and read walls still read zero. Every one of % region level(s) equals '
    'the derivation re-run off Lisbon''s own SAILED distances — 0 disagreements, the founding '
    'frame''s own region open at level 1, and at least three distinct levels in the ladder so it is '
    'not decoration. On a probe house, rolled back: a new house has earned the base per-fleet cap '
    'and no more, SEAMANSHIP 3 lifts it by three, and twenty levels of it never pass the flat '
    'ceiling. Lisbon to Funchal is inside a beginner''s reach; Lisbon to Nagasaki in ONE leg is '
    'refused E_LEG_TOO_FAR — carrying the two figures it turned on — and allowed at NAVIGATION 5, '
    'because the reach doubles. A region the '
    'derivation prices above level 1 is refused E_REGION_CLOSED on a one-mile leg, and the SAME '
    'harbour opens when its region is priced at 1 — so it was the level and not the harbour. A '
    'MERCHANT company is exempt on a 999,999 nm leg into the dearest region there is, so is a null '
    'player, and a merchant reads the flat caps. Through the doors: a route inside her reach saves, '
    'the same route is refused E_LEG_TOO_FAR by the SAVE door when her reach is cut under it, '
    'voyage.sail_refusal refuses the same water in the same words, and with her reach restored that '
    'door stops mentioning her captain at all.', v_regions;
end $$;
