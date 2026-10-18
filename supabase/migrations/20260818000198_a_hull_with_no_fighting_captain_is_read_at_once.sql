-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0198 — A HULL WITH NO FIGHTING CAPTAIN IS READ AT ONCE  (the cost of combat_bite, taken out; DARK)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY ─────────────────────────────────────────────────────────────────────────────────────────
-- 0192 lit combat and the arrivals sweep's average rose past its 3 s bound (0195 rolled it back). Two causes,
-- measured (docs/dev-log/2026-10-18-auto-fight.md, "Why the sweep rose"):
--   * 0182's re-plan batch (up to npc_replan_sweep_ms = 600 ms a sweep) moved the DARK baseline from ~2.1 s to
--     ~2.8 s at 14:20 UTC — the whole distribution shifted (p10 1.38 → 2.22 s, p50 2.07 → 2.80 s), and no deploy
--     after it moved it again. Not this file's: its knob is 0182's.
--   * Lit, every world.ship_stats call — speed, cargo space, supplies, every hull of every landing fleet and of
--     every re-plan — runs public.ship_crew_terms' loop: public.crew_pct three times (accuracy, reach, attack),
--     each a full public.crew_terms over the fleet. On a prod-shaped world: ship_stats over every hull 329 → 1071
--     ms, fleet speed + supplies 1425 → 3069 ms, cargo space 526 → 1293 ms; the same 15 landings 742 → 872 ms a
--     sweep (16 paired rounds). On production, 915 hulls × that loop measured 2.2 s read-only.
-- A term exists only for a captain seated ON that hull whose job, or a trait she uses, has a SHIP-scope effect
-- (the Gunner, the Boarder). Today no hull has one (prod, read-only: 0 of 915). So the loop answers "nothing"
-- at full price, for every hull, on every read.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- One hunk on public.ship_crew_terms: after the combat switch, if no captain seated on p_ship has a job or an
-- active trait with a ship-scope effect, return the stats as given. That is EXACTLY the old answer: every term
-- public.crew_pct sums for (fleet, p_ship, effect) is a public.crew_terms row of a captain seated on p_ship whose
-- job (dark) or active trait (lit) carries that effect — so with no such captain every v_pct is 0 and the loop
-- changes nothing. Measured: the same 15 landings lit 872 → 715 ms (dark 742).
--
-- ── WHAT IT DOES NOT DO ─────────────────────────────────────────────────────────────────────────
-- No knob, no row, no ALTER, no entry point; combat stays dark (0195). Not 0182's batch budget.
-- No top-level LOCK / SET LOCAL / BEGIN / SET ROLE. Timings by RAISE NOTICE only.
--
-- SUPERSEDES by one hunk sliced from the LIVE body (LF-normalised), asserted to occur once and to reverse to its
-- pre-image, ACL / volatility / definer / config unchanged: public.ship_crew_terms (0168).
-- ROLLBACK (forward migration): reverse the hunk (old text in hunks_0198).
-- VERSION: 0198 (provisional; head + 1 at deploy). Applies on 0197 (routes always pay).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  perform set_config('random_page_cost', '1.1', true);
end $guard$;

create or replace function pg_temp.occurs_0198(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 1. THE PRE-IMAGE, and the old body under a pg_temp name ─────────────────────────────────────
create temp table defs_before_0198 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('public.ship_crew_terms(uuid, jsonb)')) f(fn);

create temp table untouched_before_0198 on commit drop as
select f.fn, replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def
  from (values ('world.ship_stats(uuid)'), ('public.crew_pct(uuid, uuid, text, uuid, timestamp with time zone)'),
               ('public.crew_terms(uuid, timestamp with time zone)'), ('voyage.fight(uuid, integer, uuid, numeric)')) f(fn);

do $$
declare
  v_def text := (select def from defs_before_0198);
  v_new text := 'CREATE OR REPLACE FUNCTION pg_temp.ship_crew_terms_b0198(';
begin
  v_def := replace(v_def, 'CREATE OR REPLACE FUNCTION public.ship_crew_terms(', v_new);
  if pg_temp.occurs_0198(v_def, v_new) <> 1 then
    raise exception '0198 self-assert FAIL: could not rename the pre-image of public.ship_crew_terms';
  end if;
  execute v_def;
end $$;

create temp table dark_before_0198 on commit drop as
select s.id as ship_id, world.ship_stats(s.id)::text as st from public.ships s;

-- ── 2. THE HUNK ────────────────────────────────────────────────────────────────────────────────
create temp table hunks_0198 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0198 values
('public.ship_crew_terms(uuid, jsonb)', 1,
$h$  if p_stats is null or not public.combat_bite_on() then
    return p_stats;
  end if;
$h$,
$h$  if p_stats is null or not public.combat_bite_on() then
    return p_stats;
  end if;
  -- 0198: no captain seated on HER whose job or a trait she uses has a ship-scope effect → no term can be above 0
  -- (every term public.crew_pct sums for her is such a captain's), so the stats as given — the loop's own answer,
  -- without three public.crew_terms reads of the fleet for every hull on every read
  if not exists (select 1 from public.captain_seats cs
                   join public.player_officers po on po.id = cs.player_officer_id
                   join public.trait_effects te on te.trait in (select ca.trait from public.captain_active ca where ca.player_officer_id = po.id
                                                                union all
                                                                select j.job from public.captain_job j where j.officer_id = po.officer_id)
                   join public.crew_effects ce on ce.code = te.effect and ce.scope = 'ship'
                  where cs.ship_id = p_ship) then
    return p_stats;
  end if;
$h$);

do $$
declare
  d   record;
  h   record;
  v_def text;
begin
  for d in select * from defs_before_0198 loop
    v_def := d.def;
    for h in select * from hunks_0198 where fn = d.fn order by n loop
      if pg_temp.occurs_0198(v_def, h.old) <> 1 then
        raise exception '0198 self-assert FAIL: hunk % of % occurs % time(s), not once', h.n, d.fn, pg_temp.occurs_0198(v_def, h.old);
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    execute v_def;
  end loop;
end $$;


-- ── 3. THE PROBE (rolled back): every hull lit, the old body vs the new; captains who fight; the cost ─
create or replace function pg_temp.probe_0198()
returns jsonb
language plpgsql
as $$
declare
  c_p    constant uuid := '00000000-0198-4000-8000-000000000001';
  v_p    uuid;
  v_pf   uuid;
  v_nau  uuid;
  v_base jsonb;
  v_out  jsonb := '{}'::jsonb;
  v_t0   timestamptz;
  v_n    int;
  v_m    int;
  v_len  numeric;
begin
  begin
    update public.world_config set value = 'true'::jsonb where key in ('combat_bite', 'crew_bite');
    -- (a) every hull of the world, lit: the new body = the old body, answer for answer (on the hull's own base stats)
    update public.world_config set value = 'false'::jsonb where key = 'combat_bite';
    create temp table base_0198 on commit drop as select s.id as ship_id, world.ship_stats(s.id) as st from public.ships s;
    update public.world_config set value = 'true'::jsonb where key = 'combat_bite';
    select count(*), count(*) filter (where public.ship_crew_terms(b.ship_id, b.st) is distinct from pg_temp.ship_crew_terms_b0198(b.ship_id, b.st))
      into v_n, v_m from base_0198 b;
    v_out := v_out || jsonb_build_object('hulls', v_n, 'hulls_differ', v_m);
    -- (b) the cost of the read, lit: world.ship_stats over every hull — the new body, then the old one reinstated
    v_t0 := clock_timestamp();
    select count(*), sum(length(world.ship_stats(s.id)::text)) into v_n, v_len from public.ships s;
    v_out := v_out || jsonb_build_object('lit_new_ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1));
    execute (select def from defs_before_0198);
    v_t0 := clock_timestamp();
    select count(*), sum(length(world.ship_stats(s.id)::text)) into v_n, v_len from public.ships s;
    v_out := v_out || jsonb_build_object('lit_old_ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1));
    raise exception 'PROBE_ROLLBACK_0198';
  exception when others then
    if sqlerrm <> 'PROBE_ROLLBACK_0198' then raise; end if;
  end;
  begin
    -- (c) its own company: Tartaglia (Gunner, her job) in the nau's Captain's cabin and Turgut Reis (Boarder, a trait
    --     in use) in its second cabin — the guard lets them through: new body = old body, and the stats DO move
    update public.world_config set value = 'true'::jsonb where key = 'crew_bite';
    update public.world_config set value = 'false'::jsonb where key = 'combat_bite';
    v_p := public.new_house(c_p, 'Casa da Pressa 0198', 'PRT', 'LIS');
    select id into v_pf from public.fleets where player_id = v_p;
    perform public.credit(v_p, 'PROBE_0198', 10000000);
    v_nau := public.commission_ship(v_p, v_pf, 'nau', 'Prova Nau', false, true);
    perform public.sign_officer(v_p, 'TARTAGLIA', v_pf);
    perform public.seat_captain_for(v_p, 'TARTAGLIA', v_nau, 1);
    perform public.captain_traits_set_for(v_p, 'TARTAGLIA', array['GUNNER']);
    perform public.sign_officer(v_p, 'TURGUT', v_pf);
    perform public.seat_captain_for(v_p, 'TURGUT', v_nau, 2);
    perform public.captain_traits_set_for(v_p, 'TURGUT', array['BOARDER']);
    v_base := world.ship_stats(v_nau);
    update public.world_config set value = 'true'::jsonb where key = 'combat_bite';
    v_out := v_out || jsonb_build_object('captains', jsonb_build_object(
      'seated', (select count(*) from public.captain_seats where ship_id = v_nau),
      'base', v_base, 'new', public.ship_crew_terms(v_nau, v_base), 'old', pg_temp.ship_crew_terms_b0198(v_nau, v_base),
      'stats', world.ship_stats(v_nau)));
    raise exception 'PROBE_ROLLBACK_0198';
  exception when others then
    if sqlerrm <> 'PROBE_ROLLBACK_0198' then raise; end if;
  end;
  return v_out;
end $$;

create temp table probe_0198 (j jsonb) on commit drop;
do $$
declare
  v_try int := 0; v_state text; v_msg text;
begin
  loop
    v_try := v_try + 1;
    begin
      insert into probe_0198 select pg_temp.probe_0198();
      exit;
    exception when lock_not_available or deadlock_detected then
      get stacked diagnostics v_msg = message_text, v_state = returned_sqlstate;
    end;
    if v_try >= 5 then
      raise exception '0198 self-assert FAIL: LOCK CONTENTION, not a result (%: %). Re-run the push.', v_state, v_msg;
    end if;
    perform pg_sleep(0.2);
  end loop;
end $$;

-- ── 4. SELF-ASSERT ─────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_pr  jsonb := (select j from probe_0198);
  v_c   jsonb;
  v_d   record;
  v_pp  record;
  v_def text;
  v_h   record;
  v_bad int;
begin
  -- (a) dark (as the world stands): every hull's ship_stats is what it was before the hunk
  select count(*) into v_bad from dark_before_0198 b where world.ship_stats(b.ship_id)::text is distinct from b.st;
  if v_bad <> 0 or (select count(*) from dark_before_0198) = 0 then
    raise exception '0198 self-assert FAIL: dark, % hull(s) read different stats', v_bad;
  end if;
  -- (b) lit, every hull: the new body answers as the old
  if (v_pr->>'hulls')::int = 0 or (v_pr->>'hulls_differ')::int <> 0 then
    raise exception '0198 self-assert FAIL: lit, % of % hull(s) read differently through the new body', v_pr->>'hulls_differ', v_pr->>'hulls';
  end if;
  -- (c) fighting captains are not skipped: the same answer as the old body, and the stats moved
  v_c := v_pr->'captains';
  if (v_c->>'seated')::int <> 2 or v_c->'new' is distinct from v_c->'old' or v_c->'new' = v_c->'base'
     or not ((v_c->'new'->>'accuracy')::numeric > (v_c->'base'->>'accuracy')::numeric)
     or not ((v_c->'new'->>'attack')::numeric > (v_c->'base'->>'attack')::numeric) then
    raise exception '0198 self-assert FAIL: with a Gunner and a Boarder seated the new body read % (old %, base %)', v_c->'new', v_c->'old', v_c->'base';
  end if;
  -- (d) the hunk reverses to the pre-image; ACL / volatility / definer / config unmoved; neighbours untouched
  for v_d in select * from defs_before_0198 loop
    v_def := replace(pg_get_functiondef(v_d.fn::regprocedure), E'\r', '');
    for v_h in select * from hunks_0198 where fn = v_d.fn order by n desc loop
      if pg_temp.occurs_0198(v_def, v_h.new) <> 1 then
        raise exception '0198 self-assert FAIL: hunk % is not in the new body exactly once', v_h.n;
      end if;
      v_def := replace(v_def, v_h.new, v_h.old);
    end loop;
    if v_def <> v_d.def then
      raise exception '0198 self-assert FAIL: % does not reverse to its pre-image', v_d.fn;
    end if;
    select coalesce(pr.proacl::text, '') acl, pr.provolatile vol, pr.prosecdef secdef, coalesce(pr.proconfig::text, '') cfg
      into v_pp from pg_proc pr where pr.oid = v_d.fn::regprocedure;
    if v_pp.acl <> v_d.acl or v_pp.vol <> v_d.vol or v_pp.secdef <> v_d.secdef or v_pp.cfg <> v_d.cfg then
      raise exception '0198 self-assert FAIL: % changed its ACL, volatility, definer or config', v_d.fn;
    end if;
  end loop;
  for v_d in select * from untouched_before_0198 loop
    if replace(pg_get_functiondef(v_d.fn::regprocedure), E'\r', '') <> v_d.def then
      raise exception '0198 self-assert FAIL: % moved — it was to be left untouched', v_d.fn;
    end if;
  end loop;
  if (select count(*) from public.client_write_grants()) <> 0 or (select count(*) from public.client_executable_writers()) <> 0
     or (select value from public.world_config where key = 'combat_bite') <> 'false'::jsonb then
    raise exception '0198 self-assert FAIL: the grant wall moved, or combat is not dark';
  end if;
  raise notice '0198 self-assert ok: A HULL WITH NO FIGHTING CAPTAIN IS READ AT ONCE. DARK: % hull(s) read the same stats. LIT (rolled back): % hull(s), the new body = the old for every one; a nau with a seated Gunner and Boarder read through (accuracy % → %, attack % → %, = the old body). COST lit (notice only): ship_stats over every hull % ms (old body % ms). 1 body reverses, 4 untouched, combat dark.',
    (select count(*) from dark_before_0198), v_pr->>'hulls', v_c->'base'->>'accuracy', v_c->'new'->>'accuracy',
    v_c->'base'->>'attack', v_c->'new'->>'attack', v_pr->>'lit_new_ms', v_pr->>'lit_old_ms';
end $$;
