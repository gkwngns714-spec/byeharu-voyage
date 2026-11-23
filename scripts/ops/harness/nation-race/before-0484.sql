-- THE COUNTRY RACE (0484), BEFORE. A PROD CHECK: read-only, ONE statement. It carries the gate's own three figures (the arrivals beat's
-- mean over 5 minutes, the database by the catalog, the sessions waiting on the disk), so it is the builder's one prod read.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/nation-race/before-0484.sql
-- Expect: head 20260818000483; `knobs` {} (no nation_race_*); `absent` true (no public.nation_race_book / _weeks, no public.nation_race_*
-- function, no world.nation_race, no reputation kind nation_race); `anchors` 1 for each of the six hunked bodies and `new_absent` true
-- (each hunk's anchor once in prod's live body, its new text nowhere); `bodies` the md5 of the six hunked bodies (the chain's, printed
-- by the local chain).
-- THE PROBE'S SELECTIONS, as the self-assert makes them: `probe.c1` the first contested harbour by code with a purse and a good it may
-- sell there, `probe.c2` the second contested harbour, `probe.home` Portugal's first home harbour with a purse, `probe.else` the first
-- harbour with a purse Portugal does not hold, `probe.house` a house: none may be null.
-- THE WORLD THE RACE SEES: `harbours` / `contested` / `home`; `racers` the great powers that are not the pirates; `companies` the
-- companies (not merchants) by country; the switches the race reads beside its own (the purses, the closed economy, Reputation, regard,
-- influence, the board).
-- THE LOAD IT WOULD ADD, from the last 24 hours of the companies' own ledgers (by the (player_id, created_at) index, a company at a time):
-- `company_acts_24h` their sales (SELL), request bonuses (PREMIUM) and gifts and stakes (DONATION, SHARE): each is at most one upsert
-- into the race book when lit (only those in a contested harbour count). `cities_ms` the marks' one scan of the allegiance (254 rows).
-- Reads: arrivals_beats (5 minutes), pg_class, pg_stat_activity, world_config by key, the catalog (pg_proc), reputation_kinds, ports,
-- port_allegiance, port_treasury, port_goods, goods, great_powers, nations, npc_houses (one row), players (the companies), the ledger by
-- (player_id, created_at) for the companies. No function that writes is called. ROLLBACK: nothing to roll back (read only; ends with
-- rollback).
begin transaction read only;
with prt as materialized (
  select n.id from public.nations n where n.code = 'PRT'
), c1 as materialized (
  select p.code, g.code as good
    from public.port_allegiance a join public.ports p on p.id = a.port_id and p.kind = 'HARBOUR'
    join public.port_treasury t on t.port_id = p.id
   cross join lateral (select gg.code from public.port_goods pg join public.goods gg on gg.id = pg.good_id
                        where pg.port_id = p.id and gg.bulk > 0 and not public.culture_refuses(p.culture, gg.culture_mask)
                        order by gg.bulk, gg.code limit 1) g
   where not a.home
   order by p.code limit 1
), c2 as materialized (
  select p.code from public.port_allegiance a join public.ports p on p.id = a.port_id and p.kind = 'HARBOUR'
   where not a.home and p.code <> (select c1.code from c1) order by p.code limit 1
), home as materialized (
  select p.code from public.port_allegiance a join public.ports p on p.id = a.port_id and p.kind = 'HARBOUR' join public.port_treasury t on t.port_id = p.id
   where a.home and a.nation_id = (select prt.id from prt) order by p.code limit 1
), els as materialized (
  select p.code from public.port_allegiance a join public.ports p on p.id = a.port_id and p.kind = 'HARBOUR' join public.port_treasury t on t.port_id = p.id
   where a.nation_id is distinct from (select prt.id from prt) and not public.port_is_free(p.id) order by p.code limit 1
), bodies as materialized (
  select f.fn, replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as d, f.anchor, f.added
    from (values
      ('cmd.do_sell(uuid,jsonb)', '      || public.goods_mastery_sale(f.player_id, g.id, q.units)));', 'nation_race_sale'),
      ('cmd.run_fulfil(uuid,uuid)', '  perform public.level_grant(f.player_id, ''request'', v_pay);', 'nation_race_job'),
      ('public.pay_city(uuid,uuid,text,bigint,uuid)', '    perform public.city_month_post(p_player, p_port, p_kind, p_amount);', 'nation_race_gift'),
      ('public.port_fee(uuid,uuid,numeric)', '                           * public.logbook_fee_factor(p_player, p_port)))::bigint;', 'nation_fee_factor'),
      ('public.hq_board_for(uuid)', '  return jsonb_build_object(' || E'\n' || '    -- THE RANKING: the one rule (0480''s header): the band, then coin an hour, then the profit, then the id', 'nation_race_marks'),
      ('public.client_rpc_entry_points()', '      (''world'',       ''courier_contracts'',     ''''),', 'nation_race')) f(fn, anchor, added)
), t0 as materialized (
  select clock_timestamp() as t
), cities as materialized (
  select (select count(*) from (select jsonb_object_agg(p.code, true) as j
                                  from public.port_allegiance a join public.ports p on p.id = a.port_id where not a.home and p.kind = 'HARBOUR') x) as n,
         clock_timestamp() as t
    from t0
), acts as materialized (
  select l.kind, count(*) as n, coalesce(sum(l.ducats_delta), 0) as sum
    from public.players pl
   cross join lateral (select x.kind, x.ducats_delta from public.ledger x
                        where x.player_id = pl.id and x.created_at > now() - interval '24 hours'
                          and x.kind in ('SELL', 'PREMIUM', 'DONATION', 'SHARE')) l
   where not pl.is_npc
   group by l.kind
)
select jsonb_build_object(
  'at', now(),
  'gate', jsonb_build_object(
    'beat_mean_ms', (select round(avg(b.ms)) from public.arrivals_beats b where b.at > now() - interval '5 minutes'),
    'beats', (select count(*) from public.arrivals_beats b where b.at > now() - interval '5 minutes'),
    'database_mb', (select (sum(c.relpages)::numeric * 8192 / 1048576)::int from pg_class c where c.relkind in ('r', 'i', 't', 'm', 'S', 'p')),
    'io_waiting', (select count(*) from pg_stat_activity a where a.pid <> pg_backend_pid() and a.wait_event_type = 'IO' and a.state = 'active')),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'knobs', (select coalesce(jsonb_object_agg(c.key, c.value), '{}'::jsonb) from public.world_config c where c.key like 'nation\_race\_%'),
  'absent', to_regclass('public.nation_race_book') is null and to_regclass('public.nation_race_weeks') is null
            and to_regprocedure('world.nation_race()') is null
            and not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname like 'nation\_race\_%')
            and not exists (select 1 from public.reputation_kinds k where k.code = 'nation_race'),
  'anchors', (select jsonb_object_agg(b.fn, (length(b.d) - length(replace(b.d, b.anchor, ''))) / length(b.anchor)) from bodies b),
  'new_absent', (select bool_and(position(b.added in b.d) = 0) from bodies b),
  'bodies', (select jsonb_object_agg(b.fn, md5(b.d)) from bodies b),
  'probe', jsonb_build_object('c1', (select c1.code from c1), 'c1_good', (select c1.good from c1), 'c2', (select c2.code from c2),
                              'home', (select home.code from home), 'else', (select els.code from els),
                              'house', (select count(*) from public.npc_houses) > 0),
  'harbours', (select count(*) from public.port_allegiance a join public.ports p on p.id = a.port_id and p.kind = 'HARBOUR'),
  'contested', (select count(*) from public.port_allegiance a join public.ports p on p.id = a.port_id and p.kind = 'HARBOUR' where not a.home),
  'home', (select count(*) from public.port_allegiance a join public.ports p on p.id = a.port_id and p.kind = 'HARBOUR' where a.home),
  'racers', (select jsonb_agg(n.code order by n.code) from public.great_powers g join public.nations n on n.id = g.nation_id where not g.pirate),
  'companies', (select jsonb_object_agg(x.code, x.n) from (select coalesce(n.code, '-') as code, count(*) as n
                                                             from public.players pl left join public.nations n on n.id = pl.nation_id
                                                            where not pl.is_npc group by 1) x),
  'switches', (select jsonb_object_agg(c.key, c.value) from public.world_config c
                where c.key in ('city_treasury_enabled', 'economy_closed', 'reputation_on', 'regard_enabled', 'influence_enabled',
                                'hq_board_enabled', 'logbook_enabled', 'pirate_ports_free', 'port_fee_base', 'port_fee_pct')),
  'company_acts_24h', (select coalesce(jsonb_object_agg(a.kind, jsonb_build_object('rows', a.n, 'sum', a.sum)), '{}'::jsonb) from acts a),
  'cities_ms', (select round(extract(epoch from cities.t - t0.t) * 1000, 2) from cities, t0)
) as r;
rollback;
