-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0237 — EVERY PORT CHARGES AND TAKES A MINUTE
--        (slice E4b of docs/CLOSED_ECONOMY.md §4c: lit, every harbour a fleet makes charges her a dock fee — players
--         and merchants alike, paid INTO the city's purse — she needs one real minute in port before she sails again,
--         and the profit tax and the fee are scaled by how her country stands with the city's. DARK (the economy
--         open, as it is): no fee, no port time, factor 1 — every body answers byte for byte as before.)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER, VERBATIM (docs/OWNER_REQUESTS.md row 215, 2026-10-26) ────────────────────────────
--   "the players and merchants should pay a fee for every city it visits for restock. and it will take realtime 1 min
--    to get back to ocean - preparation. the tax based on country should be different, for example if you are in the
--    same country, no tax ~ few tax, where as relationship between country means more tax."
--
-- ── WHAT LIGHTS IT ──────────────────────────────────────────────────────────────────────────────
--   public.economy_closed() — the closed-economy switch (0228; E7's economy_close_switch). Every new path asks it, so
--   this slice goes live WITH the switch, as the owner wants. Its own knobs can each turn a part off while lit:
--   port_fee_base and port_fee_pct at 0 → no fee; port_prep_seconds 0 → no port time; country_tax_factor all 1 →
--   no country scaling. Dark, the knobs are never read on any path that changes an answer.
--
-- ── THE PIECES ──────────────────────────────────────────────────────────────────────────────────
--   RELATIONS — NOT A NEW TABLE. §4c asks for `power_relations` (same / friendly / neutral / rival, seeded from
--     1500–1650 history). It EXISTS since 0196 (data/relations.json: 13 pairs of the ten great powers, 1580–1640,
--     each with its reason — Spain–Portugal ally under the Iberian Union, Ottoman–Spain rival, Ming–Japan rival,
--     Netherlands–Spain at war …), read by ONE reader, public.power_stance(a, b): home / ally / peace / rival / war.
--     A second relations table would be a second authority (NO_SPAGHETTI). §4c's words map onto it: same = home,
--     friendly = ally, neutral = peace, rival = rival AND war.
--   HOME COUNTRY — NOT A NEW COLUMN. players.nation_id IS it: for every player it equals her founding port's power
--     (prod 2026-10-26: 19 of 19), and a merchant company's nation is her capital's by definition (nations.capital
--     _port_code of players.nation_id, the country E4's gifts read).
--   KNOBS: port_fee_base 50, port_fee_pct 0.005, port_prep_seconds 60,
--          country_tax_factor {home 0.25, ally 0.5, peace 1, rival 2, war 2}.
--   NEW, server-only:
--   * public.country_factor(stance) — THE one factor (§4c): 1 while the economy is open; closed, the knob's entry.
--   * public.port_fee(port, player, value) — THE one dock fee: closed and the purses lit, at a harbour with a purse,
--       round((port_fee_base + port_fee_pct × value) × country_factor(her stance there)); else 0. `value` = the cargo
--       aboard at what it cost (public.fleet_stock_at_cost — the basis her books count as hers; no quote is asked).
--   * public.port_call(fleet, port, player, at, now, event) — THE one writer of a port call, from voyage.settle's
--       arrival: the fee is paid from her purse to the city (public.pay_city, kind PORT_FEE — moved, never burned);
--       what the purse cannot cover is OWED (public.port_fee_debts) and taken from her next sale there; and her port
--       time is set: fleets.ready_at = the arrival instant + port_prep_seconds (only when that is still ahead — a
--       voyage settled late is ready at once, by the same clock every reader uses).
--   * public.port_fee_collect(player, port, net) — cmd.do_sell's: the owed fee, up to the sale's net, to the city.
--   * public.port_time_wake(now, until, only) — tick_arrivals': a fleet whose port time is up runs her queue
--       (cmd.advance), so a SAIL that waited leaves now. Each fleet woken once (ready_at cleared).
--   * public.preparing_refusal(ready_at, now) — the E_PREPARING refusal: "ready in 42 s", figures = the seconds gone
--       of the seconds asked (cmd.figures: have, need, 'seconds').
--   * public.port_dues(port, player, value) — the reads' `dues` key {stance, factor, fee, fee_base, fee_pct,
--       prep_seconds}; '{}' while the economy is open or with nobody signed in, so dark reads are byte for byte.
--   * public.port_fee_debts(player_id, port_id, ducats, updated_at) — what a company owes a harbour. Mutable (a debt
--       is paid down), server-only (RLS on, no grant). Empty while dark.
--   * fleets.ready_at (nullable) + a partial index on it — null for every fleet while dark.
--   stats_flow_words: PORT_FEE → moved ("Dock fees").
--
-- ── HUNKS SLICED FROM THE LIVE BODIES (prod head 0234, LF-normalised; each asserted to occur exactly once and to
--    reverse to its pre-image; ACL / volatility / definer / config unchanged) ────────────────────────────────────
--   voyage.settle ×1        the port call at arrival, before the queue runs (lit only)
--   voyage.sail_refusal ×1  E_PREPARING with the seconds left, right after the status gate (ready_at in the future)
--   world.tax_rate ×1       closed: least(base × country_factor, greatest(base, tariff_rate_max)) in place of 0147's
--                           citizen cut and 0196's tariff (with a company, the race on — where 0196's tariff applies)
--   public.tick_arrivals ×1 the port-time wake, after the route wakes, before the waiting merchants are asked
--   cmd.advance ×1          a SAIL waits in the queue while her port time runs (the halt rule untouched)
--   cmd.do_sell ×1          the owed fee taken from the sale, after tax and wages
--   cmd.preview ×1          a SAIL is judged as it will run when she is ready (her port time set aside inside the
--                           preview's rolled-back block), so the send tray can queue it — "a SAIL sent sooner waits"
--   world.fleets ×1         `ready_at` on a fleet in her port time (absent otherwise)
--   world.town_hall ×1      `dues` (the signed-in company's stance, factor and fee base here; lit only)
--   world.good_board ×1     `dues` on every sell row (the fee for this parcel there; lit only)
--   None of the ten is sliced by 0236 (capital_gift_pass).
--
-- ── WHAT IT SELF-ASSERTS (probe companies only; flows counted are above a mark taken in-block AND at this
--    transaction's now(); every probe in a sub-transaction, rolled back, asserted) ────────────────────────────
--   (a) the hunks reverse; ACL / volatility / definer / config unmoved; the new functions server-only; the debts table
--       holds no client grant; registry unchanged; walls 0; ready_at null on every fleet; no debt.
--   (b) THE COUNTRY FACTOR, every harbour × ten probe companies (one of each great power), the purses and the race
--       lit: OPEN, world.tax_rate equals its pre-image (a pg_temp copy) for every pair; CLOSED, it equals
--       least(base × factor, greatest(base, tariff_rate_max)), base = the pre-image's company-less rate — every
--       stance (home, ally, peace, rival, war) seen.
--   (c) DARK, A DOCKING AND A SALE, BYTE FOR BYTE: a probe Dutch company sails Lisbon → Funchal (a Portuguese
--       harbour: at war) with 40 t aboard at 25; the voyage is set to have landed 30 s ago; voyage.settle then a SELL
--       there — through the NEW bodies and through pg_temp copies of the OLD settle and do_sell, from the same state
--       — leave the same flows, ledger, purse, fleet row, events and sale answer; no fee, no ready_at, no debt; the
--       board and the Town Hall serve no `dues`, her fleet no `ready_at`.
--   (d) LIT, THE SAME CALL: fee = round((50 + 0.005 × 1,000) × 2) = 110; her purse of 10 pays 10 (PORT_FEE +10 at
--       Funchal, −10 on her ledger), 100 is owed; ready_at = landed + 60 s (30 s ahead); a SAIL queued at sea waits
--       (pending); sail_refusal answers E_PREPARING with 30 of 60 seconds; the preview of a SAIL is not refused;
--       the board's sell rows and the Town Hall serve `dues` (war, 2); her fleet serves `ready_at`; her SELL there
--       pays the 100 owed out of its net (PORT_FEE +100) and clears the debt; the wake finds nothing while she
--       prepares, and once her port time is up (ready_at moved back past now — the clock passing, stated) it wakes
--       her once: the SAIL is done, she is SAILING, ready_at null.
--   No table that grows on production is counted or summed against a remembered figure; nothing is DELETEd from an
--   append-only table; no `set role`; tick_arrivals / npc ticks are never RUN (the wake is called for the probe fleet
--   alone); nothing reads the hour of day (the probe's times are relative to its own now()).
-- ROLLBACK (forward): reverse the ten hunks (each OLD text is here verbatim); drop the seven functions, the table, the
--   column and its index, the four knobs and the PORT_FEE word. Lit, the switch off is enough: every path is dark.
-- VERSION: 0237 = 0236 + 1 (0235 is reserved by the coordinator for a slice in flight).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regprocedure('public.economy_closed()') is null or to_regprocedure('public.capital_pays(uuid,uuid,uuid,text,bigint,uuid,boolean,jsonb)') is null then
    raise exception '0237 refuses: 0228 / 0234 (E1, E4) is not in this world';
  end if;
  if to_regclass('public.power_relations') is null or to_regprocedure('public.power_stance(uuid,uuid)') is null
     or to_regprocedure('public.pay_city(uuid,uuid,text,bigint,uuid)') is null then
    raise exception '0237 refuses: 0196 / 0122 is not in this world';
  end if;
  if to_regprocedure('public.port_fee(uuid,uuid,numeric)') is not null or to_regclass('public.port_fee_debts') is not null then
    raise exception '0237 refuses: public.port_fee already exists — this has been applied once';
  end if;
  if public.economy_closed() then
    raise exception '0237 refuses: the economy is already closed — this slice ships dark';
  end if;
end $guard$;

create or replace function pg_temp.occurs_0237(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 0. THE PRE-IMAGES (LF-normalised), and copies of three of them to compare against ───────────
create temp table defs_before_0237 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('voyage.settle(uuid,timestamptz)'),
               ('voyage.sail_refusal(uuid,uuid,jsonb,numeric,jsonb)'),
               ('world.tax_rate(uuid,uuid)'),
               ('public.tick_arrivals(timestamptz)'),
               ('cmd.advance(uuid,timestamptz)'),
               ('cmd.do_sell(uuid,jsonb)'),
               ('cmd.preview(uuid,text,jsonb)'),
               ('world.fleets()'),
               ('world.town_hall(uuid)'),
               ('world.good_board(uuid,uuid,uuid,numeric)')) f(fn);

create temp table before_0237 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points;

do $$
declare
  r record;
begin
  for r in select * from (values ('voyage.settle(uuid,timestamptz)', 'FUNCTION voyage.settle(', 'FUNCTION pg_temp.settle_old_0237('),
                                 ('cmd.do_sell(uuid,jsonb)', 'FUNCTION cmd.do_sell(', 'FUNCTION pg_temp.do_sell_old_0237('),
                                 ('world.tax_rate(uuid,uuid)', 'FUNCTION world.tax_rate(', 'FUNCTION pg_temp.tax_rate_old_0237(')) x(fn, a, b) loop
    if pg_temp.occurs_0237((select def from defs_before_0237 d where d.fn = r.fn), r.a) <> 1 then
      raise exception '0237 self-assert FAIL: %''s definition does not name itself once', r.fn;
    end if;
    execute replace((select def from defs_before_0237 d where d.fn = r.fn), r.a, r.b);
  end loop;
end $$;

-- ── 1. THE KNOBS, THE WORD, THE COLUMN, THE DEBTS ───────────────────────────────────────────────
insert into public.world_config (key, value, description) values
  ('port_fee_base', to_jsonb(50),
   '0237 (docs/CLOSED_ECONOMY.md §4c): the dock fee every harbour charges a fleet that makes it, before the cargo share — × the country factor. Read only while the economy is closed (public.port_fee).'),
  ('port_fee_pct', to_jsonb(0.005),
   '0237: the dock fee''s share of the cargo aboard, at what it cost (public.fleet_stock_at_cost): 0.005 = 0.5 %.'),
  ('port_prep_seconds', to_jsonb(60),
   '0237: real seconds a fleet needs in a harbour after making it before she sails again (fleets.ready_at). Written only while the economy is closed; 0 = none.'),
  ('country_tax_factor', '{"home": 0.25, "ally": 0.5, "peace": 1, "rival": 2, "war": 2}'::jsonb,
   '0237 (§4c): how a company''s country standing with a city''s holder (public.power_stance) scales the profit tax and the dock fee while the economy is closed — same country 0.25×, friendly 0.5×, neutral 1×, rival or at war 2×. Open: 1.');

insert into public.stats_flow_words (kind, side, word, ord) values ('PORT_FEE', 'moved', 'Dock fees', 41);

alter table public.fleets add column ready_at timestamptz;
comment on column public.fleets.ready_at is
  '0237 (docs/CLOSED_ECONOMY.md §4c): her port time — she may not sail before this instant (voyage.sail_refusal E_PREPARING; a queued SAIL waits in cmd.advance and public.port_time_wake runs it). One writer: public.port_call, at arrival, only while the economy is closed. Null = ready.';
create index fleets_ready_at on public.fleets (ready_at) where ready_at is not null;

create table public.port_fee_debts (
  player_id  uuid        not null references public.players(id) on delete cascade,
  port_id    uuid        not null references public.ports(id),
  ducats     bigint      not null check (ducats > 0),
  updated_at timestamptz not null default now(),
  primary key (player_id, port_id)
);
comment on table public.port_fee_debts is
  '0237 (§4c): the dock fee a company''s purse could not pay when her fleet made this harbour — taken from her next sale there (public.port_fee_collect). One writer each way: public.port_call (owed), public.port_fee_collect (paid). Server-only.';
alter table public.port_fee_debts enable row level security;
revoke all on table public.port_fee_debts from public, anon, authenticated;

-- ── 2. THE COUNTRY FACTOR ───────────────────────────────────────────────────────────────────────
create function public.country_factor(p_stance text)
returns numeric
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0237 (docs/CLOSED_ECONOMY.md §4c): THE one factor a company's standing with a city's holder (public.power_stance:
-- home / ally / peace / rival / war) puts on the profit tax and the dock fee. 1 while the economy is open; closed,
-- country_tax_factor's entry. A stance the knob does not price RAISES (a defect, never a silent 1).
declare
  v numeric;
begin
  if not public.economy_closed() then
    return 1;
  end if;
  v := (public.wc('country_tax_factor') ->> coalesce(p_stance, 'peace'))::numeric;
  if v is null or v < 0 then
    raise exception 'E_NO_COUNTRY_FACTOR: country_tax_factor does not price the stance "%"', coalesce(p_stance, '') using errcode = 'P0001';
  end if;
  return v;
end $$;
comment on function public.country_factor(text) is
  '0237: the country factor of a stance (home 0.25, ally 0.5, peace 1, rival 2, war 2) while the economy is closed; 1 while open. Server-only.';
revoke all on function public.country_factor(text) from public, anon, authenticated;

-- ── 3. THE DOCK FEE ─────────────────────────────────────────────────────────────────────────────
create function public.port_fee(p_port uuid, p_player uuid, p_value numeric)
returns bigint
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0237 (§4c): THE one dock fee — what harbour p_port charges company p_player's fleet with cargo worth p_value (at
-- cost) aboard: round((port_fee_base + port_fee_pct × value) × country_factor). 0 while the economy is open, while
-- the purses are dark, for a company of nobody, and at a place with no purse.
begin
  if p_player is null or not public.economy_closed() or not public.city_treasury_on()
     or not exists (select 1 from public.port_treasury t join public.ports p on p.id = t.port_id
                     where t.port_id = p_port and p.kind = 'HARBOUR') then
    return 0;
  end if;
  return greatest(0, round((public.wc_num('port_fee_base') + public.wc_num('port_fee_pct') * greatest(coalesce(p_value, 0), 0))
                           * public.country_factor(public.power_stance(
                               (select pl.nation_id from public.players pl where pl.id = p_player), public.port_nation(p_port)))))::bigint;
end $$;
comment on function public.port_fee(uuid, uuid, numeric) is
  '0237: the dock fee a harbour charges a company for a cargo worth p_value aboard — 0 while the economy is open. Server-only.';
revoke all on function public.port_fee(uuid, uuid, numeric) from public, anon, authenticated;

-- ── 4. THE PORT CALL (voyage.settle's arrival) ──────────────────────────────────────────────────
create function public.port_call(p_fleet uuid, p_port uuid, p_player uuid, p_at timestamptz, p_now timestamptz, p_event uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0237 (§4c): THE one writer of a port call. Fleet p_fleet of company p_player made harbour p_port at p_at (the voyage's
-- eta — the deterministic instant, never the settle's clock). Closed only (null while open). The dock fee is paid from
-- her purse to the city (PORT_FEE, through public.pay_city — the house first, then the harbour); what the purse cannot
-- cover is owed (public.port_fee_debts) — she still docks. Her port time: ready_at = p_at + port_prep_seconds, written
-- only when that instant is still ahead of p_now. Answers {fee, paid, owed, ready_at}.
declare
  v_fee   bigint;
  v_purse bigint;
  v_pay   bigint := 0;
  v_owed  bigint := 0;
  v_prep  numeric;
  v_ready timestamptz;
begin
  if not public.economy_closed()
     or not exists (select 1 from public.ports p where p.id = p_port and p.kind = 'HARBOUR') then
    return null;
  end if;
  v_fee := public.port_fee(p_port, p_player, public.fleet_stock_at_cost(p_fleet));
  if v_fee > 0 then
    select pl.ducats into v_purse from public.players pl where pl.id = p_player for update;
    v_pay := least(v_fee, greatest(coalesce(v_purse, 0), 0));
    if v_pay > 0 then
      perform public.pay_city(p_player, p_port, 'PORT_FEE', v_pay, p_event);
    end if;
    v_owed := v_fee - v_pay;
    if v_owed > 0 then
      insert into public.port_fee_debts as d (player_id, port_id, ducats, updated_at)
      values (p_player, p_port, v_owed, p_now)
      on conflict (player_id, port_id) do update set ducats = d.ducats + excluded.ducats, updated_at = excluded.updated_at;
    end if;
  end if;
  v_prep := coalesce(public.wc_num('port_prep_seconds'), 0);
  if v_prep > 0 and p_at + make_interval(secs => v_prep::double precision) > p_now then
    v_ready := p_at + make_interval(secs => v_prep::double precision);
    update public.fleets set ready_at = v_ready where id = p_fleet and status = 'DOCKED';
    if not found then
      v_ready := null;
    end if;
  end if;
  return jsonb_build_object('fee', v_fee, 'paid', v_pay, 'owed', v_owed, 'ready_at', v_ready);
end $$;
comment on function public.port_call(uuid, uuid, uuid, timestamptz, timestamptz, uuid) is
  '0237: a fleet makes a harbour — the dock fee to the city (what the purse cannot pay is owed) and her port time (fleets.ready_at). Closed only. Called by voyage.settle. Server-only.';
revoke all on function public.port_call(uuid, uuid, uuid, timestamptz, timestamptz, uuid) from public, anon, authenticated;

-- ── 5. THE OWED FEE, TAKEN FROM HER NEXT SALE THERE (cmd.do_sell) ───────────────────────────────
create function public.port_fee_collect(p_player uuid, p_port uuid, p_net bigint)
returns bigint
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0237 (§4c): what company p_player owes harbour p_port is paid out of a sale there — up to the sale's net (p_net) and
-- her purse — to the city (PORT_FEE). Nothing owed (always, while the economy has never been closed): one key read,
-- nothing written. Answers the ducats taken.
declare
  v_debt bigint;
  v_take bigint;
begin
  select d.ducats into v_debt from public.port_fee_debts d where d.player_id = p_player and d.port_id = p_port for update;
  if v_debt is null or not public.city_treasury_on() then
    return 0;
  end if;
  v_take := least(v_debt, greatest(coalesce(p_net, 0), 0),
                  greatest(coalesce((select pl.ducats from public.players pl where pl.id = p_player), 0), 0));
  if v_take <= 0 then
    return 0;
  end if;
  perform public.pay_city(p_player, p_port, 'PORT_FEE', v_take, null);
  if v_take >= v_debt then
    delete from public.port_fee_debts d where d.player_id = p_player and d.port_id = p_port;
  else
    update public.port_fee_debts d set ducats = d.ducats - v_take, updated_at = now()
     where d.player_id = p_player and d.port_id = p_port;
  end if;
  return v_take;
end $$;
comment on function public.port_fee_collect(uuid, uuid, bigint) is
  '0237: the dock fee a company owes a harbour, taken from her sale there (up to its net). Called by cmd.do_sell. Server-only.';
revoke all on function public.port_fee_collect(uuid, uuid, bigint) from public, anon, authenticated;

-- ── 6. THE WAKE (tick_arrivals) ─────────────────────────────────────────────────────────────────
create function public.port_time_wake(p_now timestamptz, p_until timestamptz, p_only uuid default null)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0237 (§4c): every fleet whose port time is up (fleets.ready_at ≤ p_now) runs her queue — cmd.advance, so the SAIL
-- that waited leaves now. ready_at is cleared first: each fleet is woken once. Inside the arrivals job's budget
-- (p_until); SKIP LOCKED as its other passes. p_only narrows it to one fleet (a probe). Answers the fleets woken.
-- While the economy is open no fleet has a ready_at: the partial index holds nothing to find.
declare
  r   record;
  v_n int := 0;
begin
  for r in select f.id from public.fleets f
            where f.ready_at is not null and f.ready_at <= p_now and (p_only is null or f.id = p_only)
            order by f.ready_at
              for update skip locked loop
    exit when clock_timestamp() >= p_until;
    update public.fleets set ready_at = null where id = r.id;
    perform cmd.advance(r.id, p_now);
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;
comment on function public.port_time_wake(timestamptz, timestamptz, uuid) is
  '0237: fleets whose port time is up run their queue (a waiting SAIL leaves). Called by public.tick_arrivals. Server-only.';
revoke all on function public.port_time_wake(timestamptz, timestamptz, uuid) from public, anon, authenticated;

-- ── 7. THE REFUSAL, AND THE READS' KEY ──────────────────────────────────────────────────────────
create function public.preparing_refusal(p_ready timestamptz, p_now timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0237 (§4c): E_PREPARING — she is in her port time; ready in N s. Figures: the seconds gone of the seconds asked.
declare
  v_left numeric := ceil(greatest(extract(epoch from (p_ready - p_now)), 0));
  v_need numeric := greatest(coalesce(public.wc_num('port_prep_seconds'), 0), v_left, 1);
begin
  return cmd.refusal('E_PREPARING', format('she is making ready in port — %s s to go', v_left),
                     cmd.figures(v_need - v_left, v_need, 'seconds'));
end $$;
comment on function public.preparing_refusal(timestamptz, timestamptz) is
  '0237: the E_PREPARING refusal (seconds left; figures have/need in seconds). Read by voyage.sail_refusal. Server-only.';
revoke all on function public.preparing_refusal(timestamptz, timestamptz) from public, anon, authenticated;

create function public.port_dues(p_port uuid, p_player uuid, p_value numeric default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0237 (§4c): {dues: {stance, factor, fee, fee_base, fee_pct, prep_seconds}} — what harbour p_port asks company p_player:
-- her standing there, the factor on its tax and fee, the fee for cargo worth p_value (at cost; none = the base). '{}'
-- while the economy is open, while the purses are dark, with nobody signed in, at a place with no purse.
declare
  v_stance text;
begin
  if p_player is null or not public.economy_closed() or not public.city_treasury_on()
     or not exists (select 1 from public.port_treasury t join public.ports p on p.id = t.port_id
                     where t.port_id = p_port and p.kind = 'HARBOUR') then
    return '{}'::jsonb;
  end if;
  v_stance := public.power_stance((select pl.nation_id from public.players pl where pl.id = p_player), public.port_nation(p_port));
  return jsonb_build_object('dues', jsonb_build_object(
    'stance', v_stance, 'factor', public.country_factor(v_stance),
    'fee', public.port_fee(p_port, p_player, p_value),
    'fee_base', public.wc_num('port_fee_base'), 'fee_pct', public.wc_num('port_fee_pct'),
    'prep_seconds', public.wc_num('port_prep_seconds')));
end $$;
comment on function public.port_dues(uuid, uuid, numeric) is
  '0237: the reads'' `dues` key — stance, country factor, dock fee — or {} while the economy is open. Read by world.town_hall and world.good_board. Server-only.';
revoke all on function public.port_dues(uuid, uuid, numeric) from public, anon, authenticated;

-- ── 8. THE HUNKS (each occurs exactly once in the live body) ─────────────────────────────────────
create temp table hunks_0237 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0237 values
('voyage.settle(uuid,timestamptz)', 1,
$h$    -- 0225: the standing order (0034) no longer fires here — every SAIL buys its own stores (cmd.do_sail).
    perform cmd.advance(p_fleet, p_now);
$h$,
$h$    -- 0237 (E4b, docs/CLOSED_ECONOMY.md §4c): THE PORT CALL — closed, the harbour charges her its dock fee (PORT_FEE, to
    -- the city's purse; what her purse cannot pay is owed and taken from her next sale there) and she needs her port time
    -- before she sails again (fleets.ready_at). public.port_call is the one writer of both. Open: nothing.
    if v.dest_port_id is not null and public.economy_closed() then
      perform public.port_call(p_fleet, v.dest_port_id, f.player_id, v.eta, p_now, v_report);
    end if;
    -- 0225: the standing order (0034) no longer fires here — every SAIL buys its own stores (cmd.do_sail).
    perform cmd.advance(p_fleet, p_now);
$h$),
('voyage.sail_refusal(uuid,uuid,jsonb,numeric,jsonb)', 1,
$h$      format('she is %s — a fleet sails from a quay or from her own anchor', f.status));
  end if;
$h$,
$h$      format('she is %s — a fleet sails from a quay or from her own anchor', f.status));
  end if;

  -- 0237 (E4b, §4c): HER PORT TIME — after making a harbour she needs port_prep_seconds before she sails (fleets.ready_at,
  -- written by public.port_call only while the economy is closed): E_PREPARING with the seconds left.
  if f.ready_at is not null and f.ready_at > now() then
    return public.preparing_refusal(f.ready_at, now());
  end if;
$h$),
('world.tax_rate(uuid,uuid)', 1,
$h$  if v_stance = 'home' then
$h$,
$h$  -- 0237 (E4b, §4c): closed, THE COUNTRY FACTOR (public.country_factor) replaces the citizen cut and the tariff — home
  -- 0.25×, ally 0.5×, peace 1×, rival 2×, war 2× — under 0196's cap (never above tariff_rate_max unless the city's own is).
  if public.economy_closed() then
    return least(v_base * public.country_factor(v_stance), greatest(v_base, public.wc_num('tariff_rate_max')));
  end if;
  if v_stance = 'home' then
$h$),
('public.tick_arrivals(timestamptz)', 1,
$h$  -- 0182: A WAITING MERCHANT IS ASKED IN TURN$h$,
$h$  -- 0237 (E4b, §4c): A FLEET WHOSE PORT TIME IS UP runs her queue — the SAIL that waited leaves now (public.port_time_wake;
  -- while the economy is open no fleet has a ready_at, and the partial index holds nothing to find).
  v_fleets := v_fleets + public.port_time_wake(p_now, v_t0 + v_budget);

  -- 0182: A WAITING MERCHANT IS ASKED IN TURN$h$),
('cmd.advance(uuid,timestamptz)', 1,
$h$    v_res := cmd.execute_order(o.id);
$h$,
$h$    -- 0237 (E4b, §4c): a SAIL waits in the queue while her port time runs (fleets.ready_at); public.port_time_wake runs
    -- her when it is up. Nothing is refused, nothing skipped.
    exit when o.verb = 'SAIL' and f.ready_at is not null and f.ready_at > p_now;
    v_res := cmd.execute_order(o.id);
$h$),
('cmd.do_sell(uuid,jsonb)', 1,
$h$  v_wages := public.pay_wages(p_fleet, f.port_id, v_profit - v_tax, null);
$h$,
$h$  v_wages := public.pay_wages(p_fleet, f.port_id, v_profit - v_tax, null);
  -- 0237 (E4b, §4c): the dock fee she could not pay when she made this harbour is taken from this sale, up to its net
  -- (public.port_fee_collect; nothing owed — always, while the economy has never been closed — nothing taken).
  perform public.port_fee_collect(f.player_id, f.port_id, q.total - v_tax - v_wages);
$h$),
('cmd.preview(uuid,text,jsonb)', 1,
$h$  begin
    v_res := case v_parsed->>'verb'
$h$,
$h$  begin
    -- 0237 (E4b, §4c): a SAIL sent in her port time waits in the queue and leaves when she is ready (cmd.advance), so it is
    -- judged as it will run then: her port time is set aside inside this rolled-back block.
    if v_parsed->>'verb' = 'SAIL' then
      update public.fleets set ready_at = null where id = (v_parsed->>'fleet_id')::uuid and ready_at is not null;
    end if;
    v_res := case v_parsed->>'verb'
$h$),
('world.fleets()', 1,
$h$    'queue', cmd.queue(f.id)) order by f.created_at), '[]'::jsonb)
$h$,
$h$    'queue', cmd.queue(f.id))
    -- 0237 (E4b, §4c): her port time while she is in it (`Ready in 0:42`) — absent otherwise, so an open economy reads as before
    || case when f.ready_at > now() then jsonb_build_object('ready_at', f.ready_at) else '{}'::jsonb end
    order by f.created_at), '[]'::jsonb)
$h$),
('world.town_hall(uuid)', 1,
$h$    || public.town_hall_gifts(p_port);
$h$,
$h$    || public.town_hall_gifts(p_port)
    -- 0237 (E4b, §4c): what this harbour asks the signed-in company — her standing, the factor on her tax, the dock fee
    -- (`Tax 2× (rival)`) — served only while the economy is closed.
    || public.port_dues(p_port, v_player, null);
$h$),
('world.good_board(uuid,uuid,uuid,numeric)', 1,
$h$                        order by c.premium_pct desc limit 1))
           order by (p.id is null),
$h$,
$h$                        order by c.premium_pct desc limit 1))
           -- 0237 (E4b, §4c): the dock fee for this parcel there and the country factor on its tax — closed only
           || public.port_dues(r.id, v_player, p.cost)
           order by (p.id is null),
$h$);

create or replace function pg_temp.recut_0237(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := (select def from defs_before_0237 where fn = p_fn);
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0237 where fn = p_fn order by n loop
    v_n := pg_temp.occurs_0237(v_def, h.old);
    if v_n <> 1 then
      raise exception '0237 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0237(fn) from defs_before_0237 order by fn;

-- ── 9. THE PROBE'S TOOLS ────────────────────────────────────────────────────────────────────────
-- What a probe wrote since the mark: flows (port code, kind, ducats; probe flows left out), and her purse, ledger,
-- fleet, orders, events (voyage ids left out: a new voyage is a new id) and debts.
create or replace function pg_temp.seen_0237(p_mark bigint, p_p uuid, p_f uuid)
returns jsonb
language sql
as $$
  select jsonb_build_object(
    'flows', coalesce((select jsonb_agg(jsonb_build_array(p.code, f.kind, f.ducats) order by f.id)
                         from public.treasury_flows f join public.ports p on p.id = f.port_id
                        where f.id > p_mark and f.created_at = now() and f.kind <> 'PROBE_0237'), '[]'::jsonb),
    'purse', (select pl.ducats from public.players pl where pl.id = p_p),
    'ledger', coalesce((select jsonb_agg(jsonb_build_array(l.kind, l.ducats_delta, l.balance_after) order by l.kind, l.ducats_delta, l.balance_after)
                          from public.ledger l where l.player_id = p_p and l.kind <> 'PROBE_0237'), '[]'::jsonb),
    'fleet', (select jsonb_build_array(f.status, p.code, f.ready_at, f.version)
                from public.fleets f left join public.ports p on p.id = f.port_id where f.id = p_f),
    'orders', coalesce((select jsonb_agg(jsonb_build_array(o.verb, o.status, o.error_code) order by o.seq)
                          from public.orders o where o.fleet_id = p_f), '[]'::jsonb),
    'events', coalesce((select jsonb_agg(jsonb_build_array(e.kind, e.payload - 'voyage_id' - 'eta') order by e.created_at, e.kind, e.payload::text)
                          from public.events e where e.player_id = p_p), '[]'::jsonb),
    'debts', coalesce((select jsonb_agg(jsonb_build_array(p.code, d.ducats) order by p.code)
                         from public.port_fee_debts d join public.ports p on p.id = d.port_id where d.player_id = p_p), '[]'::jsonb))
$$;

-- ── 10. THE SELF-ASSERT ─────────────────────────────────────────────────────────────────────────
do $$
declare
  c_uid    constant uuid := '00000000-0237-4000-8000-000000000001';
  v_before record;
  v_d record; v_h record; v_pp record; v_def text;
  v_mark   bigint := (select coalesce(max(f.id), 0) from public.treasury_flows f);
  v_lis    uuid := (select p.id from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR');
  v_fnc    uuid := (select p.id from public.ports p where p.code = 'FNC' and p.kind = 'HARBOUR');
  v_good   uuid; v_gcode text;
  v_p      uuid; v_f uuid; v_voy uuid;
  v_out    jsonb;
  v_a      jsonb; v_b jsonb; v_c jsonb;
  v_stances text[];
  v_n      int;
  v_res    jsonb;
  v_ready  timestamptz;
  v_course jsonb; v_back jsonb;
begin
  select * into v_before from before_0237;

  -- (a) THE RE-CUTS reverse to their pre-images; ACL / volatility / definer / config unmoved
  for v_d in select * from defs_before_0237 loop
    v_def := replace(pg_get_functiondef(v_d.fn::regprocedure), E'\r', '');
    for v_h in select * from hunks_0237 where fn = v_d.fn order by n desc loop
      if pg_temp.occurs_0237(v_def, v_h.new) <> 1 then
        raise exception '0237 self-assert FAIL: hunk % of % is not in the new body exactly once', v_h.n, v_d.fn;
      end if;
      v_def := replace(v_def, v_h.new, v_h.old);
    end loop;
    if v_def <> v_d.def then
      raise exception '0237 self-assert FAIL: % does not reverse to its pre-image', v_d.fn;
    end if;
    select coalesce(p.proacl::text, '') as acl, p.provolatile as vol, p.prosecdef as secdef, coalesce(p.proconfig::text, '') as cfg
      into v_pp from pg_proc p where p.oid = v_d.fn::regprocedure;
    if v_pp.acl <> v_d.acl or v_pp.vol <> v_d.vol or v_pp.secdef <> v_d.secdef or v_pp.cfg <> v_d.cfg then
      raise exception '0237 self-assert FAIL: % changed its ACL, volatility, definer or config', v_d.fn;
    end if;
  end loop;
  if exists (select 1 from (values ('public.country_factor(text)'), ('public.port_fee(uuid,uuid,numeric)'),
                                   ('public.port_call(uuid,uuid,uuid,timestamptz,timestamptz,uuid)'),
                                   ('public.port_fee_collect(uuid,uuid,bigint)'), ('public.port_time_wake(timestamptz,timestamptz,uuid)'),
                                   ('public.preparing_refusal(timestamptz,timestamptz)'), ('public.port_dues(uuid,uuid,numeric)')) f(fn)
              where has_function_privilege('authenticated', f.fn, 'execute') or has_function_privilege('anon', f.fn, 'execute')) then
    raise exception '0237 self-assert FAIL: a client role can execute a server-only function';
  end if;
  if has_table_privilege('authenticated', 'public.port_fee_debts', 'select') or has_table_privilege('anon', 'public.port_fee_debts', 'select') then
    raise exception '0237 self-assert FAIL: a client role can read the debts';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> v_before.entry_points then
    raise exception '0237 self-assert FAIL: the registry moved';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0237 self-assert FAIL: a wall moved';
  end if;
  if exists (select 1 from public.fleets f where f.ready_at is not null) or exists (select 1 from public.port_fee_debts) then
    raise exception '0237 self-assert FAIL: a fleet has a port time or a company owes a fee, dark';
  end if;
  if v_lis is null or v_fnc is null or public.port_nation(v_fnc) is distinct from (select n.id from public.nations n where n.code = 'PRT') then
    raise exception '0237 self-assert FAIL: no Lisbon, or Funchal is not Portuguese';
  end if;

  -- (b) THE COUNTRY FACTOR on the profit tax: every harbour × one probe company of each great power
  begin
    update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'influence_enabled');
    perform public.new_house(null, 'Probe 0237 ' || n.code, n.code, 'LIS', p_ducats => 0)
       from public.great_powers gp join public.nations n on n.id = gp.nation_id;
    -- open: every answer is the pre-image's
    select count(*) into v_n
      from public.ports h join public.players pl on pl.company_name like 'Probe 0237 %'
     where h.kind = 'HARBOUR' and world.tax_rate(h.id, pl.id) is distinct from pg_temp.tax_rate_old_0237(h.id, pl.id);
    if v_n <> 0 then
      raise exception using errcode = 'ZX237', message = jsonb_build_object('fail', 'open', 'n', v_n)::text;
    end if;
    -- closed: least(base × factor, greatest(base, cap)), base = the company-less rate
    update public.world_config set value = 'true'::jsonb where key = 'economy_closed';
    select count(*) into v_n
      from public.ports h join public.players pl on pl.company_name like 'Probe 0237 %'
      cross join lateral (select pg_temp.tax_rate_old_0237(h.id, null) as base,
                                 public.power_stance(pl.nation_id, public.port_nation(h.id)) as st) x
     where h.kind = 'HARBOUR'
       and world.tax_rate(h.id, pl.id) is distinct from
           least(x.base * (public.wc('country_tax_factor') ->> x.st)::numeric, greatest(x.base, public.wc_num('tariff_rate_max')));
    select array_agg(distinct public.power_stance(pl.nation_id, public.port_nation(h.id)) order by public.power_stance(pl.nation_id, public.port_nation(h.id)))
      into v_stances
      from public.ports h join public.players pl on pl.company_name like 'Probe 0237 %' where h.kind = 'HARBOUR';
    raise exception using errcode = 'ZX237', message = jsonb_build_object('n', v_n, 'stances', v_stances)::text;
  exception when sqlstate 'ZX237' then
    v_c := sqlerrm::jsonb;
  end;
  if v_c ? 'fail' or (v_c->>'n')::int <> 0
     or not (v_c->'stances' @> '["home", "ally", "peace", "rival", "war"]'::jsonb) then
    raise exception '0237 self-assert FAIL: the country factor on the profit tax is not least(base × factor, greatest(base, cap)) closed, or not the pre-image open: %', v_c;
  end if;
  v_out := jsonb_build_object('stances', v_c->'stances');

  -- (c)(d) A DUTCH COMPANY MAKES FUNCHAL (at war with its holder): dark byte for byte, then lit
  begin
    update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'influence_enabled');
    update public.world_config set value = '0'::jsonb where key = 'hazard_p_max';   -- a quiet passage: no lottery
    perform set_config('request.jwt.claim.sub', c_uid::text, true);
    v_p := public.new_house(c_uid, 'Huis van de Haven 0237', 'NLD', 'LIS');
    select f.id into v_f from public.fleets f where f.player_id = v_p;
    perform public.credit(v_p, 'PROBE_0237', 1000000);
    select g.id, g.code into v_good, v_gcode from public.goods g join public.ports p on p.id = v_fnc
     where g.bulk = 1 and not public.culture_refuses(p.culture, g.culture_mask) order by g.code limit 1;
    v_n := public.fleet_load(v_f, v_gcode, 40, 25);
    if v_n <> 40 or public.fleet_stock_at_cost(v_f) <> 1000 then
      raise exception '0237 self-assert FAIL: the probe''s 40 t of % at 25 did not load (% loaded, worth %)', v_gcode, v_n, public.fleet_stock_at_cost(v_f);
    end if;
    update public.port_treasury set reserve = 0 where port_id in (v_lis, v_fnc);
    perform public.treasury_post(v_fnc, 'PROBE_0237', 10000000, null, null, true);
    select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon), jsonb_build_array(b.roadstead_lat, b.roadstead_lon)),
           jsonb_build_array(jsonb_build_array(b.roadstead_lat, b.roadstead_lon), jsonb_build_array(a.roadstead_lat, a.roadstead_lon))
      into v_course, v_back
      from public.sea_reaches a, public.sea_reaches b where a.port_id = v_lis and b.port_id = v_fnc;
    v_voy := (cmd.do_sail(v_f, jsonb_build_object('dest', v_fnc, 'path', v_course))->>'voyage_id')::uuid;
    -- she landed 30 s ago (the whole passage moved back by one interval: its days keep their shape)
    update public.voyages vo
       set departed_at = vo.departed_at - (vo.eta - (now() - interval '30 seconds')), eta = now() - interval '30 seconds'
     where vo.id = v_voy;

    -- (c) DARK through the NEW bodies
    begin
      perform voyage.settle(v_f, now());
      v_res := cmd.do_sell(v_f, jsonb_build_object('good', v_good));
      raise exception using errcode = 'ZY237', message = jsonb_build_object('seen', pg_temp.seen_0237(v_mark, v_p, v_f), 'sale', v_res,
        'board_dues', exists (select 1 from jsonb_array_elements(world.good_board(v_good, v_f)->'sell') e where e ? 'dues'),
        'hall_dues', world.town_hall(v_fnc) ? 'dues',
        'fleet_ready', exists (select 1 from jsonb_array_elements(world.fleets()) e where e ? 'ready_at'))::text;
    exception when sqlstate 'ZY237' then
      v_a := sqlerrm::jsonb;
    end;
    -- (c) DARK through the OLD bodies, from the same state
    begin
      perform pg_temp.settle_old_0237(v_f, now());
      v_res := pg_temp.do_sell_old_0237(v_f, jsonb_build_object('good', v_good));
      raise exception using errcode = 'ZY237', message = jsonb_build_object('seen', pg_temp.seen_0237(v_mark, v_p, v_f), 'sale', v_res)::text;
    exception when sqlstate 'ZY237' then
      v_b := sqlerrm::jsonb;
    end;

    -- (d) LIT: the port call, the wait, the debt, the reads, the sale, the wake
    begin
      update public.world_config set value = 'true'::jsonb where key = 'economy_closed';
      insert into public.orders (fleet_id, player_id, seq, raw_text, verb, args)
      values (v_f, v_p, 1, 'SAIL TO LIS', 'SAIL', jsonb_build_object('dest', v_lis, 'path', v_back));
      perform public.credit(v_p, 'PROBE_0237', 10 - (select pl.ducats from public.players pl where pl.id = v_p));
      perform voyage.settle(v_f, now());
      v_c := jsonb_build_object('docked', pg_temp.seen_0237(v_mark, v_p, v_f));
      v_c := v_c || jsonb_build_object('ready_in', round(extract(epoch from ((select f.ready_at from public.fleets f where f.id = v_f) - now()))));
      v_c := v_c || jsonb_build_object('refusal', voyage.sail_refusal(v_f, v_lis, null, 0));
      perform public.credit(v_p, 'PROBE_0237', 100000);   -- her stores for the way home are bought by the SAIL itself
      v_c := v_c || jsonb_build_object('preview_ok', (cmd.preview(v_f, 'SAIL TO LIS', v_back)->>'ok')::boolean);
      v_c := v_c || jsonb_build_object('ready_after_preview', (select f.ready_at is not null from public.fleets f where f.id = v_f));
      v_c := v_c || jsonb_build_object('advance_waits', cmd.advance(v_f, now()));
      v_c := v_c || jsonb_build_object('board', (select jsonb_build_object('dues', e->'dues', 'quoted', e->'quoted')
                                                   from jsonb_array_elements(world.good_board(v_good, v_f)->'sell') e
                                                   join public.ports bp on bp.code = e->>'port'
                                                  where public.port_nation(bp.id) = public.port_nation(v_fnc)
                                                  order by (e->>'quoted')::boolean desc, bp.code limit 1));
      v_c := v_c || jsonb_build_object('board_all', not exists (select 1 from jsonb_array_elements(world.good_board(v_good, v_f)->'sell') e where not e ? 'dues'));
      v_c := v_c || jsonb_build_object('hall', world.town_hall(v_fnc)->'dues');
      v_c := v_c || jsonb_build_object('fleet_ready', exists (select 1 from jsonb_array_elements(world.fleets()) e where e ? 'ready_at'));
      v_c := v_c || jsonb_build_object('wake_early', public.port_time_wake(now(), clock_timestamp() + interval '1 minute', v_f));
      v_res := cmd.do_sell(v_f, jsonb_build_object('good', v_good));
      v_c := v_c || jsonb_build_object('sale', v_res, 'sold', pg_temp.seen_0237(v_mark, v_p, v_f));
      update public.fleets set ready_at = now() - interval '1 second' where id = v_f;   -- her minute has passed
      v_c := v_c || jsonb_build_object('wake', public.port_time_wake(now(), clock_timestamp() + interval '1 minute', v_f),
                                       'woken', pg_temp.seen_0237(v_mark, v_p, v_f));
      raise exception using errcode = 'ZY237', message = v_c::text;
    exception when sqlstate 'ZY237' then
      v_c := sqlerrm::jsonb;
    end;
    raise exception using errcode = 'ZX237', message = jsonb_build_object('a', v_a, 'b', v_b, 'c', v_c)::text;
  exception when sqlstate 'ZX237' then
    v_res := sqlerrm::jsonb;
    v_a := v_res->'a'; v_b := v_res->'b'; v_c := v_res->'c';
  end;

  -- (c) dark: the new bodies are the old ones, byte for byte; nothing new is served
  if v_a is null or v_b is null or v_a->'seen' <> v_b->'seen' or v_a->'sale' <> v_b->'sale'
     or v_a->'seen'->'fleet'->>0 <> 'DOCKED' or v_a->'seen'->'fleet'->>1 <> 'FNC' or v_a->'seen'->'fleet'->2 <> 'null'::jsonb
     or v_a->'seen'->'debts' <> '[]'::jsonb
     or exists (select 1 from jsonb_array_elements(v_a->'seen'->'flows') e where e->>1 = 'PORT_FEE')
     or (v_a->'sale'->>'qty')::numeric <> 40
     or (v_a->>'board_dues')::boolean or (v_a->>'hall_dues')::boolean or (v_a->>'fleet_ready')::boolean then
    raise exception '0237 self-assert FAIL: dark, the docking and the sale are not the pre-image''s byte for byte (or a new key was served): new % old %', v_a, v_b;
  end if;
  v_out := v_out || jsonb_build_object('dark_flows', v_a->'seen'->'flows');

  -- (d) lit
  if (select count(*) from jsonb_array_elements(v_c->'docked'->'flows') e where e->>1 = 'PORT_FEE') <> 1
     or not (v_c->'docked'->'flows' @> '[["FNC", "PORT_FEE", 10]]'::jsonb)
     or not (v_c->'docked'->'ledger' @> '[["PORT_FEE", -10, 0]]'::jsonb)
     or v_c->'docked'->'debts' <> '[["FNC", 100]]'::jsonb
     or v_c->'docked'->'fleet'->>0 <> 'DOCKED' or (v_c->>'ready_in')::int <> 30
     or v_c->'docked'->'orders' <> '[["SAIL", "pending", null]]'::jsonb
     or v_c->'refusal'->>'code' <> 'E_PREPARING' or v_c->'refusal'->'figures' <> '{"have": 30, "need": 60, "unit": "seconds"}'::jsonb
     or not (v_c->>'preview_ok')::boolean or not (v_c->>'ready_after_preview')::boolean or (v_c->>'advance_waits')::int <> 0
     or v_c->'board'->'dues'->>'stance' <> 'war' or (v_c->'board'->'dues'->>'factor')::numeric <> 2
     or (v_c->'board'->'dues'->>'fee')::bigint <> (case when (v_c->'board'->>'quoted')::boolean then 110 else 100 end)
     or not (v_c->>'board_all')::boolean
     or v_c->'hall'->>'stance' <> 'war' or (v_c->'hall'->>'factor')::numeric <> 2 or (v_c->'hall'->>'fee')::bigint <> 100
     or not (v_c->>'fleet_ready')::boolean or (v_c->>'wake_early')::int <> 0 then
    raise exception '0237 self-assert FAIL: lit, the port call (fee 110 at war, 10 paid, 100 owed, 30 s of port time, the SAIL waiting, E_PREPARING 30/60, the preview, the reads) is not right: %', v_c;
  end if;
  if (v_c->'sale'->>'qty')::numeric <> 40
     or not (v_c->'sold'->'flows' @> jsonb_build_array(jsonb_build_array('FNC', 'PORT_FEE', least(100, (v_c->'sale'->>'net')::bigint))))
     or v_c->'sold'->'debts' <> (case when (v_c->'sale'->>'net')::bigint >= 100 then '[]'::jsonb
                                      else jsonb_build_array(jsonb_build_array('FNC', 100 - (v_c->'sale'->>'net')::bigint)) end)
     or (v_c->>'wake')::int <> 1
     or v_c->'woken'->'orders' <> '[["SAIL", "done", null]]'::jsonb
     or v_c->'woken'->'fleet'->>0 <> 'SAILING' or v_c->'woken'->'fleet'->2 <> 'null'::jsonb then
    raise exception '0237 self-assert FAIL: lit, the owed 100 was not taken from the sale, or the wake did not send her once her port time was up: %', v_c;
  end if;

  -- nothing of the probe survives
  if exists (select 1 from public.players p where p.company_name in ('Huis van de Haven 0237') or p.company_name like 'Probe 0237 %')
     or exists (select 1 from public.treasury_flows f where f.id > v_mark and f.created_at = now())
     or exists (select 1 from public.fleets f where f.ready_at is not null) or exists (select 1 from public.port_fee_debts)
     or public.economy_closed() or coalesce(current_setting('request.jwt.claim.sub', true), '') <> '' then
    raise exception '0237 self-assert FAIL: the probe left rows behind';
  end if;

  raise notice '0237 self-assert ok: EVERY PORT CHARGES AND TAKES A MINUTE. Ten bodies re-cut (settle, sail_refusal, tax_rate, tick_arrivals, advance, do_sell, preview, fleets, town_hall, good_board), each reversed, ACL unmoved; seven functions server-only, the debts table no client grant; registry unchanged; walls 0. COUNTRY FACTOR: every harbour × the ten powers, open = the pre-image, closed = least(base × factor, greatest(base, cap)), stances %. DARK: a Dutch company making Funchal and selling 40 t there, new bodies = old bodies byte for byte (flows %), no fee, no port time, no debt, no new key. LIT: fee round((50 + 5) × 2) = 110 at war — 10 paid, 100 owed; 30 s of port time; the queued SAIL waited, E_PREPARING 30/60 s, the preview passed; board and Town Hall served dues (war, 2×); the sale paid %; the wake sent her once her minute was up. Rolled back.',
    v_out->'stances', v_out->'dark_flows', least(100, (v_c->'sale'->>'net')::bigint);
end $$;
