-- STATS-ONE (0448), AFTER: every reader the Stats screen uses, and the verdict, in ONE read-only statement.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/stats-one/after.sql
-- A PROD CHECK: read-only, one statement; only STABLE functions (world.stats_fleets, world.stats_fleet_list, world.stats_merchants,
-- public.fleet_tally: provolatile 's'). It reads four stored rows and the census once (~1,300 fleets with their ships by key).
-- WANTED: ok true. `faces` is the table of docs/dev-log/2026-11-16-stats-one.md after the fix: for every kind the Ships face's card, the kind's own
--   face and (for the three lists) the rows by state, which must all be the same figures; `whole` true (fleets = sea + port + battle + laid_up +
--   wrecked, ships = ships_by); one `counted_at` for all. `now` is the live tally (public.fleet_tally) beside it: it differs from the count only
--   by what moved since `counted_at` (not part of `ok`).
begin transaction read only;
with s as (select world.stats_fleets() as v),
     st(k) as (values ('sea'), ('port'), ('battle'), ('laid_up'), ('wrecked')),
     keys(k) as (select k from st union all values ('fleets'), ('ships'), ('ships_by')),
     face as (
       select 'MERCHANT' as kind, 'merchants' as key, world.stats_merchants(null) as v
       union all
       select k.kind, k.key, world.stats_fleet_list(k.kind) from (values ('NAVY', 'navy'), ('PIRATE', 'pirates'), ('CARGO', 'cargo')) k(kind, key)),
     row_ as (
       select f.kind, f.key, f.v,
              (select jsonb_object_agg(keys.k, (select s.v from s) -> f.key -> keys.k) from keys) as card,
              (select jsonb_object_agg(keys.k, f.v -> keys.k) from keys) as own,
              case when f.kind = 'MERCHANT' then null
                   else (select jsonb_object_agg(st.k, (select count(*) from jsonb_array_elements(f.v -> 'list') e where e ->> 'state' = st.k)) from st) end as rows_by_state
         from face f)
select jsonb_build_object(
  'at', now(),
  'counted_at', (select s.v -> 'counted_at' from s),
  'faces', (select jsonb_object_agg(r.kind, jsonb_build_object(
              'ships_face_card', r.card, 'own_face', r.own, 'own_counted_at', r.v -> 'counted_at', 'list_rows_by_state', r.rows_by_state,
              'whole', (r.own ->> 'fleets')::int = (select sum((r.own ->> st.k)::int) from st)
                       and (r.own ->> 'ships')::int = (select sum((r.own -> 'ships_by' ->> st.k)::int) from st),
              'same', r.card = r.own and (r.v -> 'counted_at') = (select s.v -> 'counted_at' from s)
                      and (r.rows_by_state is null or not exists (select 1 from st where (r.rows_by_state ->> st.k)::int <> (r.own ->> st.k)::int)))) from row_ r),
  'ok', (select bool_and(r.card = r.own and (r.v -> 'counted_at') = (select s.v -> 'counted_at' from s)
                         and (r.own ->> 'fleets')::int = (select sum((r.own ->> st.k)::int) from st)
                         and (r.own ->> 'ships')::int = (select sum((r.own -> 'ships_by' ->> st.k)::int) from st)
                         and (r.rows_by_state is null or not exists (select 1 from st where (r.rows_by_state ->> st.k)::int <> (r.own ->> st.k)::int))) from row_ r),
  'now', public.fleet_tally(),
  'retired_cargo_rows', (select count(*) from public.cargo_ships c where c.laid_up_at is not null),
  'fighting_battles', (select count(*) from public.battles b where b.status = 'FIGHTING')) as r;
commit;
