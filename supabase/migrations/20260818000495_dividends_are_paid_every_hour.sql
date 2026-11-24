-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- news: none (dark: nothing changes for a player until the owner lights dividend_hourly_enabled)
-- 0495 - DIVIDENDS ARE PAID EVERY HOUR  (dark: the owner's switch dividend_hourly_enabled, false. Slice `dividend-hourly`,
--   docs/design/hq-corp-2026-11-24.md D6 (there numbered 0494), docs/design/hq-corp-economy-2026-11-24.md section 9)
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, row 373: "investing will give you dividends every hour". Dev log docs/dev-log/2026-11-24-dividend-hourly.md.
--
-- TODAY (read in the live bodies, not guessed). public.tick_city runs at :37 every hour; its step 6 calls public.city_coupons for a
--   harbour only when port_treasury.coupon_day is before today's real day, so once a real day (the 00:37 UTC run). city_coupons then adds
--   each row's due to city_shares.accrued ("set aside"), never to a purse: the holder is paid only by public.collect_coupons, when a
--   fleet of hers makes that harbour. A holder who buys shares and never sails there is never paid. That is the fault under the owner's
--   words: her 461,384 d. of shares (docs/dev-log/2026-11-24-rate-why.md) earned her purse nothing.
--
-- LIT (dividend_hourly_enabled true):
--   * public.tick_city step 6 (ONE hunk) calls public.city_coupons for every harbour once per real hour (port_treasury.coupon_hour).
--   * public.city_coupons (ONE hunk) hands the call to public.city_coupon_hour (new) and returns its answer; the daily form never runs.
--   * public.city_coupon_hour, per harbour and hour:
--       due      = round(public.coupon_day_of(harbour, holder, all she paid there) / 24): 1/24 of her day's coupon, the rule's one home
--                  (0456): works_coupon_day x 0148's multiplier. At 0.018 a day that is 0.075 % of what she paid, an hour.
--       payable  = least(sum of dues, the city's surplus above its reserve (public.city_surplus), its PROFIT OVER THE TRAILING 24 HOURS / 24)
--                  shared pro rata, exactly as the daily form shares (cumulative rounding, to the coin).
--       paid     = public.city_pays(harbour, holder, 'DIVIDEND', pay): the city's purse to her purse in one act. No fleet, no arrival.
--     THE TRAILING 24 HOURS: port_treasury.profit is the city's own net since the last coupon (0312; the roll adds it, DIVIDEND, SHARE and
--     the crown's money are not profit: public.flow_is_profit). Each hour that figure is moved into port_treasury.profit_hours, a ring of
--     24 slots (slot = real hour mod 24), and set back to 0; the trailing figure is the ring's sum. A missed hour is a 0 slot and its profit
--     lands in the next hour that runs. An hour with no profit of its own pays from the ring; a city that lost over the 24 hours pays 0.
--     Nothing is owed and nothing is carried, as 0312 decided.
--   * city_shares is not written (no row a holder an hour): `accrued` and `accrued_day` stand. OLD `accrued` IS COLLECTED AS TODAY, by
--     public.collect_coupons at arrival (not touched by this file).
--   * coupon_day is kept at today, so the daily form resumes cleanly if the switch goes dark again (its first day then pays at most one
--     day's coupon from the profit since the last paid hour).
-- CLOSED ECONOMY: every coin a holder gets leaves that city's purse in the same act (public.city_pays: treasury_post(-pay), then
--   credit(+pay)); nothing is minted. The self-assert checks purse + holders to the coin in every scene; proof 198 checks the world's sum.
-- LOCK ORDER (0122: the house first, the harbour second, everywhere): the hour locks the holders' rows FIRST and never waits for one
--   (FOR UPDATE SKIP LOCKED, the tick's own rule: "never waits"), then the harbour. A holder whose row is held at that instant (she is
--   mid-trade) is not paid that hour; her part stays in the city; nothing is carried. No lock at all is taken at a harbour with no holder
--   or with nothing to pay.
-- DARK (dividend_hourly_enabled false, as deployed): BYTE-IDENTICAL. tick_city's loop reads the same rows in the same order (the added
--   test is `or (false and ...)`); city_coupons reads the switch and falls through to its old lines. The self-assert runs one daily
--   coupon scene before the hunks and again after them, dark, and compares every figure, row and flow.
-- DECIDED BY DEFAULT (the owner may reverse):
--   1. The 24 hours live on the purse row (two columns), not in a new table: no new row, bounded by construction at 24 slots a harbour.
--   2. One credit a holder a harbour an hour (her kinds there are summed first): one ledger row, not one a kind.
--   3. A holder is paid from her first hour (no part-hour pro rata; at most one hour's coupon, 0.075 %, for a buy made a minute before :37).
--   4. A locked holder misses the hour rather than making the tick wait (see LOCK ORDER).
--   5. No event and no news line for a paid hour: the ledger row (kind DIVIDEND) is what Holdings (world.holdings `paid`) and the Ledger's
--      Dividends line (public.company_rate_for, 0493) already read. No client change.
-- THE HUNKS (2; each once in the live body, each reverses): public.tick_city x1, public.city_coupons x1.
-- NEW: public.dividend_hourly_on() (the switch), public.real_hour(at) (the hour's number, beside 0312's public.real_day),
--   public.city_coupon_hour(port, at) (the rule). All server only (public, anon, authenticated, service_role revoked).
--   port_treasury.profit_hours bigint[] default '{}', port_treasury.coupon_hour int default 0. One knob: dividend_hourly_enabled false.
-- NOT CHANGED: works_coupon_day and every other knob and switch; public.coupon_day_of, public.collect_coupons, public.city_pays,
--   public.invest_for, public.city_surplus, public.flow_is_profit, world.holdings; the cron job (still '37 * * * *'); any client read.
-- ROWS. Dark: none (the two columns keep their defaults; nothing writes them).
--   Lit, an hour (H = harbours with a purse, 254 in the chain's world; P = holder-and-harbour pairs paid that hour):
--     port_treasury      H row updates (the ring; today the same rows are already updated once an hour by step 3, and once a day by the coupon)
--     ledger             P rows (kind DIVIDEND; today: one a holder a harbour at each ARRIVAL that collects)
--     treasury_flows     P rows, deleted by the next hour's roll into the daybook's one DIVIDEND row a harbour a game day (today: 1 a harbour a day)
--     stats_live_deltas  2 P rows (the journal of 0224: the city's and the holder's figure), folded by its own job
--     players            P row updates (the purse)
--     city_shares        0 (today: every row once a day)
--   That is at most (H + 5 P) / 60 rows a minute, in one run at :37. P is read by the lead before the switch is lit
--   (scripts/ops/harness/dividend-hourly/before-0495.sql, `pairs`): this file adds no load while dark.
-- budget: none while dark; lit, about H + 5 P rows an hour as above (no table, no cron job, no index, no autovacuum setting is made).
-- retention: none, bounded by 24 slots a harbour in port_treasury.profit_hours (a column of the one-row-a-harbour purse; no table is made).
-- THE TICK'S COST (local, PGlite, proof 198 prints it): dark, step 6 is one switch read more an hour. Lit, step 6 is one
--   public.city_coupon_hour a harbour an hour (a row read, 24 slots summed, one row update), plus one public.city_pays a pair paid.
-- LOCKS: ALTER TABLE public.port_treasury ADD COLUMN x2 with constant defaults (no rewrite; ACCESS EXCLUSIVE for an instant),
--   CREATE OR REPLACE x2 by hunks, CREATE FUNCTION x3, one knob. Deploy away from minute :37. TIME: about a second. BUDGET:
--   statement_timeout 45 s, lock_timeout 5 s; fails above 30 s.
-- ROLLBACK (forward, owner only): QUICK, dividend_hourly_enabled false: the next tick pays the daily way again, into `accrued`; what was
--   paid stays paid. FULL: scripts/ops/harness/dividend-hourly/rollback-0495.sql (a draft: reverses the two hunks, drops the three
--   functions, the two columns and the knob).
-- SELF-ASSERT: each hunk once and reversing; no other function moved; the hunked bodies' grants, volatility, definer, search path and
--   owner unmoved; no other knob moved and the switch false; the three new functions server only. THE PROBES (rolled back by raised
--   sentinels; no role is changed; ISOLATED FROM REAL ROWS: the scene's city is a SEA_PLACE, where no house can invest
--   (public.invest_for refuses it) and no purse exists, so every purse row, share row, flow, house and ledger row it reads or writes is
--   its own; no real harbour's purse, lock or holder is touched and public.tick_city is not run). DARK IDENTITY: one daily coupon scene
--   before the hunks and again after them, dark: equal, and no hourly state written. LIT: a holding of 461,384 d. is paid 346 d. an
--   hour straight to a purse that has no fleet, and 0 when the city lost over the 24 hours; one credit for two kinds; the same hour
--   twice pays once; the next hour pays again from the ring; the profit limit, the surplus limit, a losing hour inside a winning day,
--   a ring gone stale, a gap of missed hours, rate 0; old `accrued` untouched by the hour and still collected by
--   public.collect_coupons; in every scene the purse fell by exactly what the holders rose (no coin minted).
--   Proof 198 runs the REAL public.tick_city over the whole world, a holder who bought through public.invest_for and owns no fleet.
-- VERSION: 0495 = 0494 + 1 (the stack 0492, 0493, 0494 is not on prod yet; the lead deploys in number order).
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
do $m$
declare
  c_hunked constant text[] := array['public.tick_city(timestamp with time zone)', 'public.city_coupons(uuid,timestamp with time zone)'];
  c_new    constant text[] := array['public.dividend_hourly_on()', 'public.real_hour(timestamp with time zone)',
                                    'public.city_coupon_hour(uuid,timestamp with time zone)'];
  v_t0         timestamptz := clock_timestamp();
  x            record;
  v_def        text;
  v_pre        text;
  v_old        text;
  v_new        text;
  v_n          int;
  v_fn_before  text;
  v_meta       text;
  v_cfg_before text;
  v_d0         jsonb;
  v_d1         jsonb;
  v_all        jsonb := '{}'::jsonb;
  v_x          jsonb;
  s            record;
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from public.world_config where key = 'dividend_hourly_enabled') or to_regprocedure(c_new[1]) is not null
     or to_regprocedure(c_new[2]) is not null or to_regprocedure(c_new[3]) is not null
     or exists (select 1 from information_schema.columns c where c.table_schema = 'public' and c.table_name = 'port_treasury'
                                                              and c.column_name in ('profit_hours', 'coupon_hour')) then
    raise exception '0495 refuses: it has been applied once';
  end if;
  if exists (select 1 from unnest(c_hunked || array['public.coupon_day_of(uuid,uuid,numeric)', 'public.city_pays(uuid,uuid,text,bigint,uuid)',
                                                    'public.city_surplus(uuid)', 'public.real_day(timestamp with time zone)',
                                                    'public.collect_coupons(uuid,uuid,uuid)', 'public.treasury_lock(uuid)']) f
              where to_regprocedure(f) is null)
     or not exists (select 1 from information_schema.columns c where c.table_schema = 'public' and c.table_name = 'port_treasury' and c.column_name = 'profit') then
    raise exception '0495 refuses: the coupon (0312, 0456) or the purse (0122) is not in this world';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  create temp table pre_0495 (fn text primary key, def text) on commit drop;
  insert into pre_0495 select f, replace(pg_get_functiondef(f::regprocedure), E'\r', '') from unnest(c_hunked) f;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
    into v_cfg_before from public.world_config c;

  -- ── 2. THE SCENE (a temp function; every row it touches is its own: a SEA_PLACE as the city, two probe houses with no fleet) ──
  --    p: {purse, profit, days} and, lit, {lit, ago, ring, rate, next, collect}. Answers {digest (what the dark pair compares), hourly}.
  execute $f$
create function pg_temp.scene_0495(p jsonb)
returns jsonb
language plpgsql
as $body$
declare
  v_now   timestamptz := now();
  v_rday  int := public.real_day(v_now);
  v_hour  int := floor(extract(epoch from v_now) / 3600)::int;
  v_today int := world.game_day(v_now);
  v_lit   boolean := coalesce((p->>'lit')::boolean, false);
  v_port  uuid;
  v_nat   uuid;
  v_a     uuid;
  v_b     uuid;
  v_r     jsonb;
  v_again jsonb;
  v_next  jsonb;
  v_coll  bigint;
  v_row   jsonb;
  v_mid   jsonb;
  v_shares jsonb;
begin
  update public.world_config set value = 'true'::jsonb where key = 'city_treasury_enabled' and value is distinct from 'true'::jsonb;
  update public.world_config set value = to_jsonb(coalesce((p->>'rate')::numeric, 0.018)) where key = 'works_coupon_day';
  if v_lit then
    update public.world_config set value = 'true'::jsonb where key = 'dividend_hourly_enabled';
  end if;
  select q.id into v_port from public.ports q
   where q.kind = 'SEA_PLACE'
     and not exists (select 1 from public.port_treasury t where t.port_id = q.id)
     and not exists (select 1 from public.city_shares cs where cs.port_id = q.id)
     and not exists (select 1 from public.treasury_flows f where f.port_id = q.id)
   order by q.code limit 1;
  if v_port is null then
    raise exception '0495 self-assert FAIL: no sea place without a purse, a share or a flow to stand the scene on';
  end if;
  -- a country that does not hold the place: 0148's multiplier is exactly 1 for the probes, whatever the race says
  select g.nation_id into v_nat from public.great_powers g where g.nation_id is distinct from public.port_nation(v_port) order by g.nation_id limit 1;
  insert into public.players (company_name, nation_id, ducats, is_npc) values ('Probe 0495 a', v_nat, 0, false) returning id into v_a;
  insert into public.players (company_name, nation_id, ducats, is_npc) values ('Probe 0495 b', v_nat, 0, false) returning id into v_b;
  insert into public.port_treasury (port_id, ducats, reserve, profit, coupon_day)
  values (v_port, (p->>'purse')::bigint, 1000, (p->>'profit')::bigint, v_rday - coalesce((p->>'days')::int, 1));
  -- a: the owner's holding, 461,384 d. in one work, with 555 d. set aside from before. b: 1,200,000 d. in two works.
  insert into public.city_shares (port_id, kind, player_id, shares, paid, accrued, accrued_day) values
    (v_port, 'docks', v_a, 10, 461384, 555, v_today - 1000),
    (v_port, 'market', v_b, 30, 1000000, 0, v_today - 1000),
    (v_port, 'inn', v_b, 5, 200000, 0, v_today - 1000);
  if v_lit then
    update public.port_treasury t
       set coupon_hour = case when p ? 'ago' then v_hour - (p->>'ago')::int else 0 end,
           profit_hours = case when p ? 'ring' then array_fill((p->>'ring')::bigint, array[24]) else '{}'::bigint[] end
     where t.port_id = v_port;
  end if;

  v_r     := public.city_coupons(v_port, v_now);
  v_again := public.city_coupons(v_port, v_now);
  if p ? 'next' then
    update public.port_treasury t set profit = (p->>'next')::bigint where t.port_id = v_port;
    v_next := public.city_coupons(v_port, v_now + interval '1 hour');
  end if;
  v_mid := jsonb_build_object(
    'a', (select pl.ducats from public.players pl where pl.id = v_a),
    'b', (select pl.ducats from public.players pl where pl.id = v_b),
    'purse', public.treasury_balance(v_port));
  -- the share rows as the coupon left them (before the old `accrued` is collected below)
  select jsonb_agg(jsonb_build_array(cs.kind, case cs.player_id when v_a then 'a' else 'b' end, cs.shares, cs.paid, cs.accrued,
                                     cs.accrued_day - v_today) order by cs.kind)
    into v_shares from public.city_shares cs where cs.port_id = v_port;
  if p ? 'collect' then
    v_coll := public.collect_coupons(v_a, v_port, null);
  end if;
  select to_jsonb(t) into v_row from public.port_treasury t where t.port_id = v_port;
  return jsonb_build_object(
    'digest', jsonb_build_object(
      'r', v_r, 'again', v_again, 'money', v_mid,
      'row', v_row - 'port_id' - 'updated_at' - 'rolled_at' - 'seeded_at' - 'profit_hours' - 'coupon_hour' - 'coupon_day'
             || jsonb_build_object('coupon_day', (v_row->>'coupon_day')::int - v_rday),
      'shares', v_shares,
      'flows', (select coalesce(jsonb_agg(jsonb_build_array(f.kind, f.ducats, case f.player_id when v_a then 'a' when v_b then 'b' end) order by f.id), '[]'::jsonb)
                  from public.treasury_flows f where f.port_id = v_port),
      'ledger', (select coalesce(jsonb_agg(jsonb_build_array(case l.player_id when v_a then 'a' else 'b' end, l.kind, l.ducats_delta, l.balance_after)
                                           order by l.player_id = v_b, l.balance_after), '[]'::jsonb)
                   from public.ledger l where l.player_id in (v_a, v_b))),
    'hourly', jsonb_build_object(
      'next', v_next, 'collected', v_coll,
      'hour', (v_row->>'coupon_hour')::int - v_hour,
      'ring', v_row->'profit_hours',
      'a_end', (select pl.ducats from public.players pl where pl.id = v_a),
      'a_owed', (select cs.accrued from public.city_shares cs where cs.port_id = v_port and cs.player_id = v_a),
      'fleets', (select count(*) from public.fleets fl where fl.player_id in (v_a, v_b))));
end
$body$
  $f$;

  -- BEFORE the hunks: the daily coupon, as the deployed bodies pay it (a real day due; the profit covers it)
  begin
    raise exception using errcode = 'ZX495', message = pg_temp.scene_0495('{"purse": 10000000, "profit": 1000000, "days": 1}'::jsonb)::text;
  exception when sqlstate 'ZX495' then v_d0 := sqlerrm::jsonb;
  end;
  if (v_d0 #>> '{digest,r,paid}')::bigint is distinct from round(1661384 * 0.018)::bigint or (v_d0 #>> '{digest,again,paid}')::bigint <> 0
     or v_d0 #>> '{digest,money,a}' <> '0' or v_d0 #> '{digest,ledger}' <> '[]'::jsonb then
    raise exception '0495 self-assert FAIL: the daily scene did not pay a day''s coupon into `accrued` before the hunks: %', left(v_d0::text, 900);
  end if;

  -- ── 3. THE KNOB (the owner's switch; dark) ──
  insert into public.world_config (key, value, description) values
    ('dividend_hourly_enabled', 'false'::jsonb,
     '0495: THE SWITCH (the owner''s). true: every hourly public.tick_city pays each holder 1/24 of her day''s coupon (public.coupon_day_of) straight to her purse by public.city_pays, from the city''s purse, limited by the city''s surplus and by its profit over the trailing 24 hours / 24 (public.city_coupon_hour); nothing is added to city_shares.accrued. false: the coupon is paid once a real day into `accrued` and collected at arrival (0312), as before. Old `accrued` is collected at arrival either way.');

  -- ── 4. THE BOOK: the trailing 24 hours, on the purse row ──
  alter table public.port_treasury
    add column profit_hours bigint[] not null default '{}'::bigint[],
    add column coupon_hour int not null default 0;
  comment on column public.port_treasury.profit_hours is
    '0495: the city''s own net (public.flow_is_profit) by real hour, a ring of 24 slots (slot = public.real_hour mod 24, 1-based), written only by public.city_coupon_hour while dividend_hourly_enabled is lit. Its sum is the profit over the trailing 24 hours.';
  comment on column public.port_treasury.coupon_hour is
    '0495: the real hour (public.real_hour) of its last hourly coupon; 0 = never.';

  -- ── 5. THE RULES ──
  execute $f$
create function public.dividend_hourly_on()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0495: THE SWITCH, read once: world_config dividend_hourly_enabled.
  select public.wc('dividend_hourly_enabled') = 'true'::jsonb
$body$
  $f$;

  execute $f$
create function public.real_hour(p_at timestamptz)
returns int
language sql
immutable
as $body$
  -- 0495: the real hour's number (hours since the epoch, UTC), beside 0312's public.real_day. The hour an hourly coupon is paid on.
  select floor(extract(epoch from p_at) / 3600)::int
$body$
  $f$;

  execute $f$
create function public.city_coupon_hour(p_port uuid, p_now timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0495: THE HOURLY COUPON of one harbour (public.city_coupons hands it the call while dividend_hourly_enabled is lit). Once per real hour:
--   1. the city's own net since its last coupon (port_treasury.profit, 0312) moves into the ring of 24 hourly slots and is set to 0; a
--      slot whose hour was missed is 0; the ring's sum is the profit over the trailing 24 hours;
--   2. each holder's due is 1/24 of her day's coupon on all she paid here (public.coupon_day_of, the rule's one home);
--   3. the city pays the least of what is due, what it holds above its reserve, and that trailing profit / 24, pro rata;
--   4. each holder is paid straight to her purse by public.city_pays (kind DIVIDEND): the coin leaves this city's purse, none is minted.
-- The shortfall is not owed and nothing is carried. city_shares is not written: old `accrued` waits for public.collect_coupons as before.
-- LOCK ORDER (0122): the holders' rows first, never waited for (SKIP LOCKED: a holder mid-trade misses this hour), then the harbour.
-- Answers {paid, due, cap, profit_24h}.
declare
  v_hour   int := public.real_hour(p_now);
  v_last   int;
  v_profit bigint;
  v_ring   bigint[];
  v_trail  bigint;
  v_cap    bigint;
  v_free   uuid[] := '{}'::uuid[];
  v_pay    bigint := 0;
  v_due    bigint := 0;
  r        record;
begin
  if not public.city_treasury_on() then
    return jsonb_build_object('paid', 0, 'due', 0);   -- dark purses: public.city_pays would credit from nothing
  end if;
  select t.coupon_hour, t.profit, t.profit_hours into v_last, v_profit, v_ring
    from public.port_treasury t where t.port_id = p_port for update;
  if v_last is null or v_last >= v_hour then
    return jsonb_build_object('paid', 0, 'due', 0);   -- no purse, or this hour is paid
  end if;
  -- 1. THE RING: the 24 hours ending with this one. A slot written at or before the last coupon is kept; one after it was missed (0).
  select array_agg(q.v order by q.h % 24), coalesce(sum(q.v), 0)::bigint into v_ring, v_trail
    from (select h.h, case when h.h = v_hour then v_profit
                           when h.h <= v_last then coalesce(v_ring[h.h % 24 + 1], 0)
                           else 0 end::bigint as v
            from generate_series(v_hour - 23, v_hour) h(h)) q;
  update public.port_treasury t
     set profit = 0, coupon_hour = v_hour, coupon_day = public.real_day(p_now), profit_hours = v_ring
   where t.port_id = p_port;
  v_cap := greatest(0, v_trail) / 24;
  -- the locks, only where something can be paid: the holders first and never waited for, then the harbour, before the purse is judged
  if v_cap > 0 and exists (select 1 from public.city_shares s where s.port_id = p_port) then
    select coalesce(array_agg(q.id), '{}'::uuid[]) into v_free
      from (select pl.id from public.players pl
             where pl.id in (select s.player_id from public.city_shares s where s.port_id = p_port)
             order by pl.id
               for update skip locked) q;
    perform public.treasury_lock(p_port);
  end if;
  -- 2-4. the dues, the payable and each holder's part, in one statement (the daily form's own split, by holder)
  for r in
    with d as (
      select s.player_id, round(public.coupon_day_of(p_port, s.player_id, sum(s.paid)) / 24)::bigint as due
        from public.city_shares s where s.port_id = p_port
       group by s.player_id
    ), t as (
      select coalesce(sum(d.due), 0)::bigint as total,
             least(coalesce(sum(d.due), 0), v_cap,
                   case when v_cap > 0 then greatest(0, public.city_surplus(p_port)) else 0 end)::bigint as payable
        from d
    ), a as (
      select d.player_id, d.due,
             case when t.total > 0 then
               round(sum(d.due) over w * t.payable::numeric / t.total)
               - round((sum(d.due) over w - d.due) * t.payable::numeric / t.total) else 0 end::bigint as pay
        from d cross join t window w as (order by d.due, d.player_id)
    )
    select a.player_id, a.due, a.pay from a order by a.player_id
  loop
    v_due := v_due + r.due;
    if r.pay > 0 and r.player_id = any (v_free) then
      perform public.city_pays(p_port, r.player_id, 'DIVIDEND', r.pay, null);
      v_pay := v_pay + r.pay;
    end if;
  end loop;
  return jsonb_build_object('paid', v_pay, 'due', v_due, 'cap', v_cap, 'profit_24h', v_trail);
end
$body$
  $f$;

  -- grants: all three server only (service_role too: the platform grants execute on a new function by default, 0459's first push)
  foreach v_def in array c_new loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', v_def::regprocedure);
  end loop;

  -- ── 6. THE HUNKS (each OLD text once in the live body; each reverses) ──
  create temp table hunks_0495 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0495 values
  ('public.tick_city(timestamp with time zone)', 1,
$h$      for hp in select t.port_id from public.port_treasury t where t.coupon_day < v_rday order by t.port_id loop
$h$,
$h$      for hp in select t.port_id from public.port_treasury t
                 where t.coupon_day < v_rday
                    -- 0495 (dark: dividend_hourly_enabled): lit, every harbour once per real hour (public.city_coupon_hour pays, through public.city_coupons)
                    or ((select public.dividend_hourly_on()) and t.coupon_hour < public.real_hour(p_now))
                 order by t.port_id loop
$h$),
  ('public.city_coupons(uuid,timestamp with time zone)', 1,
$h$begin
  perform public.treasury_lock(p_port);   -- before the purse is judged
$h$,
$h$begin
  -- 0495 (dark: dividend_hourly_enabled): lit, the coupon is paid every real hour, straight to each holder's purse, by public.city_coupon_hour;
  -- the daily form below then never runs. Dark, the lines below are all that runs, as before.
  if public.dividend_hourly_on() then
    return public.city_coupon_hour(p_port, p_now);
  end if;
  perform public.treasury_lock(p_port);   -- before the purse is judged
$h$);

  for x in select distinct h.fn from hunks_0495 h loop
    v_pre := (select p.def from pre_0495 p where p.fn = x.fn);
    v_def := v_pre;
    for v_old, v_new, v_n in select h.old, h.new, h.ord from hunks_0495 h where h.fn = x.fn order by h.ord loop
      if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then
        raise exception '0495 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', v_n, x.fn,
          (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
      end if;
      v_def := replace(v_def, v_old, v_new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(x.fn::regprocedure), E'\r', '');
    for v_old, v_new, v_n in select h.old, h.new, h.ord from hunks_0495 h where h.fn = x.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, v_new, ''))) / length(v_new) <> 1 then
        raise exception '0495 self-assert FAIL: hunk % of % is not in the new body once', v_n, x.fn;
      end if;
      v_def := replace(v_def, v_new, v_old);
    end loop;
    if v_def <> v_pre then
      raise exception '0495 self-assert FAIL: % does not reverse to its pre-image', x.fn;
    end if;
  end loop;
  if (select count(*) from hunks_0495) <> 2 or (select count(distinct h.fn) from hunks_0495 h) <> 2 then
    raise exception '0495 self-assert FAIL: the hunks are not the 2 of the two re-cut bodies';
  end if;

  -- ── 7. THE SELF-ASSERT: the catalog ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked || c_new) u(q)))) <> v_fn_before then
    raise exception '0495 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0495 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked body moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
        from public.world_config c where c.key <> 'dividend_hourly_enabled') <> v_cfg_before
     or public.wc('dividend_hourly_enabled') is distinct from 'false'::jsonb or public.dividend_hourly_on() then
    raise exception '0495 self-assert FAIL: a knob other than dividend_hourly_enabled moved, or the switch is not false';
  end if;
  if exists (select 1 from unnest(c_new) u(q)
              where has_function_privilege('anon', u.q::regprocedure, 'execute') or has_function_privilege('authenticated', u.q::regprocedure, 'execute')
                 or has_function_privilege('service_role', u.q::regprocedure, 'execute') or has_function_privilege('public', u.q::regprocedure, 'execute'))
     or (select p.provolatile from pg_proc p where p.oid = c_new[1]::regprocedure) <> 's'
     or (select p.provolatile from pg_proc p where p.oid = c_new[2]::regprocedure) <> 'i' then
    raise exception '0495 self-assert FAIL: a new function is reachable by a client or service_role, or the switch is not STABLE, or the hour is not IMMUTABLE';
  end if;
  if exists (select 1 from public.port_treasury t where t.coupon_hour <> 0 or t.profit_hours <> '{}'::bigint[]) then
    raise exception '0495 self-assert FAIL: a purse row was born with hourly state';
  end if;

  -- ── 8. DARK IDENTITY: the same daily scene after the hunks, the switch dark ──
  begin
    raise exception using errcode = 'ZX495', message = pg_temp.scene_0495('{"purse": 10000000, "profit": 1000000, "days": 1}'::jsonb)::text;
  exception when sqlstate 'ZX495' then v_d1 := sqlerrm::jsonb;
  end;
  if v_d1->'digest' is distinct from v_d0->'digest' then
    raise exception '0495 self-assert FAIL: DARK IS NOT IDENTICAL. Before: % After: %', left((v_d0->'digest')::text, 900), left((v_d1->'digest')::text, 900);
  end if;
  if v_d1 #>> '{hourly,hour}' is null or (v_d1 #>> '{hourly,hour}')::int >= 0 or v_d1 #> '{hourly,ring}' <> '[]'::jsonb then
    raise exception '0495 self-assert FAIL: dark, the daily coupon wrote hourly state: %', v_d1->'hourly';
  end if;

  -- ── 9. LIT, on the probe (each scene rolled back alone; the switch is lit only inside it) ──
  for s in select * from (values
    ('covered', '{"lit": true, "purse": 10000000, "profit": 100000, "next": 0, "collect": true}'::jsonb),   -- 100,000 earned: 4,166 an hour may be paid; 1,246 is due
    ('thin',    '{"lit": true, "purse": 10000000, "profit": 12000}'),                                        -- 12,000 over the 24 hours: 500 an hour
    ('trail',   '{"lit": true, "purse": 10000000, "profit": -34000, "ago": 1, "ring": 2000}'),               -- a losing hour in a winning day: 23 x 2,000 - 34,000 = 12,000
    ('stale',   '{"lit": true, "purse": 10000000, "profit": 2400, "ago": 30, "ring": 1000000}'),             -- the ring is 30 hours old: none of it counts
    ('gap',     '{"lit": true, "purse": 10000000, "profit": 3000, "ago": 3, "ring": 1000}'),                 -- two hours missed: 21 x 1,000 + 3,000
    ('loss',    '{"lit": true, "purse": 10000000, "profit": -500}'),                                         -- a loss
    ('lostday', '{"lit": true, "purse": 10000000, "profit": 2000, "ago": 1, "ring": -100}'),                 -- this hour earned, the 24 hours lost: 0
    ('poor',    '{"lit": true, "purse": 1400, "profit": 100000}'),                                           -- the surplus (400 above the reserve) is the limit
    ('knob0',   '{"lit": true, "purse": 10000000, "profit": 100000, "rate": 0}')
  ) v(name, p) loop
    begin
      raise exception using errcode = 'ZX495', message = pg_temp.scene_0495(s.p)::text;
    exception when sqlstate 'ZX495' then v_all := v_all || jsonb_build_object(s.name, sqlerrm::jsonb);
    end;
  end loop;
  drop function pg_temp.scene_0495(jsonb);

  for s in select k.key as name, k.value as v from jsonb_each(v_all) k loop
    v_x := s.v->'digest';
    v_n := coalesce((s.v #>> '{hourly,next,paid}')::int, 0);
    -- CLOSED: the purse fell by exactly what the two purses rose; the flows say the same; every paid coin is a ledger row
    if (v_x #>> '{money,a}')::bigint + (v_x #>> '{money,b}')::bigint <> (v_x #>> '{r,paid}')::bigint + v_n
       or (select coalesce(sum((f->>1)::bigint), 0) from jsonb_array_elements(v_x->'flows') f where f->>0 = 'DIVIDEND') <> -((v_x #>> '{r,paid}')::bigint + v_n)
       or (select count(*) from jsonb_array_elements(v_x->'flows') f where f->>0 <> 'DIVIDEND') <> 0 then
      raise exception '0495 self-assert FAIL: what left the city is not what the holders were paid in %: %', s.name, left(s.v::text, 900);
    end if;
    if (v_x #>> '{money,purse}')::bigint < 1000 then
      raise exception '0495 self-assert FAIL: a purse went under its reserve in %: %', s.name, left(s.v::text, 900);
    end if;
    -- the hour is closed once: a second call pays nothing; the period's profit is in the ring; the daily clock is kept at today
    if (v_x #>> '{again,paid}')::bigint <> 0 or (v_x #>> '{row,profit}')::bigint <> 0 or (v_x #>> '{row,coupon_day}')::int <> 0
       or (s.v #>> '{hourly,hour}')::int <> (case when s.v #> '{hourly,next}' <> 'null'::jsonb then 1 else 0 end)
       or jsonb_array_length(s.v #> '{hourly,ring}') <> 24 then
      raise exception '0495 self-assert FAIL: the hour did not close once in %: %', s.name, left(s.v::text, 900);
    end if;
    -- city_shares is not written: `accrued` (a's 555) and every stamp stand
    if v_x->'shares' is distinct from '[["docks","a",10,461384,555,-1000],["inn","b",5,200000,0,-1000],["market","b",30,1000000,0,-1000]]'::jsonb then
      raise exception '0495 self-assert FAIL: the hour wrote city_shares in %: %', s.name, v_x->'shares';
    end if;
    if (s.v #>> '{hourly,fleets}')::int <> 0 then
      raise exception '0495 self-assert FAIL: a probe house has a fleet in %', s.name;
    end if;
  end loop;

  -- THE OWNER'S HOLDING: 461,384 d. is paid 346 d. an hour (0.075 %), straight to a purse with no fleet; b's two works are one credit of 900
  v_x := v_all->'covered';
  if v_x #> '{digest,r}' is distinct from '{"paid": 1246, "due": 1246, "cap": 4166, "profit_24h": 100000}'::jsonb
     or v_x #> '{digest,ledger}' is distinct from '[["a","DIVIDEND",346,346],["a","DIVIDEND",346,692],["a","DIVIDEND",555,1247],["b","DIVIDEND",900,900],["b","DIVIDEND",900,1800]]'::jsonb
     or v_x #>> '{digest,money,purse}' <> (10000000 - 2 * 1246)::text then
    raise exception '0495 self-assert FAIL: a covered hour did not pay 1/24 of the day''s coupon to the purse: %', left(v_x::text, 900);
  end if;
  -- the next hour earned nothing itself and pays from the 24 hours; old `accrued` then collected as today (555), on top of 2 x 346
  if v_x #> '{hourly,next}' is distinct from '{"paid": 1246, "due": 1246, "cap": 4166, "profit_24h": 100000}'::jsonb
     or (v_x #>> '{hourly,collected}')::bigint <> 555 or (v_x #>> '{hourly,a_end}')::bigint <> 2 * 346 + 555 or (v_x #>> '{hourly,a_owed}')::bigint <> 0 then
    raise exception '0495 self-assert FAIL: the next hour, or the collection of old `accrued`: %', left(v_x::text, 900);
  end if;
  if v_all #> '{thin,digest,r}' is distinct from '{"paid": 500, "due": 1246, "cap": 500, "profit_24h": 12000}'::jsonb
     or v_all #>> '{thin,digest,money,a}' <> '139' or v_all #>> '{thin,digest,money,b}' <> '361' then
    raise exception '0495 self-assert FAIL: the trailing profit / 24 does not limit the hour, pro rata: %', v_all #> '{thin,digest}';
  end if;
  if v_all #> '{trail,digest,r}' is distinct from '{"paid": 500, "due": 1246, "cap": 500, "profit_24h": 12000}'::jsonb then
    raise exception '0495 self-assert FAIL: a losing hour inside a winning day: %', v_all #> '{trail,digest,r}';
  end if;
  if v_all #> '{stale,digest,r}' is distinct from '{"paid": 100, "due": 1246, "cap": 100, "profit_24h": 2400}'::jsonb then
    raise exception '0495 self-assert FAIL: a ring older than 24 hours still counted: %', v_all #> '{stale,digest,r}';
  end if;
  if v_all #> '{gap,digest,r}' is distinct from '{"paid": 1000, "due": 1246, "cap": 1000, "profit_24h": 24000}'::jsonb then
    raise exception '0495 self-assert FAIL: two missed hours were not two empty slots: %', v_all #> '{gap,digest,r}';
  end if;
  if v_all #> '{loss,digest,r}' is distinct from '{"paid": 0, "due": 1246, "cap": 0, "profit_24h": -500}'::jsonb
     or v_all #> '{lostday,digest,r}' is distinct from '{"paid": 0, "due": 1246, "cap": 0, "profit_24h": -300}'::jsonb
     or v_all #> '{loss,digest,ledger}' <> '[]'::jsonb or v_all #> '{lostday,digest,ledger}' <> '[]'::jsonb then
    raise exception '0495 self-assert FAIL: a city that lost over the 24 hours paid: % / %', v_all #> '{loss,digest,r}', v_all #> '{lostday,digest,r}';
  end if;
  if v_all #> '{poor,digest,r}' is distinct from '{"paid": 400, "due": 1246, "cap": 4166, "profit_24h": 100000}'::jsonb
     or v_all #>> '{poor,digest,money,purse}' <> '1000' then
    raise exception '0495 self-assert FAIL: the surplus does not limit the hour: %', v_all #> '{poor,digest}';
  end if;
  if (v_all #>> '{knob0,digest,r,paid}')::bigint <> 0 or (v_all #>> '{knob0,digest,r,due}')::bigint <> 0 then
    raise exception '0495 self-assert FAIL: rate 0 paid: %', v_all #> '{knob0,digest,r}';
  end if;

  -- ── 10. NOTHING OF THE PROBE SURVIVES; the switch is dark ──
  if exists (select 1 from public.players p where p.company_name like 'Probe 0495 %')
     or exists (select 1 from public.port_treasury t join public.ports q on q.id = t.port_id where q.kind = 'SEA_PLACE')
     or exists (select 1 from public.port_treasury t where t.coupon_hour <> 0 or t.profit_hours <> '{}'::bigint[])
     or public.dividend_hourly_on()
     or (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
           from public.world_config c where c.key <> 'dividend_hourly_enabled') <> v_cfg_before then
    raise exception '0495 self-assert FAIL: the probe left rows behind, or a knob moved';
  end if;
  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0495 self-assert FAIL: the file took % (budget 30 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0495 self-assert ok: DIVIDENDS ARE PAID EVERY HOUR (dark). 2 hunks once and reversing (tick_city, city_coupons); no other function moved; the hunked bodies'' grants and settings unmoved; three new functions server only; one knob, dividend_hourly_enabled false; port_treasury.profit_hours and coupon_hour. DARK IDENTICAL: the daily scene paid % d. into `accrued` before and after, every row and flow equal, no hourly state. LIT, on a probe with no fleet: 461,384 d. paid 346 d. an hour to the purse (b: one credit of 900 for two works), the same hour twice paid once, the next hour paid again from the 24 hours, old accrued 555 untouched then collected; trailing profit 12,000 -> 500 paid of 1,246 due (139 / 361); a losing hour in a winning day 500; a stale ring 100; two missed hours 1,000; a loss and a lost day 0; surplus 400 -> 400; rate 0 -> 0; in every scene the purse fell by what the holders rose. % ms.',
    v_d0 #>> '{digest,r,paid}', round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0495;
  drop table pre_0495;
end $m$;
