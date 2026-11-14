-- ROLLBACK DRAFT for 0420 (forward, OWNER ONLY; never run by an agent). Puts drift_spread_runs back to 50 (every harbour every 50 minutes, ~3,130 rows a
-- run) and public.clock_set back to its 0413 body (the two hunks reversed: the door moves the spread by old / new again).
-- At once, with no file: drift_spread_runs 50 alone undoes the pace (the door's hunks change nothing until the clock is next moved).
-- As a migration it would be prod head + 1, with its own self-assert; this file is the body of that migration.
-- LOCAL SCENE (tests/harness.guard.spec.ts): it writes; the guard refuses anywhere but the local PGlite world.
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $r$
declare
  v_def  text := replace(pg_get_functiondef('public.clock_set(integer,timestamp with time zone)'::regprocedure), E'\r', '');
  v_new1 text := $h$--   same way); the economy's rates per real time (/ f) and its half-lives (x f); and the clock's anchor.
-- 0420: NOT the drift job's spread (drift_spread_runs): it is a pace in real minutes (every harbour once in that many one-minute runs; the
--   owner's "every 15 minute") and the database's rows a real minute; the compounded step (0409) keeps the walk per voyage-day whatever it is.
$h$;
  v_old1 text := $h$--   same way); the drift job's spread (x f); the economy's rates per real time (/ f) and its half-lives (x f); and the clock's anchor.
$h$;
  v_new2 text := $h$  -- 0420: drift_spread_runs is not moved here (a pace in real minutes; see the head of this body)
$h$;
  v_old2 text := $h$  update public.world_config wc
     set value = to_jsonb(greatest(1, round((wc.value #>> '{}')::numeric * v_f))::int), updated_at = now()
   where wc.key = 'drift_spread_runs';
$h$;
begin
  if (length(v_def) - length(replace(v_def, v_new1, ''))) / length(v_new1) <> 1 or (length(v_def) - length(replace(v_def, v_new2, ''))) / length(v_new2) <> 1 then
    raise exception 'rollback-0420 refuses: public.clock_set is not the body 0420 left';
  end if;
  execute replace(replace(v_def, v_new2, v_old2), v_new1, v_old1);
  update public.world_config
     set value = to_jsonb(50), updated_at = now(),
         description = '0409: the drift job (pg_cron byeharu-voyage:drift, every minute) steps one harbour in this many a run, by its place in the port order (public.drift_ports_due); a harbour stepped after k missed slots takes one compounded step with the law of k steps (public.tick_market_drift), and a quay somebody opens is stepped on that read. 1 = every harbour every run (the rule before 0409). Rolled back from 0420''s 15 to 50.'
   where key = 'drift_spread_runs';
  raise notice 'rollback-0420 ok: drift_spread_runs 50; public.clock_set is 0413''s again (it moves the spread with the clock)';
end
$r$;
