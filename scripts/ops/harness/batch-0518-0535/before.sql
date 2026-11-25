-- BATCH 0518-0535, BEFORE. A PROD CHECK: read-only, ONE statement (begin read only ... rollback), the gate first.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/batch-0518-0535/before.sql
-- Gathers the slices' own checks (scripts/ops/harness/<slice>/), which stay the detail of each.
-- Expect: head 20260818000517; bodies_off []; new_there []; knobs_there []; tables_there 0; classes_have_profiles true; seas.n 64; seas.table_md5 49b9e399ed3e2909a6bd1c1d3034e1c0;
--   payers >= 1, founding_room >= 4 (0529's probe founds three); tar_sca not under 1030 (0531's market guard is at 0.999 of it; under, 0531 refuses); long_tx 0 (0518 holds public.fleets ACCESS EXCLUSIVE for its status check).
-- Reads: arrivals_beats (5 minutes), pg_class, pg_stat_activity, the catalog, world_config by key, small tables by count. Only STABLE functions are
--   called, none writes. The digests are of the local chain's world (PGlite, migrations to 0535).
begin transaction read only;
select json_build_object(
  'at', now(),
  'gate', json_build_object(
    'beat_mean_ms', (select round(avg(b.ms)) from public.arrivals_beats b where b.at > now() - interval '5 minutes'),
    'database_mb', (select (sum(k.relpages)::numeric * 8192 / 1048576)::int from pg_class k where k.relkind in ('r', 'i', 't', 'm', 'S', 'p')),
    'io_waiting', (select count(*) from pg_stat_activity a where a.pid <> pg_backend_pid() and a.wait_event_type = 'IO' and a.state = 'active')),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'bodies_off', (select coalesce(json_agg(json_build_object('fn', w.fn, 'have', h.have)), '[]'::json)
                   from (values ('voyage.settle(uuid,timestamp with time zone)', 'f7cabade071c42d8b769472e510cad18'),
                                ('cmd.advance(uuid,timestamp with time zone)', '189de474c2662d51d919e76fa9d3e142'),
                                ('world.ship_stat(uuid,text)', '0ececa76e5c7588b084fefb9f44c4f77'),
                                ('public.client_rpc_entry_points()', 'f7cae67b3f6f1e0d64ca0515c3edf3bf'),
                                ('public.sign_officer(uuid,text,uuid)', '3fdb50014d6f784cffd89c3b5c9c067b'),
                                ('public.fleet_job_set_for(uuid,uuid,text,jsonb)', '570e127737ed8ba9981a32efdf404f40'),
                                ('public.crew_hire_cost(uuid,integer)', 'b7e7228491fab62200e263547c4e1661'),
                                ('public.seat_captain_for(uuid,text,uuid,integer)', 'b16eef22b16048ffd470885123921d67'),
                                ('public.captain_level(uuid,text)', '8fbd4f8dce198f2b4fcc2c8be1eb9c29'),
                                ('public.sea_routes(uuid,integer,numeric,jsonb)', 'cafd5150335dd7715f33fda49154d4b9'),
                                ('public.captain_seat_put(uuid,uuid,integer)', '006013569be3a1e755070582f09ecdd0'),
                                ('public.new_house(uuid,text,text,text,text,text,text,bigint,boolean)', 'f5c84b9e9d1094fc78c7d25e42faa686'),
                                ('public.fleet_job_plan(uuid)', '12ba4230d3beb6c724f2e4a4492d065f'),
                                ('world.sea_conditions()', 'a1302112d4d3ce96389f67fae961d8a7'),
                                ('cmd.refusal_line(text,jsonb)', 'dc88d0b5857f5632f56a8a6c693237bd'),
                                ('public.fleet_census(uuid)', '3e2f70e818fb3c89340b7dfb1cb22268'),
                                ('public.land_terms(uuid,text)', 'f1df1f071e734c7386a3fb8f418535e8'),
                                ('public.land_settle(uuid,timestamp with time zone)', '08d8cba0e09c8c44ef4be4d968eca90a'),
                                ('public.land_progress(uuid,timestamp with time zone)', 'd81c33e13ffa135ce9142671cda0801b'),
                                ('public.tick_fleet_jobs(boolean)', '97b92b12ee33e6a793169e20511c1175'),
                                ('public.hq_board_for(uuid)', '22031872db57012be3d0b051a499ab56'),
                                ('public.workers_for(uuid)', '1f5b3cb1daa4dea49b5b6c4a4743c60a'),
                                ('public.fleet_job_open(uuid,jsonb)', 'e954683f9178003d17a15acf550651d6'),
                                ('public.sea_gate(uuid,uuid,uuid,jsonb)', '0413777b7685ff587b1f0d1c45c3b1c1'),
                                ('public.seas_relit_ready()', 'efbf4580f8e663d7a69aea07a7db49f5'),
                                ('public.sea_closed(uuid,uuid)', 'ad8841bac78abb0fb6256c3d5e81a9ba'),
                                ('cmd.hire_officer(text,uuid)', '8230411c8bbc4d0040c14ef024813afe'),
                                ('world.captains()', 'b98aaa7ad874c79ef05d4beca70edc5e')) w(fn, want)
                  cross join lateral (select md5(replace(pg_get_functiondef(to_regprocedure(w.fn)), E'', '')) as have) h
                  where h.have is distinct from w.want),
  'new_there', (select coalesce(json_agg(u.s), '[]'::json) from unnest(array['public.round_door(uuid,text,jsonb)', 'cmd.round_home(uuid)', 'public.captain_land_put(uuid,uuid)', 'cmd.captain_land(text,integer)', 'public.captain_land_for(uuid,text,integer)', 'public.honor_on()', 'public.honor_book_chains()', 'public.honor_reconciles()', 'public.captain_upgrades_card(uuid)', 'public.round_level(uuid,text)', 'public.round_progress(uuid,timestamp with time zone)', 'public.rounds_on()', 'public.round_clock(timestamp with time zone,numeric,timestamp with time zone,timestamp with time zone)', 'public.round_send_for(uuid,uuid,text,jsonb,timestamp with time zone)', 'public.round_stores(uuid,numeric,numeric,integer)', 'public.round_settle(uuid,timestamp with time zone)', 'public.round_home_for(uuid,uuid,timestamp with time zone)', 'public.round_settle_due(timestamp with time zone,integer)', 'public.round_plan(uuid)', 'public.round_works_for(uuid,uuid)', 'public.round_run_card(uuid)', 'cmd.round_send(uuid,text,jsonb)', 'public.ammo_on()', 'public.round_ammo_need(uuid,numeric)', 'public.round_ammo_aboard(uuid)', 'public.combat_rounds_on()', 'public.round_fights(uuid,uuid)', 'public.round_sequence(uuid,jsonb,jsonb,jsonb,timestamp with time zone)', 'public.round_hull(uuid,numeric)', 'public.round_fights_sig(uuid,uuid)', 'public.round_fights_keep(uuid,uuid,jsonb)', 'public.round_job_param(uuid,uuid,jsonb)', 'public.wrecks_yield_on()', 'public.round_spoils(uuid,integer,integer,timestamp with time zone)', 'public.expedition_rounds_on()', 'public.round_terms(uuid,text,jsonb)', 'public.artifacts_on()', 'public.round_artifacts(uuid,integer,integer)', 'public.artifact_report_for(uuid,uuid)', 'cmd.artifact_report(uuid)', 'public.round_finds(uuid,integer,integer,boolean,timestamp with time zone)', 'public.sea_refusal(integer,numeric,text[],jsonb)', 'world.rounds(uuid)', 'public.sea_stats_derive()', 'public.ship_sea_stat(uuid,text)', 'public.fleet_sea_stats(uuid)', 'public.sea_more(uuid,text[])', 'public.chart_backfill(uuid,integer)', 'public.chart_sight_nm(uuid)', 'public.chart_paint(bytea,jsonb,numeric)', 'public.chart_mark(uuid,uuid)', 'public.chart_backfill_next(integer,integer)', 'world.chart()', 'public.captain_works_on()', 'public.captain_work_level(uuid,text)', 'public.captain_work_credit(uuid,text,numeric)', 'public.captain_works_card(uuid)', 'public.captain_work_perk(uuid,text)', 'public.captain_places_on()', 'public.captain_places_count(uuid)', 'public.captain_sign_rows(uuid,uuid)', 'public.captains_found(uuid)', 'public.captain_places_full(uuid)', 'public.captain_places_card(uuid)', 'public.captain_place_for(uuid)', 'public.captain_places_light()', 'cmd.captain_place()', 'cmd.captain_dismiss(text)', 'world.land_expedition(text,jsonb)', 'public.honor_credit(uuid,text,integer,text,jsonb)', 'public.land_raids_on()', 'public.land_expedition_settle_due(timestamp with time zone,integer)', 'public.land_expedition_home_for(uuid,text,timestamp with time zone)', 'public.land_raid_crew_cap(uuid)', 'public.land_raid_party(integer,integer,numeric)', 'public.land_foe_side(text)', 'public.land_raid_terms(uuid,text,integer,uuid,uuid)', 'public.land_raid_round(jsonb,uuid,integer)', 'public.land_raid_card(jsonb)', 'public.captain_upgrade_pct(uuid,text)', 'cmd.captain_upgrade(text,text)', 'public.land_expedition_on()', 'public.land_party_out(uuid)', 'public.land_expedition_terms(uuid,uuid,jsonb,uuid)', 'public.crew_hire_cost_at(uuid,uuid,integer)', 'public.land_expedition_round(jsonb,integer)', 'public.land_expedition_stop(jsonb)', 'public.land_expedition_card(jsonb)', 'public.land_expedition_party(uuid,uuid)', 'public.land_expedition_send_for(uuid,text,jsonb,timestamp with time zone)', 'public.land_expedition_settle(uuid,timestamp with time zone)', 'cmd.land_expedition(text,jsonb)', 'public.captain_dismiss_for(uuid,text)', 'public.captain_upgrade_for(uuid,text,text)', 'public.round_seas_for(uuid)', 'public.round_log_of(uuid,integer)', 'world.round_quote(uuid,text,text,jsonb)']) u(s) where to_regprocedure(u.s) is not null),
  'knobs_there', (select coalesce(json_agg(c.key), '[]'::json) from public.world_config c where c.key in ('captain_work_forage', 'captain_places_enabled', 'honor_enabled', 'honor_upgrade_base', 'land_wood_enabled', 'land_raids_enabled', 'land_raid_crew_share', 'land_crew_cap', 'land_expedition_enabled', 'land_works_are_no_fleets', 'land_crew_carry', 'land_round_stores', 'land_round_stores_crew', 'land_raid_march_s', 'rounds_enabled', 'round_away_hours', 'ammo_enabled', 'chart_fog_enabled', 'chart_sight_nm', 'combat_rounds_enabled', 'round_hull_stop', 'round_hand_share', 'wrecks_yield_enabled', 'captain_works_enabled', 'captain_work_time_pct', 'expedition_rounds_enabled', 'captain_work_time_most', 'captain_work_crew_pct', 'artifacts_enabled', 'artifact_tiers', 'captain_work_crew_most', 'round_far_legs')),
  'switches', (select json_object_agg(c.key, c.value) from public.world_config c where c.key in ('economy_closed', 'city_treasury_enabled', 'jobs_wait_enabled', 'wreck_sells_enabled', 'fleet_jobs_enabled', 'influence_enabled')),
  'payers', (select count(*) from public.port_treasury t where t.ducats - t.reserve >= 40000),
  'founding_room', (select coalesce(sum(floor((t.ducats - t.reserve) / 40000)), 0) from public.port_treasury t where t.ducats - t.reserve >= 40000),
  'long_tx', (select count(*) from pg_stat_activity a where a.pid <> pg_backend_pid() and a.state <> 'idle' and a.xact_start < now() - interval '4 seconds' and a.backend_type = 'client backend'),
  'tables_there', (select count(*) from pg_class k where k.relnamespace = 'public'::regnamespace and k.relname in ('round_fights_kept', 'sea_stats_item', 'fleet_artifacts', 'sea_stats_class', 'round_works', 'company_chart', 'captain_works', 'round_runs', 'captain_work_xp', 'captain_places', 'honor_kinds', 'captain_places_open', 'honor_book', 'honor_balance', 'land_foes', 'captain_upgrade_kinds', 'captain_upgrades')),
  'seas', (select json_build_object('bite', (select c.value from public.world_config c where c.key = 'sea_conditions_bite'), 'n', count(*), 'table_md5', md5(string_agg(z.code || z.title_min || ':' || z.wave_min, ',' order by z.code))) from public.sea_zones z),
  'classes_have_profiles', (select count(*) from public.ship_classes) = (select count(*) from public.class_profile),
  'fleets', (select k.reltuples::bigint from pg_class k where k.oid = 'public.fleets'::regclass),
  'fleets_of_companies', (select count(*) from public.fleets f join public.players p on p.id = f.player_id where not p.is_npc),
  'captains_a_company', (select json_object_agg(z.n, z.c) from (select y.n, count(*) as c from (select count(po.id) as n from public.players p left join public.player_officers po on po.player_id = p.id where not p.is_npc group by p.id) y group by y.n) z),
  'land_parties', (select count(*) from public.land_parties),
  'tar_sca', (select percentile_disc(0.5) within group (order by coalesce(pg.base_target, pg.stock_target) * least(1, coalesce((select (c.value #>> '{}')::numeric from public.world_config c where c.key = 'depth_m0'), 1)))
     from public.goods g cross join unnest(g.origin_regions) o(rc) join public.regions rg on rg.code = o.rc join public.ports p on p.region_id = rg.id and p.kind = 'HARBOUR' join public.port_goods pg on pg.port_id = p.id and pg.good_id = g.id where g.code = 'tar' and rg.code = 'SCA')
);
rollback;
