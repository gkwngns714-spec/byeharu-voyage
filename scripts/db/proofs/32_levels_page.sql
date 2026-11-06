-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 32 — THE LEVELS PAGE READS ONE THING  (migration 0327, owner 2026-11-06: "first create a tab on command - levels")
--
--   world.levels() is a read that composes the readers that own each figure. This proof runs it for a probe company, as `authenticated`, dark and lit, and
--   checks every figure against the reader that owns it. Everything rolls back with proof.mjs's transaction.
--
-- @pass LEVELS_DOOR       as authenticated the read answers; anon is refused 42501; a caller with no company gets {company: false}
-- @pass LEVELS_TRACKS     each track equals public.player_progress; `from` and `next_at` are public.level_points of its level and the next; the next title names the sea zones that ask it
-- @pass LEVELS_HULLS      a hull's EARNED level is read from ship_xp on the one curve; dark it acts as level 1, lit as her own; the top level has no next_at
-- @pass LEVELS_ROOM       the room is public.earned_caps, with the fleets she has; the title is public.title_level and the next title's name
-- @pass LEVELS_REGARD     dark: null. Lit: every great power, the home country at its stance base (200, Friendly), sorted highest first
-- @pass LEVELS_READ_ONLY  the read is STABLE and wrote no event and no row of the probe's
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $$
declare
  c_uid   constant uuid := '00000000-0f32-4000-8000-000000000001';
  v_p     uuid;
  v_ship  uuid;
  v_r     jsonb;
  v_pp    jsonb;
  v_x     jsonb;
  v_ev0   bigint;
  v_n     int;
  v_denied boolean := false;
begin
  v_p := public.new_house(c_uid, 'Casa dos Niveis 0f32', 'PRT', 'LIS');
  select s.id into v_ship from public.ships s where s.player_id = v_p order by s.created_at limit 1;
  perform cmd.assume_identity(c_uid);
  if public.levels_bite_on() or public.regard_on() then
    raise exception 'PROOF 32 FAIL: levels_bite or regard_enabled is lit in this world; the proof owns the dark start';
  end if;
  v_ev0 := (select count(*) from public.events e where e.player_id = v_p);

  -- ── THE DOOR ──
  set local role authenticated;
  v_r := world.levels();
  reset role;
  set local role anon;
  begin
    perform world.levels();
  exception when insufficient_privilege then v_denied := true;
  end;
  reset role;
  perform cmd.assume_identity('00000000-0f32-4000-8000-0000000000ff');
  v_x := world.levels();
  perform cmd.assume_identity(c_uid);
  if v_denied is not true or (v_r ->> 'company') <> 'true' or (v_x ->> 'company') <> 'false' then
    raise exception 'PROOF 32 FAIL: the door: anon refused %, answer %, a stranger %', v_denied, v_r ->> 'company', v_x;
  end if;
  raise notice 'PASS: LEVELS_DOOR — authenticated reads, anon is refused, a caller with no company reads {company: false}';

  -- ── THE TRACKS ──
  v_pp := public.player_progress(v_p);
  for v_n in 1..3 loop
    declare
      k text := (array['trading', 'exploration', 'combat'])[v_n];
      lvl int := (v_pp -> k ->> 'level')::int;
    begin
      if (v_r -> 'tracks' -> k ->> 'level')::int <> lvl
         or (v_r -> 'tracks' -> k ->> 'points')::numeric <> floor((v_pp -> k ->> 'points')::numeric)
         or (v_r -> 'tracks' -> k ->> 'from')::numeric <> public.level_points(lvl)
         or (v_r -> 'tracks' -> k ->> 'next_at')::numeric <> public.level_points(lvl + 1) then
        raise exception 'PROOF 32 FAIL: track % is not player_progress cut by level_points: % vs %', k, v_r -> 'tracks' -> k, v_pp -> k;
      end if;
    end;
  end loop;
  if (v_r -> 'tracks' -> 'combat' ->> 'playable')::boolean is distinct from (v_pp -> 'combat' ->> 'playable')::boolean then
    raise exception 'PROOF 32 FAIL: combat playable moved';
  end if;
  raise notice 'PASS: LEVELS_TRACKS — three tracks equal player_progress; from and next_at are level_points';

  -- ── THE HULLS ──
  insert into public.ship_xp (ship_id, xp) values (v_ship, public.level_points(3) + 5)
    on conflict (ship_id) do update set xp = excluded.xp;
  v_r := world.levels();
  v_x := (select e from jsonb_array_elements(v_r -> 'ships') e where (e ->> 'id')::uuid = v_ship);
  if (v_x ->> 'level')::int <> 3 or (v_x ->> 'in_force')::int <> 1 or (v_x ->> 'from')::numeric <> public.level_points(3)
     or (v_x ->> 'next_at')::numeric <> public.level_points(4) or (v_x ->> 'points')::numeric <> public.level_points(3) + 5 then
    raise exception 'PROOF 32 FAIL: dark, a level 3 hull reads %', v_x;
  end if;
  if (v_r ->> 'bite') <> 'false' then
    raise exception 'PROOF 32 FAIL: dark, bite reads %', v_r ->> 'bite';
  end if;
  update public.world_config set value = 'true'::jsonb where key = 'levels_bite';
  v_r := world.levels();
  v_x := (select e from jsonb_array_elements(v_r -> 'ships') e where (e ->> 'id')::uuid = v_ship);
  if (v_x ->> 'in_force')::int <> 3 or (v_r ->> 'bite') <> 'true' or (v_r -> 'ships' -> 0 ->> 'id')::uuid <> v_ship then
    raise exception 'PROOF 32 FAIL: lit, the hull acts as % (bite %), first row %', v_x ->> 'in_force', v_r ->> 'bite', v_r -> 'ships' -> 0 ->> 'id';
  end if;
  update public.ship_xp set xp = public.level_points(1000) where ship_id = v_ship;
  v_x := (select e from jsonb_array_elements(world.levels() -> 'ships') e where (e ->> 'id')::uuid = v_ship);
  if (v_x ->> 'level')::int <> public.level_from_points(public.level_points(1000)) or (v_x ->> 'next_at') is not null then
    raise exception 'PROOF 32 FAIL: the top level names a next one: %', v_x;
  end if;
  update public.world_config set value = 'false'::jsonb where key = 'levels_bite';
  raise notice 'PASS: LEVELS_HULLS — earned level 3 acts as 1 dark and 3 lit, her bar runs from level_points(3) to level_points(4), the top has no next';

  -- ── THE ROOM AND THE TITLE ──
  v_r := world.levels();
  if (v_r -> 'room' ->> 'fleet_max')::int <> (public.earned_caps(v_p) ->> 'fleet_max')::int
     or (v_r -> 'room' ->> 'fleet_ship_max')::int <> (public.earned_caps(v_p) ->> 'fleet_ship_max')::int
     or (v_r -> 'room' ->> 'fleets')::int <> (select count(*) from public.fleets f where f.player_id = v_p)
     or (v_r -> 'title' ->> 'level')::int <> public.title_level(v_p)
     or (v_r -> 'title' ->> 'name') is distinct from (select t.name from public.title_names t where t.level = public.title_level(v_p))
     or (v_r -> 'title' -> 'next' ->> 'name') is distinct from (select t.name from public.title_names t where t.level = public.title_level(v_p) + 1)
     or (v_r -> 'title' -> 'next' -> 'opens') is distinct from (select coalesce(jsonb_agg(z.name order by z.ord), '[]'::jsonb) from public.sea_zones z where z.title_min = public.title_level(v_p) + 1)
     or (v_r -> 'title' ->> 'seas_bite')::boolean is distinct from (public.wc('sea_conditions_bite') = 'true'::jsonb)
     or (v_r -> 'skills' -> 'seamanship' ->> 'level')::int <> public.skill_level(v_p, 'SEAMANSHIP') then
    raise exception 'PROOF 32 FAIL: room, title or seamanship disagree with their readers: %', v_r;
  end if;
  raise notice 'PASS: LEVELS_ROOM — room %, title % (next %), seamanship %', v_r -> 'room', v_r -> 'title' ->> 'name', v_r -> 'title' -> 'next' ->> 'name', v_r -> 'skills' -> 'seamanship' ->> 'level';

  -- ── REGARD ──
  if (v_r -> 'regard') <> 'null'::jsonb then
    raise exception 'PROOF 32 FAIL: dark, regard is served: %', v_r -> 'regard';
  end if;
  update public.world_config set value = 'true'::jsonb where key = 'regard_enabled';
  v_r := world.levels();
  if jsonb_array_length(v_r -> 'regard') <> (select count(*) from public.great_powers) then
    raise exception 'PROOF 32 FAIL: lit, regard names % countries, not every great power', jsonb_array_length(v_r -> 'regard');
  end if;
  v_x := (select e from jsonb_array_elements(v_r -> 'regard') e where e ->> 'code' = 'PRT');
  if (v_x ->> 'score')::numeric <> 200 or (v_x ->> 'band') <> 'friendly' or (v_r -> 'regard' -> 0 ->> 'score')::numeric < (v_r -> 'regard' -> -1 ->> 'score')::numeric then
    raise exception 'PROOF 32 FAIL: lit, home regard reads % or the list is not sorted: %', v_x, v_r -> 'regard';
  end if;
  update public.world_config set value = 'false'::jsonb where key = 'regard_enabled';
  raise notice 'PASS: LEVELS_REGARD — dark null; lit % countries, home at 200 Friendly', jsonb_array_length(v_r -> 'regard');

  -- ── READ ONLY ──
  if (select p.provolatile from pg_proc p where p.oid = 'world.levels()'::regprocedure) <> 's'
     or (select count(*) from public.events e where e.player_id = v_p) <> v_ev0 then
    raise exception 'PROOF 32 FAIL: the read is not stable or it wrote an event';
  end if;
  raise notice 'PASS: LEVELS_READ_ONLY — stable, no event written';
end $$;
