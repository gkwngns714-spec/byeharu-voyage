do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
-- rollback-0419.sql: the FORWARD ROLLBACK DRAFT of 0419 (owner only). To deploy it: copy it into supabase/migrations/ under the next number and delete
-- its first line (the guard). It swaps 0419's four hunks back (each must occur once, and the bodies must come out without a trace of 0419), takes the
-- read out of the registry by that hunk, and drops world.stats_fleets, public.stats_fleets_count and public.stats_fleets. After it public.tick_stats
-- and public.client_rpc_entry_points are main's bodies before 0419 to the byte. The client's Ships face then reads nothing (it says "Ship figures not
-- loaded") until the client is reverted too.
do $r$
declare
  h     record;
  v_def text;
  v_n   int;
begin
  perform set_config('lock_timeout', '5s', true);
  create temp table hunk_r419 (ord int primary key, fn text, new text, old text) on commit drop;
  insert into hunk_r419 values
  (1, 'public.tick_stats(timestamp with time zone)',
$h$  v_w int := 0; v_g int := 0; v_c int := 0; v_cg int := 0; v_m int := 0; v_x int := 0;
  v_fl int := 0;   -- 0419: the fleets' row (public.stats_fleets)
$h$,
$h$  v_w int := 0; v_g int := 0; v_c int := 0; v_cg int := 0; v_m int := 0; v_x int := 0;
$h$),
  (2, 'public.tick_stats(timestamp with time zone)',
$h$  v_ph := v_ph || jsonb_build_object('merchants', public.beat_ms(clock_timestamp() - v_tp)); v_tp := clock_timestamp();   -- 0269

  -- 0419: EVERY FLEET (the owner, 2026-11-15: "in stats, show like merchants navy, pirates, anad cargo"): the merchants' ships, the navy, the
  -- pirates and the cargo ships as this count sees them, and what happened in its window (public.stats_fleets_count); kept 26 hours.
  -- budget: 1 row written and about 1 row deleted a count (twice an hour); ~1,400 small rows read by key (the three ship tables, their fleets and ships)
  insert into public.stats_fleets (slot, at, figures)
  values (v_slot, p_now, public.stats_fleets_count(v_prev_at, p_now))
  on conflict (slot) do nothing;
  get diagnostics v_fl = row_count;
  delete from public.stats_fleets x where x.at < p_now - interval '26 hours';
  v_ph := v_ph || jsonb_build_object('fleets', public.beat_ms(clock_timestamp() - v_tp)); v_tp := clock_timestamp();   -- 0419
$h$,
$h$  v_ph := v_ph || jsonb_build_object('merchants', public.beat_ms(clock_timestamp() - v_tp)); v_tp := clock_timestamp();   -- 0269
$h$),
  (3, 'public.tick_stats(timestamp with time zone)',
$h$                            'city_goods', v_cg, 'merchants', v_m, 'fleets', v_fl, 'compacted', v_x, 'fold', v_fold,   -- 0419: fleets
$h$,
$h$                            'city_goods', v_cg, 'merchants', v_m, 'compacted', v_x, 'fold', v_fold,
$h$),
  (4, 'public.client_rpc_entry_points()',
$h$      ('world',       'stats_me',              ''),
      -- 0419: the merchants, the navy, the pirates and the cargo ships (the Stats face "Ships").
      ('world',       'stats_fleets',          ''),
$h$,
$h$      ('world',       'stats_me',              ''),
$h$);
  for h in select * from hunk_r419 order by ord desc loop   -- last first: v_fl is declared until its uses are gone
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    v_n := (length(v_def) - length(replace(v_def, h.new, ''))) / length(h.new);
    if v_n <> 1 then
      raise exception 'rollback-0419: hunk % of % occurs % time(s), not once', h.ord, h.fn, v_n;
    end if;
    execute replace(v_def, h.new, h.old);
  end loop;
  if exists (select 1 from pg_proc p where p.oid in ('public.tick_stats(timestamp with time zone)'::regprocedure, 'public.client_rpc_entry_points()'::regprocedure)
              and pg_get_functiondef(p.oid) ~ '0419|stats_fleets') then
    raise exception 'rollback-0419: a trace of 0419 is left in a body';
  end if;
  drop function world.stats_fleets();
  drop function public.stats_fleets_count(timestamptz, timestamptz);
  drop table public.stats_fleets;
  raise notice 'rollback-0419 ok: four hunks reversed, world.stats_fleets, public.stats_fleets_count and public.stats_fleets dropped';
end $r$;
