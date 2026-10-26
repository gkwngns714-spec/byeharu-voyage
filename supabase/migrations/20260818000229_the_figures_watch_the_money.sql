-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0229 — THE FIGURES WATCH THE MONEY
--        (slice E2 of docs/CLOSED_ECONOMY.md: the figures the closed economy will be watched by, §7, are
--         counted by the 15-minute job and served by the one live read — BEFORE anything is lit)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER, VERBATIM (docs/OWNER_REQUESTS.md row 212, 2026-10-26) ────────────────────────────
--   "lets try this model and see the stats after few days."
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- §7 of the design names the figures that say whether the closed economy is healthy, and E2 adds them to
-- Stats while the economy is still OPEN, so the "before" is on record (new money reads ≈ 70 M a day today).
--   COUNTED by the 15-minute job (public.tick_stats → public.stats_watch(p_now), kept on the row it writes,
--   stats_world.watch; old rows keep null):
--     under_reserve   harbours whose purse (public.treasury_balance) is under its reserve (port_treasury.reserve, 0122)
--     under_thin      harbours whose purse is under stats_thin_purse (10,000) — "harbours under 10 k"
--     broke           merchant companies (npc_houses) whose purse is under merchant_broke_pct (0.2) × her capital
--                     (the §1 measure: 38 on 2026-10-26; E4's gift trigger reads the same knob)
--     gifts, gifts_ducats   capital gifts (0228's book) in the 24 h to p_now — 0 while dark
--     swing_p50, swing_p90, swing_steps   the price swing: every step between two consecutive recorded mids of
--                     one (city, good) in price_history within the hour to p_now, |mid / previous − 1|, its
--                     median and 90th percentile (a fraction: 0.026 = 2.6 %) and how many steps
--   SERVED by world.stats_now() under one new key, `watch` (public.stats_watch_read(live total, now())):
--     the newest row's watch figures, plus
--     new_slot        the newest count's minted money (stats_world.minted — the words table's minted kinds, 0228)
--     new_day         Σ minted over the 24 h to the newest count (the Overview's "Printed, 24 h" sum)
--     total_day_ago, day_ago_at, total_delta_day   the world's total at the newest count at or before
--                     now − 24 h, and the LIVE total (the same sum stats_now serves as `total`) less it
--   No figure here decides anything. Nothing is lit; no purse, price or flow moves.
--
-- ── HUNKS SLICED FROM THE LIVE BODIES (each occurs once; reverses to its pre-image; ACL / volatility /
--    definer / config unchanged) — kept to ONE LINE each, because osn-stats-all-live re-cuts both ──────
--   public.tick_stats ×1   after the world row's `get diagnostics v_w`: if a row was written, set its watch.
--   world.stats_now ×1     after `'at', now(),`: the `watch` key.
--
-- ── WHAT IT SELF-ASSERTS (own probe rows; the probe is rolled back whole) ───────────────────────
--   (a) the hunks reverse; ACL / volatility / definer / config unmoved; the two new functions server-only;
--       the registry unchanged; the three walls at 0; stats_world.watch a nullable jsonb.
--   (b) world.stats_now() serves every key it served before, plus `watch`, and nothing else.
--   (c) THE TIME-WINDOWED FIGURES, ON PROBE ROWS ALONE: the window is put ten years ahead (T = now() + 3650
--       days — no real row stands there, and nothing depends on the hour of day). Planted: two pairs' mids
--       at T−70 / −50 / −30 / −10 min (100→110→99 and 100→100→104; the −70 row is outside the hour) →
--       steps 0.1, 0.1, 0, 0.04 → p50 0.07, p90 0.1, 4 steps; three gifts of a probe company at T−1 h,
--       T−2 h (in) and T−25 h (out) → 2 gifts, 8,000.
--   (d) THE READ, ON PROBE ROWS ALONE: three stats_world rows planted at T, T−20 h and T−24 h−5 min (minted
--       500, 300, 9,999; the last one's holders 1,000 + 2,000 + 3,000 + 4,000) and stats_watch_read(12,345, T)
--       → new_slot 500, new_day 800, total_day_ago 10,000, total_delta_day 2,345, and the newest row's watch
--       keys merged in.
--   (e) THE STATE FIGURES, each in ONE statement against its own definition (a statement is one snapshot,
--       so the live game moving cannot make them disagree): under_reserve and under_thin equal the
--       harbours counted inline; stats_thin_purse 0 → under_thin 0 (no purse is under zero, 0122);
--       merchant_broke_pct 0 → broke 0. No table that grows on production is counted or summed against a
--       remembered figure, and tick_stats is never RUN here (its retention would compact real rows at T).
-- ROLLBACK (forward): reverse the two hunks (each old text is in this file); drop the two functions, the
-- column and the two knobs.
-- VERSION: 0229 = 0228 (E1) + 1 at the time of writing — RENUMBER TO PROD HEAD + 1 AT PUSH, AFTER E1
-- (and the _0229 suffixes, the probe uuid and this header's tags with it).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '5min', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regclass('public.capital_gifts') is null or to_regprocedure('public.economy_closed()') is null then
    raise exception '0229 refuses: 0228 (E1, the books say what moves) is not in this world';
  end if;
  if to_regclass('public.stats_live') is null or to_regprocedure('world.stats_now()') is null
     or to_regprocedure('public.tick_stats(timestamptz)') is null or to_regclass('public.price_history') is null then
    raise exception '0229 refuses: 0214 / 0224 (the stats rollup and its live read) is not in this world';
  end if;
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'stats_world' and column_name = 'watch') then
    raise exception '0229 refuses: stats_world.watch already exists — this has been applied once';
  end if;
end $guard$;

create or replace function pg_temp.occurs_0229(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 0. THE PRE-IMAGES (LF-normalised), and what the live read served before ──────────────────────
create temp table defs_before_0229 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('public.tick_stats(timestamptz)'), ('world.stats_now()')) f(fn);

create temp table before_0229 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select array_agg(k order by k) from jsonb_object_keys(coalesce(world.stats_now(), '{}'::jsonb)) k) as now_keys,
       (world.stats_now() is null) as now_empty;

-- ── 1. THE KNOBS ────────────────────────────────────────────────────────────────────────────────
insert into public.world_config (key, value, description) values
  ('stats_thin_purse', to_jsonb(10000),
   '0229 (docs/CLOSED_ECONOMY.md §7): a harbour whose purse is under this many ducats is counted "thin" by public.stats_watch ("harbours under 10 k").'),
  ('merchant_broke_pct', to_jsonb(0.2),
   '0229 (docs/CLOSED_ECONOMY.md §5.2, §7): a merchant company whose purse is under this × her capital is BROKE — counted by public.stats_watch; E4''s capital gift reads the same knob.');

-- ── 2. THE COLUMN ───────────────────────────────────────────────────────────────────────────────
alter table public.stats_world add column watch jsonb;
comment on column public.stats_world.watch is
  '0229: the closed economy''s watch figures at this count (public.stats_watch): under_reserve, under_thin, thin, broke, gifts, gifts_ducats, swing_p50, swing_p90, swing_steps. Null on rows counted before 0229.';

-- ── 3. THE COUNT — one function, called by tick_stats on the row it writes ─────────────────────
create function public.stats_watch(p_now timestamptz)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0229: the figures docs/CLOSED_ECONOMY.md §7 watches, at p_now (header of 0229). Reads; decides nothing.
  with b as (
    select t.port_id, t.reserve, public.treasury_balance(t.port_id) as bal from public.port_treasury t
  ), s as (
    select abs(h.mid / nullif(lag(h.mid) over (partition by h.port_id, h.good_id order by h.slot), 0) - 1) as step
      from public.price_history h
     where h.at > p_now - interval '1 hour' and h.at <= p_now
  ), sw as (
    select percentile_cont(0.5) within group (order by s.step) as p50,
           percentile_cont(0.9) within group (order by s.step) as p90,
           count(*) as n
      from s where s.step is not null
  ), g as (
    select count(*) as n, coalesce(sum(c.ducats), 0) as d
      from public.capital_gifts c
     where c.created_at > p_now - interval '24 hours' and c.created_at <= p_now
  )
  select jsonb_build_object(
           'under_reserve', (select count(*) from b where b.bal < b.reserve),
           'under_thin',    (select count(*) from b where b.bal < public.wc_num('stats_thin_purse')),
           'thin',          public.wc_num('stats_thin_purse'),
           'broke',         (select count(*) from public.npc_houses h join public.players p on p.id = h.player_id
                              where p.ducats < h.capital * public.wc_num('merchant_broke_pct')),
           'gifts', g.n, 'gifts_ducats', g.d,
           'swing_p50', round(sw.p50::numeric, 4), 'swing_p90', round(sw.p90::numeric, 4), 'swing_steps', sw.n)
    from sw, g
$$;
comment on function public.stats_watch(timestamptz) is
  '0229: the closed economy''s watch figures at p_now — harbours under reserve and under stats_thin_purse, broke merchants (merchant_broke_pct), capital gifts in the 24 h to p_now, and the price swing (median / p90 of |mid step| over the hour to p_now in price_history). Written onto stats_world.watch by tick_stats. Server-only.';
revoke all on function public.stats_watch(timestamptz) from public, anon, authenticated;

-- ── 4. THE READ — served by world.stats_now() as `watch` ────────────────────────────────────────
create function public.stats_watch_read(p_total bigint, p_now timestamptz)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0229: the newest count's watch figures, its new money and the day's, and the world total's move over
  -- 24 h: p_total (the caller's LIVE total) less the total of the newest count at or before p_now − 24 h.
  -- Null when no count exists yet.
  select jsonb_build_object(
           'at', l.at,
           'new_slot', l.minted,
           'new_day', (select coalesce(sum(w.minted), 0) from public.stats_world w where w.at > l.at - interval '24 hours' and w.at <= l.at),
           'total_day_ago', a.total, 'day_ago_at', a.at,
           'total_delta_day', p_total - a.total)
         || coalesce(l.watch, '{}'::jsonb)
    from (select w.at, w.minted, w.watch from public.stats_world w where w.at <= p_now order by w.slot desc limit 1) l
    left join lateral (select w.at, w.players + w.merchants + w.cities + w.set_aside as total
                         from public.stats_world w where w.at <= p_now - interval '24 hours'
                        order by w.slot desc limit 1) a on true
$$;
comment on function public.stats_watch_read(bigint, timestamptz) is
  '0229: what world.stats_now serves as `watch` — the newest count''s stats_world.watch, new_slot (its minted), new_day (Σ minted over the 24 h to it), and total_day_ago / day_ago_at / total_delta_day (the live total less the newest count at or before p_now − 24 h). Server-only.';
revoke all on function public.stats_watch_read(bigint, timestamptz) from public, anon, authenticated;

-- ── 5. THE HUNKS (each occurs exactly once in the live body) ─────────────────────────────────────
create temp table hunks_0229 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0229 values
('public.tick_stats(timestamptz)', 1,
$h$  get diagnostics v_w = row_count;
$h$,
$h$  get diagnostics v_w = row_count;
  if v_w = 1 then update public.stats_world set watch = public.stats_watch(p_now) where slot = v_slot; end if;   -- 0229: the closed economy's watch figures (docs/CLOSED_ECONOMY.md §7)
$h$),
('world.stats_now()', 1,
$h$           'at', now(),
$h$,
$h$           'at', now(),
           'watch', public.stats_watch_read(l.players + d.players + l.merchants + d.merchants + l.cities + d.cities + l.set_aside + d.set_aside, now()),   -- 0229: docs/CLOSED_ECONOMY.md §7
$h$);

create or replace function pg_temp.recut_0229(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := (select def from defs_before_0229 where fn = p_fn);
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0229 where fn = p_fn order by n loop
    v_n := pg_temp.occurs_0229(v_def, h.old);
    if v_n <> 1 then
      raise exception '0229 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0229(fn) from defs_before_0229 order by fn;

-- ── 6. THE SELF-ASSERT ──────────────────────────────────────────────────────────────────────────
do $$
declare
  c_uid    constant uuid := '00000000-0229-4000-8000-000000000001';
  v_before record;
  v_d      record; v_h record; v_pp record; v_def text;
  v_t      timestamptz := now() + interval '3650 days';
  v_port   uuid; v_pcode text; v_g1 uuid; v_g2 uuid; v_p uuid;
  v_w      jsonb; v_r jsonb; v_now jsonb;
  v_keys   text[];
  v_ok     boolean;
  v_ms     numeric; v_c timestamptz;
  v_out    jsonb;
begin
  select * into v_before from before_0229;

  -- (a) THE RE-CUTS reverse to their pre-images; ACL / volatility / definer / config unmoved
  for v_d in select * from defs_before_0229 loop
    v_def := replace(pg_get_functiondef(v_d.fn::regprocedure), E'\r', '');
    for v_h in select * from hunks_0229 where fn = v_d.fn order by n desc loop
      if pg_temp.occurs_0229(v_def, v_h.new) <> 1 then
        raise exception '0229 self-assert FAIL: hunk % of % is not in the new body exactly once', v_h.n, v_d.fn;
      end if;
      v_def := replace(v_def, v_h.new, v_h.old);
    end loop;
    if v_def <> v_d.def then
      raise exception '0229 self-assert FAIL: % does not reverse to its pre-image', v_d.fn;
    end if;
    select coalesce(p.proacl::text, '') as acl, p.provolatile as vol, p.prosecdef as secdef, coalesce(p.proconfig::text, '') as cfg
      into v_pp from pg_proc p where p.oid = v_d.fn::regprocedure;
    if v_pp.acl <> v_d.acl or v_pp.vol <> v_d.vol or v_pp.secdef <> v_d.secdef or v_pp.cfg <> v_d.cfg then
      raise exception '0229 self-assert FAIL: % changed its ACL, volatility, definer or config', v_d.fn;
    end if;
  end loop;
  if has_function_privilege('authenticated', 'public.stats_watch(timestamptz)', 'execute')
     or has_function_privilege('anon', 'public.stats_watch(timestamptz)', 'execute')
     or has_function_privilege('authenticated', 'public.stats_watch_read(bigint, timestamptz)', 'execute')
     or has_function_privilege('anon', 'public.stats_watch_read(bigint, timestamptz)', 'execute') then
    raise exception '0229 self-assert FAIL: a client role can execute a server-only function';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> v_before.entry_points then
    raise exception '0229 self-assert FAIL: the registry moved';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0229 self-assert FAIL: a wall moved';
  end if;
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'stats_world'
                  and column_name = 'watch' and data_type = 'jsonb' and is_nullable = 'YES') then
    raise exception '0229 self-assert FAIL: stats_world.watch is not a nullable jsonb';
  end if;

  -- (b) THE LIVE READ: every old key, plus `watch`, nothing else (values move with the live game; keys do not)
  v_now := world.stats_now();
  if not v_before.now_empty then
    select array_agg(k order by k) into v_keys from jsonb_object_keys(v_now) k where k <> 'watch';
    if v_keys is distinct from v_before.now_keys or not (v_now ? 'watch') then
      raise exception '0229 self-assert FAIL: stats_now keys are % (+watch: %), were %', v_keys, v_now ? 'watch', v_before.now_keys;
    end if;
  end if;

  -- (e) THE STATE FIGURES, each in ONE statement against its own definition (one snapshot)
  select (w->>'under_reserve')::int = (select count(*) from public.port_treasury t where public.treasury_balance(t.port_id) < t.reserve)
     and (w->>'under_thin')::int    = (select count(*) from public.port_treasury t where public.treasury_balance(t.port_id) < 10000)
     and (w->>'broke')::int         = (select count(*) from public.npc_houses h join public.players p on p.id = h.player_id where p.ducats < h.capital * 0.2)
     and (w->>'thin')::numeric = 10000
    into v_ok
    from (select public.stats_watch(now()) as w) x;
  if not v_ok then
    raise exception '0229 self-assert FAIL: a state figure disagrees with its definition in the same statement: %', public.stats_watch(now());
  end if;

  begin
    -- (c) THE TIME-WINDOWED FIGURES, on probe rows alone, ten years ahead
    select p.id, p.code into v_port, v_pcode from public.ports p where p.kind = 'HARBOUR' order by p.code limit 1;
    select g.id into v_g1 from public.goods g order by g.code limit 1;
    select g.id into v_g2 from public.goods g where g.id <> v_g1 order by g.code limit 1;
    if exists (select 1 from public.price_history h where h.at > v_t - interval '2 days')
       or exists (select 1 from public.stats_world w where w.at > v_t - interval '2 days')
       or exists (select 1 from public.capital_gifts c where c.created_at > v_t - interval '2 days') then
      raise exception '0229 self-assert FAIL: a real row stands in the probe''s window ten years ahead';
    end if;
    insert into public.price_history (port_id, good_id, slot, at, mid, stock)
    select v_port, x.good, public.drift_slot_of(v_t - make_interval(mins => x.mins)), v_t - make_interval(mins => x.mins), x.mid, 0
      from (values (v_g1, 70, 50::numeric), (v_g1, 50, 100), (v_g1, 30, 110), (v_g1, 10, 99),
                   (v_g2, 50, 100), (v_g2, 30, 100), (v_g2, 10, 104)) x(good, mins, mid);
    if exists (select 1 from public.players p where p.auth_uid = c_uid or p.company_name = 'Casa das Contas 0229') then
      raise exception '0229 self-assert FAIL: the probe house already exists';
    end if;
    v_p := public.new_house(c_uid, 'Casa das Contas 0229', 'PRT', 'LIS');
    insert into public.capital_gifts (port_id, player_id, ducats, called_from, created_at) values
      (v_port, v_p, 5000, null,   v_t - interval '1 hour'),
      (v_port, v_p, 3000, v_port, v_t - interval '2 hours'),
      (v_port, v_p, 7000, null,   v_t - interval '25 hours');
    v_c := clock_timestamp();
    v_w := public.stats_watch(v_t);
    v_ms := round(extract(epoch from clock_timestamp() - v_c) * 1000, 1);
    if (v_w->>'swing_steps')::int <> 4 or (v_w->>'swing_p50')::numeric <> 0.07 or (v_w->>'swing_p90')::numeric <> 0.1
       or (v_w->>'gifts')::int <> 2 or (v_w->>'gifts_ducats')::bigint <> 8000 then
      raise exception '0229 self-assert FAIL: on the probe rows the watch read %, expected 4 steps, p50 0.07, p90 0.1, 2 gifts, 8000', v_w;
    end if;

    -- (d) THE READ, on planted rollup rows alone
    insert into public.stats_world (slot, at, game_day, players, merchants, cities, set_aside, minted, removed, moved,
                                    sold, bought, units, trades, period, recent, watch)
    select public.drift_slot_of(x.at), x.at, world.game_day(x.at), x.pl, x.me, x.ci, x.sa, x.minted, 0, 0, 0, 0, 0, 0,
           '{}'::jsonb, '{}'::jsonb, x.watch
      from (values (v_t,                                         0::bigint, 0::bigint, 0::bigint, 0::bigint, 500::bigint, v_w),
                   (v_t - interval '20 hours',                   0, 0, 0, 0, 300, null::jsonb),
                   (v_t - interval '24 hours' - interval '5 minutes', 1000, 2000, 3000, 4000, 9999, null)) x(at, pl, me, ci, sa, minted, watch);
    v_r := public.stats_watch_read(12345, v_t);
    if (v_r->>'new_slot')::bigint <> 500 or (v_r->>'new_day')::bigint <> 800
       or (v_r->>'total_day_ago')::bigint <> 10000 or (v_r->>'total_delta_day')::bigint <> 2345
       or (v_r->>'day_ago_at')::timestamptz <> v_t - interval '24 hours' - interval '5 minutes'
       or (v_r->>'swing_steps')::int <> 4 or (v_r->>'gifts')::int <> 2 or not (v_r ? 'under_reserve') or not (v_r ? 'broke') then
      raise exception '0229 self-assert FAIL: the read over the planted rows served %', v_r;
    end if;

    -- (e, cont.) THE KNOBS ARE READ: thin 0 → none under it (no purse is under zero); broke pct 0 → none broke
    update public.world_config set value = to_jsonb(0) where key in ('stats_thin_purse', 'merchant_broke_pct');
    v_w := public.stats_watch(v_t);
    if (v_w->>'under_thin')::int <> 0 or (v_w->>'broke')::int <> 0 or (v_w->>'thin')::numeric <> 0 then
      raise exception '0229 self-assert FAIL: with both knobs at 0 the watch read %', v_w;
    end if;

    raise exception using errcode = 'ZX229', message = jsonb_build_object('read', v_r, 'ms', v_ms)::text;
  exception when sqlstate 'ZX229' then
    v_out := sqlerrm::jsonb;
  end;

  -- nothing of the probe survives
  if exists (select 1 from public.players p where p.auth_uid = c_uid)
     or exists (select 1 from public.price_history h where h.at > v_t - interval '2 days')
     or exists (select 1 from public.stats_world w where w.at > v_t - interval '2 days')
     or exists (select 1 from public.capital_gifts c where c.created_at > v_t - interval '2 days')
     or public.wc_num('stats_thin_purse') <> 10000 or public.wc_num('merchant_broke_pct') <> 0.2 then
    raise exception '0229 self-assert FAIL: the probe left rows behind';
  end if;

  raise notice '0229 self-assert ok: THE FIGURES WATCH THE MONEY. tick_stats writes stats_world.watch (one line); stats_now serves `watch` (one line) beside every key it had. On probe rows ten years ahead: swing 4 steps p50 0.07 p90 0.1, gifts 2 / 8,000 (the 25-h one out), read new_slot 500 new_day 800 total_day_ago 10,000 delta 2,345 (%). State figures equal their definitions in one statement; knobs at 0 → 0. stats_watch on the probe window % ms. Live now: %. Registry unchanged; walls 0.',
    v_out->'read', v_out->>'ms', public.stats_watch(now());
end $$;
