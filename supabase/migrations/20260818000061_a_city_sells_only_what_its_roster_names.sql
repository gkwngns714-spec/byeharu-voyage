-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0061 — A CITY SELLS ONLY WHAT ITS ROSTER NAMES
--        The roster stops being a price affinity and becomes the QUAY: a captain may buy, at a
--        city, exactly the goods that city trades — and nothing else. She may still SELL anything
--        she is carrying, anywhere, because a hold that cannot be emptied is not a game.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE ASK, SAID TWICE ────────────────────────────────────────────────────────────────────────
-- docs/OWNER_REQUESTS.md row 48, verbatim:
--
--   "i told you, min 4, max 10 trades goods per city. there should be a purpose to go to a city
--    that is far away to get rare trade goods. i told you, capital cities - 10 items, mid sized
--    cities - 4~8, small cities 4, randomly distributed"
--
-- ── WHY 0058 DID NOT ANSWER IT, NAMED ──────────────────────────────────────────────────────────
-- 0058 built the roster in `public.port_specialties` and made its COUNT obey the owner's numbers.
-- What `port_specialties` decides is AFFINITY (0005:196 `world.affinity_for` — a port that
-- produces a good sells it cheap). It does not decide what is ON THE QUAY. The market table,
-- `public.port_goods`, still carries one row per (harbour, good) — MEASURED on this machine
-- 2026-08-26 against the applied chain through 0059: 54,432 rows = 224 harbours x 243 goods — so
-- `world.market` (0032, the MARKET screen's one read) listed all 243 goods at every city and
-- `cmd.do_buy` let a captain buy any of them anywhere. The owner then said the same thing again,
-- which is what a repeated instruction always means: the wrong thing shipped.
--
-- The owner's OWN reason is the thing this file is graded on — "there should be a purpose to go to
-- a city that is far away to get rare trade goods." A purpose exists only if the good cannot be
-- had at home. That is a rule about BUYING, and this file makes exactly that rule true.
--
-- ── THE DECISION: BUY IS THE ROSTER, SELL IS NOT — AND WHY THAT ASYMMETRY IS DELIBERATE ────────
-- The owner's words are about what a captain can GET at a city. Restricting SELL as well was
-- considered and REFUSED, on measurements taken here rather than on taste:
--
--   * the roster names 1,288 (port, good) pairs over 243 goods — MEASURED: a good is on the
--     roster of 5.30 harbours on average, minimum 0, maximum 50;
--   * so a hold full of a good would have, typically, FIVE buyers in a world of 224 harbours, and
--     three goods (measured) are on no roster at all and would have NONE;
--   * cargo already afloat when this migration lands would become unsellable at the port the
--     fleet is standing in, with no way to know where it could be sold.
--
-- That is a game-breaking outcome and it is not what was asked for, so it is not what was built.
-- `cmd.do_sell` is DELIBERATELY NOT TOUCHED by this file. A city buys what a captain offers it;
-- it only SELLS what it trades. Every `public.port_goods` row therefore survives — the row is the
-- PRICE, and a price must exist for a sale to be possible at all. See "WHAT THIS FILE
-- DELIBERATELY DOES NOT TOUCH", below, for what that costs and what it buys.
--
-- ── COMPOSED ONTO THE REFUSAL THAT ALREADY EXISTS, NOT A SECOND ONE ────────────────────────────
-- `cmd.do_buy` already refuses a good a port will not trade, and says it in the sentence a player
-- already reads (0007:435-443, still the live text, re-read out of `pg_get_functiondef` on this
-- machine today):
--
--     raise exception 'E_UNAVAILABLE: % is not traded in this port', g.name
--
-- That refusal exists for the CULTURE mask (DESIGN B.4). The roster is a SECOND REASON the same
-- sentence is true, so this file adds a gate that raises the SAME refusal from a NEW authority
-- rather than inventing a second vocabulary. `cmd.refusal_caught` (0050), the client's refusal
-- rendering and every fixes-list downstream are untouched by construction.
--
-- ── ONE AUTHORITY, AND IT READS THE ROSTER — IT DOES NOT RE-DERIVE IT ──────────────────────────
--     public.port_offers(port, good)  ->  "is this good on this city's quay?"
--
-- It is `exists (select 1 from public.port_specialties ...)`. It does NOT call
-- `public.roster_target_count` or `public.roster_rng` (0058), it does not count anything, and it
-- has no opinion about how many goods a city ought to name. That is deliberate and it is a
-- REQUIREMENT: the CONTENT of the roster is being restored to `data/ports.json`'s authored,
-- historically-grounded lists in a separate slice (0058's seeded hash dropped 78 authored pairs
-- and filled 56 arbitrary ones — its own receipt: "78 offer(s) dropped, 56 offer(s) filled").
-- Every rule and every assert in this file must go on being true the moment that content changes
-- underneath it, so nothing here pins WHICH goods a city names, and the only count this file
-- asserts is the owner's own band, 4..10 (docs/OWNER_REQUESTS.md row 48: "min 4, max 10").
--
-- ── AND ONE MORE, BECAUSE A QUAY MUST SHOW HER WHAT SHE IS CARRYING ────────────────────────────
--     public.quay_shows(port, good)  ->  "does this quay's market read list this good?"
--                                     =  port_offers(port, good)
--                                        OR a fleet of the reader's lies here carrying it
--
-- Without the second half, SELL is legal on the server and UNREACHABLE in the game:
-- `src/features/command/ArgPickers.tsx:471` draws the SELL list from `world.market(port).goods`
-- intersected with what is aboard, and a good the read omits has no price to sell at and no row
-- to tap. A capability that exists but cannot be exercised is the shape docs/NO_SPAGHETTI.md §7C
-- forbids, so the read carries the cargo rows, flagged `offered: false`, and they may be sold and
-- never bought. It COMPOSES `public.fleet_cargo_qty` (0007:223) rather than reaching into
-- `ships.cargo` itself — "how much of this is aboard" has one author and this file does not
-- become its second.
--
-- ── WHAT MOVES, ALL OF IT IN THIS FILE (docs/NO_SPAGHETTI.md §3.2) ─────────────────────────────
--   * cmd.do_buy                   — SUPERSEDES 0050's cut of 0022:674. One gate added: the
--                                    roster, raising the refusal already quoted above.
--   * world.market                 — SUPERSEDES 0032:189. Two hunks: the goods list is restricted
--                                    to `public.quay_shows`, and each row carries `offered`.
--   * world.trade_routes           — SUPERSEDES 0019:676 as 0047 re-cut it (the third argument
--                                    became a sailed radius in nm, so the live signature is
--                                    (uuid, uuid, numeric, int, uuid)). One hunk, and it was found by a PROOF
--                                    rather than by reasoning: the scan's origin CTE was still
--                                    naming cargoes cmd.do_buy would refuse. Origin only.
--   * public.tick_price_snapshot   — SUPERSEDES 0057's cut of 0013:97. One hunk: the record
--                                    samples the pairs the quay OFFERS, not every pair that has a
--                                    price. A price nobody can be shown is not a record worth
--                                    keeping, and it is 97.6% of the table.
--   * public.price_history         — the rows for pairs no quay offers are DELETED. Deleting the
--                                    writer's reach without deleting what it already wrote would
--                                    leave the table's whole cost in place and prove nothing.
--
-- Each function body is SLICED out of the DEPLOYED definition with `pg_temp.recut` (0050:120,
-- copied below because `pg_temp` cannot be inherited across migrations). Every hunk must occur
-- EXACTLY ONCE in `pg_get_functiondef`, so a drifted deployment REFUSES rather than half-applies.
-- The hunks were sliced from a locally applied chain on 2026-08-26 and are LF only (.gitattributes
-- forces LF on *.sql for exactly this reason — CRLF baked into a hunk can never match).
--
-- ── PRODUCTION IS NOT AN EMPTY DATABASE, AND 0057 IS THE SCAR ──────────────────────────────────
-- 0057 was green on PGlite and green on CI's disposable Supabase and FAILED the production push,
-- because both engines boot empty and production carries live rows. So, explicitly:
--
--   * THIS FILE INSERTS NOTHING and UPDATES NO GAME STATE. There is no row it can collide with.
--   * `public.port_goods` IS NOT TOUCHED — not one row, not one column. Every price a live player
--     can see or trade at is bit-identical after this migration. Stock, drift, season_mod and
--     affinity are exactly what they were.
--   * A HOLD FULL OF CARGO IS SAFE. `cmd.do_sell` is unchanged, so anything afloat right now can
--     still be sold at the port the fleet is standing in, at the price it would have fetched
--     yesterday. Self-assert (f) proves this by SELLING a good the port does not offer, on a real
--     fleet with real cargo, and requiring the ducats to land.
--   * AN OPEN ORDER IS REFUSED, NOT CRASHED. A queued BUY of a good the port does not trade now
--     raises E_UNAVAILABLE inside `cmd.execute_order`, which already catches an `E_*` refusal and
--     records it on the order (0050). Self-assert (e) drives exactly that path and reads the
--     refusal code back rather than trusting the shape.
--   * THE ONLY DELETE IS `public.price_history`, and it is bounded and reversible-by-time: the
--     table is a RECORD, never a source (0013's own comment), nothing reads it but the chart, and
--     the rows removed are the ones no client can ever be shown again. On this machine the delete
--     removes 53,630 of 54,918 rows; on production the same predicate removes the same 97.6%.
--   * FK / CASCADE, CHECKED NOT ASSUMED. Queried on the applied chain today:
--       - `select conname from pg_constraint where confrelid = 'public.port_goods'::regclass`
--         returns ZERO ROWS. NOTHING in the schema references `public.port_goods`, so no delete
--         anywhere can cascade through it — and this file deletes none of it in any case.
--       - `public.price_history`'s two FKs are `port_id -> ports(id) on delete cascade` and
--         `good_id -> goods(id) on delete cascade` (0013:53-54). Both point AT ports and goods,
--         not at `port_goods`. Deleting price_history rows cascades to nothing: no table
--         references `price_history` at all.
--   * IDEMPOTENT ON REPLAY. The delete's predicate is `not public.port_offers(...)`; a second run
--     finds nothing left to delete. The three re-cuts are `create or replace` of a body that then
--     names `public.port_offers` — which is why assert (i) counts the name in the DEPLOYED text
--     rather than trusting that the slice ran.
--
-- ── WHAT IT DOES TO THE DISK, MEASURED, AND THE SEAM IT LEAVES NAMED ───────────────────────────
-- 0057 made the retention window a DISK BUDGET divided by the world's pair count:
-- `price_history_window() = greatest(48, floor(629,145,600 / (pairs x 201)))`, reading
-- `count(*) from public.port_goods`. THIS FILE DOES NOT CHANGE THAT LAW and does not change its
-- input: `port_goods` still holds 54,432 rows, so the window stays at **57 slots** (measured, not
-- recalled). What changes is what the WRITER writes:
--
--     before   54,432 pairs x 57 slots x 201 bytes/row  =  623,627,424 B  ~= 594.7 MiB
--     after     1,288 pairs x 57 slots x 201 bytes/row  =   14,750,616 B  ~=  14.1 MiB
--
-- a 97.6% cut, and it is the number that decides whether this project fits Supabase's free 500 MB
-- database. THE SEAM, NAMED RATHER THAN HIDDEN: 0057's divisor is now an UPPER BOUND on the pairs
-- the record can hold rather than the exact count, which makes the budget CONSERVATIVE — it sizes
-- the window for 42x more pairs than are written. Pointing `price_history_window()` at the offered
-- count instead would raise the window to 2,430 slots (measured: `price_history_window_for(1288)`)
-- and put the ceiling straight back to ~600 MiB, because a budget-filling law fills its budget.
-- That is a decision about how much history is worth keeping, it belongs to whoever next revisits
-- 0057's budget, and this file deliberately does not take it.
--
-- ── WHAT THIS FILE DELIBERATELY DOES NOT TOUCH ────────────────────────────────────────────────
--   * `public.port_goods` — see the decision above. The row is the price; deleting it would take
--     SELL down with it, since `world.quote`, `world.price` and `world.mid_price` all raise
--     E_NO_SUCH_GOOD without one (0005:350/383/426, 0053:435).
--   * `cmd.do_sell` — the asymmetry IS the design. Its culture gate stays exactly as it was.
--   * `public.port_specialties` and its CONTENT — this file reads the roster and never writes it.
--     0058's `roster_rng` / `roster_target_count` are not called here at all.
--   * `world.trade_routes`'s DESTINATION side (0019:676) — see statement 4b. Its ORIGIN side IS
--     narrowed here, because the origin is where a BUY happens; the far end is a SELL and selling
--     is not gated by the roster, so a city that does not trade a good may still be the best place
--     to carry it. Narrowing both ends would have deleted the owner's own point.
--   * The world's affinity, stock, drift, prices, fairs, fame, rarity — untouched, and assert (g)
--     re-reads a price at a port before and after to prove it.
--
-- ── SPAGHETTI, NAMED AND NOT ADDED TO ──────────────────────────────────────────────────────────
-- The culture predicate `culture = any(g.culture_mask)` is written FIVE times in the live schema —
-- `cmd.do_buy`, `cmd.do_sell`, `world.market`, `world.trade_routes` and `cmd.haggle`. That is
-- spaghetti by docs/NO_SPAGHETTI.md §1's own count, it predates this file, and folding five live
-- bodies in a migration whose subject is the roster would triple the blast radius on a live game.
-- What this file DOES do is refuse to become the sixth: `public.port_offers` answers the ROSTER
-- question only and contains no copy of the culture rule. The fold is named here so it cannot be
-- lost. MEASURED consequence of leaving it: 2 (port, good) pairs are on a roster AND blocked by
-- their port's culture, so 2 harbours offer one fewer BUYABLE good than their roster names. That
-- is content, not mechanism; assert (c) therefore bands the ROSTER, which is what the owner's
-- sentence is about.
--
-- Depends on: 0002 (ports/goods/port_specialties), 0005 (port_goods, world.price/quote/mid_price),
-- 0007 (cmd.do_buy's refusals, fleet_cargo_qty, fleet_load), 0013 (price_history, the snapshot),
-- 0022/0050 (the deployed do_buy body this file slices), 0032 (the deployed world.market body),
-- 0057 (price_history_window, the deployed tick_price_snapshot body), 0058 (the roster this file
-- READS and never re-derives).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ── 0. The slice tool: replace hunks that must occur exactly once, else refuse (0050:120) ──────
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
      raise exception '0061 slice: hunk % of % occurs % time(s) in %, expected exactly 1 — the deployed body is not what this migration was generated against.',
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

-- ── 0b. BEFORE, captured for the report and for the asserts that must compare against it ───────
create temporary table quay_before_0061 as
select
  (select count(*) from public.port_goods)                                as market_rows,
  (select count(*) from public.port_specialties)                          as roster_rows,
  (select count(*) from public.ports where kind = 'HARBOUR')              as harbours,
  (select count(*) from public.goods)                                     as goods,
  (select count(*) from public.price_history)                             as history_rows,
  (select public.price_history_window())                                  as window_slots;

-- ── 1. THE AUTHORITY — "is this good on this city's quay?" ─────────────────────────────────────
-- `create`, not `create or replace`: this file claims the function is NEW (0051:252's convention).
--
-- `language sql` / `stable` / no `security definer`, and every one of those is deliberate:
-- PostgreSQL's inline_function() refuses a definer function, and this predicate is asked once per
-- (port, good) pair by public.tick_price_snapshot — 54,432 times per tick. An un-inlined callee
-- there would be 54,432 function calls where the planner can otherwise fold the EXISTS into the
-- scan. Every path that reaches it enters through a SECURITY DEFINER function already — cmd.do_buy,
-- world.market and public.tick_price_snapshot call it directly, and public.quay_shows (also an
-- invoker, for the same inlining reason) is reached only from world.market — so it never needs
-- privileges of its own, and both are revoked from every client role below.
create function public.port_offers(p_port uuid, p_good uuid)
returns boolean
language sql
stable
parallel safe
as $$
  select exists (select 1 from public.port_specialties s
                  where s.port_id = p_port and s.good_id = p_good)
$$;

comment on function public.port_offers(uuid, uuid) is
  'THE QUAY (0061): does this city offer this good for sale? It READS public.port_specialties — '
  'the one authority for what a city trades — and derives nothing. It deliberately does NOT call '
  'public.roster_target_count or public.roster_rng (0058) and has no opinion about how many goods '
  'a city ought to name, so it goes on being correct when the roster''s CONTENT is restored to '
  'data/ports.json''s authored lists. It deliberately does NOT fold the culture mask either: that '
  'rule has its own (five, see 0061''s header) readers and this function does not become a sixth. '
  'cmd.do_buy, world.market and public.tick_price_snapshot are its callers; none of them re-asks '
  'the roster table itself.';

revoke all on function public.port_offers(uuid, uuid) from public, anon, authenticated;

-- ── 2. WHAT A QUAY SHOWS — the roster, plus whatever she is carrying here so she can sell it ────
create function public.quay_shows(p_port uuid, p_good uuid)
returns boolean
language sql
stable
as $$
  select public.port_offers(p_port, p_good)
      or exists (
           select 1
             from public.fleets f
             join public.goods  g on g.id = p_good
            where f.player_id = public.current_player_id()
              and f.port_id   = p_port
              and f.status    = 'DOCKED'
              and public.fleet_cargo_qty(f.id, g.code) > 0
         )
$$;

comment on function public.quay_shows(uuid, uuid) is
  'What world.market lists at a quay (0061): every good the city OFFERS (public.port_offers), plus '
  'every good a fleet of the READER''S is lying here carrying — because cmd.do_sell will buy '
  'anything she carries and a row she cannot see is a sale she cannot make '
  '(src/features/command/ArgPickers.tsx:471 draws the SELL list from this read). The second half '
  'composes public.fleet_cargo_qty (0007:223) rather than reading ships.cargo itself. A row it '
  'admits for the second reason carries offered=false and may be sold, never bought — cmd.do_buy '
  'asks public.port_offers, not this.';

revoke all on function public.quay_shows(uuid, uuid) from public, anon, authenticated;

-- ── 3. BUY IS THE ROSTER — SUPERSEDES 0050's cut of 0022:674 ───────────────────────────────────
-- ONE gate, raising the refusal cmd.do_buy already raises for the culture mask. Placed BEFORE the
-- market-row read so that "this city does not trade it" is the reason a player is given, rather
-- than the structural "no market row here" that would never fire (every pair still has a row).
select pg_temp.recut('cmd.do_buy(uuid, jsonb)'::regprocedure, false,
  $b0$  select stock into v_stock from public.port_goods where port_id = f.port_id and good_id = g.id;
  if v_stock is null then raise exception 'E_NO_SUCH_GOOD: no market for % here', g.name using errcode = 'P0001'; end if;$b0$,
  $b1$  -- 0061: A CITY SELLS ONLY WHAT ITS ROSTER NAMES. public.port_offers is the one authority
  -- for "is this good on this city's quay?"; the sentence is the one this verb already raises for
  -- the culture mask, because from the captain's side it is the same fact.
  if not public.port_offers(f.port_id, g.id) then
    raise exception 'E_UNAVAILABLE: % is not traded in this port', g.name using errcode = 'P0001';
  end if;

  select stock into v_stock from public.port_goods where port_id = f.port_id and good_id = g.id;
  if v_stock is null then raise exception 'E_NO_SUCH_GOOD: no market for % here', g.name using errcode = 'P0001'; end if;$b1$);
revoke all on function cmd.do_buy(uuid, jsonb) from public, anon, authenticated;

comment on function cmd.do_buy(uuid, jsonb) is
  'THE BUY (0022''s body, 0050''s refusals). SUPERSEDED BY 0061 in one gate: a captain may buy, at '
  'a city, exactly the goods public.port_offers names — docs/OWNER_REQUESTS.md row 48. cmd.do_sell '
  'is deliberately NOT gated the same way (0061''s header): a city buys what is offered to it and '
  'only sells what it trades, so no hold can be stranded.';

-- ── 4. THE MARKET READ SERVES THE QUAY — SUPERSEDES 0032:189 ──────────────────────────────────
select pg_temp.recut('world.market(uuid)'::regprocedure, false,
  $m0$        'available', not (pr.culture = any(g.culture_mask)),$m0$,
  $m1$        'available', not (pr.culture = any(g.culture_mask)),
        -- 0061 QUAY: `available` is the CULTURE fact and is unchanged. `offered` is the ROSTER
        -- fact, from public.port_offers. A row with offered=false is in this payload only because
        -- she is carrying it here: it may be SOLD on this quay and it may never be bought.
        'offered', public.port_offers(pg.port_id, pg.good_id),$m1$,
  $m2$     cross join lateral world.price(pg.port_id, pg.good_id) q
     where pg.port_id = p_port),$m2$,
  $m3$     cross join lateral world.price(pg.port_id, pg.good_id) q
     where pg.port_id = p_port
       and public.quay_shows(pg.port_id, pg.good_id)),$m3$);
revoke all on function world.market(uuid) from public, anon;
grant execute on function world.market(uuid) to authenticated;

-- ── 4b. THE QUAY NEVER NAMES A TRADE THE VERB WOULD REFUSE — SUPERSEDES 0019:676 ──────────────
-- CAUGHT BY scripts/db/proofs/04_first_session.sql, not reasoned out in advance, and that is worth
-- recording: this file's first draft left world.trade_routes alone on the argument that it joins
-- public.port_goods at BOTH ends. It does — and every (harbour, good) pair still HAS a port_goods
-- row, so that join restricts nothing. The scan's `here` CTE was therefore still proposing that a
-- captain BUY, at Lisboa, a good Lisboa does not trade, which `cmd.do_buy` now refuses. Proof 4
-- read it back as *"the quay named civet and Lisboa's market serves it 0 time(s)"*.
--
-- That is 0017:50-55's scar exactly — a rule wired into one half and not the other — and the fix
-- belongs in THIS file for 0017's own reason, not in a follow-up: the quay may not promise what
-- the verb will refuse.
--
-- ONLY the origin is narrowed. The DESTINATION side is deliberately left open, and that is the
-- same asymmetry the whole file rests on: the far end is a SELL, cmd.do_sell is not gated by the
-- roster, and every port has a price for every good — so a city that does not trade a good may
-- still be the best place to take it. Narrowing the destination would have thrown away the owner's
-- own point ("a purpose to go to a city that is far away") by construction.
select pg_temp.recut('world.trade_routes(uuid, uuid, numeric, int, uuid)'::regprocedure, false,
  $r0$     where pg.port_id = p_from
       and not (p.culture = any(g.culture_mask))$r0$,
  $r1$     where pg.port_id = p_from
       and not (p.culture = any(g.culture_mask))
       -- 0061: and she can only LOAD what this city trades. Same authority cmd.do_buy asks, so the
       -- shortlist cannot name a cargo the order would refuse. The destination is NOT filtered:
       -- selling is not gated by the roster (see this file's header).
       and public.port_offers(p_from, pg.good_id)$r1$);
revoke all on function world.trade_routes(uuid, uuid, numeric, int, uuid) from public, anon;
grant execute on function world.trade_routes(uuid, uuid, numeric, int, uuid) to authenticated;

-- ── 5. THE RECORD KEEPS WHAT THE QUAY OFFERS — SUPERSEDES 0057's cut of 0013:97 ───────────────
select pg_temp.recut('public.tick_price_snapshot(timestamptz)'::regprocedure, false,
  $t0$    from public.port_goods pg
  on conflict (port_id, good_id, slot) do nothing;$t0$,
  $t1$    from public.port_goods pg
   -- 0061: a price nobody can be shown is not a record worth keeping. The chart is drawn on the
   -- MARKET screen, which serves world.market — the quay. 97.6% of this table was pairs no client
   -- could ever ask for. 0057's window law and its 600 MiB budget are UNTOUCHED.
   where public.port_offers(pg.port_id, pg.good_id)
  on conflict (port_id, good_id, slot) do nothing;$t1$);
revoke all on function public.tick_price_snapshot(timestamptz) from public, anon, authenticated;

-- ── 6. AND WHAT IT ALREADY WROTE GOES WITH IT ─────────────────────────────────────────────────
-- Bounded, idempotent, and cascades to nothing: no table references public.price_history, and its
-- own two FKs point at ports and goods (0013:53-54), never at port_goods. See the header.
delete from public.price_history h
 where not public.port_offers(h.port_id, h.good_id);

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_harbours   int;
  v_goods      int;
  v_market     int;
  v_roster     int;
  v_n          int;
  v_bad        int;
  v_list       text;
  v_off_true   int;
  v_off_false  int;
  v_min_c      int;
  v_max_c      int;
  v_dist       text;
  v_port       uuid;
  v_port_code  text;
  v_mkt        jsonb;
  v_mkt_n      int;
  v_probe      constant uuid := '00000000-0061-4000-8000-000000000001';
  v_player     uuid;
  v_fleet      uuid;
  v_on         uuid;   -- a good this port DOES offer
  v_off        uuid;   -- a good this port does NOT offer
  v_on_code    text;
  v_off_code   text;
  v_res        jsonb;
  v_code       text;
  v_purse0     bigint;
  v_purse1     bigint;
  v_cargo0     numeric;
  v_cargo1     numeric;
  v_sold       jsonb;
  v_hist_before int;
  v_hist_after  int;
  v_qty        numeric;
  v_order      uuid;
  v_routes     jsonb;
  v_n2         int;
  v_wrote      int;
  v_window     int;
  v_price0     numeric;
  v_price1     numeric;
  v_def        text;
begin
  -- (a) NON-VACUOUS FLOOR. Nothing below can prove anything against an empty world, and every
  --     count this file reports is taken from the tables rather than pinned.
  select harbours, goods, market_rows, roster_rows, history_rows, window_slots
    into v_harbours, v_goods, v_market, v_roster, v_hist_before, v_window
    from quay_before_0061;
  if v_harbours = 0 or v_goods = 0 or v_market = 0 or v_roster = 0 then
    raise exception '0061 self-assert FAIL: % harbour(s), % good(s), % market row(s), % roster row(s) — this world cannot prove anything',
      v_harbours, v_goods, v_market, v_roster;
  end if;

  -- (b) THE RULE, BOTH DIRECTIONS: public.port_offers answers TRUE for exactly the pairs
  --     public.port_specialties names, and FALSE for every other (harbour, good) pair. Asserted as
  --     a disagreement count over the whole market table, so it cannot pass vacuously; the two
  --     populations are counted and required to be non-empty first.
  select count(*) filter (where public.port_offers(pg.port_id, pg.good_id)),
         count(*) filter (where not public.port_offers(pg.port_id, pg.good_id))
    into v_off_true, v_off_false
    from public.port_goods pg;
  if v_off_true = 0 or v_off_false = 0 then
    raise exception '0061 self-assert FAIL: port_offers answers true on % pair(s) and false on % — one of the two populations is empty and the rule below would prove nothing',
      v_off_true, v_off_false;
  end if;
  select count(*) into v_bad
    from public.port_goods pg
   where public.port_offers(pg.port_id, pg.good_id)
         is distinct from exists (select 1 from public.port_specialties s
                                   where s.port_id = pg.port_id and s.good_id = pg.good_id);
  if v_bad <> 0 then
    raise exception '0061 self-assert FAIL: public.port_offers disagrees with the roster on % of % market pair(s)', v_bad, v_market;
  end if;
  -- ... and it never invents a quay for a place that has none (a SEA_PLACE carries no roster).
  select count(*) into v_bad
    from public.ports p cross join public.goods g
   where p.kind <> 'HARBOUR' and public.port_offers(p.id, g.id);
  if v_bad <> 0 then
    raise exception '0061 self-assert FAIL: % (sea place, good) pair(s) are reported as offered', v_bad;
  end if;

  -- (c) THE OWNER'S BAND, AND NOTHING NARROWER. "min 4, max 10 trades goods per city"
  --     (docs/OWNER_REQUESTS.md row 48). The exact per-tier counts are DELIBERATELY not asserted:
  --     the roster's CONTENT is being restored to data/ports.json's authored lists in a separate
  --     slice, and an assert pinned to today's membership would go red on a correct world. The
  --     distribution is REPORTED below instead, as a measurement.
  --     The band is written ONCE, in the `where` below, and the count and the named offenders both
  --     come out of it — so a message can never describe a different test from the one that fired.
  select count(*), string_agg(code || '=' || c, ', ' order by c, code)
    into v_bad, v_list
    from (select p.code, (select count(*)::int from public.port_specialties s where s.port_id = p.id) as c
            from public.ports p where p.kind = 'HARBOUR') y
   where c < 4 or c > 10;
  select min(c), max(c) into v_min_c, v_max_c
    from (select p.id, (select count(*)::int from public.port_specialties s where s.port_id = p.id) as c
            from public.ports p where p.kind = 'HARBOUR') x;
  if v_bad <> 0 then
    raise exception '0061 self-assert FAIL: % harbour(s) offer a number of goods outside the owner''s 4..10 (the world spans % .. %): %', v_bad, v_min_c, v_max_c, v_list;
  end if;
  select string_agg(t, '  ' order by t) into v_dist
    from (select 'tier' || p.size_tier || ': ' || count(*) || ' ports, ' ||
                 min(c) || '-' || max(c) || ' goods (avg ' || round(avg(c), 2) || ')' as t
            from public.ports p
            join lateral (select count(*)::int as c from public.port_specialties s where s.port_id = p.id) x on true
           where p.kind = 'HARBOUR'
           group by p.size_tier) d;
  raise notice '0061: the quay, measured — %', v_dist;

  -- (d) THE MARKET READ SERVES THE QUAY AND NOTHING ELSE. One harbour per tier, each picked by a
  --     STABLE order (docs/NO_SPAGHETTI.md §4: never let a probe pick its subject by lottery), and
  --     the count of goods the read returns must EQUAL that port's roster count. Nobody is signed
  --     in inside a migration, so public.current_player_id() is null and quay_shows can only be
  --     true for the roster half — which is precisely the "exactly those" claim.
  for v_n in select distinct size_tier from public.ports where kind = 'HARBOUR' order by 1 loop
    select p.id, p.code into v_port, v_port_code
      from public.ports p where p.kind = 'HARBOUR' and p.size_tier = v_n order by p.code limit 1;
    v_mkt   := world.market(v_port);
    v_mkt_n := jsonb_array_length(v_mkt->'goods');
    select count(*)::int into v_bad from public.port_specialties where port_id = v_port;
    if v_mkt_n <> v_bad then
      raise exception '0061 self-assert FAIL: world.market(%) serves % good(s); its roster names % — the read is not the quay',
        v_port_code, v_mkt_n, v_bad;
    end if;
    if v_bad < 4 then
      raise exception '0061 self-assert FAIL: probe port % offers % good(s) — under the owner''s floor, and too thin to prove anything', v_port_code, v_bad;
    end if;
    -- every row it did serve says so, and says it from the same authority
    select count(*) into v_bad
      from jsonb_array_elements(v_mkt->'goods') e
     where (e->>'offered')::boolean is distinct from
           public.port_offers(v_port, (e->>'good_id')::uuid);
    if v_bad <> 0 then
      raise exception '0061 self-assert FAIL: % row(s) of world.market(%) carry an `offered` flag that disagrees with public.port_offers', v_bad, v_port_code;
    end if;
    raise notice '0061: world.market(%) serves % good(s), tier % — its roster exactly', v_port_code, v_mkt_n, v_n;
  end loop;

  -- ── THE VERBS, ON A REAL HOUSE WITH A REAL FLEET AND REAL CARGO ─────────────────────────────
  -- Everything from here to the end of (f) runs against a house this block creates, and the whole
  -- migration is one transaction, so a failure takes the whole file with it.
  v_player := public.new_house(v_probe, 'Casa do Cais', 'PRT');
  select id into v_fleet from public.fleets where player_id = v_player;
  perform cmd.assume_identity(v_probe);
  select port_id into v_port from public.fleets where id = v_fleet;
  select code into v_port_code from public.ports where id = v_port;

  -- The two subjects, chosen DETERMINISTICALLY and each required to SATISFY ITS OWN PRECONDITION
  -- before anything is asserted about it (docs/NO_SPAGHETTI.md §4 — a probe never picks its
  -- subject by lottery, and never picks one the world would refuse for an unrelated reason):
  --
  --   v_on   the good this city offers that this fleet can most afford — `bound_by`/`max_qty`
  --          come from public.fleet_buy_capacity, the authority the picker itself asks, so the
  --          positive control cannot fail for want of purse, hold, stock or daily cap. Ties are
  --          broken on `g.code`, so the pick is stable on an unchanged world.
  --   v_off  the alphabetically first good this city does NOT offer, that its culture does not
  --          refuse (so the refusal below can only be the roster gate) and that STILL HAS a
  --          market row (so it cannot be the "no market row here" refusal either).
  select g.id, g.code into v_on, v_on_code
    from public.goods g
   where public.port_offers(v_port, g.id)
     and not ((select culture from public.ports where id = v_port) = any(g.culture_mask))
   order by (public.fleet_buy_capacity(v_fleet, g.id)->>'max_qty')::numeric desc, g.code
   limit 1;
  select g.id, g.code into v_off, v_off_code
    from public.goods g
   where not public.port_offers(v_port, g.id)
     and not ((select culture from public.ports where id = v_port) = any(g.culture_mask))
     and exists (select 1 from public.port_goods pg where pg.port_id = v_port and pg.good_id = g.id)
   order by g.code limit 1;
  if v_on is null or v_off is null then
    raise exception '0061 self-assert FAIL: the probe port % has no offered good (%) or no un-offered good (%) to test with', v_port_code, coalesce(v_on_code, '-'), coalesce(v_off_code, '-');
  end if;
  v_qty := least(10, (public.fleet_buy_capacity(v_fleet, v_on)->>'max_qty')::numeric);
  if v_qty <= 0 then
    raise exception '0061 self-assert FAIL: the richest good % offers this fleet is % (max_qty %) — the positive control has no subject', v_port_code, v_on_code, v_qty;
  end if;

  -- (e) BUY IS REFUSED FOR A GOOD THIS CITY DOES NOT TRADE, and it is refused THROUGH THE ORDER
  --     QUEUE — which is how an order a player queued before this migration landed will meet it.
  --     The order is written straight into public.orders rather than parsed, so this proves
  --     cmd.execute_order's refusal path and not cmd.parse's vocabulary. The market row for this
  --     pair still exists (asserted in the subject selection above), so the only thing that can be
  --     refusing is the roster gate.
  insert into public.orders (fleet_id, player_id, seq, raw_text, verb, args)
  values (v_fleet, v_player, 900, 'buy ' || v_off_code || ' 10 (0061 probe)', 'BUY',
          jsonb_build_object('good', v_off::text, 'qty', 10))
  returning id into v_order;
  v_res  := cmd.execute_order(v_order);
  v_code := coalesce(v_res->>'error_code', '(none)');
  if v_code <> 'E_UNAVAILABLE' then
    raise exception '0061 self-assert FAIL: buying %, which % does not trade, answered % — expected E_UNAVAILABLE. Full answer: %',
      v_off_code, v_port_code, v_code, v_res;
  end if;
  if (select status from public.orders where id = v_order) <> 'failed' then
    raise exception '0061 self-assert FAIL: the refused order is recorded as %, not failed — a queued order must be refused, never crash the queue',
      (select status from public.orders where id = v_order);
  end if;
  if public.fleet_cargo_qty(v_fleet, v_off_code) <> 0 then
    raise exception '0061 self-assert FAIL: the refused buy of % still put % tun(s) aboard', v_off_code, public.fleet_cargo_qty(v_fleet, v_off_code);
  end if;
  --     THE POSITIVE CONTROL, and it must move the AMOUNT: a good the city DOES trade is still
  --     bought, the tuns land aboard and the purse falls by what the verb reported. Without this
  --     the gate above would pass just as well if it had closed the quay entirely.
  select ducats into v_purse0 from public.players where id = v_player;
  v_res    := cmd.do_buy(v_fleet, jsonb_build_object('good', v_on::text, 'qty', v_qty));
  select ducats into v_purse1 from public.players where id = v_player;
  if (v_res->>'qty')::numeric <= 0 or public.fleet_cargo_qty(v_fleet, v_on_code) <> (v_res->>'qty')::numeric then
    raise exception '0061 self-assert FAIL: buying % reported % tun(s) and put % aboard', v_on_code, v_res->>'qty', public.fleet_cargo_qty(v_fleet, v_on_code);
  end if;
  if v_purse1 <> v_purse0 - (v_res->>'total')::bigint then
    raise exception '0061 self-assert FAIL: buying % cost % d. and the purse moved % -> %', v_on_code, (v_res->>'total')::bigint, v_purse0, v_purse1;
  end if;
  raise notice '0061: at % — BUY % refused E_UNAVAILABLE (not on the roster, market row intact, order recorded failed); BUY % accepted, % tun(s) for % d.',
    v_port_code, v_off_code, v_on_code, v_res->>'qty', (v_res->>'total')::bigint;

  -- (f) SELL IS NOT REFUSED, AND A HOLD IS NEVER STRANDED. The same good the city refused to sell
  --     her is put aboard by hand and then SOLD on that same quay: the ducats must land and the
  --     cargo must leave. This is the whole justification for not deleting public.port_goods.
  select ducats into v_purse0 from public.players where id = v_player;
  perform public.fleet_load(v_fleet, v_off_code, 20);
  v_cargo0 := public.fleet_cargo_qty(v_fleet, v_off_code);
  if v_cargo0 < 20 then
    raise exception '0061 self-assert FAIL: only % of 20 tun(s) of % would go aboard — the sell probe has no subject', v_cargo0, v_off_code;
  end if;
  v_sold := cmd.do_sell(v_fleet, jsonb_build_object('good', v_off::text, 'qty', v_cargo0));
  v_cargo1 := public.fleet_cargo_qty(v_fleet, v_off_code);
  select ducats into v_purse1 from public.players where id = v_player;
  if v_cargo1 <> 0 then
    raise exception '0061 self-assert FAIL: selling % that % does not trade left % tun(s) aboard — the hold is stranded', v_off_code, v_port_code, v_cargo1;
  end if;
  if (v_sold->>'total')::bigint <= 0 or v_purse1 <> v_purse0 + (v_sold->>'total')::bigint then
    raise exception '0061 self-assert FAIL: selling % paid % d. and the purse moved % -> % — the two disagree',
      v_off_code, (v_sold->>'total')::bigint, v_purse0, v_purse1;
  end if;
  raise notice '0061: at % — SELL % accepted though % is not on the roster: % tun(s) for % d. (purse % -> %). No hold is stranded.',
    v_port_code, v_off_code, v_off_code, v_cargo0, (v_sold->>'total')::bigint, v_purse0, v_purse1;

  -- ... and the quay SHOWED her that row, so the sale is reachable in the game and not only in
  -- the schema. Re-loaded and re-read, because the sale above emptied the hold again.
  perform public.fleet_load(v_fleet, v_off_code, 5);
  v_mkt := world.market(v_port);
  select count(*) into v_bad from jsonb_array_elements(v_mkt->'goods') e
   where e->>'code' = v_off_code and (e->>'offered')::boolean = false and (e->>'sell')::numeric > 0;
  if v_bad <> 1 then
    raise exception '0061 self-assert FAIL: with % tun(s) of % aboard at %, world.market serves % such row(s) (expected exactly 1, offered=false, with a bid) — the SELL list cannot show it',
      5, v_off_code, v_port_code, v_bad;
  end if;
  select count(*)::int into v_mkt_n from public.port_specialties where port_id = v_port;
  if jsonb_array_length(v_mkt->'goods') <> v_mkt_n + 1 then
    raise exception '0061 self-assert FAIL: a hold carrying one un-offered good widened world.market(%) to % row(s); the roster is % and the read must be exactly one wider',
      v_port_code, jsonb_array_length(v_mkt->'goods'), v_mkt_n;
  end if;
  perform public.fleet_unload(v_fleet, v_off_code, 5);

  -- (k) THE QUAY NEVER NAMES A CARGO THE VERB WOULD REFUSE. world.trade_routes shortlists what to
  --     BUY here, and cmd.do_buy now refuses anything off the roster; if the two disagree the game
  --     promises a trade it will not execute, which is 0017:50-55's scar. This assert exists
  --     BECAUSE the first draft of this file got it wrong and scripts/db/proofs/04 caught it —
  --     "the Lisboa market served 10 of 243 goods, civet is on it 0 time(s)". A defect a proof
  --     found is a defect the migration should have refused, so it refuses it here.
  --     Asked WITH the fleet, so the scan runs on the same `fleet` basis a player is served.
  v_routes := world.trade_routes(v_port, v_fleet, null::numeric, null::int);
  v_n := jsonb_array_length(coalesce(v_routes->'routes', '[]'::jsonb));
  if v_n = 0 then
    raise exception '0061 self-assert FAIL: the quay named 0 route(s) out of % — the check below would prove nothing', v_port_code;
  end if;
  select count(*) into v_bad
    from jsonb_array_elements(v_routes->'routes') e
   where not public.port_offers(v_port, (e->>'good_id')::uuid);
  if v_bad <> 0 then
    raise exception '0061 self-assert FAIL: % of % route(s) the quay names out of % start with a good this city does not trade — cmd.do_buy would refuse every one of them', v_bad, v_n, v_port_code;
  end if;
  --     ... and the DESTINATION side is deliberately NOT narrowed. How many routes end at a port
  --     that does not trade the good is CONTENT — it is reported, never asserted, because a
  --     re-authored roster may legitimately change it to any number including zero.
  select count(*) into v_n2
    from jsonb_array_elements(v_routes->'routes') e
   where not public.port_offers((e->'to'->>'id')::uuid, (e->>'good_id')::uuid);
  raise notice '0061: the quay names % route(s) out of %, and every one of them starts with a good this city trades; % of them END at a port that does not trade it — sellable only because SELL is ungated',
    v_n, v_port_code, v_n2;

  -- (g) THE PRICE DID NOT MOVE. This file claims to touch no price; a claim is not evidence. The
  --     mid at a pair the quay does NOT offer is re-read and required to be exactly what
  --     world.mid_price answers off its untouched port_goods row.
  select pg.stock into v_price0 from public.port_goods pg where pg.port_id = v_port and pg.good_id = v_off;
  v_price1 := world.mid_price(v_port, v_off, v_price0);
  if v_price1 is null or v_price1 <= 0 then
    raise exception '0061 self-assert FAIL: the mid for % at % reads % — an un-offered pair lost its price', v_off_code, v_port_code, v_price1;
  end if;
  select count(*) into v_bad from public.port_goods where stock is null or stock_target is null or affinity is null;
  if v_bad <> 0 then
    raise exception '0061 self-assert FAIL: % port_goods row(s) lost a column', v_bad;
  end if;
  select count(*) into v_n from public.port_goods;
  if v_n <> v_market then
    raise exception '0061 self-assert FAIL: public.port_goods holds % row(s), was % — this file must not touch the market table', v_n, v_market;
  end if;

  -- (h) THE RECORD KEEPS ONLY WHAT THE QUAY OFFERS. The snapshot is RUN, and what it wrote is
  --     counted against the offered-pair count rather than assumed. Both halves must bite: the
  --     write count, and zero surviving rows for pairs no quay offers.
  if v_hist_before = 0 then
    raise exception '0061 self-assert FAIL: price_history was empty before this file ran — the delete below proves nothing';
  end if;
  select count(*) into v_bad from public.price_history h where not public.port_offers(h.port_id, h.good_id);
  if v_bad <> 0 then
    raise exception '0061 self-assert FAIL: % price_history row(s) survive for pairs no quay offers', v_bad;
  end if;
  select count(*) into v_n from public.price_history;
  if v_n >= v_hist_before then
    raise exception '0061 self-assert FAIL: price_history holds % row(s), was % — the delete removed nothing', v_n, v_hist_before;
  end if;
  v_wrote := (public.tick_price_snapshot(now() + interval '1 hour')->>'wrote')::int;
  if v_wrote <> v_off_true then
    raise exception '0061 self-assert FAIL: the snapshot wrote % row(s) for % offered pair(s) — the record is not following the quay', v_wrote, v_off_true;
  end if;
  select count(*) into v_bad from public.price_history h where not public.port_offers(h.port_id, h.good_id);
  if v_bad <> 0 then
    raise exception '0061 self-assert FAIL: the snapshot wrote % row(s) for pairs no quay offers', v_bad;
  end if;
  select count(*) into v_hist_after from public.price_history;

  -- (i) THE SLICES ACTUALLY LANDED IN THE DEPLOYED BODIES — read back out of pg_get_functiondef,
  --     not inferred from the fact that the recut did not raise (0057's own pattern).
  v_def := pg_get_functiondef('cmd.do_buy(uuid, jsonb)'::regprocedure);
  select count(*) into v_n from regexp_matches(v_def, 'public\.port_offers\(', 'g');
  if v_n <> 1 then
    raise exception '0061 self-assert FAIL: the deployed cmd.do_buy names public.port_offers % time(s), expected 1', v_n;
  end if;
  v_def := pg_get_functiondef('world.market(uuid)'::regprocedure);
  select count(*) into v_n from regexp_matches(v_def, 'public\.quay_shows\(', 'g');
  if v_n <> 1 then
    raise exception '0061 self-assert FAIL: the deployed world.market names public.quay_shows % time(s), expected 1', v_n;
  end if;
  select count(*) into v_n from regexp_matches(v_def, '''offered''', 'g');
  if v_n <> 1 then
    raise exception '0061 self-assert FAIL: the deployed world.market names the `offered` field % time(s), expected 1', v_n;
  end if;
  v_def := pg_get_functiondef('public.tick_price_snapshot(timestamptz)'::regprocedure);
  select count(*) into v_n from regexp_matches(v_def, 'public\.port_offers\(', 'g');
  if v_n <> 1 then
    raise exception '0061 self-assert FAIL: the deployed tick_price_snapshot names public.port_offers % time(s), expected 1', v_n;
  end if;
  --     ... and cmd.do_sell was NOT touched: the asymmetry is the design, so the absence is the
  --     property and it is asserted rather than left to a reader's trust.
  v_def := pg_get_functiondef('cmd.do_sell(uuid, jsonb)'::regprocedure);
  if strpos(v_def, 'port_offers') > 0 or strpos(v_def, 'quay_shows') > 0 then
    raise exception '0061 self-assert FAIL: cmd.do_sell names the roster gate — SELL must not be restricted to the roster, or a hold can be stranded';
  end if;

  -- (j) POSTURE. No client role may reach either new function, and the two standing posture reads
  --     must still be zero after this migration (README §3's "assert the posture too").
  if has_function_privilege('anon', 'public.port_offers(uuid,uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.port_offers(uuid,uuid)', 'execute')
     or has_function_privilege('anon', 'public.quay_shows(uuid,uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.quay_shows(uuid,uuid)', 'execute') then
    raise exception '0061 self-assert FAIL: a client role may execute the quay predicate';
  end if;
  if not has_function_privilege('authenticated', 'world.market(uuid)', 'execute') then
    raise exception '0061 self-assert FAIL: world.market lost its grant when it was re-cut — the MARKET screen would go dark';
  end if;
  select count(*) into v_bad from public.client_write_grants();
  if v_bad <> 0 then
    raise exception '0061 self-assert FAIL: % client write grant(s) after this migration', v_bad;
  end if;
  select count(*) into v_bad from public.client_executable_writers();
  if v_bad <> 0 then
    raise exception '0061 self-assert FAIL: % client-executable writer(s) after this migration', v_bad;
  end if;

  drop table quay_before_0061;

  raise notice '0061 self-assert ok: public.port_offers agrees with the roster on all % market pair(s) (% offered, % not) and invents no quay for a sea place; every harbour offers % .. % goods, inside the owner''s 4..10; world.market serves each probe port''s roster exactly and one row wider when a hold carries something it does not trade; BUY of an un-offered good is refused E_UNAVAILABLE while an offered one still fills; SELL of that same un-offered good still pays, so no hold is stranded; public.port_goods is untouched at % row(s) and prices still read; price_history % -> % row(s) and the snapshot now writes % (was %) — at a window of % slot(s) and 201 bytes/row that is a ceiling of ~% MiB, down from ~% MiB; posture reads zero',
    v_market, v_off_true, v_off_false, v_min_c, v_max_c, v_market,
    v_hist_before, v_hist_after, v_off_true, v_market, v_window,
    round((v_off_true::numeric * v_window * 201) / 1048576, 1),
    round((v_market::numeric  * v_window * 201) / 1048576, 1);
end $$;
