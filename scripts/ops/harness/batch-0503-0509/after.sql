-- BATCH 0503-0509, AFTER. A PROD CHECK: read-only, ONE statement (begin read only ... rollback), the gate first.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/batch-0503-0509/after.sql
-- Gathers the slices' own checks (scripts/ops/harness/<slice>/), which stay the detail of each.
-- Expect: head 20260818000509; bodies_off []; missing []; knobs_off []; reach []; doors true; name_index true where case_twins was 0;
--   renames.over_free 0 ALWAYS; charts 0; rates_md5 = the before file's; stores_separate true, graced 0; hq.rows = hq.companies (less a
--   company with no country capital and no founding port), merchants 0, no_harbour 0, steps 5; closed 0.
--   The 30-minute check is this file again (0503's name rule and 0509's HQ row are live with no switch), with the gate.
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
                   from (values ('voyage.settle(uuid,timestamp with time zone)', '9341f218f7095618f0d66bf3df06f7f9'),
                                ('public.run_day(uuid,uuid,uuid,uuid,uuid,numeric,numeric,numeric,numeric,numeric)', '9a6e97028bdf70a13868c3368017c194'),
                                ('cmd.do_buy(uuid,jsonb)', '6772cad2c8ef4c3d9ef7ffb6dcdb5e72'),
                                ('cmd.haggle(uuid,uuid,text)', 'f6a2d7a58bcf825c6e8def8e350e5880'),
                                ('public.client_rpc_entry_points()', '9a5ef69fcb9ce215d758e60fe393b52e'),
                                ('cmd.do_sell(uuid,jsonb)', '18fff22b5f80d5d649cad174c624a55f'),
                                ('world.town_hall(uuid)', 'c0d5b62a724a84e287d4cf5c8b1c2ea6'),
                                ('public.fleet_job_set_for(uuid,uuid,text,jsonb)', 'da1a0d55c91cd239539f4ebaff048b10'),
                                ('public.haggle_odds(uuid,uuid,uuid,uuid)', '8fcf384d9b7815fdf4a3560c8b755241'),
                                ('world.quote_priced(uuid,uuid,numeric,text,numeric,uuid,numeric,numeric,numeric,numeric)', '0e837b48ff97d74c5392ce9633a1f91f'),
                                ('cmd.found_house(text,text)', '234bc83b157260f14882161010092fcc'),
                                ('world.stats_me()', '89a970f50a64c256b83a668a8aaca540'),
                                ('public.town_hall_gifts(uuid)', 'af29dc8c90e459274b1f199b6b380000'),
                                ('public.new_house(uuid,text,text,text,text,text,text,bigint,boolean)', 'f5c84b9e9d1094fc78c7d25e42faa686'),
                                ('world.city_history(uuid,integer)', '632bb0f964eafd4e91b1e2e7c2138b5f'),
                                ('public.home_port_of(uuid)', '79c042731f5f9fc5381d369b89ad138a'),
                                ('public.flow_is_profit(text)', 'd8112860e2455a7b4b42e82f8ef7f8fc'),
                                ('public.ledger_is_earning(text)', '3b3f45a46443e277ca684a697995fdfd'),
                                ('world.tax_rate(uuid,uuid)', '9a9da687b6ad125df2f1bc9715d9382e'),
                                ('public.fleet_job_plan(uuid)', '3314a40c43244545443b5450fc1d4703'),
                                ('public.ship_stores_room(uuid,numeric)', 'c45f4e47330dc83982b98e05d81c2cc6'),
                                ('public.level_skills_card(uuid,jsonb)', '49b1006b9163ba8fad5cd59376b2af88'),
                                ('world.spread_pair_from(uuid,uuid,uuid,boolean,numeric[],numeric)', '8657099742301c76a50d9a99d125b69a'),
                                ('public.fleet_run_quote(uuid,uuid,uuid,text,text,text[])', 'af48eb64101d73e877567ccfd9c2d1ee'),
                                ('cmd.set_tax(uuid,numeric)', '2b4dbc2e2ed1f66881dad48292d30a32'),
                                ('world.haggle_state(uuid,uuid)', '1d73a68e9e25c55c073323c87ba30009'),
                                ('public.settle_standings(timestamp with time zone)', 'c590e7f29fdf4319c23077819f5afa87'),
                                ('world.player()', '639935dc5f5c0234f95033c35147a5c2'),
                                ('public.company_rename_free(integer)', '8edef1a53a667e4ac585426ac866ced8'),
                                ('public.rename_company(uuid,text)', 'd2a51d3cf3caae0382f74460bb8021d9'),
                                ('public.company_name_refusal(text,uuid)', '770ebcbdeba3f8130a96e975097c98cf'),
                                ('cmd.rename_company(text)', 'd925fc54f28629857b039a86a4ea6aa9'),
                                ('public.chart_sight_nm(uuid)', '02b27df86e6a293a08f1c379837ecb0c'),
                                ('public.tax_cap()', 'b1429b243eeab521a0816e0cf083c976'),
                                ('public.tax_home_half(uuid,uuid,numeric,numeric)', 'e4f27883a61ed55603b8df7d910207e1'),
                                ('public.bargain_side_refusal(uuid,uuid,uuid,text)', '6eb294c62c20017a7aefcc7ac571bc63'),
                                ('public.bargain_p1(uuid,uuid,uuid,uuid)', '83b4750eec39ae7f9d28f9046dc91eca'),
                                ('public.bargain_odds(uuid,uuid,uuid,uuid)', 'f1e7ab41f400d36e6047ea75497fdedd'),
                                ('public.bargain_actor()', '5ce5243869ff8a8cce5cabc00d4b6c4b'),
                                ('public.bargain_xp(uuid,boolean)', '74491ae1cc349838fdb0867deae284bc'),
                                ('public.job_bargain_tries(uuid)', '964a3026d236e5c22245915777e114a8'),
                                ('public.nation_in_europe(uuid)', 'dd65210fc5bd876b30cf76a36bffdfdd'),
                                ('public.hq_card(uuid)', '3713aea18b20d3ee7d37ab287b54e66e'),
                                ('public.company_heir(uuid)', 'a5ded8d04055f3f129e0c41783cade38'),
                                ('public.chart_paint(bytea,jsonb,numeric)', '306fa04cf67e82ec0e538bb40b9c5bfb'),
                                ('public.chart_backfill(uuid,integer)', 'c19440ebaf3ab8df51587d8953fe3b06'),
                                ('public.chart_mark(uuid,uuid)', 'f4add0ec183e750c700da880d76e617f'),
                                ('public.chart_backfill_next(integer,integer)', '5179e109ee690e8d1278f86153fb6ae6'),
                                ('world.chart()', 'd9343f61d4116a2609cf18a549e2d5e2'),
                                ('public.tax_thirty_on()', 'e64bbc3a353bcf48887a46564e5e5a66'),
                                ('public.bargain_on()', 'e4e1bb1114c7a315770f3dc2aee5c321'),
                                ('public.haggle_attempts_max()', 'fbff182611eacb843033922a93c8cc75'),
                                ('public.haggle_step()', 'ceb212c336ae47ac557ed7a4ccef16a3'),
                                ('public.haggle_cap()', 'ad1200df66d6269eb815a3ef1dca8951'),
                                ('public.job_bargain(uuid,uuid,text)', '7e6a6e1aa64eb6d74cb00b6c3e40e101'),
                                ('public.job_bargain_param(jsonb)', '4c7a2eb943436dd994487570641b37a3'),
                                ('public.bargain_factor(uuid,uuid,uuid,text)', '96c243d94ad7c034a06c0f5fd6b6e1eb'),
                                ('public.bargain_state(uuid,uuid,uuid,uuid)', 'c3a18b417d2cac7bedf7ca7086d2a2a0'),
                                ('public.bargain_first(uuid,uuid,uuid,text,numeric,numeric)', 'a485db15053c3830b9c7728019746f16'),
                                ('public.buy_tax_on()', '2ea7858f94bbcafaa66a82aa9a3e6c48'),
                                ('public.buy_tax_rate(uuid,uuid)', '02caa3bb1356e699df418cbfd8a206d8'),
                                ('public.ship_hold_over(uuid)', '1149c2f68e7d2ad25687afe8831109c0'),
                                ('public.fleet_trip_stores(uuid,uuid,text[])', '8b3b4cde16fdc4b0a01d745f3ef0aa1b'),
                                ('public.stores_in_hold_ready()', 'cccb8ec46cf2a99e995e5e34e61d86bc'),
                                ('public.stores_in_hold_light()', '5175ea8f66536971c3f398e9882c01f8'),
                                ('public.restart_on()', '1f7c2b43cc5895cf45a4b35e7de84cfb'),
                                ('public.hq_cities_on()', '7443e076cd007169e0ce61e190b8ff04'),
                                ('public.restart_refusal(uuid,timestamp with time zone)', '2e2a6d7b047660db9f88d87819565745'),
                                ('public.restart_card(uuid)', 'c244bb62e8088d83687c100cec18343c'),
                                ('public.company_retire(uuid,timestamp with time zone)', 'e951c6d230e6c7372a7dd0ffba8f3915'),
                                ('cmd.restart_company(text,text,text)', '4221dc6c52adb8f5a943985dbd8fd021')) w(fn, want)
                  cross join lateral (select md5(replace(pg_get_functiondef(to_regprocedure(w.fn)), E'', '')) as have) h
                  where h.have is distinct from w.want),
  'missing', (select coalesce(json_agg(u.s), '[]'::json) from unnest(array['public.company_rename_free(integer)', 'public.rename_company(uuid,text)', 'public.company_name_refusal(text,uuid)', 'cmd.rename_company(text)', 'public.chart_sight_nm(uuid)', 'public.tax_cap()', 'public.tax_home_half(uuid,uuid,numeric,numeric)', 'public.bargain_side_refusal(uuid,uuid,uuid,text)', 'public.bargain_p1(uuid,uuid,uuid,uuid)', 'public.bargain_odds(uuid,uuid,uuid,uuid)', 'public.bargain_actor()', 'public.bargain_xp(uuid,boolean)', 'public.job_bargain_tries(uuid)', 'public.nation_in_europe(uuid)', 'public.hq_card(uuid)', 'public.company_heir(uuid)', 'public.chart_paint(bytea,jsonb,numeric)', 'public.chart_backfill(uuid,integer)', 'public.chart_mark(uuid,uuid)', 'public.chart_backfill_next(integer,integer)', 'world.chart()', 'public.tax_thirty_on()', 'public.bargain_on()', 'public.haggle_attempts_max()', 'public.haggle_step()', 'public.haggle_cap()', 'public.job_bargain(uuid,uuid,text)', 'public.job_bargain_param(jsonb)', 'public.bargain_factor(uuid,uuid,uuid,text)', 'public.bargain_state(uuid,uuid,uuid,uuid)', 'public.bargain_first(uuid,uuid,uuid,text,numeric,numeric)', 'public.buy_tax_on()', 'public.buy_tax_rate(uuid,uuid)', 'public.ship_hold_over(uuid)', 'public.fleet_trip_stores(uuid,uuid,text[])', 'public.stores_in_hold_ready()', 'public.stores_in_hold_light()', 'public.restart_on()', 'public.hq_cities_on()', 'public.restart_refusal(uuid,timestamp with time zone)', 'public.restart_card(uuid)', 'public.company_retire(uuid,timestamp with time zone)', 'cmd.restart_company(text,text,text)']) u(s) where to_regprocedure(u.s) is null),
  'reach', (select coalesce(json_agg(u.s), '[]'::json) from unnest(array['public.company_rename_free(integer)', 'public.rename_company(uuid,text)', 'public.company_name_refusal(text,uuid)', 'cmd.rename_company(text)', 'public.chart_sight_nm(uuid)', 'public.tax_cap()', 'public.tax_home_half(uuid,uuid,numeric,numeric)', 'public.bargain_side_refusal(uuid,uuid,uuid,text)', 'public.bargain_p1(uuid,uuid,uuid,uuid)', 'public.bargain_odds(uuid,uuid,uuid,uuid)', 'public.bargain_actor()', 'public.bargain_xp(uuid,boolean)', 'public.job_bargain_tries(uuid)', 'public.nation_in_europe(uuid)', 'public.hq_card(uuid)', 'public.company_heir(uuid)', 'public.chart_paint(bytea,jsonb,numeric)', 'public.chart_backfill(uuid,integer)', 'public.chart_mark(uuid,uuid)', 'public.chart_backfill_next(integer,integer)', 'world.chart()', 'public.tax_thirty_on()', 'public.bargain_on()', 'public.haggle_attempts_max()', 'public.haggle_step()', 'public.haggle_cap()', 'public.job_bargain(uuid,uuid,text)', 'public.job_bargain_param(jsonb)', 'public.bargain_factor(uuid,uuid,uuid,text)', 'public.bargain_state(uuid,uuid,uuid,uuid)', 'public.bargain_first(uuid,uuid,uuid,text,numeric,numeric)', 'public.buy_tax_on()', 'public.buy_tax_rate(uuid,uuid)', 'public.ship_hold_over(uuid)', 'public.fleet_trip_stores(uuid,uuid,text[])', 'public.stores_in_hold_ready()', 'public.stores_in_hold_light()', 'public.restart_on()', 'public.hq_cities_on()', 'public.restart_refusal(uuid,timestamp with time zone)', 'public.restart_card(uuid)', 'public.company_retire(uuid,timestamp with time zone)', 'cmd.restart_company(text,text,text)']) u(s)
             where has_function_privilege('anon', to_regprocedure(u.s), 'execute') or has_function_privilege('service_role', to_regprocedure(u.s), 'execute')
                or (u.s like 'public.%' and has_function_privilege('authenticated', to_regprocedure(u.s), 'execute'))),
  'knobs_off', (select coalesce(json_agg(json_build_object('key', w.key, 'have', c.value)), '[]'::json)
                  from (values ('chart_fog_enabled', 'false'), ('chart_sight_nm', '150'), ('tax_thirty_enabled', 'false'), ('tax_rate_cap', '0.30'), ('home_tax_cut', '0.5'), ('restart_enabled', 'false'), ('buy_tax_enabled', 'false'), ('buy_tax_share', '0.1'), ('bargain_total_enabled', 'false'), ('bargain_attempts', '10'), ('bargain_step', '0.05'), ('bargain_p1_base', '0.25'), ('bargain_p1_max', '0.50'), ('bargain_decay', '0.5'), ('hq_cities_enabled', 'false'), ('buy_tax_max', '0.03')) w(key, want)
                  left join public.world_config c on c.key = w.key where c.value is distinct from w.want::jsonb),
  'doors', has_function_privilege('authenticated', 'cmd.rename_company(text)', 'execute') and has_function_privilege('authenticated', 'world.chart()', 'execute')
           and has_function_privilege('authenticated', 'cmd.restart_company(text,text,text)', 'execute'),
  'name_index', to_regclass('public.players_company_name_lower_key') is not null,
  'renames', (select json_build_object('used', count(*) filter (where p.renames > 0), 'over_free', count(*) filter (where p.renames > 1)) from public.players p),
  'charts', (select count(*) from public.company_chart),
  'rates_md5', (select md5(string_agg(h.code || ':' || world.tax_rate(h.id)::text, ',' order by h.code)) from public.ports h where h.kind = 'HARBOUR'),
  'stores_separate', (select c.value from public.world_config c where c.key = 'ship_stores_separate'),
  'graced', (select count(*) from public.ships s where s.hold_grace_until is not null),
  'hq', (select json_build_object('companies', (select count(*) from public.players p where not p.is_npc and p.retired_at is null), 'rows', count(*) filter (where h.slot = 1),
                                  'merchants', count(*) filter (where p.is_npc), 'no_harbour', count(*) filter (where z.kind is distinct from 'HARBOUR'), 'steps', (select count(*) from public.hq_steps))
           from public.company_hqs h join public.players p on p.id = h.player_id left join public.ports z on z.id = h.port_id),
  'closed', (select count(*) from public.players p where p.retired_at is not null)
);
rollback;
