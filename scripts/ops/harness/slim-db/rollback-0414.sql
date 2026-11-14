-- 0414 FORWARD ROLLBACK, A DRAFT (written by gen.mjs from the migration's hunks). NOT a prod check and NOT a migration yet: to use it, strip the
-- guard line, give it the next number, add "-- news: none" and deploy it as any migration (owner only).
-- FIRST, WITH NO FILE (owner, one knob each): drift_spread_runs 1 steps every harbour every run again; npc_route_lap_keep 0 stops the merchants' lap
-- trim; city_wants_keep_periods 0 stops the wants' trim; stats_city_good_keep_days 0 stops that trim; npc_retention_hours 6 keeps six hours of the
-- merchants' books again. Rows already deleted do not come back by any of these, nor by this file.
-- This draft takes the code away: the four bodies go back to their text before 0414 (the five hunks reversed; each hunk's NEW text must occur once,
-- else it refuses: a later file re-cut those lines and the draft is stale), public.city_wants takes public.forbid_mutation back, the two new functions
-- and the eight new knobs go, the three moved knobs go back (only where they still hold 0414's value), the index is built again and the Stats count
-- runs four times an hour again. CREATE INDEX here is NOT concurrent (a migration runs in a transaction): on prod build it first, by hand, with
-- CREATE INDEX CONCURRENTLY IF NOT EXISTS (scripts/ops/harness/slim-db/RUNBOOK.md), and this file then finds it there.
-- LOCAL PGlite WORLD ONLY while it carries this line (scripts/ops/harness/README.md): it writes. The first statement refuses a real server.
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $r$
declare
  h      record;
  v_def  text;
  v_n    int;
begin
  perform set_config('statement_timeout', '60s', true);
  perform set_config('lock_timeout', '5s', true);
  create temp table back_0414 (ord int primary key, fn text, new text, old text) on commit drop;
  insert into back_0414 values
  (1, 'public.tick_market_drift(timestamp with time zone,uuid)',
$h$     -- 0414: ONE COMPOUNDED STEP FOR THE SLOTS MISSED. A row k slots behind (the drift job steps one harbour in drift_spread_runs a run; a
     -- skipped harbour; a job that was down) takes theta^k x drift + sigma x sqrt((1 - theta^2k) / (1 - theta^2)) x N(0,1): the law of k
     -- one-slot steps, so a price moves as far in a game day whatever the spread. k = 1 is the step as it always was (theta x drift +
     -- sigma x N). k is read to 10,000 slots: past that the walk has forgotten where it was.
     set drift = case when pg.drift_slot < v_slot then greatest(-v_clamp, least(v_clamp,
                   case when v_slot - pg.drift_slot <= 1 then v_theta
                        else power(v_theta, least(v_slot - pg.drift_slot, 10000)::numeric) end * pg.drift
                   + v_sigma * case when v_slot - pg.drift_slot <= 1 or abs(v_theta) >= 1 then 1
                                    else sqrt((1 - power(v_theta, (2 * least(v_slot - pg.drift_slot, 10000))::numeric)) / (1 - v_theta * v_theta)) end
                     * sqrt(-2 * ln(greatest(random(), 1e-12))) * cos(2 * pi() * random()))) else pg.drift end,
$h$,
$h$     set drift = case when pg.drift_slot < v_slot then greatest(-v_clamp, least(v_clamp,
                   v_theta * pg.drift
                   + v_sigma * sqrt(-2 * ln(greatest(random(), 1e-12))) * cos(2 * pi() * random()))) else pg.drift end,
$h$),
  (2, 'public.tick_market_drift_each_port()',
$h$  -- 0414: the harbours whose turn this minute is (public.drift_ports_due: one in drift_spread_runs; the step is compounded over the slots missed)
  for p in select d.id, d.code from public.drift_ports_due(v_now) d order by d.id loop
$h$,
$h$  for p in select po.id, po.code from public.ports po order by po.id loop
$h$),
  (3, 'public.npc_compact_houses(uuid[],timestamp with time zone)',
$h$  get diagnostics v_ev = row_count;

  -- 0414: A MERCHANT'S LAP HISTORY. A closed lap of one of these houses' routes that is BOTH past the route's newest npc_route_lap_keep AND
  -- closed more than npc_route_lap_keep_hours ago goes, at most compact_trim_rows a batch (the rest at her next visit). What stays is what
  -- the game reads of a merchant's laps: the last 24 hours and the lap before them (public.route_earnings, world.fleet_trades,
  -- public.stats_merchants_window), the newest 20 inside three days (public.npc_share_budget), the newest few. A player's route is not read
  -- here (v_hs holds merchants alone); cmd.standing_route_close_lap keeps standing_route_lap_keep of it, as before. 0 = OFF.
  if public.wc_int('npc_route_lap_keep') > 0 then
    delete from public.standing_route_laps x
     where x.id = any(array(
             select l.id
               from public.standing_routes sr
               join public.standing_route_laps l on l.route_id = sr.id
              where sr.player_id = any(v_hs)
                and l.closed_at is not null
                and l.closed_at < p_now - make_interval(hours => greatest(public.wc_int('npc_route_lap_keep_hours'), 25))
                and l.lap_no <= sr.lap_no - greatest(public.wc_int('npc_route_lap_keep'), 20)
                and l.id is distinct from sr.lap_id
              limit greatest(public.wc_int('compact_trim_rows'), 1)));
  end if;

  perform set_config('byeharu.npc_compact', 'off', true);
$h$,
$h$  get diagnostics v_ev = row_count;

  perform set_config('byeharu.npc_compact', 'off', true);
$h$),
  (4, 'public.tick_compact(boolean,boolean)',
$h$  -- 0414: the three limits are knobs, at the values the constants had (8 s, 200 ms, 25)
  c_budget constant interval := make_interval(secs => greatest(public.wc_int('compact_budget_ms'), 1) / 1000.0);   -- the minute's work, at most
  c_hold   constant numeric := greatest(public.wc_int('compact_hold_ms'), 1);   -- ms: the longest a transaction should hold its houses
  c_bmax   constant int := greatest(public.wc_int('compact_batch_max'), 1);     -- houses a transaction, at most
$h$,
$h$  c_budget constant interval := interval '8 seconds';   -- the minute's work, at most
  c_hold   constant numeric := 200;                     -- ms: the longest a transaction should hold its houses
  c_bmax   constant int := 25;                          -- houses a transaction, at most
$h$),
  (5, 'public.tick_compact(boolean,boolean)',
$h$  -- 0414: THE CITY WANTS OF PAST PERIODS, oldest first, compact_trim_rows a run. The game reads the current period and the one before
  -- (public.wants_draw, world.city_wants_now, world.want_left); city_wants_keep_periods are kept, never fewer than 2. The table is
  -- append-only: public.city_wants_guard lets this delete through, and no other (byeharu.wants_trim, this transaction only). 0 = OFF.
  if public.wc_int('city_wants_keep_periods') > 0 then
    begin
      perform set_config('byeharu.wants_trim', 'on', true);
      delete from public.city_wants w
       where w.ctid = any(array(select x.ctid from public.city_wants x
                                 where x.period < public.want_period(v_now) - greatest(public.wc_int('city_wants_keep_periods'), 2)
                                 order by x.period
                                 limit greatest(public.wc_int('compact_trim_rows'), 1)));
      perform set_config('byeharu.wants_trim', 'off', true);
    exception when others then
      v_fail := v_fail + 1;
      v_note := coalesce(v_note, 'wants: ' || sqlerrm);
    end;
    if p_commit then commit; end if;
  end if;
  insert into public.compact_runs (slot, at, ms, receipt)
$h$,
$h$  insert into public.compact_runs (slot, at, ms, receipt)
$h$);
  for h in select * from back_0414 order by ord desc loop
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    v_n := (length(v_def) - length(replace(v_def, h.new, ''))) / length(h.new);
    if v_n <> 1 then
      raise exception '0414 rollback refuses: hunk % of % occurs % time(s), not once: a later file re-cut it and this draft is stale', h.ord, h.fn, v_n;
    end if;
    execute replace(v_def, h.new, h.old);
  end loop;
  drop trigger city_wants_append_only on public.city_wants;
  create trigger city_wants_append_only before delete or update on public.city_wants
    for each row execute function public.forbid_mutation();
  drop function public.city_wants_guard();
  drop function public.drift_ports_due(timestamptz);
  delete from public.world_config where key in ('drift_spread_runs', 'city_wants_keep_periods', 'npc_route_lap_keep', 'npc_route_lap_keep_hours',
                                                'compact_trim_rows', 'compact_budget_ms', 'compact_hold_ms', 'compact_batch_max');
  update public.world_config set value = to_jsonb(0) where key = 'stats_city_good_keep_days' and value = to_jsonb(3);
  update public.world_config set value = to_jsonb(48) where key = 'stats_city_good_fine_hours' and value = to_jsonb(26);
  update public.world_config set value = to_jsonb(6) where key = 'npc_retention_hours' and value = to_jsonb(3);
  create index if not exists standing_route_laps_closed_at on public.standing_route_laps using btree (closed_at) where (closed_at is not null);
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    execute $q$select cron.alter_job(j.jobid, schedule := '6,21,36,51 * * * *') from cron.job j
                where j.jobname = 'byeharu-voyage:stats' and j.schedule = '6,36 * * * *'$q$;
  end if;
  raise notice '0414 rollback ok: the four bodies are their text before 0414; city_wants is under public.forbid_mutation; the knobs, the index and the Stats schedule are back.';
end $r$;
