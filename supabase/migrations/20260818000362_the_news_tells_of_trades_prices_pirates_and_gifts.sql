-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0362 — THE NEWS TELLS OF BIG TRADES, PRICE SPIKES, PIRATES AND GIFTS  (slices N4, N5 and the gift of N6 of docs/NEWS_AND_MARKERS.md; owner row 216). LIT
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- Owner, 2026-10-26 (row 216): "when an update or a happening is made, it should make a point on the chart, and i will be able to press it to see what caused it (major event, real time
-- news-like feature)". 0347 built the news table, its two reads and three kinds (Update, New harbour, Relations). This file adds the happenings of play: five kinds, each written by ONE
-- writer inside the transaction that causes it. The client already draws any kind the server serves (templates are rows of public.news_kinds; no kind is named in the client).
--
-- THE FIVE KINDS (rows of public.news_kinds, importance 2 = notable: the World feed shows them, the desk strip does not)
--   BIG_SALE     port   "{company} sold {qty} {good} at {city}: {n}"     cmd.do_sell, a sale whose total is at least news_big_trade (250,000)
--   BIG_BUY      port   "{company} bought {qty} {good} at {city}: {n}"   cmd.do_buy, the same knob
--   PRICE_SPIKE  port   "{good} at {city} {p} in an hour"                public.tick_price_snapshot's hour fold: the hour just closed against the hour before it (the bid's close), a move
--                                                                        of at least news_spike_pct (20 %); the news_spike_top (5) largest an hour; a pair is quiet for news_spike_quiet_hours (6)
--   PIRATES      company "Pirates took {n} from {company}"               voyage.settle, a RANSOM, PLUNDERED or STRIPPED day that cost something: the cargo taken at what it cost, the ransom
--                                                                        paid and a cargo ship's gold. A player's company always; a ship of the world at news_pirate_loss (50,000) and up
--   CAPITAL_GIFT company "{capital} gave {company} {n}"                  public.capital_gift_one (the one body of the gift pass: the merchants' hourly pass and a player's gift after a sale)
-- THE CAPS (so the merchants cannot flood the feed; every one is a knob, and 0 turns its kind off):
--   * the threshold first: a sale or a buy under news_big_trade costs ONE knob read and one comparison, and writes nothing;
--   * one row a company, a city, a good and a clock hour for a trade (the key): a lot sold in ten parts is one headline;
--   * A SHIP OF THE WORLD (players.is_npc) IS TOLD ONLY WHILE FEWER THAN news_merchant_hour (2) ROWS OF THAT KIND WERE TOLD IN THE LAST HOUR, whoever caused them
--     (public.news_room: one index range scan of the last hour of one scope, which these caps keep to a handful of rows). So the merchants add at most 2 rows an hour to each
--     of BIG_SALE, BIG_BUY, PIRATES and CAPITAL_GIFT: 8 an hour, 192 a day, at the very most, however they trade. A player's company is always told;
--   * spikes: at most 5 an hour, 120 a day.
--   WHY THE CAP AND NOT THE KNOB ALONE: the design's 250,000 was the 99.9th per cent of a sale on 2026-10-26. In the local world today 51 of 384 merchant trades reach it
--   (scripts/ops/harness/news-kinds/volume-scene.sql), so on such a world the cap is what bounds the feed, and the knob wants a read of prod's trades before it is trusted
--   (scripts/ops/harness/news-kinds/trade-sizes.sql, a prod check). The knob is the owner's.
-- THE HUNKS (sliced from the LIVE bodies, each asserted to occur once and to reverse to its pre-image; ACL, volatility, definer and settings unmoved):
--   cmd.do_sell (1)                 after the live trade figures: the threshold, then public.news_big_trade
--   cmd.do_buy (1)                  the same
--   public.tick_price_snapshot (1)  after the hour fold's mark: public.news_price_spikes, only in the run that folded an hour (once an hour)
--   voyage.settle (3)               one variable; her cargo at cost read before the raiders take their share (a PLUNDERED or STRIPPED day only); the news of the day before its payload
--   public.capital_gift_one (1)     after the gift's own sub-block: public.news_gift when a gift was made (outside the sub-block, so the news can never turn a gift into a failed one)
--   NO ANSWER, NO ROW AND NO PAYLOAD OF ANY OF THE FIVE MOVES: each hunk only adds a call that writes public.world_news. Proof 64 holds it: the old bodies (rebuilt from the live ones
--   by these hunks) against the new, on real sales, buys, snapshots and raid days, equal as text.
--   public.client_rpc_entry_points is NOT cut: no door is added.
-- NOT IN THIS FILE (docs/NEWS_AND_MARKERS.md N6's other kinds): MERCHANT_BROKE, WANTS and RESTOCK. The feed's "My goods" filter is not here either (a read and a client face).
-- DECIDED BY DEFAULT: the price read is the BID's close (every recorded pair has one; an ask only where the city sells the good). A STRIPPED day is PIRATES news too (the design names
--   PLUNDERED and RANSOM; stripped is the worse of the same thing). A ransom day that moved no gold (an anonymous raid with the old table) is not news: nothing was taken.
--   The news instant is when the world learns it (the row's own clock), also for a voyage settled late. Figures in a headline are written with thousands commas by the server
--   (public.news_num), so the client needs no rule for them. The pirates' and the merchants' caps are knobs the design does not name: news_pirate_loss, news_merchant_hour,
--   news_spike_top, news_spike_quiet_hours.
-- LIT, NO SWITCH: the design names knobs, not a switch, for these kinds; they write only public.world_news, which no rule of play reads. No switch of the game is read differently or
--   written: attack_enabled, pirates_bite, combat_bite, economy_closed and every other key are as they were (the self-assert holds every other world_config row).
-- COST (measured locally, docs/dev-log/2026-11-13-news-kinds.md): a sale or buy under the knob: one public.wc_num read. A snapshot that folds no hour: nothing. A sea day that is
--   not a costly raid: nothing.
-- SELF-ASSERT: the hunks (once each, reversing); a probe in a sub-block rolled back whole, on the helpers only (no real sale, no real voyage: nothing of live play is locked):
--   two probe companies, hour rows planted in 2099 (no hour-of-day dependence, and no fold or prune of the live job reads that year); it counts only its own rows (ids above a
--   mark taken in-block) and never deletes from world_news. Then the catalog and this file's UPDATE row. THE REAL COMMANDS are proof 64 (scripts/db/proofs/64_news_kinds.sql).
-- BUDGET: statement_timeout 45 s, lock_timeout 5 s; the file fails above 30 s. LOCKS: five function bodies replaced (brief); no table is altered; no row of play is written.
-- ROLLBACK (forward, owner only). The light one: set news_big_trade, news_spike_pct, news_merchant_hour to 0 (trades and spikes stop, the world's ships are no longer told).
--   The whole slice: scripts/ops/harness/news-kinds/rollback-0362.sql, a draft that swaps every hunk back and drops what this file made (rows already told stay: append-only).
-- news: this file posts its own UPDATE row (public.news_update('0362', ...)).
-- VERSION: 0362. 0355-0361 are held by open branches; none of them cuts any of these five bodies (checked against each branch's migration, dev-log).
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

set local statement_timeout = '45s';
set local lock_timeout = '5s';

-- ── 0. GUARD and the PRE-IMAGES, kept in a temp table for the self-assert at the end ──
create temp table pre_0362 (k text primary key, v text) on commit drop;

do $g$
declare
  c_cut constant text[] := array['cmd.do_sell(uuid,jsonb)', 'cmd.do_buy(uuid,jsonb)', 'public.tick_price_snapshot(timestamp with time zone)',
                                 'voyage.settle(uuid,timestamp with time zone)', 'public.capital_gift_one(timestamp with time zone,uuid)'];
begin
  if to_regprocedure('public.news_big_trade(text,uuid,uuid,uuid,numeric,numeric)') is not null or to_regprocedure('public.news_room(text)') is not null
     or exists (select 1 from public.news_kinds k where k.kind in ('BIG_SALE', 'BIG_BUY', 'PRICE_SPIKE', 'PIRATES', 'CAPITAL_GIFT'))
     or exists (select 1 from public.world_config c where c.key like 'news\_%') then
    raise exception '0362 refuses: something of it is already in this world';
  end if;
  if to_regprocedure('public.news_post(text,uuid,uuid,uuid,text,text,jsonb)') is null or to_regprocedure('public.news_update(text,text,text)') is null
     or to_regprocedure('public.news_place(uuid)') is null or to_regclass('public.world_news') is null or to_regclass('public.price_history_hour') is null
     or to_regprocedure('public.price_record_pairs()') is null or to_regprocedure('public.fleet_stock_at_cost(uuid)') is null
     or to_regprocedure('public.wc_num(text)') is null or to_regprocedure('public.wc_int(text)') is null
     or exists (select 1 from unnest(c_cut) f where to_regprocedure(f) is null) then
    raise exception '0362 refuses: 0347 (the news) or a body it cuts is not in this world';
  end if;
  insert into pre_0362 values
    ('fn', (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
              from pg_proc p join pg_namespace n on n.oid = p.pronamespace
             where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
               and p.oid <> all (array(select f::regprocedure::oid from unnest(c_cut) f)))),
    ('meta', (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, ''), ',' order by p.oid::regprocedure::text))
                from pg_proc p join pg_namespace n on n.oid = p.pronamespace
               where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p'))),
    ('cfg', (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) from public.world_config c)),
    ('rel', (select md5(string_agg(n.nspname || '.' || c.relname || ':' || c.relkind::text, ',' order by n.nspname, c.relname))
               from pg_class c join pg_namespace n on n.oid = c.relnamespace
              where n.nspname in ('public', 'cmd', 'world', 'voyage') and c.relkind in ('r', 'v', 'm', 'S', 'i', 'f', 'p'))),
    ('trig', (select md5(string_agg(t.tgrelid::regclass::text || ':' || t.tgname || ':' || t.tgenabled::text, ',' order by t.tgrelid::regclass::text, t.tgname))
                from pg_trigger t where not t.tgisinternal)),
    ('kinds', (select md5(string_agg(k.kind || ':' || k.importance || ':' || k.scope || ':' || k.en || ':' || k.ko, ',' order by k.kind)) from public.news_kinds k)),
    ('entry', (select md5(string_agg(e::text, ',' order by e::text)) from public.client_rpc_entry_points() e));
end $g$;

-- ── 1. THE KINDS (rows, not code) and THE KNOBS ──
insert into public.news_kinds (kind, importance, scope, en, ko) values
  ('BIG_SALE',     2, 'port',    '{company} sold {qty} {good} at {city}: {n}',   '{company}, {city}에 {good} {qty} 판매: {n}'),
  ('BIG_BUY',      2, 'port',    '{company} bought {qty} {good} at {city}: {n}', '{company}, {city}에서 {good} {qty} 구매: {n}'),
  ('PRICE_SPIKE',  2, 'port',    '{good} at {city} {p} in an hour',              '{city} {good} 1시간 {p}'),
  ('PIRATES',      2, 'company', 'Pirates took {n} from {company}',              '해적이 {company}에서 {n} 약탈'),
  ('CAPITAL_GIFT', 2, 'company', '{capital} gave {company} {n}',                 '{capital}, {company}에 {n} 지원');

insert into public.world_config (key, value, description) values
  ('news_big_trade', to_jsonb(250000),
   '0362 (docs/NEWS_AND_MARKERS.md 2.2): a sale or a buy whose total is at least this many ducats is news (BIG_SALE, BIG_BUY). Read by cmd.do_sell and cmd.do_buy. 0: no trade is news.'),
  ('news_spike_pct', to_jsonb(20),
   '0362: a price that closed an hour at least this many per cent above or below the hour before is news (PRICE_SPIKE). Read by public.news_price_spikes. 0: no spike is news.'),
  ('news_spike_top', to_jsonb(5),
   '0362: at most this many price spikes are told an hour, the largest first.'),
  ('news_spike_quiet_hours', to_jsonb(6),
   '0362: after a spike is told, the same good at the same city is not told again for this many hours.'),
  ('news_pirate_loss', to_jsonb(50000),
   '0362: a raid on a ship of the world (a merchant, a cargo ship) is news (PIRATES) only when it cost her at least this many ducats. A player''s company is always told.'),
  ('news_merchant_hour', to_jsonb(2),
   '0362: THE CAP ON THE WORLD''S SHIPS IN THE NEWS: a merchant''s trade, raid or gift is told only while fewer than this many rows of that kind were told in the last hour (public.news_room). 0: the world''s ships are never told. A player''s company is always told.');

-- ── 2. THE WRITERS' LEAVES (server only; each posts through public.news_post, 0347's one writer) ──
create function public.news_num(p_n numeric)
returns text
language sql
immutable
set search_path = public, pg_temp
as $f$
  -- 0362: a figure as a headline writes it: whole, with thousands commas ("1,250,000"). One spelling, both languages.
  select to_char(round(coalesce(p_n, 0)), 'FM999,999,999,999,999,990')
$f$;

create function public.news_good(p_good uuid)
returns jsonb
language sql
stable security definer
set search_path = public, pg_temp
as $f$
  -- 0362: a good as a news word: the client localises it by its code (properName 'good'). public.news_place's twin.
  select jsonb_build_object('kind', 'good', 'key', g.code, 'name', g.name) from public.goods g where g.id = p_good
$f$;

create function public.news_room(p_kind text)
returns boolean
language sql
volatile security definer
set search_path = public, pg_temp
as $f$
  -- 0362: IS THERE ROOM IN THE NEWS FOR A SHIP OF THE WORLD? True while fewer than news_merchant_hour rows of this kind were told in the last hour (whoever caused them).
  -- One range scan of (scope, at desc) over the last hour of the kind's scope, which this very cap keeps short. Asked for a merchant only: a player's company is always told.
  select (select count(*) from public.world_news w
           where w.scope = k.scope and w.at > clock_timestamp() - interval '1 hour' and w.kind = k.kind) < public.wc_int('news_merchant_hour')
    from public.news_kinds k
   where k.kind = p_kind
$f$;

create function public.news_big_trade(p_kind text, p_company uuid, p_port uuid, p_good uuid, p_qty numeric, p_total numeric)
returns bigint
language plpgsql
volatile security definer
set search_path = public, pg_temp
as $f$
-- 0362 (N4): A BIG TRADE IS NEWS. Called by cmd.do_sell (BIG_SALE) and cmd.do_buy (BIG_BUY) only when the total has reached news_big_trade: the threshold is theirs, one comparison.
-- A ship of the world is told only while the hour has room (public.news_room). The key makes a company's trades of one good at one city in one clock hour ONE row.
-- Answers the news id, or null when nothing was told.
declare
  v_npc  boolean;
  v_name text;
begin
  select pl.is_npc, pl.company_name into v_npc, v_name from public.players pl where pl.id = p_company;
  if v_name is null or coalesce(p_total, 0) <= 0 or (v_npc and not coalesce(public.news_room(p_kind), false)) then
    return null;
  end if;
  return public.news_post(p_kind, p_port, p_good, p_company, null,
           lower(p_kind) || ':' || p_company::text || ':' || p_port::text || ':' || p_good::text || ':' || to_char(clock_timestamp() at time zone 'UTC', 'YYYYMMDDHH24'),
           jsonb_build_object('words', jsonb_build_object('company', v_name, 'qty', public.news_num(p_qty), 'good', public.news_good(p_good),
                                                          'city', public.news_place(p_port), 'n', public.news_num(p_total)),
                              'qty', p_qty, 'total', round(p_total), 'npc', v_npc));
end $f$;

create function public.news_price_spikes(p_hour timestamptz, p_now timestamptz)
returns int
language plpgsql
volatile security definer
set search_path = public, pg_temp
as $f$
-- 0362 (N4): THE PRICE SPIKES OF THE HOUR THAT JUST CLOSED. p_hour is the hour now beginning (public.tick_price_snapshot's v_hour_now, in the run that folded): the hour before it
-- against the hour before that, the bid's close, for every recorded pair (public.price_record_pairs: two primary-key probes a pair, never a scan of the hour table).
-- A move of at least news_spike_pct per cent is a spike; the news_spike_top largest of the hour are taken FIRST, and of those a pair told in the last
-- news_spike_quiet_hours (by p_now) is passed over: a second run of the same hour takes the same few and tells nothing, and a pair that keeps moving is told once.
-- The key ('spike:<port>:<good>:<hour>') holds it too. Answers the rows told.
declare
  v_pct   numeric := public.wc_num('news_spike_pct');
  v_top   int     := public.wc_int('news_spike_top');
  v_quiet interval := make_interval(hours => public.wc_int('news_spike_quiet_hours'));
  v_n     int := 0;
  r       record;
begin
  if coalesce(v_pct, 0) <= 0 or coalesce(v_top, 0) <= 0 or p_hour is null then
    return 0;
  end if;
  for r in
    select t.*
      from (select c.port_id, c.good_id, b.bid_c as was, c.bid_c as now, (c.bid_c - b.bid_c) / b.bid_c as d
              from public.price_record_pairs() pr
              join public.price_history_hour c on c.port_id = pr.port_id and c.good_id = pr.good_id and c.hour = p_hour - interval '1 hour'
              join public.price_history_hour b on b.port_id = pr.port_id and b.good_id = pr.good_id and b.hour = p_hour - interval '2 hours'
             where b.bid_c > 0 and c.bid_c is not null
               and abs(c.bid_c - b.bid_c) * 100 >= v_pct * b.bid_c
             order by abs(c.bid_c - b.bid_c) / b.bid_c desc, c.port_id, c.good_id
             limit v_top) t
     where not exists (select 1 from public.world_news w
                        where w.port_id = t.port_id and w.at > p_now - v_quiet and w.good_id = t.good_id and w.kind = 'PRICE_SPIKE')
     order by abs(t.d) desc, t.port_id, t.good_id
  loop
    if public.news_post('PRICE_SPIKE', r.port_id, r.good_id, null, null,
         'spike:' || r.port_id::text || ':' || r.good_id::text || ':' || to_char((p_hour - interval '1 hour') at time zone 'UTC', 'YYYYMMDDHH24'),
         jsonb_build_object('words', jsonb_build_object('good', public.news_good(r.good_id), 'city', public.news_place(r.port_id),
                                                        'p', case when r.d > 0 then '+' else '-' end || round(abs(r.d) * 100)::text || '%'),
                            'before', trim_scale(round(r.was, 2)), 'after', trim_scale(round(r.now, 2)), 'pct', round(r.d * 100, 1))) is not null then
      v_n := v_n + 1;
    end if;
  end loop;
  return v_n;
end $f$;

create function public.news_pirates(p_voyage uuid, p_day int, p_company uuid, p_outcome text, p_loss numeric)
returns bigint
language plpgsql
volatile security definer
set search_path = public, pg_temp
as $f$
-- 0362 (N5): PIRATES ARE NEWS. Called by voyage.settle's PIRATES arm on a RANSOM, PLUNDERED or STRIPPED day; p_loss is what the day cost her in ducats (the cargo taken at
-- what it cost, the ransom paid, a cargo ship's gold). Nothing lost: no news. A player's company is always told; a ship of the world only at news_pirate_loss and up, and
-- only while the hour has room (public.news_room). The key is the voyage's day. Answers the news id, or null.
declare
  v_npc  boolean;
  v_name text;
begin
  if coalesce(p_loss, 0) <= 0 then
    return null;
  end if;
  select pl.is_npc, pl.company_name into v_npc, v_name from public.players pl where pl.id = p_company;
  if v_name is null or (v_npc and (p_loss < public.wc_num('news_pirate_loss') or not coalesce(public.news_room('PIRATES'), false))) then
    return null;
  end if;
  return public.news_post('PIRATES', null, null, p_company, null, 'pirates:' || p_voyage::text || ':' || p_day::text,
           jsonb_build_object('words', jsonb_build_object('company', v_name, 'n', public.news_num(p_loss)),
                              'loss', round(p_loss), 'outcome', p_outcome, 'npc', v_npc));
end $f$;

create function public.news_gift(p_capital uuid, p_company uuid, p_ducats bigint, p_now timestamptz)
returns bigint
language plpgsql
volatile security definer
set search_path = public, pg_temp
as $f$
-- 0362 (N6): A CAPITAL'S GIFT IS NEWS. Called by public.capital_gift_one after a gift was made (the merchants' hourly pass and a player's gift after her sale are that one body).
-- A player's company is always told; a merchant only while the hour has room (public.news_room). The key is the company and the pass's minute. Answers the news id, or null.
declare
  v_npc  boolean;
  v_name text;
begin
  select pl.is_npc, pl.company_name into v_npc, v_name from public.players pl where pl.id = p_company;
  if v_name is null or coalesce(p_ducats, 0) <= 0 or p_capital is null or (v_npc and not coalesce(public.news_room('CAPITAL_GIFT'), false)) then
    return null;
  end if;
  return public.news_post('CAPITAL_GIFT', p_capital, null, p_company, null,
           'gift:' || p_company::text || ':' || to_char(p_now at time zone 'UTC', 'YYYYMMDDHH24MI'),
           jsonb_build_object('words', jsonb_build_object('capital', public.news_place(p_capital), 'company', v_name, 'n', public.news_num(p_ducats)),
                              'ducats', p_ducats, 'npc', v_npc));
end $f$;

revoke all on function public.news_num(numeric) from public, anon, authenticated;
revoke all on function public.news_good(uuid) from public, anon, authenticated;
revoke all on function public.news_room(text) from public, anon, authenticated;
revoke all on function public.news_big_trade(text, uuid, uuid, uuid, numeric, numeric) from public, anon, authenticated;
revoke all on function public.news_price_spikes(timestamptz, timestamptz) from public, anon, authenticated;
revoke all on function public.news_pirates(uuid, int, uuid, text, numeric) from public, anon, authenticated;
revoke all on function public.news_gift(uuid, uuid, bigint, timestamptz) from public, anon, authenticated;

-- ── 3. THE HUNKS, the PROBE and the SELF-ASSERT ──
do $m$
declare
  v_t0     timestamptz := clock_timestamp();
  v_h      record;
  v_def    text;
  v_pre    text;
  v_n      int;
  v_lo     bigint;
  v_hi     bigint := 0;
  v_mark   bigint;
  v_id     bigint;
  v_port   uuid;
  v_good   uuid;
  v_good2  uuid;
  v_cap    uuid;
  v_pl     uuid;
  v_npc    uuid;
  v_w      public.world_news%rowtype;
  v_pairs  record;
  v_ids    int[];
  v_res    jsonb;
  v_lived  boolean := false;
  v_hour   timestamptz := '2099-03-04 05:00:00+00';   -- the hour "now beginning" of the spike probe: no fold and no prune of the live job reads 2099
  c_moves  constant numeric[] := array[0.25, 0.30, 0.35, 0.40, 0.45, 0.50, -0.60, 0.10];
  c_uid    constant uuid := '00000000-0362-4000-8000-000000000001';
  c_voy    constant uuid := '00000000-0362-4000-8000-0000000000aa';
  c_cut_fns constant text[] := array['cmd.do_sell(uuid,jsonb)', 'cmd.do_buy(uuid,jsonb)', 'public.tick_price_snapshot(timestamp with time zone)',
                                     'voyage.settle(uuid,timestamp with time zone)', 'public.capital_gift_one(timestamp with time zone,uuid)'];
  c_new_fns constant text[] := array['public.news_num(numeric)', 'public.news_good(uuid)', 'public.news_room(text)',
                                     'public.news_big_trade(text,uuid,uuid,uuid,numeric,numeric)', 'public.news_price_spikes(timestamp with time zone,timestamp with time zone)',
                                     'public.news_pirates(uuid,integer,uuid,text,numeric)', 'public.news_gift(uuid,uuid,bigint,timestamp with time zone)'];
  c_knobs  constant text[] := array['news_big_trade', 'news_spike_pct', 'news_spike_top', 'news_spike_quiet_hours', 'news_pirate_loss', 'news_merchant_hour'];
  c_kinds  constant text[] := array['BIG_SALE', 'BIG_BUY', 'PRICE_SPIKE', 'PIRATES', 'CAPITAL_GIFT'];
begin
  -- THE HUNKS (each OLD text occurs exactly once in its live body, and reverses)
  create temp table hunks_0362 (fn text, n int, old text, new text) on commit drop;
  insert into hunks_0362 (fn, n, old, new) values
  ('cmd.do_sell(uuid,jsonb)', 1,
$o$  perform public.stats_live_add(jsonb_build_object('trades', 1, 'units', q.units, 'sold', round(q.total)::bigint));
$o$,
$n$  perform public.stats_live_add(jsonb_build_object('trades', 1, 'units', q.units, 'sold', round(q.total)::bigint));
  -- 0362 (N4, docs/NEWS_AND_MARKERS.md 2.2): a big sale is news. The threshold first (one knob read, one comparison; 0 is off); public.news_big_trade only above it.
  if q.total >= nullif(public.wc_num('news_big_trade'), 0) then
    perform public.news_big_trade('BIG_SALE', f.player_id, f.port_id, g.id, q.units, q.total);
  end if;
$n$),
  ('cmd.do_buy(uuid,jsonb)', 1,
$o$  perform public.stats_live_add(jsonb_build_object('trades', 1, 'units', q.units, 'bought', round(q.total)::bigint));
$o$,
$n$  perform public.stats_live_add(jsonb_build_object('trades', 1, 'units', q.units, 'bought', round(q.total)::bigint));
  -- 0362 (N4, docs/NEWS_AND_MARKERS.md 2.2): a big buy is news. The threshold first (one knob read, one comparison; 0 is off); public.news_big_trade only above it.
  if q.total >= nullif(public.wc_num('news_big_trade'), 0) then
    perform public.news_big_trade('BIG_BUY', f.player_id, f.port_id, g.id, q.units, q.total);
  end if;
$n$),
  ('public.tick_price_snapshot(timestamp with time zone)', 1,
$o$    get diagnostics v_hours = row_count;
    update public.price_rollup set hour_done = v_hour_now where one;
$o$,
$n$    get diagnostics v_hours = row_count;
    update public.price_rollup set hour_done = v_hour_now where one;
    -- 0362 (N4): the hour that just closed against the hour before it: the largest moves are news (public.news_price_spikes). Only in the run that folded an hour.
    if v_hours > 0 then
      perform public.news_price_spikes(v_hour_now, p_now);
    end if;
$n$),
  ('voyage.settle(uuid,timestamp with time zone)', 1,
$o$  v_booked  bigint;    -- 0339: the gold she took from a cargo ship (public.pirate_loot_book)
$o$,
$n$  v_booked  bigint;    -- 0339: the gold she took from a cargo ship (public.pirate_loot_book)
  v_cost0   bigint;    -- 0362: her cargo at what it cost, read before the raiders take their share (the news of the day says what they took)
$n$),
  ('voyage.settle(uuid,timestamp with time zone)', 2,
$o$        v_taken := voyage.raid_takes(v.id, d, p_fleet, v_outcome);
$o$,
$n$        v_cost0 := public.fleet_stock_at_cost(p_fleet);   -- 0362: before they take it (public.fleet_unload drops a good's cost with its last tun)
        v_taken := voyage.raid_takes(v.id, d, p_fleet, v_outcome);
$n$),
  ('voyage.settle(uuid,timestamp with time zone)', 3,
$o$      v_payload := v_payload || jsonb_build_object('outcome', v_outcome, 'prose', v_prose,
$o$,
$n$      -- 0362 (N5, docs/NEWS_AND_MARKERS.md 2.2): pirates are news, when the day cost her something: the cargo taken at what it cost, the ransom paid, a cargo ship's gold
      -- (public.news_pirates: a player's company always, a ship of the world at news_pirate_loss and up). The day's payload below is what it was.
      if v_outcome in ('PLUNDERED', 'STRIPPED') or (v_outcome = 'RANSOM' and v_ransom > 0) then
        perform public.news_pirates(v.id, d, f.player_id, v_outcome,
                  v_ransom + v_booked + case when v_outcome = 'RANSOM' then 0 else v_cost0 - public.fleet_stock_at_cost(p_fleet) end);
      end if;
      v_payload := v_payload || jsonb_build_object('outcome', v_outcome, 'prose', v_prose,
$n$),
  ('public.capital_gift_one(timestamp with time zone,uuid)', 1,
$o$    end;
  return jsonb_build_object('gifted', v_n, 'gift_ducats', v_d, 'gift_waiting', v_wait, 'failed', v_fail, 'notes', v_notes);
$o$,
$n$    end;
  -- 0362 (N6, docs/NEWS_AND_MARKERS.md 2.2): a gift that was made is news (public.news_gift). After the gift's own sub-block, so the news never makes a gift a failed one.
  if v_n > 0 then
    perform public.news_gift(r.cap_id, r.player_id, r.capital, p_now);
  end if;
  return jsonb_build_object('gifted', v_n, 'gift_ducats', v_d, 'gift_waiting', v_wait, 'failed', v_fail, 'notes', v_notes);
$n$);

  for v_h in select h.fn from hunks_0362 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    declare
      x record;
    begin
      for x in select * from hunks_0362 h where h.fn = v_h.fn order by h.n loop
        v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
        if v_n <> 1 then
          raise exception '0362 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.n, x.fn, v_n;
        end if;
        v_def := replace(v_def, x.old, x.new);
      end loop;
      execute v_def;
      v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
      for x in select * from hunks_0362 h where h.fn = v_h.fn order by h.n desc loop
        v_n := (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new);
        if v_n <> 1 then
          raise exception '0362 self-assert FAIL: hunk % of % is not in the new body once', x.n, x.fn;
        end if;
        v_def := replace(v_def, x.new, x.old);
      end loop;
      if v_def <> v_pre then
        raise exception '0362 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
      end if;
    end;
  end loop;

  -- THE PROBE (a sub-block rolled back whole; it counts only its own rows, ids above a mark taken here; the helpers only, no real sale and no real voyage)
  v_lo := coalesce((select max(w.id) from public.world_news w), 0);
  begin
    select p.id into v_port from public.ports p where p.kind = 'HARBOUR' order by p.code limit 1;
    select p.id into v_cap from public.ports p where p.kind = 'HARBOUR' and p.id <> v_port order by p.code limit 1;
    select g.id into v_good from public.goods g order by g.code limit 1;
    select g.id into v_good2 from public.goods g where g.id <> v_good order by g.code limit 1;
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
    values (c_uid, 'Casa Nova 0362', (select n.id from public.nations n where n.code = 'PRT'), 0, false) returning id into v_pl;
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
    values (null, 'Casa Mercante 0362', (select n.id from public.nations n where n.code = 'PRT'), 0, true) returning id into v_npc;
    if v_port is null or v_cap is null or v_good is null or v_good2 is null or v_pl is null or v_npc is null then
      raise exception '0362 self-assert FAIL: the probe needs two harbours, two goods and two companies';
    end if;
    -- the cap is counted from a known floor: with no room at all, then with room for two
    update public.world_config set value = to_jsonb(0) where key = 'news_merchant_hour';

    -- (a) A BIG TRADE: a player's is one row with every word; the same company, city, good and hour again is no second row; a buy is its own kind
    v_mark := coalesce((select max(w.id) from public.world_news w), 0);
    v_id := public.news_big_trade('BIG_SALE', v_pl, v_port, v_good, 120, 300000.4);
    select * into v_w from public.world_news w where w.id = v_id;
    if v_id is null or (select count(*) from public.world_news w where w.id > v_mark) <> 1
       or v_w.kind is distinct from 'BIG_SALE' or v_w.importance is distinct from 2 or v_w.scope is distinct from 'port' or v_w.port_id is distinct from v_port or v_w.good_id is distinct from v_good or v_w.company_id is distinct from v_pl
       or v_w.detail->'words'->>'company' is distinct from 'Casa Nova 0362' or v_w.detail->'words'->>'qty' is distinct from '120' or v_w.detail->'words'->>'n' is distinct from '300,000'
       or v_w.detail->'words'->'good'->>'kind' is distinct from 'good' or v_w.detail->'words'->'city'->>'kind' is distinct from 'port' or (v_w.detail->>'npc')::boolean is distinct from false then
      raise exception '0362 self-assert FAIL: a player''s big sale is not one BIG_SALE row with its words: %', to_jsonb(v_w);
    end if;
    if public.news_big_trade('BIG_SALE', v_pl, v_port, v_good, 5, 999999) is not null
       or public.news_big_trade('BIG_BUY', v_pl, v_port, v_good, 5, 250000) is null
       or public.news_big_trade('BIG_SALE', v_pl, v_port, v_good, 5, 0) is not null
       or public.news_big_trade('BIG_SALE', gen_random_uuid(), v_port, v_good, 5, 999999) is not null then
      raise exception '0362 self-assert FAIL: the same company, city, good and hour was told twice, a buy was not told, or a trade of nothing or of nobody was told';
    end if;
    if (select count(*) from public.world_news w where w.id > v_mark) <> 2 then   -- its own statement: a count sees what the statements before it wrote
      raise exception '0362 self-assert FAIL: the same company, city, good and hour was told twice, a buy was not its own row, or a trade of nothing or of nobody was told';
    end if;
    -- THE CAP ON THE WORLD'S SHIPS: no room, nothing; room for two of a kind, and the player's row above is one of them
    if public.news_room('BIG_SALE') or public.news_big_trade('BIG_SALE', v_npc, v_port, v_good, 5, 999999) is not null then
      raise exception '0362 self-assert FAIL: with news_merchant_hour 0 a merchant''s trade was told';
    end if;
    update public.world_config set value = to_jsonb((select count(*) + 1 from public.world_news w where w.scope = 'port' and w.kind = 'BIG_SALE' and w.at > clock_timestamp() - interval '1 hour'))
     where key = 'news_merchant_hour';
    if public.news_big_trade('BIG_SALE', v_npc, v_port, v_good, 5, 999999) is null
       or public.news_big_trade('BIG_SALE', v_npc, v_port, v_good2, 5, 999999) is not null
       or public.news_big_trade('BIG_SALE', v_pl, v_port, v_good2, 5, 999999) is null then
      raise exception '0362 self-assert FAIL: with room for one more, a merchant was not told once and then refused, or a player was refused';
    end if;
    if (select count(*) from public.world_news w where w.id > v_mark and w.company_id = v_npc and (w.detail->>'npc')::boolean) <> 1
       or (select count(*) from public.world_news w where w.id > v_mark) <> 4 then
      raise exception '0362 self-assert FAIL: with room for one more, a merchant was not told once and then refused, or a player was refused';
    end if;

    -- (b) PIRATES: a player's loss always; a merchant's only at the knob; nothing lost is no news; a day is told once
    update public.world_config set value = to_jsonb(1000) where key = 'news_merchant_hour';
    v_mark := coalesce((select max(w.id) from public.world_news w), 0);
    if public.news_pirates(c_voy, 1, v_pl, 'PLUNDERED', 100) is null
       or public.news_pirates(c_voy, 1, v_pl, 'PLUNDERED', 100) is not null
       or public.news_pirates(c_voy, 2, v_pl, 'RANSOM', 0) is not null
       or public.news_pirates(c_voy, 3, v_npc, 'PLUNDERED', public.wc_num('news_pirate_loss') - 1) is not null
       or public.news_pirates(c_voy, 4, v_npc, 'STRIPPED', public.wc_num('news_pirate_loss')) is null then
      raise exception '0362 self-assert FAIL: pirates'' news is not a player always, a merchant at the knob, nothing for nothing lost, once a day';
    end if;
    if (select count(*) from public.world_news w where w.id > v_mark and w.kind = 'PIRATES' and w.scope = 'company' and w.port_id is null) <> 2
       or not exists (select 1 from public.world_news w where w.id > v_mark and w.company_id = v_pl and w.detail->'words'->>'n' = '100' and w.detail->>'outcome' = 'PLUNDERED') then
      raise exception '0362 self-assert FAIL: pirates'' news is not two company rows, the player''s with what was taken';
    end if;

    -- (c) A GIFT: one row at the capital, naming it and the company
    v_mark := coalesce((select max(w.id) from public.world_news w), 0);
    v_id := public.news_gift(v_cap, v_npc, 40000, '2099-03-04 05:06:00+00');
    select * into v_w from public.world_news w where w.id = v_id;
    if v_id is null or v_w.kind is distinct from 'CAPITAL_GIFT' or v_w.port_id is distinct from v_cap or v_w.company_id is distinct from v_npc or v_w.detail->'words'->>'n' is distinct from '40,000'
       or v_w.detail->'words'->'capital'->>'kind' is distinct from 'port'
       or public.news_gift(v_cap, v_npc, 40000, '2099-03-04 05:06:00+00') is not null or public.news_gift(v_cap, v_npc, 0, now()) is not null
       or public.news_gift(null, v_npc, 40000, now()) is not null then
      raise exception '0362 self-assert FAIL: a gift is not one CAPITAL_GIFT row at the capital: %', to_jsonb(v_w);
    end if;

    -- (d) PRICE SPIKES: eight recorded pairs, hour rows planted in 2099: the hour before at 100, the hour closed at +25 .. +50 %, -60 % and +10 %
    v_mark := coalesce((select max(w.id) from public.world_news w), 0);
    create temp table probe_pairs_0362 on commit drop as
    select row_number() over (order by pr.port_id, pr.good_id)::int as i, pr.port_id, pr.good_id
      from (select * from public.price_record_pairs() order by port_id, good_id limit 8) pr;
    if (select count(*) from probe_pairs_0362) <> 8 then
      raise exception '0362 self-assert FAIL: the probe needs eight recorded pairs';
    end if;
    insert into public.price_history_hour (port_id, good_id, hour, ask_o, ask_h, ask_l, ask_c, bid_o, bid_h, bid_l, bid_c, n)
    select x.port_id, x.good_id, v_hour - interval '2 hours', 100, 100, 100, 100, 100, 100, 100, 100, 1 from probe_pairs_0362 x
    union all
    select x.port_id, x.good_id, v_hour - interval '1 hour', b.c, b.c, b.c, b.c, b.c, b.c, b.c, b.c, 1
      from probe_pairs_0362 x cross join lateral (select 100 * (1 + c_moves[x.i::int]) as c) b
    union all
    select x.port_id, x.good_id, v_hour, b.c, b.c, b.c, b.c, b.c, b.c, b.c, b.c, 1
      from probe_pairs_0362 x cross join lateral (select 130 * (1 + c_moves[x.i::int]) as c) b;   -- the next hour: every pair up 30 % again
    v_n := public.news_price_spikes(v_hour, now());
    select array_agg(x.i order by x.i) into v_ids
      from public.world_news w join probe_pairs_0362 x on x.port_id = w.port_id and x.good_id = w.good_id where w.id > v_mark and w.kind = 'PRICE_SPIKE';
    if v_n <> 5 or v_ids is distinct from array[3, 4, 5, 6, 7]::int[] then
      raise exception '0362 self-assert FAIL: the spikes told are % (pairs %), not the five largest of seven over 20 %% (the +10 %% never)', v_n, v_ids;
    end if;
    select w.* into v_w from public.world_news w join probe_pairs_0362 x on x.port_id = w.port_id and x.good_id = w.good_id where w.id > v_mark and x.i = 7;
    if v_w.detail->'words'->>'p' is distinct from '-60%' or (v_w.detail->>'before')::numeric is distinct from 100 or (v_w.detail->>'after')::numeric is distinct from 40 or v_w.importance is distinct from 2 or v_w.scope is distinct from 'port'
       or v_w.detail->'words'->'good'->>'kind' is distinct from 'good' or v_w.detail->'words'->'city'->>'kind' is distinct from 'port' then
      raise exception '0362 self-assert FAIL: a fall of 60 %% is not told with its before and after: %', to_jsonb(v_w);
    end if;
    -- the same hour again: nothing; the next hour (all eight up 30 %, so the five taken are the first five): three of them are quiet, two are told; seven hours on, the quiet has passed
    if public.news_price_spikes(v_hour, now()) <> 0 then
      raise exception '0362 self-assert FAIL: a second run of the same hour told a spike again';
    end if;
    v_n := public.news_price_spikes(v_hour + interval '1 hour', now());
    select array_agg(x.i order by x.i) into v_ids
      from public.world_news w join probe_pairs_0362 x on x.port_id = w.port_id and x.good_id = w.good_id
     where w.id > v_mark and w.kind = 'PRICE_SPIKE' and w.key like '%:2099030405';
    if v_n <> 2 or v_ids is distinct from array[1, 2]::int[] then
      raise exception '0362 self-assert FAIL: in the next hour % were told (pairs %), not the two of the five largest that were not told in the last six hours', v_n, v_ids;
    end if;
    update public.world_config set value = to_jsonb(0) where key = 'news_spike_pct';
    if public.news_price_spikes(v_hour + interval '1 hour', now() + interval '7 hours') <> 0 then
      raise exception '0362 self-assert FAIL: with news_spike_pct 0 a spike was told';
    end if;
    update public.world_config set value = to_jsonb(20) where key = 'news_spike_pct';
    -- seven hours on nobody is quiet: the same five are taken, two of them hold this hour's key already, three are told
    if public.news_price_spikes(v_hour + interval '1 hour', now() + interval '7 hours') <> 3 then
      raise exception '0362 self-assert FAIL: seven hours on, the quiet had not passed, or the hour''s keys did not hold the two already told';
    end if;
    drop table probe_pairs_0362;

    -- every placeholder of every kind written above has its word, and the reads serve the rows
    v_hi := coalesce((select max(w.id) from public.world_news w), 0);
    if exists (select 1 from public.world_news w join public.news_kinds k on k.kind = w.kind
                cross join lateral (select m[1] as name from regexp_matches(k.en || ' ' || k.ko, '\{([a-z_]+)\}', 'g') m) ph
               where w.id > v_lo and not (w.detail->'words' ? ph.name))
       or (select count(distinct w.kind) from public.world_news w where w.id > v_lo) <> 5 then
      raise exception '0362 self-assert FAIL: a template names a word its writer did not put in detail, or not all five kinds were written';
    end if;
    v_res := world.news_marks('price', v_port, v_good, null, null);
    if not exists (select 1 from jsonb_array_elements(v_res->'items') i where i->>'kind' = 'BIG_SALE' and (i->>'id')::bigint > v_lo)
       or not exists (select 1 from jsonb_array_elements(world.news_marks('merchants', null, null, null, null)->'items') i where i->>'kind' = 'PIRATES' and (i->>'id')::bigint > v_lo)
       or not exists (select 1 from jsonb_array_elements(world.news_marks('city', v_cap, null, null, null)->'items') i where i->>'kind' = 'CAPITAL_GIFT' and (i->>'id')::bigint > v_lo) then
      raise exception '0362 self-assert FAIL: a price chart does not show its big sale, the merchants chart its pirates, or the capital''s chart its gift';
    end if;

    raise exception using errcode = 'ZX362', message = 'PROBE_ROLLBACK_0362';
  exception when sqlstate 'ZX362' then
    v_lived := true;
  end;
  if not v_lived or v_hi <= v_lo then
    raise exception '0362 self-assert FAIL: the probe did not run to its end';
  end if;

  -- THE PROBE IS GONE: its rows, its companies, its hours, its knob writes
  if exists (select 1 from public.world_news w where w.id > v_lo)
     or exists (select 1 from public.players p where p.company_name like 'Casa % 0362' or p.auth_uid = c_uid)
     or exists (select 1 from public.price_record_pairs() pr join public.price_history_hour h on h.port_id = pr.port_id and h.good_id = pr.good_id and h.hour >= '2099-01-01'::timestamptz)
     or (select jsonb_object_agg(c.key, c.value order by c.key) from public.world_config c where c.key = any (c_knobs))
          is distinct from '{"news_big_trade": 250000, "news_merchant_hour": 2, "news_pirate_loss": 50000, "news_spike_pct": 20, "news_spike_quiet_hours": 6, "news_spike_top": 5}'::jsonb then
    raise exception '0362 self-assert FAIL: the probe left a trace, or a knob is not as written';
  end if;

  -- THIS FILE'S OWN UPDATE ROW (0347's law), counted by its own key
  perform public.news_update('0362', 'More news', '더 많은 소식');
  if (select count(*) from public.world_news w where w.key = 'update:0362' and w.kind = 'UPDATE') <> 1 then
    raise exception '0362 self-assert FAIL: this file''s UPDATE row is not one row';
  end if;

  -- THE CATALOG
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select f::regprocedure::oid from unnest(c_cut_fns || c_new_fns) f))) <> (select v from pre_0362 where k = 'fn') then
    raise exception '0362 self-assert FAIL: a function other than the five it cuts moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select f::regprocedure::oid from unnest(c_new_fns) f))) <> (select v from pre_0362 where k = 'meta') then
    raise exception '0362 self-assert FAIL: an ACL, a volatility, a definer flag or a setting moved (the re-cut bodies included)';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) from public.world_config c where c.key <> all (c_knobs))
       <> (select v from pre_0362 where k = 'cfg')
     or (select count(*) from public.world_config c where c.key = any (c_knobs)) <> 6 then
    raise exception '0362 self-assert FAIL: a world_config row other than this file''s six knobs moved: no switch of the game is written here';
  end if;
  if (select md5(string_agg(n.nspname || '.' || c.relname || ':' || c.relkind::text, ',' order by n.nspname, c.relname))
        from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and c.relkind in ('r', 'v', 'm', 'S', 'i', 'f', 'p')) <> (select v from pre_0362 where k = 'rel')
     or (select md5(string_agg(t.tgrelid::regclass::text || ':' || t.tgname || ':' || t.tgenabled::text, ',' order by t.tgrelid::regclass::text, t.tgname))
           from pg_trigger t where not t.tgisinternal) <> (select v from pre_0362 where k = 'trig') then
    raise exception '0362 self-assert FAIL: a relation or a trigger appeared, went or moved: this file makes none';
  end if;
  if (select md5(string_agg(k.kind || ':' || k.importance || ':' || k.scope || ':' || k.en || ':' || k.ko, ',' order by k.kind)) from public.news_kinds k where k.kind <> all (c_kinds))
       <> (select v from pre_0362 where k = 'kinds')
     or (select count(*) from public.news_kinds k where k.kind = any (c_kinds) and k.importance = 2) <> 5 then
    raise exception '0362 self-assert FAIL: a kind other than this file''s five moved, or its five are not all there at importance 2';
  end if;
  if (select string_agg(p.provolatile::text || case when p.prosecdef then 'd' else '-' end, '' order by f.o)
        from unnest(c_new_fns) with ordinality f(fn, o) join pg_proc p on p.oid = f.fn::regprocedure) is distinct from 'i-sdvdvdvdvdvd' then
    raise exception '0362 self-assert FAIL: the new functions'' volatility / definer flags are not as written';
  end if;
  if exists (select 1 from unnest(c_new_fns) f where has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute'))
     or (select md5(string_agg(e::text, ',' order by e::text)) from public.client_rpc_entry_points() e) <> (select v from pre_0362 where k = 'entry')
     or (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0362 self-assert FAIL: a client can reach a writer, the registry moved (no door is added), or a wall moved (the posture must read zero)';
  end if;

  if extract(epoch from clock_timestamp() - v_t0) > 30 then
    raise exception '0362 self-assert FAIL: the file took % (budget 30 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0362 self-assert ok: THE NEWS TELLS OF BIG TRADES, PRICE SPIKES, PIRATES AND GIFTS (N4, N5, the gift of N6). Five kinds (BIG_SALE, BIG_BUY, PRICE_SPIKE, PIRATES, CAPITAL_GIFT), six knobs, seven leaves no client calls; % hunks over % bodies (cmd.do_sell, cmd.do_buy, public.tick_price_snapshot, voyage.settle, public.capital_gift_one), each once and reversing. Probe rolled back: a player''s big trade and its key, the cap on the world''s ships, pirates at the knob, a gift at the capital, the five largest spikes of seven, the quiet hours, the knob at 0, every word of every template, three charts'' reads. No other function, knob, relation, trigger, kind or door moved. This file''s UPDATE row posted once. % ms.',
    (select count(*) from hunks_0362), (select count(distinct h.fn) from hunks_0362 h), round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0362;
end $m$;
