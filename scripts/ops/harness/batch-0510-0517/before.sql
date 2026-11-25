-- BATCH 0510-0517, BEFORE. A PROD CHECK: read-only, ONE statement (begin read only ... rollback), the gate first.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/batch-0510-0517/before.sql
-- Gathers the slices' own checks (scripts/ops/harness/<slice>/), which stay the detail of each.
-- Expect: head 20260818000509; bodies_off []; new_there []; knobs_there []; seas.bite false, seas.n 64, seas.table_md5 ca3d649ecf94dd08551e7b00d64cd7f1 (0510 refuses another);
--   matrix_is_harbours true; steps 5, hq.past_first 0; payers >= 1 (one company a file is founded and rolled back); long_tx 0.
--   fleets_of_companies: 0514's self-assert reads each once (80 ms locally, perhaps 250 on prod): over about 150 fleets it may pass its 45 s; then it
--   refuses. pair_rows about 64,516: 0510 rewrites 40,736 of them once. hq.moves_home: SHOW THE OWNER before hq_cities_enabled is lit.
-- Reads: arrivals_beats (5 minutes), pg_class, pg_stat_activity, the catalog, world_config by key, small tables by count. Only STABLE functions are
--   called, none writes. The digests are of the local chain's world (PGlite, migrations to 0517).
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
                                ('world.market(uuid)', 'c855d403c735e297579032ba6bb81114'),
                                ('voyage.report_line(integer,text,jsonb)', '9cec8948d88df53e23d8c5e741d7cfea'),
                                ('public.client_rpc_entry_points()', 'b14f2a1c2231bae88cd1d2005b57b71b'),
                                ('cmd.do_sell(uuid,jsonb)', '18fff22b5f80d5d649cad174c624a55f'),
                                ('public.fleet_job_set_for(uuid,uuid,text,jsonb)', 'da1a0d55c91cd239539f4ebaff048b10'),
                                ('public.sea_routes(uuid,integer,numeric,jsonb)', '0bd3e864b56f05950ab335268521131c'),
                                ('world.quote_priced(uuid,uuid,numeric,text,numeric,uuid,numeric,numeric,numeric,numeric)', '0e837b48ff97d74c5392ce9633a1f91f'),
                                ('world.mid_terms(uuid,uuid)', '6ba0746ba6fc742584de419a895bab4c'),
                                ('voyage.reach_passage(uuid,uuid,uuid,numeric)', 'ed4e1e4ef63ad69c2c210725b3b7846a'),
                                ('voyage.forced_home(uuid,integer,uuid)', '99e30283333001752a30dc5a664ee93e'),
                                ('cmd.forge_good(uuid,uuid,integer)', '4ff9098adcaf40dac9c13e14a7dbba34'),
                                ('world.goods_forge(uuid)', 'c73d7948aca0f01cc60590e32b08d878'),
                                ('world.requests(uuid)', 'edec9bbda952fd39c31405bc4740b479'),
                                ('cmd.request_place(uuid,uuid,numeric,bigint)', '43b25022b880c2660f5152cac173e84e'),
                                ('public.flow_is_profit(text)', 'd8112860e2455a7b4b42e82f8ef7f8fc'),
                                ('voyage.depart(uuid,jsonb,uuid,uuid,timestamp with time zone)', '230e8716f2711d8930a97f642211dab0'),
                                ('public.fleet_wage(uuid,boolean,integer)', '8b6ff54d4c1b3f7936778cab02b7285d'),
                                ('public.fleet_job_plan(uuid)', '3314a40c43244545443b5450fc1d4703'),
                                ('public.sea_judge(integer,numeric,text[],integer,integer,integer,integer)', 'c6dee3f0792a101cc4a57c5041747e4a'),
                                ('public.tax_home_half(uuid,uuid,numeric,numeric)', 'e4f27883a61ed55603b8df7d910207e1'),
                                ('world.sea_conditions()', '048ef286e6ebcc3e2aca2009acd8c71f'),
                                ('public.sea_conditions_ready()', '6fcd0df182ae617c1cb97732c1046259'),
                                ('public.npc_sea_floor(uuid)', 'b4eed07f50b95a35f4cf2004e3b57976'),
                                ('public.level_arrival(uuid,uuid)', '40bc8597d2a74a2b9a73b9f11e1bb436'),
                                ('cmd.refusal_line(text,jsonb)', '8bea2e1f7f059a1397314b257bade3e6'),
                                ('public.sea_gate(uuid,uuid,uuid,jsonb)', 'bd12541b95e57a0bc52496745b9f5fb6'),
                                ('world.board_sell_memo(uuid,uuid,jsonb,jsonb)', 'd1365af1af4640fc6cc3f63f161df36f'),
                                ('public.level_benefits(text,integer)', '54562cb0fdb87c8d3ba890bd51154bfe'),
                                ('public.fleet_job_end(uuid,jsonb)', '249dca4dbefeb161098a94821961dcbb'),
                                ('world.workers()', '65ceab73f6fe4b93f400e080897ea62a'),
                                ('public.bargain_p1(uuid,uuid,uuid,uuid)', '83b4750eec39ae7f9d28f9046dc91eca'),
                                ('public.sea_floor(uuid,jsonb)', '48e59b52da928db7a36860e1a8423af0'),
                                ('voyage.ship_speed_parts(uuid)', '1764e1c0eb2c23ec907c0d05550001d6'),
                                ('public.company_rate_line(text)', '935e4105e87d2a1dcbfd465bf68c3b3e'),
                                ('public.hq_card(uuid)', '3713aea18b20d3ee7d37ab287b54e66e'),
                                ('public.level_perk(uuid,text)', 'e2ed74ab0ff4357f02da30688baebb24'),
                                ('public.fleet_job_note(uuid,jsonb)', 'e2c6905f09415dfeadb77afe0b3f5010'),
                                ('public.fleet_jobs_due()', 'f2d229aed2876f3ae01a8bf84422e60b'),
                                ('world.good_mids(uuid)', 'e771e478c68d705091b1b6d6c981dadf')) w(fn, want)
                  cross join lateral (select md5(replace(pg_get_functiondef(to_regprocedure(w.fn)), E'', '')) as have) h
                  where h.have is distinct from w.want),
  'new_there', (select coalesce(json_agg(u.s), '[]'::json) from unnest(array['public.sea_closed(uuid,uuid)', 'voyage.happenings_on()', 'voyage.freeze_happenings(jsonb,boolean)', 'public.sea_home(uuid)', 'public.sea_passes(uuid,uuid)', 'public.sea_lies(uuid)', 'public.sea_beyond(uuid,uuid,text[])', 'public.sea_passes_lit(uuid,uuid)', 'public.seas_relit_ready()', 'public.trade_tax_cut(uuid,numeric)', 'public.job_wait_s(uuid)', 'public.job_sail_xp(uuid,uuid)', 'public.premium_lift()', 'public.premium_mult(numeric)', 'public.seas_kept(uuid)', 'voyage.happening_takes(uuid,integer,uuid,text,numeric,numeric)', 'voyage.crew_share(uuid,jsonb)', 'public.total_level(uuid)', 'public.hq_at(uuid,uuid)', 'public.hq_open_refusal(uuid,uuid)', 'world.hq_open(text)', 'cmd.open_hq(text)', 'public.seas_relit_light(text)', 'public.management_on()', 'public.passive_settings_on()', 'public.job_settings_judge(uuid,text,jsonb)', 'public.job_settings_param(uuid,jsonb)', 'public.job_settings_lines(jsonb,jsonb)', 'public.fleet_damage_pct(uuid)', 'public.job_damage_mended(uuid)', 'public.job_settings_room(uuid)', 'public.premium_on()', 'public.premium_units(uuid,uuid)', 'public.premium_left(uuid,uuid,uuid)', 'public.premium_mine(uuid,uuid)', 'public.premium_count(uuid,uuid,numeric)', 'public.premium_hold(uuid,uuid)', 'public.premium_spend(uuid,uuid,uuid,numeric)', 'public.premium_port(uuid)', 'public.premium_face(uuid)']) u(s) where to_regprocedure(u.s) is not null),
  'knobs_there', (select coalesce(json_agg(c.key), '[]'::json) from public.world_config c where c.key in ('management_level_enabled', 'trade_benefits_enabled', 'trade_tax_keep', 'seas_by_continent_at', 'happenings_bite', 'happenings_terms', 'passive_settings_enabled', 'premium_goods_enabled', 'premium_mult_near', 'premium_mult_far', 'premium_near_nm', 'premium_far_nm', 'premium_day_units', 'premium_purse_share', 'premium_price_lift')),
  'switches', (select json_object_agg(c.key, c.value) from public.world_config c where c.key in ('economy_closed', 'city_treasury_enabled', 'jobs_wait_enabled', 'wreck_sells_enabled', 'fleet_jobs_enabled', 'influence_enabled')),
  'payers', (select count(*) from public.port_treasury t where t.ducats - t.reserve >= 40000),
  'founding_room', (select coalesce(sum(floor((t.ducats - t.reserve) / 40000)), 0) from public.port_treasury t where t.ducats - t.reserve >= 40000),
  'long_tx', (select count(*) from pg_stat_activity a where a.pid <> pg_backend_pid() and a.state <> 'idle' and a.xact_start < now() - interval '4 seconds' and a.backend_type = 'client backend'),
  'seas', (select json_build_object('bite', (select c.value from public.world_config c where c.key = 'sea_conditions_bite'), 'npc', (select c.value from public.world_config c where c.key = 'sea_conditions_bite_npc'),
                     'n', count(*), 'table_md5', md5(string_agg(z.code || z.title_min || ':' || z.wave_min, ',' order by z.code))) from public.sea_zones z),
  'pair_rows', (select k.reltuples::bigint from pg_class k where k.oid = 'public.sea_leg_asks'::regclass),
  'matrix_is_harbours', (select cardinality(m.ids) from public.sea_reach_matrix m where m.id = 1) = (select count(*) from public.ports p where p.kind = 'HARBOUR'),
  'fleets_of_companies', (select count(*) from public.fleets f join public.players p on p.id = f.player_id where not p.is_npc),
  'hq', (select json_build_object('rows', count(*), 'past_first', count(*) filter (where h.slot > 1), 'moves_home', count(*) filter (where h.slot = 1 and h.port_id is distinct from public.home_port_of(h.player_id))) from public.company_hqs h),
  'steps', (select count(*) from public.hq_steps),
  'player_voyages_at_sea', (select count(*) from public.voyages v join public.players p on p.id = v.player_id and not p.is_npc where v.status = 'SAILING')
);
rollback;
