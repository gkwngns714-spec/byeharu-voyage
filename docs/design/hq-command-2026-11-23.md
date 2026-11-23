# HQ command board, 2026-11-23

## 1. The owner's words

> "right now i can't send ships because of restriction, which means other players will also be like me. i want this game to be
> strategical game, where all the work(acitivities) are done in HQ - words with graphics. choosing best options available, finding best
> options."

> "remove sea limits entirely, build the HQ board. go"

The lead's proposal, which the owner approved:

1. **One opportunities board in HQ.** Every option open to her now is ranked: trade runs by profit per hour, requests, the yard
   (build and repair), investments, Land production and hiring captains. Each option is a card with a mark, the payoff, the time, the
   risk (pirates, sea) and what it needs. One press commits it. Finding the best option is the skill: the top few are shown, with sort
   and filter to dig deeper (an EVE market feel).
2. **Restrictions become choices, not walls.** The sea limits are off: `sea_conditions_bite` was set false on prod at 03:58 UTC.
3. **Fleets get standing assignments in HQ** ("work this route", "serve requests", "carry Land output to the yard") and keep working
   while she is away (the Melvor / RS3 idle loop). She comes back to a report and re-plans.
4. **HQ shows the whole state at a glance**: money per hour, each fleet's job and earnings, threats (pirates near her routes), what
   finishes next, and the next three best moves. Marks, bars and rings; few words.
5. **Other screens become detail views.** Everything starts from HQ.

## 2. The plan

**v1 (this PR, client only).** The sea-limit walls leave the client. The board stands at the top of HQ, built from reads the client
already makes, and ranked on the client by one documented rule. Every press goes through an action that already exists.

**v2 (server, one migration each, in number order after the open 0479):**

- **`world.hq_board()`: the server ranks.** (Built in 0480 with the risk and the rate below, dark: `hq_board_enabled`; `docs/dev-log/2026-11-23-hq-board-server.md`. The risk is computed in the board, not in `world.best_sales`.) It is a STABLE read for the caller, asked at the market's edge (like `world.best_sales`) and
  never on the beat. It returns `{moves: [{kind, fleet, score, profit, seconds, risk, needs, act}], rate, next, threats}`, where:
  - `trade` is each idle fleet's `world.best_sales` answer. It is not capped at three fleets.
  - `request` covers every port where a fleet of hers lies, not only the city in hand. The figures are `cmd.preview_fulfil`'s net,
    not the premium alone.
  - `yard` comes from the second-ship quote and the purse.
  - `crew` lists fleets whose `ship_seats` are all empty, joined to the Inn of the port each one lies in.
  - `invest` is idle coin, priced against `world.holdings`' share prices and dividends.
  - `land` covers a party home or waiting to be collected.
  - `act` names the command that commits the move, so the card can commit in one press without opening the desk.
  - Budget: no table and no cron, so no `-- budget:` line. It costs one read per HQ visit, about the cost of `world.best_sales` times
    her idle fleets. Read the gate before lighting it.
- **Risk on a sale.** `world.best_sales` and `world.good_board` gain `risk: {danger, bounty}` on each row: the highest danger of the
  waters on the course (`public.sea_danger` over the legs) and whether a named pirate's home or posted sea lies on it. Today the client
  can only mark a sale whose harbour is a bounty pirate's home.
- **The rate.** `world.player` (or `world.report('day')`) serves `rate_per_hour`: the trailing 24-hour ledger net over 24. The client
  then stops dividing today's net by the hours since 00:00 UTC.
- **Standing fleet jobs** (owner idea 3). A new table `public.fleet_jobs(fleet uuid primary key, kind text check (kind in ('route',
  'requests', 'best_trade', 'land_carry')), params jsonb, since timestamptz, paused_reason text)`, with:
  - `cmd.set_fleet_job(fleet, kind, params)`, `cmd.clear_fleet_job(fleet)` and `world.fleet_jobs()`;
  - one step on the existing beat, `public.tick_fleet_jobs()`. It acts only on a DOCKED fleet with an empty queue. `best_trade`
    issues her best sale's plan through `cmd.issue_lines`, `requests` fulfils what her hold can, and `route` defers to the standing
    route;
  - `-- budget:` and `-- retention:` lines, because it adds a table and a beat step;
  - the expected extra rows a minute: at most one order per job-holding fleet per lap.
- **Land → yard carry.** The job kind `land_carry` (params `{to: port}`) carries the Land storage's goods to the yard port's storage
  (`cmd.land_collect`, then the sail and `put in storage` lines), so the second ship's materials fill while she is away.
- **The away report.** `world.away_report(since)`: what each job earned and what stopped, since her last visit. HQ opens on it when she
  comes back.

## 3. What v1 built

### A. The sea limits out of the client

With `sea_conditions_bite` off, the client still drew each wall as "what the rule WILL say". It no longer does.

- **The Map's Seas filter** names each sea: no "Title N · Waves N" under a name, and no closed tone. The sea tray shows the sea's name,
  its harbours and the Codex door; the title, waves, verdict and fix rows are gone. A harbour's tray names its sea, with no short line.
- **The route bar** dropped the "Sea shut" word and the sea-wall line.
- **The Codex's Seas face** is a list of seas with their harbours. It has no title, waves, open/closed lists or state note.
- **The plan** dropped the "Sea rules" line, the title, the wave resistance and the per-city sea asks. The legs under its map wear no
  sea tag (it read "Later" while the switch was dark).
- **Deleted, because they served only the wall:**
  - `domain/seas/walls.ts` (`fleetSeas`, `wallIn`) and `closedMask`;
  - `features/map/seaLines.ts`;
  - `seaTagWords`, `seaWallTag`, and the chart's `zone-closed` tone, its CSS and `zoneNoteSize`;
  - the seas dictionary's ask words, and the desk's sea-state words.
  - `useFleetSeas` became `live/useSeas.ts` (`useSeaRows`, `useSeaZoneCells`).
- **Kept, because it is harmless:** a refusal the server still makes (`E_SEA_CLOSED`) prints in its own words through `Note`'s
  `seaWallWords`, and the plan's reach line words it when the server says so. Neither draws anything unless the server refuses.
- **Specs:**
  - `tests/seas.lit.spec.ts` and `tests/seasLit.fixture.ts` existed only to prove the wall, so they are deleted.
  - `map.seasFilter` now asserts no ask and no closed zone.
  - `map.look` runs on the shipped world.
  - `desk.plantab` lost its sea-state line, and `lit.screens` lost the "Sea shut" word.
- No SQL is touched.

### B. The board (`src/features/city/board/`, at the top of HQ)

- **The bridge** (`Bridge.tsx`) has four cells:
  - **Coin.** Today's net per hour sits under it: `world.report('day')`, the Report face's own read, divided by the hours since
    00:00 UTC.
  - **Fleets.** Each fleet is her flagship's picture in the tone of her job: blue at sea, green on a route, gold idle, red stuck. The
    counts at sea, in port and idle stand under the pictures.
  - **Next.** The soonest of: a voyage's arrival, the ordered ship, the Academy's next level, a route's next lap. It shows its clock.
  - **Pirates.** A target mark with a count when a bounty's sea is among the waters her voyages cross, or those waters are at danger 4
    or more. Otherwise it is a quiet shield.
- **Best moves** (`HqBoard.tsx`, `MoveCard.tsx`) shows the top five cards, with More for the rest. Each card has the activity's glyph,
  the whole title, the headline figure (+coin, and coin per hour where a time is served), and the needs as marks: the fleet, the good
  and its units, the time, the cost, and the pirate risk. Icon chips filter the list: All, Sales, Requests, Build, Crew, Invest
  (the trade chip says "Sales": "Trade" is the rail's word for the desk, and two controls may not share a label).
  - **Trade:** `world.best_sales` for up to three idle fleets' ports (the desk's own read and key), up to three paying near sales each.
  - **Requests:** the requests in the city in hand that a fleet of hers lying there can fill from her hold.
  - **Build:** the second ship, when her purse covers the Order's quote (`useSecondShipGoal`).
  - **Crew:** a fleet lying in port with no one in any cabin.
  - **Invest:** coin beyond the dearest trade card, when it is 20,000 or more and the Trading-5 gate is open.
- **The ranking rule** lives in one file, `src/domain/hq/moves.ts`:
  1. The yard comes first.
  2. Trade runs and requests follow together, by coin per hour. A request counts as a quarter hour.
  3. Hire a captain comes next.
  4. Invest comes last.
  - Ties go to the bigger figure, then the id.
- **The press** (`useMovePress.ts`). Every card hands its move to the place that already performs it:
  - **Trade:** a hand-off store (`store/deskHandoff.ts`) carries the sale to the Trade desk, whose own `pressBest` opens the trip:
    the same good, units and harbour as the desk's card.
  - **Request, Crew, Build:** the Office's City face, through its one door (`openOfficeCity`), at the market, the inn or the build
    yard with that hull's sheet. `?face=city&building=…&hull=…` is new and goes through that same door. Where no fleet lies at the yard,
    the press opens HQ's port.
  - **Invest:** the Office's Invest face.
- **Fleets** (`FleetRows.tsx`) has one row a fleet: her picture, her whole name, her job (a route's ports, a trip's line, or "Docked
  Lisbon"), and her route's money today. The press is Route (the desk's route page, RouteFold, through the same hand-off) or Plan. An
  idle fleet has a gold edge and her best card under her row.
- **HQ's buildings** stand under the board, unchanged, each one press away. `hq.design`'s laws (g) and (h) now measure the places' own
  glass, from the top of their row.
- **Moved to their one entrance:**
  - `ShipPicture` moved to `src/live/ShipPicture.tsx`, so a screen can draw a ship without importing another screen.
  - `tileToneClass` and `PLAN_LINE_CLASS` are exported from `components/ui`.
  - `NeedChip` is a new `components/ui` primitive.
- **Spec:** `tests/hq.board.spec.ts` covers:
  - the rule;
  - the bridge;
  - trade cards ranked by coin per hour;
  - a card's press opening the desk's own trip, for that good, sold there;
  - the idle fleet's inline card;
  - no sideways scroll, nothing past the glass, no cut name and 44-px presses at 320, 390 and 1280.

Screenshots (local to the PC that took them):
`C:\Users\gkwng\AppData\Local\Temp\claude\f5388e2006711d23\20c3c33b-2e64-4a9f-9933-ae93974d7413\scratchpad\hq-board\`, named
`before-<390|1280>.png` and `after-<390|1280>[-hq-fleets|-city-buildings].png`.

Decided by default (the owner may reverse each):

- The board prices at most three idle fleets, to keep the desk's read count.
- Idle coin starts at 20,000.
- The Build card shows only when the purse covers the price.
- The rate is today's (UTC) net per hour.
- The fleet's press is Route for an idle fleet or a fleet on a route, and Plan otherwise.
