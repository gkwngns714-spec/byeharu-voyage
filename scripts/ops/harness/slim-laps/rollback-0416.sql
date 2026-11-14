-- 0416 FORWARD ROLLBACK, A DRAFT (written by gen.mjs from the migration's hunks). NOT a prod check and NOT a migration yet: to use it, strip the
-- guard line, give it the next number, add "-- news: none" and deploy it as any migration (owner only).
-- FIRST, WITH NO FILE (owner, one knob): npc_route_lap_keep 0 stops the trim: a merchant's route then keeps standing_route_lap_keep (100) laps like
-- a player's. Nothing else needs undoing for the figures to be right: the readers are exact wherever the lap rows are kept.
-- This draft takes the code away: the six bodies go back to their text before 0416 (the seven hunks reversed; each hunk's NEW text must occur
-- once, else it refuses: a later file re-cut those lines and the draft is stale), the trigger, the three new functions, the hour book and the two
-- new knobs go, and the four moved knobs go back to 0409's values (only where they still hold 0416's). MIND: the readers then read lap rows
-- again, and a merchant holds only her newest ten: her "today" and the Stats tab's merchants read short until 24 hours of laps have been kept
-- again (0409's rule keeps 26 hours from then on). Deleted lap rows do not come back.
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
  create temp table back_0416 (ord int primary key, fn text, new text, old text) on commit drop;
  insert into back_0416 values
  (1, 'public.route_earnings(uuid)',
$h$    -- 0416: the day is read by public.route_day (the hour book for the whole hours, the lap rows for the part-hours), so a merchant's
    -- lap rows can be her newest ten
    'day',       (select d.net from public.route_day(p_route, now() - interval '24 hours', now()) d),
    'day_laps',  (select d.laps from public.route_day(p_route, now() - interval '24 hours', now()) d),
    'day_since', (select d.since from public.route_day(p_route, now() - interval '24 hours', now()) d),
    'day_full',  public.route_day_full(p_route, now() - interval '24 hours'),
$h$,
$h$    'day',       coalesce((select sum(x.net) from public.standing_route_laps x
                            where x.route_id = p_route and x.closed_at > now() - interval '24 hours'), 0),
    'day_laps',  (select count(*) from public.standing_route_laps x
                   where x.route_id = p_route and x.closed_at > now() - interval '24 hours'),
    'day_since', (select min(x.closed_at) from public.standing_route_laps x
                   where x.route_id = p_route and x.closed_at > now() - interval '24 hours'),
    'day_full',  exists (select 1 from public.standing_route_laps x
                          where x.route_id = p_route and x.closed_at <= now() - interval '24 hours'),
$h$),
  (2, 'world.fleet_trades(uuid)',
$h$  -- 0416: the day's totals are public.route_day's (the hour book and the part-hours' lap rows: the figures route_earnings prints); the laps
  -- that still carry their trades, and the goods below, are read from the lap rows as before
  select (select jsonb_build_object(
           'since', d.since,
           'full', public.route_day_full(sr.id, now() - interval '24 hours'),
           'laps', d.laps,
           'laps_traded', (select count(*) from w where w.trades is not null),
           'sold', d.sold,
           'bought', d.bought,
           'supplies', d.supplies,
           'repairs', d.repairs,
           'wages', d.wages,
           'taxes', d.taxes,   -- 0122
           'stock_in', d.stock_in,
           'stock_out', d.stock_out,
           'net', d.net)
            from public.route_day(sr.id, now() - interval '24 hours', now()) d)
         || jsonb_build_object(
$h$,
$h$  select jsonb_build_object(
           'since', (select min(w.closed_at) from w),
           'full', exists (select 1 from public.standing_route_laps y
                            where y.route_id = sr.id and y.closed_at <= now() - interval '24 hours'),
           'laps', (select count(*) from w),
           'laps_traded', (select count(*) from w where w.trades is not null),
           'sold', coalesce((select sum(w.sold) from w), 0),
           'bought', coalesce((select sum(w.bought) from w), 0),
           'supplies', coalesce((select sum(w.supplies) from w), 0),
           'repairs', coalesce((select sum(w.repairs) from w), 0),
           'wages', coalesce((select sum(w.wages) from w), 0),
           'taxes', coalesce((select sum(w.taxes) from w), 0),   -- 0122
           'stock_in', coalesce((select sum(w.stock_in) from w), 0),
           'stock_out', coalesce((select sum(w.stock_out) from w), 0),
           'net', coalesce((select sum(w.net) from w), 0),
$h$),
  (3, 'public.stats_merchants_window(timestamp with time zone,timestamp with time zone)',
$h$    -- 0416: the whole hours of the window from public.route_hour_laps (laps 2 onwards: net2, laps2, neg2), its two part-hours from the lap
    -- rows still kept (a merchant keeps her newest ten). The tab's "minutes since the count" lies inside one or two part-hours: exact.
    select b.route_id, b.net2 as net, b.laps2 as n, b.neg2 as neg
      from public.route_hour_laps b
     where b.hour >= date_trunc('hour', p_from) + case when p_from > date_trunc('hour', p_from) then interval '1 hour' else interval '0' end
       and b.hour < date_trunc('hour', p_to) and b.laps2 > 0
    union all
    select l.route_id, l.net, 1, (l.net <= 0)::int
      from public.standing_route_laps l
     where l.closed_at > p_from and l.closed_at <= p_to and l.lap_no >= 2
       and (l.closed_at < date_trunc('hour', p_from) + case when p_from > date_trunc('hour', p_from) then interval '1 hour' else interval '0' end
            or l.closed_at >= date_trunc('hour', p_to))
  ), h as (
    select p.company_name as name, n.code as nation, sum(l.net)::bigint as day, sum(l.n)::int as laps
$h$,
$h$    select l.route_id, l.net
      from public.standing_route_laps l
     where l.closed_at > p_from and l.closed_at <= p_to and l.lap_no >= 2
  ), h as (
    select p.company_name as name, n.code as nation, sum(l.net)::bigint as day, count(*)::int as laps
$h$),
  (4, 'public.stats_merchants_window(timestamp with time zone,timestamp with time zone)',
$h$           'n', coalesce((select sum(l.n) from l), 0),
           'neg', coalesce((select sum(l.neg) from l), 0),
$h$,
$h$           'n', (select count(*) from l),
           'neg', (select count(*) from l where l.net <= 0),
$h$),
  (5, 'public.npc_share_budget(timestamp with time zone,uuid,bigint)',
$h$            -- 0416: the dearest lap of the last npc_invest_lap_hours, from the hour book (it read her newest 20 lap rows; she keeps ten)
            cross join lateral (select b.spend_max as spend
                                  from public.route_hour_laps b
                                 where b.route_id = nf.route_id
                                   and b.hour >= date_trunc('hour', p_now - make_interval(hours => greatest(public.wc_int('npc_invest_lap_hours'), 1)))) l
$h$,
$h$            cross join lateral (select x.bought + x.supplies + x.repairs + x.wages + x.taxes + x.insurance as spend
                                  from public.standing_route_laps x
                                 where x.route_id = nf.route_id and x.closed_at > p_now - interval '3 days'
                                 order by x.lap_no desc limit 20) l
$h$),
  (6, 'public.npc_compact_houses(uuid[],timestamp with time zone)',
$h$                -- 0416: her newest npc_route_lap_keep alone (never under 10); the hours' window only while its knob is above 0. The day
                -- figures no longer read these rows (public.route_hour_laps).
                and (public.wc_int('npc_route_lap_keep_hours') <= 0
                     or l.closed_at < p_now - make_interval(hours => public.wc_int('npc_route_lap_keep_hours')))
                and l.lap_no <= sr.lap_no - greatest(public.wc_int('npc_route_lap_keep'), 10)
$h$,
$h$                and l.closed_at < p_now - make_interval(hours => greatest(public.wc_int('npc_route_lap_keep_hours'), 25))
                and l.lap_no <= sr.lap_no - greatest(public.wc_int('npc_route_lap_keep'), 20)
$h$),
  (7, 'public.tick_compact(boolean,boolean)',
$h$    if p_commit then commit; end if;
  end if;
  -- 0416: THE HOUR BOOK'S OLD HOURS (public.route_hour_laps past route_hour_keep_hours, never under 30), compact_trim_rows a run.
  begin
    delete from public.route_hour_laps b
     where b.ctid = any(array(select x.ctid from public.route_hour_laps x
                               where x.hour < v_now - make_interval(hours => greatest(public.wc_int('route_hour_keep_hours'), 30))
                               order by x.hour
                               limit greatest(public.wc_int('compact_trim_rows'), 1)));
  exception when others then
    v_fail := v_fail + 1;
    v_note := coalesce(v_note, 'hour book: ' || sqlerrm);
  end;
  if p_commit then commit; end if;
  insert into public.compact_runs (slot, at, ms, receipt)
$h$,
$h$    if p_commit then commit; end if;
  end if;
  insert into public.compact_runs (slot, at, ms, receipt)
$h$);
  for h in select * from back_0416 order by ord desc loop
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    v_n := (length(v_def) - length(replace(v_def, h.new, ''))) / length(h.new);
    if v_n <> 1 then
      raise exception '0416 rollback refuses: hunk % of % occurs % time(s), not once: a later file re-cut it and this draft is stale', h.ord, h.fn, v_n;
    end if;
    execute replace(v_def, h.new, h.old);
  end loop;
  drop trigger standing_route_laps_hour_book on public.standing_route_laps;
  drop function public.route_hour_post();
  drop function public.route_day(uuid, timestamptz, timestamptz);
  drop function public.route_day_full(uuid, timestamptz);
  drop table public.route_hour_laps;
  delete from public.world_config where key in ('route_hour_keep_hours', 'npc_invest_lap_hours');
  update public.world_config set value = to_jsonb(24) where key = 'npc_route_lap_keep' and value = to_jsonb(10);
  update public.world_config set value = to_jsonb(26) where key = 'npc_route_lap_keep_hours' and value = to_jsonb(0);
  update public.world_config set value = to_jsonb(3) where key = 'stats_city_good_keep_days' and value = to_jsonb(30);
  update public.world_config set value = to_jsonb(7) where key = 'stats_city_good_hour_days' and value = to_jsonb(2);
  raise notice '0416 rollback ok: the six bodies are their text before 0416; the hour book, its trigger and its readings are gone; the knobs are 0409''s.';
end $r$;
