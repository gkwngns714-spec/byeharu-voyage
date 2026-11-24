-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- news: none (dark: nothing changes for a player until the owner lights dividend_hourly_enabled)
-- 0495 - DIVIDENDS ARE PAID EVERY HOUR  (dark: the owner's switch dividend_hourly_enabled, false. Slice `dividend-hourly`,
--   docs/design/hq-corp-2026-11-24.md D6 (there numbered 0494), docs/design/hq-corp-economy-2026-11-24.md section 9)
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, row 373: "investing will give you dividends every hour". Dev log docs/dev-log/2026-11-24-dividend-hourly.md.
--
-- TODAY (read in the live bodies, not guessed). public.tick_city runs at :37 every hour; its step 6 calls public.city_coupons for a
--   harbour once a real day (the 00:37 UTC run). city_coupons pays least(the dues, the city's surplus, its profit of the day), pro
--   rata, into city_shares.accrued ("set aside": the DIVIDEND flow leaves the city's purse then), never into a purse: a holder is paid
--   only by public.collect_coupons, when a fleet of hers makes that harbour. A holder who buys shares and never sails there is never
--   paid. That is the fault under the owner's words: her 461,384 d. of shares earned her purse nothing.
--
-- THE FIRST BUILD OF THIS FILE WAS REFUSED BY THE DATABASE BUDGET (the lead's prod read, 2026-11-24 20:57 UTC): 3,657 holder-and-harbour
--   pairs, 3,656 of them MERCHANTS and 1 a player; 254 harbours. Paying every pair every hour was up to 18,500 row writes an hour and
--   about 88,000 new ledger rows a day. So:
--
-- THE RULE, LIT (dividend_hourly_enabled true). ONE COMPUTATION A DAY, AS TODAY; ONLY ITS PAY-OUT TO PLAYERS IS HOURLY.
--   * THE DAY'S COUPON IS UNTOUCHED: public.city_coupons computes it once a real day for EVERY holder, merchant and player together, by
--     today's one statement: the same dues, the same least(dues, surplus, the day's profit), the same pro rata split, the same DIVIDEND
--     flow, the same `accrued`. So the hourly pay-out and the merchants' coupon share the one surplus and the one profit limit BY
--     CONSTRUCTION: there is one figure, computed once, and nothing can be paid twice against the same profit. The city pays, to the
--     coin, what today's rule lets it pay: never more.
--   * A MERCHANT (players.is_npc) stays exactly on today's path: `accrued`, collected at arrival. No row of hers gets a new value.
--   * A PLAYER's part of the day's coupon is, besides, marked on her share row to be paid out over the next 24 hours (one hunk on
--     city_coupons' own UPDATE): drip_left = what is still to pay out, drip_hour = round(that / 24).
--   * EVERY HOUR public.tick_city (one hunk) calls public.city_coupon_hour: each player with something to pay out is paid
--     least(drip_hour, drip_left, accrued) from each such row, STRAIGHT TO HER PURSE, in one credit (kind DIVIDEND) for all her
--     harbours: `accrued` falls by the same coin. No fleet, no arrival. The coin was set aside for her by the city at the day's coupon:
--     it moves from `accrued` to her purse exactly as public.collect_coupons moves it. Nothing is minted; no city purse is read or
--     written by the hour; no harbour without a human holder is touched at all.
--   So a player's dividend arrives every hour, and it is yesterday's coupon: her first hourly coin comes after the first daily coupon
--   that follows her buy (the 00:37 UTC run), then 1/24 of it every hour.
-- AN HOUR SHE MISSES IS NOT LOST. The hour never waits for a holder's row (the house first, FOR UPDATE SKIP LOCKED, then her share rows,
--   0122's order; no harbour lock: no purse is judged). A holder who is mid-trade at that instant, or an hour the tick did not run, is
--   simply not paid then: the coin stays in her drip_left and her `accrued`. The next day's coupon folds what is left into the new
--   pay-out, and she can collect all of it at any arrival, as today. It is bounded by what was set aside for her: no lump can exceed it.
-- TWICE IN ONE HOUR IS IMPOSSIBLE: a row is paid only while its drip_at is before this hour, read under its row lock and set to this
--   hour in the same statement; and never more than `accrued` holds.
-- OLD `accrued` IS COLLECTED AS TODAY: only coin marked by a lit day's coupon is paid out hourly (drip_left never exceeds it); what was
--   set aside before the switch waits for public.collect_coupons at arrival. An arrival collects everything, marked or not, as today;
--   the hour then finds nothing left and clears the mark.
-- DARK (as deployed): BYTE-IDENTICAL. city_coupons' UPDATE writes the three new columns back to themselves; tick_city reads the switch
--   and calls nothing. The self-assert runs one daily coupon before the hunks and again after them, dark: every figure, row and flow.
-- DECIDED BY DEFAULT (the owner may reverse):
--   1. Yesterday's coupon, paid out hourly, not a coupon computed each hour. An hourly limit cannot keep "never more than today's rule"
--      (0312's warning: hour 1 earns 100 and pays it, hour 2 loses 100); a pay-out of a coupon already computed keeps it exactly.
--   2. One credit a player an hour for all her harbours (one ledger row), not one a harbour.
--   3. No event and no news for a paid hour: Holdings (world.holdings `paid`, `owed`) and the Ledger's Dividends line
--      (public.company_rate_for, 0493) already read ledger kind DIVIDEND and `accrued`. No client change.
--   4. If the switch goes dark again nothing is lost: what is left is in `accrued` and is collected at arrival.
-- THE HUNKS (2; each once in the live body, each reverses): public.tick_city x1, public.city_coupons x1.
-- NEW: public.dividend_hourly_on() (the switch), public.real_hour(at) (the hour's number, beside 0312's public.real_day),
--   public.city_coupon_hour(at) (the hourly pay-out). All server only (public, anon, authenticated, service_role revoked).
--   city_shares.drip_left bigint, drip_hour bigint, drip_at int, all default 0. One knob: dividend_hourly_enabled false.
-- NOT CHANGED: works_coupon_day and every other knob and switch; public.coupon_day_of, public.collect_coupons, public.city_pays,
--   public.invest_for, public.city_surplus, public.flow_is_profit, world.holdings; port_treasury; the cron job; any client read.
-- ROWS. Dark: none (the three columns keep 0; nothing writes another value).
--   Lit, an hour, for P = player-and-harbour pairs with a pay-out left, held by N players (merchants: none, ever):
--     city_shares        P row updates          ledger             N rows (kind DIVIDEND)
--     players            N row updates          stats_live_deltas  N rows (the purses) + P rows (the set-aside figure, by its trigger)
--     port_treasury 0, treasury_flows 0 (the hour touches no city).
--   P = 1 (prod today: one player, one harbour): 5 row writes an hour, 24 ledger rows a day.
--   P = 100 (100 players, one harbour each): 500 row writes an hour (8 a minute, in one run at :37), 2,400 ledger rows a day.
--   Once a day, lit or dark, as today: city_coupons updates every share row; lit, the same update also marks the players' rows.
-- budget: none while dark; lit, about 3 N + 2 P rows an hour as above (no table, no cron job, no index, no autovacuum setting is made).
-- retention: none (no table is made; three columns on public.city_shares, one row a holder a work a harbour).
-- THE TICK'S COST (local, PGlite, proof 198 prints it): dark, step 6 is one switch read more an hour. Lit, one pass over city_shares for
--   the rows with a pay-out left, then one small statement and one credit a player.
-- LOCKS: ALTER TABLE public.city_shares ADD COLUMN x3 with constant defaults (no rewrite; ACCESS EXCLUSIVE for an instant),
--   CREATE OR REPLACE x2 by hunks, CREATE FUNCTION x3, one knob. Deploy away from minute :37. TIME: about a second. BUDGET:
--   statement_timeout 45 s, lock_timeout 5 s; fails above 30 s.
-- ROLLBACK (forward, owner only): QUICK, dividend_hourly_enabled false: the next tick pays out nothing; what is left waits in
--   `accrued` for an arrival, as today. FULL: scripts/ops/harness/dividend-hourly/rollback-0495.sql (a draft: reverses the two hunks,
--   drops the three functions, the three columns and the knob).
-- SELF-ASSERT: each hunk once and reversing; no other function moved; the hunked bodies' grants, volatility, definer, search path and
--   owner unmoved; no other knob moved and the switch false; the three new functions server only. THE PROBES (rolled back by raised
--   sentinels; no role is changed; ISOLATED FROM REAL ROWS: the scene's city is a SEA_PLACE, where no house can invest
--   (public.invest_for refuses it) and no purse exists, so every purse row, share row, flow, house and ledger row it writes is its
--   own; public.tick_city is not run; the hourly pay-out, which looks at every player, finds only the probe: nothing is marked in a
--   world where the switch has never been lit, and the self-assert checks that before and after). DARK IDENTITY: the daily coupon before
--   the hunks and after them, dark: equal, nothing marked. A LIT DAY: the city pays exactly the dark day's figures (the same paid, due,
--   flow, purse and `accrued` for the merchant and the player: never above today's rule), also when the profit limit binds; the
--   player's 461,384 d. is then paid 346 d. an hour to a purse with no fleet, 24 hours running; the merchant is paid nothing hourly
--   and her rows hold no mark; the same hour twice pays once; missed hours are not lost and fold into the next day's pay-out; an
--   arrival collects everything once and the hours after it pay nothing; old `accrued` (555) is never paid out hourly; a city that
--   lost pays nothing; the city's purse row is not written by any hour.
--   Proof 198 runs the REAL public.tick_city over the whole world. scripts/ci/dividend-race.sh runs the hour under two sessions.
-- VERSION: 0495 = prod head 0494 + 1.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
do $m$
declare
  c_hunked constant text[] := array['public.tick_city(timestamp with time zone)', 'public.city_coupons(uuid,timestamp with time zone)'];
  c_new    constant text[] := array['public.dividend_hourly_on()', 'public.real_hour(timestamp with time zone)',
                                    'public.city_coupon_hour(timestamp with time zone)'];
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
     or exists (select 1 from information_schema.columns c where c.table_schema = 'public' and c.table_name = 'city_shares'
                                                              and c.column_name in ('drip_left', 'drip_hour', 'drip_at')) then
    raise exception '0495 refuses: it has been applied once';
  end if;
  if exists (select 1 from unnest(c_hunked || array['public.coupon_day_of(uuid,uuid,numeric)', 'public.credit(uuid,text,bigint,uuid)',
                                                    'public.real_day(timestamp with time zone)', 'public.collect_coupons(uuid,uuid,uuid)']) f
              where to_regprocedure(f) is null)
     or not exists (select 1 from information_schema.columns c where c.table_schema = 'public' and c.table_name = 'players' and c.column_name = 'is_npc') then
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

  -- ── 2. THE SCENE (a temp function; every row it writes is its own: a SEA_PLACE as the city, a player `a` and a merchant `m`, no fleet) ──
  --    p: {purse, profit} and {lit, hours [offsets], twice, collect, after [offsets], day2 <profit>}.
  --    Answers {daily (what the dark pair and every lit day are compared on), drip0, hours, twice, collected, after, r2, fin}.
  execute $f$
create function pg_temp.scene_0495(p jsonb)
returns jsonb
language plpgsql
as $body$
declare
  v_now    timestamptz := now();
  v_rday   int := public.real_day(v_now);
  v_today  int := world.game_day(v_now);
  v_lit    boolean := coalesce((p->>'lit')::boolean, false);
  v_port   uuid;
  v_nat    uuid;
  v_a      uuid;
  v_m      uuid;
  v_r      jsonb;
  v_again  jsonb;
  v_r2     jsonb;
  v_daily  jsonb;
  v_drip0  jsonb;
  v_row0   jsonb;
  v_hours  jsonb := '[]'::jsonb;
  v_twice  jsonb := '[]'::jsonb;
  v_after  jsonb := '[]'::jsonb;
  v_coll   bigint;
  v_h      int;
begin
  update public.world_config set value = 'true'::jsonb where key = 'city_treasury_enabled' and value is distinct from 'true'::jsonb;
  update public.world_config set value = to_jsonb(0.018) where key = 'works_coupon_day';
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
  insert into public.players (company_name, nation_id, ducats, is_npc) values ('Probe 0495 m', v_nat, 0, true) returning id into v_m;
  insert into public.port_treasury (port_id, ducats, reserve, profit, coupon_day)
  values (v_port, (p->>'purse')::bigint, 1000, (p->>'profit')::bigint, v_rday - 1);
  -- a, the player: the owner's holding, 461,384 d., with 555 d. set aside from before. m, the merchant: 1,200,000 d. in two works.
  insert into public.city_shares (port_id, kind, player_id, shares, paid, accrued, accrued_day) values
    (v_port, 'docks', v_a, 10, 461384, 555, v_today - 1000),
    (v_port, 'market', v_m, 30, 1000000, 0, v_today - 1000),
    (v_port, 'inn', v_m, 5, 200000, 0, v_today - 1000);

  -- THE DAY'S COUPON, and a second call the same day
  v_r     := public.city_coupons(v_port, v_now);
  v_again := public.city_coupons(v_port, v_now);
  select to_jsonb(t) - 'port_id' - 'updated_at' - 'rolled_at' - 'seeded_at' - 'coupon_day' || jsonb_build_object('coupon_day', t.coupon_day - v_rday)
    into v_row0 from public.port_treasury t where t.port_id = v_port;
  v_daily := jsonb_build_object(
    'r', v_r, 'again', v_again, 'row', v_row0, 'purse', public.treasury_balance(v_port),
    'a', (select pl.ducats from public.players pl where pl.id = v_a), 'm', (select pl.ducats from public.players pl where pl.id = v_m),
    'shares', (select jsonb_agg(jsonb_build_array(cs.kind, case cs.player_id when v_a then 'a' else 'm' end, cs.shares, cs.paid, cs.accrued,
                                                  cs.accrued_day - v_today) order by cs.kind)
                 from public.city_shares cs where cs.port_id = v_port),
    'flows', (select coalesce(jsonb_agg(jsonb_build_array(f.kind, f.ducats, f.player_id) order by f.id), '[]'::jsonb)
                from public.treasury_flows f where f.port_id = v_port),
    'ledger', (select count(*) from public.ledger l where l.player_id in (v_a, v_m)));
  select jsonb_agg(jsonb_build_array(cs.kind, to_jsonb(cs)->'drip_left', to_jsonb(cs)->'drip_hour') order by cs.kind)
    into v_drip0 from public.city_shares cs where cs.port_id = v_port;

  -- THE HOURS (only after the hunks: the function is 0495's)
  for v_h in select e.value::int from jsonb_array_elements_text(coalesce(p->'hours', '[]'::jsonb)) e loop
    v_hours := v_hours || (public.city_coupon_hour(v_now + make_interval(hours => v_h))->'paid');
    if p ? 'twice' then
      v_twice := v_twice || (public.city_coupon_hour(v_now + make_interval(hours => v_h))->'paid');
    end if;
  end loop;
  if p ? 'collect' then
    v_coll := public.collect_coupons(v_a, v_port, null);
  end if;
  for v_h in select e.value::int from jsonb_array_elements_text(coalesce(p->'after', '[]'::jsonb)) e loop
    v_after := v_after || (public.city_coupon_hour(v_now + make_interval(hours => v_h))->'paid');
  end loop;
  -- THE NEXT DAY'S COUPON (the rows stamped a full day back again, so the day is whole whatever the game clock says)
  if p ? 'day2' then
    update public.port_treasury t set profit = (p->>'day2')::bigint where t.port_id = v_port;
    update public.city_shares cs set accrued_day = world.game_day(v_now + interval '1 day') - 1000 where cs.port_id = v_port;
    v_r2 := public.city_coupons(v_port, v_now + interval '1 day');
  end if;

  return jsonb_build_object(
    'daily', v_daily, 'drip0', v_drip0, 'hours', v_hours, 'twice', v_twice, 'collected', v_coll, 'after', v_after, 'r2', v_r2,
    'fin', jsonb_build_object(
      'a', (select pl.ducats from public.players pl where pl.id = v_a), 'm', (select pl.ducats from public.players pl where pl.id = v_m),
      'purse', public.treasury_balance(v_port),
      'city_unwritten', (select to_jsonb(t) - 'port_id' - 'updated_at' - 'rolled_at' - 'seeded_at' - 'coupon_day' || jsonb_build_object('coupon_day', t.coupon_day - v_rday)
                           from public.port_treasury t where t.port_id = v_port) is not distinct from v_row0,
      'shares', (select jsonb_agg(jsonb_build_array(cs.kind, cs.accrued, to_jsonb(cs)->'drip_left', to_jsonb(cs)->'drip_hour') order by cs.kind)
                   from public.city_shares cs where cs.port_id = v_port),
      'flows', (select count(*) from public.treasury_flows f where f.port_id = v_port),
      'ledger_a', (select coalesce(jsonb_agg(l.ducats_delta order by l.balance_after), '[]'::jsonb) from public.ledger l where l.player_id = v_a and l.kind = 'DIVIDEND'),
      'ledger_a_other', (select count(*) from public.ledger l where l.player_id = v_a and l.kind <> 'DIVIDEND'),
      'ledger_m', (select count(*) from public.ledger l where l.player_id = v_m),
      'fleets', (select count(*) from public.fleets fl where fl.player_id in (v_a, v_m))));
end
$body$
  $f$;

  -- BEFORE the hunks: the daily coupon, as the deployed bodies pay it (a real day due; the profit covers it)
  begin
    raise exception using errcode = 'ZX495', message = pg_temp.scene_0495('{"purse": 10000000, "profit": 1000000}'::jsonb)::text;
  exception when sqlstate 'ZX495' then v_d0 := sqlerrm::jsonb;
  end;
  if (v_d0 #>> '{daily,r,paid}')::bigint is distinct from round(1661384 * 0.018)::bigint or (v_d0 #>> '{daily,again,paid}')::bigint <> 0
     or v_d0 #>> '{daily,a}' <> '0' or (v_d0 #>> '{daily,ledger}')::int <> 0 then
    raise exception '0495 self-assert FAIL: the daily scene did not pay a day''s coupon into `accrued` before the hunks: %', left(v_d0::text, 900);
  end if;

  -- ── 3. THE KNOB (the owner's switch; dark) ──
  insert into public.world_config (key, value, description) values
    ('dividend_hourly_enabled', 'false'::jsonb,
     '0495: THE SWITCH (the owner''s). true: a PLAYER''s part of each day''s coupon (public.city_coupons, computed once a real day for every holder as before) is paid out to her purse over the next 24 hours, 1/24 each hourly public.tick_city (public.city_coupon_hour), from what the city set aside for her (city_shares.accrued); no fleet has to arrive. Merchants are paid as before. false: every coupon waits in `accrued` and is collected at arrival (0312), as before. `accrued` is collected at arrival either way.');

  -- ── 4. THE BOOK: the hourly pay-out, on the holder's own share row ──
  alter table public.city_shares
    add column drip_left bigint not null default 0,
    add column drip_hour bigint not null default 0,
    add column drip_at int not null default 0;
  comment on column public.city_shares.drip_left is
    '0495: how much of `accrued` is still to be paid out hourly to this PLAYER (public.city_coupon_hour). Set by public.city_coupons at a day''s coupon while dividend_hourly_enabled is lit; always 0 for a merchant and while dark. Never more than `accrued` is paid.';
  comment on column public.city_shares.drip_hour is
    '0495: what one hour pays out of drip_left: round(drip_left / 24) at the day''s coupon, at least 1.';
  comment on column public.city_shares.drip_at is
    '0495: the real hour (public.real_hour) of this row''s last hourly pay-out; 0 = never. A row is paid once an hour.';

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
  -- 0495: the real hour's number (hours since the epoch, UTC), beside 0312's public.real_day. The hour an hourly pay-out is made in.
  select floor(extract(epoch from p_at) / 3600)::int
$body$
  $f$;

  execute $f$
create function public.city_coupon_hour(p_now timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0495: THE HOURLY PAY-OUT (public.tick_city calls it once a run while dividend_hourly_enabled is lit). Each PLAYER with coin still to
-- pay out (city_shares.drip_left, marked by public.city_coupons at the day's coupon; a merchant is never marked) is paid
-- least(drip_hour, drip_left, accrued) from each such row, in ONE credit (kind DIVIDEND) for all her harbours, and `accrued` falls by
-- the same coin: what public.collect_coupons does at an arrival, an hour's part at a time. The coin left the city at the day's coupon
-- (its DIVIDEND flow): nothing is minted, and no city's purse is read or written here.
-- ONCE AN HOUR: a row is paid only while drip_at is before this hour, read under its row lock and set in the same statement.
-- LOCK ORDER (0122): the house's row first, then her share rows; neither is waited for (SKIP LOCKED). A holder who is mid-trade is not
-- paid this hour and loses nothing: the coin stays in drip_left and `accrued`, for the next hour, the next day's coupon or an arrival.
-- Answers {paid, holders, rows}.
declare
  v_hour  int := public.real_hour(p_now);
  h       record;
  v_sum   bigint;
  v_k     int;
  v_paid  bigint := 0;
  v_n     int := 0;
  v_rows  int := 0;
begin
  for h in
    select pl.id from public.players pl
     where not pl.is_npc
       and pl.id in (select s.player_id from public.city_shares s where s.drip_left > 0 and s.drip_at < v_hour)
     order by pl.id
       for update of pl skip locked
  loop
    with c as (
      select s.port_id, s.kind, s.player_id, least(s.drip_hour, s.drip_left, s.accrued) as pay
        from public.city_shares s
       where s.player_id = h.id and s.drip_left > 0 and s.drip_at < v_hour
         for update skip locked
    ), u as (
      update public.city_shares s
         set accrued = s.accrued - c.pay,
             -- an arrival collected it all meanwhile (`accrued` 0): nothing is left to pay out
             drip_left = case when s.accrued - c.pay <= 0 then 0 else s.drip_left - c.pay end,
             drip_at = v_hour
        from c where s.port_id = c.port_id and s.kind = c.kind and s.player_id = c.player_id
      returning c.pay
    )
    select coalesce(sum(u.pay), 0), count(*) into v_sum, v_k from u;
    v_rows := v_rows + v_k;
    if v_sum > 0 then
      perform public.credit(h.id, 'DIVIDEND', v_sum, null);   -- the same credit public.collect_coupons makes
      v_paid := v_paid + v_sum;
      v_n := v_n + 1;
    end if;
  end loop;
  return jsonb_build_object('paid', v_paid, 'holders', v_n, 'rows', v_rows);
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
$h$        v_skipped := v_skipped + (v_due - v_pay);
      end loop;
$h$,
$h$        v_skipped := v_skipped + (v_due - v_pay);
      end loop;
      -- 0495 (dark: dividend_hourly_enabled): lit, every hour, each PLAYER's part of the last day's coupon is paid out to her purse, 1/24 an
      -- hour, from what the city set aside for her (public.city_coupon_hour). No city's purse moves; merchants are not paid here.
      if public.dividend_hourly_on() then
        perform public.city_coupon_hour(p_now);
      end if;
$h$),
  ('public.city_coupons(uuid,timestamp with time zone)', 1,
$h$    update public.city_shares s set accrued = s.accrued + a.pay, accrued_day = v_today
      from a where s.port_id = p_port and s.kind = a.kind and s.player_id = a.player_id
$h$,
$h$    update public.city_shares s set accrued = s.accrued + a.pay, accrued_day = v_today,
           -- 0495 (dark: dividend_hourly_enabled): lit, a PLAYER's part of this coupon (and what is left of the last one) is marked to be paid
           -- out to her purse over the next 24 hours (public.city_coupon_hour). Dark, and for every merchant, both keep their value.
           drip_left = case when (select public.dividend_hourly_on()) and not (select pl.is_npc from public.players pl where pl.id = s.player_id)
                            then least(s.drip_left, s.accrued) + a.pay else s.drip_left end,
           drip_hour = case when (select public.dividend_hourly_on()) and not (select pl.is_npc from public.players pl where pl.id = s.player_id)
                            then greatest(sign((least(s.drip_left, s.accrued) + a.pay)::numeric), round((least(s.drip_left, s.accrued) + a.pay) / 24.0))::bigint
                            else s.drip_hour end
      from a where s.port_id = p_port and s.kind = a.kind and s.player_id = a.player_id
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
  -- nothing is marked in a world where the switch was never lit: so the hourly pay-out below can find only the probe's rows
  if exists (select 1 from public.city_shares cs where cs.drip_left <> 0 or cs.drip_hour <> 0 or cs.drip_at <> 0) then
    raise exception '0495 self-assert FAIL: a share row was born with a pay-out mark';
  end if;

  -- ── 8. DARK IDENTITY: the same daily scene after the hunks, the switch dark (and the hour, called dark, finds nothing) ──
  begin
    raise exception using errcode = 'ZX495', message = pg_temp.scene_0495('{"purse": 10000000, "profit": 1000000, "hours": [0, 1]}'::jsonb)::text;
  exception when sqlstate 'ZX495' then v_d1 := sqlerrm::jsonb;
  end;
  if v_d1->'daily' is distinct from v_d0->'daily' then
    raise exception '0495 self-assert FAIL: DARK IS NOT IDENTICAL. Before: % After: %', left((v_d0->'daily')::text, 900), left((v_d1->'daily')::text, 900);
  end if;
  if v_d1->'drip0' is distinct from '[["docks", 0, 0], ["inn", 0, 0], ["market", 0, 0]]'::jsonb or v_d1->'hours' <> '[0, 0]'::jsonb
     or v_d1 #>> '{fin,a}' <> '0' then
    raise exception '0495 self-assert FAIL: dark, the day''s coupon marked a pay-out, or the hour paid: % / %', v_d1->'drip0', v_d1->'hours';
  end if;

  -- ── 9. LIT, on the probe (each scene rolled back alone; the switch is lit only inside it) ──
  for s in select * from (values
    ('thin0',   '{"purse": 10000000, "profit": 12000}'::jsonb),                                              -- DARK, the profit limit binding: what today's rule pays
    ('day',     '{"lit": true, "purse": 10000000, "profit": 1000000, "twice": true, "collect": true, "after": [24, 25],
                  "hours": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23]}'),   -- a whole lit day, then an arrival
    ('thin',    '{"lit": true, "purse": 10000000, "profit": 12000, "hours": [0]}'),                          -- lit, the profit limit binding
    ('missed',  '{"lit": true, "purse": 10000000, "profit": 1000000, "hours": [0, 1, 5], "day2": 1000000}'), -- 21 hours missed, then the next day's coupon
    ('arrive',  '{"lit": true, "purse": 10000000, "profit": 1000000, "hours": [0, 1, 2], "collect": true, "after": [3, 4]}'),   -- an arrival in the middle
    ('loss',    '{"lit": true, "purse": 10000000, "profit": -500, "hours": [0, 1]}')                         -- the city lost: nothing to pay out
  ) v(name, p) loop
    begin
      raise exception using errcode = 'ZX495', message = pg_temp.scene_0495(s.p)::text;
    exception when sqlstate 'ZX495' then v_all := v_all || jsonb_build_object(s.name, sqlerrm::jsonb);
    end;
  end loop;
  drop function pg_temp.scene_0495(jsonb);

  -- NEVER ABOVE TODAY'S RULE: lit, the day's coupon is the dark day's, to the coin and the row (paid, due, the flow, the purse, every
  -- `accrued`, the merchant's and the player's): the full day against the dark pair, the thin day against the dark thin day.
  if v_all #> '{day,daily}' is distinct from v_d0->'daily' or v_all #> '{missed,daily}' is distinct from v_d0->'daily'
     or v_all #> '{arrive,daily}' is distinct from v_d0->'daily' or v_all #> '{thin,daily}' is distinct from v_all #> '{thin0,daily}'
     or (v_all #>> '{thin0,daily,r,paid}')::bigint <> 12000 or (v_all #>> '{thin0,daily,r,due}')::bigint <> 29905 then
    raise exception '0495 self-assert FAIL: lit, the city did not pay exactly what today''s rule pays: lit % dark %; thin lit % dark %',
      left((v_all #> '{day,daily}')::text, 500), left((v_d0->'daily')::text, 500), left((v_all #> '{thin,daily}')::text, 400), left((v_all #> '{thin0,daily}')::text, 400);
  end if;
  for s in select k.key as name, k.value as v from jsonb_each(v_all) k where k.key <> 'thin0' loop
    -- THE MERCHANT: nothing hourly, no mark, no ledger row. NO CITY PURSE: the hours wrote no purse row and no flow (the day's own stand).
    if (s.v #>> '{fin,m}')::bigint <> 0 or (s.v #>> '{fin,ledger_m}')::int <> 0
       or exists (select 1 from jsonb_array_elements(s.v #> '{fin,shares}') e where e->>0 <> 'docks' and (e->>2 <> '0' or e->>3 <> '0'))
       or exists (select 1 from jsonb_array_elements(s.v->'drip0') e where e->>0 <> 'docks' and (e->>1 <> '0' or e->>2 <> '0')) then
      raise exception '0495 self-assert FAIL: a merchant was paid hourly or marked in %: %', s.name, left(s.v::text, 900);
    end if;
    if s.v #> '{r2}' = 'null'::jsonb and ((s.v #>> '{fin,city_unwritten}')::boolean is not true or (s.v #>> '{fin,purse}') <> (s.v #>> '{daily,purse}')
                                           or (s.v #>> '{fin,flows}')::int <> jsonb_array_length(s.v #> '{daily,flows}')) then
      raise exception '0495 self-assert FAIL: an hour wrote a city''s purse or a flow in %: %', s.name, left(s.v::text, 900);
    end if;
    -- NO COIN MINTED: the player's purse holds exactly what left her `accrued` (her ledger rows are DIVIDEND only, and sum to her purse)
    if (s.v #>> '{fin,a}')::bigint <> (select coalesce(sum(e::bigint), 0) from jsonb_array_elements_text(s.v #> '{fin,ledger_a}') e)
       or (s.v #>> '{fin,ledger_a_other}')::int <> 0 or (s.v #>> '{fin,fleets}')::int <> 0 then
      raise exception '0495 self-assert FAIL: the player''s purse is not her DIVIDEND rows, or a probe has a fleet, in %: %', s.name, left(s.v::text, 900);
    end if;
  end loop;

  -- A WHOLE LIT DAY: 461,384 d. -> the day's coupon 8,305 marked, 346 an hour; 24 hours pay 24 x 346 = 8,304; the same hour again 0;
  -- 1 d. is left for the next day; the old 555 was never paid out hourly; then an arrival collects the 556 and later hours pay 0.
  v_x := v_all->'day';
  if v_x->'drip0' is distinct from '[["docks", 8305, 346], ["inn", 0, 0], ["market", 0, 0]]'::jsonb
     or (select count(*) from jsonb_array_elements_text(v_x->'hours') e where e::bigint = 346) <> 24
     or (select count(*) from jsonb_array_elements_text(v_x->'twice') e where e::bigint = 0) <> 24
     or (v_x #>> '{collected}')::bigint <> 556 or v_x->'after' <> '[0, 0]'::jsonb
     or (v_x #>> '{fin,a}')::bigint <> 555 + 8305
     or v_x #> '{fin,shares}' is distinct from '[["docks", 0, 0, 346], ["inn", 3600, 0, 0], ["market", 18000, 0, 0]]'::jsonb then
    raise exception '0495 self-assert FAIL: a lit day did not pay the player 346 d. an hour, once an hour, and leave the rest to an arrival: %', left(v_x::text, 1200);
  end if;
  -- THE PROFIT LIMIT: the player's part of the limited coupon (3,332 of 12,000) is what is paid out: 139 an hour
  v_x := v_all->'thin';
  if v_x->'drip0' is distinct from '[["docks", 3332, 139], ["inn", 0, 0], ["market", 0, 0]]'::jsonb or v_x->'hours' <> '[139]'::jsonb then
    raise exception '0495 self-assert FAIL: under the profit limit the pay-out is not the player''s part of it: %', left(v_x::text, 900);
  end if;
  -- MISSED HOURS ARE NOT LOST: 3 hours paid (1,038), 7,267 left; the next day's coupon folds it in: 7,267 + 8,305 = 15,572, 649 an hour
  v_x := v_all->'missed';
  if v_x->'hours' <> '[346, 346, 346]'::jsonb or (v_x #>> '{r2,paid}')::bigint <> 29905
     or v_x #> '{fin,shares}' is distinct from '[["docks", 16127, 15572, 649], ["inn", 7200, 0, 0], ["market", 36000, 0, 0]]'::jsonb
     or (v_x #>> '{fin,a}')::bigint <> 1038 then
    raise exception '0495 self-assert FAIL: missed hours were lost, or not folded into the next day''s pay-out: %', left(v_x::text, 900);
  end if;
  -- AN ARRIVAL IN THE MIDDLE collects everything once (as today); the hours after it pay nothing; she holds 555 + 8,305, not a coin more
  v_x := v_all->'arrive';
  if v_x->'hours' <> '[346, 346, 346]'::jsonb or (v_x #>> '{collected}')::bigint <> 555 + 8305 - 1038 or v_x->'after' <> '[0, 0]'::jsonb
     or (v_x #>> '{fin,a}')::bigint <> 555 + 8305
     or v_x #> '{fin,shares,0}' is distinct from '["docks", 0, 0, 346]'::jsonb then
    raise exception '0495 self-assert FAIL: an arrival and the hourly pay-out paid the same coin twice, or not all of it: %', left(v_x::text, 900);
  end if;
  v_x := v_all->'loss';
  if (v_x #>> '{daily,r,paid}')::bigint <> 0 or v_x->'hours' <> '[0, 0]'::jsonb or (v_x #>> '{fin,a}')::bigint <> 0
     or v_x #> '{fin,shares,0}' is distinct from '["docks", 555, 0, 0]'::jsonb then
    raise exception '0495 self-assert FAIL: a city that lost paid, or old `accrued` was paid out hourly: %', left(v_x::text, 900);
  end if;

  -- ── 10. NOTHING OF THE PROBE SURVIVES; the switch is dark ──
  if exists (select 1 from public.players p where p.company_name like 'Probe 0495 %')
     or exists (select 1 from public.port_treasury t join public.ports q on q.id = t.port_id where q.kind = 'SEA_PLACE')
     or exists (select 1 from public.city_shares cs where cs.drip_left <> 0 or cs.drip_hour <> 0 or cs.drip_at <> 0)
     or public.dividend_hourly_on()
     or (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
           from public.world_config c where c.key <> 'dividend_hourly_enabled') <> v_cfg_before then
    raise exception '0495 self-assert FAIL: the probe left rows behind, or a knob moved';
  end if;
  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0495 self-assert FAIL: the file took % (budget 30 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0495 self-assert ok: DIVIDENDS ARE PAID EVERY HOUR (dark). 2 hunks once and reversing (tick_city, city_coupons); no other function moved; the hunked bodies'' grants and settings unmoved; three new functions server only; one knob, dividend_hourly_enabled false; city_shares.drip_left, drip_hour, drip_at. DARK IDENTICAL: the daily scene paid % d. into `accrued` before and after, every row and flow equal, nothing marked. LIT, a probe player and a probe merchant: the day''s coupon is the dark day''s to the coin (never above today''s rule; also with the profit limit binding: 12,000 of 29,905); the merchant is paid nothing hourly and holds no mark; the player''s 461,384 d. is paid 346 d. an hour to a purse with no fleet, 24 hours, each hour once; under the limit 139 an hour; 21 missed hours folded into the next day (7,267 + 8,305 -> 649 an hour); an arrival collected the rest once and later hours paid 0; old accrued 555 never paid out hourly; a city that lost paid 0; no hour wrote a city''s purse or a flow. % ms.',
    v_d0 #>> '{daily,r,paid}', round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0495;
  drop table pre_0495;
end $m$;
