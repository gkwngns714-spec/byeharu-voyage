-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0488 - A HARBOUR IS ASKED ONCE  (no switch; the same answers: the HQ best-sales read asks each harbour's quote terms, dock fee terms and
--        profit tax rate once a read, not once for every good and every row; and her captains' share of the spread once a good, not once a quote)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE WORK: docs/dev-log/2026-11-24-harbour-reuse.md; harness scripts/ops/harness/harbour-reuse/ (before-0488.sql, after-0488.sql);
--   proof 191 (scripts/db/proofs/191_a_harbour_is_asked_once.sql) turns the six bodies back and compares again.
--
-- WHY: 0487 took world.best_sales at Lisbon on prod from 2,555 ms (cut by its 2.5 s budget) to 1,777-1,957 ms (not cut). What is left is
--   the CPU of many small calls. A Lisbon read prices about 150 sale rows over its 10 goods, but only about 57 harbours: every row asked the
--   harbour's quote terms again (world.quote -> world.quote_terms: the port's spread, her standing among its givers, the city's bid factor),
--   every harbour called at asked public.port_fee's terms again (the gate, two knobs, the country, regard, logbook and home factors), and every
--   row sold at a profit asked world.tax_rate again. And every quote asked her captains' share of the spread (public.crew_pct twice), which
--   depends only on the good. Traced on the chain (0487's probe, prod's switches lit), a Lisbon read: 168 quote terms (55 ms of 400 locally),
--   271 dock fees (40 ms), 127 tax rates (15 ms), 336 crew_pct (30 ms).
--
-- WHAT (DECIDED BY DEFAULT; the owner may reverse it):
--   THE READS AND THE ARITHMETIC ARE SPLIT, EACH ONCE, so a reader may hand over what it already read (the 0169 pattern: world.quote_priced
--   takes a quay's terms handed over). Nine server-only functions, new (revoked from public, anon, authenticated and service_role):
--     world.spread_parts(port, fleet)        the harbour's reads of the spread: {world.spread, public.investor_shave (0 with no house)}
--     world.spread_purser(fleet, good)       her captains' share: public.crew_pct 'spread' + 'category_spread' (0 with no fleet)
--     world.spread_pair_from(..., parts, purser)  world.spread_effective_pair's arithmetic (her bargain, the floor), moved there whole
--     world.quote_quay(port, fleet)          the harbour's reads of a quote: spread_parts || {the tax a quote carries, public.city_bid_factor}
--     world.quote_terms_from(..., quay, purser)   world.quote_terms' arithmetic (the bid factor times her mastery), moved there whole
--     public.port_fee_terms(port, player)    public.port_fee's gate and terms (null: no fee) {base, pct, country, regard, logbook, home}
--     public.port_fee_of(terms, value)       public.port_fee's arithmetic, moved there whole
--     public.profit_tax_at(on, profit, rate) public.profit_tax's arithmetic, moved there whole
--     world.board_sell_memo(good, fleet, ctx, memo, OUT o_rows, OUT o_memo)   world.board_sell's body, moved there whole, with the memo
--   SIX BODIES RE-CUT (asserted against the md5 of the body this file was written against; another body refuses the whole file):
--     world.spread_effective_pair  = spread_pair_from(spread_parts, spread_purser)
--     world.quote_terms            = quote_terms_from(quote_quay, spread_purser)
--     public.port_fee              = port_fee_of(port_fee_terms, value)
--     public.profit_tax            = profit_tax_at(treasury on, profit, world.tax_rate only when it is on and the profit above 0, as before)
--     world.board_sell             = board_sell_memo(..., no memo).o_rows
--     world.best_sales             hands each good's world.board_sell_memo the memo the last one handed back (three of its four asks; the
--                                  0433 narrowing ask stays world.board_sell)
--   world.board_sell_memo is world.board_sell's live body by 11 hunks: a sold-at harbour's terms come from the memo or world.quote_quay (CTE
--   `quay`), the quote is world.quote_priced with world.quote_terms_from's terms handed over (what world.quote reads itself); a called-at
--   harbour's dock fee terms from the memo or public.port_fee_terms (`dock`); a harbour's profit tax rate from the memo or world.tax_rate
--   (`rate`, asked exactly where public.profit_tax asked it); her purser once a call. It hands back the memo with what it asked.
--   The memo is kept for one fleet and one house (a memo of another is not read) and one read (a STABLE read: one snapshot, one now()).
--   Names, arguments, return types, STABLE, SECURITY DEFINER, search path, owner and grants of the six are untouched (asserted).
--   Every other caller (the trade, the merchants, the beat, Trade's board) gets the same answers through the same arithmetic.
--
-- WHY THE SAME ANSWERS: each value is asked of the same reader with the same inputs (the harbour, her fleet, her house: fixed for the read)
--   in the same snapshot, and kept as its exact text (numeric and numeric[] text round-trips to the same value and scale). The arithmetic
--   is the old body's, moved, not rewritten: the same expressions in the same order.
--
-- THE SELF-ASSERT (one DO block; the probe rolled back by a raised sentinel):
--   THE PROBE: two houses at Lisbon, a rich one with a captain seated and a goods mastery (her purser and mastery not nought) and a poor one
--   (her purse binds: the tray's Max and the FIT rows); the switches the read reads lit for the probe (only where not already on: on prod
--   they are). BEFORE and AFTER (the re-cut tried inside the probe), compared to the byte:
--     the rich house's pieces: the quote terms and both spreads at every 32nd harbour for every good Lisbon sells, with her fleet and with
--     none; sell and buy quotes at every 32nd harbour; the dock fee (3 values) and profit tax (3 profits) at every 6th harbour for her, a
--     merchant, a crown house and nobody (proof 191 asks far more, on CI); world.board_sell for every good with the read's context; after, also world.board_sell_memo with
--     the memo threaded over the goods as best_sales threads it;
--     world.best_sales of both houses WITH ITS BUDGET TAKEN OFF (a pg_temp copy, 2.5 seconds -> 1 hour; nothing else of it moves): no
--     time-budgeted call is compared with another.
--   With switches as they are too, when any was off (on prod none is). Timed: the notice says best_sales before and after on this server.
--   Then the re-cut for real, asserted the bodies the probe tried, each hunk once and reversing, and the catalog checks. Budget 60 s.
--
-- LOAD: no rows, no tables, no cron, no beat step. 0 new rows a minute.
-- ROLLBACK (forward): a migration that writes the six bodies back (proof 191 does exactly that, inside its transaction, and compares).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

-- ── THE NEW PIECES (no reader calls them until the re-cut below) ──

create function world.spread_parts(p_port uuid, p_fleet uuid)
 returns numeric[]
 language plpgsql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
-- 0488: WHAT A QUAY'S SPREAD READS OF THE HARBOUR (out of world.spread_effective_pair, read the same): {the port's spread (world.spread), her
-- standing among its givers (public.investor_shave; 0 with no fleet or no house)}. Per harbour and house: a reader asks it once a read. Server-only.
declare
  v_player uuid;
  v_inv    numeric := 0;
begin
  if p_fleet is not null then
    select f.player_id into v_player from public.fleets f where f.id = p_fleet;
  end if;
  if v_player is not null then
    v_inv := public.investor_shave(v_player, p_port);
  end if;
  return array[world.spread(p_port), v_inv];
end
$function$;

create function world.spread_purser(p_fleet uuid, p_good uuid)
 returns numeric
 language plpgsql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
-- 0488: WHAT HER CAPTAINS TAKE OFF A QUAY'S SPREAD FOR A GOOD (out of world.spread_effective_pair, read the same): the purser (public.crew_pct
-- 'spread', 0157) and the traders of the good's category ('category_spread', 0161; added when not 0). 0 with no fleet. Per good: not per harbour.
declare
  v_purser numeric := 0;
  v_trader numeric;
begin
  if p_fleet is not null then
    v_purser := public.crew_pct(p_fleet, null, 'spread', p_good);
    v_trader := public.crew_pct(p_fleet, null, 'category_spread', p_good);
    if v_trader <> 0 then
      v_purser := v_purser + v_trader;
    end if;
  end if;
  return v_purser;
end
$function$;

create function world.spread_pair_from(p_port uuid, p_good uuid, p_fleet uuid, p_with_bargain boolean, p_parts numeric[], p_purser numeric,
                                       out q_spread numeric, out q_nohag numeric)
 returns record
 language plpgsql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
-- 0488: THE SPREAD THIS HOUSE EXECUTES AT, AND THE SAME WITHOUT THE BARGAIN — world.spread_effective_pair's arithmetic (0022 / 0083 / 0157 / 0161 /
-- 0191 / 0256), moved here whole, on the harbour's reads (p_parts: world.spread_parts) and her captains' (p_purser: world.spread_purser). Her bargain
-- (public.haggle_concession: per harbour and good) and the floor are read here. Server-only.
declare
  v_pub    numeric := p_parts[1];
  v_player uuid;
  v_purser numeric := p_purser;
  v_hag    numeric := 0;
  v_nohag  numeric := 0;   -- 0256: the bargain an unbargained answer keeps
  v_inv    numeric := p_parts[2];
  v_floor  numeric;
begin
  if p_fleet is not null then
    select f.player_id into v_player from public.fleets f where f.id = p_fleet;
    -- 0083: asked with p_with_bargain = false this is what the SAME house executes at without today's bargain
    if v_player is not null and p_with_bargain then
      v_hag := public.haggle_concession(v_player, p_port, p_good);
    end if;
  end if;
  -- Decision 5: MULTIPLICATIVE, so two shaves cannot add up to more than either could win.
  -- Decision 6: and the floor, which the port keeps whatever stacks.
  v_floor  := public.wc_num('haggle_spread_floor_frac');
  q_spread := greatest(v_pub * v_floor, v_pub * (1 - v_purser) * (1 - v_hag) * (1 - v_inv));
  q_nohag  := greatest(v_pub * v_floor, v_pub * (1 - v_purser) * (1 - v_nohag) * (1 - v_inv));
end
$function$;

create function world.quote_quay(p_port uuid, p_fleet uuid)
 returns numeric[]
 language plpgsql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
-- 0488: WHAT A QUOTE READS OF THE HARBOUR (out of world.quote_terms, read the same): world.spread_parts' two, then the tax a quote carries (0 lit:
-- it is charged on profit; dark world.tax_rate) and the city's bid factor (public.city_bid_factor). Per harbour and house. Server-only.
begin
  return world.spread_parts(p_port, p_fleet)
         || array[case when public.city_treasury_on() then 0 else world.tax_rate(p_port) end, public.city_bid_factor(p_port)];
end
$function$;

create function world.quote_terms_from(p_port uuid, p_good uuid, p_fleet uuid, p_quay numeric[], p_purser numeric,
                                       out q_spread numeric, out q_nohag numeric, out q_tax numeric, out q_bidf numeric)
 returns record
 language plpgsql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
-- 0488: A QUOTE'S FOUR TERMS — world.quote_terms' arithmetic (0169 / 0256 / 0083 / 0122 / 0479), moved here whole, on the harbour's reads (p_quay:
-- world.quote_quay) and her captains' (p_purser: world.spread_purser). Server-only.
begin
  select p.q_spread, p.q_nohag into q_spread, q_nohag
    from world.spread_pair_from(p_port, p_good, p_fleet, true, p_quay[1:2], p_purser) p;
  -- 0083: what the same house pays with no bargain; with no fleet named there is no bargain.
  q_nohag  := case when p_fleet is null then q_spread
                   else q_nohag end;
  q_tax    := p_quay[3];
  -- 0479: her mastery of the good (public.goods_mastery_bid), on the city's bid factor
  q_bidf   := p_quay[4] * public.goods_mastery_bid(p_fleet, p_good, q_spread);
end
$function$;

create function public.port_fee_terms(p_port uuid, p_player uuid)
 returns numeric[]
 language plpgsql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
-- 0488: WHAT public.port_fee READS (out of it, read the same): null when harbour p_port charges company p_player nothing (the economy open, the
-- purses dark, nobody, a crown's ship, a free port, a place with no purse); else {port_fee_base, port_fee_pct, the country factor, her regard
-- factor, her logbook factor, her home factor}. Per harbour and house: a reader asks it once a read. Server-only.
begin
  if p_player is null or not public.economy_closed() or not public.city_treasury_on()
     or public.crown_house(p_player)
     or public.port_is_free(p_port)
     or not exists (select 1 from public.port_treasury t join public.ports p on p.id = t.port_id
                     where t.port_id = p_port and p.kind = 'HARBOUR') then
    return null;
  end if;
  return array[public.wc_num('port_fee_base'), public.wc_num('port_fee_pct'),
               public.country_factor(public.power_stance(
                 (select pl.nation_id from public.players pl where pl.id = p_player), public.port_nation(p_port))),
               public.regard_factor(p_player, p_port),
               public.logbook_fee_factor(p_player, p_port),
               public.nation_fee_factor(p_player, p_port)];
end
$function$;

create function public.port_fee_of(p_terms numeric[], p_value numeric)
 returns bigint
 language plpgsql
 immutable
 set search_path to 'public', 'pg_temp'
as $function$
-- 0488: THE DOCK FEE'S ARITHMETIC — public.port_fee's (0237 / 0319 / 0478 / 0484), moved here whole: round((base + pct x value) x country x regard
-- x logbook x home), never under 0; no terms (public.port_fee_terms null): 0. Server-only.
begin
  if p_terms is null then
    return 0;
  end if;
  return greatest(0, round((p_terms[1] + p_terms[2] * greatest(coalesce(p_value, 0), 0))
                           * p_terms[3]
                           * p_terms[4]
                           * p_terms[5]
                           * p_terms[6]))::bigint;
end
$function$;

create function public.profit_tax_at(p_on boolean, p_profit numeric, p_rate numeric)
 returns bigint
 language plpgsql
 immutable
 set search_path to 'public', 'pg_temp'
as $function$
-- 0488: THE PROFIT TAX'S ARITHMETIC — public.profit_tax's (0122 / 0147), moved here whole: lit (p_on) and a profit above nought, round(profit x rate);
-- else nothing. The rate is world.tax_rate's, asked by the caller only when it is lit and the profit above nought. Server-only.
begin
  return case when p_on and p_profit > 0
              then round(p_profit * p_rate)::bigint else 0::bigint end;
end
$function$;

revoke all on function world.spread_parts(uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function world.spread_purser(uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function world.spread_pair_from(uuid, uuid, uuid, boolean, numeric[], numeric) from public, anon, authenticated, service_role;
revoke all on function world.quote_quay(uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function world.quote_terms_from(uuid, uuid, uuid, numeric[], numeric) from public, anon, authenticated, service_role;
revoke all on function public.port_fee_terms(uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function public.port_fee_of(numeric[], numeric) from public, anon, authenticated, service_role;
revoke all on function public.profit_tax_at(boolean, numeric, numeric) from public, anon, authenticated, service_role;

-- ── THE RE-CUT: what it changes, as data (applied by pg_temp.recut_0488 inside the probe, then for real) ──
-- kind 'body': the function's whole body (prosrc, md5 below) becomes `new`. kind 'hunk': `old` occurs once in the live definition of `src` and
-- becomes `new`, in order; the result is executed (for world.board_sell_memo: world.board_sell's definition, its first hunk the new name).
create temp table recut_0488 (fn text not null, src text not null, kind text not null, ord int not null, old text, new text not null,
                              primary key (fn, ord)) on commit drop;
insert into recut_0488 (fn, src, kind, ord, old, new) values
-- world.board_sell_memo: world.board_sell's body by 11 hunks
('world.board_sell_memo(uuid,uuid,jsonb,jsonb)', 'world.board_sell(uuid,uuid,jsonb)', 'hunk', 1,
$h$CREATE OR REPLACE FUNCTION world.board_sell(p_good uuid, p_fleet uuid, p_ctx jsonb)
 RETURNS jsonb
$h$,
$h$CREATE OR REPLACE FUNCTION world.board_sell_memo(p_good uuid, p_fleet uuid, p_ctx jsonb, p_memo jsonb, OUT o_rows jsonb, OUT o_memo jsonb)
 RETURNS record
$h$),
('world.board_sell_memo(uuid,uuid,jsonb,jsonb)', 'world.board_sell(uuid,uuid,jsonb)', 'hunk', 2,
$h$  v_walked  numeric;   -- 0459: the units the legs were walked with aboard from the buy city on (null: nothing bought on the way)
begin
$h$,
$h$  v_walked  numeric;   -- 0459: the units the legs were walked with aboard from the buy city on (null: nothing bought on the way)
  -- 0488: WHAT A HARBOUR ASKS OF EVERY GOOD, ASKED ONCE A READ. p_memo (world.best_sales hands back o_memo to its next good's call; null: none)
  -- keeps, for this fleet and house, each harbour's quote terms (world.quote_quay), dock fee terms (public.port_fee_terms) and profit tax rate
  -- (world.tax_rate), as the texts of what they answered; a memo of another fleet or house is not read. o_memo: it, and what this call asked.
  -- Her captains' share of the spread for this good (world.spread_purser) is asked once a call, not once a quote.
  v_memo    jsonb := coalesce(case when p_memo->>'fleet' = p_fleet::text and p_memo->>'player' is not distinct from v_player::text then p_memo end,
                              jsonb_build_object('fleet', p_fleet::text, 'player', v_player::text, 'q', '{}'::jsonb, 'f', '{}'::jsonb, 't', '{}'::jsonb));
  v_new     jsonb;
  v_purser  numeric := world.spread_purser(p_fleet, p_good);
  v_taxon   boolean := public.city_treasury_on();
begin
$h$),
('world.board_sell_memo(uuid,uuid,jsonb,jsonb)', 'world.board_sell(uuid,uuid,jsonb)', 'hunk', 3,
$h$  ), quoted as materialized (
$h$,
$h$  ), quay as materialized (
    -- 0488: each harbour a row is sold at: its quote terms from the memo, else asked (world.quote_quay)
    select h.id, case when v_memo->'q' ? h.id::text then (v_memo->'q'->>h.id::text)::numeric[] else world.quote_quay(h.id, p_fleet) end as q,
           v_memo->'q' ? h.id::text as had
      from (select distinct l.id from lots l where l.n > 0) h
  ), quoted as materialized (
$h$),
('world.board_sell_memo(uuid,uuid,jsonb,jsonb)', 'world.board_sell(uuid,uuid,jsonb)', 'hunk', 4,
$h$     cross join lateral world.quote(r.id, p_good, l.n, 'sell', null, p_fleet) qs
$h$,
$h$      -- 0488: world.quote's own read, its terms handed over: world.quote_terms' arithmetic (world.quote_terms_from) on the harbour's terms (quay)
      join quay qy on qy.id = r.id
     cross join lateral world.quote_terms_from(r.id, p_good, p_fleet, qy.q, v_purser) k
     cross join lateral world.quote_priced(r.id, p_good, l.n, 'sell', null, p_fleet, k.q_spread, k.q_nohag, k.q_tax, k.q_bidf) qs
$h$),
('world.board_sell_memo(uuid,uuid,jsonb,jsonb)', 'world.board_sell(uuid,uuid,jsonb)', 'hunk', 5,
$h$  ), fees as materialized (
$h$,
$h$  ), dock as materialized (
    -- 0488: each harbour a priced row calls at, closed: its dock fee terms from the memo, else asked (public.port_fee_terms; null: it charges nothing)
    select h.id, case when v_memo->'f' ? h.id::text then (v_memo->'f'->>h.id::text)::numeric[] else public.port_fee_terms(h.id, v_player) end as f,
           v_memo->'f' ? h.id::text as had
      from (select distinct p.id
              from quoted q
             cross join lateral (select x from unnest(q.t_pre) x union all select x from unnest(q.t_post) x) u(code)
              join public.ports p on p.code = u.code and p.kind = 'HARBOUR'
             where v_closed and q.t_sea is not null) h
  ), fees as materialized (
$h$),
('world.board_sell_memo(uuid,uuid,jsonb,jsonb)', 'world.board_sell(uuid,uuid,jsonb)', 'hunk', 6,
$h$    select d.code, d.v, public.port_fee(p.id, v_player, d.v) as fee
$h$,
$h$    select d.code, d.v, public.port_fee_of(dk.f, d.v) as fee   -- 0488: public.port_fee's arithmetic on the harbour's terms (dock)
$h$),
('world.board_sell_memo(uuid,uuid,jsonb,jsonb)', 'world.board_sell(uuid,uuid,jsonb)', 'hunk', 7,
$h$      join public.ports p on p.code = d.code and p.kind = 'HARBOUR'
  ), priced as materialized (
$h$,
$h$      join public.ports p on p.code = d.code and p.kind = 'HARBOUR'
      join dock dk on dk.id = p.id
  ), rate as materialized (
    -- 0488: each harbour a row sells at for a profit, lit: the profit tax's rate from the memo, else asked (world.tax_rate, where public.profit_tax asks it)
    select h.id, case when v_memo->'t' ? h.id::text then (v_memo->'t'->>h.id::text)::numeric else world.tax_rate(h.id, v_player) end as t,
           v_memo->'t' ? h.id::text as had
      from (select distinct q.id from quoted q where v_taxon and q.cost is not null and q.proceeds - q.cost > 0) h
  ), priced as materialized (
$h$),
('world.board_sell_memo(uuid,uuid,jsonb,jsonb)', 'world.board_sell(uuid,uuid,jsonb)', 'hunk', 8,
$h$           public.profit_tax(q.id, case when q.cost is null then null else q.proceeds - q.cost end, v_player) as tax,
$h$,
$h$           public.profit_tax_at(v_taxon, case when q.cost is null then null else q.proceeds - q.cost end, tx.t) as tax,   -- 0488: public.profit_tax's arithmetic on the harbour's rate (rate)
$h$),
('world.board_sell_memo(uuid,uuid,jsonb,jsonb)', 'world.board_sell(uuid,uuid,jsonb)', 'hunk', 9,
$h$      from quoted q
  )
$h$,
$h$      from quoted q
      left join rate tx on tx.id = q.id
  )
$h$),
('world.board_sell_memo(uuid,uuid,jsonb,jsonb)', 'world.board_sell(uuid,uuid,jsonb)', 'hunk', 10,
$h$                    r.mid desc, r.code), '[]'::jsonb)
    into v_sell
$h$,
$h$                    r.mid desc, r.code), '[]'::jsonb),
         -- 0488: what this call asked of each harbour, for the next call
         jsonb_build_object('q', coalesce((select jsonb_object_agg(qy.id::text, qy.q::text) from quay qy where not qy.had), '{}'::jsonb),
                            'f', coalesce((select jsonb_object_agg(dk.id::text, dk.f::text) from dock dk where not dk.had), '{}'::jsonb),
                            't', coalesce((select jsonb_object_agg(tx.id::text, tx.t::text) from rate tx where not tx.had), '{}'::jsonb))
    into v_sell, v_new
$h$),
('world.board_sell_memo(uuid,uuid,jsonb,jsonb)', 'world.board_sell(uuid,uuid,jsonb)', 'hunk', 11,
$h$  return v_sell;
end
$h$,
$h$  o_rows := v_sell;
  o_memo := v_memo || jsonb_build_object('q', (v_memo->'q') || (v_new->'q'), 'f', (v_memo->'f') || (v_new->'f'), 't', (v_memo->'t') || (v_new->'t'));
  return;
end
$h$),
-- world.best_sales: each good's world.board_sell_memo is handed the memo the last one handed back
('world.best_sales(uuid,uuid)', 'world.best_sales(uuid,uuid)', 'hunk', 1,
$h$  c_budget  constant interval := interval '2.5 seconds';
begin
$h$,
$h$  c_budget  constant interval := interval '2.5 seconds';
  v_memo    jsonb;                  -- 0488: what world.board_sell_memo asked of each harbour (this read, this fleet), handed to the next good's call
  v_fitrows jsonb;                  -- 0488: a good's FIT rows, asked with the memo
begin
$h$),
('world.best_sales(uuid,uuid)', 'world.best_sales(uuid,uuid)', 'hunk', 2,
$h$      v_rows := world.board_sell(gd.id, p_fleet, v_ctx);
    elsif v_u <= 0 then
$h$,
$h$      select m.o_rows, m.o_memo into v_rows, v_memo from world.board_sell_memo(gd.id, p_fleet, v_ctx, v_memo) m;
    elsif v_u <= 0 then
$h$),
('world.best_sales(uuid,uuid)', 'world.best_sales(uuid,uuid)', 'hunk', 3,
$h$      v_rows := world.board_sell(gd.id, p_fleet, v_ctx || jsonb_build_object(
                  'units', v_u, 'basis', 'asked', 'fit', false,
                  'src', jsonb_build_object('code', v_port.code, 'units', v_u, 'cost', (v_cap->>'est_total')::numeric)));
$h$,
$h$      select m.o_rows, m.o_memo into v_rows, v_memo from world.board_sell_memo(gd.id, p_fleet, v_ctx || jsonb_build_object(
                  'units', v_u, 'basis', 'asked', 'fit', false,
                  'src', jsonb_build_object('code', v_port.code, 'units', v_u, 'cost', (v_cap->>'est_total')::numeric)), v_memo) m;
$h$),
('world.best_sales(uuid,uuid)', 'world.best_sales(uuid,uuid)', 'hunk', 4,
$h$        v_rows := (select coalesce(jsonb_agg(x.e), '[]'::jsonb)
$h$,
$h$        select m.o_rows, m.o_memo into v_fitrows, v_memo from world.board_sell_memo(gd.id, p_fleet, v_ctx, v_memo) m;
        v_rows := (select coalesce(jsonb_agg(x.e), '[]'::jsonb)
$h$),
('world.best_sales(uuid,uuid)', 'world.best_sales(uuid,uuid)', 'hunk', 5,
$h$                           select e from jsonb_array_elements(world.board_sell(gd.id, p_fleet, v_ctx)) e
$h$,
$h$                           select e from jsonb_array_elements(v_fitrows) e
$h$),
-- the five whole bodies
('world.board_sell(uuid,uuid,jsonb)', 'world.board_sell(uuid,uuid,jsonb)', 'body', 1, '081f8ae0ac7be74eebb5dfc13a277cf1',
$h$
-- 0348: THE SELL ROWS OF A GOOD (world.good_board's SELL AT; the one place a sale's profit is worked out). 0488: the body is world.board_sell_memo's,
-- moved there whole with the harbours' memo (world.best_sales hands it from good to good); asked here with none.
begin
  return (select m.o_rows from world.board_sell_memo(p_good, p_fleet, p_ctx, null) m);
end
$h$),
('world.spread_effective_pair(uuid,uuid,uuid,boolean)', 'world.spread_effective_pair(uuid,uuid,uuid,boolean)', 'body', 1, '72d155cfc975946ddedd0638979175a9',
$h$
-- 0256: THE SPREAD THIS HOUSE EXECUTES AT, AND THE SAME WITHOUT THE BARGAIN, FROM ONE READING. q_spread is what world.spread_effective answers asked
-- with p_with_bargain, q_nohag what it answered asked with false (the bargain left at its 0). Server-only.
-- 0488: THE ARITHMETIC IS world.spread_pair_from (moved there whole), on the harbour's reads (world.spread_parts: the port's spread, her standing among
-- its givers) and her captains' (world.spread_purser), read here as before: world.board_sell_memo reads a harbour's once a read.
begin
  select x.q_spread, x.q_nohag into q_spread, q_nohag
    from world.spread_pair_from(p_port, p_good, p_fleet, p_with_bargain, world.spread_parts(p_port, p_fleet), world.spread_purser(p_fleet, p_good)) x;
end
$h$),
('world.quote_terms(uuid,uuid,uuid)', 'world.quote_terms(uuid,uuid,uuid)', 'body', 1, 'bfa36c9da145c6069bf3e82305d0e193',
$h$
-- 0169: A QUOTE'S FOUR TERMS — what this house executes at here (the port's spread, her purser's and today's bargain), the same without the bargain,
-- the tax a quote carries (0 lit: it is charged on profit) and the city's bid factor (0479: times her mastery of the good). world.quote_priced reads
-- them here, at the point world.quote always did. WITH NO FLEET NAMED THEY ARE THE PORT'S (world.trade_routes reads them once a quay).
-- 0488: THE ARITHMETIC IS world.quote_terms_from (moved there whole), on the harbour's reads (world.quote_quay: the port's spread, her standing among
-- its givers, the tax a quote carries, the city's bid factor) and her captains' (world.spread_purser), read here as before.
begin
  select t.q_spread, t.q_nohag, t.q_tax, t.q_bidf into q_spread, q_nohag, q_tax, q_bidf
    from world.quote_terms_from(p_port, p_good, p_fleet, world.quote_quay(p_port, p_fleet), world.spread_purser(p_fleet, p_good)) t;
end
$h$),
('public.port_fee(uuid,uuid,numeric)', 'public.port_fee(uuid,uuid,numeric)', 'body', 1, '4b843a11bf97913cbb6a54867ce40c91',
$h$
-- 0237 (§4c): THE one dock fee — what harbour p_port charges company p_player's fleet with cargo worth p_value (at cost) aboard:
-- round((port_fee_base + port_fee_pct × value) × country_factor × regard × logbook × home). 0 while the economy is open, while the purses are dark,
-- for a company of nobody, a crown's ship, at a free port and at a place with no purse.
-- 0488: its terms are public.port_fee_terms' and its arithmetic public.port_fee_of's (both moved there whole): world.board_sell_memo asks a harbour's
-- terms once a read.
begin
  return public.port_fee_of(public.port_fee_terms(p_port, p_player), p_value);
end
$h$),
('public.profit_tax(uuid,numeric,uuid)', 'public.profit_tax(uuid,numeric,uuid)', 'body', 1, '38d1efc7e3e15ddf6150e056dbd75c20',
$h$
-- 0122: THE charge. Tax on the profit of a sale, nothing on a loss, a break-even, or a profit the game cannot know (null). Dark: nothing (the turnover
-- tax still rides the quote). 0147: at the seller's rate (world.tax_rate(port, seller)).
-- 0488: the arithmetic is public.profit_tax_at's (moved there whole); the rate is asked only when lit and the profit above nought, as before.
declare
  v_on boolean := public.city_treasury_on();
begin
  return public.profit_tax_at(v_on, p_profit, case when v_on and p_profit > 0 then world.tax_rate(p_port, p_player) end);
end
$h$);

-- THE RE-CUT (applied inside the probe, then for real): returns {fn: md5 of its new body}
create function pg_temp.recut_0488() returns jsonb language plpgsql as $c$
declare
  v_fn   text;
  v_def  text;
  v_src  text;
  v_n    int;
  v_out  jsonb := '{}'::jsonb;
  x      record;
begin
  -- the hunked: world.board_sell_memo (from world.board_sell's definition, before its body is re-cut) and world.best_sales
  foreach v_fn in array array['world.board_sell_memo(uuid,uuid,jsonb,jsonb)', 'world.best_sales(uuid,uuid)'] loop
    v_def := replace(pg_get_functiondef((select r.src from recut_0488 r where r.fn = v_fn and r.ord = 1)::regprocedure), E'\r', '');
    for x in select * from recut_0488 r where r.fn = v_fn order by r.ord loop
      v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
      if v_n <> 1 then
        raise exception '0488 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, v_fn, v_n;
      end if;
      v_def := replace(v_def, x.old, x.new);
    end loop;
    execute v_def;
  end loop;
  -- the whole bodies: the live body (its md5 is `old`) becomes `new`, nothing else of the definition moves
  for x in select * from recut_0488 r where r.kind = 'body' order by r.fn loop
    select p.prosrc into v_src from pg_proc p where p.oid = x.fn::regprocedure;
    if md5(replace(v_src, E'\r', '')) <> x.old then
      raise exception '0488 self-assert FAIL: % is not the body this file was written against', x.fn;
    end if;
    v_def := pg_get_functiondef(x.fn::regprocedure);
    if (length(v_def) - length(replace(v_def, v_src, ''))) / length(v_src) <> 1 then
      raise exception '0488 self-assert FAIL: % does not show its body once', x.fn;
    end if;
    execute replace(v_def, v_src, x.new);
  end loop;
  for x in select distinct r.fn from recut_0488 r loop
    v_out := v_out || jsonb_build_object(x.fn, (select md5(p.prosrc) from pg_proc p where p.oid = x.fn::regprocedure));
  end loop;
  return v_out;
end $c$;

-- THE PIECES (none time-budgeted; read only): p_memo: world.board_sell_memo with the memo threaded over the goods (after the re-cut only)
create function pg_temp.pieces_0488(p_player uuid, p_fleet uuid, p_memo boolean) returns jsonb language plpgsql as $q$
declare
  v_at   uuid := (select f.port_id from public.fleets f where f.id = p_fleet);
  v_code text := (select p.code from public.ports p where p.id = v_at);
  v_o    jsonb;
  v_ctx  jsonb;
  v_legs jsonb;
  v_mm   jsonb;
  v_r1   jsonb;
  v_out  jsonb := '{}'::jsonb;
  g      record;
  a      record;
begin
  v_o := world.board_origin(p_fleet);
  v_o := v_o || jsonb_build_object('trip_fleet', p_fleet, 'trip_hulls', world.trip_hulls(p_fleet), 'speed_parts', voyage.fleet_speed_parts(p_fleet));
  for g in
    select gd.id, gd.code from public.port_goods pg join public.goods gd on gd.id = pg.good_id
     where pg.port_id = v_at and public.port_offers(v_at, gd.id) order by gd.code
  loop
    select * into a from world.board_amount(p_fleet, g.id, null);
    v_ctx := v_o || jsonb_build_object(
               'units', a.units, 'basis', a.basis, 'cost_each', a.cost_each,
               'src', jsonb_build_object('code', case when a.basis <> 'on_board' then v_code end),
               'src_cut', false, 'src_name', null, 'fit', a.basis <> 'on_board', 'lean', true, 'src_passages', null);
    if v_legs is null then
      v_legs := world.board_legs(p_fleet, v_ctx || jsonb_build_object('only', '[]'::jsonb));
    end if;
    v_ctx := v_ctx || jsonb_build_object('legs', v_legs);
    if p_memo then
      select m.o_rows, m.o_memo into v_r1, v_mm from world.board_sell_memo(g.id, p_fleet, v_ctx, v_mm) m;
    else
      v_r1 := world.board_sell(g.id, p_fleet, v_ctx);
    end if;
    v_out := v_out || jsonb_build_object('sell:' || g.code, v_r1);
  end loop;
  if p_memo then
    return v_out;   -- the memo's own: compared with the plain rows
  end if;
  return v_out || jsonb_build_object(
    'terms', (select jsonb_agg(jsonb_build_array(h.code, gd.code, to_jsonb(t1), to_jsonb(t2), to_jsonb(s1), to_jsonb(s2), to_jsonb(s3)) order by h.code, gd.code)
                from (select p.id, p.code from (select p0.id, p0.code, row_number() over (order by p0.code) as k from public.ports p0 where p0.kind = 'HARBOUR') p
                       where p.k % 32 = 1) h
               cross join (select g2.id, g2.code from public.port_goods pg join public.goods g2 on g2.id = pg.good_id
                            where pg.port_id = v_at and public.port_offers(v_at, g2.id)) gd
               cross join lateral world.quote_terms(h.id, gd.id, p_fleet) t1
               cross join lateral world.quote_terms(h.id, gd.id, null) t2
               cross join lateral world.spread_effective_pair(h.id, gd.id, p_fleet, true) s1
               cross join lateral world.spread_effective_pair(h.id, gd.id, p_fleet, false) s2
               cross join lateral world.spread_effective_pair(h.id, gd.id, null, true) s3),
    'quotes', (select jsonb_agg(jsonb_build_array(h.code, gd.code, q1, q2) order by h.code, gd.code)
                 from (select p.id, p.code from (select p0.id, p0.code, row_number() over (order by p0.code) as k from public.ports p0 where p0.kind = 'HARBOUR') p
                        where p.k % 32 = 1) h
                cross join (select g2.id, g2.code from public.port_goods pg join public.goods g2 on g2.id = pg.good_id
                             where pg.port_id = v_at and public.port_offers(v_at, g2.id)) gd
                cross join lateral (select to_jsonb(q) as q1 from world.quote(h.id, gd.id, 37, 'sell', null, p_fleet) q) s1
                cross join lateral (select to_jsonb(q) as q2 from world.quote(h.id, gd.id, 11, 'buy', null, p_fleet) q) s2
                where exists (select 1 from public.port_goods x where x.port_id = h.id and x.good_id = gd.id)),
    'fees', (select jsonb_agg(jsonb_build_array(p.code, w.k,
                                                public.port_fee(p.id, w.id, 1000), public.port_fee(p.id, w.id, 0), public.port_fee(p.id, w.id, null),
                                                public.profit_tax(p.id, 1000, w.id), public.profit_tax(p.id, -5, w.id), public.profit_tax(p.id, null, w.id))
                              order by p.code, w.k)
               from public.ports p
              cross join (select 1 as k, p_player as id
                          union all select 2, (select pl.id from public.players pl where pl.is_npc order by pl.id limit 1)
                          union all select 3, (select c.player_id from public.cargo_ships c order by c.player_id limit 1)
                          union all select 4, null::uuid) w
              where p.kind = 'HARBOUR' and p.code in (select p0.code from (select p1.code, row_number() over (order by p1.code) as k from public.ports p1
                                                                           where p1.kind = 'HARBOUR') p0 where p0.k % 6 = 1)));
end $q$;

do $m$
declare
  c_ua    constant uuid := '00000000-0488-4000-8000-0000000004a1';
  c_ub    constant uuid := '00000000-0488-4000-8000-0000000004b1';
  c_lit   constant text[] := array['economy_closed', 'city_treasury_enabled', 'city_wants', 'world_events_enabled', 'regard_enabled',
                                   'nation_race_enabled', 'price_impact', 'pirates_bite', 'pirate_ports_free', 'ship_stores_separate',
                                   'influence_enabled', 'logbook_enabled', 'goods_mastery_enabled', 'first_hour_enabled',
                                   'near_choice_enabled', 'levels_bite'];
  c_new   constant text[] := array['world.spread_parts(uuid,uuid)', 'world.spread_purser(uuid,uuid)',
                                   'world.spread_pair_from(uuid,uuid,uuid,boolean,numeric[],numeric)', 'world.quote_quay(uuid,uuid)',
                                   'world.quote_terms_from(uuid,uuid,uuid,numeric[],numeric)', 'public.port_fee_terms(uuid,uuid)',
                                   'public.port_fee_of(numeric[],numeric)', 'public.profit_tax_at(boolean,numeric,numeric)'];
  c_recut constant text[] := array['world.best_sales(uuid,uuid)', 'world.board_sell(uuid,uuid,jsonb)', 'world.spread_effective_pair(uuid,uuid,uuid,boolean)',
                                   'world.quote_terms(uuid,uuid,uuid)', 'public.port_fee(uuid,uuid,numeric)', 'public.profit_tax(uuid,numeric,uuid)'];
  v_t0    timestamptz := clock_timestamp();
  v_lis   uuid := (select p.id from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR');
  v_fn_before text;
  v_meta  text;
  v_a     uuid;  v_fa uuid;
  v_b     uuid;  v_fb uuid;
  v_lit   text[] := '{}';
  v_was   jsonb := '{}'::jsonb;
  v_k     text;
  v_good  uuid;
  v_dk0   jsonb;  v_dk1 jsonb;
  v_pa0   jsonb;  v_pa1 jsonb;  v_pm1 jsonb;
  v_ba0   jsonb;  v_ba1 jsonb;
  v_bb0   jsonb;  v_bb1 jsonb;
  v_ms0   numeric;
  v_ms1   numeric;
  v_t     timestamptz;
  v_tried jsonb;
  v_done  jsonb;
  v_lived boolean := false;
  v_def   text;
  v_bad   text;
  x       record;
begin
  -- ── 0. GUARD AND THE PRE-IMAGE ──
  if to_regprocedure('world.board_sell_memo(uuid,uuid,jsonb,jsonb)') is not null then
    raise exception '0488 refuses: it has been applied once';
  end if;
  if (select md5(replace(p.prosrc, E'\r', '')) from pg_proc p where p.oid = 'world.best_sales(uuid,uuid)'::regprocedure) <> '3f71e6c4c3e6ab4241af0d546e2bdec5' then
    raise exception '0488 self-assert FAIL: world.best_sales is not the body this file was written against';
  end if;
  -- every other function of the four schemas, and the six's grants, owner, definer, search path, volatility, arguments and type
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select to_regprocedure(u)::oid from unnest(c_recut || c_new) u));
  select md5(string_agg(u || ':' || coalesce(p.proacl::text, '') || ':' || p.proowner::text || ':' || p.prosecdef::text || ':' || coalesce(p.proconfig::text, '')
                        || ':' || p.provolatile::text || p.proisstrict::text || p.proparallel::text || ':' || p.prorettype::text || ':' || p.proargtypes::text
                        || ':' || coalesce(p.proargnames::text, '') || ':' || coalesce(p.proallargtypes::text, '') || ':' || coalesce(pg_get_expr(p.proargdefaults, 0), ''),
                        ',' order by u))
    into v_meta
    from unnest(c_recut) u join pg_proc p on p.oid = to_regprocedure(u);

  -- ── 1. THE PROBE, rolled back by a raised sentinel: everything before and after the re-cut, compared ──
  begin
    -- A: rich, a captain seated, a mastery of one good Lisbon sells; B: a thin purse (the tray's Max binds, FIT rows)
    v_a := public.new_house(c_ua, 'Casa do Porto 0488', 'PRT');
    v_b := public.new_house(c_ub, 'Casa Magra 0488', 'PRT');
    select f.id into v_fa from public.fleets f where f.player_id = v_a;
    select f.id into v_fb from public.fleets f where f.player_id = v_b;
    update public.players p set ducats = 2000000 where p.id = v_a;
    update public.players p set ducats = 900 where p.id = v_b;
    if (select count(*) from public.fleets f where f.id in (v_fa, v_fb) and f.port_id = v_lis) <> 2 then
      raise exception '0488 self-assert FAIL: a Portuguese house does not start at Lisbon';
    end if;
    declare
      v_po uuid;
      o    record;
    begin
      for o in select ox.id from public.officers ox join public.captain_profile cp on cp.officer_id = ox.id order by ox.code limit 1 loop
        insert into public.player_officers (player_id, officer_id) values (v_a, o.id) returning id into v_po;
        insert into public.captain_active (player_officer_id, trait) select v_po, ct.trait from public.captain_traits ct where ct.officer_id = o.id on conflict do nothing;
        perform public.captain_seat_put(v_po, (select s.id from public.ships s where s.fleet_id = v_fa order by s.is_flagship desc, s.id limit 1), 1);
      end loop;
    end;
    select g.id into v_good from public.port_goods pg join public.goods g on g.id = pg.good_id
     where pg.port_id = v_lis and public.port_offers(v_lis, g.id) order by g.code limit 1;
    insert into public.goods_mastery (player_id, good_id, units, level) values (v_a, v_good, 500, 3);

    -- the switches as they are, when any is off (on prod none is): the pieces before
    perform cmd.assume_identity(c_ua);
    if exists (select 1 from unnest(c_lit) k join public.world_config c on c.key = k where c.value is distinct from 'true'::jsonb) then
      v_dk0 := pg_temp.pieces_0488(v_a, v_fa, false);
    end if;
    foreach v_k in array c_lit loop
      if exists (select 1 from public.world_config c where c.key = v_k and c.value is distinct from 'true'::jsonb) then
        v_was := v_was || jsonb_build_object(v_k, (select c.value from public.world_config c where c.key = v_k));
        update public.world_config c set value = 'true'::jsonb where c.key = v_k;
        v_lit := v_lit || v_k;
      end if;
    end loop;

    -- BEFORE, lit: the pieces of both, and world.best_sales of both with its budget taken off (a pg_temp copy, timed)
    execute replace(replace(replace(pg_get_functiondef('world.best_sales(uuid,uuid)'::regprocedure), E'\r', ''),
                            'FUNCTION world.best_sales(', 'FUNCTION pg_temp.best_open_0488('),
                    $r$c_budget  constant interval := interval '2.5 seconds';$r$, $r$c_budget  constant interval := interval '1 hour';$r$);
    v_pa0 := pg_temp.pieces_0488(v_a, v_fa, false);
    v_t := clock_timestamp();
    v_ba0 := pg_temp.best_open_0488(v_fa, v_lis);
    v_ms0 := round(extract(epoch from clock_timestamp() - v_t)::numeric * 1000);
    perform cmd.assume_identity(c_ub);
    v_bb0 := pg_temp.best_open_0488(v_fb, v_lis);
    drop function pg_temp.best_open_0488(uuid, uuid);

    -- THE RE-CUT, tried here (rolled back with the probe)
    v_tried := pg_temp.recut_0488();

    -- AFTER, lit: the same, and world.board_sell_memo with the memo threaded
    execute replace(replace(replace(pg_get_functiondef('world.best_sales(uuid,uuid)'::regprocedure), E'\r', ''),
                            'FUNCTION world.best_sales(', 'FUNCTION pg_temp.best_open_0488('),
                    $r$c_budget  constant interval := interval '2.5 seconds';$r$, $r$c_budget  constant interval := interval '1 hour';$r$);
    perform cmd.assume_identity(c_ub);
    v_bb1 := pg_temp.best_open_0488(v_fb, v_lis);
    perform cmd.assume_identity(c_ua);
    v_pa1 := pg_temp.pieces_0488(v_a, v_fa, false);
    v_pm1 := pg_temp.pieces_0488(v_a, v_fa, true);
    v_t := clock_timestamp();
    v_ba1 := pg_temp.best_open_0488(v_fa, v_lis);
    v_ms1 := round(extract(epoch from clock_timestamp() - v_t)::numeric * 1000);
    drop function pg_temp.best_open_0488(uuid, uuid);
    update public.world_config c set value = v_was->c.key where c.key = any (v_lit);
    if v_dk0 is not null then
      v_dk1 := pg_temp.pieces_0488(v_a, v_fa, false);
    end if;

    if v_pa1 is distinct from v_pa0 then
      raise exception '0488 self-assert FAIL: a piece answers differently (lit, the rich house): %',
        (select string_agg(k, ', ') from jsonb_object_keys(v_pa0) k where v_pa0->k is distinct from v_pa1->k);
    end if;
    if exists (select 1 from jsonb_object_keys(v_pm1) k where v_pm1->k is distinct from v_pa0->k) then
      raise exception '0488 self-assert FAIL: world.board_sell_memo with the memo threaded answers differently: %',
        (select string_agg(k, ', ') from jsonb_object_keys(v_pm1) k where v_pm1->k is distinct from v_pa0->k);
    end if;
    if v_ba1 is distinct from v_ba0 or v_bb1 is distinct from v_bb0 then
      raise exception '0488 self-assert FAIL: world.best_sales (its budget taken off) answers differently';
    end if;
    if v_dk1 is distinct from v_dk0 then
      raise exception '0488 self-assert FAIL: a piece answers differently (the switches as they are): %',
        (select string_agg(k, ', ') from jsonb_object_keys(v_dk0) k where v_dk0->k is distinct from v_dk1->k);
    end if;
    if (select count(*) from jsonb_object_keys(v_pa0) k where k like 'sell:%') = 0 or jsonb_array_length(v_pa0->'quotes') = 0
       or jsonb_array_length(v_ba0->'goods') = 0 or jsonb_array_length(v_bb0->'goods') = 0
       or not exists (select 1 from jsonb_array_elements(v_pa0->'fees') e where (e->>2)::numeric > 0)
       or not exists (select 1 from jsonb_array_elements(v_pa0->'fees') e where (e->>5)::numeric > 0) then
      raise exception '0488 self-assert FAIL: the probe compared nothing (no sale, quote or answered good, or no dock fee or profit tax above nought lit)';
    end if;
    raise exception using errcode = 'ZX488', message = 'PROBE_ROLLBACK_0488';
  exception when sqlstate 'ZX488' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0488 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.company_name like '% 0488' or p.auth_uid in (c_ua, c_ub))
     or public.current_player_id() is not null
     or to_regprocedure('world.board_sell_memo(uuid,uuid,jsonb,jsonb)') is not null then
    raise exception '0488 self-assert FAIL: the probe left something behind';
  end if;

  -- ── 2. THE RE-CUT, for real: the same bodies the probe tried ──
  v_done := pg_temp.recut_0488();
  if v_done is distinct from v_tried then
    raise exception '0488 self-assert FAIL: the re-cut is not the one the probe tried';
  end if;
  revoke all on function world.board_sell_memo(uuid, uuid, jsonb, jsonb) from public, anon, authenticated, service_role;

  -- ── 3. SELF-ASSERT: the catalog ──
  -- each hunk once in the new body, and the new body reverses to the old (world.board_sell_memo: to world.board_sell's old definition)
  for x in select r.fn, min(r.src) as src from recut_0488 r where r.kind = 'hunk' group by r.fn loop
    v_def := replace(pg_get_functiondef(x.fn::regprocedure), E'\r', '');
    for v_k in select r.ord::text from recut_0488 r where r.fn = x.fn order by r.ord desc loop
      if (select (length(v_def) - length(replace(v_def, r.new, ''))) / length(r.new) from recut_0488 r where r.fn = x.fn and r.ord = v_k::int) <> 1 then
        raise exception '0488 self-assert FAIL: hunk % of % is not in the new body once', v_k, x.fn;
      end if;
      v_def := (select replace(v_def, r.new, r.old) from recut_0488 r where r.fn = x.fn and r.ord = v_k::int);
    end loop;
    if x.fn = 'world.best_sales(uuid,uuid)' and md5(substr(v_def, strpos(v_def, E'AS $function$') + length(E'AS $function$'),
                                                           length(v_def) - strpos(v_def, E'AS $function$') - length(E'AS $function$') - length(E'$function$\n') + 1))
                                               <> '3f71e6c4c3e6ab4241af0d546e2bdec5' then
      raise exception '0488 self-assert FAIL: world.best_sales does not reverse to the body it had';
    end if;
    if x.fn = 'world.board_sell_memo(uuid,uuid,jsonb,jsonb)' and md5(substr(v_def, strpos(v_def, E'AS $function$') + length(E'AS $function$'),
                                                           length(v_def) - strpos(v_def, E'AS $function$') - length(E'AS $function$') - length(E'$function$\n') + 1))
                                               <> '081f8ae0ac7be74eebb5dfc13a277cf1' then
      raise exception '0488 self-assert FAIL: world.board_sell_memo does not reverse to world.board_sell''s body';
    end if;
  end loop;
  select string_agg(r.fn, ', ') into v_bad from recut_0488 r join pg_proc p on p.oid = to_regprocedure(r.fn) where r.kind = 'body' and p.prosrc <> r.new;
  if v_bad is not null then
    raise exception '0488 self-assert FAIL: not the new body: %', v_bad;
  end if;
  if (select md5(string_agg(u || ':' || coalesce(p.proacl::text, '') || ':' || p.proowner::text || ':' || p.prosecdef::text || ':' || coalesce(p.proconfig::text, '')
                        || ':' || p.provolatile::text || p.proisstrict::text || p.proparallel::text || ':' || p.prorettype::text || ':' || p.proargtypes::text
                        || ':' || coalesce(p.proargnames::text, '') || ':' || coalesce(p.proallargtypes::text, '') || ':' || coalesce(pg_get_expr(p.proargdefaults, 0), ''),
                        ',' order by u))
        from unnest(c_recut) u join pg_proc p on p.oid = to_regprocedure(u)) is distinct from v_meta then
    raise exception '0488 self-assert FAIL: the grants, owner, definer, search path, volatility, arguments or type of a re-cut function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select to_regprocedure(u)::oid from unnest(c_recut || c_new || array['world.board_sell_memo(uuid,uuid,jsonb,jsonb)']) u))) is distinct from v_fn_before then
    raise exception '0488 self-assert FAIL: another function moved, or one more was added';
  end if;
  -- the nine new are server-only: no client role and no service_role (prod's default ACL grants it EXECUTE on a new function) may run one
  select string_agg(u, ', ') into v_bad from unnest(c_new || array['world.board_sell_memo(uuid,uuid,jsonb,jsonb)']) u
   where to_regprocedure(u) is null or has_function_privilege('anon', u, 'execute') or has_function_privilege('authenticated', u, 'execute')
      or has_function_privilege('service_role', u, 'execute')
      or exists (select 1 from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = to_regprocedure(u) and a.grantee = 0);
  if v_bad is not null then
    raise exception '0488 self-assert FAIL: missing, or a client role, service_role or public may execute: %', v_bad;
  end if;
  if (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0488 self-assert FAIL: a client write grant appeared';
  end if;

  if clock_timestamp() - v_t0 > interval '60 seconds' then
    raise exception '0488 self-assert FAIL: the file took % (budget 60 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0488 self-assert ok: A HARBOUR IS ASKED ONCE. world.board_sell_memo is world.board_sell''s body by 11 hunks (each once, reversing to it); world.best_sales threads its memo by 5 hunks (reversing to the body it had); world.board_sell, world.spread_effective_pair, world.quote_terms, public.port_fee and public.profit_tax read through the 8 new pieces; grants, owner, definer, search path, volatility and types of the six unmoved; the nine new revoked from public, anon, authenticated and service_role; no other function moved. Probe (rolled back; lit for it: %): a rich house with a captain and a mastery and a thin purse at Lisbon; the quote terms and spreads, % quotes, the dock fee and profit tax at % harbour-houses, world.board_sell for % goods, the same with the memo threaded, and world.best_sales with its budget off (% and % goods): the same to the byte before and after%. TIMED on this server (%): world.best_sales, budget off, the rich house: % ms before, % ms after. % ms.',
    case when cardinality(v_lit) = 0 then 'none, all on' else array_to_string(v_lit, ' ') end,
    jsonb_array_length(v_pa0->'quotes'), jsonb_array_length(v_pa0->'fees'),
    (select count(*) from jsonb_object_keys(v_pa0) k where k like 'sell:%'),
    jsonb_array_length(v_ba0->'goods'), jsonb_array_length(v_bb0->'goods'),
    case when v_dk0 is null then '' else '; and with the switches as they are' end,
    current_setting('server_version'), v_ms0, v_ms1,
    round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;

drop function pg_temp.pieces_0488(uuid, uuid, boolean);
drop function pg_temp.recut_0488();
