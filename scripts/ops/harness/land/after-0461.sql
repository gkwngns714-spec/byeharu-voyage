-- 0461 PROD CHECK, AFTER the deploy (the smith, land slice L2, DARK behind land_smith_enabled), read-only, one SELECT inside
--   `begin transaction read only; ... commit;`:  npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/land/after-0461.sql
-- One row, one jsonb column `r`. Catalog, knobs and small tables only; no volatile function.
-- Wanted: head 20260818000461; land_smith_enabled false; land_enabled and land_yield_pct as before the deploy (the owner's); smithing
--   {side land, curve long, gift_every 5, lit_by land_smith_enabled}; activity smith; make_rows 21; rows_as_0457 true (Mining's);
--   new_hunks every count 1; new_fns both present, server only (service false, client false); xp_skill true; parties and parties_out as
--   before (0461 adds none); smith_parties 0 (nobody can send a smith while dark).
-- Generated from the migration's own hunks.
begin transaction read only;
with hn(ord, fn, new) as (values
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
)
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'land_smith_enabled', (select c.value from public.world_config c where c.key = 'land_smith_enabled'),
  'land_enabled', (select c.value from public.world_config c where c.key = 'land_enabled'),
  'land_yield_pct', (select c.value from public.world_config c where c.key = 'land_yield_pct'),
  'smithing', (select jsonb_build_object('side', s.side, 'curve', s.curve, 'gift_every', s.gift_every, 'lit_by', s.lit_by) from public.level_skills s where s.code = 'smithing'),
  'activity', (select a.code from public.level_activities a where a.skill = 'smithing'),
  'make_rows', (select count(*) from public.land_actions a where a.kind = 'make' and a.skill = 'smithing'),
  'rows_as_0457', (select md5(string_agg(a.code || ':' || a.seconds || ':' || a.xp, ',' order by a.ord)) from public.land_actions a where a.skill = 'mining') = 'bd9026a3e5eb6ef5f240215fa438e73f',
  'new_hunks', (select jsonb_object_agg(h.ord, (length(d.def) - length(replace(d.def, h.new, ''))) / length(h.new))
                  from hn h cross join lateral (select replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '') as def) d),
  'new_fns', (select jsonb_object_agg(f, jsonb_build_object(
                'present', to_regprocedure(f) is not null,
                'service', to_regprocedure(f) is not null and has_function_privilege('service_role', to_regprocedure(f), 'execute'),
                'client', to_regprocedure(f) is not null and (has_function_privilege('authenticated', to_regprocedure(f), 'execute') or has_function_privilege('anon', to_regprocedure(f), 'execute'))))
                from unnest(array['public.land_skill_on(text)', 'public.forge_take(uuid,uuid,uuid,integer)']) f),
  'xp_skill', exists (select 1 from pg_attribute a where a.attrelid = 'public.land_parties'::regclass and a.attname = 'xp_skill' and not a.attisdropped),
  'parties', (select count(*) from public.land_parties),
  'parties_out', (select count(*) from public.land_parties lp where lp.action is not null),
  'smith_parties', (select count(*) from public.land_parties lp join public.land_actions a on a.code = lp.action where a.kind = 'make')) as r;
commit;
