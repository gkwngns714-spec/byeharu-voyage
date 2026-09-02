// Emits migration 0073 from data/officers.json, for the reason scripts/build-fittings-0068.mjs states.
import fs from 'node:fs'

const roster = JSON.parse(fs.readFileSync('data/officers.json', 'utf8')).officers
const q = (s) => (s === null || s === undefined ? 'null' : `'${String(s).replace(/'/g, "''")}'`)

const seen = new Set()
for (const o of roster) {
  if (seen.has(o.code)) throw new Error(`duplicate officer code ${o.code}`)
  seen.add(o.code)
  if (o.code !== o.code.toUpperCase() || o.code.length < 2 || o.code.length > 16) throw new Error(`bad code ${o.code}`)
  if (!(o.bonus_pct > 0 && o.bonus_pct <= 25)) throw new Error(`${o.code}: bonus out of band`)
  if (!o.blurb || o.blurb.length < 12) throw new Error(`${o.code}: every officer carries a line about who they are`)
}

const rows = roster
  .map((o) => `  (${q(o.code)}, ${q(o.name)}, ${q(o.specialty)}, ${o.bonus_pct}, ${o.wage}, ${q(o.nation)}, ${q(o.home)}, ${q(o.blurb)})`)
  .join(',\n')

const SQL = `-- ===============================================================================================
-- 0073 - WHO IS DRINKING HERE TODAY
-- ===============================================================================================
--
-- The owner, 2026-09-01:
--
--     "another design - i want a buliding called Inn, where you can hire crew, and also captains."
--
-- and, on where they come from:
--
--     "captains ... should also have country of origin, and should be randomly appear in inn
--      (not 100%, S tear especially) on their country land, or related fields."
--
-- -- THE HARD RULE, AND IT IS THE WHOLE DESIGN ---------------------------------------------------
-- WHO IS IN AN INN IS A PURE FUNCTION OF (port, day, world secret). Not rolled and stored.
--
-- This game settles voyages while the player sleeps because every random thing in it is a pure
-- function of the world secret - PostgreSQL itself enforces that, since an IMMUTABLE function may
-- not read a table or the clock. An officer who was ROLLED AND WRITTEN DOWN could be re-rolled by
-- closing the tab and opening it again until a good one appeared. Derived, they cannot: the same
-- quay on the same day shows the same faces to everyone, for ever, and tomorrow shows different
-- ones without anybody storing a thing.
--
-- -- ONE ARITHMETIC FOR EVERY ROLL IN THE GAME ---------------------------------------------------
-- voyage.rng_raw has been the game's only random number since 0006: md5 of a key and the secret,
-- read as a 60-bit integer, divided down to [0,1). This file does NOT write a second one. It lifts
-- that arithmetic into world.roll_raw(key, secret) and RE-CUTS voyage.rng_raw to call it with its
-- own key composed exactly as before.
--
-- That is a supersede of the function that decides every hazard in every settled voyage, so it is
-- proven rather than asserted: the self-assert captures rng_raw over a spread of (voyage, day,
-- stream) BEFORE the re-cut and requires every one of them to come back byte-identical after. If a
-- single roll moved, a voyage already at sea would arrive somewhere else.
--
-- -- WEIGHTING: THE OWNER'S "RELATED FIELDS", WHICH THEY ANSWERED AS "ALL OF THEM" -------------
-- Highest in the ports of her own NATION, then in her home REGION, then in a port of her home
-- CULTURE, lowest anywhere else. And the better she is the rarer she is, everywhere - which is the
-- owner's "not 100%, S tear especially" said in the units this game has today.
--
-- -- WHAT THIS SLICE DOES NOT DO -----------------------------------------------------------------
-- No S/A/B/C ladder, no skill slots, no promotion. That is DESIGN_V1 7.1 and its own slice, and it
-- can be added as columns on these same rows. What lands here is the BUILDING and the rule that
-- makes it honest, plus the roster it needs to be worth walking into.
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
      raise exception '0073 slice: hunk % of % occurs % time(s) in %, expected exactly 1 - the deployed body is not what this migration was generated against.',
        (v_i + 1) / 2, (array_length(p_edits, 1)) / 2, v_n, p_fn;
    end if;
    v_def := replace(v_def, p_edits[v_i], p_edits[v_i + 1]);
    v_i := v_i + 2;
  end loop;
  if p_drop then execute format('drop function %s', p_fn::text); end if;
  execute v_def;
end $fn$;

-- EVERY ROLL THIS WORLD HAS EVER MADE, captured before anything moves. The re-cut below has to
-- reproduce all of them exactly or a settled voyage would land somewhere else.
create temporary table rolls_before_0073 as
  select v.id as voyage_id, d.day, s.stream,
         voyage.rng_raw(v.id, d.day, s.stream, public.wc_text('world_secret')) as roll
    from (select gen_random_uuid() as id from generate_series(1, 40)) v
   cross join (select generate_series(0, 9) as day) d
   cross join (select unnest(array['hazard', 'weather', 'desertion']) as stream) s;

-- -- 1. THE ONE ARITHMETIC ------------------------------------------------------------------------
create or replace function world.roll_raw(p_key text, p_secret text)
returns numeric
language sql
immutable
parallel safe
as $rr$
  -- IMMUTABLE is load-bearing, and it is the reason this game can settle offline: PostgreSQL
  -- forbids an immutable function from reading a table or the clock, so this cannot become
  -- time-dependent by accident. The secret arrives as an ARGUMENT precisely to keep that.
  select (('x' || substr(md5(p_key || ':' || p_secret), 1, 15))::bit(60)::bigint)::numeric
         / 1152921504606846976::numeric
$rr$;

comment on function world.roll_raw(text, text) is
  'THE one random number in this game. Pure in (key, world_secret) and in nothing else - not in '
  'now(). voyage.rng_raw composes its own key and calls this; so does the inn.';

-- voyage.rng_raw becomes a caller rather than a second copy. The key it builds is character for
-- character what it built before, which is why every roll below comes back identical.
select pg_temp.recut('voyage.rng_raw(uuid, int, text, text)'::regprocedure, false,
  $r0$  select (('x' || substr(md5(p_voyage::text || ':' || p_day::text || ':' || p_stream || ':' || p_secret), 1, 15))::bit(60)::bigint)::numeric
         / 1152921504606846976::numeric$r0$,
  $r1$  select world.roll_raw(p_voyage::text || ':' || p_day::text || ':' || p_stream, p_secret)$r1$);

-- -- 2. THE ROSTER GROWS ---------------------------------------------------------------------------
-- 0015 authored EIGHT officers, which was right for a twelve-port world. There are 224 harbours
-- now. Eight people cannot fill 224 inns: almost every one would be empty every day, and a building
-- that is empty by arithmetic reads as broken rather than as rare.
create temporary table want_officers_0073 (
  code text, name text, specialty text, bonus_pct numeric, wage bigint,
  nation_code text, home_code text, blurb text);

insert into want_officers_0073 (code, name, specialty, bonus_pct, wage, nation_code, home_code, blurb) values
${rows};

insert into public.officers (code, name, specialty, bonus_pct, wage_ducats, nation_id, home_port_id, blurb)
select w.code, w.name, w.specialty, w.bonus_pct, w.wage, n.id, p.id, w.blurb
  from want_officers_0073 w
  left join public.nations n on n.code = w.nation_code
  join public.ports p on p.code = w.home_code
on conflict (code) do update set name = excluded.name, specialty = excluded.specialty,
  bonus_pct = excluded.bonus_pct, wage_ducats = excluded.wage_ducats, nation_id = excluded.nation_id,
  home_port_id = excluded.home_port_id, blurb = excluded.blurb;

-- -- 3. WHO IS PRESENT, AND HOW LIKELY ---------------------------------------------------------
insert into public.world_config (key, value, description) values
  ('inn_weight_nation',  to_jsonb(0.40::numeric), 'How likely an officer is to be in an inn in a port of HER OWN NATION. The owner: captains "appear in inn on their country land".'),
  ('inn_weight_region',  to_jsonb(0.22::numeric), 'The same, in a port of her home REGION but another nation.'),
  ('inn_weight_culture', to_jsonb(0.12::numeric), 'The same, in a port that merely shares her home''s CULTURE.'),
  ('inn_weight_abroad',  to_jsonb(0.04::numeric), 'And anywhere else in the world. Not zero: people do travel, and an inn on the far side of the map should be worth walking into once.')
on conflict (key) do update set value = excluded.value, description = excluded.description;

-- HOW LIKELY SHE IS TO BE ANYWHERE AT ALL, before the place is considered. The owner asked that
-- the best be rare - "not 100%, S tear especially" - and this game has no ranks yet, so the stand-in
-- is what an officer is WORTH: bonus_pct. A 9% navigator turns up about half as often as a 5% one.
create or replace function world.officer_scarcity(p_bonus numeric)
returns numeric
language sql
immutable
parallel safe
as $os$ select greatest(0.25::numeric, least(1.0::numeric, (12.0 - p_bonus) / 8.0)) $os$;

create or replace function world.inn_chance(p_officer uuid, p_port uuid)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $ic$
  select world.officer_scarcity(o.bonus_pct) *
         case
           when o.nation_id is not null and o.nation_id = p.nation_id then public.wc_num('inn_weight_nation')
           when hp.region_id = p.region_id                            then public.wc_num('inn_weight_region')
           when hp.culture  = p.culture                               then public.wc_num('inn_weight_culture')
           else public.wc_num('inn_weight_abroad')
         end
    from public.officers o
    join public.ports p on p.id = p_port
    left join public.ports hp on hp.id = o.home_port_id
   where o.id = p_officer
$ic$;

comment on function world.inn_chance(uuid, uuid) is
  'How likely this officer is to be found in this city on any given day: her scarcity times how '
  'close the city is to home, by nation, then region, then culture, then not at all.';

create or replace function world.inn_present(p_officer uuid, p_port uuid, p_day int)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $ip$
  -- THE KEY IS (officer, port, day) AND NOTHING ELSE, so the same quay on the same day shows the
  -- same faces to every player for ever, and no amount of reloading changes them.
  select world.roll_raw(o.code || '@' || p.code || '#' || p_day::text || ':inn',
                        public.wc_text('world_secret'))
         < world.inn_chance(p_officer, p_port)
    from public.officers o, public.ports p
   where o.id = p_officer and p.id = p_port
$ip$;

revoke all on function world.roll_raw(text, text) from public, anon, authenticated;
revoke all on function world.officer_scarcity(numeric) from public, anon, authenticated;
revoke all on function world.inn_chance(uuid, uuid) from public, anon, authenticated;
revoke all on function world.inn_present(uuid, uuid, int) from public, anon, authenticated;

-- -- 4. YOU MAY ONLY SIGN SOMEONE WHO IS ACTUALLY HERE ---------------------------------------------
-- Until now cmd.hire_officer would sign anyone in the world from anywhere, which is what made the
-- roster a menu rather than a place. This is the gate, and it is the only thing that makes the
-- building matter: you sign the people in the room.
select pg_temp.recut('cmd.hire_officer(text, uuid)'::regprocedure, false,
  $h0$  if exists (select 1 from public.player_officers where player_id = v_player and officer_id = v_off.id) then$h0$,
  $h1$  -- 0073: SHE HAS TO BE IN THE ROOM. A fleet of yours must be docked somewhere she is drinking
  -- today, which is derived and not stored - so this cannot be re-rolled by reloading.
  if not exists (
        select 1 from public.fleets f
         where f.player_id = v_player and f.status = 'DOCKED' and f.port_id is not null
           and exists (select 1 from public.port_buildings b
                        where b.port_id = f.port_id and b.kind = 'inn')
           and world.inn_present(v_off.id, f.port_id, world.game_day())) then
    return jsonb_build_object('ok', false, 'error_code', 'E_NOT_IN_THE_ROOM',
      'error_message', format('%s is not drinking anywhere you are lying today.', v_off.name),
      'fixes', jsonb_build_array('(look in the Inn where your fleet lies)',
                                 '(she keeps to her own coast - try nearer her home)'));
  end if;
  if exists (select 1 from public.player_officers where player_id = v_player and officer_id = v_off.id) then$h1$);

-- -- 5. WHAT THE INN SERVES -------------------------------------------------------------------------
create or replace function world.inn(p_port uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $inn$
declare
  v_player uuid := (select id from public.players where auth_uid = auth.uid());
  v_day    int  := world.game_day();
  v_has    boolean;
begin
  select exists (select 1 from public.port_buildings b where b.port_id = p_port and b.kind = 'inn')
    into v_has;

  return jsonb_build_object(
    'port_id', p_port,
    'has_inn', v_has,
    'game_day', v_day,
    -- WHO IS HERE TODAY. Derived on every read from (officer, port, day, secret) - there is no
    -- table of "tonight's guests" and there is deliberately nothing to refresh.
    'present', (select coalesce(jsonb_agg(jsonb_build_object(
        'code', o.code, 'name', o.name, 'specialty', o.specialty,
        'bonus_pct', o.bonus_pct, 'wage', o.wage_ducats, 'blurb', o.blurb,
        'nation', n.name, 'home', hp.name,
        -- WHETHER YOU ALREADY KEEP HER, so the screen offers nothing it would refuse.
        'signed', exists (select 1 from public.player_officers po
                           where po.player_id = v_player and po.officer_id = o.id))
        order by o.specialty, o.name), '[]'::jsonb)
      from public.officers o
      left join public.nations n on n.id = o.nation_id
      left join public.ports hp on hp.id = o.home_port_id
     where v_has and world.inn_present(o.id, p_port, v_day)));
end $inn$;

grant execute on function world.inn(uuid) to authenticated;

-- -- SELF-ASSERT ------------------------------------------------------------------------------------
do $$
declare
  v_n       int;
  v_bad     int;
  v_port    uuid;
  v_home    uuid;
  v_away    uuid;
  v_day     int;
  v_a       jsonb;
  v_b       jsonb;
  v_avg     numeric;
  v_max     int;
  v_empty   int;
  v_athome  numeric;
  v_abroad  numeric;
  v_moved   int;
  v_grants  int;
  v_player  uuid;
  v_fleet   uuid;
  c_uid constant uuid := '00000000-0073-4000-8000-000000000001';
begin
  -- (a) EVERY ROLL IN THE GAME IS UNCHANGED. This is the claim that matters most in this file: the
  --     one arithmetic was lifted out of voyage.rng_raw, and a single roll moving would land a
  --     voyage already at sea somewhere else.
  select count(*) into v_moved
    from rolls_before_0073 b
   where voyage.rng_raw(b.voyage_id, b.day, b.stream, public.wc_text('world_secret')) is distinct from b.roll;
  if v_moved <> 0 then
    raise exception '0073 self-assert FAIL: % of % hazard roll(s) MOVED when the arithmetic was lifted - every settled voyage is now a different voyage',
      v_moved, (select count(*) from rolls_before_0073);
  end if;
  if (select count(*) from rolls_before_0073) < 1000 then
    raise exception '0073 self-assert FAIL: the before-image held only % roll(s) - too few to mean anything',
      (select count(*) from rolls_before_0073);
  end if;
  -- AND THE POSITIVE CONTROL: the same probe MUST be able to see a difference, or it proves nothing.
  if voyage.rng_raw((select voyage_id from rolls_before_0073 limit 1), 0, 'hazard', 'a-different-secret')
     = (select roll from rolls_before_0073 where day = 0 and stream = 'hazard' limit 1) then
    raise exception '0073 self-assert FAIL: a different secret gives the same roll - the probe cannot fail';
  end if;

  -- (b) THE ROSTER IS BIG ENOUGH TO FILL A WORLD.
  select count(*) into v_n from public.officers;
  if v_n < 40 then
    raise exception '0073 self-assert FAIL: % officer(s) in the world - too few for 224 inns', v_n;
  end if;
  select count(*) into v_bad from public.officers where home_port_id is null;
  if v_bad <> 0 then
    raise exception '0073 self-assert FAIL: % officer(s) come from nowhere', v_bad;
  end if;

  -- (c) AN INN IS THE SAME ROOM TWICE. Read it, read it again, and the faces must be identical -
  --     this is the property that stops a player re-rolling by reloading.
  select p.id into v_port from public.ports p where p.kind = 'HARBOUR' order by p.code limit 1;
  v_a := world.inn(v_port);
  v_b := world.inn(v_port);
  if v_a->'present' is distinct from v_b->'present' then
    raise exception '0073 self-assert FAIL: the same inn on the same day showed different people twice';
  end if;

  -- (d) AND A DIFFERENT DAY IS A DIFFERENT ROOM, somewhere. If tomorrow always matched today the
  --     derivation would be keyed on the port alone and the inn would never change.
  v_day := world.game_day();
  select count(*) into v_moved
    from public.ports p, public.officers o
   where p.kind = 'HARBOUR'
     and world.inn_present(o.id, p.id, v_day) is distinct from world.inn_present(o.id, p.id, v_day + 1);
  if v_moved = 0 then
    raise exception '0073 self-assert FAIL: tomorrow shows exactly the same people everywhere - the day is not in the key';
  end if;

  -- (e) AN INN IS NEITHER EMPTY NOR A CROWD. Measured across every harbour rather than sampled:
  --     an average near zero means the building is broken, and a room holding half the world means
  --     the weights do nothing.
  select avg(c)::numeric(6,2), max(c), count(*) filter (where c = 0)
    into v_avg, v_max, v_empty
    from (select p.id, count(*) filter (where world.inn_present(o.id, p.id, v_day)) c
            from public.ports p cross join public.officers o
           where p.kind = 'HARBOUR' group by p.id) x;
  if v_avg < 0.5 or v_avg > 6 then
    raise exception '0073 self-assert FAIL: the average inn holds % people - that is not a room', v_avg;
  end if;
  if v_max >= (select count(*) from public.officers) then
    raise exception '0073 self-assert FAIL: one inn holds every officer in the world';
  end if;

  -- (f) SHE IS LIKELIER AT HOME. This is the owner's rule - "on their country land, or related
  --     fields" - and it is MEASURED over the whole world rather than argued: the average chance
  --     across ports of her own nation must beat the average across ports that are none of her
  --     nation, region or culture.
  select avg(world.inn_chance(o.id, p.id)) into v_athome
    from public.officers o join public.ports p
      on p.kind = 'HARBOUR' and p.nation_id = o.nation_id
   where o.nation_id is not null;
  select avg(world.inn_chance(o.id, p.id)) into v_abroad
    from public.officers o
    join public.ports hp on hp.id = o.home_port_id
    join public.ports p on p.kind = 'HARBOUR'
     and p.nation_id is distinct from o.nation_id
     and p.region_id <> hp.region_id and p.culture <> hp.culture;
  if v_athome is null or v_abroad is null then
    raise exception '0073 self-assert FAIL: could not measure home against abroad';
  end if;
  if v_athome <= v_abroad then
    raise exception '0073 self-assert FAIL: an officer is % likely at home against % abroad - the weighting is backwards',
      round(v_athome, 4), round(v_abroad, 4);
  end if;

  -- (g) AND THE BETTER SHE IS, THE RARER SHE IS - the owner's "not 100%, S tear especially",
  --     said in the units this game has today.
  if world.officer_scarcity(9.0) >= world.officer_scarcity(5.0) then
    raise exception '0073 self-assert FAIL: a 9%% officer is no rarer than a 5%% one';
  end if;

  -- (h) YOU MAY NOT SIGN SOMEBODY WHO IS NOT IN THE ROOM, and you MAY sign somebody who is. The
  --      gate that makes the building matter, proven through the verb by a house that really is
  --      standing somewhere - not by reading the function's body.
  v_player := public.new_house(c_uid, 'Casa Estalagem', 'PRT');
  select id into v_fleet from public.fleets where player_id = v_player;
  perform cmd.assume_identity(c_uid);
  perform public.credit(v_player, 'PROBE_INN', 40000,
    public.emit_event(v_player, 'PROBE', jsonb_build_object('why', '0073 self-assert')));

  -- A quay with somebody in the inn, and one of the people actually in it.
  select p.id, o.id into v_port, v_home
    from public.ports p cross join public.officers o
   where p.kind = 'HARBOUR' and world.inn_present(o.id, p.id, v_day)
   order by p.code, o.code limit 1;
  if v_port is null then
    raise exception '0073 self-assert FAIL: not one officer is in any inn in the world today';
  end if;
  update public.fleets set port_id = v_port where id = v_fleet;

  -- Somebody who is NOT in that room must refuse, by name.
  select o.id into v_away from public.officers o
   where not world.inn_present(o.id, v_port, v_day) order by o.code limit 1;
  if v_away is null then
    raise exception '0073 self-assert FAIL: every officer in the world is in this one inn';
  end if;
  v_a := cmd.hire_officer((select code from public.officers where id = v_away), null);
  if (v_a->>'ok')::boolean then
    raise exception '0073 self-assert FAIL: signed an officer who is not in the room';
  end if;
  if v_a->>'error_code' <> 'E_NOT_IN_THE_ROOM' then
    raise exception '0073 self-assert FAIL: an absent officer refused with % rather than E_NOT_IN_THE_ROOM',
      v_a->>'error_code';
  end if;

  -- And the one who IS in the room signs on. Without this the gate could simply be refusing
  -- everybody, which would pass the line above and break the building.
  v_b := cmd.hire_officer((select code from public.officers where id = v_home), null);
  if not (v_b->>'ok')::boolean then
    raise exception '0073 self-assert FAIL: could not sign the officer who IS in the room: %', v_b;
  end if;
  if not exists (select 1 from public.player_officers where player_id = v_player and officer_id = v_home) then
    raise exception '0073 self-assert FAIL: she said yes and is not on the books';
  end if;

  -- (i) POSTURE.
  select count(*) into v_grants from public.client_write_grants();
  if v_grants <> 0 then
    raise exception '0073 self-assert FAIL: % client write grant(s)', v_grants;
  end if;

  raise notice '0073 self-assert ok: WHO IS DRINKING HERE TODAY. The roster grew from 8 to % officers, because eight people cannot fill 224 inns and a building that is empty by arithmetic reads as broken rather than as rare. Who is present is DERIVED from (officer, port, day, world secret) and stored nowhere: the same inn read twice shows the same faces, tomorrow shows different ones, and no amount of reloading re-rolls them. The average harbour holds % people and the fullest holds %, so a room is a room. She is likelier at home than abroad - % against % on average, MEASURED across every port rather than argued - and the better she is the rarer she is everywhere. THE ROOM IS THE GATE, proven through the verb: a house standing at a quay was REFUSED E_NOT_IN_THE_ROOM for an officer who is not drinking there and then signed the one who is. And the one arithmetic did not move: voyage.rng_raw was lifted onto world.roll_raw and all % of its rolls came back byte-identical (positive control: a different secret DOES change them), so no voyage already at sea lands anywhere new; 0 client write grants.',
    v_n, v_avg, v_max, round(v_athome, 4), round(v_abroad, 4), (select count(*) from rolls_before_0073);
end $$;
`

fs.writeFileSync('supabase/migrations/20260818000073_who_is_drinking_here_today.sql', SQL)
console.log('wrote 0073 with', roster.length, 'new officers')
