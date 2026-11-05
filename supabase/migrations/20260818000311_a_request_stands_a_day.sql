-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0311 — A REQUEST STANDS A DAY: a request carries a set budget, pays a fixed bonus on top of the live price, lasts 24 hours, and the bonus money is on the books
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Owner, 2026-11-05: "the request, for example cumana, soju, the +300 gold should be on top of the prices. for example soju sold at 1000 each would be 1300. get it?" /
--   "and it should show quantity, and time. time should be much longer..." / "the bonus fee should be set, for example the 예산 is 1,000,000. if bonus of 1,000,000 is depleted,
--   that request no longer stands" / "and in report, or stats, bonus fees should also be monitored too".
--
-- WHAT WAS MEASURED ON PROD (docs/dev-log/2026-11-05-city-requests.md): a game day is 60 s, so a request lived 4 real minutes. No request was ever delivered: 0 PREMIUM ledger rows.
--   Of 274 "open" rows 270 had passed their deadline at harbours nobody had read (the read is the catch-up), holding 6.56 M d. until read. One draw costs about 1 s on prod.
--
-- THE RULES NOW:
--   THE BUDGET: `premium_ducats` is now WHAT IS LEFT of the budget, and `escrow` the money held for it; lit, the two are the same figure on every open row. It leaves the purse once, at posting, through
--     treasury_post (BOUNTY). budget = least(contract_budget, city_surplus / (bounty_reserve_mult x contract_open_max)), so all a harbour's requests together never hold half its surplus.
--   THE MINIMUM: a budget that cannot pay for the lot public.contract_draw names (its 1 to 3 trade steps) is not posted, which is 0122's gate kept: the surplus covers it bounty_reserve_mult times over.
--   DARK (purses off, tests and a fresh world): no purse to read, so the budget is that same lot and nothing is escrowed, as before.
--   THE BONUS: `premium_per_unit`, fixed at posting from the mid at posting (DECIDED BY DEFAULT: the mid may drift for 24 hours; the bonus is paid as posted, on top of the live sale price).
--   A DELIVERY: what she holds, cut to what the budget still pays for and to today's sale allowance (DECIDED BY DEFAULT: cut; the rest stays aboard, no plain-price sale of the excess).
--     Many houses and fleets may deliver to one request. Each bonus comes out of the escrow by public.credit(PREMIUM), so nothing is minted. cmd.fulfil keeps its signature.
--   CLOSED: a budget that cannot pay one more unit's bonus closes the request at once, status 'spent'; an odd coin left over goes home as BOUNTY_LAPSED. At expiry the unspent budget goes home the same way.
--   THE DEADLINE: contract_deadline_days 4 -> 1,440 game days = 24 real hours at game_day_seconds 60 (decided by default, a knob; only new requests take it, open ones keep their 4 minutes and drain).
--   THE CAP: contract_open_max (3) open requests a harbour replaces contract_posts_per_day, which is removed. A wind posts AT MOST ONE, on (port, today, the lowest free seq), and draws nothing at the cap,
--     so one read makes at most one draw (it was up to four). The unique key still makes a second wind a no-op: two at once take one seq and one of them posts nothing.
--     At a game-day edge two winds can take different days and stand one over the cap for that request's life: named here, harmless, and it drains.
--   THE ROW OF THE READ: `qty` is now what the budget still pays for, `sale_price` this quay's bid (world.price, what world.market serves as `sell`), `price_each` that plus the bonus. The client adds nothing.
--
-- THE BOOKS: BOUNTY, BOUNTY_LAPSED and PREMIUM are the existing kinds. public.bonus_figures adds what the flow lines cannot: `held` (open escrow) and `paid` (ledger PREMIUM) for the world or one city, served in
--   world.stats_overview and world.stats_city; budget and returned stay the flow lines those reads already carry. stats_flow_words names all three. world.report files PREMIUM under trade as Bonus.
--   ledger_premium_at is a partial index, so `paid` costs nothing on a read asked every second.
--
-- STATUS 'spent' writes no fulfilled_by: many houses share it, and the record of who is the ledger and the FULFILLED events. No code writes 'fulfilled' any more; old rows may keep it until pruned.
-- ZERO-ESCROW ROWS: lit, an open row with no escrow is a pre-0122 leftover and could only pay from nothing. All 32 on prod are past their deadline; they are marked expired here, no money moves.
-- OTHER READERS, CHECKED: world.good_board and world.watchlist read premium_pct, days_left and ports, none of them the lot or the money. tick_stats and stats_live_* read open escrow, which still moves with the row.
--
-- SELF-ASSERT: hunks, reversal, grants, nothing else moved; then on one rolled-back house at a real harbour: the cap, the knob, the share, the minimum, a partial delivery, a second house, a cut delivery, the
--   daily allowance, spent, expiry, the read, the books. Mutation controls: scripts/ops/harness/city-requests/proof-0311.mjs (local).
-- BUDGET (docs/OPS_HEALTH.md section 4): ONE DO block, statement_timeout 60 s, lock_timeout 5 s first. Work: six bodies, one index on the ledger, about 8 draws at about 1 s. Self-assert fails above 60 s.
-- ROLLBACK (forward, a NEW migration, owner only): docs/dev-log/2026-11-05-city-requests.md.
-- VERSION: 0311 - follows 0310 (#492), which must be deployed first.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_p1    constant uuid := '00000000-0311-4000-8000-000000000311';
  c_p2    constant uuid := '00000000-0311-4000-8000-000000000312';
  v_fn    text[];
  v_old   text[];
  v_new   text[];
  v_oids  oid[];
  v_def0  jsonb := '{}'::jsonb;
  v_acl0  jsonb := '{}'::jsonb;
  v_cur   jsonb := '{}'::jsonb;
  v_def   text;
  v_i     int;
  v_n     int;
  v_fn_before   text;
  v_cfg_after   text;
  v_trig_before text;
  v_t0    timestamptz := clock_timestamp();
  v_day   int := world.game_day();
  v_p1    uuid;
  v_p2    uuid;
  v_f1    uuid;
  v_f2    uuid;
  v_port  uuid;
  v_max   int;
  v_mult  int;
  v_draw  record;
  v_good  uuid;
  v_code  text;
  v_pu    numeric;
  v_pu1   numeric;
  v_flows bigint;
  v_lot   bigint;
  v_top   bigint := 0;
  v_b     bigint;
  v_id    uuid;
  c       public.trade_contracts%rowtype;
  v_mark  bigint;
  v_a     jsonb;
  v_q     numeric;
  v_pay   bigint;
  v_paid  bigint := 0;
  v_paid1 bigint := 0;
  v_was   bigint;
  v_cap   numeric;
  v_since timestamptz := now() - interval '1 second';
begin
  perform set_config('statement_timeout', '60s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regprocedure('public.sea_houses()') is null then
    raise exception '0311 refuses: 0310 is not in this world';
  end if;
  if to_regprocedure('public.bonus_figures(uuid, timestamptz)') is not null or exists (select 1 from public.world_config where key = 'contract_open_max') then
    raise exception '0311 refuses: it has been applied once';
  end if;

  v_fn := array[
    'public.tick_contracts(uuid,timestamp with time zone)', 'public.tick_contracts(uuid,timestamp with time zone)', 'public.tick_contracts(uuid,timestamp with time zone)',
    'world.contracts(uuid)', 'world.contracts(uuid)',
    'cmd.run_fulfil(uuid,uuid)', 'cmd.run_fulfil(uuid,uuid)', 'cmd.run_fulfil(uuid,uuid)', 'cmd.run_fulfil(uuid,uuid)',
    'cmd.run_fulfil(uuid,uuid)', 'cmd.run_fulfil(uuid,uuid)', 'cmd.run_fulfil(uuid,uuid)', 'cmd.run_fulfil(uuid,uuid)',
    'world.report(text)', 'world.report(text)',
    'world.stats_overview(integer,text)', 'world.stats_city(uuid,text)'];

  select array_agg(p.oid) into v_oids
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid not in (select f::regprocedure::oid from unnest(v_fn) f);
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_before from pg_proc p where p.oid = any (v_oids);
  select md5(string_agg(t.tgrelid::regclass::text || ':' || t.tgname || ':' || t.tgenabled::text, ',' order by t.tgrelid::regclass::text, t.tgname)) into v_trig_before
    from pg_trigger t where not t.tgisinternal;
  for v_i in 1 .. array_length(v_fn, 1) loop
    v_def0 := v_def0 || jsonb_build_object(v_fn[v_i], replace(pg_get_functiondef(v_fn[v_i]::regprocedure), E'\r', ''));
    v_acl0 := v_acl0 || jsonb_build_object(v_fn[v_i], (select coalesce(p.proacl::text, '') || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '')
                                                         from pg_proc p where p.oid = v_fn[v_i]::regprocedure));
  end loop;
  v_cur := v_def0;

  -- ── 1. THE KNOBS, THE TABLE, THE WORDS, THE INDEX ──
  insert into public.world_config (key, value, description) values
    ('contract_open_max', to_jsonb(3), '0311: how many requests a harbour keeps open at once. It posts only under this; replaces contract_posts_per_day.'),
    ('contract_budget', to_jsonb(1000000), '0311: the most one request may hold, in ducats. The budget is the least of this and city_surplus / (bounty_reserve_mult x contract_open_max).');
  update public.world_config
     set value = to_jsonb(1440),
         description = '0311: how many game-days a request stays open after the day it is posted. 1,440 = 24 real hours at game_day_seconds 60.'
   where key = 'contract_deadline_days';
  delete from public.world_config where key = 'contract_posts_per_day';

  alter table public.trade_contracts drop constraint trade_contracts_status_check;
  alter table public.trade_contracts add constraint trade_contracts_status_check check (status in ('open', 'fulfilled', 'expired', 'spent'));
  alter table public.trade_contracts drop constraint trade_contracts_premium_ducats_check;
  alter table public.trade_contracts add constraint trade_contracts_premium_ducats_check check (premium_ducats >= 0);
  comment on column public.trade_contracts.premium_ducats is '0311: WHAT IS LEFT of the budget, in ducats. Falls with each delivery; 0 once spent.';
  comment on column public.trade_contracts.escrow is '0311: the money held for premium_ducats (lit, the same figure on an open row; dark, 0). Falls with each delivery; what is left goes home as BOUNTY_LAPSED.';

  update public.trade_contracts set status = 'expired' where status = 'open' and escrow = 0 and public.city_treasury_on();

  create index ledger_premium_at on public.ledger (created_at) where kind = 'PREMIUM';

  update public.stats_flow_words set word = 'Bonus budget' where kind = 'BOUNTY';
  update public.stats_flow_words set word = 'Bonus returned' where kind = 'BOUNTY_LAPSED';
  insert into public.stats_flow_words (kind, side, word, ord) values ('PREMIUM', 'moved', 'Bonus paid', 47);

  select md5(string_agg(x.key || ':' || x.value::text || ':' || coalesce(x.description, '') || ':' || x.updated_at::text, ',' order by x.key)) into v_cfg_after from public.world_config x;

  -- ── 2. THE NEW READ ──
  execute $f$
create function public.bonus_figures(p_port uuid, p_since timestamptz)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0311: what the flow lines cannot say: `held`, the money open requests hold now, and `paid`, the bonus paid to houses since p_since (ledger PREMIUM), for one city or, with no port, the world.
  select jsonb_build_object(
           'held', (select coalesce(sum(c.escrow), 0) from public.trade_contracts c where c.status = 'open' and (p_port is null or c.port_id = p_port)),
           'paid', (select coalesce(sum(l.ducats_delta), 0) from public.ledger l where l.kind = 'PREMIUM' and l.created_at > p_since and (p_port is null or l.port_id = p_port)))
$body$
  $f$;
  revoke all on function public.bonus_figures(uuid, timestamptz) from public, anon, authenticated;

  -- ── 3. THE HUNKS: each occurs once ──
  v_old := array[
$h$  v_posts    int := public.wc_int('contract_posts_per_day');
  v_kind     text;
  v_d        int;
  v_s        int;
$h$,
$h$  v_open     boolean;                                          -- 0122
$h$,
$h$  -- POST today and back-fill the window: a request a port posted three days ago is still open
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
      -- 0122: lit, an OPEN request is posted only when the city's surplus covers its premium
      -- bounty_reserve_mult times; a later read back-fills it when the city can.
      v_open := v_d + v_deadline > v_day;
      continue when public.city_treasury_on() and v_open
        and not public.city_can_spend(p_port, round(v_per_unit * v_draw.qty)::bigint * public.wc_int('bounty_reserve_mult'));
      insert into public.trade_contracts
        (port_id, good_id, posted_day, seq, qty, premium_pct, mid_at_post, premium_per_unit, premium_ducats, expires_day,
         status, escrow)
      values
        (p_port, v_draw.good_id, v_d, v_s, v_draw.qty, v_draw.premium_pct, v_mid, v_per_unit,
         round(v_per_unit * v_draw.qty)::bigint, v_d + v_deadline,
         case when v_d + v_deadline <= v_day then 'expired' else 'open' end,
         case when public.city_treasury_on() and v_open then round(v_per_unit * v_draw.qty)::bigint else 0 end)
      on conflict (port_id, posted_day, seq) do nothing;
      if found then
        v_posted := v_posted + 1;
        -- 0122: ESCROW AT POSTING — the premium leaves the city now; cmd.run_fulfil's credit(PREMIUM)
        -- pays it out of nothing new.
        if public.city_treasury_on() and v_open then
          perform public.treasury_post(p_port, 'BOUNTY', -round(v_per_unit * v_draw.qty)::bigint, null, null);
        end if;
      end if;
    end loop;
  end loop;
  return v_posted;
$h$,
$h$        'qty', c.qty,
$h$,
$h$        join public.goods g on g.id = c.good_id
       where c.port_id = p_port and c.status = 'open'));
$h$,
$h$  v_event  uuid;
$h$,
$h$  if c.status = 'fulfilled' then
$h$,
$h$  -- THE WHOLE LOT, OR NOTHING. The two figures ride in DETAIL (0050) so the tray draws the bar.
  v_have := public.fleet_cargo_qty(p_fleet, g.code);
  if v_have < c.qty then
    perform cmd.refuse('E_CONTRACT_SHORT',
      format('%s carries too little %s for this request', f.name, g.name),
      cmd.figures(v_have, c.qty, 'units'));
  end if;
$h$,
$h$              jsonb_build_object('side', 'sell', 'good', g.code, 'qty', c.qty)));
$h$,
$h$  -- THE PREMIUM, its own movement: the figure the board served, to the ducat.
  v_event := public.emit_event(f.player_id, 'FULFILLED', jsonb_build_object(
               'fleet', f.name, 'port', v_port.code, 'good', g.name, 'qty', c.qty,
               'premium', c.premium_ducats, 'premium_pct', c.premium_pct,
               'sold_total', v_rcpt->'lines'->0->'total', 'contract', c.id));
  perform public.credit(f.player_id, 'PREMIUM', c.premium_ducats, v_event);

  update public.trade_contracts
     set status = 'fulfilled', fulfilled_by = f.player_id, fulfilled_fleet = p_fleet, fulfilled_at = now()
   where id = c.id;
$h$,
$h$           'id', c.id, 'good', g.code, 'name', g.name, 'qty', c.qty,
$h$,
$h$           'premium', c.premium_ducats, 'expires_day', c.expires_day),
$h$,
$h$           'premium', c.premium_ducats,
           'net', (v_rcpt->'totals'->>'net')::bigint + c.premium_ducats),
$h$,
$h$    ('SELL', 'Sold', 1), ('BUY', 'Bought', 2), ('TAX', 'Profit tax', 3), ('PORT_FEE', 'Port fee', 3),
$h$,
$h$           case when k.kind in ('SELL', 'BUY', 'TAX', 'PORT_FEE') then 'trade'
$h$,
$h$    'series', coalesce((select jsonb_agg(jsonb_build_object('at', sp.at, 'n', sp.n, 'players', sp.players, 'merchants', sp.merchants, 'cities', sp.cities,
$h$,
$h$    'flows_1d', public.stats_flow_lines((select jsonb_object_agg(k.kind, k.s)
$h$];
  v_new := array[
$h$  v_max      int := public.wc_int('contract_open_max');   -- 0311: the cap, in place of a posting a day
  v_kind     text;
  v_s        int;
$h$,
$h$  v_lit      boolean := public.city_treasury_on();             -- 0311
  v_share    bigint;                                           -- 0311: what this harbour may set on one request
  v_lot      bigint;                                           -- 0311: the bonus on the drawn lot: the least a budget may be
  v_budget   bigint;                                           -- 0311
$h$,
$h$  -- 0311: POST ONE, under the cap, on today and the lowest free seq. No back-fill: a harbour nobody read posts when it is read, and a day's worth of draws never runs on one read.
  -- At the cap nothing is drawn. The draw is pure and the unique key makes a second wind a no-op.
  if (select count(*) from public.trade_contracts where port_id = p_port and status = 'open') >= v_max then
    return 0;
  end if;
  select min(s) into v_s
    from generate_series(1, v_max) s
   where not exists (select 1 from public.trade_contracts c where c.port_id = p_port and c.posted_day = v_day and c.seq = s);
  if v_s is null then
    return 0;   -- every seq of this game day is taken: the next game day has more
  end if;
  if v_lit then
    v_share := public.city_surplus(p_port) / (public.wc_int('bounty_reserve_mult') * v_max);
    if v_share < 1 then
      return 0;   -- no surplus: no draw to spend
    end if;
  end if;
  select * into v_draw from public.contract_draw(p_port, v_day, v_s);
  if v_draw.good_id is null then
    return 0;
  end if;
  -- The mid is struck to the ducat-cent ONCE, here: the row keeps that figure, and the bonus per unit is
  -- computed from it, so what the row states and what the rule recomputes are the same number.
  select round(q.mid, 2) into v_mid from world.price(p_port, v_draw.good_id) q;
  v_per_unit := round(v_mid * v_draw.premium_pct, 2);
  v_lot := ceil(v_per_unit * v_draw.qty)::bigint;
  v_budget := case when v_lit then least(public.wc_int('contract_budget')::bigint, v_share) else v_lot end;
  if v_budget < v_lot then
    return 0;   -- a budget that cannot pay for the drawn lot does not post
  end if;
  insert into public.trade_contracts
    (port_id, good_id, posted_day, seq, qty, premium_pct, mid_at_post, premium_per_unit, premium_ducats, expires_day, status, escrow)
  values
    (p_port, v_draw.good_id, v_day, v_s, floor(v_budget / v_per_unit), v_draw.premium_pct, v_mid, v_per_unit, v_budget, v_day + v_deadline, 'open',
     case when v_lit then v_budget else 0 end)
  on conflict (port_id, posted_day, seq) do nothing;
  if found then
    v_posted := 1;
    -- 0122: ESCROW AT POSTING — the budget leaves the city now; cmd.run_fulfil's credit(PREMIUM) pays it out of nothing new.
    if v_lit then
      perform public.treasury_post(p_port, 'BOUNTY', -v_budget, null, null);
    end if;
  end if;
  return v_posted;
$h$,
$h$        -- 0311: what the budget still pays for, this quay's live bid, and the two prices as one figure: the client adds nothing
        'qty', floor(c.premium_ducats / c.premium_per_unit),
        'sale_price', q.bid,
        'price_each', round(q.bid + c.premium_per_unit, 2),
$h$,
$h$        join public.goods g on g.id = c.good_id
       cross join lateral world.price(c.port_id, c.good_id) q   -- 0311
       where c.port_id = p_port and c.status = 'open'));
$h$,
$h$  v_event  uuid;
  v_left   numeric;   -- 0311: the units the budget still pays for
  v_qty    numeric;   -- 0311: what this delivery lands
  v_cap    numeric;   -- 0311
  v_pay    bigint;    -- 0311: this delivery's bonus
  v_rest   bigint;    -- 0311: the budget after it
$h$,
$h$  v_left := floor(c.premium_ducats / c.premium_per_unit);   -- 0311
  if c.status in ('fulfilled', 'spent') or (c.status = 'open' and v_left < 1) then
$h$,
$h$  -- 0311: WHAT SHE HOLDS, CUT TO THE BUDGET AND TO TODAY'S ALLOWANCE. The rest stays aboard. Nothing aboard is the one refusal, and its figures ride in DETAIL (0050).
  v_have := public.fleet_cargo_qty(p_fleet, g.code);
  if floor(v_have) < 1 then
    perform cmd.refuse('E_CONTRACT_SHORT',
      format('%s carries too little %s for this request', f.name, g.name),
      cmd.figures(v_have, v_left, 'units'));
  end if;
  v_qty := least(floor(v_have), v_left);
  v_cap := world.daily_cap_remaining(f.player_id, c.port_id, c.good_id);
  if v_cap >= 1 then   -- under one unit the sale below refuses in its own words
    v_qty := least(v_qty, floor(v_cap));
  end if;
$h$,
$h$              jsonb_build_object('side', 'sell', 'good', g.code, 'qty', v_qty)));
$h$,
$h$  -- THE BONUS, its own movement, out of the escrow: the fixed figure on what landed, rounded up to the ducat. The budget is whole ducats and v_qty at most v_left, so it is never more than the budget.
  v_pay  := ceil(c.premium_per_unit * v_qty)::bigint;
  v_rest := c.premium_ducats - v_pay;
  v_event := public.emit_event(f.player_id, 'FULFILLED', jsonb_build_object(
               'fleet', f.name, 'port', v_port.code, 'good', g.name, 'qty', v_qty,
               'premium', v_pay, 'premium_pct', c.premium_pct,
               'sold_total', v_rcpt->'lines'->0->'total', 'contract', c.id));
  perform public.credit(f.player_id, 'PREMIUM', v_pay, v_event);

  -- 0311: MORE THAN ONE MORE UNIT'S BONUS LEFT, the request stands; less, it is spent, and the odd coin goes home.
  if v_rest >= c.premium_per_unit then
    update public.trade_contracts
       set premium_ducats = v_rest, escrow = greatest(escrow - v_pay, 0)
     where id = c.id;
  else
    update public.trade_contracts set status = 'spent', premium_ducats = 0, escrow = 0 where id = c.id;
    if c.escrow > v_pay then
      perform public.treasury_post(c.port_id, 'BOUNTY_LAPSED', c.escrow - v_pay, null, null, true);
    end if;
  end if;
$h$,
$h$           'id', c.id, 'good', g.code, 'name', g.name, 'qty', v_qty,
$h$,
$h$           'premium', v_pay, 'budget_left', case when v_rest >= c.premium_per_unit then v_rest else 0 end, 'expires_day', c.expires_day),
$h$,
$h$           'premium', v_pay,
           'net', (v_rcpt->'totals'->>'net')::bigint + v_pay),
$h$,
$h$    ('SELL', 'Sold', 1), ('PREMIUM', 'Bonus', 1), ('BUY', 'Bought', 2), ('TAX', 'Profit tax', 3), ('PORT_FEE', 'Port fee', 3),
$h$,
$h$           case when k.kind in ('SELL', 'PREMIUM', 'BUY', 'TAX', 'PORT_FEE') then 'trade'
$h$,
$h$    'bonus', public.bonus_figures(null, l.at - interval '24 hours'),   -- 0311: open escrow now, bonus paid in the same 24 h as `day`
    'series', coalesce((select jsonb_agg(jsonb_build_object('at', sp.at, 'n', sp.n, 'players', sp.players, 'merchants', sp.merchants, 'cities', sp.cities,
$h$,
$h$    'bonus', public.bonus_figures(p_port, v_at - interval '24 hours'),   -- 0311: this city's, in the same 24 h as flows_1d
    'flows_1d', public.stats_flow_lines((select jsonb_object_agg(k.kind, k.s)
$h$];
  for v_i in 1 .. array_length(v_old, 1) loop
    v_def := v_cur ->> v_fn[v_i];
    v_n := (length(v_def) - length(replace(v_def, v_old[v_i], ''))) / length(v_old[v_i]);
    if v_n <> 1 then
      raise exception '0311 self-assert FAIL: hunk % of % occurs % time(s), not once: the live body is not what this file was cut against', v_i, v_fn[v_i], v_n;
    end if;
    v_cur := v_cur || jsonb_build_object(v_fn[v_i], replace(v_def, v_old[v_i], v_new[v_i]));
  end loop;
  for v_i in 1 .. array_length(v_fn, 1) loop
    continue when v_i > 1 and v_fn[v_i] = v_fn[v_i - 1];   -- several hunks to a body: one write of each
    execute v_cur ->> v_fn[v_i];
  end loop;

  -- ── 4. THE SELF-ASSERT: hunks, grants, nothing else moved ──
  for v_i in 1 .. array_length(v_fn, 1) loop
    v_def := replace(pg_get_functiondef(v_fn[v_i]::regprocedure), E'\r', '');
    if v_def <> v_cur ->> v_fn[v_i] then
      raise exception '0311 self-assert FAIL: % is not the body this file wrote', v_fn[v_i];
    end if;
  end loop;
  for v_i in reverse array_length(v_old, 1) .. 1 loop
    v_def := v_cur ->> v_fn[v_i];
    if (length(v_def) - length(replace(v_def, v_new[v_i], ''))) / length(v_new[v_i]) <> 1 then
      raise exception '0311 self-assert FAIL: hunk % is not in the new body of % exactly once', v_i, v_fn[v_i];
    end if;
    v_cur := v_cur || jsonb_build_object(v_fn[v_i], replace(v_def, v_new[v_i], v_old[v_i]));
  end loop;
  if v_cur <> v_def0 then
    raise exception '0311 self-assert FAIL: a body does not reverse to its pre-image';
  end if;
  for v_i in 1 .. array_length(v_fn, 1) loop
    if (select coalesce(p.proacl::text, '') || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') from pg_proc p where p.oid = v_fn[v_i]::regprocedure) <> v_acl0 ->> v_fn[v_i] then
      raise exception '0311 self-assert FAIL: the grants or settings of % moved', v_fn[v_i];
    end if;
  end loop;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (v_oids)) <> v_fn_before then
    raise exception '0311 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(t.tgrelid::regclass::text || ':' || t.tgname || ':' || t.tgenabled::text, ',' order by t.tgrelid::regclass::text, t.tgname))
        from pg_trigger t where not t.tgisinternal) <> v_trig_before then
    raise exception '0311 self-assert FAIL: a trigger moved';
  end if;
  if has_function_privilege('anon', 'public.bonus_figures(uuid, timestamptz)', 'execute') or has_function_privilege('authenticated', 'public.bonus_figures(uuid, timestamptz)', 'execute') then
    raise exception '0311 self-assert FAIL: a client can reach the helper';
  end if;
  if public.wc_int('contract_deadline_days') <> 1440 or public.wc_int('contract_open_max') <> 3 or public.wc_int('contract_budget') <> 1000000
     or exists (select 1 from public.world_config where key = 'contract_posts_per_day') then
    raise exception '0311 self-assert FAIL: the knobs are not this file''s';
  end if;
  v_max := public.wc_int('contract_open_max');
  v_mult := public.wc_int('bounty_reserve_mult');

  -- ── 5. THE WORKED EXAMPLE, ON TWO HOUSES AT ONE REAL HARBOUR, EVERY ROW ROLLED BACK ──
  execute $f$
create function pg_temp.purse_0311(p_port uuid, p_surplus bigint) returns void language plpgsql as $b$
begin
  perform public.treasury_post(p_port, 'CROWN_CALL', p_surplus - public.city_surplus(p_port), null, null, true);
end $b$
  $f$;
  begin
    update public.world_config set value = 'false'::jsonb where key = 'economy_closed';   -- a founding is refused on a closed economy; the two probe houses are rolled back with the rest
    v_p1 := public.new_house(c_p1, 'Casa do Bonus Um', 'PRT');
    v_p2 := public.new_house(c_p2, 'Casa do Bonus Dois', 'PRT');
    v_f1 := (select f.id from public.fleets f where f.player_id = v_p1);
    v_f2 := (select f.id from public.fleets f where f.player_id = v_p2);
    v_port := (select f.port_id from public.fleets f where f.id = v_f1);
    update public.fleets set port_id = v_port where id = v_f2;
    update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed') and value is distinct from 'true'::jsonb;
    insert into public.port_treasury (port_id, ducats, reserve, earned_day) values (v_port, 0, 0, v_day) on conflict (port_id) do update set reserve = 0;
    delete from public.trade_contracts where port_id = v_port;

    -- what the draws of today ask for, so the probe does not lean on the day's good
    for v_i in 1 .. v_max loop
      select * into v_draw from public.contract_draw(v_port, v_day, v_i);
      if v_draw.good_id is null then
        raise exception '0311 self-assert FAIL: the probe harbour draws nothing for seq %', v_i;
      end if;
      v_pu := round(round((select q.mid from world.price(v_port, v_draw.good_id) q), 2) * v_draw.premium_pct, 2);
      v_top := greatest(v_top, ceil(v_pu * v_draw.qty)::bigint);
      if v_i = 1 then
        v_good := v_draw.good_id;
        v_pu1 := v_pu;
        v_lot := ceil(v_pu * v_draw.qty)::bigint;
      end if;
    end loop;
    update public.goods set bulk = 0.01 where id = v_good;   -- any lot fits the probe's hold
    v_code := (select g.code from public.goods g where g.id = v_good);

    -- (a) THE KNOB CAPS IT, AND THE CAP HOLDS: a rich city posts the knob's budget, one a wind, three, then nothing
    v_b := v_top * 4;
    update public.world_config set value = to_jsonb(v_b) where key = 'contract_budget';
    perform pg_temp.purse_0311(v_port, v_b * v_mult * v_max * 3);
    v_was := public.treasury_balance(v_port);
    v_mark := coalesce((select max(f.id) from public.treasury_flows f), 0);
    for v_i in 1 .. v_max loop
      if public.tick_contracts(v_port, now()) <> 1 then
        raise exception '0311 self-assert FAIL: wind % of a rich harbour did not post exactly one', v_i;
      end if;
    end loop;
    if public.tick_contracts(v_port, now()) <> 0 or (select count(*) from public.trade_contracts t where t.port_id = v_port and t.status = 'open') <> v_max then
      raise exception '0311 self-assert FAIL: the cap of % did not hold', v_max;
    end if;
    if public.tick_contracts(v_port, now() + make_interval(secs => public.wc_num('game_day_seconds')::double precision)) <> 0 then
      raise exception '0311 self-assert FAIL: the cap of % did not hold on the next game day', v_max;
    end if;
    if exists (select 1 from public.trade_contracts t where t.port_id = v_port
                and (t.premium_ducats <> v_b or t.escrow <> v_b or t.expires_day <> v_day + 1440 or t.posted_day <> v_day or t.qty <> floor(v_b / t.premium_per_unit))) then
      raise exception '0311 self-assert FAIL: a request is not the knob''s budget, its escrow and its 1,440 days: %',
        (select jsonb_agg(to_jsonb(t)) from public.trade_contracts t where t.port_id = v_port);
    end if;
    if v_was - public.treasury_balance(v_port) <> v_b * v_max
       or (select coalesce(sum(f.ducats), 0) from public.treasury_flows f where f.id > v_mark and f.kind = 'BOUNTY' and f.port_id = v_port) <> -v_b * v_max then
      raise exception '0311 self-assert FAIL: the budgets did not leave the purse by BOUNTY';
    end if;

    -- (b) THE SHARE AND THE MINIMUM: below the lot nothing posts and nothing moves; at it, the budget is surplus / (mult x cap)
    delete from public.trade_contracts where port_id = v_port;
    perform pg_temp.purse_0311(v_port, 0);
    if public.tick_contracts(v_port, now()) <> 0 then
      raise exception '0311 self-assert FAIL: a city with no surplus posted';
    end if;
    perform pg_temp.purse_0311(v_port, (v_lot - 1) * v_mult * v_max);
    v_mark := coalesce((select max(f.id) from public.treasury_flows f), 0);
    if public.tick_contracts(v_port, now()) <> 0 or exists (select 1 from public.treasury_flows f where f.id > v_mark) then
      raise exception '0311 self-assert FAIL: a budget under the lot posted or moved money';
    end if;

    -- THE SMALL REQUEST the deliveries run on: the lot's budget and half a unit's bonus more, so an odd coin is left at the end
    v_b := v_lot + floor(v_pu1 / 2)::bigint;
    perform pg_temp.purse_0311(v_port, v_b * v_mult * v_max);
    v_since := now() - interval '1 second';
    v_flows := coalesce((select max(f.id) from public.treasury_flows f), 0);
    if public.tick_contracts(v_port, now()) <> 1 then
      raise exception '0311 self-assert FAIL: a budget at the share did not post';
    end if;
    select t.* into c from public.trade_contracts t where t.port_id = v_port and t.status = 'open';
    v_id := c.id;
    if c.premium_ducats <> v_b or c.escrow <> v_b or c.good_id <> v_good then
      raise exception '0311 self-assert FAIL: the budget is not surplus / (mult x cap): % against %', c.premium_ducats, v_b;
    end if;
    perform pg_temp.purse_0311(v_port, 1000000000);   -- the sale itself must not be short: the purse is not what is under test from here

    -- (c) THE READ: the figure the client prints is served, and is the quay's bid plus the bonus
    v_a := (select e from jsonb_array_elements((world.contracts(v_port)) -> 'contracts') e where e ->> 'id' = v_id::text);
    if (v_a ->> 'qty')::numeric <> floor(c.premium_ducats / c.premium_per_unit)
       or (v_a ->> 'sale_price')::numeric is distinct from (select q.bid from world.price(v_port, v_good) q)
       or (v_a ->> 'price_each')::numeric is distinct from round((v_a ->> 'sale_price')::numeric + c.premium_per_unit, 2)
       or (v_a ->> 'premium_ducats')::bigint <> v_b then
      raise exception '0311 self-assert FAIL: the read does not serve the row: %', v_a;
    end if;

    -- (d) NOTHING ABOARD IS REFUSED, AND NOTHING MOVES
    perform cmd.assume_identity(c_p1);
    v_a := cmd.fulfil(v_f1, v_id, null);
    if v_a ->> 'error_code' is distinct from 'E_CONTRACT_SHORT' or (v_a #>> '{figures,have}')::numeric <> 0 or (v_a #>> '{figures,need}')::numeric <> floor(c.premium_ducats / c.premium_per_unit) then
      raise exception '0311 self-assert FAIL: an empty hold was not refused with its figures: %', v_a;
    end if;

    -- (e) A PART: two units land, the bonus is the fixed figure on two, the rest of the budget stands, the books move together, nothing is made
    perform public.fleet_load(v_f1, v_code, 2);
    v_a := cmd.preview_fulfil(v_f1, v_id);
    if not coalesce((v_a ->> 'ok')::boolean, false) or (v_a #>> '{estimate,totals,premium}')::bigint <> ceil(c.premium_per_unit * 2)::bigint then
      raise exception '0311 self-assert FAIL: the dry run of a part: %', v_a;
    end if;
    if (select t.premium_ducats from public.trade_contracts t where t.id = v_id) <> v_b then
      raise exception '0311 self-assert FAIL: the dry run spent the budget';
    end if;
    -- house + city + what the city holds in escrow: the delivery's wind may post another request, which is the city's money moved into escrow
    v_was := (select p.ducats from public.players p where p.id = v_p1) + public.treasury_balance(v_port)
             + (select coalesce(sum(t.escrow), 0) from public.trade_contracts t where t.port_id = v_port and t.status = 'open');
    v_a := cmd.fulfil(v_f1, v_id, null);
    v_pay := ceil(c.premium_per_unit * 2)::bigint;
    v_paid := v_pay;
    v_paid1 := v_pay;
    if (v_a ->> 'kind') is distinct from 'fulfil' or (v_a #>> '{totals,premium}')::bigint <> v_pay or (v_a #>> '{lines,0,qty}')::numeric <> 2
       or (v_a #>> '{contract,budget_left}')::bigint <> v_b - v_paid then
      raise exception '0311 self-assert FAIL: a part did not land: %', v_a;
    end if;
    select t.* into c from public.trade_contracts t where t.id = v_id;
    if c.status <> 'open' or c.premium_ducats <> v_b - v_paid or c.escrow <> v_b - v_paid then
      raise exception '0311 self-assert FAIL: the budget did not fall by the bonus paid: %', to_jsonb(c);
    end if;
    if (select p.ducats from public.players p where p.id = v_p1) + public.treasury_balance(v_port)
             + (select coalesce(sum(t.escrow), 0) from public.trade_contracts t where t.port_id = v_port and t.status = 'open') <> v_was then
      raise exception '0311 self-assert FAIL: a delivery made or lost money: house, city and escrow moved %',
        (select p.ducats from public.players p where p.id = v_p1) + public.treasury_balance(v_port)
             + (select coalesce(sum(t.escrow), 0) from public.trade_contracts t where t.port_id = v_port and t.status = 'open') - v_was;
    end if;
    if (select l.port_id from public.ledger l where l.player_id = v_p1 and l.kind = 'PREMIUM' order by l.created_at desc limit 1) is distinct from v_port
       or (select sum(l.ducats_delta) from public.ledger l where l.player_id = v_p1 and l.kind = 'PREMIUM') <> v_pay then
      raise exception '0311 self-assert FAIL: the ledger''s bonus row is not at this city';
    end if;
    v_a := (select e from jsonb_array_elements((world.contracts(v_port)) -> 'contracts') e where e ->> 'id' = v_id::text);
    if (v_a ->> 'premium_ducats')::bigint is distinct from c.premium_ducats or (v_a ->> 'qty')::numeric is distinct from floor(c.premium_ducats / c.premium_per_unit) then
      raise exception '0311 self-assert FAIL: the read does not show what is left: %', v_a;
    end if;

    -- (f) ANOTHER HOUSE ON THE SAME REQUEST
    perform public.fleet_load(v_f2, v_code, 1);
    perform cmd.assume_identity(c_p2);
    v_a := cmd.fulfil(v_f2, v_id, null);
    v_pay := ceil(c.premium_per_unit)::bigint;
    v_paid := v_paid + v_pay;
    if (v_a #>> '{totals,premium}')::bigint is distinct from v_pay or (select t.premium_ducats from public.trade_contracts t where t.id = v_id) <> v_b - v_paid then
      raise exception '0311 self-assert FAIL: a second house could not deliver: %', v_a;
    end if;

    -- (g) MORE THAN THE BUDGET PAYS FOR IS CUT, THE REST STAYS ABOARD, AND THE REQUEST IS SPENT WITH ITS ODD COIN HOME
    select t.* into c from public.trade_contracts t where t.id = v_id;
    v_q := floor(c.premium_ducats / c.premium_per_unit);
    perform cmd.assume_identity(c_p1);
    perform public.fleet_load(v_f1, v_code, v_q + 2);
    v_mark := coalesce((select max(f.id) from public.treasury_flows f where f.kind = 'BOUNTY_LAPSED'), 0);
    v_a := cmd.fulfil(v_f1, v_id, null);
    v_pay := ceil(c.premium_per_unit * v_q)::bigint;
    v_paid := v_paid + v_pay;
    v_paid1 := v_paid1 + v_pay;
    if (v_a #>> '{lines,0,qty}')::numeric is distinct from v_q or public.fleet_cargo_qty(v_f1, v_code) <> 2 or (v_a #>> '{totals,premium}')::bigint is distinct from v_pay then
      raise exception '0311 self-assert FAIL: a delivery over the budget was not cut: %', v_a;
    end if;
    select t.* into c from public.trade_contracts t where t.id = v_id;
    if c.status <> 'spent' or c.premium_ducats <> 0 or c.escrow <> 0 then
      raise exception '0311 self-assert FAIL: a budget that cannot pay one more unit did not close: %', to_jsonb(c);
    end if;
    if (select coalesce(sum(f.ducats), 0) from public.treasury_flows f where f.id > v_mark and f.kind = 'BOUNTY_LAPSED' and f.port_id = v_port) <> v_b - v_paid then
      raise exception '0311 self-assert FAIL: the odd coin did not go home: % of %',
        (select coalesce(sum(f.ducats), 0) from public.treasury_flows f where f.id > v_mark and f.kind = 'BOUNTY_LAPSED'), v_b - v_paid;
    end if;
    v_a := cmd.fulfil(v_f1, v_id, null);
    if v_a ->> 'error_code' is distinct from 'E_CONTRACT_DONE' then
      raise exception '0311 self-assert FAIL: a spent request took a delivery: %', v_a;
    end if;
    if exists (select 1 from jsonb_array_elements((world.contracts(v_port)) -> 'contracts') e where e ->> 'id' = v_id::text) then
      raise exception '0311 self-assert FAIL: a spent request is still on the board';
    end if;

    -- (h) TODAY'S ALLOWANCE CUTS A DELIVERY, IT DOES NOT REFUSE IT: an open request with room for more than a house may sell today
    select t.* into c from public.trade_contracts t where t.port_id = v_port and t.status = 'open' order by t.seq limit 1;
    v_code := (select g.code from public.goods g where g.id = c.good_id);
    update public.goods set bulk = 0.01 where id = c.good_id;
    v_cap := world.daily_cap_remaining(v_p2, v_port, c.good_id);
    v_b := ceil(c.premium_per_unit * (floor(v_cap) + 10))::bigint;
    perform public.treasury_post(v_port, 'BOUNTY', -(v_b - c.escrow), null, null);
    update public.trade_contracts set premium_ducats = v_b, escrow = v_b where id = c.id;
    perform public.fleet_load(v_f2, v_code, floor(v_cap) + 2);
    perform cmd.assume_identity(c_p2);
    v_a := cmd.fulfil(v_f2, c.id, null);
    v_pay := ceil(c.premium_per_unit * floor(v_cap))::bigint;
    v_paid := v_paid + v_pay;
    if (v_a #>> '{lines,0,qty}')::numeric is distinct from floor(v_cap) or public.fleet_cargo_qty(v_f2, v_code) <> 2
       or (select t.status from public.trade_contracts t where t.id = c.id) <> 'open' then
      raise exception '0311 self-assert FAIL: today''s allowance did not cut the delivery: %', v_a;
    end if;

    -- (i) AT EXPIRY THE UNSPENT BUDGET GOES HOME
    v_mark := coalesce((select max(f.id) from public.treasury_flows f where f.kind = 'BOUNTY_LAPSED'), 0);
    v_was := (select coalesce(sum(t.escrow), 0) from public.trade_contracts t where t.port_id = v_port and t.status = 'open');
    perform public.tick_contracts(v_port, now() + make_interval(secs => ((1440 + 1) * public.wc_num('game_day_seconds'))::double precision));
    if (select coalesce(sum(f.ducats), 0) from public.treasury_flows f where f.id > v_mark and f.kind = 'BOUNTY_LAPSED' and f.port_id = v_port) <> v_was or v_was <= 0
       or (select t.status from public.trade_contracts t where t.id = c.id) <> 'expired' then
      raise exception '0311 self-assert FAIL: the unspent budget did not go home at expiry: % of %',
        (select coalesce(sum(f.ducats), 0) from public.treasury_flows f where f.id > v_mark and f.kind = 'BOUNTY_LAPSED' and f.port_id = v_port), v_was;
    end if;

    -- (j) THE BOOKS RECONCILE TO THE FLOWS, TO THE DUCAT: set aside = paid + returned + still held, and bonus_figures says so
    v_a := public.bonus_figures(v_port, v_since);
    if (v_a ->> 'paid')::bigint <> v_paid
       or (v_a ->> 'held')::bigint <> (select coalesce(sum(t.escrow), 0) from public.trade_contracts t where t.port_id = v_port and t.status = 'open')
       or (select coalesce(-sum(f.ducats), 0) from public.treasury_flows f where f.id > v_flows and f.port_id = v_port and f.kind = 'BOUNTY')
          <> (v_a ->> 'paid')::bigint + (v_a ->> 'held')::bigint
             + (select coalesce(sum(f.ducats), 0) from public.treasury_flows f where f.id > v_flows and f.port_id = v_port and f.kind = 'BOUNTY_LAPSED') then
      raise exception '0311 self-assert FAIL: the bonus books do not reconcile: figures %, paid here %, flows %', v_a, v_paid,
        (select jsonb_object_agg(x.kind, x.s) from (select f.kind, sum(f.ducats) s from public.treasury_flows f where f.id > v_flows and f.port_id = v_port group by 1) x);
    end if;

    -- (k) THE REPORT AND THE WORDS
    perform cmd.assume_identity(c_p1);
    v_a := (select l from jsonb_array_elements(world.report('all') -> 'sections') s, jsonb_array_elements(s -> 'lines') l where s ->> 'id' = 'trade' and l ->> 'kind' = 'PREMIUM');
    if (v_a ->> 'ducats')::bigint is distinct from v_paid1 or v_a ->> 'word' <> 'Bonus' then
      raise exception '0311 self-assert FAIL: the report does not show the bonus on its own line: %', v_a;
    end if;
    if (select string_agg(e ->> 'word', ',' order by e ->> 'word') from jsonb_array_elements(public.stats_flow_lines('{"PREMIUM":3,"BOUNTY":-3,"BOUNTY_LAPSED":1}'::jsonb)) e)
       <> 'Bonus budget,Bonus paid,Bonus returned' then
      raise exception '0311 self-assert FAIL: the words of the books';
    end if;

    raise exception using errcode = 'ZX311', message = 'rolled back';
  exception when sqlstate 'ZX311' then
    null;
  end;
  drop function pg_temp.purse_0311(uuid, bigint);

  if (select md5(string_agg(x.key || ':' || x.value::text || ':' || coalesce(x.description, '') || ':' || x.updated_at::text, ',' order by x.key)) from public.world_config x) <> v_cfg_after then
    raise exception '0311 self-assert FAIL: a world_config row moved';
  end if;
  if exists (select 1 from public.players p where p.id in (c_p1, c_p2)) then
    raise exception '0311 self-assert FAIL: a probe house stayed';
  end if;
  if clock_timestamp() - v_t0 > interval '60 seconds' then
    raise exception '0311 self-assert FAIL: over budget, %', clock_timestamp() - v_t0;
  end if;
  raise notice '0311 self-assert ok: a budget posted, part-delivered by two houses, cut, spent, expired and reconciled to the flows, in %', clock_timestamp() - v_t0;
end
$m$;
