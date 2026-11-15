-- 0435 + 0436 PROD CHECK, BEFORE the deploy (one statement, read only): the live bodies 0436 hunks are what it was written against.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/tick-combat/before-0436.sql
-- Wanted: head 20260818000434 (0434, #726, live first); tick_run 0 (0435 not yet live); h_registry 1; h_pirates true; h_navy true;
--   how_check without JOINED; knobs 0 (battle_join_nm comes with 0435); sides_rows small (0436's constraint VALIDATE scans battle_sides).
begin transaction read only;
select (select max(version) from supabase_migrations.schema_migrations) as head,
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'tick_battle_run') as tick_run,
       (select (length(d) - length(replace(d, $$      ('cmd',         'battle_stance',         'uuid, text'),$$, ''))) / 61
          from (select replace(pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure), E'\r', '') d) x) as h_registry,
       (select position($$jsonb_build_object('purses', public.pirate_purse_step(p_now)) else '{}'::jsonb end;$$ in pg_get_functiondef('public.tick_pirates(timestamp with time zone)'::regprocedure)) > 0) as h_pirates,
       (select position($$bool_or(bs.how not in ('OPENED', 'ARMADA') and bs.arrives_at <= b.resolves_at or$$ in pg_get_functiondef('public.navy_close(uuid,timestamp with time zone)'::regprocedure)) > 0) as h_navy,
       (select pg_get_constraintdef(c.oid) from pg_constraint c where c.conname = 'battle_sides_how_check') as how_check,
       (select count(*) from public.world_config where key like 'battle_join%') as knobs,
       (select count(*) from public.battle_sides) as sides_rows;
rollback;
