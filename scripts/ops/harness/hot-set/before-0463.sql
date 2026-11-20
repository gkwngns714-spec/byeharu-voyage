-- 0463 PROD CHECK, BEFORE the deploy (the same read as the after-0463.sql), read-only, ONE statement (run db-health/gate.sql first: gate_ok true):
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/hot-set/before-0463.sql
-- Reads the catalog, pg_stat_user_tables, the compactor's receipt ring (public.compact_runs: 1,440 rows at most) and the live body of public.tick_compact. No game table is scanned.
-- BEFORE, wanted: head 20260818000461 (or 0462 if queued ahead); applied false; hunks[] old 1 new 0 for both; the compactor's receipt `left` 0 and `due` ~7-12 a minute (the ledger alone).
begin transaction read only;
with tc as (select replace(pg_get_functiondef('public.tick_compact(boolean,boolean)'::regprocedure), E'', '') as d),
     h(i, old, new) as (values
  (1, $h$THE DUE HOUSES: a merchant
-- whose oldest ledger row awaiting a roll (her NPC_CARRIED row skipped) is over c_due past the cut, oldest
-- first. A BATCH$h$, $h$THE DUE HOUSES (0463): a merchant
-- whose oldest row awaiting a cut, her oldest ledger row (her NPC_CARRIED row skipped) or her oldest ended voyage, whichever is
-- older, is over c_due past the cut, oldest first (a house with no ledger, a navy or pirate fleet, was never due before 0463).
-- A BATCH$h$),
  (2, $h$      from (select p.id, (select min(l.created_at) from public.ledger l
                           where l.player_id = p.id and l.kind <> 'NPC_CARRIED') as m
              from public.players p where p.is_npc) x
$h$, $h$      from (select p.id, least(
                     (select min(l.created_at) from public.ledger l
                       where l.player_id = p.id and l.kind <> 'NPC_CARRIED'),
                     -- 0463: her oldest ended voyage (voyages_fleet_ended_0249: one ordered probe a fleet, limit 1)
                     (select min(w.eta) from public.fleets f
                        cross join lateral (select v.eta from public.voyages v
                                             where v.fleet_id = f.id and v.status <> 'SAILING'
                                             order by v.eta limit 1) w
                       where f.player_id = p.id)) as m
              from public.players p where p.is_npc) x
$h$))
select jsonb_build_object(
  'at', now(),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'applied', (select position('-- 0463:' in d) > 0 from tc),
  'hunks', (select jsonb_agg(jsonb_build_object('hunk', h.i, 'old', (length(tc.d) - length(replace(tc.d, h.old, ''))) / length(h.old),
                                                'new', (length(tc.d) - length(replace(tc.d, h.new, ''))) / length(h.new)) order by h.i) from h, tc),
  'knobs', (select jsonb_object_agg(c.key, c.value) from public.world_config c where c.key in ('compact_budget_ms', 'compact_hold_ms', 'compact_batch_max', 'npc_retention_hours')),
  'recent_runs', (select jsonb_agg(jsonb_build_object('at', r.at, 'ms', r.ms, 'due', r.receipt->'due', 'houses', r.receipt->'houses', 'left', r.receipt->'left',
                                                      'voyages', r.receipt->'voyages', 'events', r.receipt->'events', 'oldest', r.receipt->'oldest') order by r.at desc)
                   from (select * from public.compact_runs order by at desc limit 6) r),
  'tables', (select jsonb_agg(jsonb_build_object('t', c.relname, 'mb', ((c.relpages + coalesce((select sum(ic.relpages) from pg_index i join pg_class ic on ic.oid = i.indexrelid where i.indrelid = c.oid), 0))::numeric * 8192 / 1048576)::int,
                                                 'live', s.n_live_tup, 'dead', s.n_dead_tup, 'last_av', s.last_autovacuum) order by c.relname)
               from pg_class c join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
               left join pg_stat_user_tables s on s.relid = c.oid
              where c.relkind = 'r' and c.relname in ('voyages', 'voyage_events', 'events', 'insured_voyages')),
  'db_mb', (select (sum(c.relpages)::numeric * 8192 / 1048576)::int from pg_class c where c.relkind in ('r', 'i', 't', 'm', 'S', 'p')),
  'beat', (select jsonb_build_object('beats', count(*), 'mean_ms', round(avg(b.ms))) from public.arrivals_beats b where b.at > now() - interval '5 minutes')
) as r;
commit;
