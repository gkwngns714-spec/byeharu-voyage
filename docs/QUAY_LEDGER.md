# QUAY LEDGER — the market and trading redesign (owner row 76)

**Written 2026-09-11.** The owner brought nine screenshots of the Uncharted Waters Origin trade
house (buy/sell card list, right-hand basket with the hold bar, item-info popup with a price line
and slider, the 판매 확인 table, the 협상 haggle scene, the 정산 settlement, the 의뢰 request board)
and said: *"come up with the same design plan, but different and modern than this"*, then
*"make this in game"*. This file is the design that was shown and approved, kept in the repo so it
survives compaction. The rendered plan with mockups is the artifact
`https://claude.ai/code/artifact/d2549ddb-ba34-4367-a4be-2d02397a191d`; this file is its record.

Everything below composes onto what the chain already serves. Every figure on screen is a served
figure; the client formats and never multiplies (`docs/NO_SPAGHETTI.md` §2, "a decision is the
server").

---

## 1. Anatomy of the reference, and what voyage already has

| reference part | verdict | composes onto |
|---|---|---|
| Buy / Sell tabs + goods card list (index % badge, unit price with base) | keep, reshape | `world.market(p_port)` — buy, sell, mid, range_lo/hi, stock_band, offered, rarity (0071:49-95) |
| right-hand basket + 선창 hold bar, one big button with the total | keep, **new verb** | hold from `world.fleets` (hold, free_hold, cargo_tuns); the basket is ABSENT — `cmd.issue` takes one BUY/SELL — so `cmd.preview_basket` + `cmd.trade_basket` (0083) |
| item-info popup (description, price line, hi/lo, calc panel, −/+ slider, 담기) | keep, **inline** | `world.price_history` (≥48 slots), `world.buy_capacity` (cap + binding word), `Stepper`. Becomes the tray under the press, never a modal |
| 판매 확인 table (원가 · 관세 · 할증 · 판매 금액) | keep as **receipt** | `cmd.preview` already returns profit vs `cargo_basis` (0081); the basket preview returns the breakdown per line |
| 협상 haggle scene (7 chances, +49%, success gauge) | keep, **both sides** | `cmd.haggle`, `world.haggle_state`, `haggle_daily` (0022/0024). Sell side exists server-side; `HaggleRow.tsx:36` only calls `'buy'`. Concession is a slice of the SPREAD, never of mid |
| 정산 settlement (XP, 공헌도, 거래 점수, 명성; totals; purse after) | keep, **trimmed** | trading XP = `player_progress.trading` (0069). Contribution / reputation are ABSENT and are not faked |
| 의뢰 교역품 request board | keep, **new system** | nothing exists. `trade_contracts` + `world.contracts(p_port)` + `cmd.fulfil` — last slice |
| gem timer refresh, four currencies, 언어 효과 buff card, NPC portraits, gold CTAs | **drop** | one currency; the 15-minute drift clock is already on the TopBar; fairs (`active_buffs` SPREAD) become one line |

## 2. The five moves — what makes it different, and modern

1. **One sheet, zero modals.** A row's press opens the one `Tray` (quantity, trend, paid); the
   manifest is the same tray's other face; haggle and receipt render inside it. Nothing covers the
   ledger; nothing above a press moves (`docs/UI_DIRECTION.md` §6 PORT).
2. **Price + tide, not `96% · 1,124 (1,110)`.** Each row shows the served buy and sell figures as
   its two tap cells (owner row 6), and a 4-px tide `Bar`: where mid sits inside the served
   `range_lo … range_hi`. Row 64's ±20 % band becomes a shape, not an index.
3. **Haggle as a thread.** Short merchant turns templated from `world.haggle_state`; the stake
   written out — spread points, then the per-tun figure — attempts as pips, odds once, under 100.
   Buy and sell.
4. **Phone-first, one column — and on a wide glass the basket IS the right-hand panel.** Ledger
   list + bottom tray on a phone. From `lg` (`src/components/ui/screenLayout.ts`, 2026-09-13) the
   Sheet is a 48-rem column and a docked Tray is a 26-rem side panel to its right; on PORT › Trade
   that slot ALWAYS shows the basket (empty, with lines, or as the receipt), and a price press
   puts the unfolded row in the same slot. Same components, one `Tray`, no desktop tree — this is
   the reference's left/right split, which row 80 named as what slice 1 lacked.
5. **Chart-ink on chalk.** The repo's tokens; gain/loss keep their semantic colours and are never
   the accent; tabular figures everywhere (`Figure`).

## 3. Screens

* **A · The board** — PORT › Trade after absorbing MARKET. Port + purse in the bar; hold gauge with
  the staged tuns hatched; `Segmented` Buy · Sell · Contracts; a ledger `Row` per good: name, tag
  (`rare` from served rarity; `native` only once the payload carries it), tide bar, `aboard N t`
  caption, two price cells. Dead cells stay visible, dimmed, with today's texts.
* **B · The row, unfolded** — the tray: served trend sparkline, `Range lo – hi`, `On the quay N t`,
  `Paid` avg/tun or "none aboard", the `Stepper` (gauge max = quay stock / aboard; server cap as the
  red tick with its binding word), tun-figure chips, HaggleRow on buy, ONE button whose label is
  the order (`Buy 80 t · 33,180`). Slice 2 adds `Add to manifest` beside it.
* **C · The basket** (`features/port/ManifestPanel.tsx`, built 2026-09-13) — the panel in the
  tray's slot: the ship's cargo bar with the staged change washed on (from the served
  `hold.free_after`), lines from either side (`good · units · d. each · signed total`), the totals
  block once (Market tax · Port fee · Haggle saved · Profit vs bought at · Net), and ONE button
  whose words are the basket's verb and served figure — `Buy 3 lines · 1,420 d.`, `Sell 2 lines ·
  980 d.`, `Trade 3 lines · +440 d.` — atomic (`cmd.trade_basket`). Empty, it says so in one
  sentence and still shows the cargo bar. Words per `docs/WORDS.md`: "basket", never "manifest",
  in anything a player reads.
* **D · Haggle, as a thread** — inside the tray for a haggle-able line; `Take N` / `Press on`.
* **E · The receipt** (`ReceiptFace.tsx`) — the settlement after the atomic trade, in the SAME
  slot: per-line settled figures, the same totals block, ducats before → after, `Trading +N xp`;
  dismissed by one press, dropped by the next line staged, never shown on another board.
  No reputation line until a reputation authority exists.
* **F · Contracts + the real chart** — third segment: what this port pays a premium for, by
  when, how much is already aboard; and the 48-slot price history drawn with an axis.

## 4. Laws this design is built inside

| law | how it is honoured | source |
|---|---|---|
| no "where to sell" hints | this port's figures only; the tide bar is this port's own range | OWNER_REQUESTS row 55 |
| gauge, not words | gauge max = quay stock; server cap as a tick; chips carry tun figures | rows 63 · 64; UI_DIRECTION Stepper law |
| press moves nothing | a cell press opens the tray; only the labelled button executes | UI_DIRECTION §6 PORT; row 6 |
| all figures served | buy, sell, range, cap, profit, tax, spread, concession, XP — RPC fields | NO_SPAGHETTI §2 |
| ports are the base | the board opens on the quay a fleet lies at; elsewhere is read-only | UI_DIRECTION MARKET § |
| concession is a slice of spread | the thread writes spread points first, per-tun second | 0022 |

## 5. Data mapping

| element | source today | change |
|---|---|---|
| row buy / sell / tide / stock | `world.market` | none — tide position is formatting |
| row tag `native` | rarity served; origin = `goods.origin_regions` vs the port's region | add `native boolean` to `world.market` (server join; `demand` stays unserved, 0066:225-229) |
| aboard / paid | `world.fleets` cargo, cargo_basis | none |
| hold gauge, staged | `world.fleets` hold/free_hold/cargo_tuns | staged tuns from the basket preview, not client bulk maths |
| stepper cap + word | `world.buy_capacity` cap, bound_by | none |
| trend / chart | `world.price_history` | none |
| manifest totals | `cmd.preview` (one line) | **new** `cmd.preview_basket(lines[])` |
| Trade N lines | `cmd.issue` | **new** `cmd.trade_basket(lines[])` — one transaction, composed from `do_buy`/`do_sell`, returns the receipt |
| haggle thread | `cmd.haggle(side)`, `world.haggle_state` | expose `side='sell'`; serve odds / attempts if missing |
| receipt XP | `player_progress.trading` | delta in the receipt |
| contracts | absent | **new** `trade_contracts`, `world.contracts`, `cmd.fulfil` |

## 6. Build order — four slices, each dark until proven

| slice | what | done when |
|---|---|---|
| **1** frontend only — `osn-quay-board` | fold MARKET into PORT (closes RESUME.md's open fold; one harbour source); ledger row replaces the tile grid; the tray becomes the unfolded row (B) | a single-good buy and sell on production round-trip through the new row via the same `cmd.issue`; MARKET is gone from `navTabs.ts` |
| **2** migration 0083 — `osn-quay-manifest` (server, LIVE on production 2026-09-11) + `osn-manifest-panel` (frontend, 2026-09-13; supersedes the bottom-tray cut on PR #59) | `cmd.preview_basket` + `cmd.trade_basket` composed from the existing primitives; `native` on `world.market`; the basket as the right-hand panel at wide and the bottom tray on a phone; receipt | a 3-line mixed basket lands atomically on production and its receipt equals the ledger's BOUGHT/SOLD rows; a refused line refuses the whole basket |
| **3** frontend (+ a migration only if `haggle_state` lacks fields) | haggle thread, both sides; chart with axis | a sell-side haggle narrows the spread on production; "haggle saved" is non-zero on a receipt |
| **4** migration — contracts | `trade_contracts`, spawn/expiry on the day tick, premium through `trade_basket`; third segment | one contract fulfilled on production, premium as its own receipt line |

Each slice: architect (read-only, file:line) → implementer in its own worktree → adversarial
review → `tsc -b`, `eslint`, `db:apply`/`db:proof` → PR → CI (build, pglite-gate, disposable
chain, acceptance) → merge → hand deploy per `docs/DEPLOY_RUNBOOK.md` → verify on the target.

---

## Appendix A — Slice 3 blueprint (architect, 2026-09-11; read-only, nothing built)

Received after the session had to stop; kept here so the next session starts from it. Refs are
file:line on main `65cff64` + draft PR #59's tree.

**Server truth.** `cmd.haggle(fleet, good, side)` 0022:430-581 — both sides share one body/row/odds/
concession (side gates: buy needs stock, sell needs cargo); 3 attempts/day (`haggle_attempts_per_day`
0022:208) in `haggle_daily (player, port, good, game_day)`; odds = `haggle_odds` 0022:276-301; the
concession is a fraction of the PUBLISHED spread, folded by `spread_effective` with a floor; spent
on the next trade of that good at that port, either side (0022:670-673). Return 0022:558-580 carries
a **server-written merchant sentence `message`** (won / won-at-cap / lost) — the thread prints it
verbatim, no client templates. `world.haggle_state` 0022:594-659 already serves `attempts_used/left/
max, wins, concession(_pct), next_odds(_pct), spread_published, spread_effective, spread_floor,
at_floor, spent_on` — **no migration is needed**. `world.price_history` 0013:139-172 serves
`{slot, at, mid}` per point (**no `stock`** — §1 row 3 above overstated it), `slot_seconds` = 600, so
48 slots = **8 h**, not the mockup's 12 h; window = `price_history_window()` (57 today).

**Frontend today.** `HaggleRow.tsx:39` calls `'buy'` only; mounted at `PortTrade.tsx:171` on BUY only;
`useHaggleState` re-reads on `readAt`; `worldStore.haggle` deliberately does not re-read the market, so
`MarketGood.buy/sell` never reflect a bargain — only `cmd.preview` does; `saleEstimate`
(`src/domain/order/estimate.ts:45-53`) drops the served `avg_price` and `haggle_saved` — add both.
`src/chart/*` is the nautical chart; `SmallChart` is dead map code (own deletion slice) — the price
chart goes in `components/ui` beside `Sparkline`.

**A · `HaggleThread`** (`features/port`, 4 props: fleetId, good, side, preview) replaces `HaggleRow`,
mounted on BOTH sides. Folded by default as one `Row` `Bargain · N left · P%` (+ caption "x% off his
cut, held"); tap → thread expands inside the same tray body. Turns: opening line keyed on the served
`preview.avg_price` ("He names 412 d./t for 80 t."), then the server's `message` per attempt, refusals
via `Note`. Stake rows, all served: `Port's cut` published → effective (`formatPct`), `Per tun` served
avg_price with a remembered before → after across a won attempt, `On this lot` = `preview.haggle_saved`
when > 0, `Attempts` as the segmented `Bar` (tries left), `Odds of another step` = `next_odds_pct`
(muted at floor). Actions: `Take N` (collapse) · `Press on` (`haggle(fleet, good, side)`).

**B · `PriceChart`** (`components/ui`; `priceChartModel.ts` pure + `PriceChart.tsx`, 3 props):
viewBox 340×170, y ticks = served min / round(mid) / max, x ticks in hours from `at` ending `now`,
area + line, low (danger) / high (success) / now (accent ring) marks, token utilities only, legend
`low · now · high`. Opens in place from the Trend row in `PriceRows` (toggle; Sparkline is the
folded form). No cross-port figure (row 55).

**Files.** CREATE `features/port/HaggleThread.tsx`, `components/ui/{priceChartModel.ts,PriceChart.tsx}`;
MODIFY `components/ui/{index.ts,PriceRows.tsx,TradeTray.tsx}`, `domain/order/estimate.ts`,
`features/port/PortTrade.tsx`, `live/useTrade.ts` comment; DELETE `features/port/HaggleRow.tsx`.
Docs: §1 row 3 here, `SECTIONS.md`, `DEV_LOG.md`, row 76.

**Tests.** layout.spec: bargain row on BUY and on SELL (buy 1 t first in the disposable in-tab world),
thread expands with nothing above moving, both buttons ≥ 44 px, `Press on` adds a turn; chart opens
from Trend with ≥ 3 y labels and an `−Nh … now` axis, closes back to the sparkline. rpc.surface:
`cmd.haggle(…,'sell')` with the forced-win knobs (`:924-926` pattern) → SELL preview total rises and
`haggle_saved ≈ Δ` within 1. New pure `priceChart.spec.ts` for the model. Proof 06: add
`HAGGLE_SELL_SIDE_MOVES_THE_BID`.

**Tripwires.** Client odds; client spread maths; client "price after" or `good.buy/sell` shown as the
bargained figure; a second history loader; a second path builder; any outcome sentence not the served
`message`; a `12 h` / `48` literal in axis wording.
