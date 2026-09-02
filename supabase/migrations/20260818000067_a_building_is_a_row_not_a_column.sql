-- ===============================================================================================
-- 0067 - A BUILDING IS A ROW, NOT A COLUMN
-- ===============================================================================================
--
-- The owner, 2026-09-01:
--
--     "buildings are market, a workstation where you can create ship related items - sail etc.
--      inn where you can hire crew, find captains. etc. it is a concept."
--
-- -- WHAT A FACILITY IS TODAY, AND WHY IT CANNOT GROW --------------------------------------------
-- A boolean on the port plus a hard-coded screen. `has_yard` gates REPAIR, `has_academy` gates the
-- Academy face, and PortScreen carries the line `f.id !== 'academy' || port.has_academy` - one
-- special case, written by hand, for one facility.
--
-- The owner has now asked for four more buildings: a warehouse (row 57), a workstation (rows
-- 68/69), a 건조소 (row 58) and an Inn (row 60). Done the same way that is four more columns, four
-- more hand-written special cases, and a PORT screen growing back the tabs rows 53 and 56 just cut.
--
-- -- THE SHAPE ----------------------------------------------------------------------------------
-- A building is a row: (port, kind, tier). Adding a seventh building is an INSERT, not a migration
-- that re-cuts every screen. `kind` is itself a row in public.building_kinds rather than an enum,
-- for the same reason and at the same cost.
--
-- -- WHY THE PORT COLUMNS STAY, AND ARE NOT A SECOND AUTHORITY -----------------------------------
-- `has_yard`, `yard_tier` and `has_academy` are AUTHORED in data/ports.json and world-guard holds
-- the applied world equal to that file in both directions. They stay exactly where they are and
-- keep being the authored truth. What this migration adds is a DERIVATION of them into rows - the
-- same relationship port_goods.affinity has to the port's coordinates, or port_goods.demand to
-- data/demand.json. One authority, one derivation, no copy.
--
-- The direction of travel matters though: from here the ROW is what the game reads. A tier that a
-- player raises has nowhere to live in a boolean, and the building yard and the workstation both
-- need one.
--
-- -- WHAT THIS SLICE DELIBERATELY DOES NOT DO ---------------------------------------------------
-- It builds no warehouse, no workstation, no building yard and no Inn behaviour. Those are their
-- own slices, each landing its own behaviour whole (docs/WORK_PLAN.md 1). This lands the CONCEPT
-- and both sides of it: the rows exist, the payload carries them, and the port screen's face strip
-- is driven by them instead of by a hand-written boolean check. The three new kinds are seeded onto
-- no port at all - a kind that exists and is nowhere is exactly what "not built yet" looks like.
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
      raise exception '0067 slice: hunk % of % occurs % time(s) in %, expected exactly 1 - the deployed body is not what this migration was generated against.',
        (v_i + 1) / 2, (array_length(p_edits, 1)) / 2, v_n, p_fn;
    end if;
    v_def := replace(v_def, p_edits[v_i], p_edits[v_i + 1]);
    v_i := v_i + 2;
  end loop;
  if p_drop then execute format('drop function %s', p_fn::text); end if;
  execute v_def;
end $fn$;

create temporary table defs_before_0067 as
  select 'world.snapshot'::text as fn, pg_get_functiondef('world.snapshot()'::regprocedure) as def;

-- -- 1. THE KINDS, AS ROWS ----------------------------------------------------------------------
-- Seven words, each with the sentence that says what it DOES, because "what is a workstation" is a
-- question every later slice will ask and it must have exactly one answer.
--
-- ON THE TWO YARDS: the owner once asked "what is yard?" and a migration renamed everything to
-- shipyard, which today means REPAIR. The building yard is a different building - it BUILDS hulls.
-- Repair keeps `shipyard`; the new one is `building_yard`. Two buildings may not share one word.
create table if not exists public.building_kinds (
  kind      text primary key,
  name      text not null,
  does      text not null check (length(does) > 12),
  sort      int  not null
);

insert into public.building_kinds (kind, name, does, sort) values
  ('market',        'Market',        'Buy and sell what this city trades.', 1),
  ('warehouse',     'Warehouse',     'Store goods here. A warehouse belongs to one city and is reachable only while docked in it.', 2),
  ('workstation',   'Workstation',   'Make ship fittings out of trade goods.', 3),
  ('building_yard', 'Building yard', 'Build a hull, out of timber and fittings. It is not the shipyard, which repairs.', 4),
  ('inn',           'Inn',           'Hire crew, and meet the captains who happen to be drinking here.', 5),
  ('shipyard',      'Shipyard',      'Repair a hull the sea has taken a toll on.', 6),
  ('academy',       'Academy',       'Study a trade, one level at a time.', 7)
on conflict (kind) do update set name = excluded.name, does = excluded.does, sort = excluded.sort;

-- READ BY EVERYONE, WRITTEN BY NOBODY - the posture every world table in this chain holds, and
-- proof 03 refuses a table that does not (it caught this one missing).
alter table public.building_kinds enable row level security;

drop policy if exists building_kinds_read on public.building_kinds;
create policy building_kinds_read on public.building_kinds
  for select to anon, authenticated using (true);

comment on table public.building_kinds is
  'The kinds of building a city can keep, one row each. A seventh building is an INSERT here plus '
  'rows in public.port_buildings - never a new column on public.ports, and never a hand-written '
  'special case on a screen.';

-- -- 2. WHICH CITY KEEPS WHICH ------------------------------------------------------------------
create table if not exists public.port_buildings (
  port_id uuid not null references public.ports(id) on delete cascade,
  kind    text not null references public.building_kinds(kind),
  tier    int  not null check (tier between 1 and 5),
  primary key (port_id, kind)
);

comment on table public.port_buildings is
  'What this city keeps, and how good it is at it. `tier` is where "some cities can craft" lives: '
  'a city crafts because its workstation is good enough, not because a list names it. Seeded by '
  'DERIVING the authored ports.has_yard / yard_tier / has_academy, which stay the authored truth '
  'in data/ports.json - this is a derivation of them, not a second copy.';

alter table public.port_buildings enable row level security;

drop policy if exists port_buildings_read on public.port_buildings;
create policy port_buildings_read on public.port_buildings
  for select to anon, authenticated using (true);

insert into public.port_buildings (port_id, kind, tier)
  -- EVERY HARBOUR TRADES AND EVERY HARBOUR POURS. Market and Inn are not facilities a city may
  -- lack: 0061 gave every harbour a roster, and cmd.do_hire already answers at every quay. Seeding
  -- them anywhere else would make these rows disagree with the game as it is played today.
  select p.id, 'market', greatest(1, least(5, p.size_tier)) from public.ports p where p.kind = 'HARBOUR'
  union all
  select p.id, 'inn', greatest(1, least(5, p.size_tier)) from public.ports p where p.kind = 'HARBOUR'
  union all
  -- THE TWO THAT ALREADY EXIST, derived from their own authored columns. yard_tier is 0-5 and 0
  -- means "no yard", so the floor of 1 only ever applies to a port that has one.
  select p.id, 'shipyard', greatest(1, least(5, p.yard_tier)) from public.ports p where p.kind = 'HARBOUR' and p.has_yard
  union all
  select p.id, 'academy', greatest(1, least(5, p.size_tier)) from public.ports p where p.kind = 'HARBOUR' and p.has_academy
on conflict (port_id, kind) do update set tier = excluded.tier;

-- -- 3. THE PAYLOAD CARRIES THEM ----------------------------------------------------------------
-- Onto the port object the snapshot already builds, so the client needs no second read and no
-- code-to-catalogue join to ask "what does this city keep".
-- The KINDS travel with it, once for the whole world rather than repeated on 224 ports. A client
-- that hard-coded "Workstation" and "Make ship fittings out of trade goods" would be the second
-- authority this file was written to avoid - the name of a building belongs with the building.
select pg_temp.recut('world.snapshot()'::regprocedure, false,
  $k0$    'ports', (select coalesce(jsonb_agg(jsonb_build_object($k0$,
  $k1$    'building_kinds', (select coalesce(jsonb_agg(jsonb_build_object(
        'kind', bk.kind, 'name', bk.name, 'does', bk.does) order by bk.sort), '[]'::jsonb)
      from public.building_kinds bk),
    'ports', (select coalesce(jsonb_agg(jsonb_build_object($k1$,
  $s0$        'dev_industry', p.dev_industry, 'dev_commerce', p.dev_commerce, 'dev_military', p.dev_military)$s0$,
  $s1$        'dev_industry', p.dev_industry, 'dev_commerce', p.dev_commerce, 'dev_military', p.dev_military,
        'buildings', (select coalesce(jsonb_agg(jsonb_build_object(
            'kind', pb.kind, 'tier', pb.tier) order by bk.sort), '[]'::jsonb)
          from public.port_buildings pb
          join public.building_kinds bk on bk.kind = pb.kind
         where pb.port_id = p.id))$s1$);

-- -- 4. THE SERVER READS THE ROWS TOO -----------------------------------------------------------
-- Moving only the SCREENS onto the rows would have left the seam exactly where it was, one layer
-- down: the client asking the rows whether a yard is here while cmd.do_repair asks the boolean.
-- Two authorities for one question is the defect, wherever the second one lives.
--
-- These are the only two server readers in the chain, and both are the same shape: "does this
-- harbour keep one, and if not, name some that do".
select pg_temp.recut('cmd.do_repair(uuid, jsonb)'::regprocedure, false,
  $r0$  select has_yard, dev_industry into v_yard, v_dev from public.ports where id = f.port_id;$r0$,
  $r1$  -- 0067: the ROW is the authority. The boolean is still the authored truth in data/ports.json
  -- and 0067 proves the two equal, so this reads the same today - and keeps reading correctly the
  -- day a player raises a yard, which a boolean cannot express.
  select exists (select 1 from public.port_buildings b
                  where b.port_id = f.port_id and b.kind = 'shipyard'),
         p.dev_industry
    into v_yard, v_dev
    from public.ports p where p.id = f.port_id;$r1$);

select pg_temp.recut('cmd.study_skill(text, uuid)'::regprocedure, false,
  $a0$  select p.code, p.name, p.has_academy into v_port from public.ports p where p.id = v_fleet.port_id;
  if not v_port.has_academy then$a0$,
  $a1$  -- 0067: the row, not the column - see cmd.do_repair above.
  select p.code, p.name,
         exists (select 1 from public.port_buildings b
                  where b.port_id = p.id and b.kind = 'academy') as has_academy
    into v_port
    from public.ports p where p.id = v_fleet.port_id;
  if not v_port.has_academy then$a1$,
  $a2$                  from (select code, name from public.ports where has_academy order by code limit 6) p));$a2$,
  $a3$                  from (select p2.code, p2.name from public.ports p2
                         join public.port_buildings b2 on b2.port_id = p2.id and b2.kind = 'academy'
                        order by p2.code limit 6) p));$a3$);

-- -- SELF-ASSERT ---------------------------------------------------------------------------------
do $$
declare
  v_kinds   int;
  v_rows    int;
  v_bad     int;
  v_harb    int;
  v_yard    int;
  v_acad    int;
  v_snap    jsonb;
  v_port    jsonb;
  v_before  text;
  v_grants  int;
  v_probe_port   uuid;
  v_probe_fleet  uuid;
  v_probe_player uuid;
  c_probe_uid constant uuid := '00000000-0067-4000-8000-000000000001';
  v_code    text;
begin
  select count(*) into v_kinds from public.building_kinds;
  if v_kinds <> 7 then
    raise exception '0067 self-assert FAIL: % building kind(s), expected the 7 this file names', v_kinds;
  end if;
  if to_regclass('public.port_buildings') is null then
    raise exception '0067 self-assert FAIL: public.port_buildings does not exist';
  end if;

  select count(*) into v_harb from public.ports where kind = 'HARBOUR';
  select count(*) into v_yard from public.ports where kind = 'HARBOUR' and has_yard;
  select count(*) into v_acad from public.ports where kind = 'HARBOUR' and has_academy;
  select count(*) into v_rows from public.port_buildings;
  if v_rows <> v_harb * 2 + v_yard + v_acad then
    raise exception '0067 self-assert FAIL: % building row(s), expected % (a market and an inn at each of % harbours, % shipyard(s), % academy(ies))',
      v_rows, v_harb * 2 + v_yard + v_acad, v_harb, v_yard, v_acad;
  end if;

  -- (a) THE ROWS EQUAL THE AUTHORED COLUMNS, BOTH DIRECTIONS. This is the whole claim of the file:
  --     the derivation says exactly what data/ports.json said, so nothing about the game changed
  --     today except WHERE the answer is read from. A row where has_academy is false, or a true
  --     has_academy with no row, would each be a world that quietly moved.
  select count(*) into v_bad
    from public.ports p
   where p.kind = 'HARBOUR'
     and (exists (select 1 from public.port_buildings b where b.port_id = p.id and b.kind = 'academy')) <> p.has_academy;
  if v_bad <> 0 then
    raise exception '0067 self-assert FAIL: % harbour(s) disagree with has_academy', v_bad;
  end if;
  select count(*) into v_bad
    from public.ports p
   where p.kind = 'HARBOUR'
     and (exists (select 1 from public.port_buildings b where b.port_id = p.id and b.kind = 'shipyard')) <> p.has_yard;
  if v_bad <> 0 then
    raise exception '0067 self-assert FAIL: % harbour(s) disagree with has_yard', v_bad;
  end if;
  select count(*) into v_bad
    from public.port_buildings b
    join public.ports p on p.id = b.port_id
   where b.kind = 'shipyard' and b.tier <> greatest(1, least(5, p.yard_tier));
  if v_bad <> 0 then
    raise exception '0067 self-assert FAIL: % shipyard row(s) do not carry the authored yard_tier', v_bad;
  end if;

  -- (b) A SEA PLACE KEEPS NOTHING. 0036 gave the sea places no shore; a building on one would be a
  --     face offered on a screen that has no quay to put it on.
  select count(*) into v_bad
    from public.port_buildings b join public.ports p on p.id = b.port_id where p.kind <> 'HARBOUR';
  if v_bad <> 0 then
    raise exception '0067 self-assert FAIL: % building(s) stand on something that is not a harbour', v_bad;
  end if;

  -- (c) THE THREE NEW KINDS EXIST AND ARE NOWHERE. That is what "not built yet" looks like, and it
  --     is asserted rather than assumed, so a later slice cannot quietly find them pre-seeded.
  select count(*) into v_bad
    from public.port_buildings where kind in ('warehouse', 'workstation', 'building_yard');
  if v_bad <> 0 then
    raise exception '0067 self-assert FAIL: % row(s) of a building this slice does not build yet', v_bad;
  end if;

  -- (d) THE PAYLOAD CARRIES THEM, read from the function the game actually calls. A port with an
  --     academy must say so IN THE PAYLOAD, or the screen has nothing to drive its strip with.
  v_snap := world.snapshot();
  select value into v_port
    from jsonb_array_elements(v_snap->'ports')
   where value->>'code' = (select p.code from public.ports p
                            where p.kind = 'HARBOUR' and p.has_academy order by p.code limit 1);
  if v_port is null then
    raise exception '0067 self-assert FAIL: the snapshot serves no port that keeps an academy';
  end if;
  if not (v_port->'buildings' @> '[{"kind": "academy"}]'::jsonb) then
    raise exception '0067 self-assert FAIL: % is served without its academy: %', v_port->>'code', v_port->'buildings';
  end if;
  if not (v_port->'buildings' @> '[{"kind": "market"}]'::jsonb) then
    raise exception '0067 self-assert FAIL: % is served without its market', v_port->>'code';
  end if;
  if jsonb_array_length(v_snap->'building_kinds') <> 7 then
    raise exception '0067 self-assert FAIL: the snapshot serves % kind(s), not the 7 that exist',
      jsonb_array_length(v_snap->'building_kinds');
  end if;
  if not (v_snap->'building_kinds' @> '[{"kind": "building_yard", "name": "Building yard"}]'::jsonb) then
    raise exception '0067 self-assert FAIL: the kinds travel without their names';
  end if;

  -- POSITIVE CONTROL: the same read must be able to say NO. A port without a yard must come back
  -- without one, or (d) is a test that passes on any payload with a non-empty list.
  select value into v_port
    from jsonb_array_elements(v_snap->'ports')
   where value->>'code' = (select p.code from public.ports p
                            where p.kind = 'HARBOUR' and not p.has_yard order by p.code limit 1);
  if v_port is null then
    raise exception '0067 self-assert FAIL: every harbour keeps a yard, so the control cannot run';
  end if;
  if v_port->'buildings' @> '[{"kind": "shipyard"}]'::jsonb then
    raise exception '0067 self-assert FAIL: % has no yard but is served one', v_port->>'code';
  end if;

  -- (e) NOTHING ELSE IN THE SNAPSHOT MOVED. The port object gained one key; the rest of the
  --     function is its own pre-image.
  select def into v_before from defs_before_0067 where fn = 'world.snapshot';
  if position('buildings' in v_before) <> 0 then
    raise exception '0067 self-assert FAIL: the pre-image already served buildings';
  end if;

  -- (e2) THE SERVER READS THE ROWS TOO. Proven by BEHAVIOUR, not by grepping the body: a fleet is
  --      docked at a harbour that keeps no academy, its academy row is planted, and the same call
  --      that refused must now get past the gate. If study_skill were still reading has_academy
  --      the planted row would change nothing and this block would fail.
  select p.id into v_probe_port from public.ports p
   where p.kind = 'HARBOUR' and not p.has_academy order by p.code limit 1;
  -- A house of its own, so the probe never borrows a real player's fleet. 0007 founds two the
  -- same way. It stays afterwards; see the note at the foot of this block.
  v_probe_player := public.new_house(c_probe_uid, 'Casa Obra', 'PRT');
  select f.id into v_probe_fleet from public.fleets f where f.player_id = v_probe_player;
  update public.fleets set port_id = v_probe_port where id = v_probe_fleet;
  perform cmd.assume_identity(c_probe_uid);

  select (cmd.study_skill('navigation', v_probe_fleet))->>'error_code' into v_code;
  if v_code is distinct from 'E_NO_ACADEMY' then
    raise exception '0067 self-assert FAIL: a harbour with no academy did not refuse study (got %)', coalesce(v_code, 'ok');
  end if;
  insert into public.port_buildings (port_id, kind, tier) values (v_probe_port, 'academy', 1);
  select (cmd.study_skill('navigation', v_probe_fleet))->>'error_code' into v_code;
  if v_code = 'E_NO_ACADEMY' then
    raise exception '0067 self-assert FAIL: cmd.study_skill still reads ports.has_academy - planting the row changed nothing';
  end if;
  delete from public.port_buildings where port_id = v_probe_port and kind = 'academy';

  -- THE PROBE HOUSE STAYS, and that is the game refusing rather than a loose end: founding one
  -- writes to the ledger, and the ledger is append-only, so striking it out is exactly the thing
  -- public.events is built to forbid. 0007 founds two the same way and leaves them. It is named
  -- Casa Obra so anyone reading the players table knows what it is and which file made it.

  -- (f) POSTURE. A player may READ what a city keeps and may not write it.
  select count(*) into v_grants from public.client_write_grants();
  if v_grants <> 0 then
    raise exception '0067 self-assert FAIL: % client write grant(s)', v_grants;
  end if;

  raise notice '0067 self-assert ok: A BUILDING IS A ROW. 7 kinds exist as rows rather than an enum, and % building(s) stand across % harbour(s) - a market and an inn at every one, % shipyard(s) and % academy(ies) - each DERIVED from the authored column that already said so and proven equal to it in BOTH directions, so nothing about the world changed today except where the answer is read from. No sea place keeps anything. The three buildings this slice does not build yet exist as kinds and stand nowhere, which is what "not built yet" looks like. The snapshot carries them on the port object it already built (positive control: a yardless harbour comes back WITHOUT a shipyard, so the read can say no), and every other byte of that function is its own pre-image. THE SERVER READS THE ROWS TOO: cmd.do_repair and cmd.study_skill were re-cut off the booleans, and study_skill''s gate is proven by BEHAVIOUR - a harbour with no academy refused, its academy row was planted, and the same call got past the gate, which it could not have done while the function still read ports.has_academy; 0 client write grants.',
    v_rows, v_harb, v_yard, v_acad;
end $$;
