# CMD — orders are MADE, not typed

`DESIGN.md` §E.1 and §F are the specification. This file records what was built, what was deleted,
and the handful of decisions a future reader could otherwise mistake for an accident.

**The correction that shaped this tab (the owner, 2026-08-19): _"not typing, but making commands."_**
The order input is gone. It is not hidden behind a toggle and there is no "advanced" mode that
brings it back — a second way in would be a second way for the two paths to drift.

---

## 1. The flow, in order

| step | what the player does | where the options come from |
|---|---|---|
| **1. Commanding** | taps a fleet chip | `world.fleets()` — name, where she lies or is bound, queue depth, whether she is HALTED |
| **2. What she is to do** | taps a verb | `world.snapshot().verbs` — the server's own `cmd.verb_schema()`. Nothing on this side lists verbs. The card prints the verb, its mark and `spec.help` (one line); `spec.note` — the fine print 0021 split out of it — is behind the ⓘ and never on the card |
| **3. Each argument** | taps a row, a chip, or drags a stepper | one picker per argument TYPE the schema declares (below) |
| **3b. (BUY · HIRE · REPAIR · PROVISION) her state** | reads it | the fleet rail — the room, the crew, the hulls or the stores, whichever the verb is a decision about (§9) |
| **3b'. (SAIL) where she is** | reads it | the same rail slot, carrying a CHART instead: her berth, the harbour this order would send her to, and the sea lanes between them (§11) |
| **3c. (BUY only) a bargain** | taps *Haggle* | `cmd.haggle` / `world.haggle_state` — one finite, server-rolled attempt at the port's cut (§10) |
| **4. What will be sent** | reads it | the line assembles itself, read-only, as the picks land |
| **5. Preview** | reads the estimate, or the refusal | `cmd.preview()` — the REAL verb, run and rolled back |
| **6. Issue** | one button | `cmd.issue(fleet_id, text, expected_version)` |
| **7. Her queue** | cancels a row, or clears the halt | `fleet.queue`, `cmd.cancel()`, `cmd.clear()` |

Every argument picker offers what actually exists **now**:

* **port** — the snapshot's ports, ones a single authored leg away first and ordered by the leg's
  own sailed `nm`; everything else has no direct leg, so it prints a dash and is grouped by region
  rather than ranked by a great circle no ship sails. A filter narrows the list, which **caps at
  twelve rows** because the world is 214 harbours and no sort can put the one you mean near the top.
* **good** — the goods in *this port's* market, with ask, bid, %NBR against the ports within
  600 nm, the stock band and the server's own buy/hold/sell advice. SELL offers only what is
  aboard. **Every good the port trades is listed** — no cap (the owner, 2026-08-22: *"i want all
  the trade goods on left side"*) — sorted by the server's advice, with the count stated above the
  list and the filter still there to reach one by name. **A row UNFOLDS to be read** (the owner,
  2026-08-23: *"click a trade good → it unfolds showing how much I can buy, and more"*): one row at
  a time, opening is looking, and inside it are `world.buy_capacity()`'s ceiling, total and the
  server's phrase for what stops her, and the stock figures behind the row's meter. **The BUY and
  SELL price cells are the trade itself** (the owner, 2026-08-23: *"i want to be able to click on
  buy and sell itself and do trades"*): tapping a cell names the verb AND the good on the one
  draft, and the composer's own derivation then unfolds the quantity step — the `Choose <good>`
  button the fold used to carry was deleted with that change, because two ways to pick one good is
  two authorities for the pick. A sell cell for a good she carries none of is disabled and says
  why (“none aboard”). The fold's “where it pays more” block — `world.trade_routes()` — was
  removed by the owner's instruction (2026-08-23: *"where it pays more does not need to be given
  in buy"*); the comparison lives on the Market tab, which still reads 0019. **SELL's fold has no
  capacity block at all** — what is aboard is already on the row and again in the stepper's
  caption, and a third rendering was the copy to delete.
* **qty** — ALL / HALF / MAX and a stepper that walks in `config.trade_step_tuns`, bounded by the
  hold, the stock and the purse, and captioned with **which** of those stops you there. What that
  quantity would COST is not on the caption; the rail says it (§9).
* **number** — HIRE is bounded by empty berths, REPAIR starts above her present hull, PROVISION
  offers days. No free-form number field exists on this screen. **HIRE's and PROVISION's argument
  rows do not fold** (the owner, 2026-08-23: *"when pressing hire, 12, it unfolds. this is
  uncomfortable"* / *"Provision also"*): each is one number, the picker is simply there, and
  answering never collapses it — the fold is BUY's, where it informs a choice among seventy.
* **enum / price** — the schema's own words; a limit is offered around the market's price.

## 2. The string is still the one contract

F.4: *"Submit sends the string, not a structured object. There is exactly one parser."* The
composer holds an intent while it is being made, and `orderText.ts` turns it into the exact line at
issue time. That line is displayed while it writes itself, which is how a player learns the
language without ever being made to spell it.

`orderText.ts` encodes three facts about how `cmd.parse()` (migration 0008) **reads** a line — not a
grammar, but the things a player would otherwise discover by collecting `E_PARSE`:

1. A leading fleet name is consumed only by SAIL / PROVISION / HIRE / REPAIR, and only in first
   position — so a fleet is written only where the schema lists it first.
2. **BUY and SELL take no fleet at all**: their branch skips FOR/FROM as noise and then demands a
   number, so `BUY sal 50 FOR Gaivota` is a parse error. The fleet travels as `cmd.issue()`'s own
   `fleet_id`, which is where it belongs.
3. Ports and goods are emitted as **codes** (`CAD`, `black-pepper`): `cmd.resolve_port/good` match a
   code exactly, and "Banda Aceh" is two tokens to a parser that splits on whitespace.

**Proven, not assumed (2026-08-19).** Every line the composer can emit was run through
`cmd.preview()` on the real chain in PGlite — SAIL, SAIL … VIA, BUY n, BUY ALL, BUY … AT <=n, SELL
ALL, PROVISION FULL, PROVISION n DAYS, HIRE n, REPAIR … TO n, CANCEL n, CLEAR, CLEAR ALL. All
thirteen parsed; the only refusals were state refusals (`E_NO_CARGO`, `E_UNAVAILABLE`), which is the
game working.

## 3. What was deleted, and why

| gone | why |
|---|---|
| the order input, `CheckBlock.tsx`, `TapBuilder.tsx` | the typing path. The owner said orders are made |
| `validate.ts` (838 lines) | a second authority for "is this order legal". `cmd.preview()` runs the real verb in a subtransaction and rolls it back, so the estimate and the commit cannot disagree — and a client that also judges legality can only ever drift from it |
| `parse.ts`, `grammar.ts`, `errors.ts` | a client-side parser, verb table and error catalogue with nothing left to parse. The grammar is served by `cmd.verb_schema()`; the sentences come with the refusal |
| `tests/commandGrammar.spec.ts` | it tested exactly those four modules. `tests/rpc.surface.spec.ts` and `tests/rpc.firstSession.spec.ts` exercise the real parser, which is the one that decides |
| `worldModel.ts`, `geo.ts` | the fixture read model and a second haversine. `src/lib/geo` is the one geography authority and `src/live/worldStore.ts` is the one world |
| `src/fixtures/` | orphaned the moment the last screen left it. Nothing imported it |

## 4. CANCEL and CLEAR are made on the queue

They are two of the eight verbs the server serves, and their only argument is a row of the queue —
so they are composed **where that row is**, by tapping it, and the composer's verb strip shows the
other six. That is one way to cancel and one way to clear, rather than a queue button and a
composer flow that do the same job. Both reach the same `cmd.cancel_at()` / `cmd.clear()`.

## 5. The hand-off from other tabs

`commandDraft.ts` is the one authority for "the order being made", and MARKET / PORT / FLEETS write
into it. On 2026-08-19 it changed from a half-typed **string** to a structured **intent** (fleet +
verb + a value per argument NAME, as the server's schema names them). The file's header carries the
before/after for every caller; `features/market/handOff.ts` is the market's whole side of that seam.

## 6. Refusals

A refusal is data (F.5): a code as a small mono badge, the **sentence** as the thing the player
reads, and every `fix` as a tappable option. Tapping a fix loads that corrected order into the
composer — arguments the fix leaves as `<placeholders>` are simply left unanswered, and their picker
opens. A fix that is a queue control (`CLEAR Gaivota`) acts on the queue; one that is not an order
at all (`(reload and try again)`) is rendered as words, with no button that would lie.

## 7. Reach law

`CORE_REUSE.md` §1.5: **"An action may never live inside a region that can scroll or clip it."**

Nothing on this tab has a `max-h` or an `overflow`; the page's own scroll is the only one. The
**port** list truncates at twelve rows and says how many the filter is hiding, rather than putting
them inside a scroll box — the rows on screen are whole and pressable, and the hidden ones are
honest about being hidden. The **goods** list hides nothing at all (§1).

The fleet rail is `md:sticky`, and a sticky panel taller than the viewport pins its top and leaves
its foot unreachable. That is why the rail carries **no control of any kind** — only figures.
Anything tappable belongs in the working pane, which is never sticky, never capped and never
scrolled.

**A good row obeys the same law.** Its buy and sell price cells are ACTIONS (they are the trade
itself, §1 under **good**), and the fold they open into the quantity step has no `max-h` and no
`overflow` of its own. It simply makes the page longer; the page's scroll is still the only one on
the tab (`ArgPickers.tsx`'s `GoodFigures` and `GoodDetail`).

## 8. Time

Nothing here ticks. A read is the catch-up (D.2): `Read again` refetches, issuing refetches, and an
ETA is counted from `readAt` — the instant the world was last read — rather than from the wall clock
during a render.

## 9. The fleet rail — one panel, four verbs

*(SAIL takes the same rail SLOT and puts a chart in it — see §11. `railVerbs.ts` holds one list per
kind of rail, so "does this verb split into two columns" and "what is the rail about" are one fact
each rather than one boolean doing both jobs.)*

The owner, 2026-08-22: *"When buy, i want all the trade goods on left side, and my fleet info on the
right side, showing how much room, how much negotiation can be done, and so on."*
The owner, 2026-08-23: *"hire, repair, provision — I want fleet info like what is in buy."*

`FleetRail.tsx` (was `BuyFleetPanel.tsx`). Shown while the chosen verb is one of `railVerbs.ts`'s
four — the ones that are decisions about the fleet's own state. The working pane on the left, her
state on the right from `md` (768px) up; one column below that, with the rail written FIRST so it is
read before the list rather than eleven thousand pixels under it. The layout is the design system's
`splitClass()` / `splitMainClass()` / `splitRailClass()` — see `src/components/ui/screenLayout.ts`
for why it is flex and not grid, and why the breakpoint is `md`.

**One rail, generalised — not four panels.** A `HireFleetPanel`, a `RepairFleetPanel` and a
`ProvisionFleetPanel` beside the buyer's would be four authorities for "what a rail is".
`docs/NO_SPAGHETTI.md` §1: *owned but too narrow → generalise that one owner and repoint every
caller.* So the panel widened. **Room in the hold** is genuinely shared — BUY and PROVISION both
draw it, because water and food take cargo's own tuns (C.3) — and everything else is per verb:

| verb | the blocks | where every figure comes from |
|---|---|---|
| **BUY** | room in the hold · this order · what moves the price | the three sections below |
| **HIRE** | her crew against her berths · the idle men here | `fleetCrew(fleet)` — the spelling `E_CREW_MAX` counts by (0007:659) · `port.crew_pool` · `config.wage_per_crew_day` |
| **REPAIR** | her worst hull, then every hull · the yard here | `worstHullFraction` / `hullFraction` · `port.has_yard`, `port.yard_tier` |
| **PROVISION** | room in the hold · her stores | `fleet.endurance_days` (SERVED, never divided out here) · `fleetStores(fleet)` |

**The rail never prices HIRE, REPAIR or PROVISION, because nothing serves those prices.**
`src/lib/rpc/types.ts:18-19` states it: *"a port carries `crew_pool` but no crew RATE, no water/food
price and no repair rate … PROVISION/HIRE/REPAIR are priced by the server when the order runs."* A
plausible figure would be the fabricated number `UI_DIRECTION.md` §4 rule 5 forbids, so the last
block on those three verbs says so in the player's words and points at `cmd.preview()`, which runs
the real verb and names the figure before a ducat moves. `config.wage_per_crew_day` is the one money
figure HIRE prints, and it is the standing wage at sea rather than the price of signing a crew member on —
the RATE, where `FleetsScreen.tsx:529` already owns the daily BILL (`aboard × rate`).

Three blocks, every figure served:

| block | from |
|---|---|
| **Room in the hold** | `fleet.free_hold` (`public.fleet_free_hold`, 0017:183) over `fleetHoldTotal(fleet)`. Never recomputed here — three client spellings of that subtraction were deleted and one had been wrong its whole life |
| **This order** | `world.buy_capacity(fleet, good)` — the ceiling, what all of it costs, and the server's own PHRASE for what stops her. Asked once by `OrderComposer` and shared with the quantity stepper |
| **What moves the price** | `world.haggle_state`'s `spread_published` / `spread_effective`, `fleet.officer_pct.PURSER`, the bargain held, `market.port.tax_rate`, `config.trade_step_tuns` |

**The block is labelled "what moves the price", not "negotiation".** The reference (대항해시대
오리진) has a 협상 minigame with a before/after price and a success bar; inventing a figure of that
shape would be the fabricated number `UI_DIRECTION.md` §4 rule 5 forbids, so every row is a served
number. It does **not** assert the absence either: an earlier draft printed *"there is no haggling in
this game"* — true of every migration through 0017, whose self-assert re-checks that `world.skills()`
reports HAGGLING/SPREAD unread (`0017:1088`) — and it stopped being safe to print the same hour, when
**0022 `a_bargain_is_struck_on_the_quay`** landed. The ⓘ says the permanently true thing instead: a
price has a WORLD half (the mid, the same for every house) and a PORT half (the cut), and only the
cut can be shaved. The rows are ordered RESULT first, then CAUSES:

* **the port's spread** — `spread_published`. Half added to the ask, half taken off the bid
  (0005:381-382), derived from `dev_commerce`. The same number for everybody: 0017 explicitly
  **refused** to make `world.spread()` player-aware so that the market screen cannot print a figure
  that depends on who is looking (`0017:66-72`), and 0022 kept that refusal;
* **you execute at** — `spread_effective`, i.e. `world.spread_effective(port, good, fleet)`
  (0022:286), the function `world.quote` itself calls. Purser and bargain already folded in. This is
  the number a BUY charges against;
* **your purser** — a better fill inside the port's cut, on this fleet's quotes only (`0017:379`);
* **your bargain** — what is held, or how many tries remain today. See §10;
* **and no lower** — shown only when `at_floor`: the stack has reached `haggle_spread_floor_frac` ×
  published and the quay will go no further;
* **the mayor's tax** — rides the ask beside the spread. No bargain touches it;
* **a big order** — `world.quote` fills in `trade_step_tuns` steps and reprices every one (§G.2), so
  the price on a row is the price of the first step.

**The purse is deliberately absent**, because it is in the top bar on every screen at once and
`bound_by` already names it when it is the thing stopping her — one fact in two places is two
authorities for it.

## 10. Striking a bargain — the client half of 0022

0022 shipped `cmd.haggle` and `world.haggle_state` **with no caller anywhere in `src/`**. This tab is
the caller: `useHaggleState.ts` reads, `BuyFleetPanel` shows the figures, and `HaggleBlock.tsx` owns
the act.

**The figures are in the rail; the button never is.** The rail is `md:sticky`, and a sticky panel
taller than the viewport pins its top and leaves its foot unreachable — a button in it would be the
*"right now i can't press hunt"* defect (`CORE_REUSE` §1.5) rebuilt from scratch. So `HaggleBlock`
sits in the working pane, under the quantity stepper.

Three rules it keeps, each easy to get wrong:

1. **No client-side gate, ever.** The button is not disabled when the tries are spent, when she is at
   sea, or when the quay holds no stock. Every one of those is a refusal the server writes better —
   `E_HAGGLE_SPENT` arrives as *"The factor will hear no more about Black Pepper in Lisbon today. You
   have had 3 of 3."* with three fixes. A client check would duplicate a rule the server owns **and**
   go stale between reads.
2. **A lost haggle is not an error.** `cmd.haggle` answers `ok:true, won:false` when the factor
   refuses — he heard you and said no. It renders `warning` with the server's sentence, never the
   danger tone a refusal wears. Only `E_*` gets danger.
3. **Nothing is retried and nothing is predicted.** The attempt is written and the count incremented
   *before* the roll, and the roll is keyed on the attempt index (0022:508), so a retry is a
   different draw that has already cost a chance.

**A refusal is `attempts_used − wins`, not `attempts_used`** — the hardening line got this wrong in
its first draft and told a player who had won once and been refused twice that *"he has already
refused you 3 times"*. Caught in the running game, beside a screen that said `0 of 3 tries left`
under a bargain it had plainly won. The server does the same subtraction in `haggle_odds`
(`0022:264`), which is the count the sentence is about.

**Measured, so the copy does not oversell it.** At Lisbon's 2.6% published spread, the maximum
bargain (30% off the cut, two wins) moves 40 tuns of alum from **5,283 d. to 5,264 d. — 19 ducats,
0.36%**. The mechanic behaves exactly as 0022 specifies; its effect on a purse is small because the
spread is small and the mayor's 3% tax is untouchable. The rail therefore states the concession as a
percentage **of the cut**, which is what it actually is, and never as a saving.

## 11. The chart on SAIL, and the layer that had to exist first

The owner, 2026-08-23: *"sail — a small map + current location on the left side."*

**Built 2026-08-23.** This section previously recorded why it was NOT built, and named the two ways
it could be; that write-up is kept below as §11a because the decision it forced is the interesting
part. What shipped is option (a).

### What the player sees

SAIL now lays out in two columns like BUY does, and its rail carries a chart instead of the fleet:

* **the fleet's berth** is the port's loud filled mark, with her name beside it — or, if the order is
  composed while she is at sea, her dot on her own dotted track, exactly where `voyage.position` puts
  her. Nothing on this side computes a position;
* **the destination this order would send her to** is ringed — the same dashed ring the Map tab draws
  round a port a fleet is bound for, because it is the same fact one moment earlier. `VIA` is ringed
  too, and the argument is found by asking the SERVER'S schema which arguments are of type `port`,
  so a verb that one day declares a third one gets it without an edit;
* **the sea lanes**, close in, as hairlines between two drawn marks — the authored leg graph, which
  is the honest answer to *"where can I actually sail from here"*;
* **the frame holds both ends of the decision**, re-fitted whenever the choice changes, with the same
  12° floor that stops a lone docked fleet opening on a harbour approach.

Running a POINTER or the KEYBOARD down the destination list names each harbour on the chart as you
reach it (`OrderComposer`'s `considering`, the same shape as the good list's `inspecting`). It
**chooses nothing** — a tap still commits — and it deliberately **does not move the frame**, because
a picture that jumped as the pointer crossed twelve rows would be unreadable. A thumb raises neither
event, so on the 390px target the chart simply follows the choice.

### The three things it does not do, and why each one is load-bearing

1. **It draws no line between the two places.** A straight segment across this sheet is not the
   passage and is not its length. That exact substitution was a real defect on this very picker —
   Seville at 169 nm against the server's 286, and the wrong number SORTED the list (see
   `PortPicker`'s header, above). Printing it was fixed; drawing it would be the same lie in a shape
   nobody can check. What *is* drawn between ports is the authored lane graph, whose miles are the
   server's own, and the distance stays where it was: on the row, from `legs.nm`, with a dash where
   there is no direct leg.
2. **It takes no input at all.** No pan, no zoom, no tap, no handler prop that could carry one —
   `pointer-events: none` on the picture. The reason is about THIS chart, not about maps: a gesture
   surface embedded in a form fights the page's own scroll on a phone — `useChartSurface` sets
   `touch-none` and calls `preventDefault` on wheel, which is right for a whole tab and wrong inside
   a composer — so `SmallChart` does not mount it. *(This clause also cited "the map never accepts
   an order"; that sentence was amended 2026-08-23, when the MAP tab's own chart gained a `Sail
   here` on a tapped harbour — `docs/DESIGN.md` §E.5 Law 3. It was never this chart's real reason.)*
3. **The rail still carries no control.** `splitRailClass()` is `md:sticky`, and a sticky panel
   taller than the viewport leaves its foot unreachable (§7, §9, §10). A chart is a figure. The ⓘ
   beside it is the one thing that folds, and it folds text.

### What moved, and what it cost

`railVerbs.ts` was one list answering two questions at once — *does this verb get a rail* and *does
it render `FleetRail`*. Those diverged the moment SAIL got a rail that is not about the fleet, so it
is now one list per **kind** (`FLEET_RAIL_VERBS`, `CHART_RAIL_VERBS`) with `railKind()` deciding and
`hasRail()` derived from it. The sentence that used to explain SAIL's absence — *"SAIL's decision is
about the WORLD"* — is still there, and it is now the reason it has a rail of a different kind
rather than the reason it has none.

`buildChartModel` gained one parameter, `considering`, rather than the composer assembling its own
table of which ports are loud. Which ports are loud and which are ringed has exactly one author, and
the glyph layer, the label planner and the hit test all read it (`docs/NO_SPAGHETTI.md` §1: *owned
but too narrow → generalise that one owner*). It defaults to empty, so the Map tab is unchanged.

---

## 11a. The decision this forced, recorded as it stood

**The problem, as written before it was solved.** The rail slot was already there and the chart the
tab wants already existed and must not be rebuilt — but every piece of it lived in
`src/features/map/`, and `tests/sections.spec.ts` refuses a screen that imports another screen.
Copying a layer across that boundary is the silent copy `docs/NO_SPAGHETTI.md` §2 names as *worse
than the import*, so nothing was copied.

**The minimum a small chart needed, measured off the imports rather than guessed:**
`useCoastline.ts` → `coastline.ts` → `coastlineBuild.ts` → `svgPath.ts`; `CoastlineLayer.tsx`;
`PortsLayer.tsx` → `chartModel.ts` (for `PortRole`), `glyphs.ts`, `mapTypes.ts`. That is **nine of
the fourteen** files in `features/map/` — there was no small carve-out to take, which is exactly the
measure of how bad the copy would have been.

**And the obvious split did not work.** The natural home was the model in `src/domain/chart/` and
the SVG layers in `src/components/chart/` — but *"machinery knows nothing above it"* forbids
`src/components/**` importing `domain/**`, and every layer needs `ChartModel` / `MapPort` /
`PortRole`. Making them take plain `{x, y, role}` props to get around that is a rewrite of every
layer's prop type in order to survive a boundary, which is §2's own tell for a boundary in the wrong
place.

**Taken: a new layer, `src/chart/`** — model, hooks and layers together, one `index.ts` entrance,
sitting between `domain` and `features`. `docs/SECTIONS.md` gained the row and the case; the spec
gained two rules (`the chart knows nothing above it`, `the chart has one entrance`) and two existing
rules gained `chart`; all four were broken on purpose and watched go red. MapScreen kept composing
exactly what it composed before — only its import paths changed, plus its seven-line SVG paint order,
which became `ChartCanvas` so the second caller composes it instead of restating it.

**Standing law either way — AMENDED 2026-08-23.** This read *"the map never accepts an order"*. The
MAP tab now offers one action on a tapped harbour, and the law it was protecting survives in the form
that is actually load-bearing: **nothing outside this feature COMPOSES an order, and no argument
picker, quantity control or legality check lives in `src/features/map`.** The map names an intent and
hands it to `domain/order`'s draft, exactly as FLEETS, PORT and MARKET do, and this tab composes it —
`docs/DESIGN.md` §E.5 Law 3 and `features/map/SailHere.tsx`.

None of that touches the chart in THIS rail, which is unchanged: the destination is picked from the
list, the chart shows where she is and where that is, and nothing on it is tappable (see point 2).
