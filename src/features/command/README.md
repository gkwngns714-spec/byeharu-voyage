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
| **2. What she is to do** | taps a verb | `world.snapshot().verbs` — the server's own `cmd.verb_schema()`. Nothing on this side lists verbs |
| **3. Each argument** | taps a row, a chip, or drags a stepper | one picker per argument TYPE the schema declares (below) |
| **4. What will be sent** | reads it | the line assembles itself, read-only, as the picks land |
| **5. Preview** | reads the estimate, or the refusal | `cmd.preview()` — the REAL verb, run and rolled back |
| **6. Issue** | one button | `cmd.issue(fleet_id, text, expected_version)` |
| **7. Her queue** | cancels a row, or clears the halt | `fleet.queue`, `cmd.cancel()`, `cmd.clear()` |

Every argument picker offers what actually exists **now**:

* **port** — the snapshot's ports, ones a single authored leg away first, then by great-circle
  distance from where she lies. A filter box narrows the list; picking is still a tap on a row.
* **good** — the goods in *this port's* market, with ask, bid, %NBR against the ports within
  600 nm, the stock band and the server's own buy/hold/sell advice. SELL offers only what is
  aboard.
* **qty** — ALL / HALF / MAX and a stepper that walks in `config.trade_step_tuns`, bounded by the
  hold, the stock and the purse, and captioned with **which** of those stops you there.
* **number** — HIRE is bounded by empty berths, REPAIR starts above her present hull, PROVISION
  offers days. No free-form number field exists on this screen.
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

Nothing on this tab has a `max-h` or an `overflow`; the page's own scroll is the only one. A long
list of ports or goods **truncates** at twelve rows and says how many the filter is hiding, rather
than hiding them inside a scroll box — the rows on screen are whole and pressable, and the hidden
ones are honest about being hidden.

## 8. Time

Nothing here ticks. A read is the catch-up (D.2): `Read again` refetches, issuing refetches, and an
ETA is counted from `readAt` — the instant the world was last read — rather than from the wall clock
during a render.
