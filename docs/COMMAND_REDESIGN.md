# Command redesign: buy and sell from the Plan, a route map, Report

Owner rows 190–194, 202, 203 (docs/OWNER_REQUESTS.md), 2026-10-25:

- 190: *"i can't reach places, i can only plan on buying but not for selling ... redisign properly so that i can buy and sell."*
- 191: *"in command, plan, i want to see a small map showing route concisely."*
- 192: *"the profit tab on command, change it to report, saving all the earnings and losses by sections, points, that is saved."*
- 194: *"this game must be playable, yet it is hard to do so with just whats in the plan page"*. The test: a new player makes a full buy → sail → sell trip from the Plan page alone.
- 202: *"i hate long sentences, words ... strightforward, more simple and easy - all parts of the game"*. Labels are 1–2 words. A hint is one short line.
- 203: *"in fleet tab, what is this 'keep supply at'? this is useless"*. Supplies become automatic.

This file is design only: no code, no migration. Rules marked **default** are mine, and the owner may reverse them (§7).

---

## 1. Diagnosis (read off the chain and a cached local world at 0216, never the live project)

### 1a. "I can't reach places": every rule that shuts or hides a city

| # | Rule | Where | Bites a normal player? |
|---|---|---|---|
| 1 | **Region door.** The destination's region asks an exploration level. `regions.min_exploration_level = 1 + floor(sailed nm from Lisbon / 2,500)`, capped at 5. `public.exploration_reach` = your level, or the highest region you have already docked in. | `0107:73-77` (derivation), `0107:270` (`E_REGION_CLOSED` in `passage_gate`), `0112:58-63` (exploration_reach). `voyage.reach_passage` asks the same door for every harbour (`0188` header §2). Still in force while the sea switch is dark (`0216:13`). | **YES, this is the top cause.** Measured on the cached world: a Lisbon company at exploration 1 reaches **111 of 237 harbours**. The 126 it cannot reach are exactly every harbour in a level 2–5 region (17 + 11 + 49 + 49). None of them is shut by distance. |
| 2 | **Leg reach.** One leg may be at most `nav_leg_nm_base × 2^max(0, Navigation − 1)` = 1,700 nm at Navigation 0–1. | `0188:80` (`passage_reach_at`), knob `0112:37`. `reach_passage` runs Dijkstra over legs ≤ reach. | **Yes, far from home.** The same world has 3 of its 13 human companies at Acapulco (exploration 4). They reach **16 of 237**: the Pacific coast has no chain of legs ≤ 1,700 nm back to anywhere. `0112:79-82` names this ("still needs NAVIGATION to cross back"). |
| 3 | **Supplies.** `sailable` is false when the longest leg × `endurance_margin` (1.15) is more than the days your stores last. | `0188` header §3, knob `endurance_margin`. SAIL refuses `E_ENDURANCE`. | Sometimes. The plan writes `PROVISION FULL` where it is needed (`planLines.ts:84-96`), but a full hold leaves no room for casks. |
| 4 | **Sea conditions (0215) and the sea gate (0216).** Each sea asks a title and a wave resistance. | `0215`, `0216` (1)/(3). | **Not today:** `sea_conditions_bite` is dark. When it is lit, it replaces rule 1. |
| 5 | **The board's shortlist.** Only `good_board_quoted` = 10 sell cities are priced in full. Reachable cities are ranked first, then by price. | `0171:117` (knob), `0171:392` (`rk <= v_quoted`), `0188:372` (reachable first). | Yes, as **hiding**: the Plan's Sell chips are only those 10 (`PlanBuilder.tsx:83`). `route_scan_keep` (3, `0019:94`) is the quay's route scan, not the Plan. |
| 6 | **Buy cities nobody can reach.** The Buy chips list every city that sells the good, sailable or not. | `PlanBuilder.tsx:152`. | **Yes.** In a sample of 6 goods from Lisbon, 3 (martaban-jars, guayaquil-cacao, rice-paper) are sold **only** in shut regions: 0 sailable buy rows and 0 sailable sell rows. The goods list still offers them. |
| 7 | **Docked.** BUY and SELL run only in port (`E_NOT_DOCKED`). At sea the plan sails first (`sailOrigin`). | `planLines.ts:65-70` | No. This is handled. |

**What makes it worse: the reason is shown wrong.** A region-shut city comes back as `stops: null`, the same as a city that is too far. `reachWords` (`planLines.ts:182-188`) then says *"too far to sail in one go ... A captain with Navigation N could take you there"*. Navigation does not open a region. The player studies, and the city stays shut. The server's real reason (`passage_gate`'s `E_REGION_CLOSED`, with the region and the level it asks) never reaches the client.

**Top cause:** the region door, `supabase/migrations/20260818000107_the_ocean_is_earned_at_the_academy.sql:270`, read through `voyage.reach_passage` (0188/0216). It is shown under the wrong words at `src/features/command/plans/planLines.ts:185-188`.

### 1b. "I can only plan buying, not selling"

- **The only door into a plan is a buy.** `GoodTicket.tsx`: the Buy at list has a Plan button on each row (`:355`, `desk-plan`), and so does the best-trade card (`:266`). The **Sell at list has no Plan button at all**: `SellAt` (`:366`) takes no `onPlan`.
- **The Plans page cannot start anything.** With no draft, Plans shows only the route and the queue (`Plans.tsx:48`: `side` is null). Every plan starts on Markets, inside one good's page.
- **"Sell what is in my hold" is hidden.** It exists only as an "On board" chip inside the builder, after you have already picked that good on Markets (`PlanBuilder.tsx:146-150`). Nothing lists the hold and asks "where do I sell this?".
- **What the client asks:** `world.good_board(good, fleet, from, qty)`. One good at a time. Basis: on board, else the amount asked, else what fits (`0171:300-311`). When you hold the good, the board ignores `from`/`qty` and the buy list is empty.
- **What it never asks:** (a) "for each good in my hold, the best sailable place to sell it"; (b) "for a city I pick, what to carry there from here"; (c) the sell side beyond the 10 quoted rows. Reads exist that do part of this: `world.holdings`, `world.watchlist` and `world.route_board` (0106). No Plan path calls them.

---

## 2. The player's loop, on one page

Plans becomes **Trade**: one page, three ways to start, one card, one button.

```
START ─┬─ Hold   (what is on board)    → pick a good → Sell row list
       ├─ Here   (what this port sells)→ pick a good → Sell row list
       └─ Go to  (pick a port)          → goods to carry there        (R5)
                         │
                 THE TRADE CARD  (one good, one buy city or "Hold", one sell city)
                 Buy   Lisbon · 60 · 95 each       [edit]
                 Sail  3 stops · 6.2 days · map
                 Sell  Antwerp · 140 each          [edit]
                 Supplies −120 · Wages −40 · Profit +1,860
                 [ Go ]                       ← the one action
```

Every step has one action:

| Step | Action | What the server does |
|---|---|---|
| Pick | tap a good (Hold or Here) | `world.good_board` for that good (on_board basis for Hold) |
| Sell where | tap a Sell row (every row, closed ones last with a 1–2 word reason) | nothing until Go |
| Go | **Go** | `cmd.issue_lines`: SAIL … / BUY / SAIL … / SELL, all or none (0175) |
| Sail | automatic. Supplies are bought at each SAIL (R1) | `cmd.do_sail` tops up, then departs |
| Sell | automatic on arrival (`SELL … ALL`) | the queue runs |
| See it | Report (R4) | `world.report` |

"Where can I sell X": tap X in Hold or Here. The Sell list **is** the answer. "Sell what is in my hold": Start = Hold.

A **press selects** (`docs/dev-log/2026-10-25-plan-tab.md` "A press selects"; COMMAND_DESK §3.5): tapping a good or a row changes the card's figures in place. Nothing above it collapses, re-flows or moves. Every row of the card is always drawn, with a dash while unknown. The map has a fixed 3:2 box.

---

## 3. The mini route map (row 191)

- **Reuse, do not build.** `PlanVoyage.tsx` already draws `SmallChart → ChartCanvas` with `only` (the plan's port codes) and `legs` (`planLines`' `PlanLeg[]`, the course author's own paths). Same projection, same coastline, no merchants. Nothing new is drawn by hand.
- **Concise:** the stops only, numbered 1..n, with the start marked "Now". No other city, no name except the stops. The view fits the legs' bounds and is **static**: no pan, no zoom, no live fleets layer, and it redraws only when the legs change.
- **Under the map, one line per leg:** `1 Lisbon → Cádiz · 1.2 d`, plus the sea's ask from PR #293 as one short tag when there is one: `Title 2`, or `Shut` when it refuses. While the sea switch is dark the tag reads `Later`. The client prints the server's `sea` field and never compares it with your own figures.
- Days per leg: `daysAt(leg.nm, board.fleet.speed_kn)` (`planLines.ts:51`), the one arithmetic the plan already shares.

---

## 4. Report, replacing Profit (row 192)

**One server read:** `world.report(p_span text)`, where `p_span` is `'day' | 'week' | 'all'` (game days via `world.game_day`). It replaces `world.books` (0177). It is derived from the append-only `public.ledger` (0004: `kind, ducats_delta, balance_after, ref_event_id, created_at`) and stores nothing.

**Sections**, from the ledger kinds that exist today (`0177:75-78`, `0213:595`, the `credit`/`pay_city` callers):

| Section (EN / KO) | Ledger kinds |
|---|---|
| Trade / 무역 | `SELL`, `BUY`, `TAX` (profit tax) |
| Crew / 선원 | `WAGES`, `HIRE` |
| Supplies / 보급 | `PROVISION` |
| Repairs / 수리 | `REPAIR` |
| Insurance / 보험 | `INSURANCE` (paid), `INSURANCE_PAID` (received) |
| Invest / 투자 | `SHARE`, `DIVIDEND`, `DONATION` |
| Ships / 선박 | `BUILD` |
| Other / 기타 | `TUITION`, `TOW`, and any kind not listed, under its own name (nothing is dropped) |

`FOUNDING` (the starting money) is capital, so it is left out, as 0177 does. `PROBE_*` kinds exist only in rolled-back self-asserts.

**Points** (where the money moved): by **port**, and by **voyage** (from city → to city, departure day).

**What is missing today, and what R4 adds:**
- The ledger names **no port, no fleet and no voyage**. `ref_event_id` points at an event whose payload usually has only the fleet's *name* (`BOUGHT`, `PROVISIONED`, `REPAIRED`). `INSURED` alone carries `port` and `voyage_id`.
- `treasury_flows` (0122) has a `port_id`, but it is rolled up and **deleted** hourly, and is written only while `city_treasury_enabled`. It is not a record.
- **Port fees** are not a ledger kind. They sit inside the `SELL` proceeds (`BoardSellRow.port_fee`), so Report shows them as a figure inside Trade, never as their own line.
- **R4's migration:** `ledger` gains three nullable columns, `port_id`, `fleet_id` and `voyage_id`. They are filled at insert by **one** BEFORE INSERT trigger: the fleet comes from the ref event's fleet, the port from where that fleet is docked, and the voyage from the fleet's current or just-arrived voyage. Every writer gets it for free, because `public.credit` and `pay_city` are the only writers. Old rows stay as they are (append-only) and read as point "Earlier".

---

## 5. Screens (desktop 1440 and phone 390)

Words follow row 202: 1–2 words a label, Korean just as short.

**Trade (was Plans), desktop:**
```
┌ Command ─ [Markets 시장] [Trade 거래] [City 도시] [Invest 투자] [Report 보고] ──────────────┐
│ START  [Hold 화물] [Here 이곳] [Go to 목적지]   │ CARD                    │ MAP           │
│ ─────────────────────────────── │ Coffee 커피             │  ┌─────────┐  │
│ Coffee   60   ·  Best Antwerp +31 │ Buy 구매   Lisbon 95    │  │ 1 ─ 2   │  │
│ Pepper   12   ·  Best Cádiz  +12 │ Sell 판매  Antwerp 140  │  │    \ 3  │  │
│ Wine     —    ·  Best Bruges  +8 │ Days 일수  6.2          │  └─────────┘  │
│ ── Sell 판매 (Coffee) ─────────── │ Supplies 보급  −120     │ 1 LIS→OPO 1.2d│
│ Antwerp  140  6.2d  +1,860  [●]   │ Wages 급여     −40      │ 2 OPO→ANR 5.0d│
│ Bruges   136  6.4d  +1,610  [ ]   │ Profit 이익   +1,860    │   Title 2     │
│ Hamburg  131  7.0d  +1,200  [ ]   │ Insure 보험 [ ]         │               │
│ ── Shut 닫힘 ──────────────────── │ [ Go 출발 ]             │ ORDERS 명령   │
│ Goa      310  Explore 3 탐험 3    │ [ Route 항로 ]          │ SAIL OPO …    │
└──────────────────────────────────────────────────────────────────────────────┘
```

**Trade, phone (one column, top to bottom; the button is fixed at the bottom):**
```
[Hold 화물][Here 이곳][Go to 목적지]
Coffee 60 · Antwerp +31        ← tap = pick
Pepper 12 · Cádiz +12
── Sell 판매 ──
Antwerp 140 · 6.2d · +1,860 ●
Bruges  136 · 6.4d · +1,610
Goa     Shut · Explore 3
── Card ──
Buy   Lisbon 95 · 60
Sell  Antwerp 140
Days 6.2 · Supplies −120 · Wages −40
Profit +1,860
┌ map 3:2 ┐  1 LIS→OPO 1.2d
└─────────┘  2 OPO→ANR 5.0d
Orders …
[        Go 출발        ]
```

**Closed-row reasons (1–2 words, from the server's refusal code, never worked out in the client):**
`E_REGION_CLOSED` → `Explore N` / `탐험 N`; `E_LEG_TOO_FAR` → `Navigation N` / `항해술 N`; `E_SEA_CLOSED` → `Title N` / `작위 N` (or `Waves N` / `파도 N`); `E_ENDURANCE` → `Hold full` / `화물 가득`; no money → `No money` / `돈 부족`.

**Go disabled:** the button shows the reason in place of its label: `No money`, `Hold full`, `Shut`, `Pick sell` / `판매 선택`.

**Fleets (row 203):** the supplies block is one line, `Supplies 12 days` / `보급 12일`. No keep control.

**Report, desktop:**
```
[Day 오늘] [Week 주간] [All 전체]        Profit 이익 +4,210
┌ By section 항목별 ─────────┐ ┌ By place 장소별 ────────────────┐
│ Trade 무역      +6,900     │ │ Antwerp  +3,100                 │
│ Crew 선원         −820     │ │ Lisbon   −1,250                 │
│ Supplies 보급     −610     │ │ Voyage LIS→ANR d41  +1,860      │
│ Repairs 수리      −300     │ │ Voyage ANR→LIS d47    +940      │
│ Insurance 보험     −90     │ │ Earlier 이전          +210      │
│ Invest 투자       −870     │ └──────────────────────────────────┘
└────────────────────────────┘ [ bars: one per day, the zero line only ]
```
On the phone: span chips, then the total, then sections, then places, one under the other. A tap on a section or a place opens its lines in place, below it, and nothing else moves.

---

## 6. Build slices

Order: **R1 alone makes buy → sail → sell playable from the Plan page.**

**R1 — The trade loop, and automatic supplies. Migration + client, landing together (owner rows 190, 194, 203).**
- *Client:* Plans becomes Trade (§5). Start chips Hold / Here. Hold uses the fleet's cargo (`fleetCargoByCode`). Here uses the docked port's own market rows (what this port sells; at sea, the next port's). The Sell list shows **every** board sell row: quoted rows first, closed rows last with the code's 1–2 words. The one trade card. Go. `GoodTicket`'s Sell at rows gain the same Plan press (they open Trade). The Profit face's label stays until R4.
- *Supplies, the one rule:* `cmd.do_sail` tops the fleet up **before** `voyage.sail_refusal`'s endurance check. It calls `cmd.do_provision` in DAYS mode to `leg_days × endurance_margin`: the same knob the gate uses, so the buy and the refusal can never disagree. It buys nothing when the stores already cover that. It pays through `credit` (`PROVISION`), so it shows on Report. Every verb SAIL (typed, queued, plan, route) runs `do_sail`. On the chain, the other `voyage.depart(` calls are in self-assert probes. Before writing the hunk, the build confirms this on prod with a read-only body scan. If another live caller exists, the top-up goes where that caller and `do_sail` meet, so there is still one path.
- *The old path is removed in the same migration:* the `cmd.run_standing_provision` call is cut out of `voyage.settle`'s arrival arm and out of the standing-route runner (sliced hunks, each occurring once and reversing). `cmd.provision_preset_save / _apply / _delete` (+`_for`) and `world.provision_presets` are revoked from clients and dropped from the entry-point registry. `fleets.provision_preset_id` is nulled, with the old values kept in a backup table for rollback. The table and column are dropped in R6.
- *Client removals:* `FleetStores.tsx`'s keep control, `features/fleets/standingOrder.ts`, the preset reads and verbs in `worldStore`/`catalog`, and the dict keys `fleets.keepAt / keepN / stopKeeping` (en + ko). `planLines` stops writing `PROVISION FULL` (the server buys at SAIL). Its casks arithmetic and `stores` input are deleted, not kept beside the new rule.
- *Supplies on the card:* `world.good_board` rows gain `supplies: {cost, fits}`, from **one new function**, `public.supply_need(fleet, days)`. `do_sail` calls the same function to buy, so the card's `Supplies −120` and what Sail spends have one author. `fits=false` → Go reads `Hold full`. Cost > purse → `No money`.
- *Proof:* migration self-assert on its own probe company, rolled back: (a) a fleet with empty casks SAILs Lisbon → Porto, its stores land at ≥ leg × 1.15, and one `PROVISION` ledger row matches the purse change; (b) a fleet already stocked buys nothing; (c) a full hold → `E_ENDURANCE`, nothing bought; (d) arrival no longer provisions (the settle hunk is gone; positive control: the pre-image did); (e) good_board's `supplies.cost` equals what (a) paid; (f) the board minus `supplies` equals its pre-image, good_board timed 6+ calls in one session (0206 lesson). `scripts/db/proofs/07_standing_provision.sql` is rewritten as **07_supplies_at_sail.sql**. Specs: **new** `tests/trade.loop.spec.ts` (1440×900 and 390×844: a new company at Lisbon, Here → good → Sell row → Go; the queue holds SAIL/BUY/SAIL/SELL; on the served world it arrives and sells; a Report-side check of the purse), **new** `tests/fleet.supplies.spec.ts` (Fleets shows `Supplies N days` and no keep control). Changed: `desk.plan.spec.ts`, `desk.plantab.spec.ts`, `desk.terminal.spec.ts`, `planWords.spec.ts` (no `PROVISION FULL`), and every spec touching `fleet-keep`.

**R2 — The board says why a city is shut. Migration + client. Lands after PR #293.**
- Every `sailable:false` row gains `shut: cmd.refusal | null`: `public.passage_gate`'s own answer for that destination (region door while dark, sea gate when lit, reach), so there is one authority. This extends #293's `sea` field instead of adding a second one.
- `reachWords` prints the code's 1–2 words (§5) and no longer guesses "too far / Navigation".
- *Proof:* a self-assert at title 1 / exploration 1 from Lisbon: a level-3 region row reads `E_REGION_CLOSED` with need 3; a Pacific row from Acapulco reads `E_LEG_TOO_FAR`; sailable rows have `shut` null; the board minus `shut` equals its pre-image; timed 6+ calls. Spec `planWords.spec.ts` (+3 cases), `trade.loop.spec.ts` (a shut row says `Explore N`).

**R3 — The mini route map. Client only.** §3: stops numbered, a static fit, one line per leg with days and #293's sea tag. Spec **new** `tests/trade.map.spec.ts`: every `[data-port-code]` is a stop; the leg count equals the SAIL lines; pressing a second sell row moves neither the map box nor the card.

**R4 — Report. Migration + client, landing together (row 192).**
- *Migration:* the three ledger columns plus the one fill trigger (§4). `world.report(span)` returns `{total, sections:[{id, word, ducats, lines:[{kind, ducats}]}], places:[{kind:'port'|'voyage'|'earlier', …, ducats}], days:[{game_day, net}]}`. `world.books` is dropped from the registry in the same file. Its only caller is `Profit.tsx`, which is replaced.
- *Client:* the face id `profit` → `report`, labels `Report` / `보고`, layout §5.
- *Proof:* own probe company, rolled back. A buy, a sail, a sell, wages and a provision through the real verbs. Every new ledger row has `fleet_id`, and the trade rows also have `port_id`. The section sums equal the purse change. The place sums equal the section sums. `day ⊆ week ⊆ all`. `FOUNDING` is excluded. Old rows read "Earlier". Append-only still bites (positive control). Specs: `rpc.books.spec.ts` → **`rpc.report.spec.ts`**, **new** `tests/desk.report.spec.ts` (span chips change figures in place; sections and places stand at both widths).

**R5 — "Go to": pick a port, see what to carry. Migration + client.**
- `world.carry_to(fleet, port)`: for each good this port sells, the net at that port. The row pricing is **factored out of `world.good_board`** into one function both call, never a second copy of net. Start chip Go to → port picker (sailable first) → goods list → the same card.
- *Proof:* for 3 goods, `carry_to`'s net equals `good_board`'s row for that city to the ducat; timed 6+ calls. Spec **new** `tests/trade.goto.spec.ts`.

**R6 — Clean-up. Migration, one week after R1 is live.** Drop `provision_presets`, `fleets.provision_preset_id`, the backup table and `cmd.run_standing_provision`. Asserted: nothing references them (`pg_depend` plus a body scan).

Each slice: `npx tsc -b`, `npx eslint .`, the pure specs, and `duplication` / `sections`. Migrations follow CLAUDE.md: prod-read-only selections before the PR, renumbered at push, deployed only with `~/bin/bv-deploy.sh`.

---

## 7. Defaults I decided (the owner may reverse any of them)

1. **Plans is renamed Trade** (`거래`). Markets stays for browsing prices.
2. **Supplies margin = the existing `endurance_margin`, +15 %.** I did not add a new +20 % knob: one number means the buy and the Sail check cannot disagree. Raising it is one knob change.
3. **Supplies are bought at each SAIL, never on arrival.** Wages stay a flat 1 ducat per crew-day, unchanged.
4. **Region door unchanged.** This design shows it truthfully (R2). It does not open regions: that is the sea-conditions switch's job (0215/0216, which replaces the door when lit).
5. **Closed cities are shown, not hidden:** last in the list, with their 1–2 word reason, and not pressable.
6. **Goods sold only in shut regions:** in Here and Hold they stay listed, with `Shut` and no profit figure.
7. **Report spans = Day / Week / All**, in game days. Old ledger rows (before R4) appear as one place, "Earlier".
8. **Port fees are not a section.** They are inside Trade, because the ledger has no fee kind. Splitting them out would need a new kind written by the sell verb, and that is not in this design.
9. **Merchants are not changed** beyond R1's top-up: their planner's own PROVISION lines leave nothing for the top-up to buy.
10. **"Go" is the one button** (`출발`). It queues the whole trip, all or none. "Route" (make it repeat) stays as the second button.
