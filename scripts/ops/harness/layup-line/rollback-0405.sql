-- 0405 FORWARD ROLLBACK, A DRAFT. NOT a prod check and NOT a migration yet: to use it, strip the guard line, give it the next number, add "-- news: none" and
-- deploy it as any migration (owner only). FIRST, AND USUALLY ENOUGH: the owner sets npc_ask_job_ms to 0; the job then asks nobody within the minute and
-- the beat's own ask (0182) and the hourly reconcile serve the line as before 0405. This draft takes the job and its pieces away: the cron row, the
-- procedure, its two steps, its book and its knob. No live body was re-cut by 0405, so nothing else is to restore. A merchant asked by the job keeps her
-- stamp (npc_fleets.asked_at, the column 0182 made) and is due again ten minutes later, by the beat's hand.
-- LOCAL PGlite WORLD ONLY while it carries this line (scripts/ops/harness/README.md): it writes. The first statement refuses a real server.
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $r$
begin
  perform set_config('statement_timeout', '20s', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regprocedure('public.tick_waiting_asks(boolean,uuid)') is null then
    raise exception 'rollback 0405 refuses: 0405 is not in this world';
  end if;
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    execute $q$select cron.unschedule(j.jobid) from cron.job j where j.jobname = 'byeharu-voyage:waiting-asks'$q$;
  end if;
  drop procedure public.tick_waiting_asks(boolean, uuid);
  drop function public.waiting_ask_open(uuid, timestamptz);
  drop function public.waiting_ask_plan(uuid);
  drop table public.waiting_ask_runs;
  delete from public.world_config where key = 'npc_ask_job_ms';
  if to_regclass('public.waiting_ask_runs') is not null or exists (select 1 from public.world_config where key = 'npc_ask_job_ms') then
    raise exception 'rollback 0405 FAIL: something of 0405 is left';
  end if;
  raise notice 'rollback 0405 ok: the waiting-asks job, its two steps, its book and its knob are gone; the beat''s ask and the reconcile serve the line';
end $r$;
