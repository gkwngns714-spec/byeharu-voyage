-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0150 — A MERCHANT PAYS NOTHING FOR SKILLS SHE CANNOT USE  (K0: lit skills read cheaply — perf only)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY NOW ─────────────────────────────────────────────────────────────────────────────────────
-- docs/SKILLS_AND_CAPTAINS.md §7.1 and §8 row K0: "before anything is lit: lit skills must be cheap for
-- merchants". Lighting skills_bite today costs about 2 × the merchant ship reads (RESUME / DEV_LOG 0133:
-- speed + cargo space 345 → 622 ms, ship_view 1,388 → 2,414 ms on the cached world), because every
-- hot read of a merchant hull (world.ship_stats, called 4-5 times per ship_view; world.ship_budget;
-- world.ship_view; public.fleet_officer_bonus → world.skill_pct) runs world.skill_bonuses' whole query
-- for a house whose skills cannot touch a ship. Merchants hold only the four company skills
-- (ACCOUNTING, HAGGLING, NAVIGATION, SEAMANSHIP — public.skill_effects scope 'company', read by
-- public.player_skill_bonus, never by these reads), so for them every one of those queries returns
-- nothing. K0 makes that "nothing" one indexed read. THE SWITCH DOES NOT MOVE: skills_bite stays false.
--
-- ── WHAT THIS FILE DOES (one authority; every answer is the pre-image, dark AND lit — asserted) ──
-- (1) public.house_skill_scopes(player, ship) — NEW: THE one reading of "which scopes can this company's
--     skills reach" — the distinct public.skill_effects scopes (ship, fitting, house; never company)
--     of every skill the house holds a level in: a public.player_skills row (level ≥ 1 by its CHECK)
--     or a public.skill_queue entry whose finish has passed — EXACTLY world.skill_bonuses' own `held`
--     set, so "no scope here" ⇔ "skill_bonuses finds no row of that scope". PL/pgSQL (cached plan —
--     0133's lesson: PostgreSQL 17 re-plans a SQL body on every call), STABLE, invoker, no SET (the
--     per-call SET cost measured by 0135), every name schema-qualified. '{}' for no such house. The
--     company is the player named, or (player null) the owner of the ship named, so a hull's reader asks
--     in a plain call with no query in its own expression.
-- (2) EARLY EXITS, by hunks sliced from the LIVE bodies (prod 0140, pg_get_functiondef, LF-normalised),
--     each placed AFTER the live switch test (dark runs exactly the statements it ran before):
--       world.skill_bonuses   returns at once when the house holds no skill of the scope the read can
--                             return (house with no ship; ship / fitting with one)
--       world.skill_pct       becomes PL/pgSQL (same query; its plan cached) — it only sums skill_bonuses
--       world.ship_stats      lit branch only when the house holds a SHIP-scope skill; else the dark
--                             query, which is the lit query's answer when no skill row joins (every
--                             d.pct is null → `b.base + coalesce(d.delta, 0)`, the same expression)
--       world.ship_budget     returns the 0132 budget at once with no FITTING-scope skill (the lit tail
--                             would find v_deck = v_drill = 0 and return it anyway)
--       world.ship_view       `bonuses` = the constant [] with no SHIP / FITTING-scope skill (the lit
--                             aggregate over no row is coalesce(…, '[]')); and its one world.ship_stats
--                             call made ONE again (`offset 0`): 0124's builder says "one ship_stats call
--                             for the six combat stats", but the planner pulls that lateral up and runs
--                             ship_stats once per x.st reference — six times a ship, so every per-call
--                             cost (the lit test above all) was paid six times over. Measured on the
--                             cached world: merchant ship_view dark 1,025 → 727 ms. Not named in the
--                             plan's K0 row; the same answer (proven below), fewer calls.
--       public.fleet_officer_bonus   its Command term only for a house with a HOUSE-scope skill (with none,
--                             world.skill_pct reads 0 and skill_scale returns the officers' sum itself —
--                             v_bonus). Not named in the plan's K0 row: it is the merchant read that
--                             otherwise walks skill_pct → skill_bonuses → the probe, three calls deep.
--
-- ── WHAT IT DELIBERATELY DOES NOT DO ────────────────────────────────────────────────────────────
-- Light skills_bite. Change any answer, rule, knob, table, row, refusal, client grant or entry point.
-- Read is_npc anywhere (a merchant leaves early because of what she holds, not who she is — the probe
-- shows a player house with only company skills leaving the same way). Touch world.ship_stat,
-- voyage.ship_speed, voyage.fleet_speed, public.ship_hold_capacity,
-- public.player_skill_bonus, public.skill_level(_at), public.skills_bite_on (asserted untouched). Cache
-- anything across calls.
--
-- ── THE PROOF (all in this file; old and new on the SAME snapshot, one statement each) ──────────
-- §1 keeps the pre-image TREE under pg_temp names: world.skill_bonuses, world.skill_pct, world.ship_stats,
-- world.ship_stat, world.ship_budget, world.ship_view, voyage.ship_speed, voyage.fleet_speed,
-- public.ship_hold_capacity, public.fleet_officer_bonus — every function on a path from the compared
-- reads to a changed body (checked on prod 0140: no other body calls a changed one on those paths), each
-- copy pointed at the other copies. §4 compares, as text and as an md5 over the whole set, DARK (as
-- shipped) and LIT (skills_bite true inside a rolled-back subtransaction): every hull's ship_stats,
-- ship_budget, ship_view (which carries speed, cargo space and `bonuses`), voyage.ship_speed and
-- public.ship_hold_capacity; every fleet's voyage.fleet_speed and fleet_officer_bonus for each
-- specialty; every house's skill_pct('officer_bonus') and house-scope skill_bonuses. A difference
-- RAISES. Every house's house_skill_scopes equals the scopes derived independently through
-- public.skill_level (the one reading of a level) — a difference RAISES.
-- THE CONTROL (own throw-away houses, rolled back): a probe company with PRT Medium Hulls III, Deck
-- Management II, Command II, an officer and a nau; a second whose only ship skill is a FINISHED queue
-- entry (Lookouts I); a third whose ship skill is still training; a fourth with only company skills.
-- Lit, the first reads the nau's sighting × (1 + its Medium Hulls III per cents, derived from
-- skill_effects — +12 % as 0133 wrote it), Deck above dark, officer bonus × Command; the second's hull
-- reads Lookouts I; the third and fourth leave early. Old = new for all four, dark and lit.
-- §5 TIMES the merchant reads (speed + cargo space, ship_stats, ship_view over every merchant hull),
-- old tree vs new, dark and lit, three passes with old and new interleaved, the fastest kept, AT PRODUCTION'S PLANNER PAGE COST
-- (random_page_cost 1.1 for this transaction — prod's own setting, so a no-op there; PGlite plans at 4,
-- see 0135's header) and REPORTS them, with K0's bound "lit ≤ dark × 1.15 + 50 ms", in a notice —
-- never a raise: prod runs on burstable CPU (0135/0136), and a timing gate could abort an honest push.
--
-- ── LOCKS ───────────────────────────────────────────────────────────────────────────────────────
-- ACCESS SHARE on what it reads; CREATE FUNCTION / CREATE OR REPLACE FUNCTION (no table lock); pg_temp
-- objects; probe writes on its own throw-away houses, and the lit flip of world_config.skills_bite,
-- each inside a rolled-back subtransaction (their row locks go with it). No LOCK TABLE, no set role, no
-- top-level set. Deploy with the clock unwound as usual (DEPLOY_RUNBOOK): unwind_the_clock() → db push
-- → wind_the_clock().
--
-- ROLLBACK: a forward migration putting the six pre-image bodies back (each is here verbatim as its
-- hunks' OLD text; the self-assert proves each live body reverses to its pre-image) and dropping
-- public.house_skill_scopes. Nothing else moved.
-- SUPERSEDES, by hunks sliced from the LIVE bodies (LF-normalised), each asserted to occur exactly once,
-- ACLs / definer / config unchanged: world.skill_bonuses (0133), world.skill_pct (0133, SQL → PL/pgSQL),
-- world.ship_stats (0133), world.ship_budget (0133), world.ship_view (0133), public.fleet_officer_bonus (0133).
-- VERSION: 0150 (provisional — renumbered to head + 1 at merge). Applies on prod head 0140.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  -- every plan this file makes (the comparisons and the timings alike) is made at PRODUCTION'S page
  -- cost — on prod a no-op (its configuration says 1.1), on PGlite (default 4) what prod's planner does
  perform set_config('random_page_cost', '1.1', true);
end $guard$;

-- ── 0. HELPERS (pg_temp, gone at commit) ───────────────────────────────────────────────────────
create or replace function pg_temp.occurs_0150(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 1. THE PRE-IMAGES ──────────────────────────────────────────────────────────────────────────
create temp table defs_before_0150 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg,
       (select p.proparallel from pg_proc p where p.oid = f.fn::regprocedure) as par
  from (values ('world.skill_bonuses(uuid, uuid)'),
               ('world.skill_pct(uuid, uuid, text)'),
               ('world.ship_stats(uuid)'),
               ('world.ship_budget(uuid)'),
               ('world.ship_view(uuid)'),
               ('public.fleet_officer_bonus(uuid, text)')) f(fn);

-- NOT re-cut: their bodies must come out of this file exactly as they went in.
create temp table untouched_before_0150 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl
  from (values ('world.ship_stat(uuid, text)'), ('voyage.ship_speed(uuid)'), ('voyage.fleet_speed(uuid)'),
               ('public.ship_hold_capacity(uuid)'),
               ('public.player_skill_bonus(uuid, text)'), ('public.skill_level(uuid, text)'),
               ('public.skill_level_at(uuid, text, timestamp with time zone)'), ('public.skills_bite_on()')) f(fn);

create temp table before_0150 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'house_skill_scopes') as n_found;

-- THE OLD TREE: every function on a path from the reads §4 compares to a changed body. One overload each.
create temp table tree_0150 (nsp text, name text) on commit drop;
insert into tree_0150 values ('world', 'skill_bonuses'), ('world', 'skill_pct'), ('world', 'ship_stats'),
                             ('world', 'ship_stat'), ('world', 'ship_budget'), ('world', 'ship_view'),
                             ('voyage', 'ship_speed'), ('voyage', 'fleet_speed'),
                             ('public', 'ship_hold_capacity'), ('public', 'fleet_officer_bonus');

create or replace function pg_temp.old_sql_0150(p_sql text)
returns text
language plpgsql
stable
as $$
declare
  t record;
  v text := p_sql;
begin
  for t in select nsp, name from tree_0150 order by length(name) desc, nsp, name loop
    v := replace(v, t.nsp || '.' || t.name || '(', 'pg_temp.' || t.nsp || '_' || t.name || '_0150(');
  end loop;
  return v;
end $$;

create temp table old_tree_0150 on commit drop as
select n.nspname as nsp, p.proname as name, p.oid::regprocedure::text as sig,
       pg_temp.old_sql_0150(replace(pg_get_functiondef(p.oid), E'\r', '')) as def
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  join tree_0150 t on t.nsp = n.nspname and t.name = p.proname;

do $$
declare
  d    record;
  v_n  int;
  v_l  text;
begin
  if (select count(*) from old_tree_0150) <> (select count(*) from tree_0150) then
    raise exception '0150 self-assert FAIL: the old tree lists % name(s) but % live function(s) were found',
      (select count(*) from tree_0150), (select count(*) from old_tree_0150);
  end if;
  -- THE TREE IS CLOSED on the compared paths: the six changed bodies are called, among live bodies,
  -- only by members of the tree and by callers this file does not compare whole (public.mount_fitting
  -- calls world.skill_pct / world.ship_budget; world.fleets / world.npc_fleet_card call world.ship_view;
  -- public.raid_crew_lost, voyage.settle, world.spread_effective and world.fleets call
  -- public.fleet_officer_bonus) — what they read of a changed body is that body's answer, proven equal below.
  select count(*), string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v_n, v_l
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where p.pronamespace <> pg_my_temp_schema()
     and p.prosrc ~ '(world\.(skill_bonuses|skill_pct|ship_stats|ship_budget|ship_view)|public\.fleet_officer_bonus)\('
     and not exists (select 1 from tree_0150 t where t.nsp = n.nspname and t.name = p.proname)
     and p.oid not in ('public.mount_fitting(uuid, text)'::regprocedure, 'world.fleets()'::regprocedure,
                       'world.npc_fleet_card(uuid)'::regprocedure, 'public.raid_crew_lost(uuid, numeric, numeric)'::regprocedure,
                       'voyage.settle(uuid, timestamp with time zone)'::regprocedure,
                       'world.spread_effective(uuid, uuid, uuid, boolean)'::regprocedure);
  if v_n > 0 then
    raise exception '0150 self-assert FAIL: % live bod(ies) outside the old tree call a changed body: % — the tree is not closed', v_n, v_l;
  end if;
  -- NO COPY REACHES A LIVE TREE BODY (and every copy was renamed)
  for d in select * from old_tree_0150 loop
    if strpos(d.def, 'CREATE OR REPLACE FUNCTION pg_temp.' || d.nsp || '_' || d.name || '_0150(') <> 1 then
      raise exception '0150 self-assert FAIL: the old copy of % was not renamed', d.sig;
    end if;
    if d.def ~ '(world\.(skill_bonuses|skill_pct|ship_stats|ship_stat|ship_budget|ship_view)|voyage\.(ship_speed|fleet_speed)|public\.(ship_hold_capacity|fleet_officer_bonus))\('
       or strpos(d.def, 'house_skill_scopes') > 0 then
      raise exception '0150 self-assert FAIL: the old copy of % still calls a live tree body', d.sig;
    end if;
  end loop;
  perform set_config('check_function_bodies', 'off', true);
  for d in select * from old_tree_0150 order by nsp, name, sig loop
    execute d.def;
  end loop;
  perform set_config('check_function_bodies', 'on', true);
  select count(*) into v_n from pg_proc p
   where p.pronamespace = pg_my_temp_schema()
     and p.proname in (select t.nsp || '_' || t.name || '_0150' from tree_0150 t);
  if v_n <> 10 then
    raise exception '0150 self-assert FAIL: % old cop(ies) made, not 10', v_n;
  end if;
end $$;

-- ── 2. THE ONE READING OF WHICH SCOPES A COMPANY'S SKILLS REACH ─────────────────────────────────
create function public.house_skill_scopes(p_player uuid, p_ship uuid default null)
returns text[]
language plpgsql
stable
as $hs$
declare
  v_player uuid := p_player;
begin
  -- 0150: THE ONE READING OF "WHICH SCOPES CAN THIS COMPANY'S SKILLS REACH" — the distinct
  -- public.skill_effects scopes (ship, fitting, house; company is public.player_skill_bonus' and never
  -- asked here) of every skill the house holds a level in: a player_skills row (level >= 1, its CHECK) or
  -- a queue entry whose finish has passed — world.skill_bonuses' own `held` set, so a scope absent here
  -- is a scope skill_bonuses can return no row of. The house is p_player, or, with none, the owner of
  -- p_ship (so a hull's reader asks in a plain call, with no query of its own). '{}' for a house that
  -- holds none, or no house. Read by world.skill_bonuses, world.ship_stats, world.ship_budget,
  -- world.ship_view and public.fleet_officer_bonus to leave at once when nothing could apply (every
  -- merchant: her fixed skills are the four company ones). No merchant flag is read.
  if v_player is null and p_ship is not null then
    select s.player_id into v_player from public.ships s where s.id = p_ship;
  end if;
  if v_player is null then
    return '{}'::text[];
  end if;
  return coalesce(
    (select array_agg(distinct e.scope)
       from public.skill_effects e
      where e.scope <> 'company'
        and e.skill_code in (select sk.code
                               from public.skills sk
                              where sk.id in (select ps.skill_id from public.player_skills ps
                                               where ps.player_id = v_player
                                              union all
                                              select q.skill_id from public.skill_queue q
                                               where q.player_id = v_player and q.finishes_at <= now()))),
    '{}'::text[]);
end $hs$;
comment on function public.house_skill_scopes(uuid, uuid) is
  '0150: THE reading of which skill_effects scopes (ship / fitting / house) a company''s held skills reach — '
  'world.skill_bonuses'' own held set; the company is p_player, or the owner of p_ship. Read by '
  'world.skill_bonuses, world.ship_stats, world.ship_budget, world.ship_view and public.fleet_officer_bonus to '
  'leave at once when nothing could apply (every merchant). PL/pgSQL, STABLE, invoker, no SET. Server-only.';
revoke all on function public.house_skill_scopes(uuid, uuid) from public, anon, authenticated;

-- ── 3. THE RE-CUTS (hunks: old = verbatim from the live bodies; new = what replaces it) ─────────
-- Every exit sits AFTER the live switch test, never inside it: dark (skills_bite false) runs exactly the
-- statements it ran before, and the lit test is a plain call (no query in the caller's expression).
create temp table hunks_0150 (fn text, n int, old text, new text) on commit drop;

insert into hunks_0150 values
('world.skill_bonuses(uuid, uuid)', 1,
$h$  if p_player is null or not public.skills_bite_on() then
    return;
  end if;
$h$,
$h$  if p_player is null or not public.skills_bite_on() then
    return;
  end if;
  -- 0150: … nor for a company that holds no skill with an effect of the scope this read can return
  -- (public.house_skill_scopes, one indexed read): no row below could match it. Every merchant leaves here.
  if not (public.house_skill_scopes(p_player)
          && case when p_ship is null then array['house'] else array['ship', 'fitting'] end) then
    return;
  end if;
$h$),
('world.skill_pct(uuid, uuid, text)', 1,
$h$ LANGUAGE sql
$h$,
$h$ LANGUAGE plpgsql
$h$),
('world.skill_pct(uuid, uuid, text)', 2,
$h$AS $function$
$h$,
$h$AS $function$
begin
  -- 0150: PL/pgSQL so its plan is cached (PostgreSQL 17 re-plans a SQL body on every call — 0133's
  -- lesson); the same query, the same answer.
  return (
$h$),
('world.skill_pct(uuid, uuid, text)', 3,
$h$  select coalesce(sum(sb.pct), 0) from world.skill_bonuses(p_player, p_ship) sb where sb.stat = p_stat
$function$$h$,
$h$  select coalesce(sum(sb.pct), 0) from world.skill_bonuses(p_player, p_ship) sb where sb.stat = p_stat
  );
end $function$$h$),
('world.ship_stats(uuid)', 1,
$h$  if public.skills_bite_on() then
    return (
$h$,
$h$  if public.skills_bite_on() then
  -- 0150: … and only for a company that holds a skill with a SHIP effect (public.house_skill_scopes, one
  -- indexed read). For any other — every merchant — no skill row would join below, every d.pct would be
  -- null and the query would read `b.base + coalesce(d.delta, 0)`: the very expression of the branch after it.
  if 'ship' = any(public.house_skill_scopes(null, p_ship)) then
    return (
$h$),
('world.ship_stats(uuid)', 2,
$h$    );
  end if;
  -- 0133: WHILE IT IS OFF$h$,
$h$    );
  end if;
  end if;
  -- 0133: WHILE IT IS OFF$h$),
('world.ship_budget(uuid)', 1,
$h$  if v_bud is null or not public.skills_bite_on() then
    return v_bud;
  end if;
$h$,
$h$  if v_bud is null or not public.skills_bite_on() then
    return v_bud;
  end if;
  -- 0150: … and for a company with no FITTING-scope skill (public.house_skill_scopes — every merchant)
  -- the tail below would find v_deck = v_drill = 0 and return v_bud: it returns it at once.
  if not ('fitting' = any(public.house_skill_scopes(null, p_ship))) then
    return v_bud;
  end if;
$h$),
('public.fleet_officer_bonus(uuid, text)', 1,
$h$  if v_bonus = 0 or not public.skills_bite_on() then
    return v_bonus;
  end if;
$h$,
$h$  if v_bonus = 0 or not public.skills_bite_on() then
    return v_bonus;
  end if;
  -- 0150: … nor for a company that holds no HOUSE-scope skill (public.house_skill_scopes — every merchant):
  -- officer_bonus is the only house effect (skill_effects' CHECK), so with none world.skill_pct reads 0 and
  -- public.skill_scale returns the sum itself — the very v_bonus above.
  if not ('house' = any(public.house_skill_scopes((select fl.player_id from public.fleets fl where fl.id = p_fleet)))) then
    return v_bonus;
  end if;
$h$),
('world.ship_view(uuid)', 1,
$h$  if v_view is null or not public.skills_bite_on() then
    return v_view || '{"bonuses": []}'::jsonb;
  end if;
$h$,
$h$  if v_view is null or not public.skills_bite_on() then
    return v_view || '{"bonuses": []}'::jsonb;
  end if;
  -- 0150: … and the constant [] too for a company with no SHIP- or FITTING-scope skill
  -- (public.house_skill_scopes — every merchant): world.skill_bonuses would return no row for her.
  if not (public.house_skill_scopes(null, p_ship) && array['ship', 'fitting']) then
    return v_view || '{"bonuses": []}'::jsonb;
  end if;
$h$),
('world.ship_view(uuid)', 2,
$h$   cross join lateral (select world.ship_stats(s.id) as st) x
$h$,
$h$   -- 0150: OFFSET 0 keeps this ONE call, as 0124's header above says: without it the planner pulls the
   -- lateral up and evaluates world.ship_stats once per x.st reference — six times a ship (measured).
   cross join lateral (select world.ship_stats(s.id) as st offset 0) x
$h$);

create or replace function pg_temp.recut_0150(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := replace(pg_get_functiondef(p_fn::regprocedure), E'\r', '');
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0150 where fn = p_fn order by n loop
    v_n := pg_temp.occurs_0150(v_def, h.old);
    if v_n <> 1 then
      raise exception '0150 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0150(fn) from defs_before_0150 order by fn;

-- ── 4. THE COMPARISONS — old tree and new, side by side in ONE statement each (one snapshot) ─────
-- One row per subject, every answer as text; old and new must be byte-equal, dark AND lit.
create or replace function pg_temp.compare_0150()
returns jsonb
language plpgsql
as $$
declare
  v_hulls  jsonb;
  v_fleets jsonb;
  v_houses jsonb;
begin
  select jsonb_build_object('n', count(*), 'bad', count(*) filter (where z.new_v is distinct from z.old_v),
                            'md5_new', md5(string_agg(z.new_v::text, '|' order by z.id)),
                            'md5_old', md5(string_agg(z.old_v::text, '|' order by z.id)),
                            'bonus_rows', sum(z.bonus_rows),
                            'ex', min(z.id::text) filter (where z.new_v is distinct from z.old_v))
    into v_hulls
    from (select s.id,
                 jsonb_build_array(world.ship_stats(s.id)::text, world.ship_budget(s.id)::text, world.ship_view(s.id)::text,
                                voyage.ship_speed(s.id)::text, public.ship_hold_capacity(s.id)::text) as new_v,
                 jsonb_build_array(pg_temp.world_ship_stats_0150(s.id)::text, pg_temp.world_ship_budget_0150(s.id)::text,
                                pg_temp.world_ship_view_0150(s.id)::text, pg_temp.voyage_ship_speed_0150(s.id)::text,
                                pg_temp.public_ship_hold_capacity_0150(s.id)::text) as old_v,
                 jsonb_array_length(world.ship_view(s.id)->'bonuses') as bonus_rows
            from public.ships s) z;
  select jsonb_build_object('n', count(*), 'bad', count(*) filter (where z.new_v is distinct from z.old_v),
                            'md5_new', md5(string_agg(z.new_v::text, '|' order by z.id)),
                            'md5_old', md5(string_agg(z.old_v::text, '|' order by z.id)),
                            'ex', min(z.id::text) filter (where z.new_v is distinct from z.old_v))
    into v_fleets
    from (select f.id,
                 jsonb_build_array(voyage.fleet_speed(f.id)::text,
                           (select string_agg(public.fleet_officer_bonus(f.id, sp.specialty)::text, ',' order by sp.specialty)
                              from (select distinct o.specialty from public.officers o) sp)) as new_v,
                 jsonb_build_array(pg_temp.voyage_fleet_speed_0150(f.id)::text,
                           (select string_agg(pg_temp.public_fleet_officer_bonus_0150(f.id, sp.specialty)::text, ',' order by sp.specialty)
                              from (select distinct o.specialty from public.officers o) sp)) as old_v
            from public.fleets f
           where exists (select 1 from public.ships s where s.fleet_id = f.id)) z;
  select jsonb_build_object('n', count(*), 'bad', count(*) filter (where z.new_v is distinct from z.old_v),
                            'md5_new', md5(string_agg(z.new_v::text, '|' order by z.id)),
                            'md5_old', md5(string_agg(z.old_v::text, '|' order by z.id)),
                            'ex', min(z.id::text) filter (where z.new_v is distinct from z.old_v))
    into v_houses
    from (select p.id,
                 jsonb_build_array(world.skill_pct(p.id, null, 'officer_bonus')::text,
                           (select coalesce(jsonb_agg(to_jsonb(sb) order by sb.skill_code, sb.stat), '[]'::jsonb)::text
                              from world.skill_bonuses(p.id, null) sb)) as new_v,
                 jsonb_build_array(pg_temp.world_skill_pct_0150(p.id, null, 'officer_bonus')::text,
                           (select coalesce(jsonb_agg(to_jsonb(sb) order by sb.skill_code, sb.stat), '[]'::jsonb)::text
                              from pg_temp.world_skill_bonuses_0150(p.id, null) sb)) as old_v
            from public.players p) z;
  return jsonb_build_object('hulls', v_hulls, 'fleets', v_fleets, 'houses', v_houses);
end $$;

-- every house's scopes = the scopes derived independently through public.skill_level, the one reading
-- of a level (a level > 0 in a skill with an effect of that scope)
create or replace function pg_temp.scopes_check_0150()
returns jsonb
language plpgsql
as $$
begin
  return (
  select jsonb_build_object('n', count(*),
                            'bad', count(*) filter (where not (z.got @> z.want and z.want @> z.got)),
                            'empty', count(*) filter (where cardinality(z.got) = 0),
                            'ex', min(z.id::text) filter (where not (z.got @> z.want and z.want @> z.got)),
                            -- a hull's form (no player, her ship) names her owner's scopes
                            'ships', (select count(*) from public.ships s),
                            'ship_bad', (select count(*) from public.ships s
                                          where public.house_skill_scopes(null, s.id) is distinct from public.house_skill_scopes(s.player_id)))
    from (select p.id, public.house_skill_scopes(p.id) as got,
                 coalesce((select array_agg(distinct e.scope)
                             from public.skill_effects e
                             join public.skills sk on sk.code = e.skill_code
                            where e.scope <> 'company'
                              and (exists (select 1 from public.player_skills ps where ps.player_id = p.id and ps.skill_id = sk.id)
                                   or exists (select 1 from public.skill_queue q where q.player_id = p.id and q.skill_id = sk.id))
                              and public.skill_level(p.id, sk.code) > 0), '{}'::text[]) as want
            from public.players p) z);
end $$;

create temp table proven_0150 (k text primary key, v jsonb) on commit drop;
insert into proven_0150 values ('dark', pg_temp.compare_0150()), ('scopes', pg_temp.scopes_check_0150());

-- LIT (skills_bite true inside a rolled-back subtransaction): the answers ride out in a variable
do $$
declare
  r jsonb;
begin
  begin
    update public.world_config set value = 'true'::jsonb where key = 'skills_bite';
    if not public.skills_bite_on() then
      raise exception '0150 self-assert FAIL: the lit comparison could not light skills_bite';
    end if;
    r := pg_temp.compare_0150();
    raise exception 'LIT_ROLLBACK_0150';
  exception when others then
    if sqlerrm <> 'LIT_ROLLBACK_0150' then raise; end if;
  end;
  insert into proven_0150 values ('lit', r);
end $$;

-- THE CONTROL: four throw-away companies, rolled back — dark and lit, old = new, and the bonuses that
-- must still apply do
create or replace function pg_temp.probe_0150()
returns jsonb
language plpgsql
as $$
declare
  v_a      uuid;   v_fa uuid;  v_nau uuid;
  v_b      uuid;   v_fb uuid;  v_sb  uuid;
  v_c      uuid;   v_sc uuid;
  v_d      uuid;   v_sd uuid;
  v_off    uuid;
  v_out    jsonb := '{}'::jsonb;
  v_phase  text;
  v_sight  numeric;
  v_look   numeric;
begin
  begin
    if public.skills_bite_on() then
      raise exception '0150 self-assert FAIL: skills_bite is on before the probe — this file ships it dark';
    end if;
    -- A: PRT Medium Hulls III (ship), Deck Management II (fitting), Command II (house), an officer, a nau
    v_a := public.new_house('00000000-0150-4000-8000-000000000001', 'Casa da Prova 0150 A', 'PRT');
    select id into v_fa from public.fleets where player_id = v_a;
    v_nau := public.commission_ship(v_a, v_fa, 'nau', 'Prova Nau 0150', false, true);
    insert into public.player_skills (player_id, skill_id, level)
    select v_a, sk.id, x.lvl
      from (values ('PRT_MEDIUM', 3), ('DECK_MANAGEMENT', 2), ('COMMAND', 2)) x(code, lvl)
      join public.skills sk on sk.code = x.code;
    select o.id into v_off from public.officers o where o.specialty = 'QUARTERMASTER' order by o.bonus_pct desc, o.code limit 1;
    insert into public.player_officers (player_id, officer_id, fleet_id) values (v_a, v_off, v_fa);
    -- B: its only ship skill a FINISHED queue entry (Lookouts I) — the queue half of the held set
    v_b := public.new_house('00000000-0150-4000-8000-000000000002', 'Casa da Prova 0150 B', 'PRT');
    select id into v_fb from public.fleets where player_id = v_b;
    select id into v_sb from public.ships where fleet_id = v_fb;
    insert into public.skill_queue (player_id, pos, skill_id, to_level, starts_at, finishes_at)
    select v_b, 1, sk.id, 1, now() - interval '2 hours', now() - interval '1 hour' from public.skills sk where sk.code = 'LOOKOUTS';
    -- C: its ship skill still TRAINING (Lookouts I, finishing tomorrow) — holds nothing yet
    v_c := public.new_house('00000000-0150-4000-8000-000000000003', 'Casa da Prova 0150 C', 'PRT');
    select id into v_sc from public.ships where player_id = v_c;
    insert into public.skill_queue (player_id, pos, skill_id, to_level, starts_at, finishes_at)
    select v_c, 1, sk.id, 1, now(), now() + interval '1 day' from public.skills sk where sk.code = 'LOOKOUTS';
    -- D: a PLAYER house holding only the four company skills — what every merchant holds
    v_d := public.new_house('00000000-0150-4000-8000-000000000004', 'Casa da Prova 0150 D', 'PRT');
    select id into v_sd from public.ships where player_id = v_d;
    insert into public.player_skills (player_id, skill_id, level)
    select v_d, sk.id, 3 from public.skills sk where sk.code in ('ACCOUNTING', 'HAGGLING', 'NAVIGATION', 'SEAMANSHIP');

    v_out := v_out || jsonb_build_object('scopes',
      jsonb_build_object('a', public.house_skill_scopes(v_a), 'b', public.house_skill_scopes(v_b),
                         'c', public.house_skill_scopes(v_c), 'd', public.house_skill_scopes(v_d)));
    foreach v_phase in array array['dark', 'lit'] loop
      if v_phase = 'lit' then
        update public.world_config set value = 'true'::jsonb where key = 'skills_bite';
      end if;
      v_out := v_out || jsonb_build_object(v_phase, jsonb_build_object(
        'nau_new',  world.ship_view(v_nau),  'nau_old',  pg_temp.world_ship_view_0150(v_nau),
        'nau_stats', world.ship_stats(v_nau), 'nau_budget', world.ship_budget(v_nau),
        'b_new',    world.ship_view(v_sb),   'b_old',    pg_temp.world_ship_view_0150(v_sb),
        'b_stats',  world.ship_stats(v_sb),
        'c_new',    world.ship_view(v_sc),   'c_old',    pg_temp.world_ship_view_0150(v_sc),
        'd_new',    world.ship_view(v_sd),   'd_old',    pg_temp.world_ship_view_0150(v_sd),
        'fleet_new', jsonb_build_array(voyage.fleet_speed(v_fa), public.fleet_officer_bonus(v_fa, 'QUARTERMASTER'),
                               world.skill_pct(v_a, null, 'officer_bonus'), world.skill_pct(v_a, v_nau, 'deck')),
        'fleet_old', jsonb_build_array(pg_temp.voyage_fleet_speed_0150(v_fa), pg_temp.public_fleet_officer_bonus_0150(v_fa, 'QUARTERMASTER'),
                               pg_temp.world_skill_pct_0150(v_a, null, 'officer_bonus'), pg_temp.world_skill_pct_0150(v_a, v_nau, 'deck')),
        'officer',  public.fleet_officer_bonus(v_fa, 'QUARTERMASTER'),
        'house_rows', (select count(*) from world.skill_bonuses(v_a, null))));
    end loop;
    -- what the nau's sighting must gain from PRT Medium Hulls III, read from the catalogue itself
    select coalesce(sum(e.pct_per_level * 3), 0) into v_sight
      from public.skill_effects e
      join public.ships s on s.id = v_nau
      join public.ship_classes c on c.id = s.class_id
      join public.class_profile cp on cp.class_code = c.code
     where e.skill_code = 'PRT_MEDIUM' and e.stat = 'sighting'
       and (e.line_code is null or e.line_code = cp.line_code) and (e.size is null or e.size = cp.size);
    select coalesce(sum(e.pct_per_level), 0) into v_look
      from public.skill_effects e where e.skill_code = 'LOOKOUTS' and e.stat = 'sighting' and e.scope = 'ship'
       and e.line_code is null and e.size is null and e.role is null and e.tech is null;
    v_out := v_out || jsonb_build_object('sight_pct', v_sight, 'look_pct', v_look,
                                         'officer_pct', (select bonus_pct from public.officers where id = v_off));
    raise exception 'PROBE_ROLLBACK_0150';
  exception when others then
    if sqlerrm <> 'PROBE_ROLLBACK_0150' then raise; end if;
  end;
  return v_out;
end $$;

create temp table probe_0150 (j jsonb) on commit drop;
do $$
declare
  v_try   int := 0;
  v_state text;
  v_msg   text;
begin
  loop
    v_try := v_try + 1;
    begin
      insert into probe_0150 select pg_temp.probe_0150();
      exit;
    exception when lock_not_available or deadlock_detected then
      get stacked diagnostics v_msg = message_text, v_state = returned_sqlstate;
    end;
    if v_try >= 5 then
      raise exception '0150 self-assert FAIL: LOCK CONTENTION, not a result — the probe could not get its locks in 5 tries (%: %). Re-run the push.',
        v_state, v_msg;
    end if;
    perform pg_sleep(0.2);
  end loop;
end $$;

-- ── 5. THE TIMING — REPORTED, NOT GATED (merchant hulls; old tree vs new; dark, then lit rolled back) ─
create temp table merchant_hulls_0150 on commit drop as
select s.id as ship_id from public.ships s join public.players p on p.id = s.player_id where p.is_npc;

create or replace function pg_temp.reads_now_0150()
returns jsonb
language plpgsql
as $$
declare
  v_t0 timestamptz;
  v    jsonb := '{}'::jsonb;
  w    text;
  v_ms numeric;
  k    text;
  t    text;
begin
  -- three passes, old and new INTERLEAVED in each (a noisy stretch of the CPU hits both trees alike),
  -- the fastest pass of each kept
  foreach w in array array['speed+hold', 'ship_stats', 'ship_view'] loop
    for i in 1 .. 3 loop
      foreach t in array array['old', 'new'] loop
        k := w || ' ' || t;
        v_t0 := clock_timestamp();
        case k
          when 'speed+hold old' then perform pg_temp.voyage_ship_speed_0150(h.ship_id), pg_temp.public_ship_hold_capacity_0150(h.ship_id) from merchant_hulls_0150 h;
          when 'speed+hold new' then perform voyage.ship_speed(h.ship_id), public.ship_hold_capacity(h.ship_id) from merchant_hulls_0150 h;
          when 'ship_stats old' then perform pg_temp.world_ship_stats_0150(h.ship_id) from merchant_hulls_0150 h;
          when 'ship_stats new' then perform world.ship_stats(h.ship_id) from merchant_hulls_0150 h;
          when 'ship_view old'  then perform pg_temp.world_ship_view_0150(h.ship_id) from merchant_hulls_0150 h;
          else                       perform world.ship_view(h.ship_id) from merchant_hulls_0150 h;
        end case;
        v_ms := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
        v := v || jsonb_build_object(k, least(coalesce((v->>k)::numeric, 1e12), v_ms));
      end loop;
    end loop;
  end loop;
  return v;
end $$;

create temp table timing_0150 (phase text primary key, t jsonb) on commit drop;
insert into timing_0150 values ('dark', pg_temp.reads_now_0150());
do $$
declare
  r jsonb;
begin
  begin
    update public.world_config set value = 'true'::jsonb where key = 'skills_bite';
    r := pg_temp.reads_now_0150();
    raise exception 'LIT_TIMING_ROLLBACK_0150';
  exception when others then
    if sqlerrm <> 'LIT_TIMING_ROLLBACK_0150' then raise; end if;
  end;
  insert into timing_0150 values ('lit', r);
end $$;

-- ── 6. SELF-ASSERT ─────────────────────────────────────────────────────────────────────────────
do $$
declare
  d       record;
  h       record;
  p       record;
  v_def   text;
  v_back  text;
  v_rev   int := 0;
  v_x     jsonb;
  v_ph    text;
  v_k     text;
  v_pr    jsonb := (select j from probe_0150);
  v_dark  jsonb := (select v from proven_0150 where k = 'dark');
  v_lit   jsonb := (select v from proven_0150 where k = 'lit');
  v_sc    jsonb := (select v from proven_0150 where k = 'scopes');
  v_td    jsonb := (select t from timing_0150 where phase = 'dark');
  v_tl    jsonb := (select t from timing_0150 where phase = 'lit');
  v_tim   text := '';
  w       text;
  v_nd    jsonb;
  v_nl    jsonb;
begin
  if public.skills_bite_on() then
    raise exception '0150 self-assert FAIL: skills_bite is on — this file never lights it';
  end if;

  -- (a) DARK AND LIT: every hull, fleet and house reads byte-equal old vs new (md5 over the whole set too)
  foreach v_ph in array array['dark', 'lit'] loop
    v_x := case v_ph when 'dark' then v_dark else v_lit end;
    if v_x is null then
      raise exception '0150 self-assert FAIL: the % comparison did not run', v_ph;
    end if;
    foreach v_k in array array['hulls', 'fleets', 'houses'] loop
      if coalesce((v_x->v_k->>'n')::int, 0) < 1 or (v_x->v_k->>'bad')::int <> 0
         or v_x->v_k->>'md5_new' is distinct from v_x->v_k->>'md5_old' then
        raise exception '0150 self-assert FAIL: % — % of % % differ from the pre-image (e.g. %; md5 new % old %)',
          v_ph, v_x->v_k->>'bad', v_x->v_k->>'n', v_k, v_x->v_k->>'ex', v_x->v_k->>'md5_new', v_x->v_k->>'md5_old';
      end if;
    end loop;
  end loop;
  if (v_dark->'hulls'->>'n')::int <> (select count(*) from public.ships)
     or (v_lit->'hulls'->>'n')::int <> (select count(*) from public.ships)
     or (v_dark->'houses'->>'n')::int <> (select count(*) from public.players) then
    raise exception '0150 self-assert FAIL: the comparison did not cover every hull and house (% / % hulls of %, % houses of %)',
      v_dark->'hulls'->>'n', v_lit->'hulls'->>'n', (select count(*) from public.ships), v_dark->'houses'->>'n', (select count(*) from public.players);
  end if;
  if (v_dark->'hulls'->>'bonus_rows')::int <> 0 then
    raise exception '0150 self-assert FAIL: a hull lists skill bonuses dark';
  end if;

  -- (b) every house's scopes = the scopes derived through public.skill_level
  if (v_sc->>'bad')::int <> 0 or (v_sc->>'n')::int <> (select count(*) from public.players)
     or (v_sc->>'ship_bad')::int <> 0 or (v_sc->>'ships')::int < 1 then
    raise exception '0150 self-assert FAIL: house_skill_scopes differs from the held skills'' scopes for % of % house(s) (e.g. %)',
      v_sc->>'bad', v_sc->>'n', v_sc->>'ex';
  end if;

  -- (c) THE CONTROL
  if coalesce(v_pr->'scopes'->'a' is distinct from '["fitting", "house", "ship"]'::jsonb
     or v_pr->'scopes'->'b' is distinct from '["ship"]'::jsonb
     or v_pr->'scopes'->'c' is distinct from '[]'::jsonb
     or v_pr->'scopes'->'d' is distinct from '[]'::jsonb, true) then
    raise exception '0150 self-assert FAIL: the probe houses'' scopes are not as planted: %', v_pr->'scopes';
  end if;
  foreach v_ph in array array['dark', 'lit'] loop
    v_x := v_pr->v_ph;
    if coalesce(v_x->'nau_new' is distinct from v_x->'nau_old' or v_x->'b_new' is distinct from v_x->'b_old'
       or v_x->'c_new' is distinct from v_x->'c_old' or v_x->'d_new' is distinct from v_x->'d_old'
       or v_x->>'fleet_new' is distinct from v_x->>'fleet_old', true) then
      raise exception '0150 self-assert FAIL: a probe house reads differently old vs new %: %', v_ph, v_x;
    end if;
  end loop;
  v_nd := v_pr->'dark';
  v_nl := v_pr->'lit';
  -- the exits still let every real bonus through: the nau gains its Medium Hulls III sighting, the
  -- Deck above dark, the officer × Command; the queued Lookouts I reads on B's hull; C and D read nothing
  if coalesce((v_pr->>'sight_pct')::numeric <= 0
     or (v_nl->'nau_stats'->>'sighting') <> round((v_nd->'nau_stats'->>'sighting')::numeric * (1 + (v_pr->>'sight_pct')::numeric / 100),
                                                   scale((v_nd->'nau_stats'->>'sighting')::numeric))::text
     or (v_nl->'nau_budget'->'deck'->>'max')::int <= (v_nd->'nau_budget'->'deck'->>'max')::int
     or (v_nl->>'officer')::numeric <= (v_nd->>'officer')::numeric
     or (v_nl->>'officer')::numeric <> least((v_pr->>'officer_pct')::numeric * 1.04, public.wc_num('officer_bonus_cap_pct')) / 100.0
     or (v_nl->>'house_rows')::int < 1 or (v_nd->>'house_rows')::int <> 0
     or (select count(*) from jsonb_array_elements(v_nl->'nau_new'->'bonuses') b
          where b->>'source' = 'Portuguese Medium Hulls III' and b->>'stat' = 'sighting') <> 1
     or (v_pr->>'look_pct')::numeric <= 0
     or (v_nl->'b_stats'->>'sighting') <> round((v_nd->'b_stats'->>'sighting')::numeric * (1 + (v_pr->>'look_pct')::numeric / 100),
                                                 scale((v_nd->'b_stats'->>'sighting')::numeric))::text
     or jsonb_array_length(v_nl->'b_new'->'bonuses') < 1
     or v_nl->'c_new'->'bonuses' is distinct from '[]'::jsonb
     or v_nl->'d_new'->'bonuses' is distinct from '[]'::jsonb
     or v_nd->'nau_new'->'bonuses' is distinct from '[]'::jsonb, true) then
    raise exception '0150 self-assert FAIL: an exit swallowed a real bonus (or a bonus read dark): sighting % → % (+%), deck % → %, officer % → %, B % → % (+%)',
      v_nd->'nau_stats'->>'sighting', v_nl->'nau_stats'->>'sighting', (v_pr->>'sight_pct') || '%',
      v_nd->'nau_budget'->'deck'->>'max', v_nl->'nau_budget'->'deck'->>'max', v_nd->>'officer', v_nl->>'officer',
      v_nd->'b_stats'->>'sighting', v_nl->'b_stats'->>'sighting', (v_pr->>'look_pct') || '%';
  end if;
  if exists (select 1 from public.players where auth_uid::text like '00000000-0150-4000-8000-00000000000%')
     or public.skills_bite_on() then
    raise exception '0150 self-assert FAIL: the probe world was not rolled back';
  end if;

  -- (d) THE RE-CUTS: each body reverses to its pre-image hunk by hunk; ACL / volatility / definer / config /
  --     parallel safety unmoved (skill_pct's language moves sql → plpgsql, as its hunk says); the
  --     untouched bodies untouched
  for d in select * from defs_before_0150 order by fn loop
    v_def  := replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '');
    v_back := v_def;
    for h in select * from hunks_0150 where fn = d.fn order by n desc loop
      if pg_temp.occurs_0150(v_back, h.new) <> 1 then
        raise exception '0150 self-assert FAIL: hunk % of % is not in the live body once', h.n, d.fn;
      end if;
      v_back := replace(v_back, h.new, h.old);
    end loop;
    if v_back is distinct from d.def then
      raise exception '0150 self-assert FAIL: % does not reverse to its pre-image', d.fn;
    end if;
    v_rev := v_rev + 1;
    select coalesce(pr.proacl::text, '') as acl, pr.provolatile as vol, pr.prosecdef as secdef,
           coalesce(pr.proconfig::text, '') as cfg, pr.proparallel as par, l.lanname as lang
      into p from pg_proc pr join pg_language l on l.oid = pr.prolang where pr.oid = d.fn::regprocedure;
    if p.acl <> d.acl or p.vol <> d.vol or p.secdef <> d.secdef or p.cfg <> d.cfg or p.par <> d.par or p.lang <> 'plpgsql' then
      raise exception '0150 self-assert FAIL: % changed its ACL, volatility, definer, config or parallel safety (or is not PL/pgSQL)', d.fn;
    end if;
  end loop;
  if v_rev <> 6 then
    raise exception '0150 self-assert FAIL: % bodies checked, not 6', v_rev;
  end if;
  for d in select * from untouched_before_0150 loop
    if replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '') <> d.def
       or coalesce((select pr.proacl::text from pg_proc pr where pr.oid = d.fn::regprocedure), '') <> d.acl then
      raise exception '0150 self-assert FAIL: % moved — it was to be left untouched', d.fn;
    end if;
  end loop;

  -- (e) the new reading: one new function, PL/pgSQL, STABLE, invoker, no SET, server-only, no is_npc;
  --     each of the five exits asks it (one authority); no new entry point
  if (select n_found from before_0150) <> 0
     or (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'house_skill_scopes') <> 1 then
    raise exception '0150 self-assert FAIL: public.house_skill_scopes is not one new function';
  end if;
  select l.lanname as lang, pr.provolatile as vol, pr.prosecdef as secdef, pr.proconfig as cfg, pr.prosrc as src
    into p from pg_proc pr join pg_language l on l.oid = pr.prolang
   where pr.oid = 'public.house_skill_scopes(uuid, uuid)'::regprocedure;
  if p.lang <> 'plpgsql' or p.vol <> 's' or p.secdef or p.cfg is not null or strpos(p.src, 'is_npc') > 0 then
    raise exception '0150 self-assert FAIL: public.house_skill_scopes is not a plain STABLE PL/pgSQL reading (lang %, vol %, definer %, config %)',
      p.lang, p.vol, p.secdef, p.cfg;
  end if;
  if has_function_privilege('anon', 'public.house_skill_scopes(uuid, uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.house_skill_scopes(uuid, uuid)', 'execute') then
    raise exception '0150 self-assert FAIL: public.house_skill_scopes is callable by a client';
  end if;
  for w in select unnest(array['world.skill_bonuses(uuid, uuid)', 'world.ship_stats(uuid)', 'world.ship_budget(uuid)', 'world.ship_view(uuid)',
                                'public.fleet_officer_bonus(uuid, text)']) loop
    if pg_temp.occurs_0150((select pr.prosrc from pg_proc pr where pr.oid = w::regprocedure), 'public.house_skill_scopes(') <> 1
       or strpos((select pr.prosrc from pg_proc pr where pr.oid = w::regprocedure), 'is_npc') > 0 then
      raise exception '0150 self-assert FAIL: % does not ask public.house_skill_scopes exactly once (or reads is_npc)', w;
    end if;
  end loop;
  if (select count(*) from pg_proc pr where pr.pronamespace <> pg_my_temp_schema() and strpos(pr.prosrc, 'house_skill_scopes(') > 0) <> 5 then
    raise exception '0150 self-assert FAIL: house_skill_scopes has a reader beyond the five exits';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> (select entry_points from before_0150) then
    raise exception '0150 self-assert FAIL: the client entry points moved (% → %)',
      (select entry_points from before_0150), (select count(*) from public.client_rpc_entry_points());
  end if;

  -- (f) THE TIMING (reported): K0's bound — merchant reads lit ≤ dark × 1.15 + 50 ms, new tree
  foreach w in array array['speed+hold', 'ship_stats', 'ship_view'] loop
    v_tim := v_tim || format('%s: dark %s → %s ms, lit %s → %s ms (old tree → new) — new lit %s ms vs the bound %s ms (new dark × 1.15 + 50): %s; ',
      w, v_td->>(w || ' old'), v_td->>(w || ' new'), v_tl->>(w || ' old'), v_tl->>(w || ' new'), v_tl->>(w || ' new'), round((v_td->>(w || ' new'))::numeric * 1.15 + 50, 1),
      case when (v_tl->>(w || ' new'))::numeric <= (v_td->>(w || ' new'))::numeric * 1.15 + 50
           then 'WITHIN the bound' else 'OVER the bound' end);
  end loop;

  raise notice '0150 self-assert ok: A MERCHANT PAYS NOTHING FOR SKILLS SHE CANNOT USE — skills_bite still false, every answer the pre-image. SAME ANSWERS (old tree vs new, one statement each), DARK: % hulls (stats, budget, view, speed, cargo space; md5 %), % fleets (speed, officer bonuses), % houses (Command per cent, house bonuses) — 0 differ. LIT (rolled back): % hulls (md5 %), % fleets, % houses — 0 differ. SCOPES: % houses, % of them with no ship / fitting / house skill, = the scopes derived through skill_level; % hulls name their owner''s. CONTROL (4 throw-away houses, rolled back): old = new dark and lit; lit, PRT Medium Hulls III → nau sighting % → % (+%), Deck Management II → Deck % → %, Command II → officer % → %; a finished queue entry (Lookouts I) → sighting % → %; still training and company-only houses list no bonus. BODIES: 6 reverse to their pre-images (skill_pct now PL/pgSQL), ACL / volatility / definer / config unmoved, 8 untouched; public.house_skill_scopes is THE reading (PL/pgSQL, invoker, no SET, server-only, read by the 5 exits only, no is_npc); no new entry point. TIMING over % merchant hulls (fastest of 3 interleaved passes, random_page_cost %; reported, not gated — RE-MEASURE ON PROD BEFORE THROWING skills_bite): %',
    v_dark->'hulls'->>'n', v_dark->'hulls'->>'md5_new', v_dark->'fleets'->>'n', v_dark->'houses'->>'n',
    v_lit->'hulls'->>'n', v_lit->'hulls'->>'md5_new', v_lit->'fleets'->>'n', v_lit->'houses'->>'n',
    v_sc->>'n', v_sc->>'empty', v_sc->>'ships',
    v_nd->'nau_stats'->>'sighting', v_nl->'nau_stats'->>'sighting', (v_pr->>'sight_pct') || '%',
    v_nd->'nau_budget'->'deck'->>'max', v_nl->'nau_budget'->'deck'->>'max', v_nd->>'officer', v_nl->>'officer',
    v_nd->'b_stats'->>'sighting', v_nl->'b_stats'->>'sighting',
    (select count(*) from merchant_hulls_0150), current_setting('random_page_cost'), v_tim;
end $$;
