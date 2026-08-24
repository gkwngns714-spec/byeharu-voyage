-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0049 — THE GRAPH IS HISTORY
--        public.legs is dropped. The raster (0046) is the ONE authority for what water connects
--        to what; the reach table carries every sailed distance; the mover (0047) reads neither
--        a leg nor a lane. A table nobody reads is drift waiting to be trusted.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY ITS OWN MIGRATION ──────────────────────────────────────────────────────────────────────
-- docs/NO_SPAGHETTI.md: when a new model replaces an old one, the deletion of the old is its OWN
-- explicit slice. 0047 replaced the mover and left public.legs "as history, with no reader" —
-- which is exactly the state the no-spaghetti law forbids leaving in place: a second, dead
-- authority for "what water connects to what", which every future world change would have to
-- keep regenerating (0041 regenerated data/sea-routes.json for no reader) and which the world
-- guard would keep certifying as if it mattered. So the table goes, the data file
-- (data/sea-routes.json) and its generator (scripts/build-sea-routes.mjs) are deleted in the
-- same commit, the growth generator (scripts/build-world-growth.mjs) stops deriving legs, and
-- the world guard stops checking a table that no longer exists — while KEEPING its planted-drift
-- positive controls, so it can still fail (a guard that cannot fail certifies nothing).
--
-- ── WHAT STILL MENTIONS LEGS, AND WHY THAT IS FINE ─────────────────────────────────────────────
--   * Applied migrations (0002 creates the table, 0003/0036/0041 seed it, 0045's probe routes
--     over it, 0047's carry-forward probe converts a leg-shaped path): they run at their own
--     chain positions, where the table still exists. History is not edited.
--   * Stored voyage paths: 0047 converted every leg-shaped path to self-contained legacy
--     segments; the guard below asserts none remain before the drop.
--   * voyage.convert_leg_path: its one-time conversion ran in 0047; it is dropped here, first,
--     because it is the last function whose body names the table.
--
-- Depends on: 0002 (the table), 0047 (the mover that left it readerless and converted the paths).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- The conversion tool's work is done; it is also the last catalogued reader of the table.
drop function voyage.convert_leg_path(jsonb);

do $$
declare
  v_legs    int;
  v_readers text;
  v_shaped  int;
begin
  -- (a) NON-VACUOUS: the world really held a graph here. A drop that deletes nothing is a
  --     different migration than the one this file documents.
  select count(*) into v_legs from public.legs;
  if v_legs < 100 then
    raise exception '0049 self-assert FAIL: only % leg row(s) found — this file documents the retirement of the 782-leg-era graph, and this database never held it', v_legs;
  end if;

  -- (b) NO FUNCTION READS THE TABLE. Asserted from the catalog itself, not from memory: if any
  --     live body still names public.legs, dropping the table would break it at call time —
  --     refuse here instead, by name.
  select string_agg(n.nspname || '.' || p.proname, ', ') into v_readers
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'voyage', 'cmd', 'world')
     and p.prosrc like '%public.legs%';
  if v_readers is not null then
    raise exception '0049 self-assert FAIL: public.legs still has reader(s): % — retire them before the table', v_readers;
  end if;

  -- (c) NO STORED PATH IS LEG-SHAPED. 0047 converted them all; a straggler would keep a
  --     dangling reference to rows this file deletes.
  select count(*) into v_shaped from public.voyages where path->0 ? 'leg_id';
  if v_shaped <> 0 then
    raise exception '0049 self-assert FAIL: % voyage path(s) still carry leg references', v_shaped;
  end if;

  raise notice '0049: dropping public.legs — % rows of graph history, zero readers, zero leg-shaped paths', v_legs;
end $$;

drop table public.legs;

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
begin
  -- the table and the conversion tool are GONE
  if to_regclass('public.legs') is not null then
    raise exception '0049 self-assert FAIL: public.legs still exists';
  end if;
  if to_regprocedure('voyage.convert_leg_path(jsonb)') is not null then
    raise exception '0049 self-assert FAIL: voyage.convert_leg_path still exists';
  end if;

  -- the free sea's authorities are intact: the raster, the reach table, the mover's law
  if (select count(*) from public.sea_raster) <> 1
     or (select count(*) from public.sea_reaches) <> (select count(*) from public.ports)
     or to_regprocedure('voyage.path_refusal(jsonb, numeric, numeric, numeric, numeric, numeric, numeric, numeric)') is null then
    raise exception '0049 self-assert FAIL: the free sea''s authorities are not standing';
  end if;

  -- the wire still resolves whole and the read wall did not move
  if exists (select 1 from public.client_rpc_entry_points() e where e.fn is null)
     or (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0049 self-assert FAIL: an entry point no longer resolves, or the read wall moved';
  end if;

  raise notice '0049 self-assert ok: THE GRAPH IS HISTORY — public.legs and voyage.convert_leg_path are gone, no live function names the table, no stored path is leg-shaped, the raster and the reach table stand as the one authority for the water, every client entry point still resolves, and the read wall reads zero';
end $$;
