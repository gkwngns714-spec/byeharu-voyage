-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- news: none (dark: nothing changes for a player until the owner lights it)
-- 0531 - WOODCUTTING  (the land's wood, on the land frame of 0455. Dark behind its own switch: land_wood_enabled, false)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, 2026-11-25 (R4): "dungeon raids, mining, woodcutting etc. can be done". docs/design/land-2026-11.md 4 (the frame), 5.8 (the market
--   guard), 6.3 (a job is a row); docs/design/captains-land-2026-11-25.md; docs/dev-log/2026-11-25-captain-works.md.
--
-- WHAT, AND ALL OF IT IS DATA (no function is made and no body is cut: the frame is 0455's, the switch 0461's public.land_skill_on):
--   level_skills, level_activities  Woodcutting (land, the long curve to 100, a gift every 5th level as Mining's, lit by land_wood_enabled) and what raises
--                                   it. The Levels card, the Land read, Send and public.land_actions_for read a land skill by these rows.
--   land_sites                      the woods of all 25 regions, a 15 s march as the mines.
--   land_actions                    31 jobs: the raw wood of the catalogue and what is tapped or burned from it (Timber, Bamboo, Rattan, Cork ... Aloeswood),
--                                   by the level each asks, done on the land of every region the good comes from. The rows are the generator's
--                                   (scripts/build-land-migration.mjs --wood; tests/land.data.spec.ts holds this file's block to it). No tool yet: an axe
--                                   would move the guard's pace.
--   captain_works                   Woodcutting's company skill, so a party's captain earns in it what a Collect books (0528) and 0534 may gather it.
-- THE MARKET GUARD (0457, 5.8 rule 2) is in the rows: at the fastest pace (Woodcutting 100, no tool, the crowd's full chance of a second unit) a
--   party-hour of a good is at most a hundredth of the least middling-harbour target of every region it comes from; re-proved below on the live rows.
-- NO COIN IS MADE: a haul is goods in Storage at a cost of 0, as Mining's.
-- DARK: a Send refuses E_NOT_IN_USE, the Land read serves no wood, the Levels card no Woodcutting, the expedition no wood.
-- ROWS: 2 skill rows, 25 sites, 31 jobs, 1 config row; lit, as Mining's presses. 0 rows a minute idle.
-- budget: no table, no job, no cron, no trigger.
-- LOCKS: INSERTs into catalogue tables and one UPDATE of a captain_works row, for well under a second.
-- ROLLBACK (forward, owner only): land_wood_enabled false (a party out on wood keeps its row; its Collect still books).
-- SELF-ASSERT: no function or knob moved; the rows exactly the generator's and Mining's and Smithing's untouched; every job's good raw and from somewhere
--   with woods; then a probe company, rolled back: dark not served and its Send refused; lit the guard for every job and every region on the live
--   port_goods; the first job of Lisbon. The market's day, the dice and other companies are asked nothing.
-- VERSION: 0531 (before 0534, whose gathering reads the works).
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
do $m$
declare
  c_hunked constant text[] := array[]::text[];
  c_new    constant text[] := array[]::text[];
  c_doors  constant text[] := array[]::text[];
  c_knobs  constant text[] := array['land_wood_enabled']::text[];
  v_t0        timestamptz := clock_timestamp();
  v_h         record;
  x           record;
  v_q         text;
  v_def       text;
  v_pre       text;
  v_n         int;
  v_fn_before text;
  v_meta      text;
  v_cfg_before text;
  v_lived     boolean := false;
  v_note      text := '';
  v_pl uuid; v_lis uuid; v_r record; v_act text; v_md5 text; v_t jsonb; v_c jsonb;
begin
  perform set_config('statement_timeout', '90s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from public.world_config where key = any (c_knobs)) or exists (select 1 from unnest(c_new) u(q) where to_regprocedure(u.q) is not null) then
    raise exception '0531 refuses: it has been applied once';
  end if;
  if exists (select 1 from unnest(c_hunked) u(q) where to_regprocedure(u.q) is null) or to_regprocedure('public.land_skill_on(text)') is null or to_regclass('public.captain_works') is null then
    raise exception '0531 refuses: a body it cuts or a reading it asks is not in this world';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
    into v_cfg_before from public.world_config c;
  select md5(string_agg(to_jsonb(a)::text, ',' order by a.code)) into v_md5 from public.land_actions a;

  -- ── 2. THE TABLES ──

  insert into public.level_skills (code, ord, word, kept, day_cap, side, curve, gift_every, lit_by)
  values ('woodcutting', (select max(s.ord) + 1 from public.level_skills s), 'Woodcutting', 'book', null, 'land', 'long', 5, 'land_wood_enabled');
  insert into public.level_activities (code, skill, ord, word, unit, xp, per, xp_knob, per_knob, most_xp, once, at_gain, voyage_nm)
  values ('cut', 'woodcutting', 1, 'A turn of work in the woods, by the job''s own experience', 'each', 1, 1, null, null, null, false, false, null);
  insert into public.land_sites (region_id, ground, march_seconds) select r.id, 'woods', 15 from public.regions r;
  create temp table wood_0531 (code text primary key, skill text, kind text, level int, seconds int, xp int, ground text, ord int) on commit drop;
  insert into wood_0531 (code, skill, kind, level, seconds, xp, ground, ord)
  values
      -- BEGIN wood generated by scripts/build-land-migration.mjs --wood (do not edit by hand)
      ('timber', 'woodcutting', 'gather', 1, 1285, 107, 'woods', 1),
      ('bamboo', 'woodcutting', 'gather', 1, 7780, 648, 'woods', 2),
      ('rattan', 'woodcutting', 'gather', 1, 330, 28, 'woods', 3),
      ('cork', 'woodcutting', 'gather', 5, 250, 21, 'woods', 4),
      ('mangrove-poles', 'woodcutting', 'gather', 8, 420, 35, 'woods', 5),
      ('rosin', 'woodcutting', 'gather', 10, 500, 50, 'woods', 6),
      ('potash', 'woodcutting', 'gather', 12, 460, 46, 'woods', 7),
      ('tar', 'woodcutting', 'gather', 15, 480, 48, 'woods', 8),
      ('pine-pitch', 'woodcutting', 'gather', 18, 465, 47, 'woods', 9),
      ('mangrove-bark', 'woodcutting', 'gather', 20, 560, 75, 'woods', 10),
      ('wattle-bark', 'woodcutting', 'gather', 22, 545, 73, 'woods', 11),
      ('live-oak', 'woodcutting', 'gather', 25, 350, 47, 'woods', 12),
      ('redwood', 'woodcutting', 'gather', 28, 560, 75, 'woods', 13),
      ('balsa-wood', 'woodcutting', 'gather', 30, 540, 90, 'woods', 14),
      ('stockholm-tar', 'woodcutting', 'gather', 33, 485, 81, 'woods', 15),
      ('cedar', 'woodcutting', 'gather', 35, 450, 75, 'woods', 16),
      ('teak', 'woodcutting', 'gather', 38, 445, 74, 'woods', 17),
      ('sappanwood', 'woodcutting', 'gather', 40, 475, 95, 'woods', 18),
      ('camwood', 'woodcutting', 'gather', 43, 435, 87, 'woods', 19),
      ('riga-mast', 'woodcutting', 'gather', 46, 285, 57, 'woods', 20),
      ('lignum-vitae', 'woodcutting', 'gather', 48, 435, 87, 'woods', 21),
      ('alerce-timber', 'woodcutting', 'gather', 50, 670, 179, 'woods', 22),
      ('huon-pine', 'woodcutting', 'gather', 53, 655, 175, 'woods', 23),
      ('naval-timber', 'woodcutting', 'gather', 56, 700, 187, 'woods', 24),
      ('logwood', 'woodcutting', 'gather', 60, 370, 123, 'woods', 25),
      ('brazilwood', 'woodcutting', 'gather', 63, 340, 113, 'woods', 26),
      ('ebony', 'woodcutting', 'gather', 66, 450, 150, 'woods', 27),
      ('mast-pine', 'woodcutting', 'gather', 70, 320, 128, 'woods', 28),
      ('kauri-timber', 'woodcutting', 'gather', 74, 745, 298, 'woods', 29),
      ('sandalwood', 'woodcutting', 'gather', 78, 735, 294, 'woods', 30),
      ('aloeswood', 'woodcutting', 'gather', 86, 440, 235, 'woods', 31)
      -- END wood generated by scripts/build-land-migration.mjs
  ;
  insert into public.land_actions (code, skill, kind, level, seconds, xp, ground, tool, ord, good_id)
  select x2.code, x2.skill, x2.kind, x2.level, x2.seconds, x2.xp, x2.ground, null, x2.ord, g.id from wood_0531 x2 join public.goods g on g.code = x2.code;
  update public.captain_works set skill = 'woodcutting' where code = 'woodcutting' and skill is null;

  -- ── 3. THE KNOBS ──
  insert into public.world_config (key, value, description) values
    ('land_wood_enabled', 'false'::jsonb, '0531: THE SWITCH (the owner''s). true (with land_enabled): Woodcutting is a land skill: its jobs are served and may be sent. false: no wood is served or sent.');

  -- ── 4. THE RULES ──

  foreach v_q in array c_new loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', v_q::regprocedure);
  end loop;
  foreach v_q in array c_doors loop
    execute format('grant execute on function %s to authenticated', v_q::regprocedure);
  end loop;

  -- ── 5. THE HUNKS (each OLD text once in the live body; each reverses) ──
  create temp table hunks_0531 (fn text, ord int, old text, new text) on commit drop;


  for v_h in select h.fn from hunks_0531 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    for x in select * from hunks_0531 h where h.fn = v_h.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
      if v_n <> 1 then
        raise exception '0531 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
      end if;
      v_def := replace(v_def, x.old, x.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_0531 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception '0531 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    if v_def <> v_pre then
      raise exception '0531 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
    end if;
  end loop;

  -- ── 6. SELF-ASSERT: the catalog, the grants, the knobs ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked || c_new) u(q)))) <> v_fn_before then
    raise exception '0531 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) is distinct from v_meta then
    raise exception '0531 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked body moved';
  end if;
  if exists (select 1 from unnest(c_new) u(q)
              where has_function_privilege('anon', u.q::regprocedure, 'execute') or has_function_privilege('service_role', u.q::regprocedure, 'execute')
                 or has_function_privilege('authenticated', u.q::regprocedure, 'execute') <> (u.q = any (c_doors)))
     or (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0531 self-assert FAIL: a new function is reachable by a client that should not reach it, or a client may write';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
        from public.world_config c where c.key <> all (c_knobs)) <> v_cfg_before then
    raise exception '0531 self-assert FAIL: a knob of another file moved';
  end if;
  if (select md5(string_agg(to_jsonb(a)::text, ',' order by a.code)) from public.land_actions a where a.skill <> 'woodcutting') is distinct from v_md5
     or (select count(*) from public.land_actions a join wood_0531 x2 on x2.code = a.code where (a.skill, a.kind, a.level, a.seconds, a.xp, a.ground, a.ord) = (x2.skill, x2.kind, x2.level, x2.seconds, x2.xp, x2.ground, x2.ord) and a.tool is null) <> 31
     or (select count(*) from wood_0531) <> 31
     or exists (select 1 from public.land_actions a join public.goods g on g.id = a.good_id where a.skill = 'woodcutting' and (not g.is_raw or coalesce(cardinality(g.origin_regions), 0) = 0))
     or (select count(*) from public.land_sites s where s.ground = 'woods') <> (select count(*) from public.regions) or (select w.skill from public.captain_works w where w.code = 'woodcutting') is distinct from 'woodcutting' then
    raise exception '0531 self-assert FAIL: the jobs are not exactly the generator''s 31 rows of raw goods, or another job moved';
  end if;

  -- ── 7. THE PROBE, rolled back by a raised sentinel (its own companies' rows) ──
  begin

    v_pl := public.new_house('00000000-0531-4000-8000-000000000001', 'Casa da Lenha 0531', 'PRT');
    perform cmd.assume_identity('00000000-0531-4000-8000-000000000001');
    select p.id into v_lis from public.ports p where p.code = 'LIS';
    update public.world_config set value = 'true'::jsonb where key in ('land_enabled', 'captain_works_enabled');
    -- DARK: not served, not sent, not on the Levels card
    select a.code into v_act from public.land_actions a join public.goods g on g.id = a.good_id where a.skill = 'woodcutting' and a.level = 1
       and (select rg.code from public.ports p join public.regions rg on rg.id = p.region_id where p.id = v_lis) = any(g.origin_regions) order by a.ord limit 1;
    if v_act is null or public.land_skill_on('woodcutting') or exists (select 1 from jsonb_array_elements_text(world.land('mining')->'skills') e where e = 'woodcutting')
       or cmd.land_send(v_act)->>'error_code' is distinct from 'E_NOT_IN_USE'
       or exists (select 1 from jsonb_array_elements(public.level_skills_card(v_pl, public.player_progress(v_pl))->'skills') e where e->>'code' = 'woodcutting') then
      raise exception '0531 self-assert FAIL: dark, wood is open (%)', v_act;
    end if;
    -- LIT: served, and THE GUARD for every job and every region at the fastest pace, on the live market rows
    update public.world_config set value = 'true'::jsonb where key = 'land_wood_enabled';
    perform public.land_party(v_pl);
    insert into public.level_xp (player_id, skill, xp, seq) values (v_pl, 'woodcutting', public.level_begins('woodcutting', 100)::int, 0);
    select z.code, z.region, z.share, z.per_hour, z.target, z.n, z.bad into v_r from (
      with pace as (
        select a.code, a.good_id, (t.j ->> 'a')::int as a, (t.j ->> 'have')::int as have, 3600.0 / (t.j ->> 'a')::int * (1 + public.wc_num('land_crowd_max') / 100) as per_hour
          from public.land_actions a cross join lateral (select public.land_terms(v_pl, a.code) as j offset 0) t where a.skill = 'woodcutting'),
      mid as (
        select g.id as good_id, rg.code as region,
               percentile_disc(0.5) within group (order by coalesce(pg.base_target, pg.stock_target) * least(1, coalesce((select (c.value #>> '{}')::numeric from public.world_config c where c.key = 'depth_m0'), 1))) as target
          from public.goods g cross join unnest(g.origin_regions) o(rc) join public.regions rg on rg.code = o.rc
          join public.ports p on p.region_id = rg.id and p.kind = 'HARBOUR' join public.port_goods pg on pg.port_id = p.id and pg.good_id = g.id
         where g.id in (select a.good_id from public.land_actions a where a.skill = 'woodcutting') group by g.id, rg.code)
      select pace.code, mid.region, pace.per_hour / (mid.target / 100.0) as share, pace.per_hour, mid.target, count(*) over () as n, bool_or(pace.have <> 100 or pace.a is null) over () as bad
        from pace join mid on mid.good_id = pace.good_id order by 3 desc, 1, 2 limit 1) z;
    if v_r.share > 1 or v_r.bad or v_r.n < 31 then
      raise exception '0531 self-assert FAIL: THE GUARD: % at % is % a party-hour against a hundredth of % (%x of it; % job-regions)', v_r.code, v_r.region, round(v_r.per_hour, 2), v_r.target, round(v_r.share, 3), v_r.n;
    end if;
    -- a trip of Lisbon's first wood, by the frame's own Send and Collect: goods home, experience booked to Woodcutting alone
    delete from public.level_xp x3 where x3.player_id = v_pl;
    v_t := public.land_terms(v_pl, v_act);
    perform public.land_send_for(v_pl, v_act, now());
    v_c := public.land_collect_for(v_pl, now() + make_interval(secs => (v_t->>'trip')::double precision + 1));
    if (v_c->>'xp')::int <> (v_t->>'p')::int * (v_t->>'xp')::int
       or coalesce((select x3.xp from public.level_xp x3 where x3.player_id = v_pl and x3.skill = 'woodcutting'), 0) < 1 or exists (select 1 from public.level_xp x3 where x3.player_id = v_pl and x3.skill = 'mining')
       or coalesce((select sum(ps.qty) from public.player_storage ps join public.goods g on g.id = ps.good_id where ps.player_id = v_pl and g.code = v_act), 0) < (v_t->>'p')::int then
      raise exception '0531 self-assert FAIL: a trip of % did not come home as its terms say: % / %', v_act, v_t, v_c;
    end if;
    v_note := format('%s job-regions, the tightest %s at %s (%s of the hundredth); Lisbon''s first wood %s, a trip %s s', v_r.n, v_r.code, v_r.region, round(v_r.share, 3), v_act, v_t->>'trip');
    raise exception using errcode = 'ZX531', message = 'PROBE_ROLLBACK_0531';
  exception when sqlstate 'ZX531' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0531 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.auth_uid::text like '00000000-0531-4000-8000-%') or public.wc('land_wood_enabled') is distinct from 'false'::jsonb then
    raise exception '0531 self-assert FAIL: the probe left something behind';
  end if;
  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0531 self-assert FAIL: the file took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0531 self-assert ok: WOODCUTTING (dark). 31 jobs, 25 woods, one skill; no function made or cut; no other knob moved; Mining and Smithing untouched; the market guard holds. Probe (rolled back) whole. % ms. %', round(extract(epoch from clock_timestamp() - v_t0) * 1000), v_note;
end $m$;
