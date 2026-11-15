-- STATS-ONE (0448), BEFORE: every reader the Stats screen uses, beside the live tables, in ONE read-only statement.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/stats-one/before.sql
-- A PROD CHECK: read-only, one statement; only STABLE functions (world.stats_fleets, world.stats_fleet_list, world.stats_merchants,
-- world.stats_now, public.stats_merchant_fleets, public.stats_fleets_count: each provolatile 's' on prod 2026-11-15). It reads the four small
-- ship tables (~1,300 rows), their fleets and ships by key, and the stored Stats rows. Run it ONCE (it was run on 2026-11-15 16:25 UTC, head 0446:
-- docs/dev-log/2026-11-16-stats-one.md has its table). `live_cells` is every fleet by kind, status and the facts the old rules read. After the
-- deploy run after.sql instead: the Merchants face no longer serves the keys this file's reading of it expects.
begin transaction read only;
with live as (
  select k.kind, f.status, k.laid, k.wreck, coalesce(s.alive, false) as alive, coalesce(s.ships, 0) as ships,
         (f.id in (select bs.fleet_id from public.battles b join public.battle_sides bs on bs.battle_id = b.id where b.status = 'FIGHTING')) as fighting
    from (select 'MERCHANT' as kind, nf.fleet_id, coalesce(r.paused_reason = 'laid_up', false) as laid, false as wreck
            from public.npc_fleets nf left join public.standing_routes r on r.id = nf.route_id
          union all select 'NAVY', n.fleet_id, n.laid_up_at is not null, false from public.navy_ships n
          union all select 'PIRATE', p.fleet_id, p.laid_up_at is not null, p.wrecked_at is not null from public.pirate_ships p
          union all select 'CARGO', c.fleet_id, c.laid_up_at is not null, false from public.cargo_ships c) k
    join public.fleets f on f.id = k.fleet_id
    left join lateral (select count(*)::int as ships, bool_or(x.durability > 0) as alive from public.ships x where x.fleet_id = k.fleet_id) s on true),
tabs as (select k.kind, world.stats_fleet_list(k.kind) as v from (values ('NAVY'), ('PIRATE'), ('CARGO')) k(kind))
select jsonb_build_object(
  'at', now(),
  'live_cells', (select jsonb_agg(to_jsonb(z)) from (select l.kind, l.status, l.laid, l.wreck, l.alive, l.fighting, count(*) as fleets, sum(l.ships) as ships
                                                       from live l group by 1, 2, 3, 4, 5, 6 order by 1, 2, 3, 4, 5, 6) z),
  'ships_tab', (select jsonb_build_object('counted_at', v ->> 'counted_at', 'merchants', v -> 'merchants', 'navy', (v -> 'navy') - 'nations',
                                          'pirates', (v -> 'pirates') - 'homes', 'cargo', v -> 'cargo') from (select world.stats_fleets() as v) x),
  'tabs', (select jsonb_object_agg(t.kind, (t.v - 'list' - 'day' - 'week') || jsonb_build_object(
             'rows', jsonb_array_length(t.v -> 'list'),
             'rows_by_state', (select jsonb_object_agg(z.st, jsonb_build_array(z.n, z.ships))
                                 from (select e ->> 'state' as st, count(*) as n, sum((e ->> 'ships')::int) as ships from jsonb_array_elements(t.v -> 'list') e group by 1) z))) from tabs t),
  'merchants_tab', (select v - 'list' - 'series' - 'top' - 'bottom' || jsonb_build_object('list_rows', jsonb_array_length(v -> 'list'),
                             'list_fleets', (select sum((e ->> 3)::int) from jsonb_array_elements(v -> 'list') e)) from (select world.stats_merchants(null) as v) x),
  'merchant_fleets_live', public.stats_merchant_fleets(),
  'stats_merchants_row', (select jsonb_build_object('at', m.at, 'fleets', m.fleets, 'sailing', m.sailing, 'docked', m.docked, 'repairing', m.repairing, 'unable', m.unable, 'laid_up', m.laid_up)
                            from public.stats_merchants m order by m.slot desc limit 1),
  'count_live', (select jsonb_build_object('merchants', v -> 'merchants', 'navy', (v -> 'navy') - 'nations', 'pirates', (v -> 'pirates') - 'homes', 'cargo', v -> 'cargo')
                   from (select public.stats_fleets_count(now(), now()) as v) x),
  'now', (select jsonb_build_object('at_sea', v -> 'at_sea', 'at_sea_merchants', v -> 'at_sea_merchants', 'counted_at', v -> 'counted_at', 'cargo_ships', v -> 'cargo_ships',
                                    'cargo_at_sea', v -> 'cargo_at_sea', 'keys', (select jsonb_agg(k) from jsonb_object_keys(v) k)) from (select world.stats_now() as v) x),
  'fighting_battles', (select count(*) from public.battles b where b.status = 'FIGHTING')) as r;
commit;
