-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0468 - EACH LEVEL OPENS SOMETHING  (dark: the owner's switch level_unlocks_enabled, false; lit, every Trading level from 2 to 20
--        opens one thing a company uses: a route, a ship in each fleet, a smaller fee at the yard, or (as today) a fleet)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE DESIGN: docs/design/playable-2026-11-22.md P2 ("each level opens something real"); docs/design/content-plan-2026-11.md 5.3 item 9
--   ("A benefit is a row in public.level_perks and one reading"); docs/LEVELS.md section 7; docs/dev-log/2026-11-22-level-unlocks.md.
--
-- WHY: Trading climbs fast (level 13 of 20 in a first hour, content plan 3.2) and, past its two fleet rungs (3 and 6, fleet_room_levels),
--   a Trading level pays Reputation and nothing a company can use. The seven levels raised by doing got their benefits in 0417; Trading,
--   Exploration and Combat got none ("Trading, Exploration and Combat get nothing new here", 0417).
--
-- ONE AUTHORITY, EXTENDED (no second one made):
--   - WHAT A LEVEL GIVES is public.level_perks (0417): a step is a row. This file adds 17 rows for Trading. public.level_perk stays the ONE
--     reading of what a benefit is worth to a company; public.level_benefits stays the ONE list the page, the arrival card and the goal
--     card read (it lists a Trading step only while lit).
--   - EACH STEP MULTIPLIES OR ADDS TO ONE FIGURE IN THE ONE FUNCTION THAT OWNS IT, so what a screen quotes and what a door does agree:
--       trade_routes  one more route at Trading 2, 7, 11, 15, 19   public.standing_route_max_for (0154: the one reading of a route cap; the
--                                                                  Routes level's route_room adds there the same way, 0417)
--       fleet_ships   one more ship in each fleet at 4, 9, 13, 17  public.fleet_room_caps (0321: the one ladder of ships a fleet; never above
--                                                                  fleet_ship_top, unchanged), so public.earned_caps and the house's hull cap follow
--       yard_fee      the yard's order fee 10 % less at 5, 8, 10,   public.hull_order_price (0465: the one price of an order; labour and the
--                     12, 14, 16, 18, 20 (80 % less at 20)         materials untouched: they are the Academy's and the market's figures)
--     and, unchanged, one more fleet at Trading 3 and 6 (fleet_room_levels, public.fleet_room_caps). So every Trading level from 2 to 20
--     opens exactly one thing (asserted).
--   - A HULL BY LEVEL WAS WEIGHED AND LEFT: hulls are opened by the Academy's hull skills (0135, public.requirements_unmet, the one rule of
--     a requirement); a Trading gate there would be a second ladder for the same doors, and would take hulls away from companies today.
--     A cheaper yard LABOUR was left for the same reason (docs/LEVELS.md 7: the yard's labour is a skill's figure). Every step here only adds.
-- WHICH LEVEL: a level counted from the record (Trading) is read at the level she was last PAID for and shown: public.house_level_marks
--   (0356), the level whose LEVEL_UP moment the arrival card announces. One primary-key probe, so a door, a yard read of many hulls and the
--   caps trigger pay nothing heavy; public.player_progress (the derived level, 15 to 60 ms) is not called by any of these. A company with no
--   mark row, and every merchant (who has none), reads level 1: no step. A mark rises when the client settles a crossing (cmd.level_up),
--   seconds after the read that shows it.
-- THE SWITCH level_unlocks_enabled (FALSE here). Dark: public.level_perk answers 0 for a Trading step, so every figure above is its
--   pre-image's, and public.level_benefits lists no Trading step, so every screen is as it was (asserted on a probe company at Trading 20).
--   level_perks_on (0417) false switches these off too, as every other step. Lighting is the owner's.
-- NOT CHANGED: any knob (standing_route_max, fleet_ship_base, fleet_ship_top, yard_order_fee_pct, fleet_room_levels), Trading's curve, the
--   seven book levels' steps and their reading (a book step reads public.level_xp exactly as before; one more probe of level_skills' key),
--   any price a merchant pays (a merchant has no mark), the sale, the buy, voyage.settle.
-- ROWS: none, dark or lit (17 rows of data here; no event: the LEVEL_UP moment is 0356's). -- budget: none (no table, no job, no cron, no
--   index, no fillfactor or autovacuum setting).
-- LOCKS: CREATE OR REPLACE x5 by hunks (level_perk, level_benefits, standing_route_max_for, fleet_room_caps, hull_order_price). TIME: a second.
--   BUDGET: statement_timeout 45 s, lock_timeout 5 s; fails above 30 s.
-- ROLLBACK (forward, owner only): QUICK, level_unlocks_enabled false (every figure is its pre-image's at once). A company that used a lit
--   step (a route or a ship past the dark cap) keeps it, and the caps' triggers refuse the next one until she is under the cap again: read
--   scripts/ops/harness/level-unlocks/after-0468.sql's `over` first. Full: a new migration reversing the five hunks (OLD texts below
--   verbatim), deleting the 17 rows and the knob.
-- SELF-ASSERT: each hunk once and reversing; no other function moved; the hunked bodies' grants, volatility, definer, search path, owner
--   unmoved; the knob false; the steps whole (every Trading level 2-20 opens one thing). THE PROBE (rolled back): a company at Trading 20 and
--   a merchant. DARK every hunked figure equals its pre-image's (copies in pg_temp) and the Trading list has no step; LIT her routes are the
--   pre-image's + 5, her ships a fleet least(top, pre-image + 4), an order's fee 80 % less with labour and materials equal, the list names
--   the 17 steps, a book level's reading is the pre-image's, a merchant reads 0 and a mark of 1 reads 0. Proof 171 plays the doors.
-- VERSION: 0468 = prod head 0467 + 1 (0469 is another builder's; this file reads none of its bodies).
-- news: none (dark: nothing changes for a player until the owner lights level_unlocks_enabled)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_hunked constant text[] := array['public.level_perk(uuid,text)', 'public.level_benefits(text,integer)', 'public.standing_route_max_for(uuid)',
                                    'public.fleet_room_caps(uuid)', 'public.hull_order_price(uuid,uuid,text)'];
  c_perks  constant text[] := array['trade_routes', 'fleet_ships', 'yard_fee'];
  c_uid    constant uuid := '00000000-0468-4000-8000-000000000001';
  v_t0        timestamptz := clock_timestamp();
  v_h         record;
  x           record;
  v_def       text;
  v_pre       text;
  v_n         int;
  v_fn_before text;
  v_meta      text;
  v_cfg_before text;
  v_lived     boolean := false;
  v_pl        uuid;
  v_npc       uuid;
  v_lis       uuid;
  v_old       jsonb;
  v_new       jsonb;
  v_top       int;
  v_note      text := '';
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from public.world_config c where c.key = 'level_unlocks_enabled')
     or exists (select 1 from public.level_perks k where k.perk = any(c_perks)) then
    raise exception '0468 refuses: it has been applied once';
  end if;
  if exists (select 1 from unnest(c_hunked) f where to_regprocedure(f) is null)
     or to_regclass('public.house_level_marks') is null or to_regprocedure('public.level_perk_at(text,integer)') is null
     or to_regprocedure('public.new_house(uuid,text,text,text,text,text,text,bigint,boolean)') is null
     or not exists (select 1 from public.level_skills s where s.code = 'trading' and s.kept = 'record')
     or public.wc('fleet_room_levels') is null or public.wc('yard_order_fee_pct') is null or public.wc('fleet_ship_top') is null then
    raise exception '0468 refuses: the levels (0411, 0417, 0453), the marks (0356), the room (0321) or the yard order (0465) is not in this world';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  create temp table pre_0468 (fn text primary key, def text) on commit drop;
  insert into pre_0468 select f, replace(pg_get_functiondef(f::regprocedure), E'\r', '') from unnest(c_hunked) f;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
    into v_cfg_before from public.world_config c;

  -- ── 2. THE SWITCH, THE STEPS ──
  insert into public.world_config (key, value, description) values
    ('level_unlocks_enabled', 'false'::jsonb,
     '0468: EACH LEVEL OPENS SOMETHING (the owner''s switch). true: the Trading steps of public.level_perks apply and are listed: one more route at Trading 2, 7, 11, 15, 19 (public.standing_route_max_for), one more ship in each fleet at 4, 9, 13, 17 (public.fleet_room_caps, never above fleet_ship_top), the yard''s order fee 10 % less at 5, 8, 10, 12, 14, 16, 18, 20 (public.hull_order_price); read at the level she was last paid for (public.house_level_marks). false: public.level_perk answers 0 for them and public.level_benefits lists none: every figure is what it was before 0468.');

  insert into public.level_perks (perk, level, skill, unit, amount, word)
  select st.perk, l.level, 'trading', st.unit, st.amount, st.word
    from (values
      ('trade_routes', 'count',    1,  array[2, 7, 11, 15, 19],             'One more route'),
      ('fleet_ships',  'count',    1,  array[4, 9, 13, 17],                 'One more ship in each fleet'),
      ('yard_fee',     'pct_less', 10, array[5, 8, 10, 12, 14, 16, 18, 20], 'The yard''s order fee is less')
    ) st(perk, unit, amount, levels, word)
    cross join lateral unnest(st.levels) l(level);

  -- ── 3. THE HUNKS (each OLD text once in its live body; each reverses) ──
  create temp table hunks_0468 (fn text, ord int, old text, new text, primary key (fn, ord)) on commit drop;
  insert into hunks_0468 values
  ('public.level_perk(uuid,text)', 1,
$h$  select k.skill into v_skill from public.level_perks k where k.perk = p_perk limit 1;
$h$,
$h$  select k.skill into v_skill from public.level_perks k where k.perk = p_perk limit 1;
  -- 0468: a step of a level counted from the record (Trading) is read at the level she was last paid for and shown (public.house_level_marks,
  -- the LEVEL_UP moment; one key probe), and only while level_unlocks_enabled. A merchant and a company with no mark: no step, 0.
  if exists (select 1 from public.level_skills s where s.code = v_skill and s.kept = 'record') then
    if public.wc('level_unlocks_enabled') is distinct from 'true'::jsonb then
      return 0;
    end if;
    return coalesce(public.level_perk_at(p_perk, (select m.level from public.house_level_marks m where m.player_id = p_player and m.track = v_skill)), 0);
  end if;
$h$),
  ('public.level_benefits(text,integer)', 1,
$h$       where k.skill = p_skill and public.wc('level_perks_on') = 'true'::jsonb
$h$,
$h$       where k.skill = p_skill and public.wc('level_perks_on') = 'true'::jsonb
         -- 0468: a step of a level counted from the record (Trading's unlocks) is listed only while level_unlocks_enabled
         and (public.wc('level_unlocks_enabled') = 'true'::jsonb
              or not exists (select 1 from public.level_skills s where s.code = p_skill and s.kept = 'record'))
$h$),
  ('public.standing_route_max_for(uuid)', 1,
$h$  v_max := v_max + public.level_perk(p_player, 'route_room')::int;   -- 0417: and the routes her Routes level gives
$h$,
$h$  v_max := v_max + public.level_perk(p_player, 'route_room')::int;   -- 0417: and the routes her Routes level gives
  v_max := v_max + public.level_perk(p_player, 'trade_routes')::int;   -- 0468: and the routes her Trading level opens (dark: 0)
$h$),
  ('public.fleet_room_caps(uuid)', 1,
$h$                              + greatest(public.skill_level(p_player, 'SEAMANSHIP'), public.skill_level(p_player, 'COMMAND'))
$h$,
$h$                              + greatest(public.skill_level(p_player, 'SEAMANSHIP'), public.skill_level(p_player, 'COMMAND'))
                              + public.level_perk(p_player, 'fleet_ships')::int   -- 0468: and the ships a fleet her Trading level opens (dark: 0)
$h$),
  ('public.hull_order_price(uuid,uuid,text)', 1,
$h$  v_fee := round((v_lab + v_mat) * public.wc_num('yard_order_fee_pct') / 100.0)::bigint;
$h$,
$h$  -- 0468: less the share her Trading level takes off the fee (public.level_perk; dark: 0). Labour and materials are untouched.
  v_fee := round((v_lab + v_mat) * public.wc_num('yard_order_fee_pct') / 100.0 * (1 - public.level_perk(p_player, 'yard_fee') / 100))::bigint;
$h$);

  for v_h in select h.fn from hunks_0468 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    for x in select * from hunks_0468 h where h.fn = v_h.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
      if v_n <> 1 then
        raise exception '0468 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
      end if;
      v_def := replace(v_def, x.old, x.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_0468 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception '0468 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    if v_def <> v_pre then
      raise exception '0468 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
    end if;
  end loop;

  -- ── 4. SELF-ASSERT: the catalog, the knob, the steps ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_fn_before then
    raise exception '0468 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0468 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked function moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
        from public.world_config c where c.key <> 'level_unlocks_enabled') <> v_cfg_before
     or public.wc('level_unlocks_enabled') is distinct from 'false'::jsonb then
    raise exception '0468 self-assert FAIL: an existing world_config row moved, or level_unlocks_enabled is not false';
  end if;
  -- every Trading level from 2 to 20 opens exactly one thing: a step of this file or a fleet rung (fleet_room_levels), never both
  v_top := least(20, public.level_from_points(1000000000000));
  if exists (select 1 from generate_series(2, v_top) g(l)
              where (select count(*) from public.level_perks k where k.skill = 'trading' and k.level = g.l)
                    + (select count(*) from jsonb_array_elements_text(public.wc('fleet_room_levels')) r where r.value::int = g.l) <> 1)
     or (select count(*) from public.level_perks k where k.skill = 'trading') <> 17
     or exists (select 1 from public.level_perks k where k.perk = any(c_perks) and k.skill <> 'trading')
     or exists (select 1 from public.level_perks k where k.skill = 'trading' and not (k.perk = any(c_perks)))
     or (select sum(k.amount) from public.level_perks k where k.perk = 'yard_fee') >= 100 then
    raise exception '0468 self-assert FAIL: the Trading steps are not one thing a level from 2 to %, or the fee falls to nothing', v_top;
  end if;
  if (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0468 self-assert FAIL: a client can write a table';
  end if;

  -- ── 5. THE PROBE, rolled back by a raised sentinel ──
  begin
    -- the pre-images, callable as pg_temp.*_old_0468 (their definer dropped: a copy in pg_temp runs as the migration)
    for x in select p.fn, p.def from pre_0468 p where p.fn <> 'public.level_benefits(text,integer)' loop
      execute replace(replace(replace(replace(replace(replace(x.def,
        'FUNCTION public.level_perk(', 'FUNCTION pg_temp.level_perk_old_0468('),
        'FUNCTION public.standing_route_max_for(', 'FUNCTION pg_temp.route_max_old_0468('),
        'FUNCTION public.fleet_room_caps(', 'FUNCTION pg_temp.room_caps_old_0468('),
        'FUNCTION public.hull_order_price(', 'FUNCTION pg_temp.order_price_old_0468('),
        ' SECURITY DEFINER', ''), 'SECURITY DEFINER', '');
    end loop;
    update public.world_config set value = 'true'::jsonb where key = 'level_perks_on' and value is distinct from 'true'::jsonb;
    select p.id into v_lis from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR';
    v_pl := public.new_house(c_uid, 'Casa dos Degraus 0468', 'PRT');
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
    values (null, 'Casa Mercante 0468', (select n.id from public.nations n where n.code = 'PRT'), 0, true) returning id into v_npc;
    -- she was paid for Trading 20; a book level (Supplies) at its top, to hold the book reading to its pre-image
    insert into public.house_level_marks (player_id, track, level) values (v_pl, 'trading', 20)
      on conflict (player_id, track) do update set level = excluded.level;
    insert into public.level_xp (player_id, skill, xp, seq) values (v_pl, 'supplies', public.level_points(20)::int, 0)
      on conflict do nothing;

    -- (a) DARK: every hunked figure is its pre-image's; the Trading list has no step
    if public.level_perk(v_pl, 'trade_routes') <> 0 or public.level_perk(v_pl, 'yard_fee') <> 0
       or public.standing_route_max_for(v_pl) <> pg_temp.route_max_old_0468(v_pl)
       or public.fleet_room_caps(v_pl) <> pg_temp.room_caps_old_0468(v_pl)
       or public.hull_order_price(v_pl, v_lis, 'barca') is distinct from pg_temp.order_price_old_0468(v_pl, v_lis, 'barca')
       or public.level_perk(v_pl, 'supplies_price') <> pg_temp.level_perk_old_0468(v_pl, 'supplies_price')
       or exists (select 1 from jsonb_array_elements(public.level_benefits('trading', 10)) b where b ->> 'kind' = 'perk') then
      raise exception '0468 self-assert FAIL: dark, a figure moved or the Trading list names a step';
    end if;

    -- (b) LIT
    update public.world_config set value = 'true'::jsonb where key = 'level_unlocks_enabled';
    if public.level_perk(v_pl, 'trade_routes') <> 5 or public.level_perk(v_pl, 'fleet_ships') <> 4 or public.level_perk(v_pl, 'yard_fee') <> 80
       or public.standing_route_max_for(v_pl) <> pg_temp.route_max_old_0468(v_pl) + 5
       or (public.fleet_room_caps(v_pl) ->> 'fleet_ship_max')::int
          <> least(public.wc_int('fleet_ship_top'), (pg_temp.room_caps_old_0468(v_pl) ->> 'fleet_ship_max')::int + 4)
       or (public.fleet_room_caps(v_pl) ->> 'fleet_max') <> (pg_temp.room_caps_old_0468(v_pl) ->> 'fleet_max')
       or public.level_perk(v_pl, 'supplies_price') <> pg_temp.level_perk_old_0468(v_pl, 'supplies_price')
       or public.level_perk(v_npc, 'trade_routes') <> 0 or public.standing_route_max_for(v_npc) <> pg_temp.route_max_old_0468(v_npc)
       or public.fleet_room_caps(v_npc) <> pg_temp.room_caps_old_0468(v_npc) then
      raise exception '0468 self-assert FAIL: lit, routes (% of %), ships a fleet (% of %) or a book or merchant reading are not the steps''',
        public.standing_route_max_for(v_pl), pg_temp.route_max_old_0468(v_pl), public.fleet_room_caps(v_pl), pg_temp.room_caps_old_0468(v_pl);
    end if;
    v_old := pg_temp.order_price_old_0468(v_pl, v_lis, 'barca');
    v_new := public.hull_order_price(v_pl, v_lis, 'barca');
    if v_old is null then
      v_note := 'the order''s fee was NOT RUN HERE (no barca price at Lisbon; proof 171 holds it)';
    elsif (v_new ->> 'labour') <> (v_old ->> 'labour') or (v_new ->> 'materials') <> (v_old ->> 'materials') or (v_new ->> 'minutes') <> (v_old ->> 'minutes')
       or (v_new ->> 'fee')::bigint <> round(((v_old ->> 'labour')::bigint + (v_old ->> 'materials')::bigint) * public.wc_num('yard_order_fee_pct') / 100.0 * 0.2)::bigint
       or (v_new ->> 'price')::bigint <> (v_new ->> 'labour')::bigint + (v_new ->> 'materials')::bigint + (v_new ->> 'fee')::bigint then
      raise exception '0468 self-assert FAIL: lit, the order of a barca is % against %', v_new, v_old;
    else
      v_note := format('a barca''s order fee %s -> %s', v_old ->> 'fee', v_new ->> 'fee');
    end if;
    -- the list names every Trading step at its level, with its running total; a book level's list is as dark
    if (select count(*) from jsonb_array_elements(public.level_benefits('trading', 10)) b where b ->> 'kind' = 'perk') <> 17
       or exists (select 1 from jsonb_array_elements(public.level_benefits('trading', 10)) b
                   where b ->> 'kind' = 'perk'
                     and (b ->> 'total')::numeric <> (select sum(k.amount) from public.level_perks k where k.perk = b ->> 'perk' and k.level <= (b ->> 'level')::int)) then
      raise exception '0468 self-assert FAIL: lit, the Trading list is not the steps';
    end if;
    -- a mark of 1 opens nothing; a mark of 2 opens the first route
    update public.house_level_marks set level = 1 where player_id = v_pl and track = 'trading';
    if public.level_perk(v_pl, 'trade_routes') <> 0 or public.standing_route_max_for(v_pl) <> pg_temp.route_max_old_0468(v_pl) then
      raise exception '0468 self-assert FAIL: a company paid for Trading 1 has a step';
    end if;
    update public.house_level_marks set level = 2 where player_id = v_pl and track = 'trading';
    if public.level_perk(v_pl, 'trade_routes') <> 1 or public.level_perk(v_pl, 'fleet_ships') <> 0 then
      raise exception '0468 self-assert FAIL: a company paid for Trading 2 has not exactly its route';
    end if;
    -- level_perks_on false switches the Trading steps off too
    update public.world_config set value = 'false'::jsonb where key = 'level_perks_on';
    if public.level_perk(v_pl, 'trade_routes') <> 0 then
      raise exception '0468 self-assert FAIL: with level_perks_on false a Trading step is still worth something';
    end if;
    raise exception using errcode = 'ZX468', message = 'PROBE_ROLLBACK_0468';
  exception when sqlstate 'ZX468' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0468 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.company_name like 'Casa % 0468' or p.auth_uid = c_uid)
     or public.wc('level_unlocks_enabled') is distinct from 'false'::jsonb
     or to_regprocedure('pg_temp.route_max_old_0468(uuid)') is not null
     or public.current_player_id() is not null then
    raise exception '0468 self-assert FAIL: the probe left something behind';
  end if;

  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0468 self-assert FAIL: the file took % (budget 30 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0468 self-assert ok: EACH LEVEL OPENS SOMETHING (dark). % hunks once each and reversing; grants and volatility unmoved; no other function or knob moved; level_unlocks_enabled false; 17 Trading steps, one thing at each Trading level 2-%. Probe (rolled back), a company paid for Trading 20 and a merchant: dark every figure its pre-image''s and no step listed; lit routes +5, ships a fleet +4 (within the top), %, 17 steps listed, a book level and a merchant as before; Trading 1 opens nothing, 2 its route; level_perks_on false: 0. % ms.',
    (select count(*) from hunks_0468), v_top, v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;
