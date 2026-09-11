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
4. **Phone-first, one column.** Ledger list + bottom tray; desktop docks the tray. Same components.
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
* **C · The manifest** — the tray's other face: lines from either side, served totals (goods at
  mid, market tax, spread after haggle, profit vs paid, net to purse, purse after), hold-after
  drawn back onto the top gauge, one button `Trade N lines` — atomic.
* **D · Haggle, as a thread** — inside the tray for a haggle-able line; `Take N` / `Press on`.
* **E · The receipt** — the settlement chit after the atomic trade: per-line settled figures,
  tax, spread, haggle saved, profit vs paid, net, purse before → after, `Trading +N xp`.
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
| **2** migration 0083 — `osn-quay-manifest` | `cmd.preview_basket` + `cmd.trade_basket` composed from the existing primitives; `native` on `world.market`; manifest face; receipt | a 3-line mixed manifest lands atomically on production and its receipt equals the ledger's BOUGHT/SOLD rows; a refused line refuses the whole basket |
| **3** frontend (+ a migration only if `haggle_state` lacks fields) | haggle thread, both sides; chart with axis | a sell-side haggle narrows the spread on production; "haggle saved" is non-zero on a receipt |
| **4** migration — contracts | `trade_contracts`, spawn/expiry on the day tick, premium through `trade_basket`; third segment | one contract fulfilled on production, premium as its own receipt line |

Each slice: architect (read-only, file:line) → implementer in its own worktree → adversarial
review → `tsc -b`, `eslint`, `db:apply`/`db:proof` → PR → CI (build, pglite-gate, disposable
chain, acceptance) → merge → hand deploy per `docs/DEPLOY_RUNBOOK.md` → verify on the target.
