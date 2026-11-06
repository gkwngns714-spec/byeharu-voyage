-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0332 — A PLAYER BUILDS THE CROWN'S SHIPS: the cargo ship and the navy ship, named where a player chooses a hull. LIVE
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- The owner, 2026-11-06: *"you need to make ships too, so that players can build these cargo and navy ships too."*
--
-- WHAT WAS ALREADY TRUE, read on prod at head 0330 and on 0331: a crown ship is a CLASS, and every class of hull already stands in public.hull_recipes.
-- cmd.do_build is one verb over that table with no list of hulls in it. So `qpinnace` (convoy_ship_class), `navire` (convoy_armed_class) and `galion` (navy_ship_class, 0331) could be
-- laid down before this file, at their line's yards, by a company with their skills, for their materials and labour. What was missing is that nothing says so:
-- a player sees a teal cargo ship on the chart, and nothing in the yard or the Codex tells him which of 103 hulls she is.
-- This file adds NO second shipyard path, no flag column, no class row, and it moves no number of ship_classes, hull_recipes or world_config.
--
-- ONE AUTHORITY: which class is a crown's ship is already held by three knobs, read by the jobs that lay the hulls. public.crown_classes reads those three and nothing else, so
-- the mark follows a knob the moment the owner turns it. A flag on ship_classes or class_profile would be a second copy of those knobs. Both cargo classes are named: the one sailing today and the armed one.
-- The served key is `crown`, 'CARGO' or 'NAVY', and is ABSENT on every other class, so all other rows of both reads are byte for byte what they were.
--
-- A PLAYER'S SUCH SHIP IS AN ORDINARY PLAYER SHIP: public.fleet_kind asks public.cargo_ships and public.navy_ships, never the class, so she answers COMPANY: her own fleet, wages, stores, repairs and dock fees, no city pays her,
-- she carries no crown funds, public.fleet_origin is null, public.attack_for refuses her E_HUMAN_TARGET, and the chart draws her as a player's. Proof 39 proves each of those through the real verb.
--
-- PRICE, GATE, PLACE: all unchanged, the existing rule. See docs/dev-log/2026-11-06-a-player-builds-the-crown-ships.md for prod's figures. Gold moves as every hull's does: public.pay_city, kind BUILD, company to the yard's city. Nothing minted.
-- A capital pays ship_classes.build_cost for a navy hull (BUILD_NAVY, 0331) because it brings no materials; a player pays the recipe's labour and brings them (0072's rule, a quarter of build_cost). Two payers, the same ladder.
-- NO SWITCH: nothing a player could not already do is opened, so there is no balance change to hold back. Measured in the dev-log: `navire` is 27th of 103 on hold per ducat, `galion` 22nd on attack per ducat.
--
-- THE RE-CUTS (hunks of the live bodies, read on prod at head 0330; 0331 cuts neither), each occurs once and reverses to its pre-image; these supersede the same lines of 0135's world.snapshot and 0184's world.building_yard:
--   world.snapshot (2):        each ship class says `crown`, for the Codex.
--   world.building_yard (2):   each hull says `crown`, for the yard.
--
-- NEW: public.crown_classes.
--
-- SELF-ASSERT: the catalog and stable reads only: hunks once and reversing; ACL, volatility and config unmoved; no other function, knob, class or recipe moved; the mark is the knobs' and nobody else's; no row written.
-- THIS FILE RUNS NO GAME STEP, in every environment (docs/OPS_HEALTH.md section 4). THE LIVE PATHS ARE PROVED IN CI: proof 39, scripts/db/proofs/39_a_player_builds_the_crown_ships.sql. Mutation controls: scripts/ops/harness/crown-ships/proof-0332.mjs (local).
--
-- BUDGET (docs/OPS_HEALTH.md section 4): ONE DO block, statement_timeout 45 s, lock_timeout 5 s first. Self-assert fails above 45 s.
-- ROLLBACK (forward, a NEW migration): reverse the four hunks and drop the function. No row, ship or gold depends on it; an unmarked hull is what every hull was.
-- VERSION: 0332 - follows W12, 0331 (#537), which is deployed first: it reads navy_ship_class.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0   timestamptz := clock_timestamp();
  v_h    record;
  v_def  text;
  v_pre  text;
  v_n    int;
  v_want text;
  v_fn_before     text;
  v_cfg_before    text;
  v_meta_before   text;
  v_class_before  text;
  c_new_fn constant text := 'public.crown_classes()';
  c_hunked constant text[] := array['world.snapshot()', 'world.building_yard(uuid)'];
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regprocedure(c_new_fn) is not null then
    raise exception '0332 refuses: something of it is already in this world';
  end if;
  if (select count(*) from public.world_config c where c.key in ('convoy_ship_class', 'convoy_armed_class', 'navy_ship_class')) <> 3 then
    raise exception '0332 refuses: 0308 / 0328 / 0331 (the three knobs that name a crown ship) are not in this world';
  end if;
  if exists (select 1 from public.world_config c where c.key in ('convoy_ship_class', 'convoy_armed_class', 'navy_ship_class')
              and not exists (select 1 from public.hull_recipes h where h.class_code = c.value #>> '{}')) then
    raise exception '0332 refuses: a crown class has no hull recipe, so no yard lays her down and this file would name a ship nobody can build';
  end if;

  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_hunked) x));
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before
    from public.world_config c;
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, ''), ',' order by p.oid::regprocedure::text))
    into v_meta_before
    from pg_proc p where p.oid::regprocedure::text = any (array(select x::regprocedure::text from unnest(c_hunked) x));
  select md5((select string_agg(to_jsonb(c)::text, '|' order by c.code) from public.ship_classes c) || (select string_agg(to_jsonb(h)::text, '|' order by h.class_code) from public.hull_recipes h))
    into v_class_before;

  -- ── 1. THE ONE READER ──
  execute $f$
create function public.crown_classes()
returns table (class_code text, crown text)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0332: WHICH HULLS ARE A CROWN'S SHIPS: the classes the three knobs name, and nothing else. One row a class; a class named twice is the navy's. A label for the yard and the Codex: no rule reads it.
  select distinct on (k.code) k.code, k.crown
    from (values (public.wc_text('navy_ship_class'), 'NAVY', 1),
                 (public.wc_text('convoy_ship_class'), 'CARGO', 2),
                 (public.wc_text('convoy_armed_class'), 'CARGO', 3)) k(code, crown, ord)
   where k.code is not null
   order by k.code, k.ord
$$
  $f$;
  revoke all on function public.crown_classes() from public, anon, authenticated;

  -- ── 2. THE RE-CUTS ──
  create temporary table hunks_0332 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0332 (fn, ord, old, new) values
  ('world.snapshot()', 1,
$h$        || jsonb_build_object('size', cp.size, 'role', cp.role, 'tech', cp.tech)     -- 0135: the Codex grid's filters
$h$,
$h$        || jsonb_build_object('size', cp.size, 'role', cp.role, 'tech', cp.tech)     -- 0135: the Codex grid's filters
        || case when cu.crown is null then '{}'::jsonb else jsonb_build_object('crown', cu.crown) end   -- 0332: a crown's ship says so, for the Codex; no other class has the key
$h$),
  ('world.snapshot()', 2,
$h$      left join public.ship_lines sl on sl.code = cp.line_code),
$h$,
$h$      left join public.ship_lines sl on sl.code = cp.line_code
      left join public.crown_classes() cu on cu.class_code = c.code),
$h$),
  ('world.building_yard(uuid)', 1,
$h$        -- 0165: a famous ship the company keeps already says so (public.famous_held), only then
$h$,
$h$        -- 0332: a crown's ship says so; no other hull has the key
        || case when cu.crown is null then '{}'::jsonb else jsonb_build_object('crown', cu.crown) end
        -- 0165: a famous ship the company keeps already says so (public.famous_held), only then
$h$),
  ('world.building_yard(uuid)', 2,
$h$      left join public.ship_lines sl on sl.code = cp.line_code         -- 0130
$h$,
$h$      left join public.ship_lines sl on sl.code = cp.line_code         -- 0130
      left join public.crown_classes() cu on cu.class_code = c.code    -- 0332
$h$);

  for v_h in select h.fn from hunks_0332 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    declare
      x record;
    begin
      for x in select * from hunks_0332 h where h.fn = v_h.fn order by h.ord loop
        v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
        if v_n <> 1 then
          raise exception '0332 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
        end if;
        v_def := replace(v_def, x.old, x.new);
      end loop;
      execute v_def;
      v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
      for x in select * from hunks_0332 h where h.fn = v_h.fn order by h.ord desc loop
        v_n := (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new);
        if v_n <> 1 then
          raise exception '0332 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
        end if;
        v_def := replace(v_def, x.new, x.old);
      end loop;
      if v_def <> v_pre then
        raise exception '0332 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
      end if;
    end;
  end loop;

  -- ── 3. THE SELF-ASSERT: the catalog and stable reads. No game step, no row. ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_hunked || c_new_fn) x))) <> v_fn_before then
    raise exception '0332 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) from public.world_config c) <> v_cfg_before then
    raise exception '0332 self-assert FAIL: a world_config row moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid::regprocedure::text = any (array(select x::regprocedure::text from unnest(c_hunked) x))) <> v_meta_before then
    raise exception '0332 self-assert FAIL: the ACL, volatility, definer or config of a hunked function moved';
  end if;
  if md5((select string_agg(to_jsonb(c)::text, '|' order by c.code) from public.ship_classes c) || (select string_agg(to_jsonb(h)::text, '|' order by h.class_code) from public.hull_recipes h)) <> v_class_before then
    raise exception '0332 self-assert FAIL: a class or recipe moved';
  end if;
  if (select p.provolatile from pg_proc p where p.oid = c_new_fn::regprocedure) <> 's' then
    raise exception '0332 self-assert FAIL: public.crown_classes is not stable';
  end if;
  if has_function_privilege('anon', c_new_fn::regprocedure, 'execute') or has_function_privilege('authenticated', c_new_fn::regprocedure, 'execute') then
    raise exception '0332 self-assert FAIL: public.crown_classes can be called from a client';
  end if;

  -- The mark is the knobs', and every read says the same: table-driven over every served class, so a hull marked by any other route is caught.
  select string_agg(k.value #>> '{}', ',' order by k.value #>> '{}') into v_want
    from public.world_config k where k.key in ('convoy_ship_class', 'convoy_armed_class', 'navy_ship_class');
  if (select string_agg(c.class_code, ',' order by c.class_code) from public.crown_classes() c) is distinct from v_want then
    raise exception '0332 self-assert FAIL: public.crown_classes is not the three knobs';
  end if;
  if (select string_agg(s ->> 'code', ',' order by s ->> 'code') from jsonb_array_elements(world.snapshot() -> 'ship_classes') s where s ? 'crown') is distinct from v_want
     or exists (select 1 from jsonb_array_elements(world.snapshot() -> 'ship_classes') s join public.crown_classes() c on c.class_code = s ->> 'code' where s ->> 'crown' <> c.crown) then
    raise exception '0332 self-assert FAIL: the snapshot does not serve the mark on exactly those classes';
  end if;
  if (select string_agg(s ->> 'class', ',' order by s ->> 'class')
        from jsonb_array_elements(world.building_yard((select b.port_id from public.port_buildings b where b.kind = 'building_yard' order by b.port_id limit 1)) -> 'hulls') s where s ? 'crown') is distinct from v_want then
    raise exception '0332 self-assert FAIL: the yard does not serve the mark on exactly those classes';
  end if;

  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0332 self-assert FAIL: the self-assert took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0332 self-assert ok: A PLAYER BUILDS THE CROWN''S SHIPS: % named from their knobs on both reads. % hunks once each and reversing; no other function, knob, class or recipe; no row written; no game step ran (proof 39 runs them in CI). % ms.',
    v_want, (select count(*) from hunks_0332), round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0332;
end
$m$;
