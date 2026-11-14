-- ROLLBACK DRAFT for 0421 (THE WORLD IS COUNTED AND READ MORE OFTEN). A FORWARD migration, owner only: copy what is needed into the next free
-- number. Each part stands alone; take the FIRST part alone if the gate goes red (the Stats count is the biggest added load).
-- docs/dev-log/2026-11-15-pace-up.md has the measurements. The client's 15-s read is reverted in src/domain/readClock.ts
-- (READS_PER_VOYAGE_DAY 30 -> 12), a client-only PR.
--
-- budget: the Stats count back to twice an hour, about 2,450 rows a run (0409's cadence): -82 rows a minute.
-- LOCAL SCENE (tests/harness.guard.spec.ts): it writes; the guard refuses anywhere but the local PGlite world.
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $r$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    -- budget: the Stats count (byeharu-voyage:stats) back to 2 runs an hour, about 2,450 rows written a run.
    execute $q$select cron.alter_job(j.jobid, schedule := '6,36 * * * *') from cron.job j
                where j.jobname = 'byeharu-voyage:stats' and j.schedule = '6,21,36,51 * * * *'$q$;
  end if;
end $r$;

-- the request boards' retry back to 60 minutes (0315's value)
update public.world_config
   set value = to_jsonb(60), updated_at = now(),
       description = '0315: how long the wind job leaves a harbour that could not post before asking it again. (0421 set 30; put back to 60.)'
 where key = 'contract_wind_retry_minutes' and value = to_jsonb(30);

-- the pirates' add back to one fleet in 10 minutes (0414's value). Proofs 106 and 115 pin 10 themselves; proof 118 (which wants 5) is then
-- retired or re-pinned in the same PR.
update public.world_config
   set value = to_jsonb(10), updated_at = now(),
       description = '0414: the pirates add at most one fleet in this many minutes (public.pirate_add). Before 0414 it was navy_build_hours (24 hours), which stays the navy''s. (0421 set 5; put back to 10.)'
 where key = 'pirate_add_minutes' and value = to_jsonb(5);
