-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0352 - EVERY SUCCESS EARNS REPUTATION  (slice R1 of docs/REPUTATION.md; owner row 317; docs/SUCCESS_PLAN.md section B)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
-- WHY: the owner, row 317: a new currency, Reputation, from every success, spent on captain skills. This file is the
-- earning half: the book, the one writer, the earn hooks and the read. Nothing is spent yet (R2).
--
-- WHAT THIS FILE MAKES
--   THE BOOK      public.reputation_kinds (what may be booked: its sign, whether it counts against the day's cap),
--                 public.reputation_balance (one row a company: balance, the newest book row, today's capped earnings,
--                 the profit not yet turned into a point) and public.reputation_book (append-only, one row an earn).
--                 The book is a CHAIN, not a sum: a row must follow the row before it (reputation_book_chains, one
--                 primary-key probe), and at the end of the transaction the balance must be the newest row's
--                 (reputation_reconciles, deferred, two probes). Nothing ever sums the book.
--   THE WRITER    public.reputation_credit(player, kind, amount, key, note): the ONE place the balance moves. A merchant
--                 leaves after one players probe; the switch off writes nothing; a key is booked once ever; a capped
--                 kind past the day's cap writes nothing; a spend past the balance is refused E_NOT_ENOUGH_REPUTATION.
--   THE HELPERS   reputation_sale (profit to points, the remainder carried), reputation_arrival (miles, pirates seen
--                 off, a first landfall), reputation_request (a city's request delivered), reputation_built (a hull laid
--                 down), reputation_card (the read: balance, today, cap, the 8 newest rows). Every number is a knob.
--   THE HOOKS     one hunk each, sliced from the live bodies (pg_get_functiondef, LF), each once and reversing:
--                 cmd.do_sell (after 0162's promotion_credit line), voyage.settle (after 0162's promotion_credit
--                 statement, inside 0127's players-only block: a merchant's arrival pays nothing), cmd.run_fulfil (after
--                 the PREMIUM credit), cmd.do_build (after the ship is commissioned: the once-key is her id),
--                 world.player() (serves `reputation` beside `levels`).
--   THE KNOBS     reputation_on true, rep_profit_per_point 250, rep_sale_max 120, rep_nm_per_point 100, rep_miles_max 40,
--                 rep_per_fight_point 2, rep_landfall 25, rep_request_per_point 250, rep_request_min 5,
--                 rep_request_max 100, rep_built 100, rep_day_cap 600; and, seeded but read by nothing yet, rep_lap 10
--                 and rep_battle 40 (their kinds are seeded too: R4 and C5 hook them).
--
-- IT IS NOT GOLD: no row of ledger, no public.credit, no mint_guard, no stats_live. IT IS NOT AN EVENT: an earn writes
-- no events row (the book row is the record). No client can read or write the three tables or call a function here:
-- the read reaches a player through world.player() alone.
-- NO BACK-PAY: it banks from the deploy. A first landfall is a port she has no VOYAGE_REPORT to from before the voyage.
--
-- WHERE THIS FILE LEAVES docs/REPUTATION.md (the code was followed; each is in docs/dev-log/2026-11-11-reputation.md):
--   * cmd.do_build's hook stands after public.commission_ship, not after the HULL_LAID_DOWN emit: the ship has no id before.
--   * a request pays once a contract a house (key request:<contract id>): a contract is delivered in parts (0311), and an
--     uncapped kind with a floor of 5 a delivery would pay 5 a tun to a house that lands one tun at a time.
--   * two more helpers than the design names (reputation_request, reputation_built), so each hook is one line and no
--     amount stands in a door; and four more knobs (rep_miles_max, rep_request_per_point, rep_request_min, rep_request_max).
--   * the once-key is read again under the balance row's lock: two arrivals of one house at one instant would otherwise
--     both pass the first read and the second would die on the unique index, inside voyage.settle.
--   * two triggers named reputation_reconciles, one on each table (a trigger belongs to one table).
--
-- COST: a merchant's sale gains one function call and, at a gain, one players probe (what promotion_credit pays there
-- already). A merchant's arrival gains nothing. A human sale at a gain: the balance row twice, one book row, three
-- deferred probes. A human arrival: up to three book rows and one events probe. world.player(): one balance probe and
-- the 8 newest rows by the primary key. The self-assert prints OLD against NEW cmd.do_sell on probe merchant sales,
-- interleaved, bounded to 6 s.
-- ROLLBACK (forward, owner only): reputation_on false stops every write at once; a migration restoring the five OLD
-- hunks takes the hooks out. The tables stay.
-- SELF-ASSERT: the catalog, then probe houses of this file's own rows, every one rolled back by a raised sentinel. No
-- table is counted or summed. The real arrival (voyage.settle) is proved in CI: scripts/db/proofs/55_reputation.sql.
-- BUDGET (docs/OPS_HEALTH.md section 4): ONE DO block, statement_timeout 45 s, lock_timeout 5 s first. Fails above 45 s.
-- LOCKS: the three tables reference public.players (a brief SHARE ROW EXCLUSIVE on players, under lock_timeout 5 s).
-- VERSION: 0352. 0351 (world.best_sales only) shares no function with this file.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0          timestamptz := clock_timestamp();
  v_t           timestamptz;
  v_fn_before   text;
  v_cfg_before  text;
  v_def         text;
  v_do_sell_old text;
  d             record;
  h             record;
  v_p           record;
  v_n           int;
  v_m           int;
  v_ok          boolean;
  v_lived       boolean := false;
  v_pl          uuid;
  v_pl2         uuid;
  v_vet         uuid;
  v_npc         uuid;
  v_fl          uuid;
  v_fl2         uuid;
  v_nfl         uuid;
  v_lis         uuid;
  v_far         uuid;
  v_far_code    text;
  v_voy         uuid;
  v_good        uuid;
  v_good_code   text;
  v_r           jsonb;
  v_b           record;
  v_today       int := public.real_day(now());
  v_carry       numeric;
  v_want        int;
  v_sale_note   text := 'not run';
  v_arr_ms      numeric;
  v_old_ms      numeric := 0;
  v_new_ms      numeric := 0;
  v_pairs       int := 0;
  v_meas_note   text := '';
  v_human_ms    numeric;
  c_uid   constant uuid := '00000000-0352-4000-8000-000000000001';
  c_uid2  constant uuid := '00000000-0352-4000-8000-000000000002';
  c_uid3  constant uuid := '00000000-0352-4000-8000-000000000003';
  c_new_fns constant text[] := array[
    'public.reputation_book_chains()', 'public.reputation_reconciles()',
    'public.reputation_credit(uuid,text,integer,text,jsonb)', 'public.reputation_sale(uuid,bigint,jsonb)',
    'public.reputation_arrival(uuid,uuid)', 'public.reputation_request(uuid,bigint,uuid,jsonb)',
    'public.reputation_built(uuid,uuid,jsonb)', 'public.reputation_card(uuid)'];
  c_cut_fns constant text[] := array[
    'cmd.do_sell(uuid,jsonb)', 'voyage.settle(uuid,timestamp with time zone)', 'cmd.run_fulfil(uuid,uuid)',
    'cmd.do_build(uuid,jsonb)', 'world.player()'];
  c_knobs constant text[] := array[
    'reputation_on', 'rep_profit_per_point', 'rep_sale_max', 'rep_nm_per_point', 'rep_miles_max', 'rep_per_fight_point',
    'rep_landfall', 'rep_request_per_point', 'rep_request_min', 'rep_request_max', 'rep_built', 'rep_day_cap', 'rep_lap', 'rep_battle'];
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regclass('public.reputation_book') is not null or to_regprocedure('public.reputation_credit(uuid,text,integer,text,jsonb)') is not null
     or exists (select 1 from public.world_config c where c.key = any (c_knobs)) then
    raise exception '0352 refuses: it has been applied once';
  end if;
  if to_regprocedure('public.forbid_mutation()') is null or to_regprocedure('public.real_day(timestamp with time zone)') is null
     or to_regprocedure('public.voyage_xp_tracks(uuid)') is null or to_regprocedure('public.promotion_credit(uuid,uuid,text,numeric)') is null
     or to_regprocedure('public.wc_num(text)') is null or to_regprocedure('public.wc_int(text)') is null
     or to_regprocedure('cmd.refuse(text,text,jsonb)') is null or to_regprocedure('cmd.figures(numeric,numeric,text)') is null
     or to_regprocedure('public.client_write_grants()') is null
     or exists (select 1 from unnest(c_cut_fns) f where to_regprocedure(f) is null) then
    raise exception '0352 refuses: a function it calls or cuts is not in this world (0004 / 0127 / 0160 / 0162 / 0311)';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  create temp table defs_0352 on commit drop as
  select f.fn,
         replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
         coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
         (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
         (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
         (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
    from unnest(c_cut_fns) f(fn);
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (select f::regprocedure::oid from unnest(c_cut_fns) f);
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
    into v_cfg_before from public.world_config c;

  -- ── 2. THE HUNKS (each OLD text once in its live body; NEW is OLD and one statement more) ──
  create temp table hunks_0352 (fn text, n int, old text, new text) on commit drop;
  insert into hunks_0352 (fn, n, old, new) values
    ('cmd.do_sell(uuid,jsonb)', 1,
$o$  perform public.promotion_credit(f.player_id, f.port_id, 'trading', q.total / public.wc_num('fame_ducats_per_point'));
$o$,
$n$  perform public.promotion_credit(f.player_id, f.port_id, 'trading', q.total / public.wc_num('fame_ducats_per_point'));
  -- 0352 (R1): a sale at a gain earns Reputation (public.reputation_sale: a merchant earns none; a loss or an unknown cost earns none)
  perform public.reputation_sale(f.player_id, v_profit, jsonb_build_object('port', f.port_id, 'good', g.code));
$n$),
    ('voyage.settle(uuid,timestamp with time zone)', 1,
$o$              public.promotion_credit(f.player_id, v.dest_port_id, 'combat', x.combat)
         from public.voyage_xp_tracks(v.id) x;
$o$,
$n$              public.promotion_credit(f.player_id, v.dest_port_id, 'combat', x.combat)
         from public.voyage_xp_tracks(v.id) x;
      -- 0352 (R1): the arrival's Reputation: her miles, the pirates seen off, a first landfall (public.reputation_arrival)
      perform public.reputation_arrival(f.player_id, v.id);
$n$),
    ('cmd.run_fulfil(uuid,uuid)', 1,
$o$  perform public.credit(f.player_id, 'PREMIUM', v_pay, v_event);
$o$,
$n$  perform public.credit(f.player_id, 'PREMIUM', v_pay, v_event);
  -- 0352 (R1): a city's request delivered earns Reputation, once a contract (public.reputation_request)
  perform public.reputation_request(f.player_id, v_pay, c.id, jsonb_build_object('port', v_port.code, 'good', g.code));
$n$),
    ('cmd.do_build(uuid,jsonb)', 1,
$o$  v_ship := public.commission_ship(f.player_id, p_fleet, c.code, v_name, false, false);
$o$,
$n$  v_ship := public.commission_ship(f.player_id, p_fleet, c.code, v_name, false, false);
  -- 0352 (R1): a hull laid down earns Reputation, once a ship (public.reputation_built)
  perform public.reputation_built(f.player_id, v_ship, jsonb_build_object('class', c.code));
$n$),
    ('world.player()', 1,
$o$      'levels',        public.player_progress(v_id),
$o$,
$n$      'levels',        public.player_progress(v_id),
      -- 0352 (R1): her Reputation: balance, today against the day's cap, the 8 newest rows (public.reputation_card)
      'reputation',    public.reputation_card(v_id),
$n$);

  -- ── 3. THE TABLES ──
  create table public.reputation_kinds (
    code   text primary key,
    sign   smallint not null check (sign in (-1, 1)),
    capped boolean  not null default false,
    word   text     not null,
    check (not (sign = -1 and capped))
  );
  comment on table public.reputation_kinds is
    '0352: what may be booked in the Reputation book. sign 1 earns, -1 spends; capped counts against the day''s cap (rep_day_cap); word is the server''s English word. No amount lives here: every number is a world_config knob.';
  alter table public.reputation_kinds enable row level security;
  revoke all on table public.reputation_kinds from public, anon, authenticated;
  insert into public.reputation_kinds (code, sign, capped, word) values
    ('sale',     1, true,  'Sale'),
    ('miles',    1, true,  'Voyage'),
    ('pirates',  1, true,  'Pirates seen off'),
    ('landfall', 1, false, 'First landfall'),
    ('request',  1, false, 'Request delivered'),
    ('built',    1, false, 'Ship built'),
    ('lap',      1, true,  'Route lap'),
    ('battle',   1, false, 'Battle won'),
    ('level',    1, false, 'Level reached'),
    ('convert',  1, false, 'Items converted'),
    ('skill',   -1, false, 'Captain skill'),
    ('promote', -1, false, 'Promotion');

  create table public.reputation_balance (
    player_id  uuid primary key references public.players(id) on delete cascade,
    balance    int     not null default 0 check (balance >= 0),
    seq        int     not null default 0 check (seq >= 0),
    day        int     not null default 0,
    day_earned int     not null default 0 check (day_earned >= 0),
    carry      numeric not null default 0 check (carry >= 0)
  );
  comment on table public.reputation_balance is
    '0352: a company''s Reputation. balance is the newest book row''s balance_after (seq names it; reputation_reconciles holds the two together at commit). day is public.real_day of day_earned, what the capped kinds earned that day. carry is sale profit not yet turned into a point. Written by public.reputation_credit and public.reputation_sale alone. Not gold: never in ledger.';
  alter table public.reputation_balance enable row level security;
  revoke all on table public.reputation_balance from public, anon, authenticated;

  create table public.reputation_book (
    player_id     uuid not null references public.players(id) on delete cascade,
    seq           int  not null check (seq >= 1),
    kind          text not null references public.reputation_kinds(code),
    delta         int  not null check (delta <> 0),
    balance_after int  not null check (balance_after >= 0),
    key           text,
    note          jsonb not null default '{}'::jsonb,
    created_at    timestamptz not null default now(),
    primary key (player_id, seq)
  );
  create unique index reputation_book_once on public.reputation_book (player_id, key) where key is not null;
  comment on table public.reputation_book is
    '0352: the Reputation book, APPEND-ONLY (public.forbid_mutation, as events and ledger) and a CHAIN: each row follows the row before it (reputation_book_chains). key is the once-ever guard (landfall:LIS, miles:<voyage>). Written by public.reputation_credit alone. An earn writes no events row: this row is the record.';
  alter table public.reputation_book enable row level security;
  revoke all on table public.reputation_book from public, anon, authenticated;

  -- ── 4. THE TRIGGER FUNCTIONS ──
  execute $f$
create function public.reputation_book_chains()
returns trigger
language plpgsql
as $body$
-- 0352: a book row follows the row before it. One primary-key probe; no sum.
begin
  if new.seq = 1 then
    if new.balance_after <> new.delta then
      raise exception 'reputation_book: row 1 of % opens at %, not at its own delta %', new.player_id, new.balance_after, new.delta using errcode = '23514';
    end if;
  elsif not exists (select 1 from public.reputation_book b
                     where b.player_id = new.player_id and b.seq = new.seq - 1 and b.balance_after + new.delta = new.balance_after) then
    raise exception 'reputation_book: row % of % does not follow row % (balance_after % after a delta of %)',
      new.seq, new.player_id, new.seq - 1, new.balance_after, new.delta using errcode = '23514';
  end if;
  return new;
end
$body$
  $f$;
  execute $f$
create function public.reputation_reconciles()
returns trigger
language plpgsql
as $body$
-- 0352: at the end of the transaction the balance is the newest book row's, and no row stands past it. Two probes; no sum.
declare
  v_balance int;
  v_seq     int;
begin
  select b.balance, b.seq into v_balance, v_seq from public.reputation_balance b where b.player_id = new.player_id;
  if not found then
    raise exception 'reputation: % has a book row and no balance row', new.player_id using errcode = '23514';
  end if;
  if v_seq = 0 then
    if v_balance <> 0 then
      raise exception 'reputation: % holds % with an empty book', new.player_id, v_balance using errcode = '23514';
    end if;
  elsif not exists (select 1 from public.reputation_book k
                     where k.player_id = new.player_id and k.seq = v_seq and k.balance_after = v_balance) then
    raise exception 'reputation: the balance of % (% at row %) is not its newest book row''s', new.player_id, v_balance, v_seq using errcode = '23514';
  end if;
  if exists (select 1 from public.reputation_book k where k.player_id = new.player_id and k.seq = v_seq + 1) then
    raise exception 'reputation: the book of % runs past its balance row (row %)', new.player_id, v_seq + 1 using errcode = '23514';
  end if;
  return null;
end
$body$
  $f$;
  create trigger reputation_book_append_only
    before update or delete on public.reputation_book
    for each row execute function public.forbid_mutation();
  create trigger reputation_book_chains
    before insert on public.reputation_book
    for each row execute function public.reputation_book_chains();
  create constraint trigger reputation_reconciles
    after insert on public.reputation_book
    deferrable initially deferred
    for each row execute function public.reputation_reconciles();
  create constraint trigger reputation_reconciles
    after insert or update of balance, seq on public.reputation_balance
    deferrable initially deferred
    for each row execute function public.reputation_reconciles();

  -- ── 5. THE KNOBS ──
  insert into public.world_config (key, value, description) values
    ('reputation_on', 'true'::jsonb,
     '0352: Reputation is earned while true. false stops every write of public.reputation_credit and public.reputation_sale at once (the rollback switch); the read still serves what was banked.'),
    ('rep_profit_per_point', to_jsonb(250),
     '0352: a sale earns 1 Reputation for this many ducats of profit (cmd.do_sell''s own profit, before tax). The remainder is carried to the next sale.'),
    ('rep_sale_max', to_jsonb(120), '0352: the most Reputation one sale earns.'),
    ('rep_nm_per_point', to_jsonb(100), '0352: an arrival at a port earns 1 Reputation for this many nautical miles of the voyage. A shorter voyage earns none.'),
    ('rep_miles_max', to_jsonb(40), '0352: the most Reputation one arrival earns for its miles.'),
    ('rep_per_fight_point', to_jsonb(2),
     '0352: Reputation for each combat point of a voyage (public.voyage_xp_tracks: pirates evaded xp_evaded_points, driven off xp_driven_off_points).'),
    ('rep_landfall', to_jsonb(25), '0352: Reputation for the first arrival at a port, once a port ever. 0 = none.'),
    ('rep_request_per_point', to_jsonb(250), '0352: a city''s request delivered earns 1 Reputation for this many ducats of its bonus, once a contract.'),
    ('rep_request_min', to_jsonb(5), '0352: the least Reputation a delivered request earns.'),
    ('rep_request_max', to_jsonb(100), '0352: the most Reputation a delivered request earns.'),
    ('rep_built', to_jsonb(100), '0352: Reputation for a hull laid down, once a ship. 0 = none.'),
    ('rep_day_cap', to_jsonb(600), '0352: the most Reputation a company earns in one real day (UTC, public.real_day) from the capped kinds: sale, miles, pirates, lap.'),
    ('rep_lap', to_jsonb(10), '0352: Reputation for a standing-route lap closed at a gain. SEEDED, READ BY NOTHING YET (slice R4 hooks it).'),
    ('rep_battle', to_jsonb(40), '0352: Reputation for a battle won. SEEDED, READ BY NOTHING YET (slice C5 hooks it).');

  -- ── 6. THE ONE WRITER ──
  execute $f$
create function public.reputation_credit(p_player uuid, p_kind text, p_amount int, p_key text default null, p_note jsonb default '{}'::jsonb)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0352: THE ONE WRITER of Reputation. Returns what was booked (0 when nothing was). An earn passes a positive amount, a
-- spend a negative one; the kind's sign must agree. A merchant leaves after one players probe (docs/REPUTATION.md 1.3).
declare
  k        public.reputation_kinds%rowtype;
  b        public.reputation_balance%rowtype;
  v_amount int := p_amount;
  v_today  int;
  v_earned int;
begin
  if p_player is null or p_amount is null or p_amount = 0 then
    return 0;
  end if;
  if coalesce((select pl.is_npc from public.players pl where pl.id = p_player), true) then
    return 0;
  end if;
  if public.wc('reputation_on') is distinct from 'true'::jsonb then
    return 0;
  end if;
  select * into k from public.reputation_kinds rk where rk.code = p_kind;
  if k.code is null then
    raise exception 'reputation_credit: no kind is called %', p_kind using errcode = '22023';
  end if;
  if sign(p_amount) <> k.sign then
    raise exception 'reputation_credit: % books a % amount and was given %', p_kind, case k.sign when 1 then 'positive' else 'negative' end, p_amount using errcode = '22023';
  end if;
  if p_key is not null and exists (select 1 from public.reputation_book rb where rb.player_id = p_player and rb.key = p_key) then
    return 0;
  end if;
  insert into public.reputation_balance (player_id) values (p_player) on conflict (player_id) do nothing;
  select * into b from public.reputation_balance rb where rb.player_id = p_player for update;
  -- under the lock, the key again: two calls at one instant both pass the read above, and only one may book
  if p_key is not null and exists (select 1 from public.reputation_book rb where rb.player_id = p_player and rb.key = p_key) then
    return 0;
  end if;
  v_today  := b.day;
  v_earned := b.day_earned;
  if k.capped then
    if b.day <> public.real_day(now()) then
      v_today  := public.real_day(now());
      v_earned := 0;
    end if;
    v_amount := least(v_amount, public.wc_int('rep_day_cap') - v_earned);
    if v_amount <= 0 then
      return 0;
    end if;
    v_earned := v_earned + v_amount;
  end if;
  if k.sign = -1 and b.balance < -v_amount then
    perform cmd.refuse('E_NOT_ENOUGH_REPUTATION', format('Needs %s Reputation: you have %s', -v_amount, b.balance),
      cmd.figures(b.balance, -v_amount, 'reputation'));
  end if;
  insert into public.reputation_book (player_id, seq, kind, delta, balance_after, key, note)
  values (p_player, b.seq + 1, p_kind, v_amount, b.balance + v_amount, p_key, coalesce(p_note, '{}'::jsonb));
  update public.reputation_balance
     set balance = b.balance + v_amount, seq = b.seq + 1, day = v_today, day_earned = v_earned
   where player_id = p_player;
  return v_amount;
end
$body$
  $f$;

  -- ── 7. THE HELPERS ──
  execute $f$
create function public.reputation_sale(p_player uuid, p_profit bigint, p_note jsonb default '{}'::jsonb)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0352: A SALE AT A GAIN. The profit joins what was carried; every whole rep_profit_per_point of it is one point (at most
-- rep_sale_max a sale) and the remainder is carried on, so splitting a lot gains no rounding. A loss, an unknown cost, a
-- merchant and the switch off: nothing, and nothing is written. The profit itself stays cmd.do_sell's (the SOLD event).
declare
  v_per   numeric;
  v_carry numeric;
  v_pts   numeric;
begin
  if p_player is null or p_profit is null or p_profit <= 0 then
    return 0;
  end if;
  if coalesce((select pl.is_npc from public.players pl where pl.id = p_player), true) then
    return 0;
  end if;
  if public.wc('reputation_on') is distinct from 'true'::jsonb then
    return 0;
  end if;
  v_per := public.wc_num('rep_profit_per_point');
  if v_per <= 0 then
    return 0;
  end if;
  insert into public.reputation_balance (player_id) values (p_player) on conflict (player_id) do nothing;
  select rb.carry into v_carry from public.reputation_balance rb where rb.player_id = p_player for update;
  v_carry := v_carry + p_profit;
  v_pts   := floor(v_carry / v_per);
  update public.reputation_balance set carry = v_carry - v_pts * v_per where player_id = p_player;
  if v_pts < 1 then
    return 0;
  end if;
  return public.reputation_credit(p_player, 'sale', least(v_pts, public.wc_int('rep_sale_max'))::int, null, coalesce(p_note, '{}'::jsonb));
end
$body$
  $f$;
  execute $f$
create function public.reputation_arrival(p_player uuid, p_voyage uuid)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0352: AN ARRIVAL. The pirates she saw off (public.voyage_xp_tracks, the one reading of a voyage's fights), her miles when
-- she makes a port, and a first landfall: a port she has no VOYAGE_REPORT to from before this voyage sailed, once a port
-- ever. Each is keyed by the voyage or the port, so settling twice books once. Returns what was booked.
declare
  v_nm     numeric;
  v_dest   uuid;
  v_sailed timestamptz;
  v_code   text;
  v_per    numeric;
  v_pts    numeric;
  v_n      int := 0;
begin
  if p_player is null or coalesce((select pl.is_npc from public.players pl where pl.id = p_player), true) then
    return 0;
  end if;
  if public.wc('reputation_on') is distinct from 'true'::jsonb then
    return 0;
  end if;
  select v.total_nm, v.dest_port_id, v.departed_at into v_nm, v_dest, v_sailed
    from public.voyages v where v.id = p_voyage and v.player_id = p_player;
  if not found then
    return 0;
  end if;
  v_pts := floor(coalesce((select x.combat from public.voyage_xp_tracks(p_voyage) x), 0) * public.wc_num('rep_per_fight_point'));
  if v_pts >= 1 then
    v_n := v_n + public.reputation_credit(p_player, 'pirates', v_pts::int, 'pirates:' || p_voyage, jsonb_build_object('voyage', p_voyage));
  end if;
  if v_dest is null then
    return v_n;   -- anchored in open water: no port was made
  end if;
  select p.code into v_code from public.ports p where p.id = v_dest;
  v_per := public.wc_num('rep_nm_per_point');
  if v_per > 0 and v_nm >= v_per then
    v_pts := least(floor(v_nm / v_per), public.wc_int('rep_miles_max'));
    if v_pts >= 1 then
      v_n := v_n + public.reputation_credit(p_player, 'miles', v_pts::int, 'miles:' || p_voyage, jsonb_build_object('voyage', p_voyage, 'port', v_code));
    end if;
  end if;
  if public.wc_int('rep_landfall') > 0
     and not exists (select 1 from public.reputation_book rb where rb.player_id = p_player and rb.key = 'landfall:' || v_code)
     and not exists (select 1 from public.events e
                      where e.player_id = p_player and e.kind = 'VOYAGE_REPORT' and e.payload ->> 'to' = v_code and e.created_at < v_sailed) then
    v_n := v_n + public.reputation_credit(p_player, 'landfall', public.wc_int('rep_landfall'), 'landfall:' || v_code, jsonb_build_object('port', v_code));
  end if;
  return v_n;
end
$body$
  $f$;
  execute $f$
create function public.reputation_request(p_player uuid, p_premium bigint, p_contract uuid, p_note jsonb default '{}'::jsonb)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0352: A CITY'S REQUEST DELIVERED. 1 point for each rep_request_per_point ducats of the bonus, at least rep_request_min,
-- at most rep_request_max, ONCE A CONTRACT (a contract is delivered in parts, 0311: the floor is not paid a part).
declare
  v_per numeric;
begin
  if p_player is null or p_contract is null or p_premium is null or p_premium <= 0
     or coalesce((select pl.is_npc from public.players pl where pl.id = p_player), true) then
    return 0;
  end if;
  if public.wc('reputation_on') is distinct from 'true'::jsonb then
    return 0;
  end if;
  v_per := public.wc_num('rep_request_per_point');
  if v_per <= 0 then
    return 0;
  end if;
  return public.reputation_credit(p_player, 'request',
    least(greatest(floor(p_premium / v_per), public.wc_int('rep_request_min')), public.wc_int('rep_request_max'))::int,
    'request:' || p_contract, coalesce(p_note, '{}'::jsonb));
end
$body$
  $f$;
  execute $f$
create function public.reputation_built(p_player uuid, p_ship uuid, p_note jsonb default '{}'::jsonb)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0352: A HULL LAID DOWN. rep_built, once a ship (her id is the key).
begin
  if p_player is null or p_ship is null
     or coalesce((select pl.is_npc from public.players pl where pl.id = p_player), true) then
    return 0;
  end if;
  if public.wc('reputation_on') is distinct from 'true'::jsonb then
    return 0;
  end if;
  return public.reputation_credit(p_player, 'built', public.wc_int('rep_built'), 'built:' || p_ship, coalesce(p_note, '{}'::jsonb));
end
$body$
  $f$;
  execute $f$
create function public.reputation_card(p_player uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0352: THE READ. Her balance, what the capped kinds earned today against the day's cap, the newest book row, and the 8
  -- newest rows (newest first). A company with no row reads zeros. Served through world.player() alone.
  select jsonb_build_object(
    'balance', coalesce(b.balance, 0),
    'today',   case when b.day = public.real_day(now()) then b.day_earned else 0 end,
    'cap',     public.wc_int('rep_day_cap'),
    'seq',     coalesce(b.seq, 0),
    'recent',  coalesce((select jsonb_agg(jsonb_build_object('seq', r.seq, 'kind', r.kind, 'delta', r.delta, 'at', r.created_at) order by r.seq desc)
                           from (select k.seq, k.kind, k.delta, k.created_at from public.reputation_book k
                                  where k.player_id = p_player order by k.seq desc limit 8) r), '[]'::jsonb))
    from (select 1) one
    left join public.reputation_balance b on b.player_id = p_player
$body$
  $f$;
  revoke all on function public.reputation_book_chains() from public, anon, authenticated;
  revoke all on function public.reputation_reconciles() from public, anon, authenticated;
  revoke all on function public.reputation_credit(uuid, text, int, text, jsonb) from public, anon, authenticated;
  revoke all on function public.reputation_sale(uuid, bigint, jsonb) from public, anon, authenticated;
  revoke all on function public.reputation_arrival(uuid, uuid) from public, anon, authenticated;
  revoke all on function public.reputation_request(uuid, bigint, uuid, jsonb) from public, anon, authenticated;
  revoke all on function public.reputation_built(uuid, uuid, jsonb) from public, anon, authenticated;
  revoke all on function public.reputation_card(uuid) from public, anon, authenticated;

  -- ── 8. THE RE-CUTS (each hunk once) ──
  for d in select * from defs_0352 order by fn loop
    v_def := d.def;
    for h in select * from hunks_0352 x where x.fn = d.fn order by x.n loop
      v_n := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
      if v_n <> 1 then
        raise exception '0352 slice: hunk % of % occurs % time(s), expected exactly 1: the deployed body is not what this migration was written against', h.n, d.fn, v_n;
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    execute v_def;
  end loop;
  select x.def into v_do_sell_old from defs_0352 x where x.fn = 'cmd.do_sell(uuid,jsonb)';

  -- ── 9. THE SELF-ASSERT: the catalog ──
  for d in select * from defs_0352 order by fn loop
    v_def := replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '');
    for h in select * from hunks_0352 x where x.fn = d.fn order by x.n desc loop
      if (length(v_def) - length(replace(v_def, h.new, ''))) / length(h.new) <> 1 then
        raise exception '0352 self-assert FAIL: hunk % of % is not in the new body exactly once', h.n, d.fn;
      end if;
      v_def := replace(v_def, h.new, h.old);
    end loop;
    if v_def <> d.def then
      raise exception '0352 self-assert FAIL: % does not reverse to its pre-image', d.fn;
    end if;
    select coalesce(pr.proacl::text, '') as acl, pr.provolatile as vol, pr.prosecdef as secdef, coalesce(pr.proconfig::text, '') as cfg
      into v_p from pg_proc pr where pr.oid = d.fn::regprocedure;
    if v_p.acl <> d.acl or v_p.vol <> d.vol or v_p.secdef <> d.secdef or v_p.cfg <> d.cfg then
      raise exception '0352 self-assert FAIL: % changed its ACL, volatility, definer or config', d.fn;
    end if;
  end loop;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (select f::regprocedure::oid from unnest(c_cut_fns || c_new_fns) f)) <> v_fn_before then
    raise exception '0352 self-assert FAIL: a function this file does not name moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
        from public.world_config c where c.key <> all (c_knobs)) <> v_cfg_before
     or (select count(*) from public.world_config c where c.key = any (c_knobs)) <> array_length(c_knobs, 1) then
    raise exception '0352 self-assert FAIL: an existing world_config row moved, or a knob of this file is missing';
  end if;
  if exists (select 1 from unnest(c_new_fns) f cross join unnest(array['anon', 'authenticated']) r(role)
              where has_function_privilege(r.role, f, 'execute')) then
    raise exception '0352 self-assert FAIL: a client may call a Reputation function';
  end if;
  if exists (select 1 from unnest(array['anon', 'authenticated']) r(role)
               cross join unnest(array['public.reputation_kinds', 'public.reputation_balance', 'public.reputation_book']) t(tab)
              where has_table_privilege(r.role, t.tab, 'select,insert,update,delete')) then
    raise exception '0352 self-assert FAIL: a client can read or write a Reputation table';
  end if;
  if exists (select 1 from pg_class c where c.oid in ('public.reputation_kinds'::regclass, 'public.reputation_balance'::regclass, 'public.reputation_book'::regclass)
                and not c.relrowsecurity) then
    raise exception '0352 self-assert FAIL: a Reputation table has no row level security';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0352 self-assert FAIL: % client write grant(s)', (select count(*) from public.client_write_grants());
  end if;
  if (select p.provolatile from pg_proc p where p.oid = 'public.reputation_card(uuid)'::regprocedure) <> 's'
     or (select p.provolatile from pg_proc p where p.oid = 'world.player()'::regprocedure) <> 's' then
    raise exception '0352 self-assert FAIL: the read is not STABLE';
  end if;
  if (select count(*) from public.reputation_kinds) <> 12
     or (select string_agg(k.code, ',' order by k.code) from public.reputation_kinds k where k.capped) <> 'lap,miles,pirates,sale'
     or (select string_agg(k.code, ',' order by k.code) from public.reputation_kinds k where k.sign = -1) <> 'promote,skill' then
    raise exception '0352 self-assert FAIL: the kinds did not land whole';
  end if;
  -- nothing here is gold or an event: no Reputation function names the purse, the ledger, the mint guard, the live figures or the event writer
  if exists (select 1 from unnest(c_new_fns) f join pg_proc p on p.oid = f::regprocedure
              where p.prosrc ~ '(public\.credit\(|ledger|mint_guard|stats_live|emit_event)') then
    raise exception '0352 self-assert FAIL: a Reputation function names the purse, the ledger, the mint guard, the live figures or an event';
  end if;

  -- ── 10. THE SELF-ASSERT: probe houses of this file's own rows, every one rolled back ──
  begin
    select p.id into v_lis from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR';
    select p.id, p.code into v_far, v_far_code from public.ports p where p.kind = 'HARBOUR' and p.code <> 'LIS' order by p.code limit 1;
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
    values (c_uid, 'Casa da Fama 0352', (select n.id from public.nations n where n.code = 'PRT'), 0, false) returning id into v_pl;
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
    values (c_uid2, 'Casa da Viagem 0352', (select n.id from public.nations n where n.code = 'PRT'), 0, false) returning id into v_pl2;
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
    values (c_uid3, 'Casa Antiga 0352', (select n.id from public.nations n where n.code = 'PRT'), 0, false) returning id into v_vet;
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
    values (null, 'Casa Mercante 0352', (select n.id from public.nations n where n.code = 'PRT'), 0, true) returning id into v_npc;

    -- (a) THE CHAIN: three credits are rows 1 to 3 and the balance is the last row's
    if public.reputation_credit(v_pl, 'built', 5, 'probe:a') <> 5 or public.reputation_credit(v_pl, 'landfall', 25, 'probe:b') <> 25
       or public.reputation_credit(v_pl, 'request', 7) <> 7 then
      raise exception '0352 self-assert FAIL: three credits did not book 5, 25 and 7';
    end if;
    select * into v_b from public.reputation_balance where player_id = v_pl;
    if v_b.seq <> 3 or v_b.balance <> 37 or v_b.day_earned <> 0
       or (select string_agg(k.seq || ':' || k.delta || ':' || k.balance_after, ',' order by k.seq) from public.reputation_book k where k.player_id = v_pl) <> '1:5:5,2:25:30,3:7:37' then
      raise exception '0352 self-assert FAIL: the chain is not rows 1 to 3 ending at the balance: %', to_jsonb(v_b);
    end if;
    set constraints public.reputation_reconciles immediate;   -- the honest chain reconciles
    set constraints public.reputation_reconciles deferred;
    v_ok := false;
    begin
      insert into public.reputation_book (player_id, seq, kind, delta, balance_after) values (v_pl, 4, 'built', 1, 99);
    exception when sqlstate '23514' then v_ok := true;
    end;
    if not v_ok then raise exception '0352 self-assert FAIL: a hand-made row with a wrong balance_after was taken'; end if;
    v_ok := false;
    begin
      insert into public.reputation_book (player_id, seq, kind, delta, balance_after) values (v_pl, 5, 'built', 1, 38);
    exception when sqlstate '23514' then v_ok := true;
    end;
    if not v_ok then raise exception '0352 self-assert FAIL: a row that skips a number was taken'; end if;
    v_ok := false;
    begin
      update public.reputation_book set delta = 6 where player_id = v_pl and seq = 1;
    exception when sqlstate '42501' then v_ok := true;
    end;
    if not v_ok then raise exception '0352 self-assert FAIL: a book row was updated'; end if;
    v_ok := false;
    begin
      delete from public.reputation_book where player_id = v_pl and seq = 3;
    exception when sqlstate '42501' then v_ok := true;
    end;
    if not v_ok then raise exception '0352 self-assert FAIL: a book row was deleted'; end if;
    v_ok := false;
    begin
      update public.reputation_balance set balance = balance + 1 where player_id = v_pl;
      set constraints public.reputation_reconciles immediate;
    exception when sqlstate '23514' then v_ok := true;
    end;
    set constraints public.reputation_reconciles deferred;
    if not v_ok then raise exception '0352 self-assert FAIL: a balance moved with no book row and the deferred check let it stand'; end if;
    v_ok := false;
    begin
      insert into public.reputation_book (player_id, seq, kind, delta, balance_after) values (v_pl, 4, 'built', 1, 38);   -- chained, and the balance row not moved
      set constraints public.reputation_reconciles immediate;
    exception when sqlstate '23514' then v_ok := true;
    end;
    set constraints public.reputation_reconciles deferred;
    if not v_ok then raise exception '0352 self-assert FAIL: a book row past the balance row was let stand'; end if;
    -- a key books once; a spend comes off; a spend past the balance is refused with its figures; a wrong sign and an unknown kind are errors
    -- (a read in the same expression as a credit would see the snapshot before it: each credit is its own statement)
    v_n := public.reputation_credit(v_pl, 'built', 5, 'probe:a');
    v_m := public.reputation_credit(v_pl, 'skill', -30);
    if v_n <> 0 or v_m <> -30 or (select balance from public.reputation_balance where player_id = v_pl) <> 7 then
      raise exception '0352 self-assert FAIL: a key booked twice, or a spend of 30 did not leave 7';
    end if;
    v_ok := false;
    begin
      perform public.reputation_credit(v_pl, 'skill', -50);
    exception when others then
      v_ok := sqlerrm like '%E_NOT_ENOUGH_REPUTATION%' and sqlerrm like '%Needs 50 Reputation: you have 7%';
      if not v_ok then raise exception '0352 self-assert FAIL: a spend past the balance was refused in other words: %', sqlerrm; end if;
    end;
    if not v_ok then raise exception '0352 self-assert FAIL: a spend past the balance was booked'; end if;
    v_ok := false;
    begin
      perform public.reputation_credit(v_pl, 'skill', 5);
    exception when sqlstate '22023' then v_ok := true;
    end;
    if not v_ok then raise exception '0352 self-assert FAIL: a spend kind took a positive amount'; end if;
    v_ok := false;
    begin
      perform public.reputation_credit(v_pl, 'no-such-kind', 5);
    exception when sqlstate '22023' then v_ok := true;
    end;
    if not v_ok then raise exception '0352 self-assert FAIL: an unknown kind was booked'; end if;

    -- (b) A SALE: 7,200 profit is 28 and carries 200; 100 then 150 is 0 then 1; a loss and an unknown cost are nothing; one sale earns at most 120
    v_n := public.reputation_sale(v_pl, 7200, '{}');
    if v_n <> 28 or (select carry from public.reputation_balance where player_id = v_pl) <> 200 then
      raise exception '0352 self-assert FAIL: a profit of 7,200 did not earn 28 and carry 200';
    end if;
    update public.reputation_balance set carry = 0 where player_id = v_pl;
    v_n := public.reputation_sale(v_pl, 100, '{}');
    v_m := public.reputation_sale(v_pl, 150, '{}');
    if v_n <> 0 or v_m <> 1
       or (select carry from public.reputation_balance where player_id = v_pl) <> 0 then
      raise exception '0352 self-assert FAIL: 100 then 150 of profit did not earn 0 then 1';
    end if;
    select seq into v_n from public.reputation_balance where player_id = v_pl;
    v_m := public.reputation_sale(v_pl, -500, '{}') + public.reputation_sale(v_pl, null, '{}') + public.reputation_sale(v_pl, 0, '{}');
    if v_m <> 0
       or (select seq from public.reputation_balance where player_id = v_pl) <> v_n
       or (select carry from public.reputation_balance where player_id = v_pl) <> 0 then
      raise exception '0352 self-assert FAIL: a loss or an unknown cost earned or was carried';
    end if;
    v_n := public.reputation_sale(v_pl, 1000000, '{}');
    if v_n <> 120 or (select day_earned from public.reputation_balance where player_id = v_pl) <> 149 then
      raise exception '0352 self-assert FAIL: one sale earned past rep_sale_max, or the day did not count 28 + 1 + 120';
    end if;

    -- (c) THE DAY'S CAP: at 590, 28 books 10; the next books nothing and writes no row; a new day starts at nothing
    update public.reputation_balance set day_earned = 590 where player_id = v_pl;
    if public.reputation_sale(v_pl, 7000, '{}') <> 10 then
      raise exception '0352 self-assert FAIL: 28 at 590 of 600 did not book 10';
    end if;
    select seq into v_n from public.reputation_balance where player_id = v_pl;
    v_m := public.reputation_sale(v_pl, 7000, '{}');
    if v_m <> 0 or (select seq from public.reputation_balance where player_id = v_pl) <> v_n
       or exists (select 1 from public.reputation_book k where k.player_id = v_pl and k.seq = v_n + 1) then
      raise exception '0352 self-assert FAIL: an earn past the day''s cap booked or wrote a row';
    end if;
    if public.reputation_credit(v_pl, 'landfall', 25, 'probe:c') <> 25 then
      raise exception '0352 self-assert FAIL: a kind outside the cap was stopped by it';
    end if;
    update public.reputation_balance set day = v_today - 1 where player_id = v_pl;
    v_n := public.reputation_sale(v_pl, 250, '{}');
    if v_n <> 1
       or (select day || ':' || day_earned from public.reputation_balance where player_id = v_pl) <> v_today || ':1' then
      raise exception '0352 self-assert FAIL: a new day did not start the cap again';
    end if;

    -- (d) AN ARRIVAL (a stub voyage: voyage.settle itself is proved in CI, proof 55). The first voyage of docs/REPUTATION.md: 28 + 12 + 25 = 65.
    v_fl := public.form_fleet(v_pl2, 'Viagem', v_lis);
    v_voy := gen_random_uuid();
    insert into public.voyages (id, fleet_id, player_id, path, total_nm, speed_profile, departed_at, eta, status, origin_port_id, dest_port_id)
    values (v_voy, v_fl, v_pl2, '[]', 1200, '{}', now() - interval '10 minutes', now() - interval '1 minute', 'ARRIVED', v_lis, v_far);
    v_n := public.reputation_sale(v_pl2, 7200, '{}');
    v_t := clock_timestamp();
    v_m := public.reputation_arrival(v_pl2, v_voy);
    v_arr_ms := extract(epoch from clock_timestamp() - v_t) * 1000;
    if v_n <> 28 or v_m <> 37 or (select balance from public.reputation_balance where player_id = v_pl2) <> 65
       or (select string_agg(k.kind || ':' || k.delta, ',' order by k.seq) from public.reputation_book k where k.player_id = v_pl2) <> 'sale:28,miles:12,landfall:25' then
      raise exception '0352 self-assert FAIL: a first voyage of 1,200 nm with 7,200 of profit is not 28 + 12 + 25 = 65 (sale %, arrival %)', v_n, v_m;
    end if;
    if public.reputation_arrival(v_pl2, v_voy) <> 0 then
      raise exception '0352 self-assert FAIL: an arrival settled twice booked twice';
    end if;
    -- a second voyage to the same port: her miles, the pirates seen off (one driven off, one evaded), no second landfall
    v_voy := gen_random_uuid();
    insert into public.voyages (id, fleet_id, player_id, path, total_nm, speed_profile, departed_at, eta, status, origin_port_id, dest_port_id)
    values (v_voy, v_fl, v_pl2, '[]', 9000, '{}', now() - interval '10 minutes', now() - interval '1 minute', 'ARRIVED', v_lis, v_far);
    insert into public.voyage_events (voyage_id, day_index, kind, payload) values
      (v_voy, 1, 'PIRATES', jsonb_build_object('outcome', 'DRIVEN_OFF')), (v_voy, 2, 'PIRATES', jsonb_build_object('outcome', 'EVADED'));
    v_want := floor((public.wc_num('xp_driven_off_points') + public.wc_num('xp_evaded_points')) * 2)::int;
    v_n := public.reputation_arrival(v_pl2, v_voy);
    if v_n <> 40 + v_want
       or (select string_agg(k.kind || ':' || k.delta, ',' order by k.kind) from public.reputation_book k where k.player_id = v_pl2 and k.key like '%' || v_voy) <> 'miles:40,pirates:' || v_want then
      raise exception '0352 self-assert FAIL: 9,000 nm with two fights did not book 40 miles (the most) and % for the pirates, with no second landfall', v_want;
    end if;
    -- short of 100 nm: nothing for the miles; anchored in open water: no miles and no landfall
    v_voy := gen_random_uuid();
    insert into public.voyages (id, fleet_id, player_id, path, total_nm, speed_profile, departed_at, eta, status, origin_port_id, dest_port_id)
    values (v_voy, v_fl, v_pl2, '[]', 99, '{}', now() - interval '10 minutes', now() - interval '1 minute', 'ARRIVED', v_far, v_far);
    if public.reputation_arrival(v_pl2, v_voy) <> 0 then
      raise exception '0352 self-assert FAIL: a voyage of 99 nm to a port she knows earned';
    end if;
    v_voy := gen_random_uuid();
    insert into public.voyages (id, fleet_id, player_id, path, total_nm, speed_profile, departed_at, eta, status, origin_port_id, dest_port_id)
    values (v_voy, v_fl, v_pl2, '[]', 5000, '{}', now() - interval '10 minutes', now() - interval '1 minute', 'ARRIVED', v_far, null);
    if public.reputation_arrival(v_pl2, v_voy) <> 0 then
      raise exception '0352 self-assert FAIL: a voyage that ended in open water earned miles or a landfall';
    end if;
    -- no back-pay: a house with an older report to that port makes no first landfall there
    v_fl2 := public.form_fleet(v_vet, 'Antiga', v_lis);
    insert into public.events (player_id, kind, payload, created_at)
    values (v_vet, 'VOYAGE_REPORT', jsonb_build_object('to', v_far_code, 'total_nm', 300), now() - interval '1 day');
    v_voy := gen_random_uuid();
    insert into public.voyages (id, fleet_id, player_id, path, total_nm, speed_profile, departed_at, eta, status, origin_port_id, dest_port_id)
    values (v_voy, v_fl2, v_vet, '[]', 300, '{}', now() - interval '10 minutes', now() - interval '1 minute', 'ARRIVED', v_lis, v_far);
    v_n := public.reputation_arrival(v_vet, v_voy);
    if v_n <> 3
       or exists (select 1 from public.reputation_book k where k.player_id = v_vet and k.kind = 'landfall') then
      raise exception '0352 self-assert FAIL: a port she had a report to before the deploy paid a first landfall';
    end if;

    -- (e) A REQUEST AND A HULL: the arithmetic, and once a contract, once a ship
    v_voy := gen_random_uuid();
    if public.reputation_request(v_vet, 10000, v_voy) <> 40 or public.reputation_request(v_vet, 10000, v_voy) <> 0
       or public.reputation_request(v_vet, 100, gen_random_uuid()) <> 5 or public.reputation_request(v_vet, 1000000, gen_random_uuid()) <> 100
       or public.reputation_request(v_vet, 0, gen_random_uuid()) <> 0 then
      raise exception '0352 self-assert FAIL: a request did not earn 40 once, 5 at the least and 100 at the most';
    end if;
    v_voy := gen_random_uuid();
    if public.reputation_built(v_vet, v_voy) <> 100 or public.reputation_built(v_vet, v_voy) <> 0 then
      raise exception '0352 self-assert FAIL: a hull did not earn 100 once';
    end if;

    -- (f) A MERCHANT: nothing, and no row
    v_n := public.reputation_credit(v_npc, 'landfall', 25, 'probe:m') + public.reputation_sale(v_npc, 7200, '{}')
           + public.reputation_request(v_npc, 10000, gen_random_uuid()) + public.reputation_built(v_npc, gen_random_uuid());
    if v_n <> 0
       or exists (select 1 from public.reputation_balance b where b.player_id = v_npc)
       or exists (select 1 from public.reputation_book k where k.player_id = v_npc) then
      raise exception '0352 self-assert FAIL: a merchant earned Reputation or has a row';
    end if;

    -- (g) THE READ, through world.player() as she reads it
    perform cmd.assume_identity(c_uid2);
    v_r := world.player() -> 'player' -> 'reputation';
    if (v_r ->> 'balance')::int <> 65 + 40 + v_want or (v_r ->> 'cap')::int <> 600 or (v_r ->> 'today')::int <> 28 + 12 + 40 + v_want
       or (v_r ->> 'seq')::int <> 5 or jsonb_array_length(v_r -> 'recent') <> 5 or (v_r -> 'recent' -> 0 ->> 'seq')::int <> 5
       or (v_r -> 'recent' -> 4 ->> 'kind') <> 'sale' or (v_r -> 'recent' -> 4 ->> 'delta')::int <> 28 then
      raise exception '0352 self-assert FAIL: world.player() does not serve her Reputation: %', v_r;
    end if;
    perform cmd.assume_identity(c_uid);
    if jsonb_array_length(world.player() -> 'player' -> 'reputation' -> 'recent') <> 8 then
      raise exception '0352 self-assert FAIL: the read does not stop at the 8 newest rows';
    end if;
    if (public.reputation_card(v_npc) ->> 'balance')::int <> 0 or jsonb_array_length(public.reputation_card(v_npc) -> 'recent') <> 0 then
      raise exception '0352 self-assert FAIL: a company with no row does not read zeros';
    end if;

    -- (h) A REAL SALE through cmd.do_sell books what public.reputation_sale says (a human), and OLD against NEW on a merchant
    select g.id, g.code into v_good, v_good_code
      from public.port_goods pg join public.goods g on g.id = pg.good_id
     where pg.port_id = v_lis and g.bulk <= 1 and pg.stock_target > 0
       and not public.culture_refuses((select p.culture from public.ports p where p.id = v_lis), g.culture_mask)
     order by pg.stock_target desc, g.code limit 1;   -- the deepest market at Lisbon: the day's allowance is a share of it
    v_fl2 := public.form_fleet(v_pl, 'Fama', v_lis);
    perform public.commission_ship(v_pl, v_fl2, 'barca', 'Fama', true, true);
    v_nfl := public.form_fleet(v_npc, 'Mercante', v_lis);
    perform public.commission_ship(v_npc, v_nfl, 'barca', 'Mercante', true, true);
    if v_good is null or public.fleet_load(v_fl2, v_good_code, 10, 1) <> 10 then
      raise exception '0352 self-assert FAIL: the probe found no good to load at Lisbon';
    end if;
    update public.reputation_balance set day = v_today, day_earned = 0, carry = 0 where player_id = v_pl;
    select seq into v_n from public.reputation_balance where player_id = v_pl;
    -- In a world whose switches this file cannot foresee (the city's purse lit, the economy closed) the door may refuse a
    -- house with an empty purse: there, and only there, the refusal is printed and the sale is left to CI's proof 55.
    v_r := null;
    begin
      v_t := clock_timestamp();
      v_r := cmd.do_sell(v_fl2, jsonb_build_object('good', v_good, 'qty', 10));
      v_human_ms := extract(epoch from clock_timestamp() - v_t) * 1000;
    exception when others then
      if not (public.city_treasury_on() or public.economy_closed()) then raise; end if;
      v_r := null;
      v_sale_note := 'the door refused the probe in this world (' || left(sqlerrm, 90) || '): NOT RUN HERE, proved in CI by proof 55';
    end;
    if v_r is not null then
      v_want := case when (v_r ->> 'profit')::bigint > 0 then least(floor((v_r ->> 'profit')::numeric / 250), 120)::int else 0 end;
      select * into v_b from public.reputation_balance where player_id = v_pl;
      if v_b.seq <> v_n + sign(v_want)::int or v_b.day_earned <> v_want
         or v_b.carry <> greatest((v_r ->> 'profit')::numeric, 0) - floor(greatest((v_r ->> 'profit')::numeric, 0) / 250) * 250
         or (v_want > 0 and (select k.kind || ':' || k.delta || ':' || (k.note ->> 'good') from public.reputation_book k where k.player_id = v_pl and k.seq = v_b.seq)
                             is distinct from 'sale:' || v_want || ':' || v_good_code)
         or exists (select 1 from public.events e where e.player_id = v_pl and e.kind ilike '%REPUTATION%') then
        raise exception '0352 self-assert FAIL: a real sale with a profit of % did not book % (row %, today %, carried %)', v_r ->> 'profit', v_want, v_b.seq, v_b.day_earned, v_b.carry;
      end if;
      v_sale_note := format('a profit of %s booked %s in %s ms', v_r ->> 'profit', v_want, round(v_human_ms, 1));
    end if;
    -- OLD against NEW cmd.do_sell on probe merchant sales, interleaved (0250's method), bounded to 6 s
    begin
      execute replace(v_do_sell_old, 'FUNCTION cmd.do_sell(', 'FUNCTION pg_temp.do_sell_old_0352(');
      v_t := clock_timestamp();
      for i in 1 .. 100 loop
        exit when clock_timestamp() - v_t > interval '6 seconds';
        perform public.fleet_load(v_nfl, v_good_code, 20, 1);
        delete from public.trade_daily td where td.player_id = v_npc;   -- the probe merchant's own allowance, so 200 sales are not stopped by the day's cap
        declare
          t1 timestamptz;
          t2 timestamptz;
          t3 timestamptz;
        begin
          if i % 2 = 0 then
            t1 := clock_timestamp(); perform pg_temp.do_sell_old_0352(v_nfl, jsonb_build_object('good', v_good, 'qty', 10));
            t2 := clock_timestamp(); perform cmd.do_sell(v_nfl, jsonb_build_object('good', v_good, 'qty', 10));
            t3 := clock_timestamp();
            v_old_ms := v_old_ms + extract(epoch from t2 - t1) * 1000; v_new_ms := v_new_ms + extract(epoch from t3 - t2) * 1000;
          else
            t1 := clock_timestamp(); perform cmd.do_sell(v_nfl, jsonb_build_object('good', v_good, 'qty', 10));
            t2 := clock_timestamp(); perform pg_temp.do_sell_old_0352(v_nfl, jsonb_build_object('good', v_good, 'qty', 10));
            t3 := clock_timestamp();
            v_new_ms := v_new_ms + extract(epoch from t2 - t1) * 1000; v_old_ms := v_old_ms + extract(epoch from t3 - t2) * 1000;
          end if;
        end;
        v_pairs := v_pairs + 1;
      end loop;
    exception when others then   -- a measurement, never a gate: whatever stops it is printed
      v_meas_note := ' (stopped: ' || left(sqlerrm, 90) || ')';
    end;
    if exists (select 1 from public.reputation_balance b where b.player_id = v_npc) or exists (select 1 from public.reputation_book k where k.player_id = v_npc) then
      raise exception '0352 self-assert FAIL: a merchant''s real sales wrote a Reputation row';
    end if;

    -- (i) THE SWITCH OFF (this file's own knob, put back by the rollback): nothing is written
    update public.world_config set value = 'false'::jsonb where key = 'reputation_on';
    select seq, carry into v_n, v_carry from public.reputation_balance where player_id = v_pl2;
    v_m := public.reputation_credit(v_pl2, 'landfall', 25, 'probe:off') + public.reputation_sale(v_pl2, 7200, '{}')
           + public.reputation_request(v_pl2, 10000, gen_random_uuid()) + public.reputation_built(v_pl2, gen_random_uuid());
    if v_m <> 0
       or (select seq from public.reputation_balance where player_id = v_pl2) <> v_n
       or (select carry from public.reputation_balance where player_id = v_pl2) <> v_carry
       or (world.player() -> 'player' -> 'reputation') is null then
      raise exception '0352 self-assert FAIL: with reputation_on false something was booked or carried, or the read went';
    end if;
    set constraints public.reputation_reconciles immediate;   -- every probe row of this transaction reconciles
    set constraints public.reputation_reconciles deferred;
    raise exception using errcode = 'ZX352', message = 'PROBE_ROLLBACK_0352';
  exception when sqlstate 'ZX352' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0352 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.company_name like 'Casa % 0352' or p.auth_uid in (c_uid, c_uid2, c_uid3))
     or (select c.value from public.world_config c where c.key = 'reputation_on') <> 'true'::jsonb
     or to_regprocedure('pg_temp.do_sell_old_0352(uuid,jsonb)') is not null then
    raise exception '0352 self-assert FAIL: the probe left something behind';
  end if;
  if public.current_player_id() is not null then
    raise exception '0352 self-assert FAIL: the probe''s identity outlived its rollback';
  end if;
  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0352 self-assert FAIL: the file took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0352 cost: cmd.do_sell on % probe merchant sales, OLD and NEW interleaved: OLD % ms a sale, NEW % ms a sale%. A human sale through the door: %. public.reputation_arrival on a stub voyage (miles and a first landfall): % ms.',
    v_pairs * 2, case when v_pairs > 0 then round(v_old_ms / v_pairs, 2) end, case when v_pairs > 0 then round(v_new_ms / v_pairs, 2) end, v_meas_note, v_sale_note, round(v_arr_ms, 1);
  raise notice '0352 self-assert ok: EVERY SUCCESS EARNS REPUTATION (R1). Three tables no client reads or writes, 12 kinds, 14 knobs, 8 functions no client calls; 5 hunks, each once and reversing, ACL, volatility, definer and config unmoved; no other function and no existing knob moved; 0 client write grants. The probe (rolled back): three credits chained 1 to 3 and the balance was the last row''s; a wrong row, a skipped row, an update, a delete, a balance with no row and a row past the balance were all refused; a key booked once; a spend past the balance was refused with its figures. A profit of 7,200 earned 28 and carried 200; 100 then 150 earned 0 then 1; a loss and an unknown cost earned nothing; one sale earned at most 120. At 590 of 600 a 28 booked 10 and the next wrote no row; a new day started again. A first voyage of 1,200 nm with 7,200 of profit: 28 + 12 + 25 = 65; settled twice, once; 9,000 nm booked 40; two fights seen off booked their points; 99 nm and open water booked nothing; a port known before the deploy paid no landfall. A request earned 40 once, 5 at least, 100 at most; a hull 100 once. A merchant: nothing and no row. reputation_on false: nothing written, the read still served. The real arrival is proved in CI (proof 55). % ms.',
    round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end
$m$;
