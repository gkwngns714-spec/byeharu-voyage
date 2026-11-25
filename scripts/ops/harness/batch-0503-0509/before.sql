-- BATCH 0503-0509, BEFORE. A PROD CHECK: read-only, ONE statement (begin read only ... rollback), the gate first.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/batch-0503-0509/before.sql
-- Gathers the slices' own checks (scripts/ops/harness/<slice>/), which stay the detail of each.
-- Expect: head 20260818000502; bodies_off [] (each body this batch cuts is the one the hunks were written against; a listed one is refused
--   at the push); new_there []; knobs_there []; tables_there 0; stores_separate true (0508 is dark by it; the push does not depend on it);
--   sea_places_free >= 1 (0505's scene); capitals 2; payers >= 1 and founding_room >= 5 (0503's probe founds three companies at once,
--   0509's two: each 40,000 from a city above its reserve, the richest at last); long_tx 0. case_twins 0 and 0503 builds its
--   index; above 0 it leaves it out and says so. rates_md5: the after file must print the same. companies.moves_home: read before
--   hq_cities_enabled is ever lit. The switches of batch 1 may be lit: proved with them lit.
-- Reads: arrivals_beats (5 minutes), pg_class, pg_stat_activity, the catalog, world_config by key, small tables by count. Only STABLE functions are
--   called, none writes. The digests are of the local chain's world (PGlite, migrations to 0509).
begin transaction read only;
select json_build_object(
  'at', now(),
  'gate', json_build_object(
    'beat_mean_ms', (select round(avg(b.ms)) from public.arrivals_beats b where b.at > now() - interval '5 minutes'),
    'database_mb', (select (sum(k.relpages)::numeric * 8192 / 1048576)::int from pg_class k where k.relkind in ('r', 'i', 't', 'm', 'S', 'p')),
    'io_waiting', (select count(*) from pg_stat_activity a where a.pid <> pg_backend_pid() and a.wait_event_type = 'IO' and a.state = 'active')),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'bodies_off', (select coalesce(json_agg(json_build_object('fn', w.fn, 'have', h.have)), '[]'::json)
                   from (values ('voyage.settle(uuid,timestamp with time zone)', '1809e424046a2dfb321f8345659702cd'),
                                ('public.run_day(uuid,uuid,uuid,uuid,uuid,numeric,numeric,numeric,numeric,numeric)', '8481b18743c6ff2773a56c93d96f9dcb'),
                                ('cmd.do_buy(uuid,jsonb)', 'c729d43130979aac20ce60e08c26ecdd'),
                                ('cmd.haggle(uuid,uuid,text)', 'cc1ed1dbd1f1c02e6575efc1d6030bf8'),
                                ('public.client_rpc_entry_points()', '16a15f96b3c5d0f71621f1d5ebc7fc82'),
                                ('cmd.do_sell(uuid,jsonb)', '0abb37cf1eccd82fa4aa0a7e0b42236b'),
                                ('world.town_hall(uuid)', 'd1e550ccfdffd0db6f2f91ff0e6a77f6'),
                                ('public.fleet_job_set_for(uuid,uuid,text,jsonb)', '371fff91841004c1d37ee9eac9b79b2e'),
                                ('public.haggle_odds(uuid,uuid,uuid,uuid)', 'c57a1ca2f096afdf8a56a47abaaa63dc'),
                                ('world.quote_priced(uuid,uuid,numeric,text,numeric,uuid,numeric,numeric,numeric,numeric)', '32f186adde3bb64d0f50491958a18783'),
                                ('cmd.found_house(text,text)', 'fe6a8c0833224db70b0c4b89d4edf8b2'),
                                ('world.stats_me()', 'b4a5eb1bf02cab704c4e49d5c27189df'),
                                ('public.town_hall_gifts(uuid)', 'c584ad8c26807b017d0a1d911413e059'),
                                ('public.new_house(uuid,text,text,text,text,text,text,bigint,boolean)', 'dd895b90903cff342811cab9417201ec'),
                                ('world.city_history(uuid,integer)', 'ce5f971cf201883966cc577aea3c164d'),
                                ('public.home_port_of(uuid)', 'b87352b1b597ac7d57e8ecaf6516777b'),
                                ('public.flow_is_profit(text)', 'f35cfcfb35e110bc3ab1407a36116301'),
                                ('public.ledger_is_earning(text)', 'a477607cb50e7949e9290086c75a3a95'),
                                ('world.tax_rate(uuid,uuid)', '01bfcd04df2051c271599605e23169eb'),
                                ('public.fleet_job_plan(uuid)', '2f3b9b0c859a032093c9637e36a75eab'),
                                ('public.ship_stores_room(uuid,numeric)', '90e678071389da3804f28927e1e2e1e9'),
                                ('public.level_skills_card(uuid,jsonb)', 'a06aa6775ffbfa92facc3728a7807fec'),
                                ('world.spread_pair_from(uuid,uuid,uuid,boolean,numeric[],numeric)', '2d46f503a190ac65b798f968e0e28c49'),
                                ('public.fleet_run_quote(uuid,uuid,uuid,text,text,text[])', 'ffb298fac04208924d167a8aeef0b9d7'),
                                ('cmd.set_tax(uuid,numeric)', 'e1d222859a6c98049c1502462bd1e8f0'),
                                ('world.haggle_state(uuid,uuid)', 'a6900eb8f9e063aa375b70dcffcd9f47'),
                                ('public.settle_standings(timestamp with time zone)', '6c89ae48600318e4878fd67d12438df1'),
                                ('world.player()', 'fc28ff0b7626af6b2fb5adc4571f87d9')) w(fn, want)
                  cross join lateral (select md5(replace(pg_get_functiondef(to_regprocedure(w.fn)), E'', '')) as have) h
                  where h.have is distinct from w.want),
  'new_there', (select coalesce(json_agg(u.s), '[]'::json) from unnest(array['public.company_rename_free(integer)', 'public.rename_company(uuid,text)', 'public.company_name_refusal(text,uuid)', 'cmd.rename_company(text)', 'public.chart_sight_nm(uuid)', 'public.tax_cap()', 'public.tax_home_half(uuid,uuid,numeric,numeric)', 'public.bargain_side_refusal(uuid,uuid,uuid,text)', 'public.bargain_p1(uuid,uuid,uuid,uuid)', 'public.bargain_odds(uuid,uuid,uuid,uuid)', 'public.bargain_actor()', 'public.bargain_xp(uuid,boolean)', 'public.job_bargain_tries(uuid)', 'public.nation_in_europe(uuid)', 'public.hq_card(uuid)', 'public.company_heir(uuid)', 'public.chart_paint(bytea,jsonb,numeric)', 'public.chart_backfill(uuid,integer)', 'public.chart_mark(uuid,uuid)', 'public.chart_backfill_next(integer,integer)', 'world.chart()', 'public.tax_thirty_on()', 'public.bargain_on()', 'public.haggle_attempts_max()', 'public.haggle_step()', 'public.haggle_cap()', 'public.job_bargain(uuid,uuid,text)', 'public.job_bargain_param(jsonb)', 'public.bargain_factor(uuid,uuid,uuid,text)', 'public.bargain_state(uuid,uuid,uuid,uuid)', 'public.bargain_first(uuid,uuid,uuid,text,numeric,numeric)', 'public.buy_tax_on()', 'public.buy_tax_rate(uuid,uuid)', 'public.ship_hold_over(uuid)', 'public.fleet_trip_stores(uuid,uuid,text[])', 'public.stores_in_hold_ready()', 'public.stores_in_hold_light()', 'public.restart_on()', 'public.hq_cities_on()', 'public.restart_refusal(uuid,timestamp with time zone)', 'public.restart_card(uuid)', 'public.company_retire(uuid,timestamp with time zone)', 'cmd.restart_company(text,text,text)']) u(s) where to_regprocedure(u.s) is not null),
  'knobs_there', (select coalesce(json_agg(c.key), '[]'::json) from public.world_config c where c.key in ('chart_fog_enabled', 'chart_sight_nm', 'tax_thirty_enabled', 'tax_rate_cap', 'home_tax_cut', 'restart_enabled', 'buy_tax_enabled', 'buy_tax_share', 'bargain_total_enabled', 'bargain_attempts', 'bargain_step', 'bargain_p1_base', 'bargain_p1_max', 'bargain_decay', 'hq_cities_enabled', 'buy_tax_max')),
  'switches', (select json_object_agg(c.key, c.value) from public.world_config c where c.key in ('economy_closed', 'city_treasury_enabled', 'jobs_wait_enabled', 'wreck_sells_enabled', 'fleet_jobs_enabled', 'influence_enabled')),
  'payers', (select count(*) from public.port_treasury t where t.ducats - t.reserve >= 40000),
  'founding_room', (select coalesce(sum(floor((t.ducats - t.reserve) / 40000)), 0) from public.port_treasury t where t.ducats - t.reserve >= 40000),
  'long_tx', (select count(*) from pg_stat_activity a where a.pid <> pg_backend_pid() and a.state <> 'idle' and a.xact_start < now() - interval '4 seconds' and a.backend_type = 'client backend'),
  'case_twins', (select count(*) from (select 1 from public.players p where not p.is_npc group by lower(p.company_name) having count(*) > 1) t),
  'companies', (select json_build_object('all', count(*), 'no_capital', count(*) filter (where cap.id is null),
                                         'moves_home', count(*) filter (where cap.id is not null and public.home_port_of(p.id) is distinct from cap.id))
                  from public.players p left join public.nations n on n.id = p.nation_id
                  left join public.ports cap on cap.code = n.capital_port_code and cap.kind = 'HARBOUR' where not p.is_npc),
  'capitals', (select count(*) from public.nations n join public.ports p on p.code = n.capital_port_code and p.kind = 'HARBOUR' where n.code in ('PRT', 'ESP')),
  'sea_places_free', (select count(*) from public.ports z where z.kind = 'SEA_PLACE' and not exists (select 1 from public.port_allegiance a where a.port_id = z.id)
                                                       and not exists (select 1 from public.port_mayor m where m.port_id = z.id)),
  'stores_separate', (select c.value from public.world_config c where c.key = 'ship_stores_separate'),
  'rates_md5', (select md5(string_agg(h.code || ':' || world.tax_rate(h.id)::text, ',' order by h.code)) from public.ports h where h.kind = 'HARBOUR'),
  'tables_there', (select count(*) from pg_class k where k.relnamespace = 'public'::regnamespace and k.relname in ('company_chart', 'company_hqs', 'hq_steps', 'company_retirements')),
  'voyages_rows', (select k.reltuples::bigint from pg_class k where k.oid = 'public.voyages'::regclass)
);
rollback;
