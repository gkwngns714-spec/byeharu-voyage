-- 0461 PROD CHECK, BEFORE the deploy (the smith, land slice L2, DARK behind land_smith_enabled), read-only, one SELECT inside
--   `begin transaction read only; ... commit;`:  npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/land/before-0461.sql
-- One row, one jsonb column `r`. It reads the catalog, the knobs and small tables (land_actions, land_tools, land_parties, goods,
--   goods_recipes, regions, ports) and port_goods for the land's goods (as before-0457 and before-0458 did): no volatile function.
-- Wanted: head 20260818000460; applied false; old_hunks every count 1; new_hunks every count 0 (else a deploy since re-cut a body: 0461
--   refuses); rows_as_0457 true; make_rows 0; products 21 (the smith's 21 goods, each with a recipe); land_enabled and land_yield_pct
--   as the owner left them (0461 does not touch them; its self-assert reads them unchanged); tools 1 at best 3; lis_harbour true;
--   secret_ok true; worst_make and worst_mine: share at most 1 = THE GUARD on production's own port_goods at the fastest pace
--   (Smithing / Mining 100; a make job no tool, no company; a Mining job the best tool and the crowd's full chance).
-- Generated from the migration's own hunks and scripts/build-land-migration.mjs --smith (the same text: the check cannot drift).
begin transaction read only;
with hk(ord, fn, old) as (values
  (1, 'public.land_terms(uuid,text)', $h$  v_short jsonb;
begin
$h$),
  (2, 'public.land_terms(uuid,text)', $h$  v_pass := public.land_passage(v_port, j.good_id);
$h$),
  (3, 'public.land_terms(uuid,text)', $h$o.action is not null and o.player_id <> p_player));$h$),
  (4, 'public.land_terms(uuid,text)', $h$  if v_lvl < j.level then
$h$),
  (5, 'public.land_terms(uuid,text)', $h$format('needs Mining %s', j.level)$h$),
  (6, 'public.land_terms(uuid,text)', $h$  elsif v_pass is null then
$h$),
  (7, 'public.land_terms(uuid,text)', $h$(v_pass ->> 'region') = any(g.origin_regions)));
$h$),
  (8, 'public.land_send_for(uuid,text,timestamp with time zone)', $h$  t       jsonb;
begin
$h$),
  (9, 'public.land_send_for(uuid,text,timestamp with time zone)', $h$  if lp.action is not null then
    perform cmd.refuse('E_LAND_OUT', 'the party is out; call it home first');
$h$),
  (10, 'public.land_send_for(uuid,text,timestamp with time zone)', $h$  t := public.land_terms(p_player, p_action);
$h$),
  (11, 'public.land_send_for(uuid,text,timestamp with time zone)', $h$                 || case when lp.repeat_on then '{}'::jsonb else '{"last": 1}'::jsonb end   -- 0458: Repeat off: one trip
$h$),
  (12, 'public.land_send_for(uuid,text,timestamp with time zone)', $h$  return jsonb_build_object('ok', true, 'action', p_action, 'trip', t -> 'trip', 'home_at', p_at + make_interval(secs => (t ->> 'trip')::numeric));
$h$),
  (13, 'public.land_settle(uuid,timestamp with time zone)', $h$  v_n     int;
begin
$h$),
  (14, 'public.land_settle(uuid,timestamp with time zone)', $h$g.id, v_put, 0);
      end if;
      if v_units > v_put then
$h$),
  (15, 'public.land_settle(uuid,timestamp with time zone)', $h$      lp.xp_due := lp.xp_due + v_new * (lp.terms ->> 'xp')::int;
$h$),
  (16, 'public.land_settle(uuid,timestamp with time zone)', $h$  -- the experience: at most once in land_book_minutes
$h$),
  (17, 'public.land_settle(uuid,timestamp with time zone)', $h$public.level_grant(lp.player_id, 'dig', lp.xp_due,$h$),
  (18, 'public.land_settle(uuid,timestamp with time zone)', $h$         found_waiting = lp.found_waiting   -- 0458
$h$),
  (19, 'public.land_settle(uuid,timestamp with time zone)', $h$                            'found', v_found, 'found_waiting', lp.found_waiting);   -- 0458: the rare finds this press booked or kept$h$),
  (20, 'world.land(text)', $h$s.code = v_skill and s.side = 'land')$h$),
  (21, 'world.land(text)', $h$    'enabled', true, 'company', true, 'now', now(),
$h$),
  (22, 'world.land(text)', $h$               'finds', coalesce(t.v -> 'finds', '[]'::jsonb),   -- 0458
$h$),
  (23, 'world.land(text)', $h$x.region_id = v_region and x.action is not null limit 20) o$h$),
  (24, 'public.level_skills_card(uuid,jsonb)', $h$where s.side = 'sea' or public.land_on()))$h$),
  (25, 'cmd.forge_good(uuid,uuid,integer)', $h$  r        record;
begin
$h$),
  (26, 'cmd.forge_good(uuid,uuid,integer)', $h$    -- EVERYTHING, BEFORE ANYTHING LEAVES. Same rule as cmd.do_make: test all the materials first,
    -- name what is short, then spend.
    select string_agg(format('%s (%s of %s)', g.name,
             trim(to_char(coalesce(ps.qty, 0), 'FM999999.99')),
             trim(to_char(gr.qty * v_qty, 'FM999999.99'))), ', ' order by g.name)
      into v_short
      from public.goods_recipes gr
      join public.goods g on g.id = gr.ingredient_id
      left join public.player_storage ps
             on ps.player_id = v_player and ps.port_id = p_port and ps.good_id = gr.ingredient_id
     where gr.product_id = p_product
       and coalesce(ps.qty, 0) < gr.qty * v_qty;
    if v_short is not null then
      perform cmd.refuse('E_NO_MATERIALS', format('the forge is short of %s', v_short));
    end if;

    for r in select gr.ingredient_id, g.code, g.name, gr.qty * v_qty as need, ps.basis
               from public.goods_recipes gr
               join public.goods g on g.id = gr.ingredient_id
               left join public.player_storage ps
                      on ps.player_id = v_player and ps.port_id = p_port and ps.good_id = gr.ingredient_id
              where gr.product_id = p_product
              order by g.code loop
      -- 0081's ONE weighted average: what the consumed tuns cost per tun, carried into the product.
      v_basis := public.blend_basis(v_tuns, v_basis, r.need, r.basis);
      v_tuns  := v_tuns + r.need;
      perform public.storage_take(v_player, p_port, r.ingredient_id, r.need);
      v_spent := v_spent || jsonb_build_object('good', r.code, 'qty', r.need);
    end loop;
$h$)
), hn(ord, fn, new) as (values
  (1, 'public.land_terms(uuid,text)', $h$  v_short jsonb;
  -- 0461: a make job: its inputs a unit (have: in the home Storage), how many it can make, what is short
  v_make  jsonb;
  v_can   int;
  v_lack  text;
begin
$h$),
  (2, 'public.land_terms(uuid,text)', $h$  -- 0461: a make job is done at home: the home land, no passage (and no ground: no march, no tool)
  v_pass := case when j.kind = 'make'
                 then (select jsonb_build_object('home', true, 'region_id', r.id, 'region', r.code, 'via', null, 'nm', 0, 'seconds', 0)
                         from public.ports p join public.regions r on r.id = p.region_id where p.id = v_port)
                 else public.land_passage(v_port, j.good_id) end;
$h$),
  (3, 'public.land_terms(uuid,text)', $h$o.action is not null and o.player_id <> p_player
                                                         and o.action in (select oa.code from public.land_actions oa where oa.ground = j.ground)));   -- 0461: company is a party on the same ground (a smith at home is nobody's)$h$),
  (4, 'public.land_terms(uuid,text)', $h$  -- 0461: A MAKE JOB is one unit a turn; it can make what the home Storage holds the inputs for (public.goods_recipes, the Forge's)
  if j.kind = 'make' then
    v_p := 1;
    select coalesce(jsonb_agg(jsonb_build_object('code', g.code, 'qty', gr.qty, 'have', coalesce(ps.qty, 0)) order by g.code), '[]'::jsonb),
           coalesce(min(floor(coalesce(ps.qty, 0) / gr.qty)), 0)::int,
           string_agg(case when coalesce(ps.qty, 0) < gr.qty then format('%s (%s of %s)', g.name, trim(to_char(coalesce(ps.qty, 0), 'FM999999.99')),
                                                                      trim(to_char(gr.qty, 'FM999999.99'))) end, ', ' order by g.name)
      into v_make, v_can, v_lack
      from public.goods_recipes gr
      join public.goods g on g.id = gr.ingredient_id
      left join public.player_storage ps on ps.player_id = p_player and ps.port_id = v_port and ps.good_id = gr.ingredient_id
     where gr.product_id = j.good_id;
  end if;
  if v_lvl < j.level then
$h$),
  (5, 'public.land_terms(uuid,text)', $h$format('needs %s %s', (select s.word from public.level_skills s where s.code = j.skill), j.level)$h$),
  (6, 'public.land_terms(uuid,text)', $h$  elsif v_make is not null and v_can < 1 then   -- 0461: a make job with too little in Storage for one unit
    v_short := cmd.refusal('E_NO_MATERIALS', format('the forge is short of %s', v_lack));
  elsif v_pass is null then
$h$),
  (7, 'public.land_terms(uuid,text)', $h$(v_pass ->> 'region') = any(g.origin_regions)))
    -- 0461: a make job's inputs a unit and how many it can make (a gather job's terms are as they were)
    || case when v_make is not null then jsonb_build_object('make', jsonb_build_object('can', v_can, 'inputs', v_make)) else '{}'::jsonb end;
$h$),
  (8, 'public.land_send_for(uuid,text,timestamp with time zone)', $h$  t       jsonb;
  v_take  jsonb;   -- 0461: what a make job took (public.forge_take)
begin
$h$),
  (9, 'public.land_send_for(uuid,text,timestamp with time zone)', $h$  -- 0461: a land skill behind a switch of its own (level_skills.lit_by) is not open while that switch is off
  if not public.land_skill_on((select a.skill from public.land_actions a where a.code = p_action)) then
    perform cmd.refuse('E_NOT_IN_USE', 'that skill is not open yet');
  end if;
  if lp.action is not null then
    perform cmd.refuse('E_LAND_OUT', 'the party is out; call it home first');
$h$),
  (10, 'public.land_send_for(uuid,text,timestamp with time zone)', $h$  -- 0461: experience still due of another skill is booked now, under its own skill (public.land_settle, its wait lifted once)
  if lp.xp_due > 0 and lp.xp_skill <> (select a.skill from public.land_actions a where a.code = p_action) then
    update public.land_parties set xp_booked_at = null where id = v_party;
    perform public.land_settle(v_party, p_at);
  end if;
  t := public.land_terms(p_player, p_action);
$h$),
  (11, 'public.land_send_for(uuid,text,timestamp with time zone)', $h$                 || case when lp.repeat_on then '{}'::jsonb else '{"last": 1}'::jsonb end   -- 0458: Repeat off: one trip
                 || case when t ? 'make' then jsonb_build_object('last', (t -> 'make' ->> 'can')::int) else '{}'::jsonb end   -- 0461: a make: as many as the inputs allow
$h$),
  (12, 'public.land_send_for(uuid,text,timestamp with time zone)', $h$  -- 0461: A MAKE TAKES ITS INPUTS NOW, for every unit it will make, through the Forge's own take (public.forge_take); a unit is booked at
  -- that cost as it is made (public.land_settle), and the inputs of the units not made are given back when the job ends
  if t ? 'make' then
    v_take := public.forge_take(p_player, lp.port_id, (t ->> 'good')::uuid, (t -> 'make' ->> 'can')::int);
    update public.land_parties
       set terms = (terms - 'make') || jsonb_build_object('basis', v_take -> 'basis',
                     'take', (select jsonb_object_agg(i ->> 'code', jsonb_build_object('qty', (i ->> 'qty')::numeric, 'basis', v_take -> 'bases' -> (i ->> 'code')))
                                from jsonb_array_elements(t -> 'make' -> 'inputs') i))
     where id = v_party;
  end if;
  return jsonb_build_object('ok', true, 'action', p_action, 'trip', t -> 'trip', 'home_at', p_at + make_interval(secs => (t ->> 'trip')::numeric));
$h$),
  (13, 'public.land_settle(uuid,timestamp with time zone)', $h$  v_n     int;
  v_back  jsonb := '{}'::jsonb;   -- 0461: a make job's inputs given back
begin
$h$),
  (14, 'public.land_settle(uuid,timestamp with time zone)', $h$g.id, v_put, case when lp.terms ? 'take' then (lp.terms ->> 'basis')::numeric else 0 end);   -- 0461: a made good at its inputs' cost
      end if;
      if v_units > v_put then
$h$),
  (15, 'public.land_settle(uuid,timestamp with time zone)', $h$      lp.xp_due := lp.xp_due + v_new * (lp.terms ->> 'xp')::int;
      lp.xp_skill := lp.terms ->> 'skill';   -- 0461: whose experience it is
$h$),
  (16, 'public.land_settle(uuid,timestamp with time zone)', $h$  -- 0461: A MAKE JOB THAT ENDS (called home, or a made good waiting for room) gives back the inputs of the units it did not make: what
  -- fits goes back into the home Storage at the cost it was taken at, the rest waits for room with the party (found_waiting, as a find)
  if v_end and lp.terms ? 'take' and (lp.terms ->> 'last')::int > lp.booked then
    for v_f in select e.key as code, ((e.value ->> 'qty')::numeric * ((lp.terms ->> 'last')::int - lp.booked))::int as qty, (e.value ->> 'basis')::numeric as basis
                 from jsonb_each(lp.terms -> 'take') e order by e.key loop
      select * into v_g from public.goods where code = v_f.code;
      v_fit := floor(greatest(public.storage_cap(lp.port_id) - public.storage_used(lp.player_id, lp.port_id), 0) / v_g.bulk);
      v_n := least(v_f.qty, greatest(v_fit, 0))::int;
      if v_n > 0 then
        perform public.storage_put(lp.player_id, lp.port_id, v_g.id, v_n, v_f.basis);
      end if;
      if v_f.qty > v_n then
        lp.found_waiting := jsonb_set(lp.found_waiting, array[v_f.code], to_jsonb(coalesce((lp.found_waiting ->> v_f.code)::int, 0) + v_f.qty - v_n));
      end if;
      v_back := v_back || jsonb_build_object(v_f.code, v_f.qty);
    end loop;
  end if;
  -- the experience: at most once in land_book_minutes
$h$),
  (17, 'public.land_settle(uuid,timestamp with time zone)', $h$public.level_grant(lp.player_id, (select la.code from public.level_activities la where la.skill = lp.xp_skill order by la.ord limit 1), lp.xp_due,$h$),
  (18, 'public.land_settle(uuid,timestamp with time zone)', $h$         found_waiting = lp.found_waiting,   -- 0458
         xp_skill = lp.xp_skill   -- 0461
$h$),
  (19, 'public.land_settle(uuid,timestamp with time zone)', $h$                            'found', v_found, 'found_waiting', lp.found_waiting,   -- 0458: the rare finds this press booked or kept
                            'given_back', v_back);   -- 0461: a make job's inputs given back$h$),
  (20, 'world.land(text)', $h$s.code = v_skill and s.side = 'land' and public.land_skill_on(s.code))$h$),
  (21, 'world.land(text)', $h$    'enabled', true, 'company', true, 'now', now(),
    -- 0461: the land skills open now (public.land_skill_on): the Land tab's faces
    'skills', (select coalesce(jsonb_agg(s.code order by s.ord), '[]'::jsonb) from public.level_skills s where s.side = 'land' and public.land_skill_on(s.code)),
$h$),
  (22, 'world.land(text)', $h$               'finds', coalesce(t.v -> 'finds', '[]'::jsonb),   -- 0458
               'kind', a.kind, 'make', t.v -> 'make',   -- 0461: a make job's inputs a unit and how many it can make
$h$),
  (23, 'world.land(text)', $h$x.region_id = v_region and x.action is not null and x.action in (select xa.code from public.land_actions xa where xa.ground is not null) limit 20) o$h$),
  (24, 'public.level_skills_card(uuid,jsonb)', $h$where s.side = 'sea' or public.land_skill_on(s.code)))   -- 0461: and its own switch$h$),
  (25, 'cmd.forge_good(uuid,uuid,integer)', $h$  r        record;
  v_take   jsonb;   -- 0461: what public.forge_take spent
begin
$h$),
  (26, 'cmd.forge_good(uuid,uuid,integer)', $h$    -- 0461: EVERYTHING, BEFORE ANYTHING LEAVES, is ONE rule, shared with the land's smith (public.forge_take): every material tested
    -- first and the short named, then spent, the cost blended by 0081's one weighted average. The same take as before, moved.
    v_take := public.forge_take(v_player, p_port, p_product, v_qty);
    v_basis := (v_take ->> 'basis')::numeric;
    v_spent := v_take -> 'spent';
$h$)
),
smith(code, seconds) as (values ('iron-bars', 24940), ('ships-nails', 4275), ('steel-billets', 4275), ('sword-blades', 7300), ('pike-heads', 4275), ('armour', 4275), ('brass-ingots', 2495), ('copper-cash', 2495), ('pewter', 2495), ('wootz-steel', 4275), ('copper-sheet', 2495), ('talwar', 9975), ('brassware', 4275), ('smallwares', 4275), ('kris', 9975), ('benin-bronzes', 2495), ('katana', 9975), ('milanese-armour', 9975), ('maghreb-brass', 4275), ('toledo-blades', 9975), ('damascus-blades', 9975)),
k as (
  select max(case when c.key = 'land_yield_pct' then (c.value #>> '{}')::numeric end) as yield,
         max(case when c.key = 'land_level_speed_pct' then (c.value #>> '{}')::numeric end) as lvl,
         max(case when c.key = 'land_crowd_max' then (c.value #>> '{}')::numeric end) as crowd,
         (select max(t.speed_pct) from public.land_tools t) as tool
    from public.world_config c where c.key in ('land_yield_pct', 'land_level_speed_pct', 'land_crowd_max')),
mid as (
  select g.id as good_id, g.code, rg.code as region, percentile_disc(0.5) within group (order by coalesce(pg.base_target, pg.stock_target) * least(1, coalesce((select (c.value #>> '{}')::numeric from public.world_config c where c.key = 'depth_m0'), 1))) as target
    from public.goods g
    cross join public.regions rg
    join public.ports p on p.region_id = rg.id and p.kind = 'HARBOUR'
    join public.port_goods pg on pg.port_id = p.id and pg.good_id = g.id
   where (g.id in (select a.good_id from public.land_actions a where a.kind = 'gather') and rg.code = any(g.origin_regions))
      or g.code in (select s.code from smith s)
   group by g.id, g.code, rg.code),
share as (
  select 'make' as kind, s.code, mid.region, mid.target,
         round(3600.0 / greatest(1, round(s.seconds * 100.0 / k.yield * (1 - k.lvl / 100 * 99))) / (mid.target / 100.0), 4) as share
    from smith s join mid on mid.code = s.code cross join k
  union all
  select 'mine', a.code, mid.region, mid.target,
         round(3600.0 / greatest(1, round(a.seconds * 100.0 / k.yield * (1 - k.lvl / 100 * 99) * (1 - k.tool / 100))) * (1 + k.crowd / 100) / (mid.target / 100.0), 4)
    from public.land_actions a join mid on mid.good_id = a.good_id cross join k where a.kind = 'gather')
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'applied', exists (select 1 from public.world_config c where c.key = 'land_smith_enabled') or exists (select 1 from public.level_skills s where s.code = 'smithing')
             or to_regprocedure('public.land_skill_on(text)') is not null or to_regprocedure('public.forge_take(uuid,uuid,uuid,integer)') is not null,
  'old_hunks', (select jsonb_object_agg(h.ord, (length(d.def) - length(replace(d.def, h.old, ''))) / length(h.old))
                  from hk h cross join lateral (select replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '') as def) d),
  'new_hunks', (select jsonb_object_agg(h.ord, (length(d.def) - length(replace(d.def, h.new, ''))) / length(h.new))
                  from hn h cross join lateral (select replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '') as def) d),
  'rows_as_0457', (select md5(string_agg(a.code || ':' || a.seconds || ':' || a.xp, ',' order by a.ord)) from public.land_actions a) = 'bd9026a3e5eb6ef5f240215fa438e73f',
  'make_rows', (select count(*) from public.land_actions a where a.kind <> 'gather'),
  'products', (select count(*) from public.goods g where g.code in (select s.code from smith s) and g.tier >= 1
                 and exists (select 1 from public.goods_recipes gr where gr.product_id = g.id)),
  'land_enabled', (select c.value from public.world_config c where c.key = 'land_enabled'),
  'land_yield_pct', (select c.value from public.world_config c where c.key = 'land_yield_pct'),
  'parties', (select count(*) from public.land_parties),
  'parties_out', (select count(*) from public.land_parties lp where lp.action is not null),
  'knobs', (select to_jsonb(k) from k),
  'tools', (select count(*) from public.land_tools),
  'lis_harbour', exists (select 1 from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR'),
  'secret_ok', (select length(c.value #>> '{}') >= 64 from public.world_config c where c.key = 'world_secret'),
  'make_regions', (select count(*) from share s where s.kind = 'make'),
  'mine_regions', (select count(*) from share s where s.kind = 'mine'),
  'worst_make', (select jsonb_build_object('code', s.code, 'region', s.region, 'target', s.target, 'share', s.share) from share s where s.kind = 'make' order by s.share desc, s.code, s.region limit 1),
  'worst_mine', (select jsonb_build_object('code', s.code, 'region', s.region, 'target', s.target, 'share', s.share) from share s where s.kind = 'mine' order by s.share desc, s.code, s.region limit 1)) as r;
commit;
