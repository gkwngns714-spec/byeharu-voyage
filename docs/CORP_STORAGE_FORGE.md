# Corp, home storage, forge — and the world's gold (DESIGN, not built)

Status: design for the owner, 2026-10-29. **Nothing here is built and nothing on prod changed.**
Prod head at writing: **0272** (0273 in flight; `docs/WORK_QUEUE.md` 2026-10-29). The closed economy is
**LIVE** (0240 lit 2026-10-26 ~06:52 UTC; stamp 9,933,467,605; E5/E5b/E6/E6b ON since 10-28).

The owner's two parked asks (`docs/WORK_QUEUE.md`, parked 2026-10-28, released 2026-10-29 by *"do all"*):

1. **CORP.** *"a corp earns money, its fleet trades and brings goods to home storage, 3 goods forge into a
   high-value item, sold dear or spent on ship/captain upgrades (Tribal Wars-style timers)."*
2. **WORLD GOLD.** *"closed merchant/city economy + capped faucet per active player, target gold per active
   player flat."*

The method this follows: `docs/RESTRUCTURE.md` (one authority per concept, rows not code, the tree) and
`docs/NO_SPAGHETTI.md` (compose, never copy). Every "decided by default" is mine; the owner reverses it.

---

## 0. The corp loop, on one page

The corp is **the company the player already has**. Nothing new is founded; the house gains a home, and the
forge. The loop:

```
SET HOME (once, or the founding port)  ──►  her fleet RUNS ITS ROUTE (the standing route, laps, as today)
    buy at A · sail · buy at B  ──►  STORE lines land the 3 goods in HOME STORAGE  ──►  CORP tab: FORGE
    one recipe, 3 goods, a TIMER ("Ready in 4:48")  ──►  the TREASURE stands at home  ──►  spend it:
    SELL (the city's purse pays ×2 the goods' value — moved gold)   or   FIT it / BUILD with it (ship)
    / captain upgrade  ──►  the money buys a bigger hold  ──►  more goods home  ──►  loop.
```

- The fleet's route trading already earns money (standing routes, laps, `world.standing_routes`). The corp
  adds the home leg: instead of selling everything, the route **stores** the forge's three goods at home.
- The forge runs on its own (Tribal-Wars timers): the player need not be home, and no fleet is needed to
  finish a job. Goods go home through the fleet; work happens at home by itself.
- The treasure is the new link between the two parked asks: it is sold **from the city's purse** (moved gold,
  no new money — the closed economy holds), so the corp circulates city gold back into the player economy.

**The screen (Corp tab, following `docs/UI_DIRECTION.md`: no new screen style, short words):**

```
════════════════════════════════════
 Corp
 Home      Lisbon           [Set home]
 Storage   240 / 450 t  ·  flax 60 · tar 20 · cedar 30
 Forge
   Figurehead (gilded)     cedar 30 · tallow 10 · lead 10
   [Forge it]    Ready in 4:48   (one at a time)
 Done: Treasure ×1   [Sell 420]   [Fit]
────────────────────────────────────
```

---

## 1. What exists today — read off the chain (everything below composes it)

### 1.1 The money chain (the world-gold half)

**The one mover.** `public.credit(player, kind, delta, event)` — `supabase/migrations/20260818000004...sql:216`,
comment `:243`: *"THE ONE way ducats move. Every purchase, sale, wage, fee and salvage in the chain calls
this. Nothing else may UPDATE players.ducats."* Two deferred triggers reconcile the ledger
(`:205-213`). Every faucet and every tap in the game is a call of this one function.

**The house–city pair.** `public.pay_city(player, port, kind, amount)` — `20260818000122...sql:344`: a house
pays a city (`credit(−)` then `treasury_post(+)`). Its twin `public.city_pays(port, player, kind, amount)` —
`:363`: a city pays a house (`treasury_post(−)`, refused `E_CITY_BROKE` when the purse cannot, then
`credit(+)`). The callers, read off the chain, **are** the sink table:

| kind | who pays | caller (file:line) |
|---|---|---|
| BUY | the house | `pay_city` `0122:556` |
| TAX (on profit) | the house | `pay_city` `0122:542`, `0128:243-246` |
| WAGES | the house | `pay_city` `0128:188` |
| PROVISION · REPAIR · HIRE · BUILD | the house | `pay_city` `0122:559-576`; PROVISION also `0241:276-281` |
| TUITION | the house | `pay_city` `0131:797` |
| SHARE · DONATION | the house | `pay_city` `0123:257`, `0144:261` |
| INSURANCE | the house | `pay_city` `0213:336` |
| TOW | the house | `pay_city` `0152:176` |
| PORT_FEE | the house | `pay_city` `0237:270,316`, `0241:374-406` |
| MERCHANT_SURPLUS | the merchant | `pay_city` `0180:235` |
| SELL · DIVIDEND · BOUNTY · INSURANCE_PAID · FOUNDING · CAPITAL_GIFT | the city | `city_pays` / `treasury_post` (0122's own rule; E3 0233 / E4 0234) |

That is `docs/CLOSED_ECONOMY.md` §2.2's table, and every row lands in a purse: **removed = 0** — verified on
prod since the close. No sink of this design adds a new path; the treasure sale joins this table as one more
`city_pays` caller.

**The ledger kinds.** `public.stats_flow_words` — `20260818000214...sql:239-275` — is the one reading of a
kind's side. Minted kinds today: **EARNINGS, IMPORT_DEMAND, SEED, GRANT, FOUNDING, NPC_REFOUND** (six; 0240's
self-assert pins exactly this set, `20260818000240...sql:457`). 0228 relabelled CROWN_AID / CROWN_TAX as
**moved** and added CAPITAL_GIFT / CROWN_CALL (`0228:89-93`).

**The closed economy's stamp — it is BUILT and LIT, not a plan.** `public.economy_closed()` (0228) reads the
flag; `public.mint_guard(kind, delta)` — `0240:236-256` — is **the one judge** of new gold: closed and the
purses lit, a positive delta of a minted kind is refused `E_NO_NEW_GOLD` at both writers (hunks on
`public.credit` `0240:264-275` and `public.treasury_post` `0240:276-284`). A city that pays runs its credit
under a local setting, `byeharu.paid_by_city = 'on'`, put back after (`0240:285-313`). The switch
`public.economy_close_switch` (`0240:338`) recorded the stamp knobs `economy_closed_at` and
`economy_closed_total` = **9,933,467,605** (`0240:229-233`). Live reading (WORK_QUEUE 10-29): closed,
`moved_since_close` +138 (the known one-time race; owner: leave it), new money 0 — **the world total is flat
by construction today.**

### 1.2 The corp's raw material (everything the corp part composes)

| concept | where it already lives |
|---|---|
| the company | `public.players` ("the house"); founded by `cmd.found_house` / `public.new_house`. **The corp is this company, extended — no second company type, no new table of corps.** |
| the fleet trades on its own | standing routes, already player-facing: `world.standing_routes`, the route editor, laps, `cmd.run_standing_route`, `public.route_earnings`. |
| storage ashore | `public.player_storage(player_id, port_id, good_id, qty)` `0070:97`; the verbs `cmd.do_store` `0070:146` / `cmd.do_take` `0070:201`; cap `public.storage_cap` `0070:130` (every harbour has a warehouse, tier 1–5, `0070:83-86`); the read `world.warehouse` `0070:296`. Goods are **per port**: what is stored at Bilbao is at Bilbao. |
| crafting | `public.item_kinds` `0068:78` (12 fittings, each `buys` one stat and `spends` another, `ws_tier` 1–3); `public.item_recipes(item_code, good_id, qty)` `0068:111` (2–5 goods a recipe, authored in `data/fittings.json`, world-guard-held); `cmd.do_make` `0068:241` (instant, from the **hold**, at a workstation city); output `public.player_items(player_id, port_id, item_code, qty)` `0068:165` — items stand at a port, the owner's location law (`0068:173-175`). |
| an item's worth | `public.item_recipe_value(item)` `0158:605` — the recipe's goods at their base value. |
| items in upgrades | ship: `cmd.do_fit` `0074:293` (fit an item from storage at the port) and `public.hull_recipe_items` (a hull's parts); captain: `public.promotion_items` `0162:175`. |
| a timed queue | `public.skill_queue(player_id, pos, skill_id, to_level, starts_at, finishes_at)` `0131:425` — the game's own timer row: starts and finishes instants, advanced by the clock. |
| home, the merchant precedent | `public.npc_houses.home_port_id` `0097:118`; the merchant refound pays from it (`0122:721`). Players have no such column yet. |
| the clock | one authority is **designed** (`docs/RESTRUCTURE.md` §3.3 A1: `voyage.clock_rate()` / `voyage.real_seconds(hours, rate)`); today the conversion is inline in 11 functions. §7 C3's dependency. |

---

## 2. The new rows (tables, columns and data — rows, not code)

### 2.1 Corp

**`public.players` gains one column**

| column | type | meaning | writer |
|---|---|---|---|
| `home_port_id` | uuid null, FK `public.ports` | the corp's home — where the route stores, and the forge works | `cmd.set_home`; `public.new_house` sets it at founding (= the founding port). Nothing else. |

**`public.item_kinds` gains two columns** (the catalogue stays ONE table; a forge item is an item)

| column | type | meaning | writer |
|---|---|---|---|
| `made_in` | text, `'workshop'` (default, = today) or `'forge'` | where the item is made. `cmd.do_make` refuses a `'forge'` item (`E_FORGE_ONLY`); only the forge makes it. | data (`data/fittings.json` / `data/forge.json`, world-guard-held) |
| `forge_hours` | numeric null | how long the forge takes (game hours, through the clock authority). null for workshop items. | data |

**`public.item_recipes` — forge rows** (the same table, no second recipes authority)

| row | rule |
|---|---|
| `(item_code, good_id, qty)` | **exactly 3 rows per `'forge'` item** (the owner's "3 goods"); a guard on the data file fails any other count. The goods are ordinary trade goods, already produced somewhere — the fleet buys them on its route. |

**`public.forge_jobs` — the timer queue (the skill_queue shape, `0131:425`)**

| column | type | meaning | writer |
|---|---|---|---|
| `id` | uuid PK | one job | `cmd.forge` |
| `player_id` | uuid FK players | whose | `cmd.forge` |
| `item_code` | text FK item_kinds | what is being forged | `cmd.forge` |
| `qty` | int ≥ 1 | how many | `cmd.forge` |
| `home_port_id` | uuid FK ports | the home at start (the goods are consumed there; the treasure lands there) | `cmd.forge` |
| `starts_at` | timestamptz | when it began | `cmd.forge` |
| `finishes_at` | timestamptz | `starts_at` + `forge_hours` through the clock authority | `cmd.forge` (computed by the clock rule, never by the client) |
| `done_at` | timestamptz null | when it completed | `public.forge_complete_due` only |

Index `(player_id) where done_at is null`. Jobs complete **on read** (lazy — §4), never in the arrivals
beat: the beat's time budget is not this feature's.

**`public.world_config` knobs** (each read through `public.wc_num`, as every knob)

| key | default | meaning |
|---|---|---|
| `forge_slots` | 1 | how many jobs run at once. 1 = Tribal-Wars's one forge, one queue. |
| `forge_mult` | 2.0 | the treasure's sale value = the recipe's goods' value × this ("sold dear") |

### 2.2 World gold

**`public.faucet_days`** — who got the day's faucet, once

| column | type | meaning | writer |
|---|---|---|---|
| `player_id` | uuid FK players | the company | `public.faucet_mint` only |
| `day` | date | the real day | `public.faucet_mint` only |
| `paid` | bigint | what was minted that day | `public.faucet_mint` only |

PK `(player_id, day)` — a day is paid at most once, so the daily job is idempotent (re-runs after a cron
failure pay nothing twice).

**`public.stats_flow_words` gains one row**

| kind | side | word | ord |
|---|---|---|---|
| `FAUCET` | `minted` | `New money: faucet` | 8 |

It is the **only** new minted kind, and mint_guard's only exception (§6.2).

**`public.world_config` knobs**

| key | default | meaning |
|---|---|---|
| `faucet_per_day` | **0** | the cap: what one active company is minted per real day. 0 = nothing (dark, byte for byte). **This is a knob value, not a new switch** — the owner lights the faucet by setting it (one update, owner-only, like every knob; never by a migration). |
| `faucet_active_days` | 7 | "active" = at least one BUY or SELL in this many real days |

---

## 3. One authority per concept

| concept | the ONE authority | composes / replaces |
|---|---|---|
| money moves | `public.credit` (`0004:216`) | unchanged. The faucet and the treasure sale go through it. |
| a city pays | `public.city_pays` (`0122:363`) | the treasure sale calls it (`ITEM_SALE`); nothing is re-implemented. |
| new gold is judged | `public.mint_guard` (`0240:236`) | gains its ONE exception: kind `FAUCET` passes only while `byeharu.faucet_mint = 'on'`, set for its own credit by `public.faucet_mint` — the exact `paid_by_city` shape (`0240:285-313`). No other minted kind, no other path. |
| who is active | `public.active_companies(p_days int)` | one SELECT over `public.ledger` (`kind in ('BUY','SELL')` in the last `p_days`); used by the daily job AND the served Stats figure. No second count anywhere. |
| the faucet mints | `public.faucet_mint(p_player)` | the one writer: inserts the `faucet_days` row (on conflict: nothing) and credits `faucet_per_day`, kind `FAUCET`. Server-only, called only by the daily job. |
| the home | `public.players.home_port_id` | one column, two writers (`new_house` at founding, `cmd.set_home`), served by `world.player`. The merchant column (`0097:118`) stays the merchants'. |
| storing ashore | `cmd.do_store` (`0070:146`) | the route's STORE line **calls it** — the route runner gains no cargo-moving code. |
| taking from storage | NEW `public.storage_take(p_player, p_port, p_good, p_qty)` | names the removal `cmd.do_take` already performs (`0070:240-243`); `do_take` is re-cut to call it (byte-identical), and the forge calls it. One removal rule. |
| items into storage | NEW `public.item_store(p_player, p_port, p_item, p_qty)` | names the insert `cmd.do_make` already performs (`0068:298`); `do_make` is re-cut to call it (byte-identical), and `forge_complete_due` calls it. One insertion rule. |
| a recipe | `public.item_recipes` (`0068:111`) | forge recipes are rows in the same table, distinguished by `item_kinds.made_in`. No second recipes table, no second reader. |
| a timed job | `forge_jobs.starts_at / finishes_at` | the `skill_queue` shape; the duration passes through the clock authority (`docs/RESTRUCTURE.md` A1 `voyage.real_seconds`) — see §7 C3. |
| a due forge completes | `public.forge_complete_due(p_player)` | the one completer, called lazily by `world.forge` and by the sell/fit paths. Never in the beat. |
| a treasure's price | NEW `public.forge_value(p_item)` = `public.item_recipe_value(p_item)` × `forge_mult` | composes `0158:605` (the one recipe value) with the one knob. The client never prices it. |
| selling the treasure | `cmd.do_sell_item` | pays through `city_pays` (`ITEM_SALE`, moved — the guard needs no change); removes through the one item consumer (`public.item_take`, the twin of `item_store`, used by `do_fit`'s path too). |
| gold per active player | `world.stats_now` + the one `active_companies` count | the server divides and serves `per_active`; the client never divides (§4). |

---

## 4. Sim / presentation split

**The server is true** — every rule above is a server function. The client shows served payloads and
computes nothing:

- a forge job's `finishes_at` is a served instant; the "Ready in 0:42" label is a countdown **display** from
  that instant (presentation, like the arrival countdown today). The client never derives the instant
  (`docs/RESTRUCTURE.md` §4.5: a missing served value is an error, never a silent constant).
- the forge's `can`/`shut` answer (materials short, one job open, not a forge item) is a server refusal code,
  printed as today's refusals are (`E_NO_MATERIALS`, `E_FORGE_BUSY`, `E_FORGE_ONLY`, `E_CITY_BROKE`).
- the treasure's price is served with the forge row; the client shows it.
- `active` and `per_active` are served by Stats; the client divides nothing.
- the forge completes jobs **on read**: `world.forge` (and the sell/fit paths) call
  `public.forge_complete_due` first. A due treasure exists the moment the player looks. The arrivals beat
  (`tick_arrivals`) is not touched — its measured time budget (`docs/dev-log` 0265-0272) is not this
  feature's.

---

## 5. Words — every new control, 1–2 plain words (through `src/lib/i18n/dict/*`)

| control | EN | KO |
|---|---|---|
| the tab | Corp | 상사 |
| the home port, and the route stop | Home | 본거지 |
| the command | Set home | 본거지 설정 |
| the building | Forge | 대장간 |
| start a job | Forge it | 제작 |
| a job running | Ready in 0:42 | 완료까지 0:42 |
| one job open (refusal) | Forge busy | 제작 중 |
| the output | Treasure | 보물 |
| the route line that stores | Store | 보관 |
| selling the treasure | Sell | 판매 |
| the flow word (Stats, ledger) | New money: faucet | 신규 화폐: 수당 |
| the ledger line to the player | Faucet | 수당 |
| Stats: how many act | Active | 활동 |
| Stats: gold per active company | Per active | 1인당 |
| the treasure sale flow word | Item sale | 물품 판매 |

`docs/WORDS.md` rules kept: **storage** stays the one word for the building and the act (`WORDS.md:46`); the
route's STORE line says "Store" because it is the same act, one word.

---

## 6. WORLD GOLD: the faucet — one authority, measurable on prod

### 6.1 The taps and sinks today (read off the chain, §1.1)

- **Taps (faucets): none lit.** The economy is closed; `mint_guard` (`0240:236`) refuses the six minted
  kinds at both money writers. EARNINGS and IMPORT_DEMAND are not posted lit (0233); SEED, GRANT and
  NPC_REFOUND have no writer lit and are refused if called; FOUNDING is paid by the country's capital through
  `city_pays` (0234) — moved, not minted. New money reads 0 (the §7 watch).
- **Sinks: all land in purses, removed = 0.** The table in §1.1 is the whole sink set; nothing burns gold.
  A closed economy therefore has **one** problem left: the total is frozen while the player base moves, so
  **gold per active player drifts** — down when companies join, and it cannot answer a player's bare purse.
- **The stamp:** `economy_closed_total` = 9,933,467,605 (`0240:229-233`, recorded by the switch at close).

### 6.2 The faucet rule (the owner's second ask)

**One writer, one kind, one cap, paid once a day.**

- `public.active_companies(p_days)` — a company (human **or** merchant; both are the economy's players) with
  at least one BUY or SELL ledger row in the last `faucet_active_days` real days. Measurable on prod
  read-only: `select count(distinct player_id) from public.ledger where kind in ('BUY','SELL') and
  created_at > now() - interval '7 days'`.
- The existing **daily job** (00:00 UTC — the daily-settings job E5b 0252 rides; `clock` owns when,
  `ledger` owns what) calls `public.faucet_mint(p_player)` for every active company.
- `faucet_mint` inserts the day's row first (idempotent) and credits `faucet_per_day`, kind `FAUCET`, under
  `byeharu.faucet_mint = 'on'` for its own credit, put back after — `mint_guard`'s **one exception**. Cap per
  player per day = the knob. Total mint per day ≤ active × `faucet_per_day`. Nothing else can mint a FAUCET.
- **The target, made true by construction.** With `faucet_per_day` at the recommended **100** and about 840
  active companies, the whole faucet mints ≤ 84,000 a day ≈ **0.004 % of the stamp** — gold per active
  player cannot drift by more than the cap allows, which is under the existing ±0.1 %/day watch trigger
  (`docs/CLOSED_ECONOMY.md` §7, kept). The owner re-sizes the one knob, one update, never a switch.
- **Measurable on prod, every figure served by Stats:** new money per slot (must equal FAUCET and be
  ≤ active × cap), `per_active` = world total ÷ active (served against the stamp ratio), and the §7 triggers
  unchanged (world total Δ, cities under reserve, broke merchants — the faucet touches none of them: it never
  pays into a city purse).

---

## 7. Slices — in the order they land; each shippable alone, with its measurement and its rollback

After RESTRUCTURE R2 merges, every slice is a tree edit + emitted migration (`docs/RESTRUCTURE.md` §2.3).
Until then, they are hunk migrations exactly as today. Migration numbers are the prod head + 1 at push.
Each migration self-asserts on its own probe rows, rolled back; nothing DELETE from append-only tables.

| # | slice | does | measurement (self-assert + prod) | rollback (forward) |
|---|---|---|---|---|
| **G1** | `the_faucet_is_named` | knobs `faucet_per_day` 0 / `faucet_active_days` 7; `faucet_days`; `active_companies`; `faucet_mint`; the FAUCET word; mint_guard's one exception (hunk) | dark, byte for byte (the hunk reverses); lit in-block: a bare `credit('FAUCET',+)` is refused, `faucet_mint` passes and pays the cap, a second call the same day pays nothing, the setting is put back; cap 0 pays 0 | reverse the hunk; drop the two functions, the table, the knobs, the word row |
| **G2** | `the_faucet_runs_daily` | the daily job's faucet pass over `active_companies` | still dark (pays 0): 0 rows written by a probe run; a probe company with a BUY inside / outside 7 days is in / out of the set; the job's added time measured (< 1 s target); idempotent re-run pays nothing | remove the job's faucet pass |
| **G3** | `the_figures_say_per_active` | Stats serves `active` and `per_active` (server divides); client line "Per active / 1인당" in Overview beside New money | probe rollup over planted probe rows; old keys unchanged; New money shows FAUCET (0 while dark) | revert the read and the client line |
| **G4** | **LIGHT** (no migration) | the owner's one `update public.world_config set value = '100' where key = 'faucet_per_day'` with the deploy note | 30-min after-check + the §7 watch: new money = FAUCET only and ≤ active × cap; `per_active` within ±0.1 %/day of the stamp ratio; no city figure moved | the owner's one update back to 0 |
| **C1** | `the_house_has_a_home` | `players.home_port_id` + `cmd.set_home` (the fleet docked at the port) + founding sets it; `world.player` serves it; Corp tab skeleton shows Home | probe: founding sets home = founding port; set_home moves it and refuses a sailing fleet (`E_NOT_DOCKED`); nothing else reads the column; every existing company keeps null (no backfill — the first `set_home` or the first forge... see defaults) | drop the column (`--allow-drop` by hand) and the function; client revert |
| **C2** | `the_route_brings_it_home` | `standing_route_lines` gains the STORE verb; the runner calls the existing `cmd.do_store` (no second cargo mover); route editor: Home stop + STORE lines (client in the same PR) | probe lap: buy at A, STORE at home, the storage row equals a hand `do_store`'s (same answer, byte-identical flows); a route without STORE lines runs byte-identical; a full shed refuses `E_SHED_FULL` on the lap's own step | remove the verb branch and the client |
| **C3** | `the_forge_works` | `item_kinds.made_in` / `forge_hours`; `cmd.do_make` refuses forge items; the named storage/item rules (`storage_take`, `item_store`, `item_take`) with `do_take`/`do_make` re-cut byte-identical; `forge_jobs`; `cmd.forge` (goods from **home storage**, one job open, timer through the clock authority); `forge_complete_due`; `world.forge`; the launch recipes (6, §8); Corp tab forge screen (client) | probe: 3 goods leave home storage exactly as `storage_take` says; `finishes_at` = starts_at + `forge_hours` through the clock; a due job completes on the read and lands in `player_items` at home via `item_store`; a second job refuses `E_FORGE_BUSY`; a workshop item refuses `E_FORGE_ONLY`; dark = today byte for byte (no forge item exists until the data lands in this slice) | forward: drop the table and columns, drop the functions, reverse the two re-cuts, remove the data |
| **C4** | `the_treasure_is_sold` | `cmd.do_sell_item` at any port where her items stand and a fleet is docked; price = `forge_value`; `city_pays('ITEM_SALE')` — moved; a purse too short refuses `E_CITY_BROKE` (no shrink, decided by default); Sell on the forge screen (client) | probe: sale = recipe value × `forge_mult`, purse pays the whole (flow row `ITEM_SALE`, ledger moved), items gone; a broke purse refuses and nothing moves; closed economy: no new gold (the probe's flows hold no minted row) | drop the function and the word row; client revert |
| **C5** | `the_treasure_builds_and_fits` | data only: two treasures in `hull_recipe_items` (ship build needs them) and effect rows for the ship slots and the captain's figures through the existing `item_effects` / `cmd.do_fit` — no new rule (build-time check names the effect targets) | yard / academy show the requirement; `do_build` and `do_fit` accept the treasure from `player_items` at the port | delete the data rows |

Order: G1 → G2 → G3 (G4 is the owner's light); C1 → C2 and C3 (C3 needs C1; C2 needs C1) → C4 → C5 (both
need C3). G and C do not touch, so G runs beside C in its own lane. **C3's clock dependency:** the timer
composes `voyage.real_seconds` (RESTRUCTURE A1). If A1 has not merged when C3 builds, C3 adds that one
function (A1's exact body) and A1's probe covers it — the ROUTE_BUILDER B1 pattern (`docs/ROUTE_BUILDER.md` §3).

---

## 8. Decided by default (the owner reverses any)

| # | decision |
|---|---|
| 1 | The corp **is** the existing company (the house). No new company type, no corp members or roles. |
| 2 | Home = the founding port at founding; `set_home` needs a fleet docked there; moving home moves nothing (stored goods and treasures stay per port — the owner's location law). |
| 3 | The forge lives at home only, one job at a time (`forge_slots` 1); it eats **home storage**, not the hold; no fleet needed to start or finish. |
| 4 | Exactly **3 goods** per forge recipe (the owner's words); 6 launch recipes: 2 ship treasures, 2 captain treasures, 2 sell-only — authored from the goods' production map at build time, held by the world guard. |
| 5 | Forge time: 2–8 game hours per recipe (`forge_hours` on the row; 1 game hour = 3 real minutes at today's clock — the clock authority does the conversion, never a hard-coded minute). |
| 6 | Treasure sale: `forge_mult` 2.0; paid by the city purse, refused (not shrunk) when short. No cancel on a forge job: the goods are committed (the simplest honest timer). |
| 7 | Faucet: `faucet_per_day` **0** at build (dark); the recommended value is **100**, the owner lights it by one update (owner-only knob, never a migration, never a new switch); active = a BUY or SELL in 7 real days; humans and merchants both count; paid once a day in the daily job. |
| 8 | The faucet pays companies only — never a city purse; `per_active` divides the world total by active companies. |
| 9 | Merchants do not forge and do not get homes of this kind (they keep trading; their `home_port_id` stays theirs). |
| 10 | Existing companies: `home_port_id` starts null (no backfill); the forge screen says "Set home" until it is set; the route's Home stop needs it. |

---

## 9. What it does NOT do

- **No new company type, no corp-to-corp anything** — no corp trading, members, roles, wars or rankings.
- **No new economy switch.** The faucet is a knob whose 0 is the dark posture; the closed-economy flag and
  the mint guard stay the only switches, owner-only, unchanged.
- **No beat work.** Forge completion is lazy on read; `tick_arrivals` is untouched.
- **No second cargo or storage mover.** The route calls `cmd.do_store`; the forge calls the named storage
  rule; nothing moves goods between ports without a ship (the NO-HOME law, `docs/FLEETS_AND_SLOTS.md` §1).
- **No second recipes table or price formula** — one `item_recipes`, one `item_recipe_value` × one knob.
- **No refunds, no cancel, no queue skipping** on the forge.
- **No faucet for inactive companies, no per-company faucet differences, no negative faucet, no faucet into
  city purses.**
- **No client arithmetic**: no client price, no client due instant, no client active count.
- **No prod changes here.** This is a design document; the slices land behind the queue's current order
  (`docs/WORK_QUEUE.md`: bugs → RESTRUCTURE → then these).

---

## 10. Risks

| risk | handling |
|---|---|
| the faucet's exception is abused (a planted `FAUCET` credit) | the guard checks the local setting, which only `faucet_mint` sets (the `paid_by_city` shape, `0240:285-313`); G1's probe asserts a bare FAUCET is refused |
| the faucet inflates instead of holding flat | the cap is the bound: ≤ active × cap a day, ≈ 0.004 % of the stamp at 100 — under the ±0.1 %/day §7 trigger; the knob is one update |
| merchants hoard the faucet | 100/day against their trading income is noise; the §7 "merchant Σ purse" trigger stays the watch |
| the forge eats the route's goods and starves the trader | only the STORE lines feed it; a player stores what she chooses; selling the goods stays the default route |
| a broke home city cannot buy the treasure | `do_sell_item` works at **any** port where her items stand (items stay per port); `E_CITY_BROKE` is the honest refusal |
| the lazy completion is forgotten by a new consumer path | every path that reads treasures (forge screen, sell, fit, build) calls the one `forge_complete_due` first — one rule, asserted in C3 |
| the clock authority is not merged when C3 builds | C3 adds `voyage.real_seconds` itself (A1's exact body); A1's probe later covers it — no second clock formula |
