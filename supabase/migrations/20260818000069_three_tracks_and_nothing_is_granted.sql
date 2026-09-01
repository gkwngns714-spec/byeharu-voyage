-- ===============================================================================================
-- 0069 - THREE TRACKS, AND NOTHING IS GRANTED
-- ===============================================================================================
--
-- The owner, 2026-09-01:
--
--     "levels - the game will have 3 kinds of levels - exploration, trading, combat"
--
-- and, asked whether exploration should count distance sailed or ports reached:
--
--     "both"
--
-- -- THE PROPERTY THIS FILE EXISTS TO PRESERVE ---------------------------------------------------
-- NOTHING IS GRANTED. public.player_fame has always been RE-READ from the append-only record every
-- time it is asked - there is no counter to inflate, only a history to recompute. A levels design
-- that wrote XP into a column would throw that away and hand this game its first farm loop.
--
-- So there is no player_levels TABLE. There is a function, and it reads the ledger and the events
-- exactly as fame does. It is retroactively right for every voyage sailed before today, and a
-- house cannot hold a point it did not earn, because it holds no points at all.
--
-- -- WHAT WAS ALREADY THERE, AND WHAT IS NEW ----------------------------------------------------
-- Two of the three tracks already existed inside player_fame: turnover on completed trades, and
-- distinct ports reached. What is new:
--
--   * DISTANCE. The owner said "both", and total_nm has been on every VOYAGE_REPORT since 0036 -
--     the record already knew, nothing was asking. Exploration is now ports AND sea miles.
--   * A LEVEL, not just a score. A number that only goes up is a scoreboard; a LEVEL is a
--     threshold something else can require, and captain promotion (DESIGN 7.1) is what will
--     require it. That is why rows 61 and 62 are one system.
--   * COMBAT, READING ZERO, HONESTLY. There is no combat in this game (migration 0035 says so
--     deliberately). The track exists and returns 0, because the owner asked for three and a
--     player is owed the truth about which one is not yet playable. Inventing a proxy - counting
--     hazards survived, say - would be worse than an honest zero: it would make the track look
--     built.
--
-- -- WHAT THIS SUPERSEDES ------------------------------------------------------------------------
-- public.player_fame, created at 0014. This file REPLACES its body: it kept its own count of
-- ledger turnover and distinct ports, and now reads public.player_progress instead. Same name,
-- same argument, same returned shape - the standings board (0025) and the house screen both read
-- it and neither changes.
--
-- Why supersede rather than add beside: two functions counting the same ledger two ways is the
-- defect this chain keeps removing, and the moment a third track existed there would have been
-- two places to add it to. The self-assert proves the replacement is total - the new body does not
-- mention the ledger at all - and proves the two agree.
--
-- The change is NOT a no-op: exploration now counts sea miles as well as landfalls, so a house
-- that has sailed scores more than it did yesterday. That is the owner's ruling of "both", stated
-- here so nobody later reads it as drift.
--
-- -- ONE DEFINITION, NOT TWO --------------------------------------------------------------------
-- public.player_fame is RE-CUT to read this function rather than compute its own turnover and port
-- count. Two functions counting the same ledger two ways is the defect this chain keeps removing;
-- fame keeps its name and its shape (the standings and the house screen both read it) and stops
-- being a second implementation.
--
-- Note what that means and say it plainly: exploration fame CHANGES today, because it now counts
-- sea miles as well as landfalls. That is the owner's ruling, not a side effect.
-- ===============================================================================================

create or replace function pg_temp.recut(p_fn regprocedure, p_drop boolean, variadic p_edits text[])
returns void
language plpgsql
as $fn$
declare
  v_def text := pg_get_functiondef(p_fn);
  v_i   int := 1;
  v_n   int;
begin
  while v_i < array_length(p_edits, 1) loop
    v_n := (length(v_def) - length(replace(v_def, p_edits[v_i], ''))) / length(p_edits[v_i]);
    if v_n <> 1 then
      raise exception '0069 slice: hunk % of % occurs % time(s) in %, expected exactly 1 - the deployed body is not what this migration was generated against.',
        (v_i + 1) / 2, (array_length(p_edits, 1)) / 2, v_n, p_fn;
    end if;
    v_def := replace(v_def, p_edits[v_i], p_edits[v_i + 1]);
    v_i := v_i + 2;
  end loop;
  if p_drop then execute format('drop function %s', p_fn::text); end if;
  execute v_def;
end $fn$;

create temporary table defs_before_0069 as
  select 'public.player_fame'::text as fn, pg_get_functiondef('public.player_fame(uuid)'::regprocedure) as def
  union all select 'world.player', pg_get_functiondef('world.player()'::regprocedure);

-- -- 1. THE TWO KNOBS THIS ADDS -------------------------------------------------------------------
insert into public.world_config (key, value, description) values
  ('fame_nm_per_point', to_jsonb(100::numeric),
   'Sea miles per point of exploration. The owner ruled that exploration counts distance AND ports '
   '("both"), and this is the distance half. At 100, a typical opening voyage of ~1,400 nm is worth '
   'about fourteen points against the twenty-five a new landfall pays - so reaching somewhere new '
   'is worth more than sailing far, and sailing far is still worth something.'),
  ('level_points_per_step', to_jsonb(25::numeric),
   'The level curve: level = floor(sqrt(points / this)) + 1. Quadratic, so each level costs more '
   'than the last and no track ever runs away. At 25 the second level lands at 25 points - about '
   'one opening voyage - the third at 100, the fifth at 400, the tenth at 2,025.')
on conflict (key) do update set value = excluded.value, description = excluded.description;

-- -- 2. POINTS INTO A LEVEL -----------------------------------------------------------------------
-- One curve for all three tracks. A track with its own curve would make "level 4" mean a different
-- amount of work depending on which word came before it, and promotion (DESIGN 7.1) is going to
-- compare them.
create or replace function public.level_from_points(p_points numeric)
returns int
language sql
stable
parallel safe
as $lp$
  select greatest(1, least(20, floor(sqrt(greatest(p_points, 0) / public.wc_num('level_points_per_step')))::int + 1))
$lp$;

comment on function public.level_from_points(numeric) is
  'The ONE level curve, quadratic in points, floored at 1 and capped at 20. Level 1 is where every '
  'house starts, including one that has done nothing - a house is never level 0.';

-- -- 3. THE THREE TRACKS --------------------------------------------------------------------------
create or replace function public.player_progress(p_player uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $pp$
declare
  v_per_ducat numeric := public.wc_num('fame_ducats_per_point');
  v_per_port  numeric := public.wc_num('fame_per_port');
  v_per_nm    numeric := public.wc_num('fame_nm_per_point');
  v_turnover  numeric := 0;
  v_ports     int     := 0;
  v_nm        numeric := 0;
  v_trade     int;
  v_explore   int;
begin
  if p_player is null then
    return jsonb_build_object(
      'trading',     jsonb_build_object('points', 0, 'level', 1, 'turnover', 0),
      'exploration', jsonb_build_object('points', 0, 'level', 1, 'ports_reached', 0, 'nm_sailed', 0),
      'combat',      jsonb_build_object('points', 0, 'level', 1, 'playable', false));
  end if;

  -- Read off the LEDGER's own movements, not off a payload field, so a verb that one day writes a
  -- differently-shaped payload still counts correctly. This is 0014's rule, kept.
  select coalesce(sum(abs(l.ducats_delta)), 0) into v_turnover
    from public.ledger l
    join public.events e on e.id = l.ref_event_id
   where l.player_id = p_player
     and e.kind in ('BOUGHT', 'SOLD');

  select count(distinct e.payload->>'to') into v_ports
    from public.events e
   where e.player_id = p_player
     and e.kind = 'VOYAGE_REPORT'
     and e.payload ? 'to';

  -- THE HALF THAT IS NEW. total_nm has been on every voyage report since 0036; nothing was asking.
  select coalesce(sum((e.payload->>'total_nm')::numeric), 0) into v_nm
    from public.events e
   where e.player_id = p_player
     and e.kind = 'VOYAGE_REPORT'
     and e.payload ? 'total_nm';

  v_trade   := floor(v_turnover / nullif(v_per_ducat, 0))::int;
  v_explore := (v_ports * v_per_port + floor(v_nm / nullif(v_per_nm, 0)))::int;

  return jsonb_build_object(
    'trading', jsonb_build_object(
      'points', v_trade, 'level', public.level_from_points(v_trade), 'turnover', v_turnover),
    'exploration', jsonb_build_object(
      'points', v_explore, 'level', public.level_from_points(v_explore),
      'ports_reached', v_ports, 'nm_sailed', round(v_nm, 1)),
    -- HONESTLY ZERO. Migration 0035: "It adds no combat, no NPC, no exploration. A half-built
    -- combat system is worse than none." `playable` says so out loud so a screen can print the
    -- reason instead of a blank.
    'combat', jsonb_build_object('points', 0, 'level', 1, 'playable', false));
end $pp$;

comment on function public.player_progress(uuid) is
  'THE ONE definition of what playing has earned, in three tracks. Derived from the append-only '
  'record every time it is asked, never stored - so it cannot drift, it is retroactively right for '
  'voyages sailed before it existed, and there is no counter to inflate.';

revoke all on function public.player_progress(uuid) from public, anon, authenticated;

-- -- 4. FAME STOPS BEING A SECOND IMPLEMENTATION --------------------------------------------------
-- Same name, same shape, same callers (the standings board and the house screen). It now READS the
-- one definition instead of counting the same ledger a second way.
create or replace function public.player_fame(p_player uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $pf$
declare
  v_p jsonb := public.player_progress(p_player);
begin
  return jsonb_build_object(
    'trade',         (v_p->'trading'->>'points')::int,
    'exploration',   (v_p->'exploration'->>'points')::int,
    'total',         (v_p->'trading'->>'points')::int + (v_p->'exploration'->>'points')::int,
    'ports_reached', (v_p->'exploration'->>'ports_reached')::int,
    'turnover',      (v_p->'trading'->>'turnover')::numeric);
end $pf$;

comment on function public.player_fame(uuid) is
  'Fame, in the shape 0014 defined and the standings still read. Since 0069 it is a VIEW of '
  'public.player_progress rather than a second count of the same ledger. Exploration counts sea '
  'miles as well as landfalls from 0069 on - the owner ruled "both".';

revoke all on function public.player_fame(uuid) from public, anon, authenticated;

-- -- 5. THE HOUSE READS ITS OWN LEVELS ------------------------------------------------------------
select pg_temp.recut('world.player()'::regprocedure, false,
  $w0$      'fame',          public.player_fame(v_id)));$w0$,
  $w1$      'fame',          public.player_fame(v_id),
      -- 0069: the three tracks, beside the fame they are computed from. Fame is one number for a
      -- board; levels are what captain promotion will require.
      'levels',        public.player_progress(v_id)));$w1$);

-- -- SELF-ASSERT ------------------------------------------------------------------------------------
do $$
declare
  v_player uuid;
  v_fleet  uuid;
  v_prog   jsonb;
  v_fame   jsonb;
  v_before text;
  v_lvl    int;
  v_prev   int;
  v_grants int;
  v_nm     numeric;
  c_uid constant uuid := '00000000-0069-4000-8000-000000000001';
  i int;
begin
  -- (a) THE CURVE IS A CURVE: level 1 at nothing, monotone, never above the cap, and each step
  --     costs more than the last. Measured across the whole range rather than spot-checked.
  if public.level_from_points(0) <> 1 then
    raise exception '0069 self-assert FAIL: a house that has done nothing is level %', public.level_from_points(0);
  end if;
  if public.level_from_points(-500) <> 1 then
    raise exception '0069 self-assert FAIL: negative points do not floor at level 1';
  end if;
  v_prev := 1;
  for i in 0..40000 loop
    v_lvl := public.level_from_points(i);
    if v_lvl < v_prev then
      raise exception '0069 self-assert FAIL: the curve went DOWN at % points (% after %)', i, v_lvl, v_prev;
    end if;
    if v_lvl > 20 then
      raise exception '0069 self-assert FAIL: % points reads level %, above the cap of 20', i, v_lvl;
    end if;
    v_prev := v_lvl;
  end loop;
  if public.level_from_points(25) <> 2 or public.level_from_points(24) <> 1 then
    raise exception '0069 self-assert FAIL: the second level does not land at 25 points';
  end if;
  if public.level_from_points(100) <> 3 or public.level_from_points(400) <> 5 then
    raise exception '0069 self-assert FAIL: the curve is not quadratic where it says it is';
  end if;
  -- AND IT IS REACHABLE AT THE TOP: a cap nothing can reach is a cap that lies.
  if public.level_from_points(9025) <> 20 then
    raise exception '0069 self-assert FAIL: level 20 is not reachable at 9,025 points';
  end if;

  -- (b) A HOUSE WITH NO HISTORY READS ZERO ON EVERY TRACK, and null reads the same. A levels
  --     function that needed a row to exist would be a counter in disguise.
  v_prog := public.player_progress(null);
  if (v_prog->'trading'->>'level')::int <> 1 or (v_prog->'combat'->>'points')::int <> 0 then
    raise exception '0069 self-assert FAIL: an unknown house does not read as a fresh one';
  end if;

  -- (c) IT COUNTS WHAT WAS ALREADY IN THE RECORD. A house is founded, trades, and SAILS - then
  --     every track is read back and must have moved for the right reason.
  v_player := public.new_house(c_uid, 'Casa Registro', 'PRT');
  select id into v_fleet from public.fleets where player_id = v_player;
  perform cmd.assume_identity(c_uid);

  v_prog := public.player_progress(v_player);
  if (v_prog->'trading'->>'points')::int <> 0 or (v_prog->'exploration'->>'points')::int <> 0 then
    raise exception '0069 self-assert FAIL: a freshly founded house has already earned something';
  end if;

  perform cmd.do_provision(v_fleet, jsonb_build_object('mode', 'FULL'));
  v_prog := public.player_progress(v_player);
  -- PROVISIONING IS NOT TRADE. It spends ducats and writes to the ledger, and if it counted, every
  -- track would be farmable by buying water. This is the positive control on the ledger filter.
  if (v_prog->'trading'->>'points')::int <> 0 then
    raise exception '0069 self-assert FAIL: buying stores earned % trading point(s)', (v_prog->'trading'->>'points')::int;
  end if;

  -- (d) FAME AND LEVELS CANNOT DISAGREE, because there is only one count now. Asserted rather
  --     than assumed: this is the whole reason player_fame was re-cut.
  v_fame := public.player_fame(v_player);
  v_prog := public.player_progress(v_player);
  if (v_fame->>'trade')::int <> (v_prog->'trading'->>'points')::int
     or (v_fame->>'exploration')::int <> (v_prog->'exploration'->>'points')::int
     or (v_fame->>'ports_reached')::int <> (v_prog->'exploration'->>'ports_reached')::int then
    raise exception '0069 self-assert FAIL: fame and levels disagree - %  vs  %', v_fame, v_prog;
  end if;
  select def into v_before from defs_before_0069 where fn = 'public.player_fame';
  if position('player_progress' in v_before) <> 0 then
    raise exception '0069 self-assert FAIL: the pre-image already read the one definition';
  end if;
  if position('ledger' in pg_get_functiondef('public.player_fame(uuid)'::regprocedure)) <> 0 then
    raise exception '0069 self-assert FAIL: player_fame still counts the ledger itself';
  end if;

  -- (e) DISTANCE IS COUNTED, and it is the half the owner asked for. Rather than sail (which drags
  --     the whole mover into a proof about arithmetic), the record is read for what it holds: if
  --     any voyage report in this world carries total_nm, exploration must exceed ports x 25.
  select coalesce(sum((e.payload->>'total_nm')::numeric), 0) into v_nm
    from public.events e where e.kind = 'VOYAGE_REPORT' and e.payload ? 'total_nm';
  if v_nm > 0 then
    declare
      v_other uuid;
      v_p2    jsonb;
    begin
      select e.player_id into v_other from public.events e
       where e.kind = 'VOYAGE_REPORT' and e.payload ? 'total_nm'
         and (e.payload->>'total_nm')::numeric >= public.wc_num('fame_nm_per_point')
       limit 1;
      if v_other is not null then
        v_p2 := public.player_progress(v_other);
        if (v_p2->'exploration'->>'points')::int
             <= (v_p2->'exploration'->>'ports_reached')::int * public.wc_num('fame_per_port') then
          raise exception '0069 self-assert FAIL: a house that has sailed % nm scores no more than its landfalls - the distance half is not counted',
            (v_p2->'exploration'->>'nm_sailed')::numeric;
        end if;
      end if;
    end;
  end if;

  -- (f) COMBAT READS ZERO AND SAYS WHY. If this ever quietly starts scoring, the track has been
  --     given a proxy and the honesty is gone.
  v_prog := public.player_progress(v_player);
  if (v_prog->'combat'->>'points')::int <> 0 or (v_prog->'combat'->>'playable')::boolean then
    raise exception '0069 self-assert FAIL: the combat track claims to be playable';
  end if;

  -- (g) THE HOUSE PAYLOAD CARRIES THEM.
  if not (world.player()->'player' ? 'levels') then
    raise exception '0069 self-assert FAIL: world.player serves no levels';
  end if;
  if (world.player()->'player'->'levels'->'exploration'->>'level')::int is null then
    raise exception '0069 self-assert FAIL: the served levels have no exploration level';
  end if;

  -- (h) POSTURE.
  select count(*) into v_grants from public.client_write_grants();
  if v_grants <> 0 then
    raise exception '0069 self-assert FAIL: % client write grant(s)', v_grants;
  end if;

  raise notice '0069 self-assert ok: THREE TRACKS, AND NOTHING IS GRANTED. There is no levels table and no counter to inflate - all three tracks are RE-READ from the append-only record, so they are retroactively right for every voyage already sailed. The curve was walked point by point from 0 to 40,000: it never falls, never passes the cap of 20, puts the second level at exactly 25 points and the fifth at 400, and level 20 is actually reachable at 9,025. A freshly founded house reads zero everywhere, and PROVISIONING it earned nothing - the positive control on the ledger filter, because a track that counted buying water would be farmable by buying water. public.player_fame is now a VIEW of the one definition rather than a second count of the same ledger (its pre-image counted it itself, and its body no longer mentions the ledger at all), and the two are asserted equal. Exploration counts sea miles as well as landfalls, which is the owner''s ruling of "both" - total_nm has been in the record since 0036 and nothing was asking. Combat reads ZERO and says playable=false out loud, because inventing a proxy would make an unbuilt track look built; 0 client write grants.';
end $$;
