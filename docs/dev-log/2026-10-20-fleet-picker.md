# 2026-10-20 — the fleet picker (`osn-fleet-picker`, client only, no migration)

**The owner** (2026-10-20, OWNER_REQUESTS row 164): *"in the command, right now i see my fleet name on left top.
when i have multiple fleets, how should this change?"* — and of the design below, *"good. we need that."*

## What changed

The COMMAND desk's header showed one chip per fleet (`flag · name · where`), scrolling sideways. It now shows ONE
button for the selected fleet: her flag, her name, a dot for her one-word signal, and ▾. Supplies and Cargo stand
beside it (wide) or under it (phone) exactly as before; the header stays one line however many fleets there are.

- **The dot** (`src/domain/fleet/derive.ts` `fleetSignal`): green = sailing (a SAILING voyage row, `whereabouts`),
  grey = waiting (docked or anchored), red = stuck. Stuck is what the server already serves: a `failed` order in her
  queue (`fleetRefusedOrder`, the same row `Queue.tsx` prints as the halt note — it used to find it inline; now
  both ask the section) or a status `fleetStatusTone` already calls danger (ADRIFT, UNABLE_TO_SAIL, 0093's
  "blocked"). No new rule.
- **If any OTHER fleet is stuck**, a red dot after the ▾ says so, with the count as its label.
- **The press** opens the list: one `Row` per fleet — flag · dot · name, the where line under it (§2.1's one rule,
  with the countdown off the last read, as the queue counts), cargo used / total at the right. A row SELECTS and
  closes the list; nothing on the page moves (the owner's rule, rows 6/15/25/28/45).
  - wide (≥ 1024): a `Popover` hung under the button — new design-system primitive, `absolute` under a `relative`
    wrapper, so out of the flow by construction; closes on a press outside or Escape.
  - phone: the bottom `Tray` at half, the primitive every other unfold already uses.
- **← / →** switch fleets on a wide glass, in the served order, wrapping; never while typing in a field, never
  with a modifier held.
- **One fleet:** her flag and her name, as a plain label — no dot, no ▾, no list.
- **One selection:** `useCommandDraft.selectFleet`, the authority the map's tap and FLEETS' "Command her" already
  write; the picker writes it through `onSelect` and reads the fleet the desk resolved from it.

## Design-system additions (`src/components/ui`)

- `Popover` — the wide glass's small "unfold under the press"; header controls with a short list.
- `useDismiss(open, box, onDismiss)` — the one press-outside + Escape. It was hand-written in `live/PortField.tsx`;
  this was its second caller, so it became a function the same turn and PortField now calls it.
- `Dot` — one state as an 8-px disc of a tone (`success` / `danger` / `neutral`), with a label when it is the
  only place the word is said.

## Decided by default

- The where line left the header for the list rows (the owner's list for the button was flag · name · dot · ▾ and
  "one line however many fleets"). The City face still names the city she is docked at or bound for.
- Grey covers "docked with orders queued" as well as "docked with none": the owner named three colours, and a
  fourth would be a colour nobody can read on an 8-px dot.
- A refused order outranks a voyage: a fleet still moving with a refused row is red, because she needs you.

## Proof

- `tests/desk.fleetpicker.spec.ts`: `fleetSignal` in Node (8 cases); one fleet at 1440 and 390 (label, nothing to
  press, no list); two fleets at 1440 (button · dropdown · select · Escape · outside · ← → · typing · the other red ·
  nothing moved); two fleets at 390 (the tray, nothing moved, select).
- The two-fleet world is the shipped image plus a trigger (`tests/twoFleets.fixture.ts`) that founds the house with
  a second fleet through the chain's own `form_fleet` / `commission_ship` and one refused order. The open / patch /
  dump / serve that `routesOn.fixture.ts` did is now `tests/worldImage.fixture.ts`, which both call.
- `tsc -b`, `eslint`, `tests/sections.spec.ts`, `tests/duplication.spec.ts`: green at writing.
- Neighbours on a preview of this build (port 4187, headless): `desk.inplace`, `desk.layout`, `layout` (COMMAND),
  `route.stopface` — 13 of 14 green at 3 workers; the one red was `route.stopface` "a running route reads the
  same", refused at Start with *"that leg is 11312 nm and your navigation carries you 1700 nm"*: the spec picks "the
  first harbour the port field offers that is not home", and under load it clicked before the reach payload landed,
  so every distance was `+Infinity` and the tie fell to alphabetical order — **Acapulco**. A pre-existing race in
  the spec (this branch changes only the field's dismissal, not its listing or the reach); it passed 3 of 3 run
  alone, read as a diagnostic. Not fixed here; noted for the spec's owner.

Not deployed: this PR does not merge.
