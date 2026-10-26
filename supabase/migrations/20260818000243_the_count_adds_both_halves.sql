-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0243 — THE COUNT ADDS BOTH HALVES OF A DAY
--        (a fix to 0214's public.tick_stats: the world's `recent` figure held ONE half of a (game day, kind)
--         whenever the kind sat in both the daybook and the not-yet-rolled flows — so around each city roll
--         (:36–:37) the next count's period, and its minted / removed / moved, jumped by that half.)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- THE BUG (diagnosed on prod 2026-10-26): `recent` is the newest three game days per kind over the daybook
-- (rolled) AND treasury_flows (not yet rolled), combined with `union all` and then `jsonb_object_agg(kind, s)`.
-- When a (day, kind) has a value in both halves the kind appears twice in the aggregate and jsonb keeps only the
-- LAST — one half. After the roll moves the flows into the daybook the next count holds the whole, and the period
-- (this recent - the last recent) jumps by the missing half (07:51: minted 443,824 = 851,659 - 407,835 of
-- IMPORT_DEMAND that was pre-switch money).
--
-- THE FIX: sum per (day, kind) BEFORE the aggregate. ONE hunk in tick_stats, cut against the LIVE body (0214 as
-- re-cut by 0224, 0226, 0229, 0232). Nothing else moves: no table, no ACL, no signature, no schedule.
--
-- SELF-ASSERT (rolled back; probe rows only): a probe kind is planted in BOTH the daybook (1000) and the flows
-- (250) of one game day; the old shape of the query is run on those rows and gives ONE half; the re-cut count,
-- run two hours ahead, writes `recent` = 1250.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '10min', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regprocedure('public.stats_fold_day(bigint)') is null then
    raise exception '0243 refuses: 0232 (the figures keep to the second) is not in this world';
  end if;
end $guard$;

create or replace function pg_temp.occurs_0243(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

create temp table def_before_0243 on commit drop as
select replace(pg_get_functiondef('public.tick_stats(timestamptz)'::regprocedure), E'\r', '') as def,
       coalesce(p.proacl::text, '') as acl, p.provolatile as vol, p.prosecdef as secdef,
       coalesce(p.proconfig::text, '') as cfg, p.proowner as owner
  from pg_proc p where p.oid = 'public.tick_stats(timestamptz)'::regprocedure;

create temp table hunk_0243 (old text, new text) on commit drop;
insert into hunk_0243 values
($h$    from (select x.gd, jsonb_object_agg(x.kind, x.s) as kinds
            from (select d.game_day as gd, d.kind, sum(d.ducats) as s
                    from public.treasury_daybook d
                   where d.kind <> 'CARRIED' and d.game_day >= world.game_day(p_now) - 2
                   group by 1, 2
                  union all
                  select world.game_day(f.created_at), f.kind, sum(f.ducats)
                    from public.treasury_flows f
                   where f.created_at <= p_now and world.game_day(f.created_at) >= world.game_day(p_now) - 2
                   group by 1, 2) x
           group by x.gd) d;
$h$,
$h$    from (select x.gd, jsonb_object_agg(x.kind, x.s) as kinds
            -- 0243: a (day, kind) in BOTH halves is ONE figure — summed here, before the aggregate keeps only the last key
            from (select y.gd, y.kind, sum(y.s) as s
                    from (select d.game_day as gd, d.kind, sum(d.ducats) as s
                            from public.treasury_daybook d
                           where d.kind <> 'CARRIED' and d.game_day >= world.game_day(p_now) - 2
                           group by 1, 2
                          union all
                          select world.game_day(f.created_at), f.kind, sum(f.ducats)
                            from public.treasury_flows f
                           where f.created_at <= p_now and world.game_day(f.created_at) >= world.game_day(p_now) - 2
                           group by 1, 2) y
                   group by 1, 2) x
           group by x.gd) d;
$h$);

do $$
declare
  d     record;
  h     record;
  p     record;
  v_def text;
  v_rev text;
begin
  select * into d from def_before_0243;
  select * into h from hunk_0243;
  if pg_temp.occurs_0243(d.def, h.old) <> 1 then
    raise exception '0243 self-assert FAIL: tick_stats carries the hunk % time(s), not once — the deployed body is not what this file was written against',
      pg_temp.occurs_0243(d.def, h.old);
  end if;
  v_def := replace(d.def, h.old, h.new);
  execute v_def;
  v_rev := replace(pg_get_functiondef('public.tick_stats(timestamptz)'::regprocedure), E'\r', '');
  if pg_temp.occurs_0243(v_rev, h.new) <> 1 or pg_temp.occurs_0243(v_rev, h.old) <> 0 then
    raise exception '0243 self-assert FAIL: the new hunk is not in the live body exactly once';
  end if;
  if replace(v_rev, h.new, h.old) <> d.def then
    raise exception '0243 self-assert FAIL: tick_stats does not reverse to its pre-image';
  end if;
  select coalesce(pr.proacl::text, '') as acl, pr.provolatile as vol, pr.prosecdef as secdef,
         coalesce(pr.proconfig::text, '') as cfg, pr.proowner as owner
    into p from pg_proc pr where pr.oid = 'public.tick_stats(timestamptz)'::regprocedure;
  if p.acl <> d.acl or p.vol <> d.vol or p.secdef <> d.secdef or p.cfg <> d.cfg or p.owner <> d.owner then
    raise exception '0243 self-assert FAIL: tick_stats changed its ACL (% -> %), owner, volatility, definer or config', d.acl, p.acl;
  end if;
end $$;

-- ── THE PROOF BY AMOUNT (rolled back) ──────────────────────────────────────────────────────────
do $$
declare
  v_now  timestamptz := now() + interval '2 hours';   -- a slot the cron cannot reach meanwhile
  v_gd   int := world.game_day(now() + interval '2 hours');
  v_port uuid;
  v_run  jsonb;
  v_new  text;
  v_old  text;
begin
  select id into v_port from public.ports where kind = 'HARBOUR' order by id limit 1;
  if v_port is null then
    raise exception '0243 self-assert FAIL: no harbour to plant the probe at';
  end if;
  begin
    -- the probe kind sits in BOTH halves of one game day (a moved-style kind: nothing is minted, no guard is asked)
    insert into public.treasury_daybook (port_id, game_day, kind, ducats) values (v_port, v_gd, 'PROBE_0243', 1000);
    insert into public.treasury_flows (port_id, kind, ducats, created_at) values (v_port, 'PROBE_0243', 250, v_now);
    -- the OLD shape of the query on exactly these rows: the aggregate keeps one key — one half
    select jsonb_object_agg(x.kind, x.s)->>'PROBE_0243' into v_old
      from (select d.kind, sum(d.ducats) as s from public.treasury_daybook d where d.kind = 'PROBE_0243' and d.game_day = v_gd group by 1
            union all
            select f.kind, sum(f.ducats) from public.treasury_flows f where f.kind = 'PROBE_0243' and world.game_day(f.created_at) = v_gd group by 1) x;
    if v_old is null or v_old::bigint not in (1000, 250) then
      raise exception '0243 self-assert FAIL: the old shape gave % (expected one half: 1000 or 250)', v_old;
    end if;
    v_run := public.tick_stats(v_now);
    select w.recent -> v_gd::text ->> 'PROBE_0243' into v_new from public.stats_world w where w.slot = (v_run->>'slot')::bigint;
    if v_new is null or v_new::bigint <> 1250 then
      raise exception '0243 self-assert FAIL: recent holds % for the probe, not the sum 1250 (old shape: %)', v_new, v_old;
    end if;
    raise exception using errcode = 'ZX227', message = jsonb_build_object('new', v_new, 'old', v_old)::text;
  exception when sqlstate 'ZX227' then
    v_run := sqlerrm::jsonb;
  end;
  if exists (select 1 from public.treasury_daybook where kind = 'PROBE_0243') or exists (select 1 from public.treasury_flows where kind = 'PROBE_0243')
     or exists (select 1 from public.stats_world where at > now() + interval '1 hour') then
    raise exception '0243 self-assert FAIL: the probe or the trial count survived its rollback';
  end if;
  raise notice '0243 self-assert ok: THE COUNT ADDS BOTH HALVES. A probe kind planted at 1000 in the daybook and 250 in the flows of one game day: the old shape keeps % (one half); the re-cut count writes recent = % (the sum). One hunk, reverses to its pre-image; ACL, owner, volatility unchanged.',
    v_run->>'old', v_run->>'new';
end $$;
