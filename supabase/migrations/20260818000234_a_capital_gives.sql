-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0234 — A CAPITAL GIVES
--        (slice E4 of docs/CLOSED_ECONOMY.md: lit, a broke merchant company gets her starting money back from her
--         country's capital — a CAPITAL_GIFT — and every new company's starting money is paid by its country's
--         capital, never printed. DARK: nothing is paid, nothing is served, every body answers as before.)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER, VERBATIM (docs/OWNER_REQUESTS.md row 212, 2026-10-26) ────────────────────────────
--   "yes, but broke merchants will receive donation (starting money) from their capital city (show this too).
--    lets try this model and see the stats after few days."
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
--   NEW, server-only:
--   * public.capital_pays(capital, nation, player, kind, amount, event, must, note) — THE ONE way a capital pays a
--     company (§5.2, §5.4). The capital pays from what it holds above its reserve (public.city_surplus, the figure
--     every city spender reads); the gap it CALLS from the harbour of its realm (public.port_nation = the country)
--     with the largest surplus — CROWN_CALL, −gap there, +gap at the capital — then pays through public.city_pays.
--     Realm short: answers {waiting}, moves nothing — unless `must` (a founding: never block a sign-up), when the
--     world's richest harbour pays it whole; if even that cannot, the plain credit of before (stated, E7 judges it).
--     Locks: the house first (city_pays's order), then the realm harbour before its capital (city_day's order).
--   * public.founding_credit(player, kind, delta, event) — credit()'s drop-in for starting money: open, it IS
--     public.credit(...) (the same call, the same ledger row); closed, the company's country's capital pays it
--     (capital_pays, must). public.new_house and public.npc_fix_hull_skills call it where they called credit for
--     FOUNDING. public.npc_found is NOT re-cut: its founding money (capital + wages + tuition) is new_house's
--     p_ducats, so it passes through new_house's one call.
--   * public.capital_gift_pass(p_now, p_only) — the hourly gift (§5.2). Null while the economy is open. Lit, for at
--     most gift_max_per_hour (50) merchant companies whose worth (public.npc_worth: purse + cargo at cost, 0203's
--     reader, restored here — 0213 dropped it with the refound) is under merchant_broke_pct (0.2, 0229's knob) ×
--     her capital, with no gift in the last gift_cooldown_hours (24) and fewer than gift_max_per_week (3) in seven
--     days, the ones gifted longest ago (or never) first: her country's capital pays her capital (her starting
--     money) — ledger CAPITAL_GIFT (+), flow CAPITAL_GIFT (−), one capital_gifts row (called_from = the realm harbour
--     if one was called), one CAPITAL_GIFT event {port, port_name, ducats, worth, called_from}. Realm short: no money,
--     one GIFT_WAITING event a day {port, port_name, ducats, worth, gap}; she is asked again next hour. p_only (a
--     probe's company) narrows the pass to one company; the hourly call passes none.
--   * public.town_hall_gifts(port) / public.npc_last_gift(player) — the two reads' new keys, served ONLY when there
--     is a gift to show: world.town_hall gains `gifts` (the capital's last town_hall_gifts_max (10) gifts: name,
--     ducats, at, called_from), world.npc_fleet_card's company gains `last_gift` (port, name, ducats, at). With no
--     gift ever given (dark: capital_gifts is empty) neither key is served, so both reads are byte for byte today's.
--   KNOBS: gift_max_per_hour 50, gift_max_per_week 3, gift_cooldown_hours 24, town_hall_gifts_max 10.
--
-- ── HUNKS SLICED FROM THE LIVE BODIES (prod head 0229, LF-normalised; each asserted to occur exactly once and
--    to reverse to its pre-image; ACL / volatility / definer / config unchanged) ────────────────────────────
--   public.npc_tend_houses ×3 (a declared variable; the pass after the investment; its counts on the receipt)
--   public.new_house ×1, public.npc_fix_hull_skills ×1 (credit → founding_credit for FOUNDING)
--   world.town_hall ×1, world.npc_fleet_card ×1 (|| the new key, served only when there is one)
--   None of the five is sliced by 0231 (voyage.reach_passage, world.good_board) or 0232 (tick_stats and the stats
--   faces), nor by 0233 (city_day, do_sell, city_sell_outflow); they are cut as they stand at 0229.
--   STATS: a capital-paid founding is a city flow FOUNDING (−) and a ledger FOUNDING (+). 0232's
--   public.stats_window_kinds sums the two per kind (0), so lit it reads no new money; CAPITAL_GIFT and CROWN_CALL
--   are moved (0228).
--
-- ── WHAT IT SELF-ASSERTS (probe companies only; flows counted are the ones above a mark taken in-block AND written
--    at this transaction's now(); every probe in a sub-transaction, rolled back, asserted) ──────────────────────
--   (a) the hunks reverse; ACL / volatility / definer / config unmoved; the new functions server-only; registry
--       unchanged; walls 0.
--   (b) LIT, THE CAPITAL PAYS: Lisbon holds 1,000,000 above its reserve; a probe merchant (capital 5,000) is founded
--       with 500 → FOUNDING −500 from Lisbon, +500 to her; worth 500 < 20 % → one pass gives one gift of 5,000:
--       purse 5,500, CAPITAL_GIFT −5,000 at Lisbon, one row, one event, the ledger row naming it; a second pass in the
--       same hour gives none; the Town Hall serves the gift, her card serves it as her last.
--   (c) LIT, THE CAPITAL SHORT: Lisbon 2,000 above its reserve, a probe Portuguese harbour 10^12 above its own (the
--       richest of the realm) → CROWN_CALL −3,000 there, +3,000 at Lisbon, then the gift; called_from = that harbour.
--   (d) LIT, THE REALM SHORT: a probe merchant of capital 10^13 (no realm holds it) → no gift, no money moved, one
--       GIFT_WAITING event; asked again, still one.
--   (e) LIT, A FOUNDING THE REALM CANNOT PAY: 10^13 of starting money, a probe harbour outside the realm 10^14 above
--       its reserve (the world's richest) → it pays FOUNDING −10^13; the house is founded.
--   (f) DARK: a merchant founded with 500 → no FOUNDING flow (credit, as today), ledger FOUNDING +500; the pass answers
--       null; no gift row; the Town Hall serves no `gifts` key and her card no `last_gift`.
--   Nothing time-windowed depends on the hour of day (the pass's windows are relative to the probe's own p_now); no
--   table that grows on production is counted or summed against a remembered figure; nothing is DELETEd from an
--   append-only table; no `set role`; npc_tend_houses / tick_reconcile are never RUN here (their passes reach every
--   real merchant) — the pass is called for the probe company alone.
-- ROLLBACK (forward): reverse the seven hunks (each OLD text is here verbatim); drop the six functions and four knobs.
-- VERSION: 0234 = 0233 (E3) + 1 (numbered by the coordinator: 0231, 0232, 0233 deploy first).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '5min', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regprocedure('public.economy_closed()') is null or to_regclass('public.capital_gifts') is null
     or not exists (select 1 from public.world_config where key = 'merchant_broke_pct') then
    raise exception '0234 refuses: 0228 / 0229 (E1, E2) is not in this world';
  end if;
  if to_regprocedure('public.city_pays(uuid,uuid,text,bigint,uuid)') is null or to_regprocedure('public.fleet_stock_at_cost(uuid)') is null
     or to_regprocedure('public.npc_tend_houses(timestamptz)') is null or to_regprocedure('world.npc_fleet_card(uuid)') is null then
    raise exception '0234 refuses: 0122 / 0129 / 0137 / 0099 is not in this world';
  end if;
  if to_regprocedure('public.capital_pays(uuid,uuid,uuid,text,bigint,uuid,boolean,jsonb)') is not null then
    raise exception '0234 refuses: public.capital_pays already exists — this has been applied once';
  end if;
  if public.economy_closed() then
    raise exception '0234 refuses: the economy is already closed — this slice ships dark';
  end if;
end $guard$;

create or replace function pg_temp.occurs_0234(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 0. THE PRE-IMAGES (LF-normalised) ───────────────────────────────────────────────────────────
create temp table defs_before_0234 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('public.npc_tend_houses(timestamptz)'),
               ('public.new_house(uuid,text,text,text,text,text,text,bigint,boolean)'),
               ('public.npc_fix_hull_skills(uuid)'),
               ('world.town_hall(uuid)'),
               ('world.npc_fleet_card(uuid)')) f(fn);

create temp table before_0234 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points;

-- ── 1. THE KNOBS ────────────────────────────────────────────────────────────────────────────────
insert into public.world_config (key, value, description) values
  ('gift_max_per_hour', to_jsonb(50),
   '0234 (docs/CLOSED_ECONOMY.md §5.2): at most this many merchant companies are given a capital gift in one hourly pass (public.capital_gift_pass), gifted longest ago first.'),
  ('gift_max_per_week', to_jsonb(3),
   '0234: a merchant company is given at most this many capital gifts in seven days.'),
  ('gift_cooldown_hours', to_jsonb(24),
   '0234: hours after a capital gift before the same company can be given another (and between two GIFT_WAITING events).'),
  ('town_hall_gifts_max', to_jsonb(10),
   '0234: how many of a capital''s newest gifts the Town Hall lists (world.town_hall `gifts`).');

-- ── 2. WHAT A MERCHANT HOUSE IS WORTH (0203's reader, restored: 0213 dropped it with the refound) ─
create function public.npc_worth(p_player uuid)
returns bigint
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0203 / 0234: her purse and the cargo in her merchants' holds at what it cost (public.fleet_stock_at_cost, the
  -- basis her BUY budget counts as hers). Read by public.capital_gift_pass: a house is BROKE when THIS is under
  -- merchant_broke_pct × her capital, never because she has just bought her parcels.
  select coalesce((select pl.ducats from public.players pl where pl.id = p_player), 0)
       + coalesce((select sum(public.fleet_stock_at_cost(nf.fleet_id)) from public.npc_fleets nf where nf.player_id = p_player), 0)::bigint
$$;
comment on function public.npc_worth(uuid) is
  '0234 (0203''s body): a merchant house''s purse + her cargo at cost. Read by public.capital_gift_pass. Server-only.';
revoke all on function public.npc_worth(uuid) from public, anon, authenticated;

-- ── 3. THE ONE WAY A CAPITAL PAYS A COMPANY ─────────────────────────────────────────────────────
create function public.capital_pays(p_capital uuid, p_nation uuid, p_player uuid, p_kind text, p_amount bigint,
                                    p_event uuid default null, p_must boolean default false, p_note jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0234 (docs/CLOSED_ECONOMY.md §5.2, §5.4): the capital p_capital pays p_amount to the company p_player, of the
-- country p_nation. From what it holds above its reserve; the gap called (CROWN_CALL) from the realm's harbour with
-- the largest surplus. Realm short: {waiting, gap} and nothing moves — unless p_must (a founding), when the world's
-- richest harbour pays it whole, and if even that cannot, the plain credit of before ({minted}).
-- p_note {kind, payload}: once the payer is known, the event is written here (its payload + called_from, the realm
-- harbour's code or null) and the payment names it — events are append-only, so it is written once, complete.
-- Answers {paid, port, called_from, called, event}. LOCKS: the house first (city_pays's order), then the realm harbour
-- before its capital (city_day's order).
declare
  v_payer  uuid := p_capital;
  v_from   uuid;
  v_gap    bigint := 0;
  v_called bigint := 0;
  v_ev     uuid := p_event;
begin
  if coalesce(p_amount, 0) <= 0 then
    raise exception 'capital_pays(): the amount must be positive, not %', p_amount;
  end if;
  perform 1 from public.players where id = p_player for update;
  if v_payer is not null then
    v_gap := p_amount - least(p_amount, greatest(0, public.city_surplus(v_payer)));
    if v_gap > 0 then
      select h.id into v_from
        from public.ports h join public.port_treasury t on t.port_id = h.id
       where h.kind = 'HARBOUR' and h.id <> v_payer and public.port_nation(h.id) = p_nation
       order by public.city_surplus(h.id) desc, h.code
       limit 1;
      if v_from is not null then
        perform public.treasury_lock(v_from);
        perform public.treasury_lock(v_payer);
        v_gap := p_amount - least(p_amount, greatest(0, public.city_surplus(v_payer)));   -- again, under the locks
        if v_gap > 0 and public.city_surplus(v_from) >= v_gap then
          perform public.treasury_post(v_from, 'CROWN_CALL', -v_gap, null, null);
          perform public.treasury_post(v_payer, 'CROWN_CALL', v_gap, null, null);
          v_called := v_gap;
        end if;
      end if;
      if v_gap > v_called then
        if not p_must then
          return jsonb_build_object('waiting', true, 'port', v_payer, 'gap', v_gap);
        end if;
        v_payer := null;
      end if;
    end if;
  end if;
  if v_payer is null then
    -- a founding the realm cannot pay (or a country with no capital): the world's richest harbour pays it whole
    select h.id into v_payer
      from public.ports h join public.port_treasury t on t.port_id = h.id
     where h.kind = 'HARBOUR'
     order by public.city_surplus(h.id) desc, h.code
     limit 1;
    if v_payer is null or public.city_surplus(v_payer) < p_amount then
      perform public.credit(p_player, p_kind, p_amount, v_ev);   -- never block a sign-up (E7's guard judges this)
      return jsonb_build_object('minted', true, 'paid', p_amount);
    end if;
    v_from := null;
    v_called := 0;
  end if;
  if p_note is not null then
    v_ev := public.emit_event(p_player, p_note->>'kind', coalesce(p_note->'payload', '{}'::jsonb) || jsonb_build_object(
              'called_from', case when v_called > 0 then (select p.code from public.ports p where p.id = v_from) end));
  end if;
  perform public.city_pays(v_payer, p_player, p_kind, p_amount, v_ev);
  return jsonb_build_object('paid', p_amount, 'port', v_payer,
                            'called_from', case when v_called > 0 then v_from end, 'called', v_called, 'event', v_ev);
end $$;
comment on function public.capital_pays(uuid, uuid, uuid, text, bigint, uuid, boolean, jsonb) is
  '0234: THE one way a capital pays a company (a capital gift, starting money): from its surplus, the gap called from its realm''s richest harbour (CROWN_CALL); realm short → {waiting} unless p_must (then the world''s richest harbour). Server-only.';
revoke all on function public.capital_pays(uuid, uuid, uuid, text, bigint, uuid, boolean, jsonb) from public, anon, authenticated;

-- ── 4. STARTING MONEY: credit's drop-in ─────────────────────────────────────────────────────────
create function public.founding_credit(p_player uuid, p_kind text, p_delta bigint, p_ref_event uuid default null)
returns bigint
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0234 (docs/CLOSED_ECONOMY.md §5.4): a company's starting money. Open (or the purses dark), it IS public.credit —
-- the same call, the same ledger row, the same answer. Closed, the company's country's capital pays it
-- (public.capital_pays, must: a sign-up is never blocked). Answers the purse after, as credit does.
declare
  v_nation uuid;
  v_cap    uuid;
begin
  if not public.economy_closed() or not public.city_treasury_on() or coalesce(p_delta, 0) <= 0 then
    return public.credit(p_player, p_kind, p_delta, p_ref_event);
  end if;
  select n.id, cp.id into v_nation, v_cap
    from public.players pl
    left join public.nations n on n.id = pl.nation_id
    left join public.ports cp on cp.code = n.capital_port_code and cp.kind = 'HARBOUR'
   where pl.id = p_player;
  perform public.capital_pays(v_cap, v_nation, p_player, p_kind, p_delta, p_ref_event, true);
  return (select pl.ducats from public.players pl where pl.id = p_player);
end $$;
comment on function public.founding_credit(uuid, text, bigint, uuid) is
  '0234: starting money — public.credit while the economy is open; closed, paid by the company''s country''s capital (public.capital_pays). Server-only.';
revoke all on function public.founding_credit(uuid, text, bigint, uuid) from public, anon, authenticated;

-- ── 5. THE HOURLY GIFT ──────────────────────────────────────────────────────────────────────────
create function public.capital_gift_pass(p_now timestamptz, p_only uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0234 (docs/CLOSED_ECONOMY.md §5.2): null while the economy is open. Lit: every broke merchant company (worth under
-- merchant_broke_pct × capital; none in the last gift_cooldown_hours; under gift_max_per_week in 7 days), at most
-- gift_max_per_hour of them, gifted longest ago (or never) first, is paid her capital by her country's capital
-- (public.capital_pays). Each company in its own sub-transaction: one that fails is counted and noted, the rest go on.
-- Answers {gifted, gift_ducats, gift_waiting, failed, notes}. p_only narrows the pass to one company (a probe).
declare
  v_pct   numeric;
  v_cool  interval;
  r       record;
  v_res   jsonb;
  v_n     int := 0;
  v_d     bigint := 0;
  v_wait  int := 0;
  v_fail  int := 0;
  v_notes jsonb := '[]'::jsonb;
begin
  if not public.economy_closed() then
    return null;
  end if;
  v_pct  := public.wc_num('merchant_broke_pct');
  v_cool := make_interval(hours => public.wc_int('gift_cooldown_hours'));
  for r in
    select h.player_id, h.capital, pl.nation_id, w.worth, cp.id as cap_id, cp.code as cap_code, cp.name as cap_name
      from public.npc_houses h
      join public.players pl on pl.id = h.player_id and pl.is_npc
      left join public.nations n on n.id = pl.nation_id
      left join public.ports cp on cp.code = n.capital_port_code and cp.kind = 'HARBOUR'
      cross join lateral (select public.npc_worth(h.player_id) as worth) w
     where (p_only is null or h.player_id = p_only)
       and pl.ducats < h.capital * v_pct               -- her purse alone is under the line (worth ≥ purse): the cheap test first
       and w.worth < h.capital * v_pct
       and not exists (select 1 from public.capital_gifts g where g.player_id = h.player_id
                         and g.created_at > p_now - v_cool and g.created_at <= p_now)
       and (select count(*) from public.capital_gifts g where g.player_id = h.player_id
              and g.created_at > p_now - interval '7 days' and g.created_at <= p_now) < public.wc_int('gift_max_per_week')
     order by (select max(g.created_at) from public.capital_gifts g where g.player_id = h.player_id) nulls first,
              w.worth::numeric / h.capital, h.player_id
     limit public.wc_int('gift_max_per_hour')
  loop
    continue when r.cap_id is null;   -- a country with no capital gives nothing
    begin
      v_res := public.capital_pays(r.cap_id, r.nation_id, r.player_id, 'CAPITAL_GIFT', r.capital, null, false,
                 jsonb_build_object('kind', 'CAPITAL_GIFT', 'payload', jsonb_build_object(
                   'port', r.cap_code, 'port_name', r.cap_name, 'ducats', r.capital, 'worth', r.worth)));
      if v_res ? 'waiting' then
        raise exception using errcode = 'ZG234', message = (v_res->>'gap');
      end if;
      insert into public.capital_gifts (port_id, player_id, ducats, called_from, created_at)
      values (r.cap_id, r.player_id, r.capital, (v_res->>'called_from')::uuid, p_now);
      v_n := v_n + 1;
      v_d := v_d + r.capital;
    exception
      when sqlstate 'ZG234' then
        -- THE REALM CANNOT PAY: no money moved, no event written; one GIFT_WAITING a day
        v_wait := v_wait + 1;
        if not exists (select 1 from public.events e where e.player_id = r.player_id and e.kind = 'GIFT_WAITING'
                         and e.created_at > p_now - v_cool) then
          perform public.emit_event(r.player_id, 'GIFT_WAITING', jsonb_build_object(
            'port', r.cap_code, 'port_name', r.cap_name, 'ducats', r.capital, 'worth', r.worth, 'gap', sqlerrm::bigint));
        end if;
      when others then
        v_fail := v_fail + 1;
        v_notes := v_notes || jsonb_build_array(jsonb_build_object('step', 'capital_gift', 'player', r.player_id, 'error', sqlerrm));
    end;
  end loop;
  return jsonb_build_object('gifted', v_n, 'gift_ducats', v_d, 'gift_waiting', v_wait, 'failed', v_fail, 'notes', v_notes);
end $$;
comment on function public.capital_gift_pass(timestamptz, uuid) is
  '0234: the hourly capital gift to broke merchant companies (docs/CLOSED_ECONOMY.md §5.2) — null while the economy is open. Called by public.npc_tend_houses. Server-only.';
revoke all on function public.capital_gift_pass(timestamptz, uuid) from public, anon, authenticated;

-- ── 6. THE TWO READS' NEW KEYS (served only when there is a gift to show) ───────────────────────
create function public.town_hall_gifts(p_port uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0234: {gifts: the capital's newest town_hall_gifts_max gifts} — or {} when this city never gave one.
  select case when x.gifts is null then '{}'::jsonb else jsonb_build_object('gifts', x.gifts) end
    from (select jsonb_agg(jsonb_build_object('name', g.company_name, 'ducats', g.ducats, 'at', g.created_at,
                                              'called_from', g.called) order by g.created_at desc, g.id desc) as gifts
            from (select c.id, c.ducats, c.created_at, pl.company_name, cf.code as called
                    from public.capital_gifts c
                    join public.players pl on pl.id = c.player_id
                    left join public.ports cf on cf.id = c.called_from
                   where c.port_id = p_port
                   order by c.created_at desc, c.id desc
                   limit public.wc_int('town_hall_gifts_max')) g) x
$$;
comment on function public.town_hall_gifts(uuid) is
  '0234: world.town_hall''s `gifts` key (a capital''s newest gifts: name, ducats, at, called_from), or {} when it gave none. Server-only.';
revoke all on function public.town_hall_gifts(uuid) from public, anon, authenticated;

create function public.npc_last_gift(p_player uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0234: {last_gift: her newest capital gift — port, name, ducats, at} — or {} when she was never given one.
  select coalesce((select jsonb_build_object('last_gift', jsonb_build_object('port', p.code, 'name', p.name,
                                                                              'ducats', c.ducats, 'at', c.created_at))
                     from public.capital_gifts c join public.ports p on p.id = c.port_id
                    where c.player_id = p_player
                    order by c.created_at desc, c.id desc
                    limit 1), '{}'::jsonb)
$$;
comment on function public.npc_last_gift(uuid) is
  '0234: world.npc_fleet_card''s company `last_gift` key (port, name, ducats, at), or {} when she was never given one. Server-only.';
revoke all on function public.npc_last_gift(uuid) from public, anon, authenticated;

-- ── 7. THE HUNKS (each occurs exactly once in the live body) ─────────────────────────────────────
create temp table hunks_0234 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0234 values
('public.npc_tend_houses(timestamptz)', 1,
$h$  v_notes   jsonb := '[]'::jsonb;
$h$,
$h$  v_notes   jsonb := '[]'::jsonb;
  v_gifts   jsonb;   -- 0234 (E4): the capital's gift pass — null while the economy is open
$h$),
('public.npc_tend_houses(timestamptz)', 2,
$h$  -- 0213: NO REFOUND. A merchant$h$,
$h$  -- 0234 (E4, docs/CLOSED_ECONOMY.md §5.2): THE CAPITAL'S GIFT — a broke merchant is given her starting money by
  -- her country's capital (public.capital_gift_pass, which answers null while the economy is open).
  if v_on then
    v_gifts := public.capital_gift_pass(p_now);
    v_failed := v_failed + coalesce((v_gifts->>'failed')::int, 0);
    v_notes := v_notes || coalesce(v_gifts->'notes', '[]'::jsonb);
  end if;

  -- 0213: NO REFOUND. A merchant$h$),
('public.npc_tend_houses(timestamptz)', 3,
$h$                            'failed', v_failed, 'deferred', v_deferred, 'notes', v_notes);
$h$,
$h$                            'failed', v_failed, 'deferred', v_deferred, 'notes', v_notes)
         || coalesce(v_gifts - 'failed' - 'notes', '{}'::jsonb);   -- 0234 (E4): gifted, gift_ducats, gift_waiting — lit only
$h$),
('public.new_house(uuid,text,text,text,text,text,text,bigint,boolean)', 1,
$h$  perform public.credit(v_player, 'FOUNDING', v_start,
$h$,
$h$  perform public.founding_credit(v_player, 'FOUNDING', v_start,   -- 0234 (E4): closed, her country's capital pays it
$h$),
('public.npc_fix_hull_skills(uuid)', 1,
$h$      perform public.credit(p_player, 'FOUNDING', v_cost);
$h$,
$h$      perform public.founding_credit(p_player, 'FOUNDING', v_cost);   -- 0234 (E4): closed, her country's capital pays it
$h$),
('world.town_hall(uuid)', 1,
$h$    'influence', world.town_hall_influence(p_port, v_player));
$h$,
$h$    'influence', world.town_hall_influence(p_port, v_player))
    -- 0234 (E4): the capital's gifts to broke merchants, newest first — served only once it has given one.
    || public.town_hall_gifts(p_port);
$h$),
('world.npc_fleet_card(uuid)', 1,
$h$                             where i.player_id = p.id and i.points > 0) x)),
$h$,
$h$                             where i.player_id = p.id and i.points > 0) x))
      -- 0234 (E4): her newest capital gift — `From Lisbon 5,000` — served only once she has been given one.
      || public.npc_last_gift(p.id),
$h$);

create or replace function pg_temp.recut_0234(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := (select def from defs_before_0234 where fn = p_fn);
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0234 where fn = p_fn order by n loop
    v_n := pg_temp.occurs_0234(v_def, h.old);
    if v_n <> 1 then
      raise exception '0234 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0234(fn) from defs_before_0234 order by fn;

-- ── 8. THE PROBE'S TOOLS ────────────────────────────────────────────────────────────────────────
-- A harbour's live purse set to its reserve + p_above (a probe flow, rolled back with the probe).
create or replace function pg_temp.above_0234(p_port uuid, p_above bigint)
returns void
language plpgsql
as $$
begin
  perform public.treasury_post(p_port, 'PROBE_0234',
    coalesce((select t.reserve from public.port_treasury t where t.port_id = p_port), 0) + p_above - public.treasury_balance(p_port),
    null, null);
end $$;

-- A probe merchant company of Portugal at Lisbon: founded with p_purse, her capital p_capital.
create or replace function pg_temp.merchant_0234(p_name text, p_capital bigint, p_purse bigint)
returns uuid
language plpgsql
as $$
declare
  v_m uuid;
begin
  if exists (select 1 from public.players p where p.company_name = p_name) then
    raise exception '0234 self-assert FAIL: the probe house % already exists', p_name;
  end if;
  v_m := public.new_house(null, p_name, 'PRT', 'LIS', p_ducats => p_purse, p_is_npc => true);
  insert into public.npc_houses (player_id, roster_ord, ink, blurb, master, home_port_id, capital, patience, wares)
  values (v_m, (select coalesce(max(h.roster_ord), 0) + 1 from public.npc_houses h), 'prt',
          'A probe house of 0234, rolled back.', 'Mestre da Prova', (select p.id from public.ports p where p.code = 'LIS'),
          p_capital, 0.1, '{}');
  return v_m;
end $$;

-- What a probe wrote, since the mark: flows (port code, kind, ducats, by id; probe flows left out), and a company's
-- purse, ledger (by kind), events (kind → payloads) and gift rows.
create or replace function pg_temp.seen_0234(p_mark bigint, p_m uuid)
returns jsonb
language sql
as $$
  select jsonb_build_object(
    'flows', coalesce((select jsonb_agg(jsonb_build_array(p.code, f.kind, f.ducats) order by f.id)
                         from public.treasury_flows f join public.ports p on p.id = f.port_id
                        where f.id > p_mark and f.created_at = now() and f.kind <> 'PROBE_0234'), '[]'::jsonb),
    'purse', (select pl.ducats from public.players pl where pl.id = p_m),
    'ledger', coalesce((select jsonb_agg(jsonb_build_array(l.kind, l.ducats_delta, l.ref_event_id is not null) order by l.kind, l.ducats_delta)
                          from public.ledger l where l.player_id = p_m), '[]'::jsonb),
    'events', coalesce((select jsonb_object_agg(e.kind, e.ps) from (select e.kind, jsonb_agg(e.payload order by e.payload::text) as ps
                          from public.events e where e.player_id = p_m and e.kind in ('CAPITAL_GIFT', 'GIFT_WAITING') group by e.kind) e), '{}'::jsonb),
    'gifts', coalesce((select jsonb_agg(jsonb_build_array(p.code, g.ducats, cf.code, g.created_at = now()) order by g.id)
                         from public.capital_gifts g join public.ports p on p.id = g.port_id left join public.ports cf on cf.id = g.called_from
                        where g.player_id = p_m), '[]'::jsonb),
    'gift_event_linked', exists (select 1 from public.ledger l join public.events e on e.id = l.ref_event_id
                                  where l.player_id = p_m and l.kind = 'CAPITAL_GIFT' and e.kind = 'CAPITAL_GIFT'))
$$;

-- ── 9. THE SELF-ASSERT ──────────────────────────────────────────────────────────────────────────
do $$
declare
  v_before record;
  v_d record; v_h record; v_pp record; v_def text;
  v_mark   bigint := (select coalesce(max(f.id), 0) from public.treasury_flows f);
  v_lis    uuid := (select p.id from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR');
  v_prt    uuid := (select n.id from public.nations n where n.code = 'PRT');
  v_h1     uuid; v_h1code text;   -- a harbour of Portugal's realm (not Lisbon)
  v_w      uuid; v_wcode text;    -- a harbour outside the realm
  v_m      uuid; v_f uuid;
  v_r1     jsonb; v_r2 jsonb;
  v_s      jsonb;
  v_hall   jsonb; v_card jsonb;
  v_out    jsonb := '{}'::jsonb;
  v_big    constant bigint := 10000000000000;   -- 10^13
begin
  select * into v_before from before_0234;

  -- (a) THE RE-CUTS reverse to their pre-images; ACL / volatility / definer / config unmoved
  for v_d in select * from defs_before_0234 loop
    v_def := replace(pg_get_functiondef(v_d.fn::regprocedure), E'\r', '');
    for v_h in select * from hunks_0234 where fn = v_d.fn order by n desc loop
      if pg_temp.occurs_0234(v_def, v_h.new) <> 1 then
        raise exception '0234 self-assert FAIL: hunk % of % is not in the new body exactly once', v_h.n, v_d.fn;
      end if;
      v_def := replace(v_def, v_h.new, v_h.old);
    end loop;
    if v_def <> v_d.def then
      raise exception '0234 self-assert FAIL: % does not reverse to its pre-image', v_d.fn;
    end if;
    select coalesce(p.proacl::text, '') as acl, p.provolatile as vol, p.prosecdef as secdef, coalesce(p.proconfig::text, '') as cfg
      into v_pp from pg_proc p where p.oid = v_d.fn::regprocedure;
    if v_pp.acl <> v_d.acl or v_pp.vol <> v_d.vol or v_pp.secdef <> v_d.secdef or v_pp.cfg <> v_d.cfg then
      raise exception '0234 self-assert FAIL: % changed its ACL, volatility, definer or config', v_d.fn;
    end if;
  end loop;
  if exists (select 1 from (values ('public.npc_worth(uuid)'), ('public.capital_pays(uuid,uuid,uuid,text,bigint,uuid,boolean,jsonb)'),
                                   ('public.founding_credit(uuid,text,bigint,uuid)'), ('public.capital_gift_pass(timestamptz,uuid)'),
                                   ('public.town_hall_gifts(uuid)'), ('public.npc_last_gift(uuid)')) f(fn)
              where has_function_privilege('authenticated', f.fn, 'execute') or has_function_privilege('anon', f.fn, 'execute')) then
    raise exception '0234 self-assert FAIL: a client role can execute a server-only function';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> v_before.entry_points then
    raise exception '0234 self-assert FAIL: the registry moved';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0234 self-assert FAIL: a wall moved';
  end if;

  select p.id, p.code into v_h1, v_h1code from public.ports p join public.port_treasury t on t.port_id = p.id
   where p.kind = 'HARBOUR' and p.id <> v_lis and public.port_nation(p.id) = v_prt order by p.code limit 1;
  select p.id, p.code into v_w, v_wcode from public.ports p join public.port_treasury t on t.port_id = p.id
   where p.kind = 'HARBOUR' and public.port_nation(p.id) is distinct from v_prt order by p.code limit 1;
  if v_lis is null or v_prt is null or v_h1 is null or v_w is null
     or (select n.capital_port_code from public.nations n where n.id = v_prt) <> 'LIS' then
    raise exception '0234 self-assert FAIL: no Lisbon capital of Portugal, no other harbour of its realm, or none outside it';
  end if;

  -- (b) LIT, THE CAPITAL PAYS — and the founding is Lisbon's, and the two reads serve the gift
  begin
    update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed', 'npc_traders_enabled', 'standing_routes_enabled');
    perform pg_temp.above_0234(v_lis, 1000000);
    v_m := pg_temp.merchant_0234('Casa da Dádiva 0234', 5000, 500);
    v_r1 := public.capital_gift_pass(now(), v_m);
    v_r2 := public.capital_gift_pass(now(), v_m);
    v_s := pg_temp.seen_0234(v_mark, v_m);
    v_hall := world.town_hall(v_lis);
    select f.id into v_f from public.fleets f where f.player_id = v_m order by f.id limit 1;
    v_card := world.npc_fleet_card(v_f);
    raise exception using errcode = 'ZX234', message = jsonb_build_object('r1', v_r1, 'r2', v_r2, 's', v_s,
      'hall', v_hall->'gifts'->0, 'card', v_card->'company'->'last_gift')::text;
  exception when sqlstate 'ZX234' then
    v_s := sqlerrm::jsonb;
  end;
  if (v_s->'r1'->>'gifted')::int <> 1 or (v_s->'r1'->>'gift_ducats')::bigint <> 5000 or (v_s->'r2'->>'gifted')::int <> 0
     or (v_s->'s'->>'purse')::bigint <> 5500
     or v_s->'s'->'flows' <> '[["LIS", "FOUNDING", -500], ["LIS", "CAPITAL_GIFT", -5000]]'::jsonb
     or v_s->'s'->'ledger' <> '[["CAPITAL_GIFT", 5000, true], ["FOUNDING", 500, true]]'::jsonb
     or v_s->'s'->'gifts' <> '[["LIS", 5000, null, true]]'::jsonb
     or jsonb_array_length(v_s->'s'->'events'->'CAPITAL_GIFT') <> 1 or v_s->'s'->'events' ? 'GIFT_WAITING'
     or (v_s->'s'->'events'->'CAPITAL_GIFT'->0) - 'port_name' <> '{"port": "LIS", "ducats": 5000, "worth": 500, "called_from": null}'::jsonb
     or v_s->'s'->'events'->'CAPITAL_GIFT'->0->>'port_name' is null
     or not (v_s->'s'->>'gift_event_linked')::boolean
     or v_s->'hall'->>'name' <> 'Casa da Dádiva 0234' or (v_s->'hall'->>'ducats')::bigint <> 5000 or v_s->'hall'->>'called_from' is not null
     or v_s->'card'->>'port' <> 'LIS' or (v_s->'card'->>'ducats')::bigint <> 5000 then
    raise exception '0234 self-assert FAIL: lit, the capital did not pay one gift of 5,000 (or its founding of 500, or the reads): %', v_s;
  end if;
  v_out := v_out || jsonb_build_object('b', v_s->'s'->'flows');

  -- (c) LIT, THE CAPITAL SHORT: the gap is called from the realm's richest harbour
  begin
    update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed');
    perform pg_temp.above_0234(v_lis, 1000000);
    v_m := pg_temp.merchant_0234('Casa da Dádiva 0234', 5000, 500);
    perform pg_temp.above_0234(v_lis, 2000);
    perform pg_temp.above_0234(v_h1, 1000000000000);
    v_r1 := public.capital_gift_pass(now(), v_m);
    raise exception using errcode = 'ZX234', message = jsonb_build_object('r1', v_r1, 's', pg_temp.seen_0234(v_mark, v_m))::text;
  exception when sqlstate 'ZX234' then
    v_s := sqlerrm::jsonb;
  end;
  if (v_s->'r1'->>'gifted')::int <> 1 or (v_s->'s'->>'purse')::bigint <> 5500
     or v_s->'s'->'flows' <> jsonb_build_array(jsonb_build_array('LIS', 'FOUNDING', -500), jsonb_build_array(v_h1code, 'CROWN_CALL', -3000),
                                               jsonb_build_array('LIS', 'CROWN_CALL', 3000), jsonb_build_array('LIS', 'CAPITAL_GIFT', -5000))
     or v_s->'s'->'gifts' <> jsonb_build_array(jsonb_build_array('LIS', 5000, v_h1code, true))
     or v_s->'s'->'events'->'CAPITAL_GIFT'->0->>'called_from' is distinct from v_h1code then
    raise exception '0234 self-assert FAIL: lit, a capital 2,000 above its reserve did not call 3,000 from % and give: %', v_h1code, v_s;
  end if;
  v_out := v_out || jsonb_build_object('c', v_s->'s'->'flows');

  -- (d) LIT, THE REALM SHORT: no gift, no money, one GIFT_WAITING (asked twice)
  begin
    update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed');
    perform pg_temp.above_0234(v_lis, 1000000);
    v_m := pg_temp.merchant_0234('Casa da Dádiva 0234', v_big, 500);
    perform pg_temp.above_0234(v_lis, 0);
    v_r1 := public.capital_gift_pass(now(), v_m);
    v_r2 := public.capital_gift_pass(now(), v_m);
    raise exception using errcode = 'ZX234', message = jsonb_build_object('r1', v_r1, 'r2', v_r2, 's', pg_temp.seen_0234(v_mark, v_m))::text;
  exception when sqlstate 'ZX234' then
    v_s := sqlerrm::jsonb;
  end;
  if (v_s->'r1'->>'gifted')::int <> 0 or (v_s->'r1'->>'gift_waiting')::int <> 1 or (v_s->'r2'->>'gift_waiting')::int <> 1
     or (v_s->'s'->>'purse')::bigint <> 500
     or v_s->'s'->'flows' <> '[["LIS", "FOUNDING", -500]]'::jsonb
     or v_s->'s'->'gifts' <> '[]'::jsonb or v_s->'s'->'events' ? 'CAPITAL_GIFT'
     or jsonb_array_length(v_s->'s'->'events'->'GIFT_WAITING') <> 1
     or (v_s->'s'->'events'->'GIFT_WAITING'->0->>'ducats')::bigint <> v_big then
    raise exception '0234 self-assert FAIL: lit, a gift no realm can pay moved money or did not wait once: %', v_s;
  end if;

  -- (e) LIT, A FOUNDING THE REALM CANNOT PAY: the world's richest harbour pays it whole
  begin
    update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed');
    perform pg_temp.above_0234(v_lis, 0);
    perform pg_temp.above_0234(v_w, 100000000000000);
    v_m := pg_temp.merchant_0234('Casa da Dádiva 0234', 5000, v_big);
    raise exception using errcode = 'ZX234', message = jsonb_build_object('s', pg_temp.seen_0234(v_mark, v_m))::text;
  exception when sqlstate 'ZX234' then
    v_s := sqlerrm::jsonb;
  end;
  if (v_s->'s'->>'purse')::bigint <> v_big
     or v_s->'s'->'flows' <> jsonb_build_array(jsonb_build_array(v_wcode, 'FOUNDING', -v_big)) then
    raise exception '0234 self-assert FAIL: lit, a founding of 10^13 was not paid whole by the world''s richest harbour %: %', v_wcode, v_s;
  end if;

  -- (f) DARK: the founding is credit as today; no gift; the reads serve no new key
  begin
    update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'npc_traders_enabled', 'standing_routes_enabled');
    perform pg_temp.above_0234(v_lis, 1000000);
    v_m := pg_temp.merchant_0234('Casa da Dádiva 0234', 5000, 500);
    v_r1 := public.capital_gift_pass(now(), v_m);
    select f.id into v_f from public.fleets f where f.player_id = v_m order by f.id limit 1;
    raise exception using errcode = 'ZX234', message = jsonb_build_object('r1', v_r1, 's', pg_temp.seen_0234(v_mark, v_m),
      'hall_gifts', world.town_hall(v_lis) ? 'gifts', 'card_gift', world.npc_fleet_card(v_f)->'company' ? 'last_gift')::text;
  exception when sqlstate 'ZX234' then
    v_s := sqlerrm::jsonb;
  end;
  if v_s->'r1' <> 'null'::jsonb or (v_s->'s'->>'purse')::bigint <> 500
     or v_s->'s'->'flows' <> '[]'::jsonb or v_s->'s'->'ledger' <> '[["FOUNDING", 500, true]]'::jsonb
     or v_s->'s'->'gifts' <> '[]'::jsonb or v_s->'s'->'events' <> '{}'::jsonb
     or (v_s->>'hall_gifts')::boolean or (v_s->>'card_gift')::boolean then
    raise exception '0234 self-assert FAIL: dark, the founding, the pass or a read moved: %', v_s;
  end if;

  -- nothing of the probe survives
  if exists (select 1 from public.players p where p.company_name = 'Casa da Dádiva 0234')
     or exists (select 1 from public.treasury_flows f where f.id > v_mark and f.created_at = now())
     or public.economy_closed() then
    raise exception '0234 self-assert FAIL: the probe left rows behind';
  end if;

  raise notice '0234 self-assert ok: A CAPITAL GIVES. npc_tend_houses ×3, new_house, npc_fix_hull_skills, town_hall, npc_fleet_card re-cut, each reversed, ACL unmoved; six new functions server-only; registry unchanged; walls 0. LIT: Lisbon paid the probe merchant''s founding 500 and one gift of 5,000 (second pass: none), the Town Hall and her card serve it — flows %; Lisbon 2,000 above its reserve called 3,000 from % — flows %; a gift of 10^13 no realm holds waited (one GIFT_WAITING, asked twice), no money moved; a founding of 10^13 was paid whole by the world''s richest harbour %. DARK: founding by credit, the pass null, no gift, no new key on either read. Rolled back.',
    v_out->'b', v_h1code, v_out->'c', v_wcode;
end $$;
