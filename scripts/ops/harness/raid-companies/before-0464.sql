-- PROD CHECK (read only) before 0464 (pirates raid companies too): public.raid_target is the chain's at 0462 (0427's body with 0432's two hunks):
-- each OLD text of 0464's two hunks once, the NEW texts 0 times; no 0464 knob yet; and THE MEASURE before: raids in the last 48 h (raid_keep_hours)
-- and how many were on a company's ship, company hours at sea in the same 48 h, and how many companies stand at or over Master (title 3).
-- Calls only stable functions (public.title_level, once per human company: 19 on 2026-11-16). One statement.
begin transaction read only;
with b as (select replace(p.prosrc, E'\r', '') as s from pg_proc p where p.oid = to_regprocedure('public.raid_target(uuid,timestamp with time zone)')),
     h(k, t) as (values
       ('old1', $h$  v_nm    numeric;$h$),
       ('old2', $h$     where public.fleet_kind(c.id) in ('MERCHANT', 'CARGO_SHIP', 'COMPANY')
     order by public.fleet_kind(c.id) = 'COMPANY', c.nm, c.id   -- 0432: the world's merchants first ("pirates' main goal is to attack other npcs"), then a player's$h$),
       ('new', $h$0464: the owner's switch$h$))
select (select jsonb_object_agg(h.k, (length(b.s) - length(replace(b.s, h.t, ''))) / length(h.t)) from h, b) as hunks,                     -- want {"old1": 1, "old2": 1, "new": 0}
       (select count(*) from public.world_config w where w.key in ('raid_companies_enabled', 'raid_company_title_min', 'raid_company_weight')) as knobs,   -- want 0
       (select count(*) from public.battles x where x.kind = 'RAID' and x.started_at > now() - interval '48 hours') as raids_48h,
       (select count(*) from public.battles x join public.battle_sides s on s.battle_id = x.id and s.side = 'DEFENDER' and s.how = 'OPENED'
                     join public.fleets f on f.id = s.fleet_id join public.players p on p.id = f.player_id
         where x.kind = 'RAID' and x.started_at > now() - interval '48 hours' and not p.is_npc) as raids_on_companies_48h,                         -- 0 on 2026-11-16
       (select round(coalesce(sum(extract(epoch from least(v.eta, now()) - greatest(v.departed_at, now() - interval '48 hours'))), 0) / 3600, 1)
          from public.voyages v join public.players p on p.id = v.player_id
         where not p.is_npc and v.status <> 'ABORTED' and v.departed_at < now() and v.eta > now() - interval '48 hours') as company_hours_at_sea_48h,   -- by the schedule (eta), aborted voyages left out
       (select jsonb_build_object('companies', count(*), 'at_or_over_master', count(*) filter (where public.title_level(p.id) >= 3))
          from public.players p where not p.is_npc) as companies,
       (select max(version) from supabase_migrations.schema_migrations) as head;                                                             -- want 20260818000462 or 20260818000463
commit;
