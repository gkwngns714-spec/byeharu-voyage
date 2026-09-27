-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0087 — A PORT ASKS FOR WHAT IT DOES NOT SELL  (the request board: a port posts a request for
--        N units of a good it does not deal in, by a day, and pays a premium over the mid when it
--        is delivered)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER (2026-09-11, docs/OWNER_REQUESTS.md row 76, docs/QUAY_LEDGER.md) ─────────────────
--   Nine screenshots of a trade house whose last screen is the 의뢰 board — a port asks for goods,
--   names a deadline, and pays over the odds when they arrive: "come up with the same design plan,
--   but different and modern than this" — "make this in game" — "do what is best, don't leave
--   anything out". QUAY_LEDGER §1: *"의뢰 교역품 request board — keep, NEW SYSTEM — nothing exists.
--   `trade_contracts` + `world.contracts(p_port)` + `cmd.fulfil` — last slice."* §6 slice 4:
--   *"spawn/expiry on the day tick, premium through `trade_basket`; third segment — done when one
--   contract is fulfilled on production, premium as its own receipt line."*
--
-- ── WHAT SAYS THE OPPOSITE, NAMED ───────────────────────────────────────────────────────────────
--   * Nothing in the chain asks the player for anything. Every price is the port's own bid, and a
--     port that does not deal in a good (0061: not on its roster) pays exactly its bid for it and
--     asks for nothing more. There is no row, no read and no verb by which a port can want a good.
--   * The daily allowance (`world.daily_cap_remaining`, 0005/0027) is an anti-cornering rule over
--     stock_target — correct for a market, and blind to a request the port itself posted. Nothing
--     is changed there; the request is SIZED under it instead (below).
--
-- ── §7B — THE FOUR QUESTIONS ────────────────────────────────────────────────────────────────────
--   1. CONCEPT: a request — a port's posted ask for N units of a good it does not sell, open until
--      a day, paying a premium per unit over the mid it was posted at when the whole lot lands.
--   2. WHERE IT LIVES: the server. `public.trade_contracts` is the board; `public.contract_draw`
--      is THE one draw (what a port asks for on a day — pure in (port, day, seq, world secret),
--      voyage.rng's discipline); `public.tick_contracts` is THE one writer (posts, expires, prunes);
--      `world.contracts` is the read; `cmd.run_fulfil` is the one body of a delivery; `cmd.fulfil`
--      and `cmd.preview_fulfil` are its two skins, exactly as 0083's basket wears its verbs.
--   3. THE SECOND CALLER: the Requests face on PORT › Trade reads the board and the receipt; the
--      MAP is the named next caller of `world.contracts` (a port's requests beside its ring) and
--      needs no second read — the read takes a port and nothing about a fleet.
--   4. WHAT WOULD MAKE IT WRONG, and how anyone finds out: a request for a good the port sells (an
--      instant arbitrage on one quay — buy at the ask, deliver at the bid plus the premium); a
--      premium paid that is not the premium served; a delivery that took the cargo and paid
--      nothing, or paid and took nothing. (b) asserts the draw never names an offered good; (e)
--      asserts the receipt's premium, the ledger's PREMIUM row and the served figure are one
--      number; the savepoint in the skins makes the sale and the premium land together or not at
--      all, and (e) refuses a delivery short of cargo and watches nothing move.
--
-- ── THE RULES, IN PLAIN WORDS (every number is a knob; none is written in a body) ───────────────
--   * A HARBOUR posts `contract_posts_per_day` request(s) each game-day (0005's calendar clock,
--     `world.game_day`). A request stays open `contract_deadline_days` game-days and then expires.
--   * A request asks for a good the port does NOT offer (0061's roster, `public.port_offers`) and
--     that its culture will trade (0080's `public.culture_refuses`). A port never asks for what it
--     sells: that would be bought at the ask and delivered at the bid plus the premium on the same
--     quay, with no voyage in between.
--   * The quantity is a whole number of trade steps (`trade_step_tuns`) between
--     `contract_qty_steps_min` and `contract_qty_steps_max` — and never more than the port's own
--     base daily allowance for that good lets a fresh house sell in one day
--     (`world.daily_cap_remaining` with no house named), so a request is never impossible by
--     construction. The lot must land WHOLE: a fleet carrying less than the request is refused.
--   * The premium is a percentage between `contract_premium_pct_min` and `_max` of the good's mid
--     at the moment of posting, fixed per unit on the row (`premium_per_unit`), so the figure the
--     board shows is the figure the delivery pays. It is paid on top of the ordinary sale, as its
--     OWN ledger movement (`PREMIUM`, event `FULFILLED`) beside the SOLD one.
--   * Which good, how many, and what premium are drawn by `voyage.rng` (0006) over
--     (port, day, seq, world secret) — the same on every replay, so the board is a fact about the
--     world and not about who looked first.
--
-- ── WHO WINDS IT ────────────────────────────────────────────────────────────────────────────────
--   There is no day tick. `world.game_day()` is a pure function of the clock (0005:294) and the
--   five cron jobs 0078 names run the market, the arrivals, the snapshot, the reconcile and the
--   fair calendar — 0078's assert names them and this file adds no sixth. The board is wound the
--   way this chain winds its other calendars (0026/0028/0029: the read IS the catch-up): ONE
--   writer, `public.tick_contracts(port)`, reached by `world.contracts` before it answers and by
--   `cmd.run_fulfil` before it judges. It back-fills every day still inside the deadline window,
--   so a port nobody read for three days shows the requests those three days posted — the draw is
--   pure, so a row materialised late is the same row. It marks the passed ones expired and prunes
--   rows a whole window past their expiry (fulfilled or expired; the ledger keeps the deliveries).
--   Unlike the fair calendar this is not wound on `world.fleets()`: a request is a fact about ONE
--   port, read on that port, and the wind costs one draw per (port, day) — it does not belong on
--   the three-second read every player makes.
--
-- ── THE NEW OBJECTS ─────────────────────────────────────────────────────────────────────────────
--   public.trade_contracts                       the board. RLS on, no policy, no client grant.
--   public.contract_draw(port, day, seq)         THE draw: (good, qty, premium_pct). Server-only.
--   public.tick_contracts(port, now)             THE writer: post, expire, prune. Server-only.
--   world.contracts(port)                        the read: this port's open requests. authenticated.
--   cmd.run_fulfil(fleet, contract)              THE body: the guards, the sale through
--                                                cmd.run_manifest (0083 — the ONE body of a sale at
--                                                a quay, so the daily cap, the culture, the basis
--                                                and the breakdown are the verbs' own), the premium
--                                                through public.credit, the row marked. Raises on
--                                                refusal; returns the receipt. Server-only.
--   cmd.fulfil(fleet, contract, version)         the committing skin (cmd.trade_basket's head:
--                                                ownership, settle, ONE savepoint, the version
--                                                guard under the row lock, E_BUSY). authenticated.
--   cmd.preview_fulfil(fleet, contract)          the dry-run skin (cmd.preview_basket's shape).
--                                                authenticated.
--   six knobs                                    contract_posts_per_day, contract_deadline_days,
--                                                contract_qty_steps_min, contract_qty_steps_max,
--                                                contract_premium_pct_min, contract_premium_pct_max.
--
-- ── THE RECEIPT IS 0083's RECEIPT, PLUS ONE LINE ────────────────────────────────────────────────
--   `cmd.run_fulfil` runs the delivery as a one-line manifest through `cmd.run_manifest`, so the
--   receipt it returns IS the manifest receipt — the sale line with its breakdown, the purse and
--   the hold read back, the trading points — with `kind` = 'fulfil', a `contract` object, and
--   `totals.premium` beside `totals.net`. `net` on a delivery is sold + premium − bought (the
--   receipt's own definition, asserted equal to the purse's movement in (e)); `purse.after` is
--   READ back after the premium lands. The client's one receipt reader (src/lib/rpc/manifest.ts)
--   reads the extra keys and the same totals block prints the premium as its own row.
--
-- ── SUPERSEDE ───────────────────────────────────────────────────────────────────────────────────
-- This file SUPERSEDES the deployed body of `public.client_rpc_entry_points()` (0018, last cut by
-- 0083 — and by 0086 on its own branch, whose hunk anchors on the `reach` row; this one anchors on
-- the `preview_basket` row, so the two apply in either order) by SLICING it: three rows added,
-- asserted in (f) to be the pre-image with exactly those rows. No ACL is re-declared for it.
-- Nothing else deployed is re-cut: `cmd.run_manifest`, `cmd.do_sell`, `public.credit`,
-- `world.daily_cap_remaining` and `voyage.rng` are CALLED, never retyped.
--
-- ── WHAT DOES NOT MOVE ──────────────────────────────────────────────────────────────────────────
--   * The sale itself: what a delivery is paid at the bid is `cmd.do_sell`'s figure through the
--     same stepped quote, under the same daily cap, spending the same bargain. The premium is a
--     separate movement and touches none of it.
--   * Trading XP and fame (0014/0069) read BOUGHT/SOLD; the premium is a PREMIUM row and counts
--     toward neither. Stated, not hidden: the receipt's `trading` block is the sale's.
--   * The grammar. FULFIL is a QUAY verb like the basket and the bargain — client-direct, no
--     `public.orders` row, it exists only where she is docked — and 0083's argument for that shape
--     stands: it carries no words to parse. cmd.parse, cmd.verb_schema, cmd.execute_order and
--     cmd.preview are untouched (0086 re-cuts all four on its branch; nothing here collides).
--   * 0078's clock. No job is scheduled.
--
-- Depends on: 0004 (credit, emit_event, players, fleets), 0005 (game_day, world.price, port_goods,
-- daily_cap_remaining's family), 0006 (voyage.rng), 0008 (cmd.assume_identity, current_player_id),
-- 0036 (ports.kind), 0050 (cmd.refuse, cmd.figures), 0051 (good_rarity), 0061 (port_offers), 0080
-- (culture_refuses), 0083 (cmd.run_manifest, cmd.manifest_refused, client_rpc_entry_points).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ── 0. The slice tool (its own copy, by necessity — tests/duplication.spec.ts:365-380) ─────────
create or replace function pg_temp.recut(p_fn regprocedure, p_drop boolean, variadic p_edits text[])
returns void
language plpgsql
as $$
declare
  v_def text := pg_get_functiondef(p_fn);
  v_i   int := 1;
  v_n   int;
begin
  while v_i < array_length(p_edits, 1) loop
    v_n := (length(v_def) - length(replace(v_def, p_edits[v_i], ''))) / length(p_edits[v_i]);
    if v_n <> 1 then
      raise exception '0087 slice: hunk % of % occurs % time(s) in %, expected exactly 1 — the deployed body is not what this migration was generated against.',
        (v_i + 1) / 2, (array_length(p_edits, 1)) / 2, v_n, p_fn;
    end if;
    v_def := replace(v_def, p_edits[v_i], p_edits[v_i + 1]);
    v_i := v_i + 2;
  end loop;
  if p_drop then
    execute format('drop function %s', p_fn::text);
  end if;
  execute v_def;
end $$;

-- ── 0b. THE PRE-IMAGE, captured before anything is cut ─────────────────────────────────────────
create temporary table defs_before_0087 as
select pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure) as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = 'public.client_rpc_entry_points()'::regprocedure), '') as acl;

-- ── 1. THE KNOBS ───────────────────────────────────────────────────────────────────────────────
insert into public.world_config (key, value, description) values
  ('contract_posts_per_day', to_jsonb(1),
   '0087: how many requests a harbour posts each game-day (world.game_day). Small on purpose: a board is read, not scrolled.'),
  ('contract_deadline_days', to_jsonb(4),
   '0087: how many game-days a request stays open after the day it is posted; the wind back-fills this many days, so at most posts x days requests are open at a port.'),
  ('contract_qty_steps_min', to_jsonb(1),
   '0087: the smallest request, in trade steps (trade_step_tuns each).'),
  ('contract_qty_steps_max', to_jsonb(3),
   '0087: the largest request, in trade steps — and never more than the port''s base daily allowance for the good (world.daily_cap_remaining with no house named) lets a fresh house sell in one day.'),
  ('contract_premium_pct_min', to_jsonb(0.08),
   '0087: the least a request pays over the good''s mid at posting, per unit, as a fraction (0.08 = 8%).'),
  ('contract_premium_pct_max', to_jsonb(0.20),
   '0087: the most a request pays over the good''s mid at posting, per unit, as a fraction.');

-- ── 2. THE BOARD ───────────────────────────────────────────────────────────────────────────────
create table public.trade_contracts (
  id               uuid primary key default gen_random_uuid(),
  port_id          uuid not null references public.ports(id),
  good_id          uuid not null references public.goods(id),
  posted_day       int  not null,
  seq              int  not null check (seq >= 1),
  qty              numeric(12,2) not null check (qty > 0),
  premium_pct      numeric(6,4)  not null check (premium_pct > 0),
  mid_at_post      numeric(12,2) not null check (mid_at_post > 0),
  premium_per_unit numeric(12,2) not null check (premium_per_unit > 0),
  premium_ducats   bigint not null check (premium_ducats > 0),
  expires_day      int  not null,
  status           text not null default 'open' check (status in ('open', 'fulfilled', 'expired')),
  fulfilled_by     uuid references public.players(id),
  fulfilled_fleet  uuid references public.fleets(id),
  fulfilled_at     timestamptz,
  created_at       timestamptz not null default now(),
  constraint trade_contracts_one_per_day_seq unique (port_id, posted_day, seq),
  constraint trade_contracts_expires_after_post check (expires_day > posted_day),
  constraint trade_contracts_fulfilled_is_whole check (
    (status = 'fulfilled') = (fulfilled_by is not null and fulfilled_fleet is not null and fulfilled_at is not null))
);
comment on table public.trade_contracts is
  '0087: THE REQUEST BOARD. One row per request a harbour posted — a good it does not sell, a whole '
  'lot, a premium per unit fixed at posting, a day it expires. Written by public.tick_contracts '
  'only (post / expire / prune) and by cmd.run_fulfil (mark fulfilled). Unreadable by any client '
  'role: world.contracts is the door.';
create index trade_contracts_port_open on public.trade_contracts (port_id, status, expires_day);
alter table public.trade_contracts enable row level security;
revoke all on table public.trade_contracts from public, anon, authenticated;

-- ── 3. THE ONE DRAW ────────────────────────────────────────────────────────────────────────────
-- Pure in (port, day, seq, world secret): three voyage.rng streams pick the good, the size and the
-- premium. The candidates are goods the port does NOT offer (0061), its culture will trade (0080)
-- and its base daily allowance lets a fresh house sell at least the smallest request of in one
-- day — ordered by code, so the same u picks the same good on every replay. Nothing about the
-- clock, nothing about a player.
create function public.contract_draw(p_port uuid, p_day int, p_seq int)
returns table (good_id uuid, qty numeric, premium_pct numeric)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_step   numeric := public.wc_num('trade_step_tuns');
  v_min    int     := public.wc_int('contract_qty_steps_min');
  v_max    int     := public.wc_int('contract_qty_steps_max');
  v_pmin   numeric := public.wc_num('contract_premium_pct_min');
  v_pmax   numeric := public.wc_num('contract_premium_pct_max');
  v_good   uuid;
  v_cap    numeric;
  v_steps  int;
  v_u      numeric;
begin
  -- The good: one draw picks an index into the ordered candidate list. No temporary table — a
  -- STABLE function may not create one, and the candidates are one query.
  v_u := voyage.rng(p_port, p_day, 'contract:' || p_seq::text || ':good');
  with cand as (
    select row_number() over (order by g.code) - 1 as i, count(*) over () as n, g.id as gid, c.cap as cap
      from public.goods g
      join public.ports p on p.id = p_port
     cross join lateral (select world.daily_cap_remaining(null::uuid, p_port, g.id) as cap) c
     where not public.port_offers(p_port, g.id)
       and not public.culture_refuses(p.culture, g.culture_mask)
       and c.cap >= v_step * v_min)
  select cand.gid, cand.cap into v_good, v_cap
    from cand
   where cand.i = least(cand.n - 1, floor(v_u * cand.n)::int);
  if v_good is null then
    return;   -- a port with no candidate posts nothing
  end if;

  v_u     := voyage.rng(p_port, p_day, 'contract:' || p_seq::text || ':qty');
  v_steps := least(v_max, v_min + floor(v_u * (v_max - v_min + 1))::int);
  -- and never more than the port's own base allowance lets a fresh house sell in a day
  v_steps := least(v_steps, floor(v_cap / v_step)::int);

  v_u := voyage.rng(p_port, p_day, 'contract:' || p_seq::text || ':premium');

  good_id     := v_good;
  qty         := v_steps * v_step;
  premium_pct := round(v_pmin + v_u * (v_pmax - v_pmin), 2);
  return next;
end $$;
comment on function public.contract_draw(uuid, int, int) is
  '0087: THE one draw — what a harbour asks for on a day: (good, qty, premium_pct), pure in '
  '(port, day, seq, world secret) through voyage.rng. Candidates: goods the port does not offer '
  '(public.port_offers), its culture trades (public.culture_refuses), and whose base daily '
  'allowance (world.daily_cap_remaining, no house) covers the smallest request. Returns no row '
  'when a port has no candidate.';
revoke all on function public.contract_draw(uuid, int, int) from public, anon, authenticated;

-- ── 4. THE ONE WRITER ──────────────────────────────────────────────────────────────────────────
create function public.tick_contracts(p_port uuid, p_now timestamptz default now())
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_day      int := world.game_day(p_now);
  v_deadline int := public.wc_int('contract_deadline_days');
  v_posts    int := public.wc_int('contract_posts_per_day');
  v_kind     text;
  v_d        int;
  v_s        int;
  v_draw     record;
  v_mid      numeric;
  v_per_unit numeric;
  v_posted   int := 0;
begin
  select kind into v_kind from public.ports where id = p_port;
  if v_kind is distinct from 'HARBOUR' then
    return 0;   -- open water keeps no board (0036); an unknown port has none either.
  end if;

  -- EXPIRE what has passed, then PRUNE what is a whole window past its expiry — fulfilled or
  -- expired; the ledger's FULFILLED events keep the deliveries.
  update public.trade_contracts
     set status = 'expired'
   where port_id = p_port and status = 'open' and expires_day <= v_day;
  delete from public.trade_contracts
   where port_id = p_port and status <> 'open' and expires_day < v_day - v_deadline;

  -- POST today and back-fill the window: a request a port posted three days ago is still open
  -- today whether or not anyone read that port since. The draw is pure, so a late row is the
  -- same row; the unique key makes a second wind a no-op.
  for v_d in (v_day - v_deadline + 1) .. v_day loop
    for v_s in 1 .. v_posts loop
      if exists (select 1 from public.trade_contracts where port_id = p_port and posted_day = v_d and seq = v_s) then
        continue;
      end if;
      select * into v_draw from public.contract_draw(p_port, v_d, v_s);
      if v_draw.good_id is null then
        continue;
      end if;
      -- The mid is struck to the ducat-cent ONCE, here: the row keeps that figure, and the premium is
      -- computed from it, so what the row states and what the rule recomputes are the same number.
      select round(q.mid, 2) into v_mid from world.price(p_port, v_draw.good_id) q;
      v_per_unit := round(v_mid * v_draw.premium_pct, 2);
      insert into public.trade_contracts
        (port_id, good_id, posted_day, seq, qty, premium_pct, mid_at_post, premium_per_unit, premium_ducats, expires_day,
         status)
      values
        (p_port, v_draw.good_id, v_d, v_s, v_draw.qty, v_draw.premium_pct, v_mid, v_per_unit,
         round(v_per_unit * v_draw.qty)::bigint, v_d + v_deadline,
         case when v_d + v_deadline <= v_day then 'expired' else 'open' end)
      on conflict (port_id, posted_day, seq) do nothing;
      if found then v_posted := v_posted + 1; end if;
    end loop;
  end loop;
  return v_posted;
end $$;
comment on function public.tick_contracts(uuid, timestamptz) is
  '0087: THE one writer of the request board, for one harbour: marks passed requests expired, '
  'prunes rows a whole window past their expiry, and posts the requests of every day still inside '
  'the deadline window that are not on the board yet (public.contract_draw, world.price for the '
  'mid at posting). Idempotent by the unique (port, day, seq) key. Reached by world.contracts and '
  'cmd.run_fulfil — the read is the catch-up (0009/0026/0028); no cron job (0078 names five and '
  'this file adds no sixth). Returns how many rows it posted.';
revoke all on function public.tick_contracts(uuid, timestamptz) from public, anon, authenticated;

-- ── 5. THE READ ────────────────────────────────────────────────────────────────────────────────
create function world.contracts(p_port uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare
  v_day int;
begin
  -- 0087 WIND: the read is the catch-up. ONE writer (public.tick_contracts); this is a caller.
  perform public.tick_contracts(p_port, now());
  v_day := world.game_day();
  return jsonb_build_object(
    'port', (select p.code from public.ports p where p.id = p_port),
    'game_day', v_day,
    'deadline_days', public.wc_int('contract_deadline_days'),
    'contracts', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', c.id,
        'good', g.code, 'name', g.name, 'category', g.category,
        'rarity', public.good_rarity(g.id),
        'bulk', g.bulk,
        'qty', c.qty,
        'premium_pct', c.premium_pct,
        'premium_per_unit', c.premium_per_unit,
        'premium_ducats', c.premium_ducats,
        'mid_at_post', c.mid_at_post,
        'posted_day', c.posted_day,
        'expires_day', c.expires_day,
        'days_left', c.expires_day - v_day,
        -- the instant it closes: the first second of expires_day on the calendar clock (0005),
        -- so a screen prints "ends in 2 h" the way the fair row does and never a count of "days"
        -- the voyage clock would be read on (0028)
        'expires_at', to_timestamp(c.expires_day * public.wc_num('game_day_seconds'))) order by c.expires_day, g.code), '[]'::jsonb)
        from public.trade_contracts c
        join public.goods g on g.id = c.good_id
       where c.port_id = p_port and c.status = 'open'));
end $$;
comment on function world.contracts(uuid) is
  '0087: THE REQUEST BOARD of one harbour — its open requests: the good (code, name, category, '
  'rarity, bulk), the whole lot asked for, the premium as a fraction and per unit and for the lot, '
  'the mid it was posted at, the day it expires, the game-days left and the instant it closes. Winds '
  'public.tick_contracts first (the read is the catch-up). Takes no fleet: what a fleet carries is '
  'on world.fleets, and the client folds it once.';
revoke all on function world.contracts(uuid) from public, anon;
grant execute on function world.contracts(uuid) to authenticated;

-- ── 6. THE ONE BODY OF A DELIVERY ──────────────────────────────────────────────────────────────
create function cmd.run_fulfil(p_fleet uuid, p_contract uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  f        public.fleets%rowtype;
  c        public.trade_contracts%rowtype;
  g        public.goods%rowtype;
  v_port   public.ports%rowtype;
  v_have   numeric;
  v_rcpt   jsonb;
  v_purse  bigint;
  v_event  uuid;
begin
  select * into f from public.fleets where id = p_fleet;
  if f.status <> 'DOCKED' then
    perform cmd.refuse('E_NOT_DOCKED', format('%s is %s and a request is delivered in port', f.name, f.status));
  end if;
  -- The board is current before it is judged (the same wind the read makes).
  perform public.tick_contracts(f.port_id, now());

  select * into c from public.trade_contracts where id = p_contract for update;
  if c.id is null then
    perform cmd.refuse('E_NO_SUCH_CONTRACT', 'there is no such request');
  end if;
  select * into v_port from public.ports where id = c.port_id;
  select * into g from public.goods where id = c.good_id;
  if c.port_id <> f.port_id then
    perform cmd.refuse('E_CONTRACT_ELSEWHERE', format('%s asked for the %s, and %s is docked at %s', v_port.name, g.name, f.name,
      (select p2.name from public.ports p2 where p2.id = f.port_id)));
  end if;
  if c.status = 'fulfilled' then
    perform cmd.refuse('E_CONTRACT_DONE', format('%s''s request for %s has already been delivered', v_port.name, g.name));
  end if;
  if c.status = 'expired' then
    perform cmd.refuse('E_CONTRACT_EXPIRED', format('%s''s request for %s has expired', v_port.name, g.name));
  end if;

  -- THE WHOLE LOT, OR NOTHING. The two figures ride in DETAIL (0050) so the tray draws the bar.
  v_have := public.fleet_cargo_qty(p_fleet, g.code);
  if v_have < c.qty then
    perform cmd.refuse('E_CONTRACT_SHORT',
      format('%s carries too little %s for this request', f.name, g.name),
      cmd.figures(v_have, c.qty, 'units'));
  end if;

  -- THE SALE, through the ONE body of a sale at a quay (0083): the bid, the daily cap, the
  -- culture, the bargain being spent, the cost basis and the breakdown are all the verbs' own.
  v_rcpt := cmd.run_manifest(p_fleet, jsonb_build_array(
              jsonb_build_object('side', 'sell', 'good', g.code, 'qty', c.qty)));

  -- THE PREMIUM, its own movement: the figure the board served, to the ducat.
  v_event := public.emit_event(f.player_id, 'FULFILLED', jsonb_build_object(
               'fleet', f.name, 'port', v_port.code, 'good', g.name, 'qty', c.qty,
               'premium', c.premium_ducats, 'premium_pct', c.premium_pct,
               'sold_total', v_rcpt->'lines'->0->'total', 'contract', c.id));
  perform public.credit(f.player_id, 'PREMIUM', c.premium_ducats, v_event);

  update public.trade_contracts
     set status = 'fulfilled', fulfilled_by = f.player_id, fulfilled_fleet = p_fleet, fulfilled_at = now()
   where id = c.id;

  -- THE RECEIPT: 0083's, with the premium on it. `purse.after` is READ after the premium landed;
  -- `net` on a delivery is sold + premium − bought.
  select ducats into v_purse from public.players where id = f.player_id;
  return v_rcpt
    || jsonb_build_object(
         'kind', 'fulfil',
         'contract', jsonb_build_object(
           'id', c.id, 'good', g.code, 'name', g.name, 'qty', c.qty,
           'premium_pct', c.premium_pct, 'premium_per_unit', c.premium_per_unit,
           'premium', c.premium_ducats, 'expires_day', c.expires_day),
         'totals', (v_rcpt->'totals') || jsonb_build_object(
           'premium', c.premium_ducats,
           'net', (v_rcpt->'totals'->>'net')::bigint + c.premium_ducats),
         'purse', jsonb_build_object('before', v_rcpt->'purse'->'before', 'after', v_purse));
end $$;
comment on function cmd.run_fulfil(uuid, uuid) is
  '0087: THE one body of a delivery. Guards (docked here; the request exists, is this port''s, is '
  'open, is not done; she carries the whole lot — E_CONTRACT_SHORT with have/need in units), then '
  'the sale as a one-line manifest through cmd.run_manifest (0083), then the premium through '
  'public.credit as its own PREMIUM movement on a FULFILLED event, then the row marked. Raises on '
  'any refusal; the skins hold the savepoint. Returns 0083''s receipt with kind = fulfil, a '
  'contract object, totals.premium and net = sold + premium - bought, purse.after read back. '
  'Server-only: it checks no ownership, exactly as run_manifest does not.';
revoke all on function cmd.run_fulfil(uuid, uuid) from public, anon, authenticated;

-- ── 7. THE COMMITTING SKIN — cmd.trade_basket's head (0083 §5), mirrored ───────────────────────
create function cmd.fulfil(p_fleet uuid, p_contract uuid, p_expected_version int default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_player uuid := public.current_player_id();
  f        public.fleets%rowtype;
  v_out    jsonb;
  v_det    text;
  v_hint   text;
  v_state  text;
  v_now    int;
begin
  select * into f from public.fleets where id = p_fleet;
  if f.id is null or v_player is null or f.player_id <> v_player then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_SUCH_FLEET',
                              'error_message', 'That fleet is not yours.', 'fixes', '[]'::jsonb);
  end if;
  perform voyage.settle(p_fleet);
  begin
    update public.fleets set version = version + 1
     where id = p_fleet and (p_expected_version is null or version = p_expected_version);
    if not found then
      select version into v_now from public.fleets where id = p_fleet;
      return jsonb_build_object('ok', false, 'error_code', 'E_STALE',
        'error_message', format('This fleet has moved on since you looked (you have version %s, it is at %s).',
                                p_expected_version, v_now),
        'fixes', cmd.fixes('E_STALE', p_fleet), 'version', v_now);
    end if;
    v_out := cmd.run_fulfil(p_fleet, p_contract);
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_det = pg_exception_detail, v_hint = pg_exception_hint;
    -- 0083's one envelope; a delivery has no input line to name.
    return (cmd.manifest_refused(p_fleet, v_state, sqlerrm, v_det, v_hint) - 'line')
        || jsonb_build_object('version', (select version from public.fleets where id = p_fleet));
  end;
  return v_out || jsonb_build_object('version', (select version from public.fleets where id = p_fleet));
end $$;
comment on function cmd.fulfil(uuid, uuid, int) is
  '0087: a delivery, committed. cmd.trade_basket''s head (ownership -> E_NO_SUCH_FLEET, settle) '
  'and ONE savepoint in which the version is checked-and-bumped under the fleet row''s lock '
  '(E_STALE) and cmd.run_fulfil runs, so the sale and the premium land together or not at all and '
  'a double-tap delivers once. Returns the receipt with `version`, or the 0050 refusal envelope, '
  'or E_BUSY on a lock collision. Writes no public.orders row: the record is the ledger''s SOLD '
  'and PREMIUM rows.';
revoke all on function cmd.fulfil(uuid, uuid, int) from public, anon;
grant execute on function cmd.fulfil(uuid, uuid, int) to authenticated;

-- ── 8. THE DRY-RUN SKIN — cmd.preview_basket's shape (0083 §6) ─────────────────────────────────
create function cmd.preview_fulfil(p_fleet uuid, p_contract uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare
  v_player uuid := public.current_player_id();
  f        public.fleets%rowtype;
  v_out    jsonb;
  v_det    text;
  v_hint   text;
  v_state  text;
begin
  select * into f from public.fleets where id = p_fleet;
  if f.id is null or v_player is null or f.player_id is distinct from v_player then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_SUCH_FLEET',
                              'error_message', 'That fleet is not yours.', 'fixes', '[]'::jsonb);
  end if;
  begin
    v_out := jsonb_build_object('ok', true, 'estimate', cmd.run_fulfil(p_fleet, p_contract));
    raise exception '__PREVIEW_ROLLBACK__' using errcode = 'P0001';
  exception when others then
    if sqlerrm = '__PREVIEW_ROLLBACK__' then
      return v_out;
    end if;
    get stacked diagnostics v_state = returned_sqlstate, v_det = pg_exception_detail, v_hint = pg_exception_hint;
    return cmd.manifest_refused(p_fleet, v_state, sqlerrm, v_det, v_hint) - 'line';
  end;
end $$;
comment on function cmd.preview_fulfil(uuid, uuid) is
  '0087: the delivery''s dry run — cmd.run_fulfil inside a subtransaction that is always rolled '
  'back (cmd.preview''s pattern). What it reports is what cmd.fulfil would do, because it is what '
  'it just did. VOLATILE on purpose. No settle, no version.';
revoke all on function cmd.preview_fulfil(uuid, uuid) from public, anon;
grant execute on function cmd.preview_fulfil(uuid, uuid) to authenticated;

-- ── 9. THE CATALOGUE — three rows, sliced in after the basket's (0086's hunk is on `reach`) ────
select pg_temp.recut('public.client_rpc_entry_points()'::regprocedure, false,
  $c0$      ('cmd',         'preview_basket',      'uuid, jsonb')
    ) as t(s, f, a)$c0$,
  $c1$      ('cmd',         'preview_basket',      'uuid, jsonb'),
      -- 0087: the request board — one harbour's open requests, and a delivery with its dry run.
      ('world',       'contracts',           'uuid'),
      ('cmd',         'fulfil',              'uuid, uuid, int'),
      ('cmd',         'preview_fulfil',      'uuid, uuid')
    ) as t(s, f, a)$c1$);

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  c_probe     constant uuid := '00000000-0087-4000-8000-000000000087';
  v_day       int := world.game_day();
  v_deadline  int := public.wc_int('contract_deadline_days');
  v_posts     int := public.wc_int('contract_posts_per_day');
  v_step      numeric := public.wc_num('trade_step_tuns');
  v_smin      int := public.wc_int('contract_qty_steps_min');
  v_smax      int := public.wc_int('contract_qty_steps_max');
  v_pmin      numeric := public.wc_num('contract_premium_pct_min');
  v_pmax      numeric := public.wc_num('contract_premium_pct_max');
  v_lis       uuid;
  v_rows0     int;
  v_n         int;
  v_bad       int;
  v_wound1    int;
  v_wound2    int;
  v_digest1   text;
  v_digest2   text;
  v_again     int;
  v_r         record;
  v_draw      record;
  v_planted   uuid;
  v_pruned    uuid;
  v_board     jsonb;
  v_player    uuid;
  v_fleet     uuid;
  v_version   int;
  v_c         public.trade_contracts%rowtype;
  v_g         public.goods%rowtype;
  v_free      numeric;
  v_loaded    numeric;
  v_purse0    bigint;
  v_purse1    bigint;
  v_events0   bigint;
  v_ledger0   bigint;
  v_cargo0    numeric;
  v_pv        jsonb;
  v_res       jsonb;
  v_refused   jsonb;
  v_prem_row  bigint;
  v_ev        jsonb;
  v_served    bigint;
  v_def       text;
  v_fn        text;
  v_cap       numeric;
  -- findings from inside the rolled-back probe
  f_short_bit      boolean := false;
  f_short_moved    boolean := true;
  f_preview_dry    boolean := false;
  f_preview_prem   boolean := false;
  f_landed         boolean := false;
  f_purse_is_net   boolean := false;
  f_premium_row    boolean := false;
  f_event          boolean := false;
  f_row_marked     boolean := false;
  f_cargo_gone     boolean := false;
  f_trading        boolean := false;
  f_version        boolean := false;
  f_stale          boolean := false;
  f_done           boolean := false;
  f_expired        boolean := false;
  f_elsewhere      boolean := false;
  f_no_such        boolean := false;
  f_board_hides    boolean := false;
  v_short_have     numeric;
  v_short_need     numeric;
  v_sold           bigint;
  v_premium        bigint;
  v_net            bigint;
  v_qty            numeric;
  v_code           text;
begin
  -- (a) THE OBJECTS AND THE KNOBS.
  if to_regprocedure('public.contract_draw(uuid, int, int)') is null
     or to_regprocedure('public.tick_contracts(uuid, timestamptz)') is null
     or to_regprocedure('world.contracts(uuid)') is null
     or to_regprocedure('cmd.run_fulfil(uuid, uuid)') is null
     or to_regprocedure('cmd.fulfil(uuid, uuid, int)') is null
     or to_regprocedure('cmd.preview_fulfil(uuid, uuid)') is null
     or to_regclass('public.trade_contracts') is null then
    raise exception '0087 self-assert FAIL: an object this file declares is missing';
  end if;
  if v_posts < 1 or v_deadline < 1 or v_smin < 1 or v_smax < v_smin or v_pmin <= 0 or v_pmax < v_pmin then
    raise exception '0087 self-assert FAIL: the knobs are not a board — posts %, deadline %, steps % .. %, premium % .. %',
      v_posts, v_deadline, v_smin, v_smax, v_pmin, v_pmax;
  end if;

  select id into v_lis from public.ports where code = 'LIS';
  if v_lis is null then
    raise exception '0087 self-assert FAIL: there is no LIS to post a request at';
  end if;
  select count(*) into v_rows0 from public.trade_contracts;

  -- (b) THE BOARD IS PURE, AND NEVER ASKS FOR WHAT THE PORT SELLS. Wind LIS: exactly the window's
  --     worth of rows appear; a second wind moves no row and re-mints no id; every row is the one
  --     draw recomputed; no row names an offered or refused good; every figure is the rule.
  v_wound1 := public.tick_contracts(v_lis, now());
  select count(*), md5(coalesce(string_agg(id::text, ',' order by id), ''))
    into v_n, v_digest1 from public.trade_contracts where port_id = v_lis;
  if v_wound1 <> v_deadline * v_posts or v_n <> v_deadline * v_posts then
    raise exception '0087 self-assert FAIL: the first wind of LIS posted % row(s) and the board holds %, expected % (deadline % x posts %)',
      v_wound1, v_n, v_deadline * v_posts, v_deadline, v_posts;
  end if;
  v_again := public.tick_contracts(v_lis, now());
  select count(*), md5(coalesce(string_agg(id::text, ',' order by id), ''))
    into v_wound2, v_digest2 from public.trade_contracts where port_id = v_lis;
  if v_again <> 0 or v_wound2 <> v_n or v_digest2 <> v_digest1 then
    raise exception '0087 self-assert FAIL: a second wind of LIS posted % more, the board went % -> % rows and the ids digested % against % — the wind is not idempotent',
      v_again, v_n, v_wound2, v_digest2, v_digest1;
  end if;
  select count(*) into v_bad from public.trade_contracts c
   where c.port_id = v_lis
     and (public.port_offers(c.port_id, c.good_id)
          or public.culture_refuses((select p.culture from public.ports p where p.id = c.port_id),
                                    (select g.culture_mask from public.goods g where g.id = c.good_id)));
  if v_bad <> 0 then
    raise exception '0087 self-assert FAIL: % request(s) at LIS ask for a good the port offers or its culture refuses', v_bad;
  end if;
  for v_r in select * from public.trade_contracts where port_id = v_lis loop
    select * into v_draw from public.contract_draw(v_r.port_id, v_r.posted_day, v_r.seq);
    if v_draw.good_id is distinct from v_r.good_id or v_draw.qty is distinct from v_r.qty
       or v_draw.premium_pct is distinct from v_r.premium_pct then
      raise exception '0087 self-assert FAIL: the row for (LIS, day %, seq %) is (%, %, %) but the one draw says (%, %, %)',
        v_r.posted_day, v_r.seq, v_r.good_id, v_r.qty, v_r.premium_pct, v_draw.good_id, v_draw.qty, v_draw.premium_pct;
    end if;
    if v_r.qty < v_smin * v_step or v_r.qty > v_smax * v_step or v_r.qty <> floor(v_r.qty / v_step) * v_step
       or v_r.qty > world.daily_cap_remaining(null::uuid, v_r.port_id, v_r.good_id) then
      raise exception '0087 self-assert FAIL: a request for % units is not a whole number of % steps between % and %, or exceeds the port''s base allowance %',
        v_r.qty, v_step, v_smin * v_step, v_smax * v_step, world.daily_cap_remaining(null::uuid, v_r.port_id, v_r.good_id);
    end if;
    if v_r.premium_pct < v_pmin or v_r.premium_pct > v_pmax then
      raise exception '0087 self-assert FAIL: a premium of % is outside % .. %', v_r.premium_pct, v_pmin, v_pmax;
    end if;
    if v_r.premium_per_unit <> round(v_r.mid_at_post * v_r.premium_pct, 2)
       or v_r.premium_ducats <> round(v_r.premium_per_unit * v_r.qty)::bigint
       or v_r.expires_day <> v_r.posted_day + v_deadline
       or v_r.posted_day < v_day - v_deadline + 1 or v_r.posted_day > v_day
       or v_r.status <> 'open' then
      raise exception '0087 self-assert FAIL: a row''s figures are not the rule — per unit % of mid % at %, lot %, expires % from %, status %',
        v_r.premium_per_unit, v_r.mid_at_post, v_r.premium_pct, v_r.premium_ducats, v_r.expires_day, v_r.posted_day, v_r.status;
    end if;
  end loop;

  -- (c) EXPIRY AND PRUNING, on rows planted outside the window: one expiring today is marked and
  --     leaves the read; one a whole window past its expiry is pruned.
  insert into public.trade_contracts (port_id, good_id, posted_day, seq, qty, premium_pct, mid_at_post, premium_per_unit, premium_ducats, expires_day)
  select v_lis, c.good_id, v_day - v_deadline, 1, c.qty, c.premium_pct, c.mid_at_post, c.premium_per_unit, c.premium_ducats, v_day
    from public.trade_contracts c where c.port_id = v_lis order by c.posted_day, c.seq limit 1
  returning id into v_planted;
  insert into public.trade_contracts (port_id, good_id, posted_day, seq, qty, premium_pct, mid_at_post, premium_per_unit, premium_ducats, expires_day)
  select v_lis, c.good_id, v_day - 3 * v_deadline, 1, c.qty, c.premium_pct, c.mid_at_post, c.premium_per_unit, c.premium_ducats, v_day - 2 * v_deadline
    from public.trade_contracts c where c.port_id = v_lis order by c.posted_day, c.seq limit 1
  returning id into v_pruned;
  v_board := world.contracts(v_lis);
  if (select status from public.trade_contracts where id = v_planted) is distinct from 'expired' then
    raise exception '0087 self-assert FAIL: a request expiring today reads % after the wind, expected expired',
      (select status from public.trade_contracts where id = v_planted);
  end if;
  if exists (select 1 from public.trade_contracts where id = v_pruned) then
    raise exception '0087 self-assert FAIL: a request a whole window past its expiry was not pruned';
  end if;
  if exists (select 1 from jsonb_array_elements(v_board->'contracts') e where e->>'id' = v_planted::text) then
    raise exception '0087 self-assert FAIL: world.contracts still serves the expired request';
  end if;
  delete from public.trade_contracts where id = v_planted;

  -- (d) THE READ serves every open row with every field, in order, with days_left = expires − today.
  if v_board->>'port' is distinct from 'LIS' or (v_board->>'game_day')::int <> v_day
     or (v_board->>'deadline_days')::int <> v_deadline
     or jsonb_array_length(v_board->'contracts') <> v_n then
    raise exception '0087 self-assert FAIL: world.contracts(LIS) serves % request(s) on day %, expected % on day %: %',
      jsonb_array_length(v_board->'contracts'), v_board->>'game_day', v_n, v_day, v_board;
  end if;
  select count(*) into v_bad
    from jsonb_array_elements(v_board->'contracts') e
    join public.trade_contracts c on c.id = (e->>'id')::uuid
    join public.goods g on g.id = c.good_id
   where e->>'good' is distinct from g.code or e->>'name' is distinct from g.name
      or (e->>'qty')::numeric is distinct from c.qty
      or (e->>'premium_pct')::numeric is distinct from c.premium_pct
      or (e->>'premium_per_unit')::numeric is distinct from c.premium_per_unit
      or (e->>'premium_ducats')::bigint is distinct from c.premium_ducats
      or (e->>'mid_at_post')::numeric is distinct from c.mid_at_post
      or (e->>'expires_day')::int is distinct from c.expires_day
      or (e->>'days_left')::int is distinct from c.expires_day - v_day
      or (e->>'days_left')::int < 1
      or (e->>'expires_at')::timestamptz is distinct from to_timestamp(c.expires_day * public.wc_num('game_day_seconds'))
      or (e->>'expires_at')::timestamptz <= now()
      or e->>'rarity' is distinct from public.good_rarity(g.id)
      or (e->>'bulk')::numeric is distinct from g.bulk;
  if v_bad <> 0 then
    raise exception '0087 self-assert FAIL: % served request(s) disagree with their rows: %', v_bad, v_board->'contracts';
  end if;

  -- ── THE WORKED EXAMPLE, ON A REAL HOUSE, THROWN AWAY AFTERWARDS ──────────────────────────────
  begin
    -- The precondition this probe owns: the sale inside a delivery is do_sell's, under the daily
    -- allowance, and the request was sized under the port's BASE allowance — this house's own
    -- allowance is that same figure at skill 0, so nothing is moved here. What IS set is the hold:
    -- a fresh Barca has ~55 tons of room and the largest request is steps x step x bulk; the
    -- example picks the request that takes the least room and demands it fits.
    v_player := public.new_house(c_probe, 'Casa dos Pedidos', 'PRT');
    select id, version into v_fleet, v_version from public.fleets where player_id = v_player;
    perform cmd.assume_identity(c_probe);

    select c.* into v_c
      from public.trade_contracts c join public.goods g on g.id = c.good_id
     where c.port_id = v_lis and c.status = 'open'
     order by c.qty * g.bulk, c.posted_day, c.seq
     limit 1;
    select * into v_g from public.goods where id = v_c.good_id;
    v_free := public.fleet_free_hold(v_fleet);
    if v_c.qty * v_g.bulk > v_free then
      raise exception '0087 self-assert FAIL: the smallest request at LIS, % units of % at bulk %, does not fit a fresh hold of % tons',
        v_c.qty, v_g.code, v_g.bulk, v_free;
    end if;
    v_cap := world.daily_cap_remaining(v_player, v_lis, v_g.id);
    if v_cap < v_c.qty then
      raise exception '0087 self-assert FAIL: the request asks % units of % and a fresh house may sell only % here today — the draw was not sized under the allowance',
        v_c.qty, v_g.code, v_cap;
    end if;

    -- (e1) TOO LITTLE CARGO IS REFUSED, WITH THE TWO FIGURES, AND NOTHING MOVES. One unit short.
    v_loaded := public.fleet_load(v_fleet, v_g.code, v_c.qty - 1);
    if v_loaded <> v_c.qty - 1 then
      raise exception '0087 self-assert FAIL: fleet_load put % of % units aboard', v_loaded, v_c.qty - 1;
    end if;
    select ducats into v_purse0 from public.players where id = v_player;
    select count(*) into v_events0 from public.events where player_id = v_player;
    v_refused := cmd.fulfil(v_fleet, v_c.id, v_version);
    f_short_bit := (coalesce((v_refused->>'ok')::boolean, true) = false
                    and v_refused->>'error_code' = 'E_CONTRACT_SHORT'
                    and v_refused->'figures'->>'unit' = 'units'
                    and (v_refused->'figures'->>'have')::numeric = v_c.qty - 1
                    and (v_refused->'figures'->>'need')::numeric = v_c.qty);
    v_short_have := (v_refused->'figures'->>'have')::numeric;
    v_short_need := (v_refused->'figures'->>'need')::numeric;
    f_short_moved := not ((select ducats from public.players where id = v_player) = v_purse0
                          and public.fleet_cargo_qty(v_fleet, v_g.code) = v_c.qty - 1
                          and (select count(*) from public.events where player_id = v_player) = v_events0
                          and (select status from public.trade_contracts where id = v_c.id) = 'open'
                          and (select version from public.fleets where id = v_fleet) = v_version);

    -- (e2) THE WHOLE LOT ABOARD: the preview moves nothing and serves the premium the board served.
    v_loaded := public.fleet_load(v_fleet, v_g.code, 1);
    select count(*) into v_ledger0 from public.ledger where player_id = v_player;
    v_pv := cmd.preview_fulfil(v_fleet, v_c.id);
    f_preview_dry := (coalesce((v_pv->>'ok')::boolean, false)
                      and (select ducats from public.players where id = v_player) = v_purse0
                      and public.fleet_cargo_qty(v_fleet, v_g.code) = v_c.qty
                      and (select count(*) from public.events where player_id = v_player) = v_events0
                      and (select status from public.trade_contracts where id = v_c.id) = 'open');
    f_preview_prem := (v_pv->'estimate'->>'kind' = 'fulfil'
                       and (v_pv->'estimate'->'totals'->>'premium')::bigint = v_c.premium_ducats
                       and (v_pv->'estimate'->'contract'->>'premium')::bigint = v_c.premium_ducats
                       and v_pv->'estimate'->'contract'->>'good' = v_g.code
                       and jsonb_array_length(v_pv->'estimate'->'lines') = 1
                       and (v_pv->'estimate'->'lines'->0->>'qty')::numeric = v_c.qty
                       and v_pv->'estimate'->'lines'->0->>'side' = 'sell'
                       and (v_pv->'estimate'->'totals'->>'net')::bigint
                           = (v_pv->'estimate'->'totals'->>'sold')::bigint + v_c.premium_ducats
                       and (v_pv->'estimate'->'purse'->>'after')::bigint - (v_pv->'estimate'->'purse'->>'before')::bigint
                           = (v_pv->'estimate'->'totals'->>'net')::bigint);

    -- (e3) THE DELIVERY LANDS: purse moves by net = sold + premium; the ledger has the SOLD row and
    --      its own PREMIUM row equal to the served figure; a FULFILLED event; the row is marked;
    --      the cargo is gone; trading is the sale's; the version bumped once.
    v_res := cmd.fulfil(v_fleet, v_c.id, v_version);
    select ducats into v_purse1 from public.players where id = v_player;
    v_sold    := (v_res->'totals'->>'sold')::bigint;
    v_premium := (v_res->'totals'->>'premium')::bigint;
    v_net     := (v_res->'totals'->>'net')::bigint;
    v_qty     := v_c.qty;
    v_code    := v_g.code;
    v_served  := v_c.premium_ducats;
    f_landed := (coalesce((v_res->>'ok')::boolean, false) and v_res->>'kind' = 'fulfil'
                 and (v_res->'contract'->>'id')::uuid = v_c.id);
    f_purse_is_net := (v_premium = v_served and v_net = v_sold + v_premium
                       and (v_res->'purse'->>'before')::bigint = v_purse0
                       and (v_res->'purse'->>'after')::bigint = v_purse1
                       and v_purse1 - v_purse0 = v_net
                       and (v_res->'lines'->0->>'total')::bigint = v_sold
                       and (v_res->'lines'->0->>'qty')::numeric = v_c.qty);
    select l.ducats_delta into v_prem_row
      from public.ledger l join public.events e on e.id = l.ref_event_id
     where l.player_id = v_player and l.kind = 'PREMIUM' and e.kind = 'FULFILLED';
    -- (the two rows are found by the EVENTS they record — every row this transaction wrote shares
    --  one now(), so a timestamp cannot tell them from the FOUNDING row)
    f_premium_row := (v_prem_row = v_served
                      and (select count(*) from public.ledger where player_id = v_player) = v_ledger0 + 2
                      and (select sum(l.ducats_delta) from public.ledger l join public.events e on e.id = l.ref_event_id
                            where l.player_id = v_player and e.kind in ('SOLD', 'FULFILLED')) = v_net);
    select e.payload into v_ev from public.events e where e.player_id = v_player and e.kind = 'FULFILLED';
    f_event := (v_ev is not null and (v_ev->>'premium')::bigint = v_served and v_ev->>'good' = v_g.name
                and (v_ev->>'qty')::numeric = v_c.qty and v_ev->>'port' = 'LIS'
                and (v_ev->>'sold_total')::bigint = v_sold
                and (select count(*) from public.events where player_id = v_player) = v_events0 + 2);
    f_row_marked := exists (select 1 from public.trade_contracts c where c.id = v_c.id and c.status = 'fulfilled'
                              and c.fulfilled_by = v_player and c.fulfilled_fleet = v_fleet and c.fulfilled_at is not null);
    f_cargo_gone := (public.fleet_cargo_qty(v_fleet, v_g.code) = 0);
    f_trading := ((v_res->'trading'->>'points_after')::int = (public.player_progress(v_player)->'trading'->>'points')::int
                  and (v_res->'trading'->>'delta')::int >= 0);
    f_version := ((select version from public.fleets where id = v_fleet) = v_version + 1
                  and (v_res->>'version')::int = v_version + 1);
    v_board := world.contracts(v_lis);
    f_board_hides := not exists (select 1 from jsonb_array_elements(v_board->'contracts') e where e->>'id' = v_c.id::text);

    -- (e4) THE REFUSALS: the same tap again (old version) is E_STALE; with the fresh version the
    --      row is done; a passed row is E_CONTRACT_EXPIRED; another port's row is elsewhere; a
    --      made-up id is no request. None moves the purse.
    v_refused := cmd.fulfil(v_fleet, v_c.id, v_version);
    f_stale := (v_refused->>'error_code' = 'E_STALE');
    v_refused := cmd.fulfil(v_fleet, v_c.id, v_version + 1);
    f_done := (v_refused->>'error_code' = 'E_CONTRACT_DONE');
    update public.trade_contracts set status = 'expired', fulfilled_by = null, fulfilled_fleet = null, fulfilled_at = null where id = v_c.id;
    v_refused := cmd.preview_fulfil(v_fleet, v_c.id);
    f_expired := (v_refused->>'error_code' = 'E_CONTRACT_EXPIRED');
    select c.id into v_planted from public.trade_contracts c where c.port_id = v_lis and c.status = 'open' order by c.posted_day, c.seq limit 1;
    update public.trade_contracts set port_id = (select id from public.ports where code = 'CAD') where id = v_planted;
    v_refused := cmd.preview_fulfil(v_fleet, v_planted);
    f_elsewhere := (v_refused->>'error_code' = 'E_CONTRACT_ELSEWHERE');
    v_refused := cmd.preview_fulfil(v_fleet, '00000000-0087-4000-8000-0000000000ff');
    f_no_such := (v_refused->>'error_code' = 'E_NO_SUCH_CONTRACT'
                  and (select ducats from public.players where id = v_player) = v_purse1);

    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '', true);
    raise exception '__PROBE_ROLLBACK_0087__' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> '__PROBE_ROLLBACK_0087__' then raise; end if;
  end;

  -- A finding is judged IS NOT TRUE, never NOT: a mutation that strips a field leaves the
  -- comparison null, and `if not null` is silence. A null finding is a red, not a pass
  -- (breaktest-0087 (e1) caught exactly this).
  if f_short_bit is not true then
    raise exception '0087 self-assert FAIL: a delivery one unit short was not refused E_CONTRACT_SHORT with have % / need % in units', v_short_have, v_short_need;
  end if;
  if f_short_moved is not false then
    raise exception '0087 self-assert FAIL: a refused delivery moved the purse, the cargo, the events, the row or the version';
  end if;
  if f_preview_dry is not true then
    raise exception '0087 self-assert FAIL: cmd.preview_fulfil moved something, or refused the whole lot: %', v_pv;
  end if;
  if f_preview_prem is not true then
    raise exception '0087 self-assert FAIL: the preview''s receipt is not 0083''s with the served premium % on it: %', v_served, v_pv;
  end if;
  if f_landed is not true then
    raise exception '0087 self-assert FAIL: cmd.fulfil refused the whole lot: %', v_res;
  end if;
  if f_purse_is_net is not true then
    raise exception '0087 self-assert FAIL: the receipt says sold % + premium % = net % (served premium %), the purse read % -> %', v_sold, v_premium, v_net, v_served, v_purse0, v_purse1;
  end if;
  if f_premium_row is not true then
    raise exception '0087 self-assert FAIL: the PREMIUM ledger row reads % against the served %, or the two new rows do not sum to net %', v_prem_row, v_served, v_net;
  end if;
  if f_event is not true then
    raise exception '0087 self-assert FAIL: the FULFILLED event is missing or carries the wrong figures: %', v_ev;
  end if;
  if f_row_marked is not true or f_board_hides is not true then
    raise exception '0087 self-assert FAIL: the delivered request is not marked fulfilled by the house and fleet, or world.contracts still serves it';
  end if;
  if f_cargo_gone is not true then
    raise exception '0087 self-assert FAIL: the delivered cargo is still aboard';
  end if;
  if f_trading is not true or f_version is not true then
    raise exception '0087 self-assert FAIL: the receipt''s trading block is not player_progress''s, or the version did not bump exactly once';
  end if;
  if f_stale is not true or f_done is not true or f_expired is not true or f_elsewhere is not true or f_no_such is not true then
    raise exception '0087 self-assert FAIL: the refusals did not bite — stale %, done %, expired %, elsewhere %, no such %',
      f_stale, f_done, f_expired, f_elsewhere, f_no_such;
  end if;

  -- THE ROLLBACK REALLY ROLLED BACK: no probe house, and LIS's board exactly as (b) left it.
  if exists (select 1 from public.players where auth_uid = c_probe) then
    raise exception '0087 self-assert FAIL: the probe house survived the subtransaction';
  end if;
  select count(*), md5(coalesce(string_agg(id::text, ',' order by id), ''))
    into v_wound2, v_digest2 from public.trade_contracts where port_id = v_lis;
  if v_wound2 <> v_n or v_digest2 <> v_digest1 then
    raise exception '0087 self-assert FAIL: LIS''s board is % row(s) digesting % after the probe, was % / %', v_wound2, v_digest2, v_n, v_digest1;
  end if;

  -- (f) THE CATALOGUE is its pre-image with exactly the three rows; the posture on every side.
  select def into v_def from defs_before_0087;
  if pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure) <> replace(v_def,
       E'      (\'cmd\',         \'preview_basket\',      \'uuid, jsonb\')\n    ) as t(s, f, a)',
       E'      (\'cmd\',         \'preview_basket\',      \'uuid, jsonb\'),\n'
       || E'      -- 0087: the request board — one harbour\'s open requests, and a delivery with its dry run.\n'
       || E'      (\'world\',       \'contracts\',           \'uuid\'),\n'
       || E'      (\'cmd\',         \'fulfil\',              \'uuid, uuid, int\'),\n'
       || E'      (\'cmd\',         \'preview_fulfil\',      \'uuid, uuid\')\n    ) as t(s, f, a)') then
    raise exception '0087 self-assert FAIL: public.client_rpc_entry_points is not its pre-image with the three request rows added';
  end if;
  if coalesce((select p.proacl::text from pg_proc p where p.oid = 'public.client_rpc_entry_points()'::regprocedure), '')
     is distinct from (select acl from defs_before_0087) then
    raise exception '0087 self-assert FAIL: the catalogue''s ACL moved';
  end if;
  foreach v_fn in array array[
      'public.contract_draw(uuid, int, int)', 'public.tick_contracts(uuid, timestamptz)', 'cmd.run_fulfil(uuid, uuid)'] loop
    if has_function_privilege('anon', v_fn, 'execute') or has_function_privilege('authenticated', v_fn, 'execute') then
      raise exception '0087 self-assert FAIL: a client role may execute %', v_fn;
    end if;
  end loop;
  foreach v_fn in array array['world.contracts(uuid)', 'cmd.fulfil(uuid, uuid, int)', 'cmd.preview_fulfil(uuid, uuid)'] loop
    if not has_function_privilege('authenticated', v_fn, 'execute') or has_function_privilege('anon', v_fn, 'execute') then
      raise exception '0087 self-assert FAIL: % is not open to authenticated and closed to anon', v_fn;
    end if;
  end loop;
  if has_table_privilege('authenticated', 'public.trade_contracts', 'select')
     or has_table_privilege('anon', 'public.trade_contracts', 'select') then
    raise exception '0087 self-assert FAIL: a client role may read the board directly';
  end if;
  if (select count(*) from public.client_rpc_entry_points() e
       where e.fn is not null and ((e.schema_name, e.function_name) in (('world', 'contracts'), ('cmd', 'fulfil'), ('cmd', 'preview_fulfil')))) <> 3
     or (select count(*) from public.client_rpc_entry_points() where fn is null) <> 0 then
    raise exception '0087 self-assert FAIL: client_rpc_entry_points does not resolve the three request doors';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0087 self-assert FAIL: % client write grant(s)', (select count(*) from public.client_write_grants());
  end if;
  if (select count(*) from public.client_executable_writers()) <> 0 then
    raise exception '0087 self-assert FAIL: % client-executable writer(s): %', (select count(*) from public.client_executable_writers()),
      (select string_agg(schema_name || '.' || function_name || ' ' || grantee, ', ') from public.client_executable_writers());
  end if;
  if (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0087 self-assert FAIL: % read-wall gap(s)', (select count(*) from public.caller_evaluated_functions());
  end if;

  -- WHAT IS LEFT: LIS's board for today's window (the same rows the first read would have posted),
  -- and nothing else — the probe house, its fleet, its money and its events are rolled back.
  raise notice '0087 self-assert ok: A PORT ASKS FOR WHAT IT DOES NOT SELL. Winding LIS on day % posted % request(s) (deadline % x posts %); a second wind posted 0 and re-minted no id; every row equals public.contract_draw recomputed, names a good LIS neither offers nor refuses, is a whole number of %-unit steps between % and % under the port''s base daily allowance, and pays % .. % of its posting mid per unit; a request expiring today was marked expired and left world.contracts, and one a whole window past was pruned; the read served % request(s) with every field equal to its row and days_left = expires - today. On a fresh house (thrown away): one unit short of % units of % was refused E_CONTRACT_SHORT with % / % units and moved nothing; with the whole lot aboard the preview moved nothing and served the board''s own premium % d.; the delivery landed — sold % d. + premium % d. = net % d., the purse read % -> %, the PREMIUM ledger row reads % beside the SOLD one and the two sum to net, the FULFILLED event carries the figures, the row is marked fulfilled and gone from the read, the cargo is gone, trading is the sale''s, version % -> %; the same tap again is E_STALE, then E_CONTRACT_DONE; a passed row E_CONTRACT_EXPIRED; another port''s row E_CONTRACT_ELSEWHERE; a made-up id E_NO_SUCH_CONTRACT. The catalogue is 0083''s with three rows; draw / tick / run_fulfil closed to clients, the board unreadable by clients, contracts / fulfil / preview_fulfil open to authenticated only; 0 client write grants, 0 client-executable writers, 0 read-wall gaps.',
    v_day, v_wound1, v_deadline, v_posts, v_step, v_smin * v_step, v_smax * v_step, v_pmin, v_pmax, v_n,
    v_qty, v_code, v_short_have, v_short_need, v_served,
    v_sold, v_premium, v_net, v_purse0, v_purse1, v_prem_row, v_version, v_version + 1;
end $$;

drop table defs_before_0087;
