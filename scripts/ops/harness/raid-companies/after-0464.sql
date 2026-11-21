-- PROD CHECK (read only) after 0464 (pirates raid companies too): public.raid_target carries both NEW texts once and 0432's order line no more;
-- it is still stable, definer and server only; the three knobs are 0464's (DARK until the owner lights raid_companies_enabled); the receipt is
-- recorded. THE MEASURE (run again 30 min and 24 h after the owner lights it): raids since the given hour, on a company's ship, and each such
-- raid's company title (under Master must be 0). Calls only stable functions. One statement.
begin transaction read only;
with b as (select replace(p.prosrc, E'\r', '') as s from pg_proc p where p.oid = to_regprocedure('public.raid_target(uuid,timestamp with time zone)')),
     h(k, t) as (values
       ('new1', $h$  v_lit   boolean := coalesce(public.wc('raid_companies_enabled') = 'true'::jsonb, false);$h$),
       ('new2', $h$     order by case when v_lit then false else public.fleet_kind(c.id) = 'COMPANY' end,$h$),
       ('old2', $h$     order by public.fleet_kind(c.id) = 'COMPANY', c.nm, c.id$h$))
select md5(replace(pg_get_functiondef(to_regprocedure('public.raid_target(uuid,timestamp with time zone)')), E'\r', '')) as md5,   -- want b360c71247f1402f6db88f1381125237 (local cached chain, 2026-11-22)
       (select jsonb_object_agg(h.k, (length(b.s) - length(replace(b.s, h.t, ''))) / length(h.t)) from h, b) as hunks,                     -- want {"new1": 1, "new2": 1, "old2": 0}
       (select p.provolatile = 's' and p.prosecdef and not has_function_privilege('authenticated', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute')
          from pg_proc p where p.oid = to_regprocedure('public.raid_target(uuid,timestamp with time zone)')) as stable_server_only,           -- want true
       (select jsonb_object_agg(w.key, w.value) from public.world_config w
         where w.key in ('raid_companies_enabled', 'raid_company_title_min', 'raid_company_weight')) as knobs,                                -- want false (until lit), 3, 1
       (select count(*) from public.battles x where x.kind = 'RAID' and x.started_at > now() - interval '1 hour') as raids_1h,
       (select jsonb_build_object('raids', count(*), 'under_master', count(*) filter (where coalesce(public.title_level(p.id), 99) < 3))
          from public.battles x join public.battle_sides s on s.battle_id = x.id and s.side = 'DEFENDER' and s.how = 'OPENED'
          join public.fleets f on f.id = s.fleet_id join public.players p on p.id = f.player_id
         where x.kind = 'RAID' and x.started_at > now() - interval '1 hour' and not p.is_npc) as on_companies_1h,                               -- dark: 0; lit: under_master 0
       (select max(version) from supabase_migrations.schema_migrations) as head;                                                             -- want 20260818000464
commit;
