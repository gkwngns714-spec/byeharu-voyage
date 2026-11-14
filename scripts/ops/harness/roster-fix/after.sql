-- 0418 PROD CHECK, BEFORE the deploy AND AGAIN AFTER IT (before.sql and after.sql are one text), read-only, ONE statement. Calls only stable functions.
--   npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/roster-fix/before.sql
-- BEFORE, wanted: head 20260818000417; applied false; hunks {1: 1, 2: 1} (each old text once in the live public.pirate_add); volatility of pirate_next_ord, pirate_spend_room, pirate_size 's'.
--   Write down roster.built, clock.added_at, room, next_ord.
-- AFTER, wanted: head 20260818000418; applied true; hunks {1: 0, 2: 0}; new_texts {1: 1, 2: 1}. Within 10 minutes of the deploy: roster.built rises by one, clock.added_at moves,
--   spend_today does not move by it (BUILD_ROSTER is outside the room); then one more every pirate_add_minutes (10) while the room is spent. hoard stays above 400,000,000.
begin transaction read only;
with hk(ord, old, new) as (values
  (1, E'    if public.pirate_spend_room(p_now) < v_slice or public.city_surplus(v_cap) < v_slice then\n      return null;\n    end if;\n',
      E'      return public.pirate_add_roster(p_now);   -- 0418: a wake the day''s room cannot pay'),
  (2, E'                else public.pirate_commission(v_ord, v_home, v_yard, p_now) end) is null then\n      return null;\n',
      E'then null else public.pirate_add_roster(p_now) end;   -- 0418: a 0339 hull')
), body as (select replace(pg_get_functiondef('public.pirate_add(timestamp with time zone)'::regprocedure), E'\r', '') as def)
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'applied', to_regprocedure('public.pirate_add_roster(timestamp with time zone)') is not null,
  'hunks', (select jsonb_object_agg(hk.ord, (length(b.def) - length(replace(b.def, hk.old, ''))) / length(hk.old)) from hk, body b),
  'new_texts', (select jsonb_object_agg(hk.ord, (length(b.def) - length(replace(b.def, hk.new, ''))) / length(hk.new)) from hk, body b),
  'volatility', (select jsonb_object_agg(p.proname, p.provolatile::text) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'public' and p.proname in ('pirate_next_ord', 'pirate_spend_room', 'pirate_size', 'pirate_hoard')),
  'clock', (select to_jsonb(c) from public.pirate_clock c),
  'next_ord', public.pirate_next_ord(), 'size', public.pirate_size(), 'hoard', public.pirate_hoard(), 'room', public.pirate_spend_room(now()),
  'spend_today', (select d.spent from public.pirate_spend_day d where d.day = (now() at time zone 'UTC')::date),
  'roster', (select jsonb_build_object('fleets', (select count(*) from public.pirate_roster), 'built', count(*), 'laid_up', count(*) filter (where n.laid_up_at is not null),
                    'newest', max(n.created_at)) from public.pirate_ships n where n.ord > 1000),
  'old_ships', (select jsonb_build_object('n', count(*), 'wrecks', count(*) filter (where n.wrecked_at is not null), 'unpaid', count(*) filter (where n.unpaid_since is not null))
                  from public.pirate_ships n where n.ord < 1000)
) as r;
commit;
