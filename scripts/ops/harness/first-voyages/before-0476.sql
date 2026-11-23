-- FIRST VOYAGES (0476), BEFORE. A PROD CHECK: read-only, ONE statement, small. The gate first (db-health/gate.sql).
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/first-voyages/before-0476.sql
-- Expect: head 20260818000475 (0475, #803, deployed first); knobs {} (none of the six); table false; word false; kind false; the registry
-- hunk's OLD line once (old 1) and the new entry absent (new 0); `fn_absent` true (world.first_voyages not there yet).
-- The BASELINE for the lit window:
--   `young`        human companies founded under 7 days ago (the ones the chain would be offered), and of them `young_premium` with a
--                  request delivered already, `young_profit10k` with 10,000 of trade profit, `young_t3` at Trading 3, `young_captain` with a
--                  captain, `young_two_hulls` with two ships or a hull on order: the steps each would be paid on her first read lit
--                  (a lit read pays every met step at once, in order).
--   `hold_open`    open hold jobs with a source (the deliver step's pool); `capitals_short` capitals whose surplus is under 5,000 (a step
--                  there would ask the realm, or wait).
-- Reads: the catalog (one pg_get_functiondef), world_config by key, players (young humans), their ledger rows by ledger_player_created,
-- house_level_marks, player_officers, ships, hull_orders by player; trade_contracts open; the capitals' surplus (public.city_surplus:
-- stable). No function that writes is called.
begin transaction read only;
with h(old, new) as (values
  ('      (''world'',       ''pirate_bounties'',       ''''),' || chr(10), '''first_voyages''')
), d as (select replace(pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure), E'\r', '') as def),
young as (
  select p.id,
         exists (select 1 from public.ledger l where l.player_id = p.id and l.kind = 'PREMIUM' and l.ducats_delta > 0) as premium,
         coalesce((select sum(l.ducats_delta) from public.ledger l where l.player_id = p.id
                    and l.kind in ('BUY', 'SELL', 'TAX', 'WAGES', 'PORT_FEE', 'PROVISION', 'REQUEST_FILL')), 0) as profit,
         coalesce((select m.level from public.house_level_marks m where m.player_id = p.id and m.track = 'trading'), 1) as trading,
         (select count(*) from public.player_officers o where o.player_id = p.id) as captains,
         (select count(*) from public.ships s where s.player_id = p.id)
           + (select count(*) from public.hull_orders o where o.player_id = p.id and o.launched_at is null) as hulls
    from public.players p where not p.is_npc and p.created_at > now() - interval '7 days'
)
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'knobs', (select coalesce(jsonb_object_agg(c.key, c.value), '{}'::jsonb) from public.world_config c where c.key like 'first\_voyages\_%'),
  'table', to_regclass('public.first_voyages') is not null,
  'word', exists (select 1 from public.stats_flow_words w where w.kind = 'VOYAGE_REWARD'),
  'kind', exists (select 1 from public.reputation_kinds k where k.code = 'first_voyage'),
  'old', (select (length(d.def) - length(replace(d.def, h.old, ''))) / length(h.old) from d, h),
  'new', (select (length(d.def) - length(replace(d.def, h.new, ''))) / length(h.new) from d, h),
  'fn_absent', to_regprocedure('world.first_voyages()') is null,
  'young', (select count(*) from young),
  'young_premium', (select count(*) from young where premium),
  'young_profit10k', (select count(*) from young where profit >= 10000),
  'young_t3', (select count(*) from young where trading >= 3),
  'young_captain', (select count(*) from young where captains >= 1),
  'young_two_hulls', (select count(*) from young where hulls >= 2),
  'hold_open', (select count(*) from public.trade_contracts c where c.status = 'open' and c.size = 'hold' and c.source_port_id is not null),
  'capitals_short', (select count(*) from public.nations n join public.ports cp on cp.code = n.capital_port_code and cp.kind = 'HARBOUR'
                      where public.city_surplus(cp.id) < 5000));
rollback;
