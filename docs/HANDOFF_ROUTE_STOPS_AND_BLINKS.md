# ROUTE STOP FACE + NO-BLINK — audits and plan (2026-09-30)

Raw output of the workflow that was STOPPED for the machine hand-off: two read-only audits and the architect's plan (with the A/B file partition). The implementations are WIP on `osn-no-blink` and `osn-route-stop-face`. Their gates were never run.

## Audit: route stop display

FILE:LINE MAP of origin/osn-trade-routes @ 0ab0d8b (fetched 2026-09-30). All paths are in the branch.

## A. The one-line stop string (owner: "sell all buy all ... in one line")

The line is built on the client, not from the server's raw_text.
- `src/domain/route/index.ts:124-141` `routeStopWords(stop, goodByCode)`
  - Reads `stop.lines[].kind/good/qty/price_limit` and `stop.repair`.
  - SELL prints `Sell ${good}` or `'Sell all'` (:130).
  - BUY prints `[Buy X, formatUnits(qty), Max formatUnitPrice(price_limit)].join(', ')` (:132-136).
  - Repair adds `'Repair'` (:139). Everything is joined with `' · '`, or reads `'Trade nothing'` (:140).
  - Gaps: SELL `qty`, SELL `price_limit` (the floor) and `at_profit` are never printed. A buy with no qty prints no units word, even though null means ALL (types.ts:1463).
- There is one render site. `src/features/command/RouteFold.tsx:149-158` draws one `Row` per stop. The label is `portNameOf(portByCode, s.port)` and the child is a single faint caption span `text-t-caption text-ink-faint` holding `routeStopWords(s, goodByCode)` (:156). Sell and buy share one caption line, one tone, no mark and no second row.
- The same one-line problem exists in the editor. `src/features/command/RouteEditor.tsx:107-124` puts `Chip "Sell all"` (:108-110) and N × `Chip "Buy {g.name}"` (:114-123, data-testid route-buy-good) in ONE `flex flex-wrap gap-2` row. Every chip uses the same Chip skin: on is `bg-accent-soft text-accent`, off is `bg-surface-2 text-ink-muted` (`src/components/ui/Chip.tsx:45`). The Units and Max fields only appear under a chosen buy (:125-146). Placeholders are "Units (blank: all that fit)" and "Max each (blank: any)".
- Served shape: `src/lib/rpc/types.ts:1458-1479`. `StandingRouteLine{ord, kind 'SELL'|'BUY', good|null (=sell everything), qty|null (=ALL), price_limit (BUY max / SELL floor), at_profit}` and `StandingRouteStop{ord, port, course, repair, lines}`. There is no resupply field on a stop. Resupply is the fleet's 0034 keep level (next section).
- Draft ↔ served: `src/features/command/standingRouteDraft.ts`
  - `RouteStopDraft` :24-42: sellAll, one buyGood/Units/Max, repair, sellAllFloor, kept[].
  - `emptyStop` :45-56 defaults sellAll to true.
  - `draftOfRoute` :60-75.
  - `routePayload` :93-121 builds the line order: kept SELL, sell-all, the one BUY, then kept BUY.
- Callers of `src/domain/route`: RouteFold (above) and FLEETS' caption through `routeCaption` (`src/features/fleets/FleetsScreen.tsx` diff hunk @@-91: `where=[…, routeCaption(routeOfFleet(routes, fleet.id))]`).

## B. What the server writes per stop (this is what the queue actually shows)

- `supabase/migrations/20260818000092_a_route_is_a_standing_order_that_sails.sql:421-473` builds `cmd.standing_route_lines`. Its raw_text order is:
  1. `SELL <code> <qty|ALL> [AT >= floor]`, one line per good on board for sell-all (:423-443).
  2. `PROVISION DAYS n`, only when below the keep level (:445-451).
  3. `REPAIR` (:453-456).
  4. `BUY <code> <qty|ALL> [AT max]` (:458-466).
  5. `SAIL TO <next>` (:468-472).
  - These rows are inserted with `raw_text` at :340.
- The queue prints them through `src/features/command/Queue.tsx:39-50` `humanize()`. It takes `verbWord(order.verb)`, drops the fleet name and TO/AT/VIA/ON, maps codes to port or good names, and passes every other token through raw.
  - Result: "Sell Iron ALL >= 12.5", "Buy Iron 20 12", "Resupply DAYS 5". These are bare figures and an uppercase ALL, which breaks WORDS law 2.
  - `verbWord` is at `src/domain/order/text.ts:152-167` (PROVISION → 'Resupply' at :155, REPAIR → 'Repair' at :158).
- Lap money: `RouteFold.tsx:160-174` prints the caption "Sold · Bought · Supplies · Repairs · Wages · n skipped" as one faint line. Its figure is `Figure formatDucatsDelta(l.net)` with `deltaTone(l.net)` (:164). The folded header also uses `deltaTone(lastLap.net)` (:81).

## C. How the trade face tells buy from sell (tokens to reuse; do not invent new ones)

- Colour is not the side marker. `src/components/ui/deltaTone.ts:5-14` says green and red only ever mean cheap/dear or gain/loss (UI_DIRECTION §4.4). `deltaTone` is for signed money only (`src/features/port/ManifestTotals.tsx:48,56`; `src/features/port/ReceiptFace.tsx:46`).
- Side is shown by position and a label word:
  - `src/components/ui/TradeRow.tsx:77-93`: two `PriceCell`s in a `grid grid-cols-2`, with label `"buy"` and label `"sell"`.
  - `PriceCell` → `ActCell` at `TradeRow.tsx:120-135`.
  - `src/components/ui/ActCell.tsx:42-47`: a `w-28 min-h-14` box with a faint caption label, a Figure under it, and a dead-reason line. Selected is `bg-accent-soft`, otherwise `bg-surface-2`.
  - `src/features/port/OnBoard.tsx:114` reuses `PriceCell label="buy"`, and its sell cell follows.
- Per-line side word, one Row per line:
  - `src/features/port/ReceiptFace.tsx:24-35`: Row label is the good; caption is `` `${sold|bought} · units · price each` ``; the value is `Figure formatDucatsDelta(lineDelta(l))`.
  - `src/features/port/ManifestPanel.tsx:224-241`: the same shape, caption `` `${line.side} · units · avg` ``, plus a profit or loss line for a sell.
- Separate faces: `src/features/port/tradeFace.ts:21-22` has `{buy:'Buy'},{sell:'Sell'}` inside `Segmented` (`src/features/port/TradeFaces.tsx:11`).
- Section heading: `SheetSection heading="On board"` (`OnBoard.tsx:46`).
- So the stop face should reuse this pattern: one `Row` per line, a side word in the caption voice (Sell / Buy, the words at `ReceiptFace.tsx:32`), `Figure` for the price or Max, and `formatUnits` / `formatUnitPrice`. No new colour.

## D. The blinking (owner: "Start route in command blinks on its own")

**Root cause: one global flag is misused as a disabled gate.**
- `src/live/worldStore.ts:158-159` defines `busy`: "True while a refresh is in flight — for a quiet indicator, never for a blocking spinner."
- `refresh()` sets `busy:true` at :418 and `busy:false` at :423 and :433.
- `src/app/AppShell.tsx:63-72` polls every `readIntervalMs` (`READ_MIN_MS = 3_000` at :34, max 30 s). Tab focus also triggers a refresh (:76-85). Both check `!world.busy`, which is the flag's legitimate use as an in-flight dedupe.
- `Button` renders a disabled button at `disabled:opacity-45` (`src/components/ui/Button.tsx:74`, :83).
- So every 3 s beat, any button with `disabled={busy}` dims and comes back. All consumers of the store's `busy` (full grep of src):

| File:line | What blinks | Branch |
|---|---|---|
| `src/features/command/RouteEditor.tsx:34`, `:165` | **Start route / Save route** (`disabled={busy \|\| !complete \|\| !seaNav}`) | new in #89 |
| `src/features/command/RouteFold.tsx:40`, `:110`, `:113`, `:116` | spare route Start, Edit, Delete | new |
| `RouteFold.tsx:133` | stopped-note Clear | new |
| `RouteFold.tsx:180` | Pause / Resume | new |
| `RouteFold.tsx:186`, `:189` | Edit, Delete | new |
| `src/features/command/CommandScreen.tsx:46`, `:110` → `src/features/command/Queue.tsx:89` | each order's cancel ✕ | also on origin/main (CommandScreen.tsx:42, Queue.tsx:89) |
| `Queue.tsx:112` | "Clear all orders" / "Clear the stopped order" | also on main |

- No other file reads the store's `busy`. The other `busy` names in the code are per-press local state, and that is the correct pattern:
  - `Button.tsx:64` ("the caller keeps its own phase state")
  - `src/features/fleets/standingOrder.ts:78`
  - `src/features/port/HaggleThread.tsx:69`
  - `src/features/port/PortAcademy.tsx:43`
  - `src/features/profile/ProfileScreen.tsx:47`
  - `src/features/found/SignTheBook.tsx:33`
  - `src/features/map/useSendFleet.ts:146`

**Second path: the routes read drops its answer.**
- `worldStore.ts:538-541` `loadRoutes` does `set({ routes: r.ok ? r.value : null })`. One failed read nulls the book, and then:
  - the RouteFold label falls to `'Route'` (`RouteFold.tsx:69-70`);
  - the `route-state` word vanishes (:87-91);
  - the open fold shows "Loading…" (:96-97);
  - the FLEETS caption word disappears.
- It is fired on every `readAt` twice, from `RouteFold.tsx:55-57` and the `FleetsScreen.tsx` hunk @@-68 (`useEffect(() => void loadRoutes(), [loadRoutes, readAt])`). Every beat therefore makes two concurrent identical reads.
- This is the exact defect row 77 retired. `docs/OWNER_REQUESTS.md:154` and `src/live/useServedRead.ts:17-24` state the rule: keep the last answer for the same subject while the re-ask is on the wire, and never blank on the beat. `useServedRead.ts:36-37` says "nothing in src/live keys its own answer on `readAt` any more". The routes read bypasses that rule; it is store state, not a doorway onto `useServedRead`.

**Prior fixes to model on:**
- Row 77: `useServedRead`, PR #62 (`docs/RESUME.md:43,102`).
- Max-flicker: rows 95-97, `docs/OWNER_REQUESTS.md:172-174`, DEV_LOG :562, ceiling exemption retired at `useServedRead.ts:30-37`.

## E. Fix shape consistent with the laws

- **Flicker:** make ONE rule. The store's `busy` is poll-in-flight only and is never a `disabled` gate.
  - Remove `disabled={busy}` at all 11 sites above, and remove the `busy` prop on Queue (`CommandScreen.tsx:110`, `Queue.tsx:19,25`).
  - Replace it with per-press pending state through `Button busy` (the documented pattern).
  - Add a guard test that forbids `useWorld((s) => s.busy)` outside AppShell.
  - For routes: keep the last book when a read fails (never set null after the first answer), and do one routes read per beat from one owner, not two screens.
- **Stop face:**
  - Replace the single caption from `routeStopWords` with one Row per line (Sell / Buy side word, then good, then `formatUnits` or "all", then `Max`/floor through `formatUnitPrice`), using the ReceiptFace/ManifestPanel pattern plus `ActCell`/`PriceCell` tokens.
  - Print the missing SELL qty, floor and at_profit ("Only sell above cost", per `tests/words.spec.ts` hunk).
  - In RouteEditor, split the Sell control and the Buy chips into two labelled groups.
- **Queue humanize** (`Queue.tsx:39-50`): route-written ALL, `>=`, AT figures and DAYS reach the player raw. Word them through format or `domain/order`, never inline.

Constraint: the bv-routes worktree belongs to the driving agent, so all edits go on a separate worktree off origin/osn-trade-routes.

## Audit: sweep for self-blinking bars

BLINK AUDIT: origin/osn-trade-routes at 0ab0d8b, compared with main at a613a05. Nothing was edited. The scratch worktree C:/Users/디폴리스/bv-blink-audit has been removed, and the preview on port 4395 is stopped.

Every blink I measured has one cause: the store's world-read flag. The shell re-reads the world every 3 s (`AppShell.tsx:34,65-71`, 9600 compression). While each read is in flight, `worldStore.ts:418` sets `busy` true, and `worldStore.ts:433` sets it back to false. That flag is wired straight into buttons' `disabled`. The Button fades to `disabled:opacity-45` over a 180 ms transition (`Button.tsx:73-74`, `index.css:278-279`). So every 3 s each of those buttons dims for about 200 ms and comes back. The store's own comment (`worldStore.ts:158`) already says this flag is "never for a blocking spinner".

**How it was measured.** The Claude-in-Chrome tab reported `document.visibilityState = hidden`, so its timers were throttled. It still caught "Start route" toggling: disabled at 2763, 5762, 8758, 11753 and 14753 ms, enabled again about 200 ms after each. The full sweep ran in headless Chromium (Playwright, 390×844) with the same MutationObserver.

- **Idle for 30 s:** COMMAND, FLEETS, MAP and HISTORY (`/ledger`) had 0 events. PORT faces (Trade, Town, Storage, Craft, Inn, Build, Repair) and an open Iron buy tray showed only the 1 s price countdown.
- **With a moving value:** the "N miles of N miles" progress text, the purse, the supplies line and the "to Porto · Ns" countdown update in place. They never blank, so they are not blinks.
- **Routes:** `standing_routes_enabled` was switched on in the scratch database only.
- **Queue:** a real SAIL plus two pending BUY orders were issued through `cmd.issue` to get queue rows.

**Confirmed blinking (class A: a button disabled by the world read)**

| # | Element | file:line | On main? | Measured |
|---|---|---|---|---|
| 1 | "Start route" / "Save route" | `RouteEditor.tsx:34,165` | no (branch only) | 20 toggles in 30 s: disabled at 1109, 4099, 7095 ms, enabled about 210 ms later |
| 2 | Spare route "Start", "Edit", "Delete" | `RouteFold.tsx:40,110,113,116` | no | 20 toggles each in 30 s, all together (1408→1602, 4410→4613 ms) |
| 3 | Running route "Pause/Resume", "Edit", "Delete", and "Clear" on a stopped route | `RouteFold.tsx:133,180,186,189` | no | Not driven: assigning a route is refused without a supplies order. Same `busy` wiring as #2. |
| 4 | Queue cancel ✕ on each live order | `Queue.tsx:89`, fed by `CommandScreen.tsx:46,110` | **yes** (main `Queue.tsx:89`, `CommandScreen.tsx:42,103`) | 16 toggles in 25 s |
| 5 | "Clear all orders" / "Clear the stopped order" | `Queue.tsx:112` | **yes** | 16 toggles in 25 s (2016→2223, 5004→5243 ms) |

These are the only components that read `s.busy`. The other hits in my search are Button's own `busy` prop, local per-press state in other components, and AppShell's in-flight guard.

**Fix for class A (one rule, applied once).** "A background world read never disables or restyles a control."
- Remove `busy` from every control's `disabled` at all 11 call sites above.
- Take the world-read flag out of what screens can read: rename it and keep it only for AppShell's in-flight guard (`AppShell.tsx:69,79`).
- Guard a press with its own pending state, as the other trays already do with `Button busy={sending}` (`Button.tsx:55-84`). Ideally that is one shared press hook, not eleven local copies.

**Class B: the served-read hook reports "loading" on every beat (code-proven, not observed in this run)**

`useServedRead.ts:124` returns `loading: stale || answer.beat !== beat`, so `loading` goes true on every 3-s re-ask. A refusal also clears `view` (`useServedRead.ts:111`). Callers that style on `loading`, or that read `loading && !view` as "first ask", therefore flip on every beat:

| # | What flips | file:line | On main? |
|---|---|---|---|
| 6 | The "tries left" figure dims on every beat | `HaggleThread.tsx:118` | yes |
| 7 | "No requests." ↔ "Loading…" when the request read was refused | `RequestBoard.tsx:51` | yes |
| 8 | "Max amount unknown" ↔ "Checking how much you can buy…" when the ceiling was refused | `TradeTray.tsx:344` | yes |
| 9 | "No storage / no inn / no workshop / does not build ships" ↔ "Loading…" | `PortStorage.tsx:105`, `PortInn.tsx:261`, `PortWorkstation.tsx:103`, `PortYard.tsx:95` | yes |
| 10 | The "Loading…" row pops in each beat when the basket preview was refused | `ManifestPanel.tsx:253` (`FulfilTray.tsx:112` is guarded by `!refusal`) | check |

In Lisbon and Porto every read answered, so none of these fired during the run. Each needs a refused read or an open bargain thread to show.

**Fix for class B (one line in the one authority).** Stop counting a beat re-ask as loading: return `loading: stale` at `useServedRead.ts:124`, and keep `WAITING` only before the first answer for a subject (`useServedRead.ts:120`). Every caller above becomes correct with no local patches. Also update the header comment at `useServedRead.ts:24` and the field comment at 57-58. `useTrade.ts:134` then counts only the first ask, which is what it means.

**Latent or not visible, for the record**
- **Route read failure:** a failed route read sets `routes` to null (`worldStore.ts:538-541`). The label then drops to "Route" (`RouteFold.tsx:69-75`) and "Loading…" shows (`RouteFold.tsx:97`). The route book is also re-read on the beat by two screens (`RouteFold.tsx:55-57`, `FleetsScreen.tsx:77-79`), next to the shell's own read. The class-B rule should cover this: keep the last book.
- **Map rows:** `WatersAhead.tsx:40` (also on main) keys each row on its distance, so the row remounts whenever the distance changes. There is no entrance animation, so nothing is visible. Key on `row.code`.
- **User-triggered blanks that bypass the hook:** `useStepOrder.ts:124-128` with `orderCheck.tsx:45-46` shows "Checking…" on every argument change. `useCrewCost.ts:63-85` with `PortInn.tsx:211` shows "Checking the wages…". Both are private copies of the hook's question rule, not beat blinks.
- **Checked and clean:** no random or timestamp keys, no Zustand selector returning a fresh object (`TopBar.tsx:50` returns a number), and `bv-fade-in` (`index.css:521-523`) is used by no component.

**The owner's first complaint ("Sell all / Buy all in one line")**
- **Route editor:** `RouteEditor.tsx:107-123` puts the "Sell all" Chip in the same `flex-wrap` row as every "Buy <good>" Chip, with the same component and shape. Stops after the first have no heading, because the port name is only inside the search field (`RouteEditor.tsx:96-103`). The screenshot showed Lisbon's chips and Porto's chips running together.
- **Running route:** each stop's caption is one joined string, "Sell all · Buy Iron, 20 units, Max 12 🪙 each" (`domain/route/index.ts:124-130`, drawn at `RouteFold.tsx:156`).

**One unexplained observation.** In the Chrome tab (hidden, with throttled timers), the first "Start route" presses logged no `cmd.standing_route_save` call and drew nothing. A later press saved and tried to assign. In headless Chromium the first press worked: saved, then assign refused with "Set how many days of supplies to keep first." I did not find the cause.

## Plan: stop face + one blink rule + partition

**Architect plan: route stop face and blink fix (origin/osn-trade-routes)**

Nothing was edited. The branch head is now `0534338`, not `0ab0d8b`. The only commit since then (0094) touches docs, SQL and `tests/db.chain.spec.ts`, so every `src/` line cited below is the same on both. The main clone's checkout was not changed, and bv-routes was not touched.

---

## 1. Route stop face

### 1.1 Problem, verified
- **Running route.** `src/domain/route/index.ts:124-141` `routeStopWords` joins every line with `' · '`. `RouteFold.tsx:149-158` then draws it as one faint caption (`:156`).
- **Words it drops.** SELL `qty`, the SELL floor `price_limit`, and `at_profit` are never printed. A BUY with `qty === null` prints no amount, although null means ALL (`types.ts:1463-1468`).
- **Editor.** `RouteEditor.tsx:107-124` puts the `Chip "Sell all"` and every `Chip "Buy {name}"` in one `flex flex-wrap gap-2` row, all in the same Chip skin (`Chip.tsx:45`).
- **Editor layout jump.** The Units and Max fields mount only after a buy chip is pressed (`RouteEditor.tsx:125-146`). That moves everything below, which breaks OWNER_REQUESTS row 15 (`docs/OWNER_REQUESTS.md:81`).
- **Queue.** Orders written by the route reach the player raw through `Queue.tsx:39-50` `humanize`, for example `Sell Iron ALL >= 12.5` and `Resupply DAYS 5`. The server writes these strings at `0092…sql:439-441, 450, 455, 463-465, 472`.

### 1.2 Shape: one skeleton with two callers (the ActCell precedent, `ActCell.tsx:5-11`)

Each stop is one block:

```
[anchor]  Lisbon                                      ← header Row (port)
Sell | [ship] Everything on board   All    Only sell above cost
     | [good] Pepper                20 units   Min 14 🪙 each
─────┼──────────────────────────────── (border-t border-edge)
Buy  | [good] Iron                  All that fit   Max 12 🪙 each
Resupply if low · Repair                                ← quiet caption line
```

**How sell and buy are told apart.** Colour is not used: green and red mean cheap/dear or gain/loss only (UI_DIRECTION §4.4; `deltaTone.ts:5-14`). Instead, the trade face's own means are reused:
1. **A side word, printed once per group, in a fixed left column.** It uses the ActCell/PriceCell label voice (`text-t-caption`, as at `ActCell.tsx:45`) in `text-ink-muted` and `w-10`. This is the same device as the `label="buy"` / `label="sell"` cells (`TradeRow.tsx:79-91`).
2. **Position.** Sell is always above Buy, which is the order the server runs them in (`0092…sql:421-466`).
3. **A hairline between the groups.** It is `border-t border-edge`, the Row hairline token. `ManifestPanel.tsx:225` already uses `border-b border-edge` inside features. There is no `bg-` in features, so the rule in `tests/duplication.spec.ts` holds.
4. **The limit's voice.** A buy caps (`Max`) and a sell floors (`Min`, or "Only sell above cost").
5. **Marks.** A named good wears its own mark, `goodIcon(code, category)` (`goodIcons.ts:160`, used as at `GoodsFace.tsx:70`). "Everything on board" wears `Icon 'ship'`. The header wears `'anchor'`, and the quiet line uses `'cask'` (supplies) and `'mallet'` (repair). All of these exist in `icons.ts:15-35`.

Each line is a `Row` (`Row.tsx:56-120`), `hairline={false}`, using the ReceiptFace/ManifestPanel pattern (`ReceiptFace.tsx:24-35`):
- `mark`: the good's mark.
- `label`: the good's name.
- `children`: a caption with the amount.
- `value`: `<Figure value={limitWords} tone="muted" />`.

No new tokens and no new colour.

### 1.3 Words: one authority in the domain (Domain B)

**`src/domain/order/text.ts`** (the grammar's home, beside `orderText` and `verbWord` at `:152-167`) gains:
- `tradeLineWords({ kind: 'SELL'|'BUY', qty: number|null, price_limit: number|null, at_profit: boolean }) → { side: 'Sell'|'Buy', amount: string, limit: string }`
  - `amount`: if `qty === null`, it is `'All'` for SELL and `'All that fit'` for BUY (the words already in the placeholder at `RouteEditor.tsx:131`). Otherwise it is `formatUnits(qty)`.
  - `limit` for BUY: `` `Max ${formatUnitPrice(p)}` `` or `'Any price'`.
  - `limit` for SELL: `at_profit ? 'Only sell above cost' : p !== null ? `Min ${formatUnitPrice(p)}` : 'Any price'`.
  - "Only sell above cost" is the mandated wording (`WORDS.md` row 51; `tests/words.spec.ts:79`).
- `queuedOrderWords(order: QueuedOrder, fleetName: string, portByCode, goodByCode) → string`. This replaces `Queue.tsx:39-50`.
  - It drops the fleet name and the TO/AT/VIA/ON tokens as before.
  - For `SELL|BUY <code> <n|ALL> [AT [>=] <p>]` it composes `tradeLineWords` into `Sell Iron · All · Min 13 🪙 each`.
  - `PROVISION DAYS n` becomes `` `${verbWord('PROVISION')} to ${formatVoyageDays(n, 0)}` `` (`time.ts:49`).
  - No raw `ALL`, `>=` or bare figure reaches the player (WORDS law 2).
- Both are exported from `src/domain/order/index.ts`.

**`src/domain/route/index.ts`**:
- Delete `routeStopWords` (`:124-141`); its only caller is `RouteFold.tsx:156`.
- Add `routeStopLines(stop, goodByCode) → { sell: StopLine[], buy: StopLine[], quiet: string }`, where `StopLine = { key: string, code: string|null, category: string|null, name: string } & ReturnType<typeof tradeLineWords>`.
  - `name` for `good === null` is `'Everything on board'`.
  - `quiet` is `'Resupply if low'`, plus `' · Repair'` when `stop.repair`. Resupply is fleet-wide and runs at every stop when below the 0034 keep level (`0092…sql:445-451`), and assign already refuses a fleet with no keep level (E_NO_KEEP, `RouteEditor.tsx:11-12`), so printing it on every stop is accurate.
  - Domain may compose domain (`tests/sections.spec.ts:124-132`).
  - Update the header's CONCEPT line (`:6-7`) from "one stop in a line" to "one stop as its sell and buy lines".

### 1.4 Components (Domain B)

**NEW `src/features/command/RouteStop.tsx`**. It is one file because both callers are in `features/command`.
- `RouteStopBlock({ header, sell, buy, quiet, last })`
  - Renders `<div data-testid="route-stop" className={last ? '' : 'border-b border-edge'}>`, then `{header}`, then `<SideGroup side="Sell">`, then `<SideGroup side="Buy" divided>`, then the quiet caption `<span className="block pb-2 text-t-caption text-ink-faint">`.
- `SideGroup({ side, divided, children })`
  - Renders `flex gap-3` with a `w-10 shrink-0 pt-3 text-t-caption text-ink-muted` side word and a `min-w-0 flex-1` body.
  - `divided` adds `border-t border-edge`.
  - Test ids: `route-stop-sell` / `route-stop-buy`.
- `StopLineRow({ line })`: the read Row described in 1.2, `data-testid="route-stop-line"`. An empty group draws one `Row label="Nothing" tone="muted" hairline={false}`, so the block's shape never depends on content.
- `RouteStopFace({ stop })`: the read-only composition over `routeStopLines`, with header `Row mark={<Icon name="anchor"…/>} label={portNameOf(portByCode, stop.port)} hairline={false}`.

**`RouteFold.tsx:149-158`** becomes `{route.stops.map((s, i) => <RouteStopFace key={s.ord} stop={s} last={i === route.stops.length - 1} />)}`. Drop the `routeStopWords` import (`:11`).

**`RouteEditor.tsx:92-151`**: each stop becomes a `RouteStopBlock`.
- **header**: the existing `Row` or `PortField` (`:96-104`), unchanged.
- **sell**:
  - `Chip on={stop.sellAll}` labelled **"Everything on board"**, with `Icon 'ship'`.
  - Then any `stop.kept` SELL lines and a non-default `sellAllFloor`, drawn read-only with `StopLineRow` through `tradeLineWords`.
  - Today these are carried silently (`standingRouteDraft.ts:34-41`); after this, nothing is hidden.
- **buy**:
  - The market chips (`:114-123`), each labelled with just `{g.name}` plus its `goodIcon`, because the group already says Buy. Keep `data-testid="route-buy-good"`.
  - Then kept BUY lines, read-only.
  - Then the Units / Max `Field` row, **always drawn** once a port is picked, `disabled={!stop.buyGood}`. `Field` passes `...rest` to its `<input>` (`Field.tsx:24-45`).
  - This removes the reflow on a chip press (row 15).
- **quiet**: `'Resupply if low'` (+ `' · Repair'` when `stop.repair`).

`standingRouteDraft.ts` does not change. The payload order at `:110-117` already matches the server.

**Word rows:**
- `docs/WORDS.md` vocabulary gains rows for `Min` (a price floor from the player; the mirror of the existing `Max` row), `Everything on board`, `All that fit` and `Any price`.
- `Min` is a new player word. It must go in the table, or the owner may pick another.
- `src/features/command/README.md:413` ("`Sell all`, and one BUY per stop") is reworded.

---

## 2. Blink fix: one rule per root-cause class

### Class A: the world-read flag used as a `disabled` gate (measured: 16 to 20 toggles per 30 s)

**Rule: a background world read never disables or restyles a control. Only the press itself does.**

**Authority 1: the store flag leaves the screens' reach.**
- In `worldStore.ts`, rename `busy` to `reading`:
  - `:158-159` (type, with a doc line: "AppShell's in-flight guard only; no screen reads it"),
  - `:343` (initial value),
  - `:418`, `:423`, `:433` (in `refresh`),
  - the comment at `:35`.
- `AppShell.tsx:69` and `:79` read `world.reading`. These are the only legitimate readers.

**Authority 2: NEW `src/live/usePress.ts`.** It is a pure React hook; `src/live/useSettled.ts` is the precedent for such a hook in live.

```ts
export function usePress(): { pending: boolean; run: (act: () => Promise<unknown>) => Promise<void> }
// run(): drops a press while one is pending; pending=true; await act(); finally pending=false (mounted-ref guarded)
```

- Create **one instance per group of controls acting on the same thing**:
  - the queue (every ✕ plus Clear),
  - the route fold (Start/Delete of a spare route, Clear, Pause/Resume, Delete),
  - the editor (Start/Save route).
- Consumers write `<Button busy={press.pending} onClick={() => void press.run(() => …)}>`. `Button busy` disables the button (`Button.tsx:64-84`).
- Why one gate per group, not per button: `cancel`/`clear` await `refresh()` (`worldStore.ts:698-716`), and CANCEL addresses by `seq` (`types.ts:808-809`). The queue-wide gate keeps the only protection the old flag gave by accident — no stale-seq ✕ while the queue is being re-read after a press — but only during a press, not on every beat.
- `Edit` buttons are synchronous (`setEditing`), so they just lose `disabled={busy}`.

**Call sites (all 11, plus the prop):**

| Site | Change |
|---|---|
| `RouteEditor.tsx:34` (selector), `:165` | `disabled={!complete \|\| !seaNav}` `busy={press.pending}` `busyLabel` optional; `onClick={() => void press.run(start)}` |
| `RouteFold.tsx:40` (selector) | delete |
| `RouteFold.tsx:110`, `:116` (spare Start/Delete) | `busy={press.pending}`; `act` (`:64-66`) runs through `press.run` |
| `RouteFold.tsx:113`, `:186` (Edit) | drop `disabled` |
| `RouteFold.tsx:133` (Clear), `:180` (Pause/Resume), `:189` (Delete) | `busy={press.pending}` via `press.run` |
| `CommandScreen.tsx:46`, `:110` | delete the selector and the prop. `onCancel` / `onClear` return the promises, e.g. `(seq) => cancel(fleet.id, seq)` instead of the `void` at `:112-113` |
| `Queue.tsx:19`, `:25` | drop the `busy` prop; type `onCancel: (seq) => Promise<boolean>` and `onClear: () => Promise<boolean>` |
| `Queue.tsx:89`, `:112` | `busy={press.pending}`, `onClick={() => void press.run(() => onCancel(order.seq))}` / `press.run(onClear)` |

- **Delete:** the store comment at `worldStore.ts:158` stops being needed as a warning, because the guard test enforces it.
- **Leave alone:** the existing per-press local states (`standingOrder.ts:78`, `HaggleThread.tsx:69`, `PortAcademy.tsx:43`, `SignTheBook.tsx:33`, `AuthPage.tsx:22`, `useSendFleet.ts:146`, and the `sending` states). They are correct and do not blink. I did not audit whether they can move onto `usePress`; that is a separate follow-up, not part of this change.

### Class A2: the routes read bypasses keep-the-last-answer (row 77's defect in store form)

**Rule: a store read that rides the beat keeps its last answer on failure.** This is already the convention for `loadOfficers` `:462-466`, `loadStandings` `:477-481`, `loadPresets` `:496-500` and `loadMarket` `:438-445`. `loadRoutes` is the one exception, and it has **one owner: `refresh()`**.

- **`worldStore.ts:421`**: add `worldStandingRoutes()` to the `Promise.all`. Set `routes: routes.ok ? routes.value : get().routes` at `:426-435`, and leave `routes` as it is on the fatal branch at `:423`. The file's own rationale for doing this is at `:419-420`: "a separate poll would be a second clock".
- **`worldStore.ts:538-541`** `loadRoutes`: `if (r.ok) set({ routes: r.value })`. Delete the comment at `:535-537`, which justifies the blank.
- **`worldStore.ts:574`, `:585`**: `await get().refresh()` alone. Keep `saveRoute` `:550` and `deleteRoute` `:561` calling `loadRoutes()`, because only the book moves.
- **Comments:** update `worldStore.ts:144-146` and `:198-200` (the doc comments on `routes` and `loadRoutes`).
- **Delete the two beat loaders:**
  - `RouteFold.tsx:53-57`, plus selectors `:36-37` if unused afterwards;
  - `FleetsScreen.tsx:75-79`, keeping `:74`.
- **After this,** `RouteFold`'s `'Route'` label (`:69-70`) and "Loading…" (`:96-97`) show only before the first read.
- **Cost trade-off:** one routes read per beat on every tab, instead of one or two per beat on COMMAND/FLEETS only. The read is light and the flag is dark-first.

### Class B: `useServedRead` reports `loading` on every beat (proven from the code; not observed live)

**Rule: a re-ask on the world's beat is not loading. Only a first ask for a subject, or a new question, is.**
- **One line, `useServedRead.ts:124`**: `return { view: answer.view, loading: stale, stale }`. `WAITING` (`:67`, `:120`) still covers the first ask.
- **Comments:** update the header at `:22-24` (so a caller's `loading && !view` really does mean "first ask") and the field doc at `:57-58`.
- **Call sites corrected with no edits:**
  - `HaggleThread.tsx:118`
  - `RequestBoard.tsx:51`, via `useRequests` (`PortPrices.tsx:66,78`; `PortTrade.tsx:118,196`)
  - `TradeTray.tsx:344`, via `useBuyCapacity.ts:69`
  - `PortStorage.tsx:105`
  - `PortInn.tsx:261`
  - `PortWorkstation.tsx:103`
  - `PortYard.tsx:95`
  - `ManifestPanel.tsx:253`
  - `FulfilTray.tsx:112` (already guarded)
  - `useTrade.ts:134` keeps its meaning.
- **Comment-only:** the `TradeTray.tsx:325-329` note describes `capacity.loading` on the beat; reword it.

### Latent, same sweep
- `WatersAhead.tsx:40`: change the key `${row.code}-${row.figure}` to `row.code`. Verify first that `watersView` rows have unique codes.
- **Out of scope, stated so it is not lost:** `useCrewCost.ts:63-85` (with `PortInn.tsx:211`) and `useStepOrder.ts:124-128` are private copies of the question rule. They blank on an argument change, not on the beat.

---

## 3. Partition (disjoint file sets)

Each domain uses its own worktree off `origin/osn-trade-routes`, never bv-routes. Push to `osn-trade-routes-blink` (A) and `osn-trade-routes-stopface` (B); the orchestrator merges both into the PR branch so nothing races the driving agent. Each `vite preview` gets an explicit port, via `localhost`.

**Order:**
1. **A0.** A commits `src/live/usePress.ts` first (about 20 lines) and pushes; B imports it.
2. **A1 and B in parallel.**
3. **A2 last, after B merges.** It covers the rename `busy` → `reading`, AppShell, and the guard test. The rename fails to compile while B's files still select `s.busy`.

### Domain A: blink (shared rules and the non-COMMAND sites)
1. `src/live/usePress.ts`: NEW (A0).
2. `src/live/useServedRead.ts`: `:124`, `:22-24`, `:57-58` (A1).
3. `src/live/worldStore.ts` (A1):
   - routes read inside `refresh` with keep-last; `:535-541`; `:574`; `:585`;
   - comments `:144-146` and `:198-200`.
   - (A2): rename to `reading` at `:35`, `:158-159`, `:343`, `:418`, `:423`, `:433`.
4. `src/app/AppShell.tsx`: `:69`, `:79` (A2).
5. `src/features/fleets/FleetsScreen.tsx`: delete `:75-79` (A1).
6. `src/components/ui/TradeTray.tsx`: comment `:325-329` only (A1).
7. `src/features/map/WatersAhead.tsx`: `:40` key (A1).
8. `tests/flicker.spec.ts`: NEW (A2).
   - **Static guards, in the fs-reading style of `tests/sections.spec.ts:55-77`:**
     - `reading` is read only in `src/app/AppShell.tsx` and `src/live/worldStore.ts`;
     - no `s.busy` store selector anywhere in `src`;
     - `loadRoutes(` is called only inside `src/live/worldStore.ts`.
   - **Browser proof, modelled on `tests/trade.ceiling.spec.ts` (which watches across three world reads):**
     - a MutationObserver counts `disabled` flips on `queue-clear` and the ✕ buttons across three or more reads; the expected count is 0;
     - add `route-start` too, if the browser database can switch `standing_routes_enabled` on. The node seam is `tests/rpc.surface.spec.ts:1620`. A browser seam is unverified, so check it, and if there is none, prove on the queue only.
9. `docs/OWNER_REQUESTS.md` (new row for the 2026-09-30 request) and `docs/DEV_LOG.md`. A writes both; B sends its paragraph to A.

### Domain B: stop face (plus the class-A rule applied inside COMMAND files it owns)
1. `src/domain/order/text.ts`: `tradeLineWords`, `queuedOrderWords`.
2. `src/domain/order/index.ts`: exports.
3. `src/domain/route/index.ts`: delete `routeStopWords` `:124-141`; add `routeStopLines`; header `:6-7`.
4. `src/features/command/RouteStop.tsx`: NEW.
5. `src/features/command/RouteFold.tsx`: face at `:149-158` and import `:11`.
6. `src/features/command/RouteEditor.tsx`: groups and always-drawn fields `:92-151`.
7. `src/features/command/Queue.tsx`: `humanize` `:39-50` becomes `queuedOrderWords`.
8. `src/features/command/CommandScreen.tsx`
9. `src/features/command/README.md`: `:413`.
10. `docs/WORDS.md`: vocabulary rows.
11. Optional: `tests/layout.spec.ts`.
    - A new case at 390×844 checking that `route-stop-sell` and `route-stop-buy` are separate boxes, sell above buy.
    - It also checks that pressing a `route-buy-good` chip moves no element below it (row 15).
    - It needs the same routes-enabled seam as item A8.

**What B does in files it owns on behalf of A (the class-A rule, from the table in §2):**
- `RouteFold.tsx`: delete `:40`, and `:36-37` plus `:53-57` (A1 makes refresh the only routes reader). Apply `usePress` at `:110`, `:116`, `:133`, `:180`, `:189`. Drop `disabled` at `:113`, `:186`.
- `RouteEditor.tsx`: delete `:34`; `usePress` at `:165`.
- `CommandScreen.tsx`: delete `:46` and the prop at `:110`; `onCancel`/`onClear` return promises (`:112-113`).
- `Queue.tsx`: drop prop `:19`, `:25`; queue-wide `usePress` at `:89`, `:112`.

**What A does that B relies on:** `usePress` (A0); `refresh()` becoming the only routes reader, with keep-last (A1); and the rename, which only lands after B has removed every `s.busy` read.

### Checks before claiming done
- `tsc --noEmit` and the project build.
- `tests/words.spec.ts` (the new literals and the queue words), `tests/sections.spec.ts`, `tests/duplication.spec.ts`, `tests/layout.spec.ts` (fold geometry `:631-678`), `tests/wide.layout.spec.ts:350-368`, `tests/trade.ceiling.spec.ts`, and the new `tests/flicker.spec.ts`.
- A live drive repeating the sweep method: a MutationObserver over 30 s on COMMAND with routes on in the local database. Expect 0 toggles on Start route, the fold's buttons, ✕ and Clear.

### Open items (not verified)
- **Rounded floors.** `formatUnitPrice` rounds through `formatInt` (`numbers.ts:25-30`). A fractional floor (the cost basis rounded up to 2 dp, `0092…sql:441`) will print as a whole number, as `avg_price` already does on the receipt (`ReceiptFace.tsx:32`). Keeping that convention is a choice, not a bug fix.
- **`Min` is a new player word** and needs a WORDS.md row (see §1.4).
- **The first Start press in the hidden, throttled Chrome tab did nothing.** A likely cause is a click landing while the world-read flag held the button disabled, since a throttled tab lengthens each read. This is not proven; check again after class A lands.