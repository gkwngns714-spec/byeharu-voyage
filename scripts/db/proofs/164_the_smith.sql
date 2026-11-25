-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 164 - THE SMITH  (migration 0461; docs/design/land-2026-11.md 8 L2, 6.3, 5.8; docs/dev-log/2026-11-20-land-l2.md)
--   Smithing is the land's first MAKING skill: rows in the one skill frame, settled by the one writer, taking its inputs through the
--   Forge's one take. Behind its own switch, land_smith_enabled. Everything rolls back (proof.mjs).
--
-- @pass SMITH_DARK       the land lit and Smithing dark: no Smithing on the Levels card, world.land serves `skills` ["mining"] and answers Smithing as no skill, a smith's Send refuses E_NOT_IN_USE and writes nothing
-- @pass SMITH_GUARD      every make job at Smithing 100 (no tool, no company): a party-hour of its good is at most a hundredth of the least middling-harbour target over every region; and the check bites (Iron Bars at 40 s is over)
-- @pass MINING_GUARD_L2  Mining's guard with the best tool L2 can make: L2 makes none, the plain pick (3 %) is still the fastest tool, and every Mining job-region at Mining 100 with the crowd's full chance is at most a hundredth
-- @pass SMITH_FORGE_SAME the Forge makes Iron Bars from the same goods at the same cost the smith books (one take, public.forge_take), and refuses a short recipe with the same code and sentence as before
-- @pass SMITH_RUN        a smith's Send takes the inputs of every unit it can make; a unit a turn is booked at its inputs' cost; the experience is Smithing's (activity smith); called home it gives back the rest at the cost it was taken at
-- @pass SMITH_SHORT      no inputs: the Send says E_NO_MATERIALS and names what is short, in the Forge's own words; too low a level: E_NEEDS_SKILL "needs Smithing 10"
-- @pass SMITH_XP_SKILL   Mining experience still due when a smith's job is sent is booked first under Mining (dig), never as Smithing's
-- @pass SMITH_NO_COMPANY a smith at home is nobody's company: a miner of the same harbour gets no second-unit chance from it, and the smith is not on the site's list
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

create function pg_temp.guard_164(p_player uuid)
returns table (code text, kind text, region text, per_hour numeric, target numeric, share numeric)
language sql
as $f$
  with pace as (
    select a.code, a.kind, a.good_id,
           3600.0 / (public.land_terms(p_player, a.code) ->> 'a')::int
             * (1 + (case when a.kind = 'make' then 0 else public.wc_num('land_crowd_max') end) / 100) as per_hour
      from public.land_actions a),
  mid as (
    select g.id as good_id, rg.code as region,
           percentile_disc(0.5) within group (order by coalesce(pg.base_target, pg.stock_target) * least(1, coalesce((select (c.value #>> '{}')::numeric from public.world_config c where c.key = 'depth_m0'), 1))) as target
      from public.goods g
      cross join public.regions rg
      join public.ports p on p.region_id = rg.id and p.kind = 'HARBOUR'
      join public.port_goods pg on pg.port_id = p.id and pg.good_id = g.id
     where g.id in (select a.good_id from public.land_actions a)
       and (rg.code = any(g.origin_regions) or g.id in (select a.good_id from public.land_actions a where a.kind = 'make'))
     group by g.id, rg.code)
  select pace.code, pace.kind, mid.region, pace.per_hour, mid.target, pace.per_hour / (mid.target / 100.0)
    from pace join mid on mid.good_id = pace.good_id
$f$;

do $p$
declare
  c_t    constant timestamptz := '2026-01-05 00:00:00+00';
  v_lis  uuid := (select p.id from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR');
  v_iron uuid := (select g.id from public.goods g where g.code = 'iron');
  v_coal uuid := (select g.id from public.goods g where g.code = 'coal');
  v_bars uuid := (select g.id from public.goods g where g.code = 'iron-bars');
  v_pl   uuid;
  v_top  uuid;
  v_fg   uuid;
  v_mn   uuid;
  v_party uuid;
  v_r    jsonb;
  v_s    jsonb;
  v_q    record;
  v_n    int;
  v_a    int;
  v_x    numeric;
  v_fmsg text;
begin
  update public.world_config set value = to_jsonb('0461-fixed-dice-of-proof-164-the-smith-0000000000000000000000000000'::text) where key = 'world_secret';
  update public.world_config set value = 'true'::jsonb where key in ('land_enabled', 'level_skills_on');   -- the land lit, as on production
  v_pl  := public.new_house('00000000-0461-4000-8000-0000000164c1', 'Casa Ferreira 164', 'PRT', 'LIS', 'Ferreira 164', 'carlat', 'Ferreira 164', null, false);
  v_top := public.new_house('00000000-0461-4000-8000-0000000164c2', 'Casa Mestre 164', 'PRT', 'LIS', 'Mestre 164', 'carlat', 'Mestre 164', null, false);
  v_fg  := public.new_house('00000000-0461-4000-8000-0000000164c3', 'Casa Forja 164', 'PRT', 'LIS', 'Forja 164', 'carlat', 'Forja 164', null, false);
  v_mn  := public.new_house('00000000-0461-4000-8000-0000000164c4', 'Casa Mina 164', 'PRT', 'LIS', 'Mina 164', 'carlat', 'Mina 164', null, false);
  if public.home_port_of(v_pl) <> v_lis or public.home_port_of(v_fg) <> v_lis or public.wc('land_smith_enabled') <> 'false'::jsonb then
    raise exception 'proof 164: the probe companies are not of Lisbon, or Smithing is lit as shipped';
  end if;

  -- ── DARK ──
  perform cmd.assume_identity('00000000-0461-4000-8000-0000000164c1');
  perform public.storage_put(v_pl, v_lis, v_iron, 12, 50);
  perform public.storage_put(v_pl, v_lis, v_coal, 6, 20);
  v_r := cmd.land_send('iron-bars');
  if v_r ->> 'error_code' <> 'E_NOT_IN_USE' or world.land('mining') -> 'skills' <> '["mining"]'::jsonb
     or world.land('smithing') <> '{"enabled": true, "company": false}'::jsonb
     or exists (select 1 from jsonb_array_elements(world.levels() -> 'level_skills' -> 'skills') s where s ->> 'code' = 'smithing')
     or not exists (select 1 from jsonb_array_elements(world.levels() -> 'level_skills' -> 'skills') s where s ->> 'code' = 'mining')
     or (select ps.qty from public.player_storage ps where ps.player_id = v_pl and ps.port_id = v_lis and ps.good_id = v_iron) <> 12
     or exists (select 1 from public.land_parties lp where lp.player_id = v_pl and lp.action is not null) then
    raise exception 'proof 164 SMITH_DARK: Smithing showed or its Send opened while dark: %', v_r;
  end if;
  raise notice 'PASS: SMITH_DARK - land lit, Smithing dark: Send %, skills %, Smithing not on the Levels card, 12 Iron still in Storage', v_r ->> 'error_code', world.land('mining') -> 'skills';
  update public.world_config set value = 'true'::jsonb where key = 'land_smith_enabled';

  -- ── THE GUARD: every make job, and Mining's with the best tool there is ──
  insert into public.level_xp (player_id, skill, xp, seq) values (v_top, 'smithing', public.level_begins('smithing', 100)::int, 0), (v_top, 'mining', public.level_begins('mining', 100)::int, 0)
    on conflict (player_id, skill) do update set xp = excluded.xp;
  insert into public.land_parties (player_id, port_id, tools) values (v_top, v_lis, (select array_agg(t.code) from public.land_tools t));
  select count(*), count(distinct g.code) into v_n, v_x from pg_temp.guard_164(v_top) g where g.kind = 'make';
  select g.* into v_q from pg_temp.guard_164(v_top) g where g.kind = 'make' order by g.share desc, g.code, g.region limit 1;
  if v_x <> 21 or v_n <> 21 * 25 or v_q.share > 1 or (public.land_terms(v_top, 'iron-bars') ->> 'have')::int <> 100
     or (public.land_terms(v_top, 'iron-bars') ->> 'tool')::numeric <> 0 or (public.land_terms(v_top, 'iron-bars') ->> 'crowd')::numeric <> 0 then
    raise exception 'proof 164 SMITH_GUARD: % at % is % a party-hour against a hundredth of % (% x), or a make job has no region (% of %)', v_q.code, v_q.region, round(v_q.per_hour, 3), v_q.target, round(v_q.share, 4), v_n, v_x;
  end if;
  v_x := (select a.seconds from public.land_actions a where a.code = 'iron-bars');
  update public.land_actions set seconds = 40 where code = 'iron-bars';
  if (select max(g.share) from pg_temp.guard_164(v_top) g where g.code = 'iron-bars') <= 1 then
    raise exception 'proof 164 SMITH_GUARD: Iron Bars at 40 s passed the guard';
  end if;
  raise notice 'PASS: SMITH_GUARD - % make job-regions over 21 jobs, the tightest % at %: % a party-hour, % of the hundredth of %; Iron Bars at 40 s would be % x',
    v_n, v_q.code, v_q.region, round(v_q.per_hour, 3), round(v_q.share, 4), v_q.target,
    round((select max(g.share) from pg_temp.guard_164(v_top) g where g.code = 'iron-bars'), 1);
  update public.land_actions a set seconds = v_x where a.code = 'iron-bars';

  select count(*) into v_n from pg_temp.guard_164(v_top) g where g.kind = 'gather';
  select g.* into v_q from pg_temp.guard_164(v_top) g where g.kind = 'gather' order by g.share desc, g.code, g.region limit 1;
  if (select max(t.speed_pct) from public.land_tools t) <> 3 or (select count(*) from public.land_tools) <> 1
     or (public.land_terms(v_top, 'iron') ->> 'tool')::numeric <> 3 or (public.land_terms(v_top, 'iron') ->> 'have')::int <> 100
     or v_q.share > 1 or (select count(distinct g.code) from pg_temp.guard_164(v_top) g where g.kind = 'gather') <> (select count(*) from public.land_actions a where a.kind = 'gather') then
    raise exception 'proof 164 MINING_GUARD_L2: % at % is % x the hundredth, or a tool faster than the plain pick exists', v_q.code, v_q.region, round(v_q.share, 4);
  end if;
  raise notice 'PASS: MINING_GUARD_L2 - L2 makes no tool: the plain pick (3 %%) is the best; % Mining job-regions at Mining 100 with it and the crowd, the tightest % at % (% of the hundredth)',
    v_n, v_q.code, v_q.region, round(v_q.share, 4);

  -- ── THE FORGE AND THE SMITH: one take, one cost ──
  perform cmd.assume_identity('00000000-0461-4000-8000-0000000164c3');
  perform public.storage_put(v_fg, v_lis, v_iron, 12, 50);
  perform public.storage_put(v_fg, v_lis, v_coal, 6, 20);
  v_r := cmd.forge_good(v_lis, v_bars, 6);
  v_s := cmd.forge_good(v_lis, v_bars, 1);
  if (v_r ->> 'ok')::boolean is not true or (v_r ->> 'qty')::int <> 6 or v_r -> 'spent' <> '[{"qty": 6, "good": "coal"}, {"qty": 12, "good": "iron"}]'::jsonb
     or (select ps.basis from public.player_storage ps where ps.player_id = v_fg and ps.port_id = v_lis and ps.good_id = v_bars) <> 40
     or v_s ->> 'error_code' <> 'E_NO_MATERIALS' or v_s ->> 'error_message' not like '%the forge is short of Iron (0%' then
    raise exception 'proof 164 SMITH_FORGE_SAME: the Forge is not the Forge: % then %', v_r, v_s;
  end if;
  perform cmd.assume_identity('00000000-0461-4000-8000-0000000164c1');
  v_r := public.land_send_for(v_pl, 'iron-bars', c_t);
  select lp.id into v_party from public.land_parties lp where lp.player_id = v_pl;
  if (select (lp.terms ->> 'basis')::numeric from public.land_parties lp where lp.id = v_party) <> 40 then
    raise exception 'proof 164 SMITH_FORGE_SAME: the smith''s cost is not the Forge''s 40: %', (select lp.terms from public.land_parties lp where lp.id = v_party);
  end if;
  raise notice 'PASS: SMITH_FORGE_SAME - 12 Iron at 50 and 6 Sea Coal at 20: the Forge makes 6 Iron Bars at 40, the smith''s Send freezes 40; short, the Forge says E_NO_MATERIALS "%"', v_s ->> 'error_message';

  -- ── THE SMITH'S RUN ──
  v_a := (select (lp.terms ->> 'a')::int from public.land_parties lp where lp.id = v_party);
  if (select (lp.terms ->> 'last')::int from public.land_parties lp where lp.id = v_party) <> 6 or v_a <> 24940
     or exists (select 1 from public.player_storage ps where ps.player_id = v_pl and ps.port_id = v_lis and ps.good_id in (v_iron, v_coal))
     or (public.land_progress(v_party, c_t + make_interval(secs => v_a - 1)) ->> 'turns')::int <> 0
     or (public.land_progress(v_party, c_t + make_interval(secs => v_a)) ->> 'turns')::int <> 1
     or (public.land_progress(v_party, c_t + make_interval(secs => v_a)) ->> 'phase') <> 'digging' then
    raise exception 'proof 164 SMITH_RUN: the Send did not take the inputs of six, or a turn is not one bar: %', (select lp.terms from public.land_parties lp where lp.id = v_party);
  end if;
  v_r := public.land_collect_for(v_pl, c_t + make_interval(secs => v_a));
  v_n := (public.land_collect_for(v_pl, c_t + make_interval(secs => 2 * v_a)) ->> 'units')::int;
  v_s := public.land_collect_for(v_pl, c_t + make_interval(secs => 3 * v_a));
  if (v_r ->> 'units')::int <> 1 or v_n <> 1 or (v_s ->> 'units')::int <> 1
     or (select ps.qty from public.player_storage ps where ps.player_id = v_pl and ps.port_id = v_lis and ps.good_id = v_bars) <> 3
     or (select ps.basis from public.player_storage ps where ps.player_id = v_pl and ps.port_id = v_lis and ps.good_id = v_bars) <> 40
     or (select x.xp from public.level_xp x where x.player_id = v_pl and x.skill = 'smithing') <> 3 * 2078
     or exists (select 1 from public.level_book b where b.player_id = v_pl and b.skill = 'smithing' and b.activity <> 'smith')
     or exists (select 1 from public.level_xp x where x.player_id = v_pl and x.skill = 'mining' and x.xp > 0) then
    raise exception 'proof 164 SMITH_RUN: the bars were not booked one a turn at 40 with Smithing''s experience: % then %', v_r, v_s;
  end if;
  perform public.land_home_for(v_pl, c_t + make_interval(secs => 3 * v_a + 60));
  v_r := public.land_collect_for(v_pl, c_t + make_interval(secs => 3 * v_a + 60));
  if (v_r ->> 'ended')::boolean is not true or v_r -> 'given_back' <> '{"coal": 3, "iron": 6}'::jsonb
     or (select ps.qty from public.player_storage ps where ps.player_id = v_pl and ps.port_id = v_lis and ps.good_id = v_iron) <> 6
     or (select ps.basis from public.player_storage ps where ps.player_id = v_pl and ps.port_id = v_lis and ps.good_id = v_iron) <> 50
     or (select ps.qty from public.player_storage ps where ps.player_id = v_pl and ps.port_id = v_lis and ps.good_id = v_coal) <> 3
     or (select ps.basis from public.player_storage ps where ps.player_id = v_pl and ps.port_id = v_lis and ps.good_id = v_coal) <> 20
     or (select lp.action from public.land_parties lp where lp.id = v_party) is not null then
    raise exception 'proof 164 SMITH_RUN: called home after three, the smith did not give back 6 Iron at 50 and 3 Sea Coal at 20: %', v_r;
  end if;
  raise notice 'PASS: SMITH_RUN - six bars sent for, 12 Iron and 6 Sea Coal taken; at % s a bar three booked at 40 (Smithing %, % experience, activity smith); called home it gave back %',
    v_a, public.level_of('smithing', 3 * 2078), 3 * 2078, v_r -> 'given_back';

  -- ── SHORT ──
  v_fmsg := v_s ->> 'error_message';
  delete from public.player_storage ps where ps.player_id = v_pl and ps.good_id in (v_iron, v_coal);
  v_r := public.land_terms(v_pl, 'iron-bars');
  v_s := cmd.land_send('iron-bars');
  if v_r -> 'short' ->> 'code' <> 'E_NO_MATERIALS' or (v_r -> 'make' ->> 'can')::int <> 0
     or position(v_r -> 'short' ->> 'sentence' in v_fmsg) = 0 or v_s ->> 'error_code' <> 'E_NO_MATERIALS'
     or public.land_terms(v_mn, 'steel-billets') -> 'short' ->> 'code' <> 'E_NEEDS_SKILL'
     or public.land_terms(v_mn, 'steel-billets') -> 'short' ->> 'sentence' <> 'needs Smithing 10'
     or public.land_terms(v_mn, 'copper') -> 'short' ->> 'sentence' <> 'needs Mining 10' then
    raise exception 'proof 164 SMITH_SHORT: % / % / %', v_r -> 'short', v_s, public.land_terms(v_mn, 'steel-billets') -> 'short';
  end if;
  raise notice 'PASS: SMITH_SHORT - no inputs: % "%"; too low: "%"; Mining''s still "%"', v_s ->> 'error_code', v_r -> 'short' ->> 'sentence',
    public.land_terms(v_mn, 'steel-billets') -> 'short' ->> 'sentence', public.land_terms(v_mn, 'copper') -> 'short' ->> 'sentence';

  -- ── EXPERIENCE STAYS WITH ITS SKILL ──
  update public.land_parties set xp_due = 500, xp_skill = 'mining', xp_booked_at = c_t + interval '1 day' where id = v_party;
  perform public.storage_put(v_pl, v_lis, v_iron, 2, 50);
  perform public.storage_put(v_pl, v_lis, v_coal, 1, 20);
  v_x := coalesce((select x.xp from public.level_xp x where x.player_id = v_pl and x.skill = 'mining'), 0);
  perform public.land_send_for(v_pl, 'iron-bars', c_t + interval '1 day' + interval '1 minute');
  if (select x.xp from public.level_xp x where x.player_id = v_pl and x.skill = 'mining') <> v_x + 500
     or not exists (select 1 from public.level_book b where b.player_id = v_pl and b.skill = 'mining' and b.activity = 'dig' and b.xp = 500)
     or (select lp.xp_due from public.land_parties lp where lp.id = v_party) <> 0
     or (select x.xp from public.level_xp x where x.player_id = v_pl and x.skill = 'smithing') <> 3 * 2078 then
    raise exception 'proof 164 SMITH_XP_SKILL: Mining''s due experience was not booked as Mining''s before the smith''s job';
  end if;
  v_r := public.land_collect_for(v_pl, c_t + interval '1 day' + interval '1 minute' + make_interval(secs => v_a));
  if (select x.xp from public.level_xp x where x.player_id = v_pl and x.skill = 'smithing') <> 4 * 2078
     or (select x.xp from public.level_xp x where x.player_id = v_pl and x.skill = 'mining') <> v_x + 500 then
    raise exception 'proof 164 SMITH_XP_SKILL: the next bar''s experience did not go to Smithing alone: %', v_r;
  end if;
  raise notice 'PASS: SMITH_XP_SKILL - 500 Mining experience due at a smith''s Send booked as Mining (dig); the next bar''s 2078 as Smithing';

  -- ── A SMITH IS NOBODY'S COMPANY ──
  perform public.storage_put(v_fg, v_lis, v_iron, 2, 50);
  perform public.storage_put(v_fg, v_lis, v_coal, 1, 20);
  perform public.land_send_for(v_fg, 'iron-bars', now());
  perform cmd.assume_identity('00000000-0461-4000-8000-0000000164c4');
  if (public.land_terms(v_mn, 'iron') ->> 'crowd')::numeric <> 0
     or exists (select 1 from jsonb_array_elements(world.land('mining') -> 'site' -> 'parties') x where x ->> 'company' in ('Casa Forja 164', 'Casa Ferreira 164'))
     or (select count(*) from public.land_parties lp where lp.region_id = (select p.region_id from public.ports p where p.id = v_lis) and lp.action is not null) < 1 then
    raise exception 'proof 164 SMITH_NO_COMPANY: a smith at home lent company to a miner, or stood on the site''s list: %', public.land_terms(v_mn, 'iron') ->> 'crowd';
  end if;
  raise notice 'PASS: SMITH_NO_COMPANY - a smith at work at Lisbon: a Lisbon miner''s second-unit chance %, and neither is on the site''s list', public.land_terms(v_mn, 'iron') ->> 'crowd';
end
$p$;
