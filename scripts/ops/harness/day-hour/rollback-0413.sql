-- 0413 FORWARD ROLLBACK, A DRAFT. NOT a prod check and NOT a migration yet: to use it, strip the guard line, give it the next number and deploy it as any
-- migration (owner only; with the clock jobs unwound, as the deploy script does). It puts the clock's rate back to 960 THROUGH THE SAME DOOR 0413 used,
-- public.clock_set, so it is continuous the same way and moves the same things back by the same factor:
--   * every voyage at sea keeps her mile at the instant and sails what is left in a fifth of the time; a battle's hold running across it keeps its end;
--   * the market's four counters (game day, drift slot, want period, population slot) keep their count at the instant and count on at a fifth of the
--     length (game_day_seconds, drift_slot_seconds, want_period_seconds, population_slot_seconds / 5); drift_spread_runs / 5;
--   * the economy's rates per real time x 5 (navy_upkeep_day, works_coupon_day, pirate_spend_day_pct, population_tax_per_1000) and its half-lives / 5
--     (glut_half_life_hours, invested_half_life_hours): WHATEVER STANDS THERE THEN. If the owner has re-set one of them since 0413, set it by hand after;
--   * the top bar's date and hour do not jump (the clock then runs a day per 720 s from where it stood; date and hour stay ONE clock).
-- Nothing else of 0413 is taken away, and nothing needs to be: the counters go on reading public.clock_count and public.clock_start, world.snapshot()
-- goes on serving the clock, and public.clock_set stays the one door.
-- ONE SEAM: an instant BEFORE 0413's own switch is then read at the length of the time between the two moves (the anchor keeps one earlier length).
-- That touches only reads of the past by day number (the books' and the Stats' day figures across the seam); no counter of now is moved by it.
-- WITH NO FILE the owner can do the same at once: select public.clock_set(960);
-- LOCAL PGlite WORLD ONLY while it carries this line (scripts/ops/harness/README.md): it writes. The first statement refuses a real server.
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $r$
declare
  v_r jsonb;
begin
  perform set_config('statement_timeout', '60s', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regprocedure('public.clock_set(integer,timestamp with time zone)') is null or public.wc_num('time_compression') <> 192 then
    raise exception 'rollback 0413 refuses: the clock is not 0413''s (time_compression %)', public.wc_num('time_compression');
  end if;
  v_r := public.clock_set(960, now());
  if public.wc_num('time_compression') <> 960 or 86400 * public.wc_num('clock_voyage_days') / public.wc_num('time_compression') <> 720 then
    raise exception 'rollback 0413 FAIL: the clock is not back at 960 (%)', v_r;
  end if;
  perform public.news_update('0413-back', 'A game day lasts twelve minutes again', '게임의 하루가 다시 12분입니다');
  raise notice 'rollback 0413 ok: %', v_r;
end $r$;
