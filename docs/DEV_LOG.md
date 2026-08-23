# byeharu-voyage — Dev Log

Running record of **requests**, **decisions**, **work done**, **bugs**, and **fixes**.
Newest entries at the top. Dates are absolute (YYYY-MM-DD).

---

## 2026-08-23 — D21: the OSN question, answered NO — and the one seam that was actually missing

Owner: *"this game might need OSN system as well as other system built in byeharu, the previous game.
audit and implement it so that later on, combat, exploration, npcs can be added."* Architecture, not a
feature. **`docs/PLATFORM.md` is the deliverable; migration 0035 is the whole of the code.**

### THE AUDIT SAYS NO TO OSN, AND THE REASON INVERTS THE PREMISE

`dev/byeharu` was read end to end. Five findings, any one of which settles it:

1. **It was built, gated, never lit, and then deleted.** The per-ship coordinate stack (byeharu
   0055–0070) ended as `20260618000232` dropping **20 functions**, plus a table, three columns and six
   CHECKs — and `0231:245-250` refuses to run unless both coordinate flags are FALSE, which they were.
   A whole subsystem authored, proved, deployed dark, demolished, with no player ever using it.
2. **Free coordinates are where combat CANNOT reach.** `combat_encounters.presence_id` is
   `not null references location_presence` (`20260616000014:14`), and the space-arrival branch creates
   no presence — *"open space has no location"* (`0208:163-166`). A fleet at a free coordinate cannot
   be ambushed, cannot hunt, cannot explore. Importing OSN to make room for those would remove the room.
3. **It produced four movement systems** (`MOVEMENT_UNIFICATION_CHARTER.md:488-500`) and cost four
   ships stuck at `traveling` with nothing behind them, five teleported to wrong ports, a global cron
   wedge, a ghost-dock where *"the fleet flew while its ships stayed docked"*, and a player's fleet lost
   because the brake refused. *"Is this fleet docked?"* reached **eleven hand-copied definitions**.
4. **Voyage cannot enforce a free coordinate.** The coastline is a build-time raster in
   `scripts/sea-grid.mjs`; nothing at runtime knows where land is, so an arbitrary lat/lon sails through
   Africa. The 782 legs *are* the coastline.
5. **It contradicts Law 3** (the map never accepts input) and the composed-not-typed order language.

And byeharu's own `ARCHITECTURE.md:24-30`, written before its first migration: *"Do not build
free-moving ships that chase/fight from live positions… build the game around location presence."*
`CORE_REUSE.md:1168` already recorded the verdict — *"Byeharu spent 2026 walking away from that rule
(OSN, free coordinate travel, spatial combat) and byeharu-voyage is walking back to it."*

**What voyage should take from OSN it already has, and better:** OSN §12's core rule is ONE
authoritative spatial state. Voyage enforces it with a partial unique index *and*
`voyage.assert_sailing_invariant`, and its position is closed-form over a multi-leg frozen speed
profile where byeharu's was one straight segment at one speed.

### THE SPATIAL PRIMITIVE IS THE LEG. ZONES ARE REJECTED.

A leg already *is* what a byeharu `danger_zone` was — a continuous exposure surface with its own risk
multiplier, bounded by two places — with no polygon, no PostGIS, no overlap policy and no hit test,
because a voyage's path is a list of legs by construction. The zone platform's own reviewer is quoted
against it in PLATFORM.md §2. `voyage.position`'s lat/lon stays display-only; its comment says so and
that fence holds.

### WHAT WAS ACTUALLY MISSING — three seams, ranked, and only the first is built

Voyage's loop is `Map → Port → Voyage → Arrival → Activity → Report`. Four links are good. **ACTIVITY is
the missing one**, and combat, exploration and NPCs are all activities.

1. **What can happen at sea was stated in THREE functions** — `hazard_roll`'s CASE, `settle`'s arms, and
   `report_line`'s CASE whose `else` printed the raw schema code at the player. Adding a kind and
   forgetting the third did not fail; it shipped `Day 7. DERELICT`. **This is 0035.**
2. **An event has no SUBJECT**, so a raid happens *with the sea* — `piracy_index × 40 × (0.5+mag)`, an
   opponent you can never meet twice. NOT BUILT: a column with no reader is byeharu's own recorded
   failure class, four items long.
3. **One event per voyage-day, and only on a voyage** — `primary key (voyage_id, day_index)`. NOT BUILT:
   that PK is what makes offline settlement byte-identical, and widening it belongs to the slice that
   first needs a second beat, so the determinism proof is written against a real case.

Shapes for 2, 3 and five more are written down in PLATFORM.md §6 so nobody re-derives them.

### 0035 — `public.voyage_event_kinds`

One table, two superseded functions, `voyage.settle` **untouched**, the hazard *probability* untouched.
`voyage_events.kind` becomes a **foreign key** into the catalogue, which is why settle needs no change:
it cannot invent a kind. `report_line`'s code-printing fallback is deleted in favour of a raise
(NO_SPAGHETTI §7C). 0027's burial sentence was generalised from `kind = 'PIRATES'` to *the payload
carries `crew_lost`* — byte-identical today (0027:388-390 is the sole writer) and free for whatever
costs crew next.

**Adding a thing that happens at sea is now one INSERT** plus, only if it does something new to the
ships, one arm in a superseding `settle`.

Proven, not asserted: the draw agrees with 0006's CASE on **50,000** (r_kind, piracy) pairs including
9,600 that cede a storm to raiders; on a real 7,071 nm haul out of Lisboa with every sea and leg at the
worst the schema holds, all **18** occurring days across 2 kinds answered exactly as the CASE would; all
**11** after-action lines are byte-identical including both fallbacks and all four branches of the
surgeon clause; and both guards were shown biting on real rejected writes. **Nine asserts, all nine
break-tested red first** — including one break that tripped the weight-closure trigger *before* the
sweep it was aimed at, which is the trigger proving itself.

**A measurement worth keeping:** `voyage.leg_at_day` called inline in a `WHERE` clause raises
`E_NO_SUCH_VOYAGE` for a voyage the very next statement can count (PGlite 0.5.5, measured). Hoist it into
a variable — which is exactly what `hazard_roll` itself does at `0006:673-675`. The house pattern was
already right; the probe had wandered off it.

---

## 2026-08-23 — D20: plain words everywhere, goods become blocks, and the useless button dies

Three owner instructions in one sweep: **"overall, check game itself - every aspect, and move simple
words"**, **"make trade goods in blocks as well, not all alligned in sentences - horizontally"**, and
**"read again on top left of the game is useless. remove it."**

### THE `read again` CONTROL IS DELETED, NOT HIDDEN

AppShell already reads the world every thirty seconds and on every tab focus, and `world.fleets()` is
the catch-up — a button asking for something already happening taught the player their tap did nothing.
Removed from MARKET, FLEETS, LEDGER, RANK and the COMPENDIUM (COMMAND holds its own local copy, another
slice's). **The reads the button carried did not die with it**: each screen's extra read (MARKET's
prices, RANK's board, the COMPENDIUM's roster) is now keyed on `readAt`, the world-read's own stamp, so
it re-asks on the same thirty-second beat — which also means a refused board/roster read retries itself,
and MARKET's prices step the drift walk (0029) while the tab is open. The two "read again to try once
more" sentences those retries orphaned are reworded. `live/WorldGate.tsx`'s `ReadAgain` now has **zero
callers** — deleting it belongs to whoever owns `src/live`, which this slice does not.

### TRADE GOODS ARE TILES (`src/components/ui/GoodTile.tsx`)

The market table read each good as a sentence — name, index, price, strung horizontally, with trend and
destination behind a sideways swipe. It is now a two-column field of blocks: the good's own drawn mark
and name as the title, its rarity mark, and the figures labelled beneath (nearby index + trend line,
buy · sell, stock, pays at). The COMPENDIUM's goods face composes the same tile with its own figures
(base, bulk, spoils, refused by), grouped under kind headings instead of spending a column on the
category. **The tile's home is the design system** — `GoodTile.tsx` + `goodTileLayout.ts` — with
COMMAND's good picker as the named next caller (docs/NO_SPAGHETTI.md §7's seam list). Sort orders are
unchanged; `tests/layout.spec.ts`'s MARKET fold proof now counts complete tiles.

### THE WORD SWEEP (one word per idea, no schema on screen)

`%NBR` → **nearby** (COMMAND's own earlier pick, now MARKET's sort chip and how-to card, and PORT's
buy notes — "of neighbours" was a third name); `Yard` → **Shipyard** (0033's word, last client
holdout); `watered and victualled` → **provisioned**; `Presets` → **Standing orders** (with `Order N`
as the default name); `flag:` → **flagship:**; Profile's raw `ready` phase → **open**, `Sea legs` →
**Sea lanes**; Map's `asking the server…` → **checking the passage…**; `pool 35` → **35 at the inn**;
bare culture values get their noun (`latin culture`); `shipyard t2` → **shipyard tier 2**. Also:
REPAIRED's ledger badge was the same red as REPAIRING — a recovery coloured as a wound — and is green
now, and PortFaces' officer bonus now prints through `formatPctPoints` like the compendium's.

---

## 2026-08-23 — D19: the map stops being a picture

Owner, on the Map tab's caption: it *"literally reads `view only · orders on Command` — that sentence is
the screen confessing it is unfinished."* You could see the whole world, your fleet lying in Lisbon and
214 harbours around her, and act from none of them: remember the name, leave the tab, find it in a list.

**The caption is deleted, with the behaviour it described.** Tapping a harbour now offers `Sail here`.

### THE SEAM: THERE WAS ALREADY ONE, AND IT GOT A FOURTH CALLER

`tests/sections.spec.ts` forbids a screen importing a screen, so the map cannot reach into COMMAND. The
honest mechanism is a hand-off — and this repo has exactly one: `domain/order`'s draft, written by FLEETS,
PORT and MARKET as `handOff(intent)` then `navigate('/command')`. **Nothing new was built to carry an
order off the Map tab.** Three alternatives were considered and rejected, each for the same reason — each
would be a second place a pending order lives:

| rejected | why |
|---|---|
| a field on `live/worldStore` | two drafts. The store is the WORLD; it is not the order being made |
| router state (`navigate('/command', { state })`) | invisible to the draft's `sessionStorage`, so a reload loses an order the composer would otherwise still hold |
| a search param (`?verb=SAIL&dest=CAD`) | the URL becomes a second authority for the draft **and** needs parsing on arrival — a second parser, in a game whose whole point is that there is one |

**And "which hull is this order for" got no new answer either.** `domain/order`'s draft already owns it
app-wide. The map READS it, and selecting a fleet on the chart or in the list WRITES it — so the harbour
you tap next sails the ship you just pointed at, and COMMAND opens on her. A `useState` here would have
been a fourth screen with a private answer to one question, which is how *"where does her next order
happen"* reached four spellings (`domain/fleet/derive.ts:76`).

### THE MAP DOES NOT JUDGE, AND CANNOT RECOMMEND WHAT `cmd.issue` WOULD REFUSE

`voyage.sail_refusal` is THE answer to "may she sail there?" and it is revoked from every client role
(`0019:461`), so the only honest way to ask it from a browser is to run the verb and throw it away —
`cmd.preview()`. The `args` the map previews and the `args` it hands over are **the same object**, walked
through the same `orderText` COMMAND will walk, so the line the server judged and the line it is later
asked to run are equal by construction rather than by agreement.

Measured in the running game at 390×844, local PGlite chain, a freshly founded house:

| tapped | what the panel said |
|---|---|
| **Cádiz** | `Sail Gaivota here` · **248 nm · 2.1 days** — the SAILED distance round Cape St Vincent, not the 188 nm straight line |
| **Las Palmas** | `Sail Gaivota here` · 808 nm · 6.8 days |
| **Alexandria** | `Sail Gaivota here`, and under it `E_ENDURANCE` — *"Gaivota carries 15.0 days of stores and that route is 19.9 voyage-days; you need 22.9 — PROVISION first"* |
| **Cádiz, with her at sea and bound there** | *"She is at sea — this would wait in her queue."* |
| **Lisbon, with her alongside** | *"Gaivota lies here."* and no button |

**The refused button is not disabled**, which is the rule the haggle block already keeps (`README` §10.1):
tapping it hands over anyway, and COMMAND renders the refusal's *fixes* as tappable orders. Driven: the
Alexandria tap landed on COMMAND carrying `SAIL Gaivota TO ALE` with `PROVISION Gaivota FULL` offered
beside it and *Issue this order* correctly dead. **The map states the reason; COMMAND offers the remedy.**

### THE LOOP, COMPLETED

Tap Cádiz → `Sail Gaivota here` → COMMAND opens on `SAIL Gaivota TO CAD` → *Issue this order* → `sent:
SAIL Gaivota TO CAD` → Gaivota `SAILING`, *at sea → Cadiz, 0 nm of 248 nm, arrives in 6m* → back on the
chart, her dotted track out of Lisbon with Cádiz ringed. No pageerror, no console.error,
`scrollWidth === clientWidth === 390`. Repeated at 1440×900.

### A DEFECT THE DRIVE CAUGHT, WHICH NO TYPE COULD

The first draft asked `fleetPortCode(fleet)` whether she was already at the tapped port. That function
answers a **different question** — *"where does her next ORDER happen"*, `fleet.port ?? fleet.voyage.to` —
so with Gaivota three minutes out of Lisbon on a Cádiz passage, tapping Cádiz printed **"Gaivota lies
here."** She was 248 nm away. It is now `fleet.port === portCode`, one served field, and the comment above
it says why the other one is wrong. One field, two questions, and the wrong one was true-looking enough
to ship.

### TWO DUPLICATIONS FOLDED, BECAUSE THIS SLICE WOULD OTHERWISE HAVE BEEN THE THIRD COPY

`docs/NO_SPAGHETTI.md` §2 listed `num`/`str` — *"read a field out of a jsonb payload safely"* — as open
debt in two places that **had already drifted**: LEDGER's `num` tolerated a numeric arriving as a string
and COMMAND's did not. The map needed to read `cmd.preview`'s estimate, which is §1's *"found a third time
→ stop the feature and fold it, the same turn."* So:

* **`src/lib/json.ts`** — `num` and `str`, the STRONGER version of each (§6: never weaken to green).
  PreviewPanel's and LedgerScreen's copies deleted; neither screen's behaviour changes.
* **`src/domain/order/estimate.ts`** — `sailEstimate()`, the one READING of `total_nm` / `voyage_days`.
  COMMAND draws the full readout, MAP prints the passage in a corner panel; the chrome differs, the keys
  have one owner. **Only SAIL** — the other verbs' estimates have one reader each, and folding something
  that is not duplicated is inventing a home rather than finding one.

### SMALLER, AND DELIBERATE

* **`fit` → `find`.** One tap, always on the glass, frames what the house HAS. The behaviour is unchanged;
  `fit` is a chart programmer's word for the thing a player calls *"where is my ship"*, and the owner's
  standing map rule is no insider jargon.
* **The FLEETS chip stays folded on a phone, and that is the right call.** Measured when the rule was
  written: open at 390×844 it filled y 0–505 of 844 — 60% of the chart, from a component whose whole brief
  is "corner panel". Folded it is a 44px chip in the corner, one tap opens it, and the fold is remembered
  per player. Desktop is unchanged (open). It is also not the only way to find her — `find` is one tap and
  never folds.
* **The port panel is wider than the fleet panel on a phone** (`74vw` against the compact default's `55vw`).
  A refusal is a SENTENCE, and a 214px column turns a readable reason into a tower that pushes the button
  up the glass. The chart clips at its own edge, so panel height is what must stay bounded, and width is
  what buys it back.
* **The action is in the CORNER PANEL, never on the marker.** A chart pans; an action drawn at a map
  coordinate can be panned off the screen. That is the reach law arrived at by a different route, and it
  is now written into `components/ui/overlayLayout.ts`, whose header used to ban command buttons on
  overlays outright.
* **`keepOut={surface.chromeBoxes}`** wired through to `ChartCanvas` — the chart side's fix for names
  printed under this screen's opaque chrome (`Saint-Malo` as `Sain`, `Nantes` as a bare `s`). The port
  card the new flow opens is a `MapPanel` and carries the `CHART_CHROME` marker already, so it is covered
  by the same one line.

### WHAT THE SERVER WOULD HAVE TO SERVE NEXT

Two things the map wants and cannot honestly have. Both are named here rather than computed on the client:

1. **"Every port she can reach right now, and the reason for each one she cannot."** One preview per tap
   answers one harbour; painting the whole sheet reachable/not would be 214 round trips, or a client copy
   of `voyage.sail_refusal`. The shape wanted is one read — `world.reachable(fleet)` → `[{port_id, nm,
   voyage_days, refusal_code, refusal_sentence}]` — over the same `voyage.reach_from` + `voyage.sail_refusal`
   pair `world.trade_routes` already composes (0019). **That is a migration, and it is not this slice's.**
2. **"Read this harbour's market" from the map.** The READ exists (`world.market`); the *seam* does not.
   Which port a screen is LOOKING at is component-local in MARKET and `sessionStorage` in PORT, and
   `MarketScreen.tsx:113-122` already names the fix as promoting that into a section of its own. Building
   it means touching two screens this slice may not, so the map offers no "read the market here" button —
   an honest absence beats a button that lands on Lisbon.

---

## 2026-08-23 — D18: seventy marks, a row that unfolds, and a fair that happens whether or not you look

Owner: *"make icon for each trade good, do all the things that i asked before, and then do 8, 9, 10"* —
and, when asked what 내 주방 meant: **the galley, as its own tab beside the cargo.**

Six background agents across three waves, partitioned by disjoint file domains. Four migrations
(0025–0028), three new screens' worth of client, and one architectural carve-out that had been
correctly refused the day before.

### SEVENTY GOODS, SEVENTY MARKS

The picker drew seven category glyphs across seventy rows, which is an icon column carrying no
information: the reader still had to read every name. Now every good in `data/goods.json` has its
own drawn mark.

**The hard part was never drawing seventy pictures — it was drawing seventy that are still tellable
apart at the 22px the picker renders them at.** Nine were redrawn after the first contact sheet:
ginseng read as a standing human figure, furs was indistinguishable from musk, horses was a smudge
as a head profile (a horseshoe now), whale oil collided with tea, raw silk with cinnamon, ivory with
tobacco.

**And the honest limit is written down rather than smoothed over.** Nothing shares a mark, but six
pairs still need the name beside them: ivory/tea, nutmeg/cacao, silk cloth/muslin, musk/furs,
cinnamon/raw silk, and the three bowls (rice, gums, whale oil). The icon is an accelerator, never a
replacement for the name — which is why the unfolding row keeps both.

The old override table was **partly dead**: `pitch` was not a good id (the good is `tar`), and four
"overrides" pointed at their own category glyph. Both classes gone.

### THE ROW THAT UNFOLDS — asked for twice before it was built

Tapping a good opens it in place. The pick happens only on the fold's own `Choose <good>` button.

    ◔ Porcelain              BUY ⌄        HOW MUCH SHE CAN TAKE
      luxury                              20 t at most
      BUY 358 · SELL 328 · NEARBY 82%     stopped by       your purse
      STOCK ████████████████              all of it costs  7,179 d.

**Cost measured, not reasoned**: opening a row is exactly 2 RPCs; opening a second is 2 (the first
closes, nothing leaks); closing is 0; `trade_routes` is 0 per row, fetched once per (port, fleet).
Opening does not commit — proven in the browser: the argument still says *not chosen yet*.

`neighbours` was truncating to `NEIGHBOUR…` in a 96px cell. A label clipped by its own cell is a
label that has stopped working; it reads `NEARBY` now. Not `%NBR` — that is the column name in
migration 0009, and the player never reads the schema.

### THE BOARD, AND WHAT A ROW MAY CARRY

**The blocking question was not how to rank — it was what a board row may say.** A name, a nation, a
standing, and the fames the standing is computed from. Nothing else.

DESIGN J.1 makes the order book the only PvP surface, so another house's purse and the harbour her
fleet lies in are not colour — they say what she can afford to corner and where to be waiting.
Enforced by the server refusing to hand it over: `public.standings` carries RLS with **no policy and
no grant to any client role**. The break-test: adding a purse to a row →
*"another house's purse of 131,457 d. was reachable through the board."*

Ties are `rank()`, not `row_number()` (which invents an order out of heap order) and not
`dense_rank()` (which hides how many are level). Two houses level are **both 1st and the third is
3rd**, `=2` on every tied row so the missing number does not read as a bug.

The board is a RECORD keyed like `price_history`, and **the read is the catch-up** — no cron
dependency, because PGlite has no pg_cron.

### THE FAIR, AND WHERE A TIMED MODIFIER MAY HONESTLY LAND

Decided by elimination, and the rejection is the load-bearing part:

* **Speed — rejected.** `voyage.depart` FREEZES speed into `voyages.speed_profile` (0006:62). A
  weather buff wired to speed would be summed into a stored total the moment a fleet sailed, and
  that freeze is what makes offline settlement byte-identical (proof 01).
* **The daily cap — rejected here on purpose**, because ACCOUNTING lands there in 0027 and two new
  terms in one function on one day is how a composition goes unproven.
* **The port's cut — taken.** `world.spread_effective` (0022) is untouched: it calls `world.spread`
  as its first line, so purser, bargain, floor and cap keep composing exactly as proven.

The calendar is **data, not code** — magnitude, duration, season length and chance all live on the
authored kind row. A `festival_*` knob would have been a second authority.

### THE THREE THAT DID NOTHING

* **SURGEON** — and the agent's own assert caught its own first draft. Shaving the surgeon off the
  loss *fraction* rounds away entirely on a starter Barca: `floor(8 × 0.721) = floor(8 × 0.70) = 5`.
  It works on **hands**. Proved on a real raid, then replayed on the identical roll with a surgeon
  aboard: 8 → 6 where nobody had left 5, and *"We buried 3 of the hands"* became *"We buried 2; the
  surgeon kept the rest."*
* **ACCOUNTING** — multiplies the allowance, never the tally already spent.
* **NAVIGATION — the trap, and it did not get deferred a fourth time.** 0016 deferred it to weather;
  0026 closed that escape hatch by establishing a timed modifier cannot reach frozen speed. So it
  composes THROUGH `voyage.fleet_speed` rather than beside it. Not double-counting, by four
  measurements — and breaking `(1+nav)*(1+skill)` to the sum form made the migration go red.

### A FAIR HAPPENS BECAUSE THE GAME IS PLAYED

`world.buffs()` was the only thing drawing a fair anywhere in the world, and PORT was its only
caller. **A world rule that depends on a screen being looked at is not a world rule.**

`world.snapshot()` was the obvious home and was **the wrong one, measured**: the client calls it
once per session and caches it hard, so winding there moves the bug from "a tab was opened" to "the
app was launched". It is also `STABLE`, so Postgres refuses a write inside it. The winder went into
`world.fleets()` — the 30-second read, already 0009's catch-up read.

    world.fleets()   1.455 ms → 1.695 ms   (+0.240 ms, +16.5%)

Three runs agreed within 0.04 ms. One writer still: 1 function writes `active_buffs`, 3 read it,
`tick_buff_calendar` has exactly 2 callers and the migration names them.

**The break-testing found a real weakness and the guard was fixed, not the test.** The first
idempotence assert compared row COUNTS — and a writer that clears its season and re-draws it leaves
the same number of fairs. It digests the row **ids** now, and that term is what fired.

### TWO CLOCKS, ONE WORD

`duration_game_days` rides the calendar clock (2,880 s/day); the wire carried only
`time_compression` (the voyage clock, 180 s/day). A client printing "lasts 3 days" would have been
**wrong by ×16** — which is why the agent that built the PORT panel printed none of them and wrote
down why instead of guessing.

They are genuinely two clocks and were not collapsed: at one rate either a passage costs an hour per
sea-day or a game year passes in an afternoon. **The defect is the wire, not the model.** The seam is
asserted end to end, with the ×16 as the negative control computed from the two served knobs.

### THE CHART, AND THE BOUNDARY THAT WAS PRODUCING COPIES

A small map on SAIL needed 9 of the 14 files in `features/map/`, and no screen may import another.
The previous agent **refused to copy and refused to weaken the guard**, and wrote the problem up
instead. That was right: `sections.spec.ts` was green the whole time `PortPicker` existed twice.

`src/chart/` is now a layer between domain and features, with one entrance. Three new guards,
each broken on purpose and watched fail:

> *"A layer nobody can reach through the entrance is a layer the next screen copies a file out of,
> which is the silent copy no import check can see."*

**No line is drawn between the two ports** — deliberately, and written into the code. A straight line
would be read as the distance, and straight-line distance is the defect that once showed Seville at
169 nm against the server's 286 *and sorted the list by it*. Distances stay on the row, from the
server: Setúbal 16, Porto 195, Cádiz 248, Seville 286.

### THE GALLEY

내 주방 — the fleet card is three faces now: **SHIPS · CARGO · GALLEY**. Water, food, range, hands,
hold and the daily burn were one run-on mono paragraph that wrapped to four lines at 390px; they are
six labelled rows. The heading came off (the tab already says GALLEY), and the disclosure it carried
moved DOWN onto the `hold` row — the row it is actually about. A dot floating alone above a grid,
attached to nothing, is not better than a heading.

### FOUR THINGS FOUND AND SAID RATHER THAN PATCHED

1. **`RankScreen` printed `PRT`** on the one screen whose job is telling houses apart. The agent
   REFUSED to write a client-side code→name table and reported it — which is why there is one
   authority (`nationNameOf`, beside `portNameOf`) instead of a seventh copy. 0028 serves
   `snapshot.nations`; a `nation_name` on the row was rejected because `snapshot.ports[].nation`
   would still be unresolvable and the wire would carry three spellings.
2. **`db.chain.spec.ts:268` was already RED on a correct chain** — pinned to 0024's literal title
   while `LAST` had moved. A guard red on a correct chain gates nothing.
3. **`rpc.surface.spec.ts` was missing `worldBuffs` and `worldStandings`.** 0022 shipped a complete
   server mechanic with no client at all for exactly this reason.
4. **`layout.spec.ts`'s TABS list never included `rank`** — the only tab with a scrolling table the
   390px guard did not measure. Added; 7 pass. `map` and `profile` stay out, and the reason is
   written in rather than left to be rediscovered.

### Gate

`db:check-versions` 28, positive control fired · `db:apply` **28/28 receipts** · `db:proof` **45/45**
markers across 6 files, run four times · `playwright` **162 passed** · tsc, eslint, build clean.

`BALANCE_MEDIAN_IN_BAND` was green on all four proof runs (13.6 / 13.2 / 11.6 / 14.2). It went red
once mid-session and was **measured rather than re-rolled**: six runs on the new chain gave
13.1/12.5/13.8/13.5/12.2/10.3 against six on the unchanged chain at 15.1/9.0/12.4/14.4/12.4/12.1.
The unchanged chain has the WIDER spread. Pre-existing non-determinism in proof 05, already
documented in 0021's header — a flake on the safety net, and worth its own slice.

**Still open:** proof 04 now winds the calendar (0026's "the proofs run in a fair-free world" is half
false, and 0028's header says so). A fair only makes a trade cheaper, so it can only help
`FIRST_SESSION_HOME_RICHER` — and the fixture was deliberately NOT reached into, because a migration
editing a fixture to protect a number nothing pins is the wrong repair.

---

## 2026-08-23 — D17: a fleet of eight, an order said in one breath, and a bargain worth striking

Owner: *"MAKE An order - Command. too much unncessary info. So is Sail, Sell, Hire etc. Too long
explanation. this is a game, make it so. Check all aspect of the game. When buy, i want all the
trade goods on left side, and my fleet info on the right side, showing how much room, how much
negotiation can be done, and so on. This game fleet will be comprised with 8 ships."*

Then, when told this game had no haggling and that adding one was a design decision rather than a
UI change: *"yes add haggling mechanic."*

Four migrations (0021–0024), a new game mechanic on both sides of the wire, a two-pane BUY, and a
verbosity sweep over every screen.

### THE VERBS: 1,212 CHARACTERS → 309

    SAIL   Put to sea and make for another port.        (153 → 37)
    BUY    Take cargo aboard at the price on the quay.  (227 → 43)
    SELL   Sell out of the hold at the price offered.   (242 → 42)

The fine print did not go: 0021 adds a served `note` field and **proves the mechanics MOVED rather
than being retyped** — six phrases must be present in the old `help` and in the new `note`. The
card prints `help`; the ⓘ prints `note`. Nothing is authored client-side, because `cmd.verb_schema()`
is the one authority for the grammar and a client gloss would be a second one.

COMMAND also deleted a paragraph that printed the selected verb's own sentence **a second time, in
full, 200px below the card**. That was the loudest instance of the owner's complaint.

### EIGHT SHIPS, AND THREE CAPS THAT WERE FICTION

The design had always said a fleet is 1–8 hulls (`fleet_ship_max = 8`, §C.4) and B.3's formation
penalty had a band for **7+ that no fleet could ever reach**. What blocked it was `ship_max = 4`.

Raising it turned up the real defect: **all three caps were read by nothing.**
`fleet_ship_max` had never been read by any function, trigger, constraint or client since 0001 —
a sentence in a `description` column. `ship_max` and `fleet_max` were *served and printed as hard
limits* (RANK's gauge, FLEETS' "1/4 ships") while no server rule held them.

One authority now — `public.assert_house_caps()` — **on the table as a trigger, not inside a verb**,
so a future shipyard verb inherits the cap instead of re-deriving it. The caps were proven to bite
SEPARATELY: a 9th hull refused from one fleet while the same hull was accepted into a second.

    1 hull   4.9125 kn · free hold  55.8 t · crew  8
    8 hulls  4.6669 kn · free hold 446.4 t · crew 64      ← the 0.95 band, exercised at last

### THE BUY SCREEN IS TWO PANES

Goods left, the fleet's own state right, sticky while the list scrolls, at `md` and up. The
breakpoint was measured, not chosen: at `sm` the left pane is ~290px and the buy/sell/%NBR columns
wrap — the exact crushed-column signature `layout.spec` fails a build over.

**The rail is written FIRST in the DOM with `md:order-last`**, because at 390px the working pane is
**11,718px tall** and a rail placed after it would sit eleven thousand pixels below the list it
belongs beside.

The goods list is uncapped now — it was showing 12 of 68 and printing "56 more, narrow the filter".
The owner asked for *all* the goods.

### HAGGLING — AND THE HONEST FORM OF IT

0016 seeded a HAGGLING skill with effect `SPREAD` and the note *"not yet read by any rule."* This
made it real, and the mechanic lands exactly there.

**The lever is the spread, never the mid.** The mid is the world's price — identical for every house
on the quay. The spread is the port's cut, and that is what a factor can be talked out of. The
inline `spread × (1 − purser)` of 0017 became a named authority, `world.spread_effective()`, so the
rule about what a house executes at has ONE place to change.

* **Save-scumming is structurally impossible** — the attempt row is written and counted BEFORE the
  roll, and the attempt index is part of the RNG key. A retry is a different draw that has already
  cost a chance.
* **No new randomness** — it reuses `voyage.rng`, the IMMUTABLE primitive that keeps the world
  secret server-side. A second RNG in a chain whose offline-equivalence proof rests on there being
  one would have been a real defect.
* **A failure hardens the ODDS, not the price** — hardening the price would make `world.market()`
  print an ask the trade does not charge, since market() is served without knowing who has haggled.
* **Purser and bargain compose multiplicatively**, not additively: 25% + 30% is 47.5% off, not 55%.

### AND IT SHIPPED AS A ROUNDING ERROR, AND WAS SENT BACK

Driven in a browser, the finished mechanic saved **19 ducats on 40 tuns — 0.36%.** Three finite,
hardening attempts for a third of a percent. That is not a mechanic, and it would have read as
broken rather than subtle.

0024 retuned it: step 0.15 → 0.25, cap 0.30 → 0.75, floor 0.55 → 0.20. A full bargain is now
**2.88% of stake — 22% of a 13% voyage.**

**The brief asked for "a fifth to a third of a voyage's margin" and a third is arithmetically
impossible**, and the agent said so rather than fudging: a round trip pays one whole spread, spreads
average 3.84%, so even a bargain of 100% — the quay keeping *nothing* — is 3.84% of stake, 30% of a
voyage. Reaching a third means widening the spread itself, which taxes every unhaggled trader. Not
done; recorded with the measured projection.

`BALANCE_MEDIAN_IN_BAND` measures the UNHAGGLED median and still reads 12.9%. A bargained trader now
sits at 15–17%, at or just over the top of the band — **stated, not absorbed.**

### THE REGRESSION I PUT ON THE LIVE SERVER

0018's grant sweep — which I pushed to production yesterday — revoked `public.current_player_id()`
from `authenticated`. **Every RLS policy in the chain calls it**, so a direct client SELECT raised
42501. It was invisible only because every read goes through a `world.*` definer function.

It was worse than first reported: **11 tables, not 6.** And the agent swept all five ways a function
can be caller-evaluated — policy, CHECK, DEFAULT, GENERATED, index expression — rather than taking my
list. Triggers are deliberately excluded: EXECUTE on a trigger body is checked at `CREATE TRIGGER`,
not at fire time, so including them would report four defects that are not defects.

`public.caller_evaluated_functions()` is the third member of the family beside `client_write_grants()`
and `client_executable_writers()`. It **refuses to grant anything VOLATILE**, so 0018's property
cannot be re-opened by accident.

**Proof 03's hole is closed.** It tested INSERT denial and never a SELECT, which is exactly why a
broken read wall was invisible to it. It now runs with a THIRD house present, so isolation is proven
by ownership rather than by arithmetic — after the agent caught its own first assert ("A + B = the
whole table") being true on an empty database and **false on production, which carries a real
house**.

### TWO THINGS MY OWN GUARD CAUGHT

`tests/duplication.spec.ts`, written two days ago, failed this work twice:

1. **83% recipe similarity** between the haggle block's head row and the Ledger's entry head — two
   screens that never met, typing the same idea. Now `headRowClass()`.
2. **0022 re-cut five functions without the word "supersede" in its header.** It genuinely does
   supersede `world.quote`, `do_buy`, `do_sell`, `world.skills` and `client_rpc_entry_points`, and
   they move in one file for 0017's reason: a bargain `world.quote` honours but `do_buy` never
   spends is the same defect as checking room with one function and placing cargo with another's
   copy.

### UNITS

`9.4 d` was voyage-days and `8,000 d.` was ducats — **one letter, two units, a full stop apart, side
by side on FLEETS and PORT.** Days spell the word now. `t` and `kn` stay short; nothing collides
with them.

### Gate

`db:apply` 24/24 receipts · `db:proof` **45/45** markers across 6 files · `playwright` **159 passed**
· tsc, eslint, build clean.

**One honest caveat:** the first full run had two failures — `rpc.firstSession` and the chain-rebuild
spec — and the second run was clean. Both are the flake class 0024 documented and fixed for proof 04:
`tick_market_drift` uses `random()` by design, so every apply builds a different market and a spec
that needs one specific profitable round trip to EXIST can miss. Proof 04 now draws from the OU
process's stationary distribution keyed on authored codes. **`tests/rpc.firstSession.spec.ts` has the
same root cause and has not been given the same fixture.** It is a lottery, it is known, and it is
written here rather than left to surprise someone.

---

## 2026-08-22 — D16: the audit, and the day the game could not tell you where to sell

Owner: *"after all things are made, run audit on the all parts of the game. Make it playable. But
most of all, sort out your code so that it is well tidy and organized. No spaghetti."*

Seven background agents across two waves, partitioned by disjoint file domains, none permitted to
run git or the suite so that one working tree could not be fought over.

### THE VERDICT: playable, and the machine is good

An agent drove the real game at 390×844 and completed the loop twice through the UI alone — read a
market, composed a buy without typing, sailed, queued a sell while at sea, watched it run on
arrival. 8,000 → 8,131 d. Zero crashes, zero console errors across eight tabs, no sideways scroll,
and `Aborted()` **could not be reproduced in 13 cold loads**.

### AND THE THING THAT WAS ACTUALLY WRONG

**The metric the entire UI was built on is mathematically incapable of pointing at a profit.**

`%NBR` compares a price against ports within 600 nm — which is almost exactly *the set of ports
reachable in one leg*, so neighbours share a price BY CONSTRUCTION. Measured: over 2,100
(port, good) pairs, **145 read "buy", 13 read "sell", 1,872 "hold"**. A player at Lisbon saw seventy
rows and no SELL anywhere. The auditor followed the screen's own printed rule and the quay's own
recommendation and **lost 199 d. in 16 minutes**.

Worse, where the band did fire it could be wrong about money: salt reads 109.6 at Porto — a SELL by
the screen's rule — and carrying it there from Lisbon **loses 77 d.** A ratio of mids contains
neither port's tax, neither spread, nor the order's own price impact. Widening the radius cannot fix
that.

**0019 mints `world.trade_routes()`**: for each good a port sells, the reachable port that pays most
for it — priced end to end through the same `world.quote()` a committed trade executes at, over the
SAILED leg distance, and only to ports the fleet may actually reach. MARKET now names voyages:

    Black Pepper → Saint-Louis  +1,640
    60 t · pay 7,747 d. here, receive 9,387 d. there · 1,534 nm, 13.01 days · 21.2% on the outlay

%NBR is **kept and unchanged** — it honestly answers "is this cheap locally?" — and simply taken off
the advice job. Its band headings read `CHEAP HERE` rather than `BUY`, and a card says plainly:
*"%NBR says cheap HERE — not profitable."*

**Three folds were required before ranking was even possible**, each because the answer would
otherwise have had two authors: `voyage.reach_from` (one shortest path — a second Dijkstra could
have quoted 195 nm for a voyage that sails 248), `voyage.sail_refusal` (one answer to "may she sail
there?", found the expensive way when the first draft recommended a voyage `cmd.issue` then refused
with `E_ENDURANCE`), and `world.market` computing %NBR once instead of four times.

**The agent caught its own ranking bug by reading its output**: ranked by profit-per-sea-mile it put
*"wax to Setúbal, 16 nm, +49 d."* above *"+1,847 d."* — the original defect in a new column.

**And it is proven cheap without being wrong.** Proof 05 gained a marker: at ALE an EXHAUSTIVE scan
of 483 (good, destination) pairs found 1,034 d. at best, and the shortlist found the same 1,034 d.
`world.market` also got FASTER — 800 ms → 245 ms.

### THE P0, and it was real

**55 SECURITY DEFINER functions were executable by `anon`**, 17 of them writers, all bypassing RLS.
Proved by exploiting it: as `anon`, `public.fleet_unload()` ANSWERED.

The root cause was not the REVOKE — it was **`IN SCHEMA`**. Measured on a fresh PG 18.3: the
per-schema form of `alter default privileges` records rows that LOOK right while the function is
still anon-executable, so a catalogue assert passes vacuously. Only the schema-less form works.
0018's governing assert is therefore BEHAVIOURAL — create a probe writer after the fix and require
the privilege check to say no. Its first draft used the catalogue check, and **its own assert caught
its own draft**.

    anon-executable 55 → 0 · authenticated 65 → 18 (exactly catalog.ts) · pg_default_acl 0 → 1

### THREE WAYS THE GAME WAS LYING, all measured and all fixed

* **`affordableUnits()` never read the purse** — two of four offered buys refused instantly on a
  fresh save. The FOURTH copy of a bug the log says was killed twice. **Deleted, not patched.**
* **PORT teleported to Acapulco** when the fleet was at sea, and lost a chosen port on every tab
  change. Underneath, "where does her next order happen" had FOUR spellings and the fourth was the
  bug. One function now.
* **The SAIL picker showed straight-line distance** — Seville 169 nm against the server's 286 — and
  that wrong number sorted the list, so "nearest first" was not.
* **OFFICERS and ACADEMY rendered off the right edge** with no scroll affordance: `scrollWidth 401`
  against `clientWidth 332`. The newest features were the ones a player could not find. The strip
  wraps now — 293/293, six of six on screen — and the agent **overruled a comment I had written**
  claiming wrapping would jump the panel height. It was right: the ON and OFF arms differ only in
  colour.

### NO SPAGHETTI — the law, and the teeth

`docs/NO_SPAGHETTI.md` is the law. `tests/duplication.spec.ts` is what makes it bite: six shapes
that fail CI, **each proved able to go red** by mirroring the tree and injecting the defect.
Thresholds measured, not guessed — the closest honest pair sits at 0.71 against a 0.75 cut.

Twelve duplications ripped out, deleted rather than adapted. The headline: **"how much fits in this
hull" had seven implementations** — four server, three client — and MarketScreen's had forgotten
water and food since the day it was written, on the screen where you decide what to buy. Also:
`fold()` was private to COMMAND, so MARKET silently stopped finding `São Vicente`; `.replace('_',
' ')` written three times, each replacing only the FIRST underscore; `portByCode[code]?.name ?? code`
written **seven** times with one already drifted; and **67 lines of Quay JSX pasted verbatim inside a
JSX comment** by my own PORT refactor, invisible to the compiler.

`useWorld()` with no selector is now banned — it re-rendered every bare subscriber twice per read,
and reading is how time passes here.

### THE FINDING WORTH KEEPING

> **A boundary that forbids borrowing converts sharing into a silent COPY that no import check can
> see.**

`sections.spec.ts` was green the entire time `PortPicker` existed twice. "No screen imports another
screen" is satisfied perfectly by a copy. The boundary was producing the duplication it existed to
prevent — which is why the import guard alone was never going to be enough, and why the duplication
guard had to be written.

### Two defects of mine, both found by agents

The sticky first column painted `bg-surface` while D12 made panels `bg-panel`. And **0014's
self-assert was a lottery** — `limit 1` with no ORDER BY — measured at 3 failures in 7 runs. Same
class as D11h's drift assert, which this project had already recorded, and I reproduced it anyway.

### Gate

`db:apply` 20/20 receipts · `db:proof` 33/33 markers · `playwright` **157 passed** · tsc, eslint and
build clean. Verified stable over five consecutive applies and six consecutive proofs, because
prices drift with the wall clock and one green run proves nothing about a flake.

### Still open

The local world is still demolished on every chain change — rows are rescued to localStorage and
**never put back**, so every migration still resets every player. The real answer is the server, and
the Supabase CLI on this machine is not authenticated. Nothing has been pushed to the live project.

---

## 2026-08-22 — D13: four migrations, and two of them change a rule

Owner: *"do the migrations - price history, player row, officers, skills"* — the four server gaps
D12 named as the real ceiling.

### The problem every one of them hit: 0007 is DEPLOYED

Fame wants to be a counter each verb increments. A skill wants to be XP each verb awards. Officers
want a hook in the trade and the voyage. **All three mean editing migrations that have already run**,
which this chain does not do. So each migration had to find the shape that fits the constraint —
and in two cases the constrained shape is better than the obvious one.

* **Fame is DERIVED** (0014), not counted: `public.player_fame()` reads the append-only ledger every
  time it is asked. It cannot drift from the record, and it is retroactively correct for every
  voyage sailed before the migration existed. A stored total would have been a second authority for
  something `events` already knows.
* **A skill is a CHOICE, so it is STUDIED** (0016), not earned: derived XP would level itself, and
  then it is not a decision, it is a second fame. `cmd.study_skill()` costs money and requires a
  port with an academy — and **`ports.has_academy` has existed since 0002 with nothing reading it.**
  A flag nothing reads is scenery; it has a consequence now.
* **Two files SUPERSEDE one function each** — `voyage.fleet_speed()` (0015) and
  `voyage.endurance_days()` (0016). That is the sanctioned way to change a rule here (README §1:
  "a change goes in a NEW file that supersedes the old one") and it is not re-cutting 0006, which
  still proves its own claims when the chain replays in order.

**The supersedes are no-ops when the new thing is absent, and that is asserted rather than assumed.**
An unofficered fleet reads 0006's exact 4.9125 kn; an unstudied captain reads 0006's exact endurance.
That is what keeps `04_first_session` — which sails an unofficered, unskilled Barca — honest.

### An officer or a skill that changes nothing is decoration

Both migrations could have shipped tables and a hiring RPC with the effect left for "later". Each
wires exactly ONE thing instead, and **says out loud which of the rest are inert**:

    NAVIGATOR    -> voyage.fleet_speed()      READ
    QUARTERMASTER / SURGEON / PURSER          seeded, NOT READ YET
    SEAMANSHIP   -> voyage.endurance_days()   READ
    NAVIGATION / ACCOUNTING / HAGGLING        seeded, NOT READ YET

`world.officers()` and `world.skills()` carry a `takes_effect` flag per row, the self-asserts check
it both ways, and the UI prints *"No rule reads this yet — this bonus changes nothing today."* The
same posture 0010 and 0012 take about an absent pg_cron: report it, never pretend.

NAVIGATION is deliberately the inert one on the skill side: **0015's navigators already own speed**,
and two authorities for one number is the thing this project forbids.

### 0013, and the sentence that had to be deleted

`public.price_history` is keyed `(port, good, slot)`, so a retried tick is a no-op by construction
rather than by a check somebody has to remember. It samples 14,980 rows per slot and prunes past a
288-slot window; both directions are proven, and the prune is proven by **ageing a row on purpose**,
because on a table this young a prune that removes nothing looks identical to one that works.

The slot formula got a name. 0010 computes `floor(epoch / drift_slot_seconds)` inline and cannot be
re-cut, so `public.drift_slot_of()` is minted as the named authority and the self-assert **proves it
returns the slot `tick_market_drift()` itself reports** rather than assuming the two agree.

MarketScreen printed, on screen: *"No seven-day line is drawn … nothing in the chain keeps one yet."*
That sentence is now false, so it is gone, and a TREND sparkline stands where it was. Three docs that
listed `history7` as not-served were corrected too.

### What the client got, so this is not half a slice

Seven RPCs (`worldPriceHistory`, `worldPlayer`, `worldOfficers`, `worldSkills`, `cmdHireOfficer`,
`cmdPostOfficer`, `cmdStudySkill`), their types, and the store. Then:

* **MARKET** draws the line. `Sparkline` refuses to interpolate (a gap in the record is a gap in the
  line), refuses to scale to zero (a 2% move would look like a halving), and draws nothing under two
  points.
* **PORT** gains two faces — **Officers** and **Academy** — because §3a's second trap is "the action
  lives on the wrong screen". An officer signs on at a quay; a trade is learned at an academy. The
  Academy face is only offered where `has_academy`, since a face that always refuses wastes a tap.
* **RANK** stops counting. It used to derive voyages and turnover from one 50-row ledger page and
  had to admit the window; fame is the server's now, over the whole record. What is left derived is
  a fact about the PAGE, and it says so.
* **PROFILE** shows the house — company, nation, level, founded, where she lies.

### Proved

`db:apply` **16/16 receipts**, `db:proof` **31/31 markers**, `playwright` **149 passed** against a
served build. tsc + eslint clean. Every new migration is LF (checked, not assumed — the CRLF trap).

**Three test pins moved deliberately:** the chain's LAST migration, its human sentence, and the RPC
catalogue's allow-list, which exists precisely so that adding an RPC is an edit somebody made on
purpose.

### Two things found on the way

1. `ledger.event_id` does not exist — the column is **`ref_event_id`**. Caught by the first apply,
   which is the whole argument for PGlite: it cost thirty seconds instead of a CI round trip.
2. A fleet cannot be set to "at sea" by nulling its port alone: `fleets_position_is_unambiguous`
   (0004) ties status and port together. The constraint doing its job — a fleet cannot be nowhere.

### Still not done

**No standings table**, and that half is a DESIGN decision rather than a missing SELECT: a table of
captains needs a rule about who may see whose figures. **Buffs** have no table. Three officer
specialties and three skills are inert by design and say so. And the price line stays empty in local
play, because nothing schedules a tick under PGlite — on the live server, where D11e proved pg_cron
runs, the record fills every ten minutes.

---

## 2026-08-20 — D12c: the rest of the screens

Owner: *"keep going, do the rest of the screens."* (D12b, logged only in its commit until now, made
a verb an action card carrying the server's own `spec.help`, and added §3a to the direction doc.)

### PORT is one place with faces now

It was four sibling Cards down a page. At 390px the fourth began roughly 1,200px down and, in
practice, was never read. It is one panel with a tab strip — **Quay · City · Services · Alongside**,
the reference's 기본/교역/시설/투자 — with the same content and the same order lines.

**The Quay opens first, deliberately.** §3a's second trap is *"the action lives on the wrong
screen"*, and the most-praised patch in that game's four-year convenience backlog added no feature
at all: it moved selling provisions onto the buy screen, where the need arises. What you can DO here
opens first; what the city IS is one tap away.

Composing it introduced two duplications immediately — `DRAFT 5` and the `HARBOUR` eyebrow each
printed twice, once in the PageHeader and once in the new panel head. Both deleted from the panel.
Same rule that took the purse off two screens in D12, broken again within ten minutes of writing it
down.

### Three primitives the design system was missing

**`TabRow`** — a real `role="tablist"`, and it **scrolls sideways rather than wrapping**: a wrapped
second row of tabs changes the panel's height when the selection changes, which makes everything
below it jump.

**`Gauge`** — a resource drawn as **countable segments**, not a smooth bar. EVE draws its capacitor
in fragments for the reason that matters on a phone: you can *count* blocks and reason "four left,
that is 40 tuns", where a bar forces arithmetic against a denominator that is not on screen. This
game already had the idea in one place — the Market's six-cell text `stockBar` — and this is that
idea as a primitive. The partial segment is **shaded, not rounded up**: a hold with a sliver free
must not read as a hold with a whole block free.

FLEETS uses it for the two facts that decide the next order, **hold and worst hull**, which were
buried one tap and a scroll down in the detail panel. Whether to buy is "how much room is left";
whether to sail is "how sound is the worst hull". The figure stays beside the blocks, because a
gauge you cannot read exactly is a mood ring and this is a ledger.

**`Input`** — the audit found four hand-written recipes differing in border, focus ring, padding and
whether they cleared 44px. Auth and the register are migrated.

### RANK and PROFILE stopped being placeholders

RANK was 18 lines naming three things that would exist one day. The honest position is narrower and
more useful: **the client can say what you are worth; it cannot say what that is worth relative to
anyone**, because no other house's figures cross the wire and nothing in the chain computes a table.

It now shows the real figures a standing would be computed FROM — purse, fleets, ships, and from the
ledger: voyages completed, ports reached, trades struck, taken in, paid out — and states the missing
half as a fact, naming the four things a standing needs first.

**The derived counts say what window they looked at.** `world.events` is ONE page of the ledger (the
store fetches the default 50), so "voyages completed" is not a lifetime total and must not be printed
as one. Purse, fleets and ships are exact, because those are served whole.

PROFILE keeps the session half, which was always real, and replaces the bullet list of promises with
**the world half** — which backend answered, the world's size, the time compression. A player asking
*"am I on the live server"* or *"why did my purse reset"* had nowhere to look. What is still absent
is named as server work rather than drawn as empty fields.

### Everywhere else

* **LEDGER**: the delta is `text-xl`. It was the same size as the "balance" caption beside it, which
  gave the number a player scans a ledger FOR the same weight as the one they merely check. Its
  filter chips are the `chip` primitive now.
* **MAP**: the corner panels take the panel material and keep their blur — they sit ON the world and
  must let the coastline stay legible. **The blur stops there**: CCP measured window blur at up to
  32 ms a frame and drop it entirely at low shader quality, so two small panels over a static SVG is
  a budget that survives and a screenful of panels is not. The chart's water is `bv-sea` now — the
  map is not a different place, it is the same world seen from further up.
* **AUTH**: the first thing anyone sees was a flat `bg-app` field, the colour of an unstyled page.
  It is the lit sea, so signing in and playing are visibly the same place.

### Proved

**149 passed** against a served production build, twice — once before the map and input changes and
once after. All 12 layout tests, the K.1 fold test, and the four-viewport map label specs. tsc and
eslint clean. Every tab screenshotted at 390×844 and checked for sideways scroll: **all eight clean.**

### Still not done

COMMAND's argument pickers are still the old chrome inside the new action cards, and the Market's
port picker still truncates 214 ports to 40 with an on-screen admission that it cannot show the
world. The server gaps are unchanged and are the real ceiling: **no price history, no player row, no
officers, no skills, no fame.** Each is a migration, and until they land there are screens here that
are correct and still look empty.

---

## 2026-08-20 — D12: it was a document, so it was made of something

Owner: *"this is not a proper game. see other games such as 대항해시대 오리진 — find korean images,
gameplay videos, images. Refer to them and make the UI the same, or even better. Refer to
Runescape 3, EVE online as well. They have good UI. USE the best tools for each tasks, and make a
proper game."*

### The reference was LOOKED AT, not remembered

Marketing art teaches nothing about UI, so the App Store shots were a dead end — they are 60%
character illustration. The usable captures are on Line Games' own Korean guide site, which
documents the game with real in-game screenshots (`static.pcs.line.games/gameguide/guideContent/`).
Twenty-six were downloaded and read. They live **outside the repo**: they are Line Games'
copyright, and what this project keeps is what was learned, never their art.

The single most useful frame is 세계지도 — the world map with the port-info panel docked at the
right. It gives the whole layout grammar in one picture, and the row inside it is the lesson:

    (icon) 포탄     101%   574
    (icon) 돌소금   105%   516
    (icon) 인쇄물    99%   306

**Four facts, one line, no prose** — and the price index is a coloured pill riding directly behind
the name, not a column you swipe to reach. D11h moved `%NBR` to second position by reasoning about
it. The reference proves the position by shipping it, and proves the *shape* we had not got to.

`docs/UI_DIRECTION.md` is the write-up: the diagnosis, the layout grammar, a pattern table, the
material read off the captures, what RuneScape 3 and EVE Online add on top, and **eight rules** the
client now builds to. It states plainly that it overrides `docs/DESIGN.md`'s UI austerity on the
owner's instruction — and that it changes nothing about the architecture.

### The doctrine that had to be retired, in its own words

`src/index.css` opened with: *"TEXT-FIRST: this game is words, numbers and tables … the type
carries the design and **the chrome stays quiet**."* That sentence is why the app looked like a
web form, and it was load-bearing — it was the reason nothing was made of anything. It is replaced
in place, with the owner's instruction quoted beside it, rather than quietly deleted.

**The palette survived unchanged.** It was never the problem. Cold ink-blue layers, warm parchment
text, brass accent — all still exactly what they were. What was missing was *material*.

### What material means, concretely

Fourteen new tokens, **every one derived via `color-mix` off the existing palette**, so retuning
`--color-accent` retunes the material with it. A literal would have been a second palette.

    panel / panel-2 / panel-head    the ink layers pushed warm, toward oiled wood
    hairline                        the 1px gold rule under every panel header
    brass / brass-2 / brass-rim     the primary action's fill, rim and lit top edge
    sea / sea-lit / sky / sea-deep  the world behind the glass
    cheap / dear / even             one meaning per colour, rule 7

and four compositions no single utility expresses: `.bv-panel-head`, `.bv-cut` (a 7px chamfer —
metal, where a 12px radius reads as a web card), `.bv-brass`, and `.bv-sea`, a **pure-CSS lit
horizon**. That last one is deliberate: this repo has no art at all, and a gradient in the
stylesheet costs zero bytes and can never 404.

### One panel, not two

The tempting move was a new `GamePanel` beside `Card`. That is two authorities for "what a panel
is", which is the thing this project keeps having to rip out. Instead **`Card` became the game
panel**: same name, same callers, new material, plus a `head`/`foot` slot — because the reference's
header bar is FULL-BLEED and a caller cannot make one from inside the padding without negative
margins. Cards that pass neither are exactly what they were and simply inherit the new skin.

### The frame

`TopBar` is the persistent chrome the app never had: wordmark, a live-read dot, and the purse. It
carries **one** figure, because the purse is the only number this server actually keeps — the
reference shows four currencies and inventing three more would be decorating the UI with facts the
game does not have. It carries **no back chevron**, because eight tabs is a flat model and a
chevron with nowhere to go is worse than none.

Wiring it found a real duplication: COMMAND and LEDGER were each printing the purse in their own
header. **Three copies of one figure**, and the two that scroll away were the wrong ones to keep.
Both deleted.

The shell root is now `.bv-sea` and does not scroll; each screen scrolls its panels over it, so the
horizon stays put the way it would from a deck.

### The chip, which the design system was missing

The audit found **twelve hand-written copies** of one pair of recipes across Command, Market and
Fleets — drifting in border colour and hover between copies. `buttonClasses` now has `chip` and
`chip-on`. Two variants rather than a boolean, because it is a pure string function and every
caller already knows which state it is drawing.

### MARKET, measured

`PriceIndex` is the %NBR pill and the one treatment of the figure the game is played from. It is
deliberately **not** a `Badge`: Badge is the status-WORD pill at 10px, and rule 2 says the number is
the hero. **The tone comes from the server's own `advice`** — never from comparing `pct` against a
threshold on this side of the wire.

Two measurements drove the rest, taken in a real browser at 390×844:

* the panel header's first cut put the tap-affordance line inside the bar, which grew it to ~100px
  and **cost two price rows above the fold**. On a screen whose whole job is rows, the chrome does
  not get to eat them. One line in the bar; the affordance moved to the body.
* the row printed the category under the name, making every row 62px — **four rows above the fold**.
  The category is a fact about the good, not about its price today, so it moved to the row's title.
  **Four became five**, and the row is still the 44px the reach law requires.

`TradedRow`'s `block` prop is gone with it: it existed only to tint the %NBR figure, and the pill
now carries that meaning from `advice`. Two renderings of one fact; this was the copy to delete.

### Proved

**149 passed, 0 failed** against a served production build — including all 12 layout tests and
`MARKET puts a complete price row above the fold, per K.1`. The fold measured directly in the
browser afterwards: `{foldY: 731, rows: 70, above: 5, firstText: "Black Pepper 83% 131 120 ██████
glut"}`. tsc + eslint clean.

### What this did NOT do, and is next

The frame and the material are in; **six screens still wear them without being re-composed**. PORT
is still four sibling cards where the reference is one place with faces; COMMAND's verbs are still
text buttons rather than the reference's hero action cards; FLEETS has no status orbs; RANK is
still an 18-line placeholder. And the honest blockers stand, all of them server-side rather than
visual: **no price history** (so no sparkline can be drawn honestly), **no player row** (so PROFILE
and RANK cannot be driven at all), no officers, no skills, no fame. Each is a migration, not a
component — and they are why the UI still looks empty in the places where it is behaving correctly.

## 2026-08-20 — D11h: the four left undone, done

Owner: *"don't leave out. do all."* So all four, each proved in a browser rather than reasoned about.

### 1. The drift flake, explained rather than suppressed

0010's assert read ONE row (Lisboa x Salt) before and after a drift tick and required it to change.
`port_goods.drift` is `numeric(6,4)`, so an OU step under 0.00005 rounds to no change — from a
zeroed drift, a perfectly ordinary draw. **The assert was a lottery on one row.**

Measured, now that it counts: **14,967 of 14,980 rows move; 13 round away.** That is 0.087%, so the
old single-row assert had roughly a **1-in-1,150 chance of failing any boot it ran in** — which is
exactly "seen once, never reproduced in 8 tries".

The claim is now measured where it lives: the tick promises to step every row, and a stepped market
is one that has MOVED. It requires 90% and gets 99.91%, and the receipt prints the count so a
regression shows instead of hiding.

### 2. %NBR was sixth, and fell off the right edge

The column the entire game turns on — this port's price against what its neighbours pay — was the
one you had to swipe to see, while `131` and `139`, which mean nothing on their own, sat in plain
view. **It is second now**, immediately behind the sticky good name, which is the last position
guaranteed to be on screen at 390px without scrolling.

Measured in the browser: `GOOD | %NBR | BUY | SELL | STOCK | NOTE`, second cell `83%`,
`fullyVisible: true`. The prices did not get less important; they got less urgent.

### 3. The queue trap now says so, while it can still be cancelled

A SELL queued behind a SAIL home is a guaranteed loss the ledger tells you about afterwards. A queue
is first-in-first-out and cannot be reordered, so the fix is to say WHERE a trade will happen:

    [2] SAIL Gaivota TO LIS                    PENDING
    [3] BUY salt ALL      after she sails      PENDING

It reads the server's own parsed `verb` and nothing else. Writing a client-side parser for the order
line — when F.4 says there is exactly one parser and it is on the server — would have been a worse
bug than the one being fixed.

### 4. A half-made order survives a reload

Composing an order is four or five deliberate taps through pickers, and a refresh threw them away
with no trace. The draft persists to **sessionStorage**, not local: a draft is a thing you are
doing, not a thing you keep, so tomorrow opens on a clean composer instead of resurrecting an order
aimed at a fleet that has since sailed, sold and come home.

`handoffs` is deliberately NOT persisted — it is the nudge that scrolls the composer into view when
another tab hands an order over, and restoring it would scroll on a plain reload as though a
hand-off had just happened. **Persist the order; never persist the reaction to it.** A corrupt byte
opens a clean composer rather than wedging the tab.

Proved: `SAIL Gaivota` on screen, reload, `SAIL Gaivota` still on screen.

### The whole suite, green

**149 passed, 0 skipped, 0 failed** — the first fully-green run of the day, including all 12 layout
tests and the fold test that had been red since before this session started. `db:proof` 31/31.

**One consequence to record:** editing 0010's self-assert changes the chain fingerprint, so any
browser still in LOCAL mode rebuilds its world once. Cloud mode has been the default since D11e, so
this is now a note rather than a loss. The live server is unaffected — `db push --dry-run` reports
*"Remote database is up to date"*, and a recorded migration is never re-applied. As with 0012, the
deployed copy of 0010 carries the older assert text; no schema or behaviour differs.

---

## 2026-08-20 — D11g: the three defects the playtest found, fixed

Owner: *"fix and do what is necessary."* So: the catalogue from D11's playtest, not new work.

### 1. The first tap a new player made was already refused

Tapping a good on MARKET handed the order to Command prefilled with the FREE HOLD — which ignores
the purse. The preview refused it instantly: *"60 tuns of Black Pepper cost 8020 d. and you hold
8000"*. Twenty ducats over, on a screen they had not touched yet.

It was the **third copy** of the rule D10 was written to kill (*"two places computing a maximum,
both ignoring the price"*). D10 fixed the MAX chip and `cmd.resolve_qty` and this one survived
because nothing pointed at it.

**The fix deletes the copy rather than correcting it.** Both sides now hand over `ALL`, and the
client computes no maximum at all: buy-side `ALL` resolves server-side through
`public.fleet_buy_capacity()`, which walks the same stepped book a committed trade walks and stops
at whichever of hold, stock, daily cap or **purse** binds first. `ALL` is read when the order RUNS,
so it survives a voyage that changed the hold.

### 2. She was "lying at" a port she was still sailing towards

The COMMAND summary read *"…56 t free · lying at Cadiz"* while the panel directly below it read
*"at sea → Cadiz, 84 nm of 248 nm"*. Same fact, two sentences, one of them false. `port` there is
where the order will TRADE — where she lies, or where she is bound if she is at sea (F.2) — and it
was printed as "lying at" either way. It now says **bound for** when she is SAILING.

### 3. A proof that had been red since before today

`MARKET puts a complete price row above the fold` failed with *"only 0 complete price rows above the
fold at 731px"*. Not a layout defect: `waitForLoadState('networkidle')` fires when the bundle has
downloaded, and the chain applies **inside the browser** for seconds after that — so the test was
measuring the loading skeleton, honestly and uselessly.

The first fix was wrong and the suite said so: waiting for a table row timed out on COMMAND, which
has no table. **Ready is the absence of the two things loading looks like**, and both are
design-system-wide: `Skeleton` is the ONE placeholder (`animate-pulse`), and *"Opening the world"*
is the one sentence every screen prints while the chain applies.

All 12 layout tests green, including the fold test, measuring the real screen.

### And a guard the deployment made necessary

With `.env.local` present the app is in cloud mode and every route redirects to `/auth`, where there
is no table to measure. That is the wrong BUILD, not a layout failure, so the spec now **skips with
the reason and the fix** instead of failing confusingly — proved by running it both ways: 12 passed
on a local build, 6 skipped on a cloud one.

`db:proof` 31/31 · `playwright` 143 passed · tsc + eslint clean.

### Left undone, deliberately

* **%NBR is still cut off at 390px** — the column the game turns on. It needs the layout change the
  redesign canvas draws, not a patch.
* **The queue is still FIFO with no reorder and no warning** when "sail home" is queued ahead of
  "sell". Design work, not a fix.
* **A half-composed order still dies on a reload** (the draft is in-memory).
* **0010's drift self-assert flake** — seen once, never reproduced, still not understood.

---

## 2026-08-20 — D11f: sections, and the clock that runs in one of them

Owner: *"do the next thing, but again, no spaghetti with others. What you've created so far,
organize them separately and independently so that individual have its own separate section …
ships, stats, skills, trade goods … prices, buffs, fleet, captains, location."*

### The spaghetti was real, and it was measurable

Nine imports had one SCREEN reaching into another screen's internals:

    port/PortScreen      -> command/commandDraft, command/orderText, fleets/worldGate, fleets/fleetDerive
    fleets/FleetsScreen  -> command/commandDraft
    market/handOff       -> command/commandDraft
    ledger/LedgerScreen  -> fleets/worldGate

None of it was bad code. Every one was a screen borrowing something that was never the lender's:
**"how much hold is free" is a property of a fleet, not of the tab that draws one.**

The clearest tell was `market/handOff.ts`, whose own header explained that it existed as an adapter
because *"commandDraft.ts is owned by the CMD tab"*. **An adapter that exists only to survive a
boundary is a sign the boundary is in the wrong place.** It still exists as a named intent; it is no
longer a border crossing.

### Two sections, by pure move

    src/domain/order/   draft.ts · text.ts · handOff.ts   the order language and the order being made
    src/domain/fleet/   derive.ts                          hold, crew, stores, cargo, hull, draught
    src/live/WorldGate  (was features/fleets/worldGate)    world loading + failure chrome

Each has one entrance (`index.ts`). Both are pure — no React, no store, no screen — and **neither
decides anything**: the server owns every rule, and these only read what a served payload says.

Cross-screen imports today: **zero**.

### The rule has teeth now

`tests/sections.spec.ts` reads the import graph off disk and fails on three things: a screen
importing another screen, a domain reaching up into a screen or the shell, and anything reaching
past a section's entrance into its internals.

**It was proved to bite before it was trusted** — a cross-screen import was added on purpose and the
spec failed, naming the exact crossing, then went green when it was removed. A boundary test that
has never failed is decoration.

`docs/SECTIONS.md` is the map: which section owns which concept today, and — for the ones the owner
named that do not exist yet — where they land. Skills, buffs and officers each get their **own
migration**, never a column bolted onto `players` because that table was nearest. The row worth
guarding is `stats`: a stats table that anything may write is not a section, it is the place
sections go to tangle.

**The server is not reorganised, and that is deliberate.** The chain is deployed; re-cutting
0001–0012 would desync `schema_migrations` on the live project and destroy every player's world to
gain a filing improvement. Existing migrations stand. New concepts get new files.

### The next thing: 0012, the clock is wound

0010 owns what a tick DOES. **0012 owns only when it runs.** Two files, two questions, no overlap —
the pattern the rest of the game should copy.

The cadence is **derived, not restated**: `drift_slot_seconds` (0010) already answers "how often does
the market step", so writing `*/10 * * * *` here would be a second answer, and the day somebody
retunes the knob the cron would keep the old rhythm. `public.tick_cron_expression()` computes it,
and the self-assert proves the crontab and the knob agree.

    arrivals    * * * * *      every minute — a voyage-day is three real minutes
    drift       */10 * * * *   from drift_slot_seconds = 600, not from a literal
    reconcile   7 * * * *      hourly and OFF the hour, so the audit never lands on the writers

Positive controls that bite: a 30-second slot and a 35-minute slot are both REFUSED, not rounded.
And under PGlite, where pg_cron cannot exist, it applies cleanly, schedules nothing, and **says so**
rather than pretending.

### Proved running, not merely scheduled

    jobname                   schedule        active
    byeharu-voyage:arrivals   * * * * *       true
    byeharu-voyage:drift      */10 * * * *    true
    byeharu-voyage:reconcile  7 * * * *       true

    cron.job_run_details: arrivals succeeded at 06:48:00 and again at 06:49:00

**The world breathes on its own now.** Market drift and stock regeneration run whether anyone is
looking or not — which is what makes a shared economy shared.

`db:apply` 12/12 receipts · `db:proof` 31/31 · `playwright` 143 passed · tsc + eslint clean. Three
test pins moved deliberately (last migration, its sentence, the receipt count).

### One honest discrepancy

0012 was pushed to the live server, and THEN two cosmetic edits were made to the file: the
no-scheduler receipt was reworded to match the `self-assert ok:` contract the chain's non-vacuity
floor requires, and a no-op `for` loop was deleted. Supabase will not re-apply an already-recorded
migration, so **the deployed copy carries the older text**. There is no schema or behaviour
difference — a NOTICE string and dead code — and the three jobs on the server are the correct ones,
verified above. It is recorded here rather than quietly left.

---

## 2026-08-20 — D11e: the game went online

Owner: *"can you just delete everything of aqua chronicles, and overwrite this?"*

### What was destroyed, and what was looked at first

`aqua-chronicles` held one of the account's two free Supabase slots. Before deleting anything:

| | |
|---|---|
| status | `ACTIVE_HEALTHY`, Seoul, Postgres 17 |
| last commit | **2026-06-16** — two months dead, the day byeharu began |
| data | 8 players, 5 ships, 3 teams |
| accounts | 8 — and **7 were test accounts** (`cooptest_`, `cargo_e2e_`, `repro_`, `claudedebug_`) |

So: a dormant dev database holding the owner's own two emails and six robots. Every row of it was
exported to `Desktop/aqua-chronicles/_final_db_export_20260820/` first, and the 293 migrations that
built it were never at risk — they are in the repo. Then the project was deleted. **That is
irreversible and the export is the only copy.**

### byeharu-voyage is now a real server

    project   byeharu-voyage · olaquvizoavjeiricyxk · ap-northeast-2 (Seoul)
    chain     11 migrations pushed, 11 self-assert receipts GREEN on real Supabase
    schemas   world, cmd, voyage exposed to PostgREST
    world     214 ports · 782 legs · 14,980 prices · 0 client write grants

0001's grant lockdown found what only a real project has: **16 default-ACL entries owned by
`supabase_admin`** that cannot be revoked from the migration role. It printed them, proved every
object in the four schemas is owned by `postgres`, and passed — the exact scenario D8 wrote the
Supabase-shaped preamble for, now confirmed against the real thing rather than a fixture.

### The proof, end to end, in a browser

    1. sign-in       -> /command   [rpc] cloud: Supabase project, PostgREST, schemas world/cmd
    2. no house      -> THE REGISTER · "Sign the book"
    3. signed        -> 8,000 d. · Gaivota · lying at Lisbon · 15.0 d of stores · 56 t free
    4. FLEETS        -> 1/2 fleets · 1/4 ships · Gaivota DOCKED at Lisbon · Barca

A `cmd.found_house()` call over PostgREST returned `{"ok": true, ...}`, and a second one returned
`E_ALREADY_FOUNDED` — **the positive control biting in production**, not in a fixture.

### The screen that had to exist first

`src/features/found/SignTheBook.tsx`. Local mode founds its captain during boot, so nobody had ever
needed one; on a real project a new account owns nothing and every tab is an empty shell. The
register now REPLACES the tab content until the book is signed (`AppShell.tsx`) — there is nothing
to navigate around and nothing to misread as broken. It appears only when the world is `ready` and
the fleet list is empty, because "still opening" and "failed" are also empty and are not the same
state; local mode never sees it.

**It validates nothing.** `public.players` already carries `unique` and
`check (length(btrim(company_name)) between 3 and 24)`, and 0011 turns each into a refusal with a
sentence. A length check in the form would be a second authority that drifts the first time the
constraint moves. The button asks, and prints what comes back.

### Two mistakes made along the way, both corrected

**1. The auth config was pushed when I had declined it.** `supabase config push` prompts per
service; piping `y\nn\n…` answered the API prompt correctly and then did *not* hold for auth —
remote auth silently took the local file's values, changing `site_url` from `localhost:3000` to
`127.0.0.1:3000` and turning MFA enrolment off. No users existed and nothing broke, but it was not
an intended change. Corrected deliberately: `site_url` is now
`http://localhost:5173/byeharu-voyage/` (where the game actually runs), the Pages URL is in
`additional_redirect_urls` for when it exists, and MFA is back on. Verified by re-diffing until all
four services reported *up to date*.

**2. I called a 42501 a defect before reading the grant.** `world.snapshot()` over PostgREST
returned *"permission denied for schema world"* and the first instinct was written down as a bug
only a live deployment could find. It is not a bug: 0001 line 223 grants `world` USAGE to
`authenticated` and `service_role` and deliberately **not** to `anon`. The call was made with an
anonymous key. Signed in, it returns 200 and the whole world.

### Still not done

* **pg_cron is not scheduled.** 0010's receipt has said so on every apply and still does. Reads
  settle voyages (D.2) so the game plays, but market drift and stock regeneration never run.
* **The `.env.local` switch is total.** With it present the dev server is in cloud mode, and the
  local PGlite world — including any game played in this browser — is not what loads. Delete the
  file to go back.
* **One world, many captains** is now literally true and has never been under load.

---

## 2026-08-20 — D11d: cloud mode could never have worked, and the reason was one missing function

Owner: *"this is an online game... everything must be server controlled."*

### What is already server-controlled, and it is most of it

The RULES have never been anywhere but the server. Every verb is a SQL function; `cmd.preview()`
runs the real verb in a subtransaction and rolls it back, so the estimate and the commit cannot
disagree; the client-side validator (838 lines) was deleted in D5 because *"two authorities for 'is
this order legal' is exactly the duplication this project forbids"*. RLS is on all 19 tables with
**0 client write grants**, re-proved on every apply. The client renders and requests. It decides
nothing.

### What is not

**The database runs in the player's browser.** PGlite, one private world each — no shared economy,
no other captains, no server clock, and a save that lives or dies with one origin's IndexedDB
(D11c). `src/lib/rpc/init.ts` was built to flip this with one answer (`hasCloud`), and
`cloudBackend.ts` has said so since it was written: *"NOT PROVEN AGAINST A REAL PROJECT."*

### The hole that flip would have fallen into

Auditing the cloud path before deploying anything, rather than after:

    grep -rn "new_house" src/     ->  src/lib/db/localDb.ts, and nothing else

`public.new_house(p_auth_uid, name, nation)` founds the house, the 8,000 ducats, the Barca at
Lisboa. 0004 line 342 revokes it from `public, anon, authenticated` — **correctly and permanently**,
because it takes a uid as an argument, so a client that held it could found a house on somebody
else's account. Its only caller was the local engine's boot.

So: **sign in to a real project and you would land in an empty world.** No fleet, no purse, no
ledger, and nothing on any screen to press. Cloud mode has never been playable, and nothing would
have said so until a real player signed up.

### 0011 — `cmd.found_house(name, nation)`

Note what is *not* in that signature. **It takes no uid.** It reads `auth.uid()` itself, so the only
house a caller can found is their own — the security property is structural, not checked.

It also **restates no rule that already exists**. `public.players` already carries
`auth_uid uuid unique` and `company_name text not null unique check (length(btrim(...)) between 3
and 24)`. The function lets those constraints bite and translates the SQLSTATE into the refusal
vocabulary the client already speaks. Two authorities for "is this name legal" would drift; there is
one, and it is the constraint.

Five refusals, and the self-assert makes **four positive controls BITE** rather than asserting the
happy path alone:

| | |
|---|---|
| `E_NOT_SIGNED_IN` | an unsigned caller, before any house exists |
| `E_ALREADY_FOUNDED` | a second house on one account |
| `E_NAME_TAKEN` | a name already trading |
| `E_BAD_NAME` | a 1-character name |
| `E_NO_SUCH_NATION` | an unknown flag — carrying all 20 real ones as fixes |

and it asserts the grants OUTSIDE the rolled-back probe, because a revoke that never happened must
fail the migration rather than vanish with it: `anon` may **not** execute it (or a crawler founds
thousands), `authenticated` may (or nobody can sign the book at all). After the four refusals it
re-checks that the refused captain still has **no** house — a refusal that half-founded one would
leave a purse with no ledger behind it.

### Wired, and the vocabulary test earned its keep

`cmdFoundHouse` is one row in `src/lib/rpc/catalog.ts` — both backends are built from it, so the
local SQL and the PostgREST named-argument call cannot drift. Adding it turned
`rpc.surface.spec.ts` red, exactly as designed: the client's whole vocabulary is asserted by name
*"so that adding one is a deliberate edit here"*. The edit is made, and the comment beside it that
0011 invalidated (*"a browser must not be able to found a house"*) is corrected to the real rule —
`new_house(uid, …)` never, `found_house(name)` yes, and **the difference is the argument**.

`npm run db:apply` 11/11 receipts · `db:proof` 31/31 · `npx playwright test` 140 passed · tsc and
eslint clean. Three test pins moved deliberately (last-migration name, its sentence, the vocabulary
list).

### THE WALL, stated as a fact

**There is no Supabase project for byeharu-voyage, and one cannot be created on this account.**
`supabase projects list` returns exactly two, and the free tier allows two:

    aqua-chronicles   Northeast Asia (Seoul)       2026-05-24
    byeharu           Southeast Asia (Singapore)   2026-06-16

The one-time fix is the owner's and takes a minute in the dashboard: **pause `aqua-chronicles`**
(reversible, keeps the data) or **upgrade the org to Pro**. Nothing else is blocked by it — CI's
disposable-Supabase job proves the whole chain against real Supabase roles on every push, and it is
green on `4f598e6`.

### What still stands between a project and a shared world

Written down now so the day it exists is a checklist, not a discovery:

1. **Expose the schemas.** PostgREST serves `public` only by default; the API settings must add
   `world`, `cmd`, `voyage`. `cloudBackend.ts` has carried this note since it was written.
2. **Schedule the clock.** 0010's own receipt says *"pg_cron absent — the tick functions exist and
   are proven, but nothing schedules them here."* Reads still settle (D.2), so the game plays; but
   market drift and stock regeneration would never run.
3. **A screen to sign the book.** 0011 gives the server side; a signed-in captain with no house
   needs somewhere to type a name. Deliberately not built blind — it cannot be proven end-to-end
   without a project, and a founding screen that has never founded anything is not a screen.
4. **One world, many captains.** The moment the economy is shared, price impact stops being personal:
   `%NBR` and the stepped book start reflecting what other people bought this morning. That is the
   game working — and it is also the first thing that has ever needed load thinking.

---

## 2026-08-20 — D11c: I reset the owner's save, and the game never said a word

Owner: *"wait, i've bought something before and the currency went down. but after this load fix, it
was set back to original value."*

They are right, and it was my doing. **This is a regression I caused in D11b, and the save is gone.**

### What happened

D11b edited migration 0005 for speed. Editing ANY migration changes the chain fingerprint, and
`src/lib/db/localDb.ts` then does exactly what its own header has always promised:

> "if the build carries a different chain, the stored database is DEMOLISHED and rebuilt from
> migration 0001 — applying six new migrations on top of a four-migration database is how you get a
> schema that exists in no repository."

`demolish()` is `drop schema public cascade`. It takes the world **and the house standing in it** —
`players`, `fleets`, `ships`, `voyages`, `orders`, `events`, `ledger`. The purse went back to 8,000
because a brand-new house was founded on the rebuilt world.

That rule is right and it stays. Two things around it were not:

1. **It happened without a word.** `bootState` has carried a `rebuilt` flag since the day it was
   written, and `grep -rn "rebuilt" src --include=*.tsx` returned nothing outside `lib/db`: a fact
   computed and thrown away. A purse silently returning to its opening balance does not read as
   "the world was rebuilt", it reads as the game losing your money — which is how it was reported.
2. **It could not be undone.** Nothing was dumped first. `dumpDataDir`, `backup`, `restore`: no
   hits anywhere in `src/lib/db`.

And I told the owner *"your browser has the old chain cached, so your next load will rebuild once"*
without saying that a rebuild destroys the save. That sentence was the last chance to prevent this
and it did not carry the one fact that mattered.

### What is fixed

**`src/lib/db/rescue.ts`** — before `demolish()`, every row of the eight player tables is read out
and stashed in `localStorage` under `byeharu-voyage.rescued.v1`, with column names, keyed by the
fingerprint of the world it came from. It cannot throw: a missing table, an unreadable one, absent
or full storage all come back as a receipt, because this runs on the path to a rebuild the player
did not ask for and must never turn a wipe into a dead boot.

**`src/app/RebuildNotice.tsx`** — the game now says it. A standing panel (not a toast: losing a
voyage is not a thing to mention for four seconds and withdraw) that names what happened, how many
rows went, where the copy is, and why it is not put back automatically.

### What is NOT fixed, and why not pretending is the point

**The rescue does not replay the save into the new world.** Every world row is keyed by
`gen_random_uuid()`, so a rebuild gives every port, good and ship class a NEW id.
`fleets.port_id`, `voyages.from_port_id`, `ships.class_id` and a cargo row's `good_id` all point at
uuids that no longer exist. A replay has to translate each one back through its stable code
(`ports.code`, `goods.code`, `ship_classes.name`) and prove the destination table still has the same
shape. That is a real piece of work with its own proofs. THE DATA HAD TO SURVIVE BEFORE ANYTHING
COULD RESTORE IT, and that half is what shipped today.

**The owner's lost voyage is not recoverable.** It was demolished before any of this existed.

### Proved on the real path, not asserted

A Playwright run that plays the game rather than mocking it:

    1. purse after a real PROVISION : 7,925        (issued through the Command tab, 8,000 -> 7,925)
    2. migration edited (fingerprint now differs)
    3. purse after the rebuild      : (fresh house)
    4. rescued from localStorage    : {"rows":8,"tables":["players","fleets","ships","orders",
                                       "events","ledger"],"ducats":7925}
    5. notice shown to the player   : true
    6. console                      : [db] THE CHAIN HAS CHANGED ... | [db] RESCUED 8 of your
                                      row(s) from 6 table(s) before demolishing

`players.ducats = 7925` — the exact figure that was silently lost this morning is now on disk before
the demolition starts. tsc, eslint clean; `npx playwright test` 137 passed.

### Observed once and NOT explained: 0010's drift self-assert

During the proof run one boot printed:

    [db] BOOT FAILED — demolishing the half-built world and trying once from empty
    MIGRATION FAILED: 20260818000010_the_clock_ticks_for_everyone.sql
    0010 self-assert FAIL: tick_market_drift did not step all 14980 rows
    ({"drifted": 14980, "slot": 2978652, ...}), or the drift did not move (0.0000 -> 0.0000)

`drifted: 14980` shows every row WAS stepped, so it is the second clause that bit: the assert reads
one specific row (Lisboa x Salt) before and after a drift tick and requires the value to change.
`port_goods.drift` is `numeric(6,4)`, so an OU step under 0.00005 rounds to no change at all.

The boot's own one-shot retry recovered it and the game came up. I could not reproduce it: **0
failures in 8 full chain applications** — but that is WEAK EVIDENCE and should not be read as
"rare". `drift_slot_seconds` is 600, so eight runs inside two minutes sampled one or two draws, not
eight. NOT INVESTIGATED FURTHER, NOT FIXED, and not caused by D11b as far as I can tell (the D11b
rewrite was proved to produce bit-identical `port_goods`). It is written down here because it was
seen, not because it is understood.

---

## 2026-08-20 — D11b: the first load took 37 seconds, and 13 of them were one INSERT

Owner: *"the first loading takes quite a long time, why?"* Measured before answering, in a real
browser at 390x844, with every non-localhost request blocked at the network layer:

| | to a rendered PORT screen |
|---|---|
| cold — first ever visit | **37.1 s** |
| warm — second visit, same profile | 3.5 s |

The console said where it went: *"chain applied: 10 migration(s) in 34194 ms"*. **The chain is not
applied on a server. It runs in the browser, in PGlite, once per player.** A cold load downloads
15.6 MB of WebAssembly PostgreSQL (`pglite.wasm` 9.62 MB + `pglite.data` 6.00 MB) and then applies
all ten migrations for real inside it — self-asserts included. A warm load is 3.5 s because
`bootState` reuses the stored world: *"reusing the stored world: 10 migration(s)"*.

Per migration, timed on this machine:

| migration | ms | share |
|---|---|---|
| 0005 every price is derived, never stored | 16 049 | **69%** |
| 0010 the clock ticks for everyone | 4 087 | 18% |
| 0009 the world reads back | 2 643 | 11% |
| the other seven | 508 | 2% |

Split 0005 at its own SELF-ASSERT banner: the proof was 2.5 s and the **seed was 13.1 s**. It was
not the proof. It was one INSERT.

### Which half of the seed, measured rather than guessed

    as shipped (world.affinity_for() per row)                 12.4 s
    knobs read once, distance still per (port, good)          10.2 s
    knobs once + the nearest source as one set-based pass     10.0 s
  * knobs once + a port x source-port distance matrix          3.8 s

The config knobs were never the cost. **The distance was.** Asked per (port, good), the
nearest-source subquery evaluates the great circle once per specialty row of that good: 214 ports x
834 specialty rows = **178,476 haversines**. But a distance does not depend on the GOOD at all.
Computed once per (port, source-port) pair it is 214 x 214 = **45,796**, and the per-good answer is
a `min` over that matrix through the authored fact. Nearly 4x fewer; 3.3x faster on the clock.

(`public.wc_num` is `security definer`, so PostgreSQL can never inline it — the five knobs per row
were ~150,000 function invocations. Real, and the smaller half: 2.2 s of the 12.4.)

### The fix, without a second economy

0005's own comment warned that *"a formula that lived only inside an INSERT could not be re-run
without copying it, and a copied formula is how two economies get born."* That law stands, so the
set-based seed does **not** restate the formula. The formula was extracted instead:

- **`world.affinity_at(is_producer, nearest_nm, producer, home, span, reach, curve)`** — the
  arithmetic and nothing else. Every input is an argument, so it is `immutable` with no
  `security definer`, which is exactly what lets PostgreSQL inline it. 14,980 calls now cost nothing.
- **`world.affinity_for(port, good)`** — unchanged signature, still the shape the balance tuner and
  any re-derivation ask for. It reads the knobs, finds the nearest source, and defers.
- **the seed** — knobs in a CTE, the port x source-port distance matrix in a second CTE, then the
  same `world.affinity_at()`.

One formula. Two callers. Neither restates it.

### Proved identical, not assumed identical

The whole chain was applied before and after and all 14,980 `port_goods` rows — affinity, stock,
stock_target, production_rate, ordered by port and good — hashed:

    before  sha256 328de64e8c263b835f38ec2ab1846d84ca1f208a97d7d59018448d96aba5d0ef
    after   sha256 328de64e8c263b835f38ec2ab1846d84ca1f208a97d7d59018448d96aba5d0ef

`npm run db:proof` 31/31 PASS, including `BALANCE_MEDIAN_IN_BAND` (median first voyage 7.4%, band
4.0-16.0) and `BALANCE_DISTANCE_PAYS`. `npx playwright test` 137 passed. tsc and eslint clean.

### Result

| | before | after |
|---|---|---|
| migration 0005 | 16.0 s | **7.9 s** |
| whole chain (node) | 23.3 s | **15.3 s** |
| chain in the browser | 34.2 s | **15.0 s** |
| **cold first load** | **37.1 s** | **17.6 s** |
| warm load | 3.5 s | 3.3 s |

### And the answer to the question before it

The game needs **no internet**. Both boot runs above ran with every non-localhost request aborted at
the network layer: **0 external requests**, game fully playable. No Supabase (`hasCloud` is false
with no `.env.local`, so `initRpc()` picks the local PGlite engine), no CDN, fonts self-hosted via
`@fontsource` and bundled. Only `npm install` and `git push` need the network.

Still on the table, not done: 0010 (4.1 s) and 0009 (2.6 s) are now 43% of the chain between them,
and the 15.6 MB PGlite payload is a one-time download that would dominate a first visit over a real
network rather than over localhost.

---

## 2026-08-20 — D11: too many words, so the words went behind a dot

Owner, looking at the running game: *"too much word. Make icons, make them tappable, then show info
explaining."*

### What was measured, before anything was changed

Every tab screenshotted at 390x844, full page, and its visible text counted:

| tab | words |
|---|---|
| PORT | 713 |
| MARKET | 766 |
| FLEETS | 235 |
| COMMAND | 194 |
| LEDGER | 106 |

The top of PORT was three numbers wearing seventy words of footnote — `Market tax 3.0%` followed by
*"set by the Mayor, banded 0–8%. Tax relief is not in the V0 chain, so what you pay is what is
printed."*, then `Spread 2.6%` followed by another. Every figure in the game came with a permanent
paragraph defending it.

The prose was not wrong. It is what makes the game legible the first time you meet it, and it is
worthless on the two-hundredth reading — by which point it is the thing standing between the player
and the number.

### The one authority: `Explain`

`src/components/ui/Explain.tsx` (+ `explainState.ts` for the hook, the same split
Collapsible/collapsibleState already uses). An `ExplainDot` — a real inline `<button>` carrying the
`info` glyph, `aria-expanded` + `aria-controls` — and an `ExplainPanel` that mounts only while open.
`<Explain>` wires the pair for the common case; PageHeader and CardHeader compose the parts because
their dot rides the heading and their panel drops below it.

Where the line falls against the fold we already had, written into the file:

- **Collapsible** — folds content the player came for. Full-width header, persisted, open by default.
- **Explain** — folds the standing explanation *of* content. Inline dot, ephemeral, always closed.

**IT DRAWS AT 28px AND IS TAPPED AT 44px.** `navTabs.ts` sets this app's floor at 44px; a dot that
cleared it visually would be a blot beside a 13px figure, and there are eleven on PORT. So the
circle is 28×28 and the hit area is an invisible `::before` inflated 8px on every side. It also
carries `z-20`, and that is part of the target rather than decoration: measured on FLEETS, the
sticky table header (`z-10`, tableLayout.ts) took the bottom half of the Ships dot and left a 44×22.

The panel is a `<span class="block">`, not a `<div>`: it opens inside `<p>`, inside `<h3>` and inside
`<dd>`, and a div is invalid in the first two. React said so out loud until it was a span.

### The prop that was carrying two different things

`subtitle` was doing two jobs, and only one of them belonged on the screen by default:

    Port · Lisbon                              Fleets
    Portugal · latin · North Atlantic Ocean    What you own, and the state it is in.
    ^ LIVE — the harbour you are reading       ^ STANDING — true on every visit, forever

So `PageHeader` and `CardHeader` now take **both**: `subtitle` stays printed (live subject, status,
or the disclosure of a tap affordance the player could not otherwise find), and `explain` goes
behind the dot. Each of the 25 call sites was sorted by hand rather than by rule.

### What may never go behind a dot

Written into Explain.tsx so it survives the next sweep: live data, a refusal sentence and its fixes,
and any hint disclosing an affordance that is otherwise invisible. `TABLE_SCROLL_HINT` ("Swipe the
table sideways…") and "Tap a fleet to command it." are still printed, on purpose — hiding those is
hiding the game, not tidying it.

### After

| tab | before | after |
|---|---|---|
| PORT | 713 | 557 |
| MARKET | 766 | 623 |
| FLEETS | 235 | **123** |
| COMMAND | 194 | **122** |
| LEDGER | 106 | 98 |

PORT and MARKET stay high because most of what remains is *data* — 70 priced goods, 214 port chips —
which is the screen doing its job. The prose walls are gone from all five.

### Proved in a browser, not asserted

A Playwright pass at 390×844 walks **every dot on every tab**: 25 dots, 25 opened and showed real
text and closed again, 0 failures. All 25 clear 44×44 at all four corners (`elementFromPoint` at
centre ±21px). No page ever scrolls sideways (390/390). Zero console errors — the invalid-nesting
warning that the first draft produced is gone.

`tsc -b` and `eslint .` clean; `npx playwright test` 137 passed / 6 skipped; `layout.spec.ts`
11 passed.

**Pre-existing red, NOT caused by this work:** `MARKET puts a complete price row above the fold`
fails with *"only 0 complete price rows above the fold at 731px"*. Verified by stashing this change,
rebuilding and re-running: `main` fails identically. The failure screenshot shows the page still on
"Opening the world." — `waitForLoadState('networkidle')` returns long before PGlite has applied the
chain (~15s), so the test measures a skeleton. It is a harness timing gap, not a layout defect.

**Also noted, environment:** `vite preview` binds `[::1]` only on this machine, while
playwright.config.ts defaults to `127.0.0.1` — the layout specs silently SKIP unless run with
`PLAYWRIGHT_BASE_URL=http://localhost:4173/byeharu-voyage/`.

---

## 2026-08-19 — D10: the picker that lied, and an economy that printed money

Two owner-reported defects, both found by looking at the running game rather than at a test.

### The MAX chip offered more than the purse could carry

The quantity picker's MAX read **91 tuns of pepper**; issuing it was refused with *"91 tuns of Black
Pepper cost 8130 d. and you hold 8000"*. The game contradicting its own control.

The client was dividing the purse by the market's opening ask — and `features/command/fleetLimits
.ts` said so in its own comment: *"a real BUY reprices as it walks the book (G.1), so the true
ceiling is a little lower."* A known-wrong number in a control that presents itself as exact.

**The same bug was in the server, and worse.** `cmd.resolve_qty` resolved buy-side `ALL` from the
FREE HOLD alone, so `BUY salt ALL` filled the hold and was then refused for want of money. Two
places computing a maximum, both ignoring the price.

One answer now: **`public.fleet_buy_capacity(fleet, good)`** walks down through `world.quote()` —
the same stepped quote a committed trade uses — and returns `{max_qty, est_total, bound_by}` where
`bound_by` is *hold* · *stock* · *daily cap* · *purse*. `ALL` means it, and `world.buy_capacity()`
serves it to the picker, which now reads:

> **MAX 50** — *up to 50 t — your purse stops you there (6,659 d. for all of it)*

Asserted at BOTH edges in 0007: affordable at the number offered, and NOT affordable one tun above
it. One edge alone would pass a function that always answered "one".

It steps down in trade steps until the last stretch, then **one tun at a time** — a pure ten-step
walk answers "0" for anything dearer than ~800 d./tun, and she can afford two diamonds.

### A first voyage returned a third of the stake

Measured across two dozen starting ports (`scripts/db/measure-first-voyage.mjs`, new): **median
33.7%, best 65.6%**, on round trips of about twenty-five real minutes. The purse doubled in two
voyages, before the player had seen the map. That is not a trading game.

The gradient was too steep between NEIGHBOURS: affinity ran 0.60 at a producer against up to 2.35 a
few hundred miles away, a price ratio near 2× for a leg you can sail in a coffee break.

The rule is now five knobs in `world_config` and ONE function, `world.affinity_for()`, which the
seed and the tuner both call — so a sweep cannot drift from the game:

```
prod 0.60 home 0.85 span 1.50 reach 6000 curve 1.00   median 32.3%   <- what shipped
prod 0.88 home 0.97 span 0.90 reach 8000 curve 0.70   median 11.5%
prod 0.90 home 0.98 span 0.88 reach 8000 curve 0.75   median  8.8%   <- chosen
prod 0.92 home 0.99 span 0.85 reach 9000 curve 0.80   median  6.0%
```

`scripts/db/tune-balance.mjs` (new) prints that table by re-deriving all 14,980 affinities per
candidate and replaying the best opening voyage. **Balance is a measurement now, not an opinion.**

What the chosen row buys, measured after the fact:

```
Barcelona    164 nm  coral         3.0%     Callao      1311 nm  cacao   12.8%
Antwerp      118 nm  diamonds      5.8%     Copenhagen  2004 nm  amber   13.3%
Bordeaux     500 nm  indigo        8.8%     Cartagena   1027 nm  diamonds 19.0%
```

**Distance is what pays** — which is the entire reason the world is 214 ports wide. The first
session proof now reads +9.41% on the stake.

`scripts/db/proofs/05_first_voyage_balance.sql` (new) holds all three claims: every sampled port
offers a voyage that pays, the median sits in a 4–16% band, and long legs out-earn short ones. If
it goes red, run the sweep and read the table — do not nudge a constant until the red goes away.

### Green

```
db:apply   10 migrations, 10 receipts     db:proof   5 files, 31/31 markers
playwright 137 passed / 6 skipped         tsc · eslint · vite build all clean
```

---

## 2026-08-19 — D9: the world became the real world, and three assumptions died with it

**The owner's correction, verbatim:** *"not typing, but making commands. i told you it will be
real world, not a imaginary places. wtf."*

Two separate defects, both mine, both structural rather than cosmetic.

### The world was twelve toy ports

`data/ports.json` has held **214 real harbours across 97 countries since day zero**, every
coordinate a Wikidata P625 item — and the chain seeded **twelve**, around Iberia. The owner opened
the game and saw a made-up world, because that is what was in the database. The data being right
in a JSON file nobody plays is not the world being right.

**Migration 0003 is now generated from the data**, by `scripts/build-world-seed.mjs`: 214 ports,
782 legs, 70 goods, 51 seas, 25 regions, 20 nations, 834 specialty rows — 115 KB of SQL that
applies in **0.1 s** and self-asserts every claim it makes. The generator's header states every
derivation rule (size tier, draft, yards, development, culture, which 1550 power held a port), so
the world can be re-derived rather than re-typed.

### The legs could not be authored, so they are DERIVED FROM THE SEA

Twenty-two hand-curated edges scaled to twelve ports. Twenty-two thousand candidate pairs do not.
The first attempt asked "does the straight line between these two ports stay at sea?" — and got a
world where **Lisbon and Cádiz had no leg at all**, because the straight line clips the Algarve.
That is the wrong question: ships round Cape St Vincent.

So `scripts/sea-grid.mjs` rasterises the Natural Earth land polygons into a **0.25° water grid**
and a route is an **A\* search through water cells**, straightened by line-of-sight. What comes out
is the real geography of the age, and nothing in the generator encodes any of it:

```
Lisbon → Cádiz          248 nm  (the straight line is 188; the cape is in the way)
Alexandria → Aden    10,944 nm  round the Cape — there is no Suez until 1869
Veracruz → Acapulco  10,860 nm  round the Horn — there is no Panama until 1914
Guam → Honolulu → Acapulco     the Manila galleon, appearing on its own as an ocean crossing
```

**782 legs, one connected world, mean sailed/straight ratio 1.16×.** Both canal controls are
printed on every run, because a generator that quietly starts digging Suez is worse than one that
fails. Fifteen named CHANNELS are authored — the Sound, the Bosphorus, Bab-el-Mandeb, Hormuz,
Malacca, the Cape road, Cape Horn, the St Lawrence — because those waters are narrower than the
map's own resolution; that list is the whole of the game's "you may pass here" authority.

### The prices could not be authored either

§G.1 calls affinity "the authored soul of the world", and with 12 ports it was a hand-typed
12×12 matrix. 214 × 70 is **14,980 cells**, and a hand-typed 14,980-cell matrix is not authorship,
it is noise nobody can check. So ONE editorial fact is authored — **which ports produce which
good**, in the new `public.port_specialties` table, sourced in `docs/WORLD_DATA.md` — and 0005
derives every affinity from it by one rule:

> a port that produces the good sells it at 0.60; everywhere else pays
> `0.85 + 1.50 × min(1, nearest source / 6000 nm)`.

That is the age of sail in one line: pepper is cheap in Malabar and dear in Lisbon because Lisbon
is nine thousand miles from the nearest vine, and the whole voyage exists to close that gap.

### THE ROUTER: 1,811 seconds → 0.1 seconds

`voyage.route_direct` enumerated every simple path and took the cheapest. Its own comment said why
that was fine: *"The V0 graph is 12 nodes and 22 undirected edges."* On 214 nodes of mean degree 7
it took **thirty minutes** — measured, in the apply log, not guessed. Replaced with Dijkstra
(O(n²) scan, edges laid out by source with a start index). Same answers, in milliseconds.

### THE HALT RULE WAS HALF-IMPLEMENTED, and a probe found it

§F.3 says a queue "halts at a failure — it never skips". `cmd.advance` did stop at a failure...
within one call. The next arrival called `advance()` again, found the failed order was no longer
`pending`, and ran the one behind it. That is skipping, on a delay. It surfaced as a queue reading
`[1:failed E_HOLD_FULL 2:done 3:pending 4:pending]` in a probe that was only meant to be checking
something else.

Fixed: a failed order now blocks the fleet until it is cleared — and `cmd.clear` was widened to
release it, because a halt with no release is the **empty-fleet deadlock** that cost the previous
game a live incident. Both halves are asserted, in the two files that own them.

### Every seed-shaped assertion in the chain, fixed in one pass

The rule from the previous project: *a test that asserts a seed asserts a WORLD.* The chain was
full of them, and the real world set them all off at once. They were rewritten to **assert the
rule and find their own subject**, never to name a cargo or a distance:

| was | is now |
|---|---|
| `port_goods rows = 144` | `= (count of ports) × (count of goods)` |
| `snapshot has 12 ports / 22 legs` | `= what the tables actually hold` |
| `tick_market_drift stepped 144 rows` | `= count(port_goods)` |
| "Lisboa→Cádiz is 188 nm, 1.6 days, 4.7 min" | days = nm/kn/24 and real = voyage/compression, on whatever leg the world has |
| "buy sal at Lisboa, sell at Cádiz" (0007, proof 4) | **find** the best one-leg trade a starter can afford, then play it |
| `"s" is ambiguous, naming Safi and Sevilla` | it refuses, says E_AMBIGUOUS, and lists more than one |

**Proof 4 — the product proof — now reads:** black pepper at Lisbon, 62.6% of its neighbours,
sold at Ponta Delgada 781 nm out, wheat carried home: **+2,763 ducats on a 7,925 stake, 34.9%**,
every order running unattended with no tick. (That return is high for an opening voyage; a
balance pass belongs on the list, and it is a balance question, not a correctness one.)

### Green, and what it costs

```
npm run db:apply    10 migrations, 10 self-assert receipts,  ~13 s
npm run db:proof    4 files, 28/28 PASS markers
```

The chain applies **in the browser on first boot**, so that 13 s is a real cost the player pays
once. 0010's drift soak came down from 15.1 s to 2.9 s by scoping the forced slots to a sample of
twenty ports and saying so out loud. 0005's remaining 7.9 s is 14,980 real `world.price()` calls —
the full sweep is kept deliberately, because "every price in the world is sane" is worth eight
seconds and a sampled version would not be the same claim.

### Still open from this entry

- **The Command tab is still a typing prompt.** The owner's first correction. Being rebuilt as a
  composer: pick fleet → verb → real options, previewed on the server, issued as the same string.
- The five screens are still on fixtures; `src/live/worldStore.ts` is the seam they move onto.
- Cold boot is ~15 s (2.2 s WASM + ~13 s chain). A prebuilt database image would remove almost all
  of it and is the obvious next optimisation.

---

## 2026-08-18 — D8: a blind local gate, and then an assert that could never pass

Two failures, one after the other, and the second is the more interesting one.

### Round 1 — the local gate was blind

CI's `disposable-chain` job — the one that boots a real Supabase in Docker — failed applying
migration **0001**, on 0001's own self-assert, three runs running (`8d1956e`, `27bcb58`, `0836c31`):

```
ERROR: 0001 self-assert FAIL: 16 default ACL entr(ies) would grant a client role a
       write/execute on future objects (SQLSTATE P0001)
```

`npm run db:apply` and `npm run db:proof` were **green on this machine** the whole time, because
`scripts/db/apply-chain.mjs` boots a **bare PGlite**: no `anon`, no `authenticated`, and **no
`ALTER DEFAULT PRIVILEGES` entries of any kind**. 0001's lockdown had nothing to revoke and its
assert had nothing to find. It passed **vacuously** — and so did every other grant / default-ACL /
role-dependent assert in the chain. A green run over an empty starting state is not a proof.

Fix: **`scripts/db/supabase-preamble.sql`**, a **test fixture, never a migration**, applied by
`apply-chain.mjs` before 0001. It creates the Supabase roles and installs the default privileges a
real project ships, **under a grantor that is not the role applying the chain** — which is the
entire mechanism. It lives in `scripts/`, so the Supabase CLI (which only reads
`supabase/migrations/`) cannot deploy it. The harness refuses to run without it, and refuses to run
if it stops printing its own receipt. With it in place, the unfixed 0001 failed locally with CI's
message character for character.

### Round 2 — the assert was over-broad, and unsatisfiable on the real thing

The first fix made 0001 revoke the defaults of **every grantor `pg_default_acl` names**. CI then
failed with the message that fix was written to produce (run `32122434872`):

```
ERROR: 0001: cannot clear the default privileges held by grantor supabase_admin in schema public
       (object type S). The role applying this migration is postgres, which is not a member of
       supabase_admin, so ALTER DEFAULT PRIVILEGES FOR ROLE is refused.
```

So the grantor was `supabase_admin` and **the revoke is genuinely impossible from the migration
role.** The assert as written could never pass on a real Supabase project.

**The assert was wrong.** Stated plainly, and argued before changing, because that is the rule.
The governing fact — verified by running it, not by reasoning about it:

> **A `pg_default_acl` row applies ONLY to objects created by its own grantor.**

Measured on PostgreSQL 18.3 with all 16 entries in place and 0001 §5a applied:

```
create table public.t_by_postgres        ->  owner postgres        relacl = null            (no client privilege)
create table public.t_by_supabase_admin  ->  owner supabase_admin  anon + authenticated get
                                             INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, SELECT
```

Same split for sequences and functions. `supabase_admin`'s defaults cannot reach an object this
game owns. The assert was demanding control over something the migration cannot control **and**
that does not threaten it — a permanently blocked deploy, which is really just sustained pressure
to delete the check.

**0001 restructured to assert what it can actually guarantee:**

* **(d)** — default ACLs **owned by the role applying the chain** are clean. Kept and narrowed to
  this; these are the ones that decide every object the chain creates. Real protection, unchanged
  in force.
* **(d2)** — foreign grantors' defaults are a permanent **`NOTICE` on every apply**, naming the
  grantor and object types. Never swallowed, never fatal.
* **(i) — NEW, and it is what pays for the narrowing.** Every table, sequence, view and function in
  all four schemas is **owned by the role applying the chain**, so none can have inherited a foreign
  grantor's defaults. That turns (d2)'s un-revokable entries from an unprovable claim into an
  irrelevant one, which is the honest position. Positive control: the same authority
  (`public.objects_not_owned_by()`) asked about a role that owns nothing must return rows — a
  control that needs no privileges, which matters because the migration role on Supabase is not a
  superuser and cannot manufacture a violation to test with.
* Proof 03 gained an **eighth marker**, `GRANT_LOCKDOWN_CHAIN_OWNS_EVERYTHING`, so the ownership law
  is checked at **end of chain** — and CI re-runs proof 03 against the disposable Supabase, which is
  the only place it meets the platform's real roles. The workflow also re-checks both claims with
  raw catalogue queries, independent of the chain's own authorities.

**§5b deliberately does not even attempt the foreign revoke.** It would succeed here (the harness
runs as a superuser) and fail there, putting the cheap gate and CI back on different code paths —
the original defect of this whole episode.

Nothing is deployed anywhere, so **0001 was amended in place; no 0011 patch.** Forward-only starts
when the chain goes live.

**A defect found by firing the error paths instead of trusting them.** Both new failure branches
were run deliberately on PGlite. The first raised `operator is not unique: text || "char"` instead
of its own message — `pg_default_acl.defaclobjtype` is `"char"` and needs an explicit `::text`. An
error path that has never been fired is not known to work.

### What this actually taught, which is subtler than round 1

Round 1's lesson was the obvious one: *CI catches a class of defect the local gate cannot see.*
Round 2's is sharper and worth more:

> **A local gate that models a hostile starting state can produce an assert that is unsatisfiable
> on the real thing.** The preamble was right to exist — without it the defect was invisible. Its
> first assert was wrong, because "reproduce the hostile state" is not the same as "reproduce what
> the migration role is *permitted to do about it*". PGlite runs as a superuser; Supabase's
> `postgres` is not one and is not a member of `supabase_admin`. A fixture that models the
> environment but not the **authority** will happily let you write a check that passes locally and
> can never pass in production.

The general rule this leaves behind: **assert the thing you own, and prove the thing you don't own
cannot reach you.** Not: assert that the platform is shaped the way you would have shaped it.

---

## 2026-08-18 — DAY ZERO: the pivot, and the founding decisions

**The owner's request, verbatim:**

> "since the combat system, visually and code-wise are not working properly. Therefore i want this
> game to turn into a wording, strategical game, where most of the game played on tabs and commands
> made on a separate tab, and i can follow where my fleets are through map - only visually see where
> it is going and where it is. It is going to be a new game, we will use byeharu core to make a new
> byeharu. This time you will have to make a world map, add real countries, cities, especially
> harbour - sea related cities. It is going to be uncharted island origin (mobile game), similar, but
> will have multiple ships (fleet) to be controlled, invest in cities, rank, etc."

### D1 — A new repository, not a branch of `byeharu`

`byeharu` is a **live multiplayer game** with real players on it and **333 applied migrations**
carrying a space-strategy schema, a spatial-combat engine, and a world editor. Grafting an
age-of-sail trading game onto that chain would be spaghetti by the owner's own law: two games, one
schema, one authority per concept violated on day one.

So: **`byeharu-voyage` is a new repository with a new migration chain that starts at 0001.**
`byeharu` is left running and untouched. What crosses over is the **core** — the stack, the shell,
the auth, and above all the *discipline* (server-authoritative RPCs, self-asserting migrations,
CI apply-proof) — not the schema and not the combat code.

Repo: `https://github.com/gkwngns714-spec/byeharu-voyage` (private).
Local: `C:\Users\디폴리스\byeharu-voyage`.

### D2 — The checkout is LF-only, from the first commit

`byeharu` was bitten by CRLF baking `\r` into sliced SQL so it could never match
`pg_get_functiondef` output, failing production deploys. This repo sets `core.autocrlf=false` and
ships a `.gitattributes` with `* text=auto eol=lf` / `*.sql text eol=lf` **before any SQL exists**,
so that class of bug cannot be born here.

### D3 — Combat is not "fixed later". It is designed out.

The visual combat layer is the thing that failed, visually and in code. This game has **no
battlefield**. Risk at sea (pirates, storms, disease) is a **server-resolved number** reported to
the player as a written after-action report on a log tab. There is no scene to render, so there is
no scene to break.

### D4 — The map is an output device

The map tab shows where fleets are and where they are heading. It **never accepts an order**.
All orders are composed on the Command tab. This is the owner's brief taken literally, and it is
also what makes the game cheap to build and impossible to break with a rendering bug.

### D5 — Database: unblocked, deliberately deferred

Verified on this machine (2026-08-18): the Supabase CLI at
`C:\Users\디폴리스\supabase-cli\supabase.exe` (v2.101.0) **is already authenticated** — it lists the
owner's `byeharu` and `aqua-chronicles` projects. So creating the new project needs no action from
the owner. It is deferred until the first migrations exist, so the project is created against a real
schema rather than an empty one.

There is **no Docker on this machine**, so `supabase start` cannot run locally. As in `byeharu`,
**the real migration chain is proven in GitHub Actions CI**, which does have Docker. That remains
the net.

### D6 — The migration chain runs LOCALLY, on real Postgres, with no Docker

`byeharu`'s single worst handicap is written into its own operating notes: *"SQL migrations can NOT be
run locally — no Docker / Supabase CLI / psql on this machine."* Every SQL mistake there costs a push
and a CI round-trip.

That handicap is **not inherited**. Proven on this machine today, not assumed:

```
VERSION: PostgreSQL 18.3 (PGlite 0.5.5) on wasm32-unknown-linux-gnu
PLPGSQL RESULT: Lisbon->Malacca = 6310.0 nautical miles
RAISE works: unknown port
```

That is a real `plpgsql` function with `SELECT ... INTO`, a `RAISE EXCEPTION`, and haversine maths,
compiled and executed in-process by PGlite — the same package `byeharu` already ships, but used there
only as a parser. So the chain gets proven in **three** places, in this order:

1. **PGlite, locally** — the whole chain applied to real Postgres before a single push. New. Fast.
2. **Disposable Supabase in GitHub Actions** — the apply-proof, exactly as in `byeharu`. Still the net.
3. **Supabase cloud** — production.

Because layer 1 exists, a migration should never reach layer 2 red.

### D7 — Supabase cloud slots are full; production is deferred, development is not

Attempted today, real output:

> `Unexpected error creating project: The following organization members have reached their maximum
> limits for the number of active free projects within organizations where they are an administrator
> or owner: gkwngns714-spec (2 project limit).`

Both free slots are taken by `byeharu` (Singapore) and `aqua-chronicles` (Seoul). A third free project
cannot be created while both are active.

This blocks **nothing** right now: V0 is built and played against layer 1 (PGlite), with the identical
SQL. The cloud project is needed only when the game goes online for other players. When that moment
comes it needs one of: pausing `aqua-chronicles` from the Supabase dashboard (reversible), or upgrading
the `byeharu` org to Pro. That is the owner's call and is not urgent yet — it is recorded here so it is
not a surprise later.

### Work dispatched today

Three foundation agents, on disjoint file domains:

| # | Agent | Writes |
|---|-------|--------|
| 1 | Core reuse audit of `byeharu` | `docs/CORE_REUSE.md` |
| 2 | Real-world port / region / goods dataset | `data/*.json`, `docs/WORLD_DATA.md` |
| 3 | Game design, grounded in Uncharted Waters Origin research | `docs/DESIGN.md`, `docs/DESIGN_RESEARCH.md` |
