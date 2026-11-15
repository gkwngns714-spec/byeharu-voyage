-- 0445 DESIGN READ (taken once, 2026-11-15, before the migration was cut), read-only, ONE statement, stable functions only:
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/pirates-at-sea/design.sql
-- The pirates' homes and the stored lanes round them (public.npc_courses by its primary key from each of the ~8 homes), the trade switch, and
-- how long a raid lasts (the raids of the last hour). No big table is scanned.
begin transaction read only;
with homes as (
  select n.home_port, count(*) as fleets, coalesce((select hb.reach_nm from public.pirate_hubs hb where hb.port_id = n.home_port), public.wc_num('navy_reach_nm')) as reach
    from public.pirate_ships n where n.laid_up_at is null group by n.home_port
), h as (
  select m.home_port, c.to_port, c.nm
    from homes m join public.npc_courses c on c.from_port = m.home_port and c.nm <= m.reach
    join public.ports p on p.id = c.to_port and p.kind = 'HARBOUR'
   where exists (select 1 from public.npc_courses b where b.from_port = c.to_port and b.to_port = m.home_port)
     and not exists (select 1 from public.port_allegiance a join public.great_powers g on g.nation_id = a.nation_id where a.port_id = p.id and a.home and g.pirate)
)
select jsonb_build_object(
  'at', now(),
  'knobs', (select jsonb_object_agg(k.key, k.value) from public.world_config k
             where k.key in ('pirates_trade', 'tick_fight', 'battle_seconds', 'pirate_respawn_minutes', 'navy_hunt_hours', 'pirate_pressure', 'pirate_pressure_max', 'npc_refit_enabled')),
  'homes', (select jsonb_agg(jsonb_build_object('home', po.code, 'fleets', m.fleets, 'reach', m.reach,
                                                'haunts', (select count(*) from h where h.home_port = m.home_port),
                                                'nm_p50', (select round((percentile_cont(0.5) within group (order by h.nm))::numeric) from h where h.home_port = m.home_port),
                                                'nm_max', (select round(max(h.nm)) from h where h.home_port = m.home_port),
                                                'pairs', (select count(*) from h a join h b on b.home_port = a.home_port and b.to_port <> a.to_port
                                                           where a.home_port = m.home_port),
                                                'pairs_direct', (select count(*) from h a join h b on b.home_port = a.home_port and b.to_port <> a.to_port
                                                                   join public.npc_courses c on c.from_port = a.to_port and c.to_port = b.to_port
                                                                  where a.home_port = m.home_port),
                                                'direct_nm_p50', (select round((percentile_cont(0.5) within group (order by c.nm))::numeric)
                                                                    from h a join h b on b.home_port = a.home_port and b.to_port <> a.to_port
                                                                    join public.npc_courses c on c.from_port = a.to_port and c.to_port = b.to_port
                                                                   where a.home_port = m.home_port)) order by m.fleets desc)
              from homes m join public.ports po on po.id = m.home_port),
  'courses', (select count(*) from public.npc_courses),
  'cargo_aboard', (select count(*) from public.pirate_ships n where n.laid_up_at is null
                    and exists (select 1 from public.ships s where s.fleet_id = n.fleet_id and s.cargo <> '{}'::jsonb)),
  'hull', (select jsonb_build_object('ships', count(*), 'p10', round((percentile_cont(0.1) within group (order by s.durability))::numeric), 'p50', round((percentile_cont(0.5) within group (order by s.durability))::numeric), 'max', round(max(s.durability)::numeric))
             from public.pirate_ships n join public.ships s on s.fleet_id = n.fleet_id where n.laid_up_at is null),
  'raid_seconds', (select jsonb_build_object('n', count(*), 'p50', round((percentile_cont(0.5) within group (order by extract(epoch from x.resolves_at - x.started_at)))::numeric),
                                             'max', round(max(extract(epoch from x.resolves_at - x.started_at))::numeric))
                     from public.battles x where x.kind = 'RAID' and x.status <> 'FIGHTING' and x.started_at > now() - interval '1 hour')
) as r;
commit;
