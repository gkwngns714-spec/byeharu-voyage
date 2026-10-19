-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0206 — A GOOD BOARD KEEPS ITS OWN PLAN  (plan_cache_mode = force_custom_plan on world.good_board and
--        voyage.reach_passage)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY ─────────────────────────────────────────────────────────────────────────────────────────
-- 0205 (live 2026-10-19 04:55 UTC) made a good's board fast on its FIRST asks, then slow: timed on prod,
-- read-only, as one docked company in one session (docs/dev-log/2026-10-19-good-board-custom-plans.md):
--   retsina 1,456 ms, reach_passage 175 ms → martaban-jars 954 ms, reach_passage 8,101 ms → retsina
--   18,161 ms, reach_passage 7,938 ms.
-- PL/pgSQL caches each statement's plan; after five runs Postgres may switch it to a GENERIC plan (one plan for
-- every parameter value). For 0205's reach_passage that generic plan is ~40× slower. A pooled PostgREST
-- connection serves many asks, so a player switching goods hit it after a handful of presses.
-- The same six boards with `set local plan_cache_mode = force_custom_plan` held at 2.0–2.9 s each, reach_passage
-- at 187–276 ms every time (before 0205: 4.3–6.1 s a board).
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- ALTER FUNCTION … SET plan_cache_mode = force_custom_plan on the two functions, so each call plans its
-- statements for its own values. Bodies, ACL, volatility and definer are unchanged; the existing config
-- (search_path) is kept. Nothing else calls voyage.reach_passage (prod, 2026-10-19: world.good_board only).
-- ROLLBACK (forward migration): ALTER FUNCTION … RESET plan_cache_mode on both.
-- VERSION: 0206. Applies on 0205.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

create temp table before_0206 on commit drop as
select p.oid::regprocedure::text as fn, p.prosrc, coalesce(p.proacl::text, '') as acl, p.provolatile, p.prosecdef,
       coalesce(p.proconfig, '{}') as cfg
  from pg_proc p
 where p.oid in ('world.good_board(uuid, uuid, uuid, numeric)'::regprocedure, 'voyage.reach_passage(uuid, uuid)'::regprocedure);

alter function world.good_board(uuid, uuid, uuid, numeric) set plan_cache_mode = force_custom_plan;
alter function voyage.reach_passage(uuid, uuid) set plan_cache_mode = force_custom_plan;

do $$
declare
  b record;
  p record;
begin
  if (select count(*) from before_0206) <> 2 then
    raise exception '0206 self-assert FAIL: expected the two functions, found %', (select count(*) from before_0206);
  end if;
  for b in select * from before_0206 loop
    select x.prosrc, coalesce(x.proacl::text, '') as acl, x.provolatile, x.prosecdef, coalesce(x.proconfig, '{}') as cfg
      into p from pg_proc x where x.oid = b.fn::regprocedure;
    if not ('plan_cache_mode=force_custom_plan' = any (p.cfg)) then
      raise exception '0206 self-assert FAIL: % does not carry plan_cache_mode=force_custom_plan (config %)', b.fn, p.cfg;
    end if;
    if exists (select 1 from unnest(b.cfg) c where not (c = any (p.cfg))) then
      raise exception '0206 self-assert FAIL: % lost a setting it had (before %, after %)', b.fn, b.cfg, p.cfg;
    end if;
    if p.prosrc <> b.prosrc or p.acl <> b.acl or p.provolatile <> b.provolatile or p.prosecdef <> b.prosecdef then
      raise exception '0206 self-assert FAIL: % changed beyond its plan setting', b.fn;
    end if;
  end loop;
  raise notice '0206 self-assert ok: world.good_board and voyage.reach_passage plan each call for its own values; bodies, ACL, volatility, definer and their other settings unchanged';
end $$;
