-- 0412 FORWARD ROLLBACK, A DRAFT. NOT a prod check and NOT a migration yet: to use it, strip the guard line, give it the next number and deploy it as any
-- migration (owner only; with the clock jobs unwound, as the deploy script does). It puts the clock's rate back to 960 THROUGH THE SAME DOOR 0412 used,
-- public.clock_set, so it is continuous too: every voyage at sea keeps her mile at the instant and sails what is left in a fifth of the time; a
-- battle's hold running across the instant keeps its end; the top bar's date and hour do not jump (the anchor is re-written at the instant: the
-- clock then runs a day per 720 s from where it stood). Nothing else of 0412 is taken away, and nothing needs to be: world.snapshot() goes on
-- serving clock_voyage_days and clock_anchor, the client goes on reading them, and public.clock_set stays the one door. The date and the hour stay
-- ONE clock (a day per 720 s): the calendar of before 0412 (a month a real day, the hour hand apart) does not come back with this draft.
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
    raise exception 'rollback 0412 refuses: the clock is not 0412''s (time_compression %)', public.wc_num('time_compression');
  end if;
  v_r := public.clock_set(960, now());
  if public.wc_num('time_compression') <> 960 or 86400 * public.wc_num('clock_voyage_days') / public.wc_num('time_compression') <> 720 then
    raise exception 'rollback 0412 FAIL: the clock is not back at 960 (%)', v_r;
  end if;
  perform public.news_update('0412-back', 'A game day lasts twelve minutes again', '게임의 하루가 다시 12분입니다');
  raise notice 'rollback 0412 ok: %', v_r;
end $r$;
