-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0063 — SHE SAYS HOW LONG SHE HAS BEEN AT SEA
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- The owner, docs/OWNER_REQUESTS.md row 50: *"i need a real timer in map, telling me how long
-- i've been on the sea, my provision depleting as the time goes, and my ship marker should be
-- updated more frequently"*.
--
-- This file is the FIRST of that row's three parts and it is one field wide.
--
-- ── WHAT WAS MISSING, AND WHAT WAS NOT ─────────────────────────────────────────────────────────
-- `public.voyages.departed_at` has existed since 0006 (`0006:63`) and is the anchor of the whole
-- movement model: `voyage.progress_nm` is `(t - departed_at) x time_compression x v_leg / 3600`
-- (`0006:575-589`), so every mile she has made is measured from it. It has never crossed the wire.
-- `world.fleets()` serves `eta`, `total_nm`, `nm_done`, `waters` and `position` — everything about
-- where she IS and where she is GOING, and nothing about when she LEFT. So the client can count
-- down to her arrival (it does: `DetailPanel`'s `arrives`) and cannot count up from her departure.
--
-- The instant is not derivable on this side, and that is the point. `eta` moves: a hazard delays
-- her (0007), a fair wind gives hours back (0059), and `voyage.recompute_eta` re-derives it when a
-- knob moves (0045). Subtracting a duration from a moving arrival does not give a fixed departure.
-- Only the row knows.
--
-- ── WHY A SLICE AND NOT A REWRITE ──────────────────────────────────────────────────────────────
-- `world.fleets()` is 0009's, re-cut by 0017, 0028, 0047 and 0055. Retyping it to add one key is
-- how a body drifts from the one that is deployed. So the deployed definition is read back with
-- `pg_get_functiondef`, ONE hunk is replaced, and `pg_temp.recut` refuses unless that hunk occurs
-- exactly once — a wrong anchor fails loudly at apply instead of silently producing a second body.
-- The anchor is the hunk 0055 itself wrote, and nothing has re-cut this function since (checked:
-- 0059 asserts against `world.fleets` but does not re-cut it).
--
-- ── WHAT THIS FILE DOES NOT DO ─────────────────────────────────────────────────────────────────
-- No schema, no new table, no new function, no grant change. It adds one key to one payload.
-- It does NOT touch the marker's cadence and it does NOT interpolate anything: the glyph is still
-- the server's own `voyage.position`, and the client still owns no part of the movement rule
-- (`src/features/map/MapScreen.tsx:92-98` records what happened the last time it did).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

create or replace function pg_temp.recut(p_fn regprocedure, p_drop boolean, variadic p_edits text[])
returns void
language plpgsql
as $$
declare
  v_def text := pg_get_functiondef(p_fn);
  v_i   int := 1;
  v_n   int;
begin
  while v_i < array_length(p_edits, 1) loop
    v_n := (length(v_def) - length(replace(v_def, p_edits[v_i], ''))) / length(p_edits[v_i]);
    if v_n <> 1 then
      raise exception '0063 slice: hunk % of % occurs % time(s) in %, expected exactly 1 — the deployed body is not what this migration was generated against.',
        (v_i + 1) / 2, (array_length(p_edits, 1)) / 2, v_n, p_fn;
    end if;
    v_def := replace(v_def, p_edits[v_i], p_edits[v_i + 1]);
    v_i := v_i + 2;
  end loop;
  if p_drop then
    execute format('drop function %s', p_fn::text);
  end if;
  execute v_def;
end $$;

-- ── PRE-IMAGE. "Nothing else moved" is a comparison, never a sentence (NO_SPAGHETTI §3.3). ─────
create temporary table defs_before_0063 as
  select 'world.fleets'::text as fn,
         pg_get_functiondef('world.fleets()'::regprocedure) as def,
         (select p.proacl::text from pg_proc p where p.oid = 'world.fleets()'::regprocedure) as acl;

-- ── 1. THE PAYLOAD CARRIES THE INSTANT SHE LEFT — SUPERSEDES 0055:577-585 ─────────────────────
select pg_temp.recut('world.fleets()'::regprocedure, false,
  $do$                 'position', (select to_jsonb(pos) from voyage.position(v.id) pos))$do$,
  $dn$                 -- 0063: WHEN SHE LEFT. The anchor of the movement model (0006:575-589
                 -- measures every mile from it) and the only fact about this voyage the client
                 -- could not derive: `eta` MOVES (a hazard delays her, a fair wind gives hours
                 -- back, recompute_eta re-derives it), so arrival minus duration is not departure.
                 'departed_at', v.departed_at,
                 'position', (select to_jsonb(pos) from voyage.position(v.id) pos))$dn$);

-- An assumed grant is how a read wall came down in 0018 and had to be rebuilt in 0023. Re-issued
-- explicitly, and asserted unmoved below.
revoke all on function world.fleets() from public, anon;
grant execute on function world.fleets() to authenticated;

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  c_probe   constant uuid := '00000000-0063-4000-8000-000000000001';
  -- THE SAME Lisbon -> Cadiz COURSE 0047 PROVES IS WATER (0047:1221), re-used rather than
  -- re-invented: a course typed fresh here would be a second fixture that could drift off the
  -- raster the law walks. Without one, cmd.do_sail synthesises the straight line and refuses it
  -- E_NO_COURSE -- which is how this probe first failed, and correctly so.
  c_course  constant jsonb := '[[38.71,-9.14],[36.875,-9.125],[36.625,-8.875],[36.53,-6.3]]'::jsonb;
  v_player  uuid;
  v_fleet   uuid;
  v_before  text;
  v_after   text;
  v_acl_b   text;
  v_acl_a   text;
  v_served  timestamptz;
  v_row     timestamptz;
  v_payload jsonb;
  v_grants  int;
  v_res     jsonb;
begin
  select def, acl into v_before, v_acl_b from defs_before_0063 where fn = 'world.fleets';
  v_after := pg_get_functiondef('world.fleets()'::regprocedure);
  select p.proacl::text into v_acl_a from pg_proc p where p.oid = 'world.fleets()'::regprocedure;

  -- (a) POSITIVE CONTROL — the field really was absent, so this file really added something.
  if position('''departed_at'', v.departed_at' in v_before) <> 0 then
    raise exception '0063 self-assert FAIL: the pre-image already served departed_at — this file changes nothing and the slice is a no-op';
  end if;
  if position('''departed_at'', v.departed_at' in v_after) = 0 then
    raise exception '0063 self-assert FAIL: the re-cut body does not serve departed_at';
  end if;

  -- (b) NOTHING ELSE MOVED — the new body IS the old one with exactly this hunk inserted.
  if replace(v_after, $x$                 -- 0063: WHEN SHE LEFT. The anchor of the movement model (0006:575-589
                 -- measures every mile from it) and the only fact about this voyage the client
                 -- could not derive: `eta` MOVES (a hazard delays her, a fair wind gives hours
                 -- back, recompute_eta re-derives it), so arrival minus duration is not departure.
                 'departed_at', v.departed_at,
$x$, '') <> v_before then
    raise exception '0063 self-assert FAIL: the re-cut body is not its own pre-image plus exactly the declared hunk';
  end if;

  -- (c) THE GRANTS ARE THE ONES IT HAD.
  if v_acl_a is distinct from v_acl_b then
    raise exception '0063 self-assert FAIL: world.fleets grants moved (% -> %)', v_acl_b, v_acl_a;
  end if;

  -- (d) A REAL HOUSE, A REAL VOYAGE, AND THE SERVED INSTANT IS THE ROW'S OWN.
  begin
    v_player := public.new_house(c_probe, 'Casa do Relogio', 'PRT');
    perform cmd.assume_identity(c_probe);
    select id into v_fleet from public.fleets where player_id = v_player;

    -- The weather is pinned for the same reason 0037 pins it and 0047 had to be taught to: a
    -- hazard drawn on this passage would delay her and this probe would be measuring the dice.
    update public.world_config set value = to_jsonb(0.0) where key = 'hazard_p_max';

    perform cmd.do_provision(v_fleet, jsonb_build_object('mode', 'FULL'));
    -- A REFUSAL IS AN ENVELOPE, NOT AN EXCEPTION (0008): `perform cmd.issue(...)` would swallow
    -- one whole and leave this probe asserting over a fleet that never sailed. Read it and say so.
    v_res := cmd.issue(v_fleet, 'SAIL TO CAD', null, c_course);
    if coalesce(v_res->>'ok', 'false') <> 'true' then
      raise exception '0063 self-assert FAIL: the probe could not put to sea: [%: %]',
        v_res->>'error_code', v_res->>'error_message';
    end if;
    perform cmd.advance(v_fleet);

    select departed_at into v_row from public.voyages
     where fleet_id = v_fleet and status = 'SAILING';
    if v_row is null then
      raise exception '0063 self-assert FAIL: the probe never put a voyage to sea, so this proves nothing';
    end if;

    select f into v_payload from jsonb_array_elements(world.fleets()) f
     where (f->>'id')::uuid = v_fleet;
    v_served := (v_payload->'voyage'->>'departed_at')::timestamptz;

    if v_served is null then
      raise exception '0063 self-assert FAIL: world.fleets() served no departed_at for a fleet at sea';
    end if;
    if v_served <> v_row then
      raise exception '0063 self-assert FAIL: the served departure (%) is not the row''s (%)', v_served, v_row;
    end if;
    -- She left BEFORE she arrives, and she left in the past. Two facts a wrong column would break.
    if v_served > now() then
      raise exception '0063 self-assert FAIL: she departed in the future (%)', v_served;
    end if;
    if v_served >= (v_payload->'voyage'->>'eta')::timestamptz then
      raise exception '0063 self-assert FAIL: departure % is not before arrival %',
        v_served, v_payload->'voyage'->>'eta';
    end if;

    raise exception '__PROBE_ROLLBACK__' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> '__PROBE_ROLLBACK__' then raise; end if;
  end;

  -- (e) POSTURE UNMOVED.
  select count(*) into v_grants from public.client_write_grants();
  if v_grants <> 0 then
    raise exception '0063 self-assert FAIL: % client write grant(s)', v_grants;
  end if;

  raise notice '0063 self-assert ok: world.fleets() serves the instant she left — proven on a real house put to sea, the served departed_at equal to the voyages row to the microsecond, in the past and strictly before her own eta; the pre-image did NOT carry the field (positive control) and the re-cut body is that pre-image plus exactly the one declared hunk, byte for byte; grants byte-identical; 0 client write grants. The marker cadence and the position itself are deliberately untouched — the glyph is still voyage.position and no part of the movement rule crosses the wire.';
end $$;
