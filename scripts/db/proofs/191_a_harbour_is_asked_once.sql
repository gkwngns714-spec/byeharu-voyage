-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 191 - A HARBOUR IS ASKED ONCE  (migration 0488; docs/dev-log/2026-11-24-harbour-reuse.md)
--
--   0488 split the quote's terms, the dock fee and the profit tax into a harbour's reads and their arithmetic, moved world.board_sell's body
--   into world.board_sell_memo (each harbour's reads asked once a read, kept in a memo world.best_sales hands from good to good) and re-cut
--   six bodies to read through them. Its self-assert compared old against new (the re-cut tried inside its probe). This proof goes THE OTHER
--   WAY: inside its own transaction it writes the six bodies back as they were before 0488 (world.best_sales and world.board_sell by reversing
--   0488's own hunks, md5 checked; the four small bodies from their text here, md5 checked) and compares again, wider: three houses (Lisbon
--   rich with a captain seated and a goods mastery, Lisbon with a thin purse, Seville), the switches lit and as they are.
--   NO TIME-BUDGETED READ IS COMPARED WITH ANOTHER: world.best_sales is compared only as a pg_temp copy with its 2.5 s budget taken off
--   (nothing else of it moves). One transaction: one now(), so no scene straddles UTC midnight.
--
-- @pass PO_SHAPE   the nine new pieces exist and are server-only; the six bodies are 0488's and reverse to the bodies it found (md5 for md5)
-- @pass PO_PIECES  the quote terms, spreads, quotes, dock fees, profit taxes and world.board_sell (and world.board_sell_memo threaded) answer the same before and after 0488
-- @pass PO_BEST    world.best_sales (its budget off) answers the same before and after 0488, for the three houses, lit
-- @pass PO_COST    world.best_sales (budget off) at Lisbon timed with 0488's bodies and with the old ones on this server
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

-- 0488's own hunks (copied from the migration, word for word); and the four small bodies as they were before it
-- 0536 re-cut world.best_sales and world.board_sell_memo (how the legs are read): its hunks are put back here, so this proof compares 0488's bodies
do $u$
declare
  v_def text := replace(pg_get_functiondef('world.board_sell_memo(uuid,uuid,jsonb,jsonb)'::regprocedure), E'\r', '');
  x record;
begin
  for x in select * from (values
  (1, $h$  v_taxon   boolean := public.city_treasury_on();
begin
$h$, $h$  v_taxon   boolean := public.city_treasury_on();
  v_rank    jsonb := p_ctx->'rank';   -- 0536: the legs' figures a harbour is ranked by (world.legs_rank), when the caller has them
begin
$h$),
  (2, $h$  -- SELL AT: every harbour whose culture buys it; the dearest good_board_quoted priced in full
$h$, $h$  if v_rank is null or jsonb_typeof(v_rank) <> 'object' then
    v_rank := world.legs_rank(v_legs);
  end if;

  -- SELL AT: every harbour whose culture buys it; the dearest good_board_quoted priced in full
$h$),
  (3, $h$           l.nm, l.stops, l.direct_nm, l.max_leg, l.shut_leg,
           l.sn_days, l.sn_tons, l.sn_cost, l.sn_fits, l.sn_hold,   -- 0225; sn_hold: the room those stores take in her hold (public.stores_in_hold), read once a leg
           l.t_sea, l.t_sup, l.t_stop, l.t_pre, l.t_post,   -- 0361: the trip there, as the game will charge it (world.board_legs)
           l.t_sail, l.t_days, l.t_arrive   -- 0459: and its time as walked (world.board_trips)
$h$, $h$           l.nm, l.max_leg, l.shut_leg, l.sn_fits, l.sn_hold, l.k   -- 0536: what a harbour is ranked and fitted by; `ranked` reads the rest of its leg
$h$),
  (4, $h$      join jsonb_to_recordset(v_legs) l(id uuid, nm numeric, stops text[], direct_nm numeric, max_leg numeric, shut_leg numeric,
                                        sn_days numeric, sn_tons numeric, sn_cost bigint, sn_fits boolean, sn_hold numeric,
                                        t_sea numeric, t_sup bigint, t_stop numeric, t_pre text[], t_post text[],
                                        t_sail numeric, t_days numeric, t_arrive timestamptz) on l.id = p.id   -- 0361; 0459: + t_sail, t_days, t_arrive
$h$, $h$      join unnest((v_rank->>'id')::uuid[], (v_rank->>'nm')::numeric[], (v_rank->>'max_leg')::numeric[], (v_rank->>'shut_leg')::numeric[],
                  (v_rank->>'sn_fits')::boolean[], (v_rank->>'sn_hold')::numeric[], (v_rank->>'k')::int[]) l(id, nm, max_leg, shut_leg, sn_fits, sn_hold, k) on l.id = p.id
$h$),
  (5, $h$  ), ranked as materialized (
$h$, $h$  ), ranked0 as materialized (
$h$),
  (6, $h$      from cand c
  ), units as (
$h$, $h$      from cand c
  ), ranked as materialized (
    -- 0536: the rest of a harbour's leg, read of the rows kept (lean: the priced ones): 0225; 0361: the trip there as the game will charge it
    -- (world.board_legs); 0459: and its time as walked (world.board_trips)
    select r0.*, l.*
      from ranked0 r0
     cross join lateral jsonb_to_record(v_legs->(r0.k - 1)) l(stops text[], direct_nm numeric, sn_days numeric, sn_tons numeric, sn_cost bigint,
                                                             t_sea numeric, t_sup bigint, t_stop numeric, t_pre text[], t_post text[],
                                                             t_sail numeric, t_days numeric, t_arrive timestamptz)
     where not v_lean or r0.rk <= v_quoted or r0.nk <= v_near
  ), units as (
$h$),
  (7, $h$                                                                                                  'only', d.ids), v_legs)) x(e)
$h$, $h$                                                                                                  'only', d.ids),
                                                      (select jsonb_agg(v_legs->(r0.k - 1)) from ranked0 r0 where d.ids @> jsonb_build_array(r0.id)))) x(e)
$h$)
  ) h(ord, old, new) order by ord desc loop
    if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
      raise exception 'PO_SHAPE: 0536''s hunk % of world.board_sell_memo(uuid,uuid,jsonb,jsonb) is not in the live body once', x.ord;
    end if;
    v_def := replace(v_def, x.new, x.old);
  end loop;
  execute v_def;
end
$u$;
do $u$
declare
  v_def text := replace(pg_get_functiondef('world.best_sales(uuid,uuid)'::regprocedure), E'\r', '');
  x record;
begin
  for x in select * from (values
  (1, $h$  v_legs_own jsonb;                 -- 0350: world.board_legs for her cargo, asked once
$h$, $h$  v_legs_own jsonb;                 -- 0350: world.board_legs for her cargo, asked once
  v_rank_buy jsonb;                 -- 0536: world.legs_rank of the two, asked once
  v_rank_own jsonb;
$h$),
  (2, $h$        v_legs_own := world.board_legs(p_fleet, v_ctx);
      end if;
      v_ctx := v_ctx || jsonb_build_object('legs', v_legs_own);
$h$, $h$        v_legs_own := world.board_legs(p_fleet, v_ctx);
        v_rank_own := world.legs_rank(v_legs_own);
      end if;
      v_ctx := v_ctx || jsonb_build_object('legs', v_legs_own, 'rank', v_rank_own);
$h$),
  (3, $h$        v_legs_buy := world.board_legs(p_fleet, v_ctx || jsonb_build_object('only', '[]'::jsonb));
      end if;
      v_ctx := v_ctx || jsonb_build_object('legs', v_legs_buy);
$h$, $h$        v_legs_buy := world.board_legs(p_fleet, v_ctx || jsonb_build_object('only', '[]'::jsonb));
        v_rank_buy := world.legs_rank(v_legs_buy);
      end if;
      v_ctx := v_ctx || jsonb_build_object('legs', v_legs_buy, 'rank', v_rank_buy);
$h$)
  ) h(ord, old, new) order by ord desc loop
    if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
      raise exception 'PO_SHAPE: 0536''s hunk % of world.best_sales(uuid,uuid) is not in the live body once', x.ord;
    end if;
    v_def := replace(v_def, x.new, x.old);
  end loop;
  execute v_def;
end
$u$;
create temp table p191_recut (fn text not null, src text not null, kind text not null, ord int not null, old text, new text not null,
                              primary key (fn, ord)) on commit drop;
insert into p191_recut (fn, src, kind, ord, old, new) values
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
$h$);
create temp table p191_old (fn text primary key, md5 text not null, src text not null) on commit drop;
insert into p191_old (fn, md5, src) values
('world.quote_terms(uuid,uuid,uuid)', 'bfa36c9da145c6069bf3e82305d0e193', $o$
-- 0169: A QUOTE'S FOUR TERMS — what this house executes at here (the port's spread, her purser's and
-- today's bargain: world.spread_effective), the same without the bargain, the tax a quote carries (0 lit:
-- it is charged on profit) and the city's bid factor. MOVED out of world.quote verbatim; world.quote_priced
-- reads them here, at the point world.quote always did. WITH NO FLEET NAMED THEY ARE THE PORT'S: p_good is
-- read only on world.spread_effective's fleet branch, so (port, any good, no fleet) = (port, null, null)
-- (asserted over every quoted row) — which is why world.trade_routes reads them once a quay.
begin
  -- 0256: both spreads from ONE reading (world.spread_effective_pair: the port's spread, her purser and traders, her
  -- standing among the givers read once; q_nohag is the same arithmetic with the bargain left at 0) — it was read twice.
  select p.q_spread, p.q_nohag into q_spread, q_nohag
    from world.spread_effective_pair(p_port, p_good, p_fleet, true) p;
  -- 0083: what the same house pays with no bargain; with no fleet named there is no bargain.
  q_nohag  := case when p_fleet is null then q_spread
                   else q_nohag end;
  -- 0122: lit, the tax leaves the price — it is charged on a sale's PROFIT in cmd.do_sell.
  q_tax    := case when public.city_treasury_on() then 0 else world.tax_rate(p_port) end;
  q_bidf   := public.city_bid_factor(p_port)
              -- 0479: her mastery of the good (public.goods_mastery_bid: 1 with no fleet or good named, dark, for a merchant, under her
              -- first sale; never past this quay's ask). The bid factor is read on a sale's side alone (world.quote_priced).
              * public.goods_mastery_bid(p_fleet, p_good, q_spread);
end $o$),
('world.spread_effective_pair(uuid,uuid,uuid,boolean)', '72d155cfc975946ddedd0638979175a9', $o$
-- 0256: THE SPREAD THIS HOUSE EXECUTES AT, AND THE SAME WITHOUT THE BARGAIN, FROM ONE READING. The arithmetic of
-- world.spread_effective (0022 / 0083 / 0157 / 0161 / 0191), moved here whole: q_spread is what it answered asked with
-- p_with_bargain, q_nohag what it answered asked with false (the bargain left at its 0). world.spread_effective reads
-- q_spread; world.quote_terms reads both, so a quote asks the port's spread, the purser, the traders and the
-- investors' shave once, not twice. Server-only.
declare
  v_pub    numeric := world.spread(p_port);
  v_player uuid;
  v_purser numeric := 0;
  v_hag    numeric := 0;
  v_nohag  numeric := 0;   -- 0256: the bargain an unbargained answer keeps (spread_effective(..., false) left v_hag here)
  v_trader numeric;   -- 0161
  v_inv    numeric := 0;   -- 0191: the company's standing among this city's givers
  v_floor  numeric;
begin
  -- With no fleet named this is world.spread() exactly, which is what every caller that predates
  -- the purser still passes (0005's own asserts, 0007's capacity walk, 0019's scan).
  if p_fleet is not null then
    select f.player_id into v_player from public.fleets f where f.id = p_fleet;
    v_purser := public.crew_pct(p_fleet, null, 'spread', p_good);   -- 0157: the captains, through the one reader
    -- 0161 (K7): and the traders of THIS good's category (0 while crew_bite is off — then nothing is added)
    v_trader := public.crew_pct(p_fleet, null, 'category_spread', p_good);
    if v_trader <> 0 then
      v_purser := v_purser + v_trader;
    end if;
    -- 0083: asked with p_with_bargain = false this is what the SAME house executes at without
    -- today's bargain — world.quote reads both, so it can say what the bargain saved.
    if v_player is not null and p_with_bargain then
      v_hag := public.haggle_concession(v_player, p_port, p_good);
    end if;
  end if;
  -- 0191: a city's leading givers are spared part of the spread (public.investor_shave) — a standing,
  -- not a bargain, so it holds with or without one.
  if v_player is not null then
    v_inv := public.investor_shave(v_player, p_port);
  end if;
  -- Decision 5: MULTIPLICATIVE, so two shaves cannot add up to more than either could win.
  -- Decision 6: and the floor, which the port keeps whatever stacks.
  v_floor  := public.wc_num('haggle_spread_floor_frac');
  q_spread := greatest(v_pub * v_floor, v_pub * (1 - v_purser) * (1 - v_hag) * (1 - v_inv));
  q_nohag  := greatest(v_pub * v_floor, v_pub * (1 - v_purser) * (1 - v_nohag) * (1 - v_inv));
end $o$),
('public.port_fee(uuid,uuid,numeric)', '4b843a11bf97913cbb6a54867ce40c91', $o$
-- 0237 (§4c): THE one dock fee — what harbour p_port charges company p_player's fleet with cargo worth p_value (at
-- cost) aboard: round((port_fee_base + port_fee_pct × value) × country_factor). 0 while the economy is open, while
-- the purses are dark, for a company of nobody, and at a place with no purse.
begin
  if p_player is null or not public.economy_closed() or not public.city_treasury_on()
     or public.crown_house(p_player)   -- 0309: a crown's ship docks free; she has no purse. 0331: a cargo ship's or a navy ship's
     or public.port_is_free(p_port)   -- 0338: a pirate home charges no dock fee, to anyone (docs/WORLD_POWERS.md section 7.2)
     or not exists (select 1 from public.port_treasury t join public.ports p on p.id = t.port_id
                     where t.port_id = p_port and p.kind = 'HARBOUR') then
    return 0;
  end if;
  return greatest(0, round((public.wc_num('port_fee_base') + public.wc_num('port_fee_pct') * greatest(coalesce(p_value, 0), 0))
                           * public.country_factor(public.power_stance(
                               (select pl.nation_id from public.players pl where pl.id = p_player), public.port_nation(p_port)))
                           * public.regard_factor(p_player, p_port)
                           -- 0478: her finished logbook sets (public.logbook_fee_factor: 1 dark, for a merchant, with none finished)
                           * public.logbook_fee_factor(p_player, p_port)
                           -- 0484: the home perk at her own country's harbours (public.nation_fee_factor: 1 dark, for a merchant, elsewhere)
                           * public.nation_fee_factor(p_player, p_port)))::bigint;   -- 0319: 1 while dark, for a merchant and in a free city. She still docks, whatever her band
end $o$),
('public.profit_tax(uuid,numeric,uuid)', '38d1efc7e3e15ddf6150e056dbd75c20', $o$
-- 0122: THE charge. Tax on the profit of a sale, nothing on a loss, a break-even, or a profit the
-- game cannot know (null). Dark: nothing (the turnover tax still rides the quote). 0147: at the
-- seller's rate (world.tax_rate(port, seller)).
begin
  return case when public.city_treasury_on() and p_profit > 0
              then round(p_profit * world.tax_rate(p_port, p_player))::bigint else 0::bigint end;
end $o$);

-- the body text of a definition
create function pg_temp.p191_body(p_def text) returns text language sql immutable as $b$
  select substr(p_def, strpos(p_def, 'AS $function$') + length('AS $function$'),
                length(p_def) - strpos(p_def, 'AS $function$') - length('AS $function$') - length(E'$function$\n') + 1)
$b$;

-- a definition with 0488's hunks of one function put back (new -> old, last first)
create function pg_temp.p191_unhunk(p_fn text) returns text language plpgsql as $u$
declare
  v_def text := replace(pg_get_functiondef(p_fn::regprocedure), E'\r', '');
  x     record;
begin
  for x in select * from p191_recut r where r.fn = p_fn order by r.ord desc loop
    if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
      raise exception 'PO_SHAPE: hunk % of % is not in the live body once', x.ord, p_fn;
    end if;
    v_def := replace(v_def, x.new, x.old);
  end loop;
  return v_def;
end $u$;

-- world.best_sales as it is now, its budget taken off, as pg_temp.p191_best
create function pg_temp.p191_open() returns void language plpgsql as $o$
begin
  drop function if exists pg_temp.p191_best(uuid, uuid);
  execute replace(replace(replace(pg_get_functiondef('world.best_sales(uuid,uuid)'::regprocedure), E'\r', ''),
                          'FUNCTION world.best_sales(', 'FUNCTION pg_temp.p191_best('),
                  $r$c_budget  constant interval := interval '2.5 seconds';$r$, $r$c_budget  constant interval := interval '1 hour';$r$);
end $o$;

create function pg_temp.p191_pieces(p_player uuid, p_fleet uuid, p_memo boolean) returns jsonb language plpgsql as $q$
declare
  v_at   uuid := (select f.port_id from public.fleets f where f.id = p_fleet);
  v_code text := (select p.code from public.ports p where p.id = v_at);
  v_o    jsonb;
  v_ctx  jsonb;
  v_ask  jsonb;
  v_legs jsonb;
  v_mm   jsonb;
  v_r1   jsonb;
  v_r2   jsonb;
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
    v_ask := v_ctx || jsonb_build_object('units', 7, 'basis', 'asked', 'fit', false, 'src', jsonb_build_object('code', v_code, 'units', 7, 'cost', 555));
    if p_memo then
      select m.o_rows, m.o_memo into v_r1, v_mm from world.board_sell_memo(g.id, p_fleet, v_ctx, v_mm) m;
      select m.o_rows, m.o_memo into v_r2, v_mm from world.board_sell_memo(g.id, p_fleet, v_ask, v_mm) m;
    else
      v_r1 := world.board_sell(g.id, p_fleet, v_ctx);
      v_r2 := world.board_sell(g.id, p_fleet, v_ask);
    end if;
    v_out := v_out || jsonb_build_object('sell:' || g.code, v_r1, 'ask:' || g.code, v_r2);
    -- a full board too (not lean: every row, the dues, the cap, the estimate)
    if not p_memo then
      v_out := v_out || jsonb_build_object('full:' || g.code, world.board_sell(g.id, p_fleet, v_ctx || jsonb_build_object('lean', false, 'fit', false)));
    end if;
  end loop;
  if p_memo then
    return v_out;
  end if;
  return v_out || jsonb_build_object(
    'terms', (select jsonb_agg(jsonb_build_array(h.code, gd.code, to_jsonb(t1), to_jsonb(t2), to_jsonb(s1), to_jsonb(s2), to_jsonb(s3)) order by h.code, gd.code)
                from (select p.id, p.code from (select p0.id, p0.code, row_number() over (order by p0.code) as k from public.ports p0 where p0.kind = 'HARBOUR') p
                       where p.k % 4 = 1) h
               cross join (select g2.id, g2.code from public.goods g2 order by g2.code limit 12) gd
               cross join lateral world.quote_terms(h.id, gd.id, p_fleet) t1
               cross join lateral world.quote_terms(h.id, gd.id, null) t2
               cross join lateral world.spread_effective_pair(h.id, gd.id, p_fleet, true) s1
               cross join lateral world.spread_effective_pair(h.id, gd.id, p_fleet, false) s2
               cross join lateral world.spread_effective_pair(h.id, gd.id, null, true) s3),
    'quotes', (select jsonb_agg(jsonb_build_array(h.code, gd.code, q1, q2) order by h.code, gd.code)
                 from (select p.id, p.code from (select p0.id, p0.code, row_number() over (order by p0.code) as k from public.ports p0 where p0.kind = 'HARBOUR') p
                        where p.k % 8 = 1) h
                cross join (select g2.id, g2.code from public.port_goods pg join public.goods g2 on g2.id = pg.good_id
                             where pg.port_id = v_at and public.port_offers(v_at, g2.id)) gd
                cross join lateral (select to_jsonb(q) as q1 from world.quote(h.id, gd.id, 37, 'sell', null, p_fleet) q) s1
                cross join lateral (select to_jsonb(q) as q2 from world.quote(h.id, gd.id, 11, 'buy', null, p_fleet) q) s2
                where exists (select 1 from public.port_goods x where x.port_id = h.id and x.good_id = gd.id)),
    'fees', (select jsonb_agg(jsonb_build_array(p.code, w.k,
                                                public.port_fee(p.id, w.id, 1000), public.port_fee(p.id, w.id, 0), public.port_fee(p.id, w.id, 123456.78),
                                                public.port_fee(p.id, w.id, null), public.port_fee(p.id, w.id, -5),
                                                public.profit_tax(p.id, 1000, w.id), public.profit_tax(p.id, -5, w.id), public.profit_tax(p.id, 777.77, w.id),
                                                public.profit_tax(p.id, 0, w.id), public.profit_tax(p.id, null, w.id)) order by p.code, w.k)
               from public.ports p
              cross join (select 1 as k, p_player as id
                          union all select 2, (select pl.id from public.players pl where pl.is_npc order by pl.id limit 1)
                          union all select 3, (select c.player_id from public.cargo_ships c order by c.player_id limit 1)
                          union all select 4, null::uuid) w
              where p.kind = 'HARBOUR'));
end $q$;

do $p$
declare
  c_a     constant uuid := '00000000-0191-4000-8000-0000000001a1';
  c_b     constant uuid := '00000000-0191-4000-8000-0000000001b1';
  c_c     constant uuid := '00000000-0191-4000-8000-0000000001c1';
  c_lit   constant text[] := array['economy_closed', 'city_treasury_enabled', 'city_wants', 'world_events_enabled', 'regard_enabled',
                                   'nation_race_enabled', 'price_impact', 'pirates_bite', 'pirate_ports_free', 'ship_stores_separate',
                                   'influence_enabled', 'logbook_enabled', 'goods_mastery_enabled', 'first_hour_enabled',
                                   'near_choice_enabled', 'levels_bite'];
  c_new   constant text[] := array['world.spread_parts(uuid,uuid)', 'world.spread_purser(uuid,uuid)',
                                   'world.spread_pair_from(uuid,uuid,uuid,boolean,numeric[],numeric)', 'world.quote_quay(uuid,uuid)',
                                   'world.quote_terms_from(uuid,uuid,uuid,numeric[],numeric)', 'public.port_fee_terms(uuid,uuid)',
                                   'public.port_fee_of(numeric[],numeric)', 'public.profit_tax_at(boolean,numeric,numeric)',
                                   'world.board_sell_memo(uuid,uuid,jsonb,jsonb)'];
  v_lis   uuid := (select p.id from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR');
  v_svq   uuid := (select p.id from public.ports p where p.code = 'SVQ' and p.kind = 'HARBOUR');
  v_a uuid; v_fa uuid; v_b uuid; v_fb uuid; v_c uuid; v_fc uuid;
  v_good  uuid;
  v_bad   text;
  v_k     text;
  v_was   jsonb := '{}'::jsonb;
  v_def   text;
  v_new   jsonb := '{}'::jsonb;
  v_old   jsonb := '{}'::jsonb;
  v_t     timestamptz;
  v_ms_new numeric;
  v_ms_old numeric;
  x       record;
begin
  -- PO_SHAPE
  select string_agg(u, ', ') into v_bad from unnest(c_new) u
   where to_regprocedure(u) is null or has_function_privilege('anon', u, 'execute') or has_function_privilege('authenticated', u, 'execute')
      or has_function_privilege('service_role', u, 'execute');
  if v_bad is not null then
    raise exception 'PO_SHAPE: missing or not server-only: %', v_bad;
  end if;
  if md5(pg_temp.p191_body(pg_temp.p191_unhunk('world.best_sales(uuid,uuid)'))) <> '3f71e6c4c3e6ab4241af0d546e2bdec5'
     or md5(pg_temp.p191_body(pg_temp.p191_unhunk('world.board_sell_memo(uuid,uuid,jsonb,jsonb)'))) <> '081f8ae0ac7be74eebb5dfc13a277cf1' then
    raise exception 'PO_SHAPE: world.best_sales or world.board_sell_memo does not reverse to the body 0488 found';
  end if;
  if exists (select 1 from p191_old o where md5(o.src) <> o.md5) then
    raise exception 'PO_SHAPE: an old body here is not the one 0488 found';
  end if;
  if (select p.prosrc from pg_proc p where p.oid = 'world.board_sell(uuid,uuid,jsonb)'::regprocedure) not like '%world.board_sell_memo(p_good, p_fleet, p_ctx, null)%'
     or (select p.prosrc from pg_proc p where p.oid = 'public.port_fee(uuid,uuid,numeric)'::regprocedure) not like '%public.port_fee_of(public.port_fee_terms(p_port, p_player), p_value)%'
     or (select p.prosrc from pg_proc p where p.oid = 'world.quote_terms(uuid,uuid,uuid)'::regprocedure) not like '%world.quote_terms_from(%'
     or (select p.prosrc from pg_proc p where p.oid = 'world.spread_effective_pair(uuid,uuid,uuid,boolean)'::regprocedure) not like '%world.spread_pair_from(%'
     or (select p.prosrc from pg_proc p where p.oid = 'public.profit_tax(uuid,numeric,uuid)'::regprocedure) not like '%public.profit_tax_at(%' then
    raise exception 'PO_SHAPE: a re-cut body is not 0488''s';
  end if;
  raise notice 'PASS: PO_SHAPE — the nine new pieces exist, none runnable by anon, authenticated or service_role; world.best_sales and world.board_sell_memo reverse to the bodies 0488 found; the four small bodies read through the pieces';

  -- the houses: A rich at Lisbon with a captain seated and a mastery; B a thin purse at Lisbon; C at Seville
  v_a := public.new_house(c_a, 'Casa do Porto 191', 'PRT');
  v_b := public.new_house(c_b, 'Casa Magra 191', 'PRT');
  v_c := public.new_house(c_c, 'Casa de Sevilla 191', 'ESP', 'SVQ');
  select f.id into v_fa from public.fleets f where f.player_id = v_a;
  select f.id into v_fb from public.fleets f where f.player_id = v_b;
  select f.id into v_fc from public.fleets f where f.player_id = v_c;
  update public.players p set ducats = 2000000 where p.id in (v_a, v_c);
  update public.players p set ducats = 900 where p.id = v_b;
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

  -- WITH 0488's BODIES: the switches as they are (A), then lit (A, B, C; the memo threaded; best_sales with its budget off)
  perform cmd.assume_identity(c_a);
  v_new := v_new || jsonb_build_object('dark', pg_temp.p191_pieces(v_a, v_fa, false));
  foreach v_k in array c_lit loop
    if exists (select 1 from public.world_config c where c.key = v_k and c.value is distinct from 'true'::jsonb) then
      v_was := v_was || jsonb_build_object(v_k, (select c.value from public.world_config c where c.key = v_k));
      update public.world_config c set value = 'true'::jsonb where c.key = v_k;
    end if;
  end loop;
  perform pg_temp.p191_open();
  for x in select * from (values (1, c_a, v_a, v_fa, v_lis), (2, c_b, v_b, v_fb, v_lis), (3, c_c, v_c, v_fc, v_svq)) h(k, uid, pl, fl, at) order by h.k loop
    perform cmd.assume_identity(x.uid);
    v_new := v_new || jsonb_build_object('lit' || x.k, pg_temp.p191_pieces(x.pl, x.fl, false), 'memo' || x.k, pg_temp.p191_pieces(x.pl, x.fl, true));
    v_t := clock_timestamp();
    v_new := v_new || jsonb_build_object('best' || x.k, pg_temp.p191_best(x.fl, x.at));
    if x.k = 1 then
      v_ms_new := round(extract(epoch from clock_timestamp() - v_t)::numeric * 1000);
    end if;
  end loop;

  -- THE SIX BODIES BACK AS THEY WERE BEFORE 0488
  execute pg_temp.p191_unhunk('world.best_sales(uuid,uuid)');
  execute pg_temp.p191_unhunk('world.board_sell_memo(uuid,uuid,jsonb,jsonb)');   -- its first hunk put back names it world.board_sell: the old body
  for x in select * from p191_old o loop
    v_def := pg_get_functiondef(x.fn::regprocedure);
    execute replace(v_def, (select p.prosrc from pg_proc p where p.oid = x.fn::regprocedure), x.src);
  end loop;
  if exists (select 1 from (values ('world.best_sales(uuid,uuid)', '3f71e6c4c3e6ab4241af0d546e2bdec5'), ('world.board_sell(uuid,uuid,jsonb)', '081f8ae0ac7be74eebb5dfc13a277cf1')) v(fn, md5)
              join pg_proc p on p.oid = v.fn::regprocedure where md5(replace(p.prosrc, E'\r', '')) <> v.md5)
     or exists (select 1 from p191_old o join pg_proc p on p.oid = o.fn::regprocedure where md5(replace(p.prosrc, E'\r', '')) <> o.md5) then
    raise exception 'PO_SHAPE: a body did not go back to the one 0488 found';
  end if;

  -- AND EVERYTHING AGAIN WITH THE OLD BODIES (the memo threaded is held against the old plain rows)
  update public.world_config c set value = v_was->c.key where v_was ? c.key;
  perform cmd.assume_identity(c_a);
  v_old := v_old || jsonb_build_object('dark', pg_temp.p191_pieces(v_a, v_fa, false));
  update public.world_config c set value = 'true'::jsonb where v_was ? c.key;
  perform pg_temp.p191_open();
  for x in select * from (values (1, c_a, v_a, v_fa, v_lis), (2, c_b, v_b, v_fb, v_lis), (3, c_c, v_c, v_fc, v_svq)) h(k, uid, pl, fl, at) order by h.k loop
    perform cmd.assume_identity(x.uid);
    v_old := v_old || jsonb_build_object('lit' || x.k, pg_temp.p191_pieces(x.pl, x.fl, false));
    v_t := clock_timestamp();
    v_old := v_old || jsonb_build_object('best' || x.k, pg_temp.p191_best(x.fl, x.at));
    if x.k = 1 then
      v_ms_old := round(extract(epoch from clock_timestamp() - v_t)::numeric * 1000);
    end if;
  end loop;

  select string_agg(k || '.' || j, ', ') into v_bad
    from jsonb_object_keys(v_old) k cross join lateral jsonb_object_keys(case when k not like 'best%' then v_old->k else '{"*": 1}'::jsonb end) j
   where case when j = '*' then v_old->k is distinct from v_new->k else v_old->k->j is distinct from v_new->k->j end;
  if v_bad is not null then
    raise exception 'PO_PIECES: answers differently before and after 0488: %', v_bad;
  end if;
  select string_agg(v.m || '.' || j, ', ') into v_bad
    from (values ('memo1', 'lit1'), ('memo2', 'lit2'), ('memo3', 'lit3')) v(m, l) cross join lateral jsonb_object_keys(v_new->v.m) j
   where v_new->v.m->j is distinct from v_old->v.l->j;
  if v_bad is not null then
    raise exception 'PO_PIECES: world.board_sell_memo threaded answers differently from the old world.board_sell: %', v_bad;
  end if;
  if (select count(*) from jsonb_object_keys(v_old->'lit1') k where k like 'sell:%') = 0 or (select count(*) from jsonb_object_keys(v_old->'lit3') k where k like 'sell:%') = 0
     or jsonb_array_length(v_old->'lit1'->'quotes') = 0
     or not exists (select 1 from jsonb_array_elements(v_old->'lit1'->'fees') e where (e->>2)::numeric > 0)
     or not exists (select 1 from jsonb_array_elements(v_old->'lit1'->'fees') e where (e->>7)::numeric > 0) then
    raise exception 'PO_PIECES: the inputs were empty (no sale, quote, dock fee or profit tax above nought)';
  end if;
  raise notice 'PASS: PO_PIECES — % quote terms and spreads (with her fleet and none), % quotes, % dock fees and profit taxes, world.board_sell for % goods three ways (the read''s, an asked count, a full board) and world.board_sell_memo threaded: the same before and after 0488, at Lisbon (a captain and a mastery; a thin purse) and Seville, lit and as the switches are',
    jsonb_array_length(v_old->'lit1'->'terms') * 5, jsonb_array_length(v_old->'lit1'->'quotes') * 2, jsonb_array_length(v_old->'lit1'->'fees') * 10,
    (select count(*) from jsonb_object_keys(v_old->'lit1') k where k like 'sell:%') + (select count(*) from jsonb_object_keys(v_old->'lit3') k where k like 'sell:%');
  if jsonb_array_length(v_old->'best1'->'goods') = 0 or jsonb_array_length(v_old->'best3'->'goods') = 0 then
    raise exception 'PO_BEST: no good answered';
  end if;
  raise notice 'PASS: PO_BEST — world.best_sales with its budget off: the same before and after 0488 for the three houses, lit (% + % + % goods)',
    jsonb_array_length(v_old->'best1'->'goods'), jsonb_array_length(v_old->'best2'->'goods'), jsonb_array_length(v_old->'best3'->'goods');
  raise notice 'PASS: PO_COST — world.best_sales, budget off, the rich house at Lisbon, lit: % ms with 0488''s bodies, % ms with the old ones (server %; one call each, after the pieces warmed them)',
    v_ms_new, v_ms_old, current_setting('server_version');
end $p$;
