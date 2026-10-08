# TRADE_ROUTES — a fleet that trades by itself, on a loop, while you are away

**Status:** design, 2026-09-30. **Slice 1 BUILT on branch `osn-trade-routes` (migration
`20260818000092_a_route_is_a_standing_order_that_sails.sql`) — NOT merged, NOT deployed, DARK
(`standing_routes_enabled` = false).** See §13 for what was built, what differs from the plan
below, and what was measured. Architect's document for owner request row **106** in
`docs/OWNER_REQUESTS.md`. Written against `main` = `a613a05`, chain head
`supabase/migrations/20260818000091_the_water_reaches_the_new_harbours.sql`.

**What the owner asked for, verbatim (2026-09-30):** *"i want this game to be a simulating based -
meaning i set up route, trade routes - going back and forth, afk, running all the time"*.

**What that means for the game.** The player defines a **route** once. A route is a loop of ports,
and at each port the player says what to sell, what to buy and whether to repair. The player then
gives the route to one fleet. The server runs that loop for ever, including while the player is
offline. When the player comes back, History shows one line per lap: what the fleet did and what
it earned. The game's centre moves from issuing each order by hand to designing and tuning routes.

**What this document is.** It is the plan that `docs/NO_SPAGHETTI.md` §7B (lines 401-467) requires
before a new concept is built. It covers the concept in one noun phrase, where it lives, its second
caller, and what would make it the wrong shape. It then gives the slices, the self-asserts, every
file slice 1 touches, and the decisions only the owner can make.

---

## 0. The answer in six lines

1. **A route is a standing order that sails.** It works like the 0034 provision preset, one level
   up. It is a company-owned row. It never executes anything itself. At the one moment a docked
   fleet's queue runs dry, it writes the next port's orders into that fleet's existing queue, in
   the player's own grammar.
2. **There is one executor, and it is the queue.** `cmd.advance` →
   `cmd.execute_order` → `do_sail / do_buy / do_sell / do_provision / do_repair` run every
   route order. There is no second trade path, no second movement path and no second clock.
3. **The hook is one line.** `cmd.advance`'s `exit when o.id is null`
   (`20260818000007_a_fleet_arrives_and_the_queue_runs_itself.sql:857`, still in the live body
   after 0047's re-cut at `…0047…:725`) becomes "if a route stands on this fleet, refill once,
   then continue".
4. **AFK mostly already works.** `tick_arrivals` runs every minute (`…0010…:54-87`, scheduled
   `* * * * *` by `…0012…`). It settles due voyages with nobody reading. The arrival arm then calls
   `cmd.advance` (live settle body, after `cmd.run_standing_provision`, the hunk 0034 sliced at
   `…0034…:274-283`). Only one small addition is needed: one loop that wakes routes held for pacing
   (§4.3).
5. **The production clock is stopped today.** All five pg_cron jobs read `active: false` (deploy
   reality, 2026-09-30). Until `select public.wind_the_clock();` (`docs/DEPLOY_RUNBOOK.md:113`)
   runs, a route advances only one stop each time someone reads the fleet. For route fleets, the
   clock is now **load-bearing**, and `…0010…:1-13`'s claim that it is "an optimisation, not a
   correctness requirement" no longer holds for them.
6. **It is not infinite money, but it is unmeasured passive income.** The daily cap, price impact
   and regeneration bound the income from each (company, port, good) pair. Income still scales
   with the number of distinct pairs a company works, and nothing damps rank today. §8 gives the
   dampers and the measurement that has to come before the switch is turned on.

---

## 1. What exists that a route composes (verified; file:line)

| Mechanism | Where | What the route uses it for |
|---|---|---|
| Per-fleet order queue `public.orders` (`seq`, `raw_text`, `verb`, `args`, status `pending/active/done/failed/cancelled/skipped`) | `…0007…:81-98`. The status check at `:90` already allows `'skipped'`, which nothing sets today | Holds a route's generated orders like any other order |
| The one grammar `cmd.parse(player, fleet, text)` | Live body (dump `cmd.parse`). SAIL takes one port token or `lat,lon`. BUY/SELL take `n / ALL / HALF / n%` plus an optional `AT [<=\|>=] price` limit | The route renders each stop line to text and parses it here, so there is no second parser |
| The only mutating entry `cmd.issue(fleet, text, version, path)` | `…0008…:453`, re-cut `…0047…:825` and `…0050…:551`. Enqueue steps are inline: queue cap (`order_queue_max` = 12, `…0001…:162`), `seq = max+1`, INSERT, `version+1`, `cmd.advance` | Its enqueue hunk is sliced out into `cmd.enqueue`, and both `cmd.issue` and the route call that (§4.1) |
| Queue runner `cmd.advance(fleet, now)` | `…0007…:812-866`. The halt rule is `:839` ("a failed order now blocks the fleet until the player clears it"), and the queue-dry exit is `:857`. Re-cut `…0047…:725` so it also runs when ANCHORED | **The hook** (§4.2) |
| Dispatcher `cmd.execute_order` | Live arms SAIL, BUY, SELL, PROVISION, HIRE, DISMISS, REPAIR, MAKE, STORE, TAKE, BUILD, FIT, UNFIT. Every error becomes `status='failed'` through `cmd.refusal_caught` | Unchanged |
| SAIL needs a course | `cmd.do_sail` (live) verifies a proposed polyline against the server raster. With no course attached it tries the straight line and refuses `E_NO_COURSE` if land is in the way | Each route leg **stores its proposed course**. The course is authored by the client's one course author, `proposeCourse` (`src/domain/passage/index.ts:160`), and re-verified by `do_sail` on every departure |
| BUY with price cap | `cmd.do_buy`: `ALL` is sized by `public.fleet_buy_capacity` (`…0017…:422`) = min(hold, stock, daily cap), then walked down to what the purse can pay. `AT p` fills partially up to the cap and refuses only if the market opens above it | The "buy up to N units, at most P each" line is `BUY g N AT p` |
| SELL with a floor | `cmd.do_sell`: `AT >= p` sells partially down to the floor. It reads `public.fleet_cargo_basis` (`…0081…:182`) and returns `profit` | The "only sell at a profit" line is `SELL g ALL AT >= <basis>` |
| SELL over the daily cap | `cmd.do_sell` refuses the **whole** order `E_DAILY_CAP` when qty > `world.daily_cap_remaining` (dump do_sell lines 37-40). BUY ALL is capped instead | Hazard. See D3 |
| Standing provision (0034) | Table `provision_presets`, `fleets.provision_preset_id`, executor `cmd.run_standing_provision` (`…0034…:195-243`), fired only in the arrival arm, before `advance` (`…0034…:274-283`) | The precedent this design copies. The route also **takes over** a route fleet's resupply timing (§3.4) |
| REPAIR | `cmd.do_repair` refuses `E_NO_YARD`. With nothing to repair it refuses `E_UNAVAILABLE: nothing aboard needs repair`. Otherwise it sets REPAIRING with `busy_until`. `tick_arrivals` releases the fleet and advances (`…0010…:79-84`) | "Repair here" is a stop line |
| Clock | `tick_arrivals` every minute. Jobs are created inactive and started by `wind_the_clock()` (`…0078…:157-200`). `public.clock_jobs()` lists them (`…0078…:140`) | Drives routes with nobody reading |
| Wages | `public.crew_wages` is charged **once per settled sea-day** through `public.credit(…,'WAGES',…)` (live settle loop, the 0086 hunk). The per-day `wages` figure is in the day's payload | Lap wage cost. It is also the biggest row-growth term (§9) |
| History | `public.events` / `public.ledger` are append-only (`forbid_mutation`, `…0004…:135-150`). The read is `world.ledger(cursor, limit)` (`…0009…:192-228`). The client renders `src/features/ledger/headline.ts` and the kind→face map is `src/features/ledger/LedgerScreen.tsx:53-62` | The per-lap line is one new event kind |
| RPC registry | `public.client_rpc_entry_points()`. Last re-cut 0087; its last row is `('cmd','preview_fulfil','uuid, uuid')` | Slice 1's new entry points are sliced in after that row |

**Not built, though the design mentions them:** `WAIT` (DESIGN.md:809-811, no arm in
`execute_order`); the CMD "idle with an empty queue" badge (DESIGN.md:477); `SAVE ROUTE / RUN ROUTE`
templates (DESIGN.md:932-934); **route fatigue** (DESIGN.md:1112, which damps fame only; `grep
fatigue supabase/migrations` finds nothing).

**Names already taken, so do not reuse them:** `world.trade_routes` (a read, `…0019…:676`, still
registered in `client_rpc_entry_points`); `voyage.route` / `voyage.route_direct` (the leg graph);
`src/chart/route.ts` (the voyage track, `buildTrack` at `:101`). The new concept is therefore
**`standing_route`** on the wire and in code, and **Route** to the player.

---

## 2. The concept, answered before the first line (NO_SPAGHETTI §7B)

1. **Concept, in one noun phrase:** *a standing route — an ordered loop of ports, each with a
   short list of trade lines, that writes a fleet's next orders into its queue whenever the queue
   runs dry in port.*
2. **Where it lives, and why.** On the server, the tables are in `public` (company data, read-own
   through RLS, like `provision_presets`), the verbs in `cmd`, and the read in `world`. The
   generator is `cmd.run_standing_route`. It lives beside `cmd.run_standing_provision` because it
   is the same kind of thing: a standing order fired from the queue path. On the client, it lives
   in `features/command`, because COMMAND is "the only tab that changes the world" (DESIGN.md
   §E.1). It is **not** in `features/fleets`: `FleetFold.tsx`'s own header (lines 20-30) names "a
   fourth thing folded in here (an order queue, a history)" as the wrong shape.
3. **Second callers, known now.** (a) MAP draws the player's own route line (slice 3). It reads the
   **served** route (`world.standing_routes`), never the editor's draft. (b) FLEETS prints one
   caption word on the fleet row (`On route`, `Stopped`). That is a reading of the served state,
   not a column. (c) History renders the lap line. All three read one served shape. None of them
   derives a figure.
4. **What would make it the wrong shape, and the guard for each.**
   - *A second executor* (the route calling `do_buy` directly). Guarded by a self-assert: every
     route trade appears as an `orders` row with `route_lap_id` set. No `BOUGHT` or `SOLD` event
     for a route fleet may exist without such an order.
   - *A copy of preconditions in the generator* (checking stock, cap or purse before enqueueing).
     Forbidden. The generator reads only the served readers it *renders from* (`fleet_cargo_basis`
     for a floor price, the fleet's cargo list for "sell everything"). It never predicts success.
     Refusals are the executor's to give.
   - *A route state copied onto the fleet.* `fleets` gains no column. The route points at its
     fleet, because the relation is 1:1 (§3.1).
   - *A second clock.* No new cron job. Pacing wakes up from `tick_arrivals` (§4.3).

---

## 3. The data model (migration 0092)

### 3.1 Tables

```
public.standing_routes
  id               uuid pk
  player_id        uuid not null → players on delete cascade
  name             text  (2..24 chars; unique per company, case-folded)          -- like provision_presets
  fleet_id         uuid null UNIQUE → fleets on delete set null                  -- one fleet per route, one route per fleet
  cursor           int  not null default 0   -- the stop the fleet is AT or HEADING TO
  lap_no           int  not null default 0
  lap_id           uuid null → standing_route_laps on delete set null            -- the open lap
  paused_reason    text null check in ('player','reserve','losing','off_route','error','edited')  -- null = running
  hold_until       timestamptz null          -- pacing (§4.3); null = not held
  reserve          bigint not null default 0 check (>= 0)     -- guard: pause when the purse is below it
  stop_after_losing_laps int not null default <knob>  check (between 1 and 20)   -- guard
  created_at, updated_at

public.standing_route_stops
  route_id  uuid → standing_routes on delete cascade
  ord       int  (0..n-1), pk (route_id, ord)
  port_id   uuid not null → ports (kind = HARBOUR; a sea place has no market)
  course    jsonb not null   -- the proposed polyline for the leg FROM this stop TO the next,
                             -- authored by proposeCourse, re-verified by do_sail at every departure
  repair    boolean not null default false     -- "Repair here" (slice 1: to 100%)

public.standing_route_lines
  route_id, stop_ord  → standing_route_stops on delete cascade
  ord       int, pk (route_id, stop_ord, ord)
  kind      text check in ('SELL','BUY')
  good_id   uuid null → goods     -- null on SELL = "everything on board"; BUY requires a good
  qty       numeric null check (qty is null or qty > 0)   -- null = ALL
  price_limit numeric null check (> 0)     -- BUY: Max price each. SELL: explicit floor
  at_profit boolean not null default false -- SELL only: floor = what it cost (fleet_cargo_basis)

public.standing_route_laps          -- bounded: the newest <standing_route_lap_keep> per route
  id uuid pk, route_id → standing_routes on delete cascade, lap_no int,
  started_at, closed_at null, stops_done int,
  sold bigint, bought bigint, supplies bigint, repairs bigint, wages bigint, net bigint,
  skipped jsonb   -- [{stop, line, code}] — the refusals that were stepped over

alter table public.orders add column route_lap_id uuid null
  references public.standing_route_laps(id) on delete set null;
```

**Why the route points at the fleet, and not the fleet at the route (as 0034 does).** A 0034
preset is **shared** by many fleets, so each fleet holds a reference (`…0034…:16-22`). A route is
held by at most one fleet at a time (the owner: "assigned to one fleet"). A `unique` `fleet_id` on
the route states that directly and keeps `fleets` unchanged. Deleting a fleet sets the route's
fleet to null, which detaches it.

**Stop and line caps** are table triggers in the 0034 shape (`…0034…:161-176`), so every future
writer inherits them. `standing_route_stop_max` (default 6) and per-stop lines are bounded so that
`lines + SELL-everything expansion + PROVISION + REPAIR + SAIL ≤ order_queue_max` (12). When the
expansion would overflow, the generator drops the trailing SELL lines and records them in
`skipped` with code `E_QUEUE_FULL`, the existing code.

**RLS:** read-own `select` for `authenticated` on all four tables, and no client table write. The
0034 posture (`…0034…:185-190`) and the grant-drift law (PR #250 memory: publish migrations REVOKE
client table-write). `client_write_grants()` must stay empty for these tables. That is a
self-assert.

### 3.2 World knobs (`world_config`, all served by the read)

| key | default | meaning |
|---|---|---|
| `standing_routes_enabled` | **false** | Dark-first switch. False means the verbs refuse `E_UNAVAILABLE` ("Routes are not open yet."), the hook is inert, and the read serves `enabled:false` |
| `standing_route_max` | 3 | routes per company (D7) |
| `standing_route_stop_max` | 6 | stops per route |
| `standing_route_laps_per_game_day` | 1 | pacing (D2); 0 = unpaced |
| `standing_route_lap_keep` | 30 | lap rows kept per route |
| `standing_route_losing_laps` | 3 | default for `stop_after_losing_laps` |

### 3.3 How a stop becomes orders (the renderer, one function)

`cmd.standing_route_lines(route, stop_ord, fleet) returns text[]` renders one stop into grammar
text, in this fixed order:

1. **SELL lines.** A line with a good renders `SELL <code> <qty|ALL> [AT >= <floor>]`. A line with
   no good renders one `SELL <code> ALL …` per good on board at refill time. The floor is
   `price_limit`, or, when `at_profit`, `public.fleet_cargo_basis(fleet, code)`. When the basis is
   null, no floor is rendered.
2. **PROVISION `<days>` DAYS**, when the fleet has a 0034 keep level. `<days>` is read from the
   preset at refill time. It is a reference, never a copy.
3. **REPAIR** when `stops.repair` is set. Grammar form to be confirmed against `cmd.parse`'s
   REPAIR arm before writing. The dump shows REPAIR takes a fleet reference and a target percent.
4. **BUY lines.** `BUY <code> <qty|ALL> [AT <price_limit>]`.
5. **SAIL TO `<next port code>`**, with the stop's stored `course` attached as `args.path`,
   exactly as `cmd.issue` attaches `p_path` (live issue body, the "0047: a SAIL may carry the
   proposed course" block).

Every rendered line goes through `cmd.parse(player, fleet, text)`, so the one grammar is the only
authority on what a line means. The migration self-asserts that every line kind renders and parses
round-trip.

### 3.4 Resupply is the 0034 keep level, placed at the right moment

Today the standing provision fires on arrival, *before* the queue (`…0034…:274-283`). A route fleet
arrives with a full hold, so that purchase would be clamped or refused for space (PROVISION_REFUSED).
The fleet would then sell, buy the hold full again, and have its SAIL refused `E_ENDURANCE`: a halt
on every lap. So:

- The route **renders the keep level as a queued `PROVISION` line after its sales and before its
  buys** (§3.3 step 2). It uses the same `cmd.do_provision` and the same preset figure.
- `cmd.run_standing_provision` gains one early return, sliced exactly-once: *"if a running standing
  route stands on this fleet, return null — the route places the keep order itself, after its
  sales."* The rule for when a route fleet resupplies then has one author, the route, and the keep
  level still has one author, the preset.
- A route assigned to a fleet with **no** keep level is refused `E_NO_KEEP` ("Set how many days of
  supplies to keep first."). Otherwise the first SAIL would fail `E_ENDURANCE` AFK.

---

## 4. Execution: composing the queue

### 4.1 One enqueuer: `cmd.enqueue`

`cmd.issue` does enqueue work inline (live body: queue-depth check → `seq = max+1` → INSERT →
`version+1`). 0092 slices that hunk out, from `pg_get_functiondef`, exactly once, LF-normalised
(memory: CRLF hunks never match), into:

```
cmd.enqueue(p_player uuid, p_parsed jsonb, p_text text, p_path jsonb, p_lap uuid) returns jsonb
  -- attaches p_path to a SAIL (moved from issue), checks order_queue_max, seq, INSERT (route_lap_id = p_lap),
  -- version+1; returns {ok:true, order_id} or {ok:false, error_code:'E_QUEUE_FULL', error_message}
```

`cmd.issue` keeps the ownership check, E_STALE, settle, parse and CANCEL/CLEAR routing, then calls
`cmd.enqueue` and wraps a refusal with its existing `fixes` / `queue` keys. **Parity is proven
byte-for-byte:** a probe fleet issues the same five orders before and after the slice (including an
E_QUEUE_FULL at 13), and the JSON responses must be identical. This is the 0034
reverse-substitution discipline (`…0034…:246-262`). `cmd.enqueue` is revoked from
`anon`/`authenticated`: server only.

### 4.2 The hook: `cmd.advance`, at the queue-dry exit

Live `cmd.advance`, in order: failed-order halt (`…0007…:839`) → REPAIRING release → `exit when
status not in ('DOCKED','ANCHORED')` → head pending order → **`exit when o.id is null`
(`…0007…:857`)** → execute → exit on failure.

0092 re-cuts two hunks, each asserted to occur exactly once:

**Hunk A, the refill.** It replaces `exit when o.id is null;` with:

```
if o.id is null then
  exit when v_refilled;                                   -- at most ONE refill per advance call
  v_refilled := true;
  exit when coalesce(cmd.run_standing_route(p_fleet, p_now), 0) = 0;   -- nothing written: done
  continue;                                               -- run what was just written
end if;
```

**Hunk B, the skip rule for route lines.** It replaces `exit when not coalesce((v_res->>'ok')::boolean, false);` with:

```
if not coalesce((v_res->>'ok')::boolean, false) then
  -- 0092 (D1): a ROUTE's trade line that is refused is stepped over and written on the lap;
  -- a route's SAIL that is refused halts the fleet exactly as every other order does.
  exit when o.route_lap_id is null or o.verb = 'SAIL';
  update public.orders set status = 'skipped' where id = o.id;
  perform cmd.standing_route_note_skip(o.id);   -- appends {stop, line, code} to the open lap
end if;
```

**Why `advance` and not the arrival arm.** `advance` is the one place that *knows the queue is dry
while the fleet is in port*, and every path that should restart a route already goes through it:

- arrival (settle's arrival arm);
- a read of a docked fleet (settle's early path calls `advance`, live settle body);
- the player's own order (`cmd.issue`);
- repair release (`tick_arrivals`, `…0010…:79-84`);
- assign or resume (the new verbs call it).

Hooking the arrival arm instead would need a second call site for assign, resume and repair
release. `cmd.preview` never calls `advance` (live preview body: execute plus a forced rollback), so
a dry run cannot trigger a refill.

**Why this terminates.** Every stop ends with a SAIL. When the SAIL executes, the fleet is SAILING,
and the next loop iteration exits at the status check before it can reach the dry exit. If the SAIL
is refused, the order stays `failed` and the loop exits. The `v_refilled` flag rules out a second
refill in one call regardless, and the existing 64-iteration guard (`…0007…:826`) stays.

**What the halted state is.** When a route's SAIL is refused, the queue holds a `failed` order, and
`advance` exits at `:839` before the dry exit. The route therefore **stops by the existing law**.
"Stopped" is derived in the read (a failed order exists), never stored. The player's CLEAR releases
it (the existing fix path), and the next `advance` refills.

### 4.3 The generator: `cmd.run_standing_route(fleet, now) returns int`

`security definer`, revoked from clients. The **whole body is inside `begin … exception when others`**,
so a bug in it can never abort `tick_arrivals`'s transaction, which runs every player's arrivals in
one transaction (`…0010…:54-87`). On error it sets `paused_reason='error'`, emits `ROUTE_PAUSED`
with the code, and returns 0. That follows the `run_standing_provision` pattern (`…0034…:224-236`).

It returns 0 (writes nothing) when any of these holds:

- the switch is off;
- no route stands on the fleet;
- `paused_reason` is set;
- the fleet is not DOCKED;
- `hold_until > p_now`.

Otherwise it runs these steps in order:

1. **Where is it?** Let `S = stops[cursor]`.
   - If `fleet.port_id = S.port`, work stop S (step 3).
   - If `fleet.port_id = stops[cursor-1].port`, the last SAIL was refused and then cleared. Enqueue
     only `SAIL TO S` with `stops[cursor-1].course` and return.
   - Otherwise set `paused_reason='off_route'`, emit `ROUTE_PAUSED` and return 0. The player sailed
     the fleet somewhere else by hand.
2. **Lap boundary** (when `cursor = 0` and the fleet is at stop 0):
   - Close the open lap (§6).
   - **Loss guard:** if the last `stop_after_losing_laps` closed laps all have `net < 0`, set
     `paused_reason='losing'` and return.
   - **Pacing (D2):** if `standing_route_laps_per_game_day` > 0 and that many laps of this route
     already started in `world.game_day(p_now)` (`…0005…:294`), set `hold_until` to the start of
     the next game-day (`(game_day+1) × game_day_seconds`) and return 0.
   - Open a new lap row (`lap_no+1`) and set `lap_id`.
3. **Reserve guard:** if the company's purse is below `reserve`, set `paused_reason='reserve'`
   and return 0.
4. Render stop S (§3.3). Parse and `cmd.enqueue` each line with `p_lap = lap_id`. Set `cursor :=
   (cursor+1) mod n`. Return the count written.

**The waking loop (the only clock change).** 0092 re-cuts `public.tick_arrivals` (`…0010…:54-87`)
to add a third loop of the same shape as the REPAIRING loop at `:79-84`:

```
for r in select f.id from public.fleets f
           join public.standing_routes sr on sr.fleet_id = f.id
          where sr.paused_reason is null and sr.hold_until is not null and sr.hold_until <= p_now
            and f.status = 'DOCKED'
            for update of f skip locked loop
  update public.standing_routes set hold_until = null where fleet_id = r.id;
  perform cmd.advance(r.id, p_now);
  v_fleets := v_fleets + 1;
end loop;
```

This adds no new cron job and no new schedule: the existing `byeharu-voyage:arrivals` job
(`* * * * *`) drives it. Everything else a route does AFK is already driven by the first loop:
SAILING voyages due → `voyage.settle` → arrival arm → `advance` → refill.

### 4.4 AFK: what already exists and what does not

- **Already exists:** settling due voyages and firing queued orders with nobody reading
  (`tick_arrivals` → settle → arrival arm → `cmd.advance`; `…0010…:54-87`, `…0034…:274-283`).
- **Added by 0092:** the refill (§4.2), the held-route wake loop (§4.3), and the in-transaction
  error containment of the generator.
- **Lag:** up to 60 s from ETA to arrival, which is the cron period. Once a fleet arrives, the
  stop's trades and the next departure happen **in the same transaction**. `voyage.depart`
  departs at `now()` (live `voyage.depart(... p_at default now())`), so each leg loses at most one
  cron period.
- **With the clock stopped** (the state of production today): a route moves one stop per read of
  the fleet, and trades price at the moment of the read. DESIGN.md:427-431's "identical results to
  one whose ticks all ran on time" holds for voyage hazards (seeded) and **does not hold for route
  trades**. Routes need the clock. The runbook's step 4 (`docs/DEPLOY_RUNBOOK.md:113`) becomes a
  hard prerequisite of turning on `standing_routes_enabled`. DESIGN.md §D.2 and `…0010…`'s header
  claim get a one-line note pointing here. The migration itself cannot be edited; the note goes in
  the docs.

---

## 5. The verbs and the read (all dark until the switch)

| Entry point | Args | What it does |
|---|---|---|
| `world.standing_routes()` | — | The company's routes. For each: name, fleet, stops (port code, course, repair, lines), `cursor`, `lap_no`. `state` is derived: `off` (switch), `paused:<reason>`, `stopped` (failed order: code, sentence, figures), `waiting` (`hold_until`, served as the next-lap time), `sailing`, `in_port`. Also the last 10 laps with every figure, and the knobs (`max`, `stop_max`, `laps_per_game_day`, `enabled`). **It settles the route's fleet first**, like every read (DESIGN D.2; `world.fleets` does the same) |
| `cmd.standing_route_save` | `p_route uuid, p_name text, p_stops jsonb, p_reserve bigint, p_losing int` | Create when `p_route` is null, otherwise replace stops and lines whole. Validates port kind, goods, caps and course shape. If the route is assigned, it re-anchors `cursor` to the stop whose port is the fleet's current port or destination; if none matches, it pauses `edited`. Edits take effect at the next refill, because the route is a reference, not a copy |
| `cmd.standing_route_delete` | `p_route` | Deletes the route. Orders already queued stay: `route_lap_id` is set to null, and they become ordinary orders under the ordinary halt law |
| `cmd.standing_route_assign` | `p_route, p_fleet` (null = unassign) | Requires the fleet to be the player's, DOCKED at a port that is one of the stops, and to have a keep level (`E_NO_KEEP`). Sets `cursor` to that stop, clears `paused_reason`, then calls `cmd.advance(p_fleet)` so the route starts now |
| `cmd.standing_route_pause` | `p_route, p_paused boolean` | Pause (`paused_reason='player'`) or resume (clear it and `hold_until`, then `cmd.advance`) |

None of these takes a player id. Each reads `public.current_player_id()`, following the 0034 verbs.
All four `cmd` verbs refuse `E_UNAVAILABLE` while the switch is off.

**Registration.** A slice of `public.client_rpc_entry_points()` anchored on the row
`('cmd','preview_fulfil','uuid, uuid')` (0087's last row) adds five rows. The self-assert requires
every row's `to_regprocedure` to be non-null and `authenticated` to hold EXECUTE on exactly these
five and on none of `cmd.enqueue`, `cmd.run_standing_route`, `cmd.standing_route_lines` or
`cmd.standing_route_note_skip`.

---

## 6. The report: one lap, one line, bounded

**Lap close** (inside the generator, at the stop-0 boundary) fills the open `standing_route_laps`
row from **the executors' own results and the settled voyage days**. Nothing is re-priced:

- `sold` = Σ `result->>'total'` of the lap's `done` SELL orders (do_sell returns `total`; dump
  do_sell lines 1173-1181).
- `bought` = Σ the same for BUY (do_buy returns `total`; dump do_buy lines 505-510).
- `repairs` = Σ `result->>'cost'` of REPAIR (do_repair returns `cost`, live body).
- `supplies` = Σ PROVISION cost. **Confirm do_provision's result key before writing the sum**: it
  emits `cost` on the PROVISIONED event, and the return shape was not read for this document.
- `wages` = Σ the per-day `wages` of the lap's voyages. The voyage ids are in the SAIL orders'
  `result->>'voyage_id'`. This is the *owed* figure; the purse floor may have charged less (live
  settle, the `least(v_wages, purse)` credit).
- `net` = sold − bought − supplies − repairs − wages.
- `stops_done`, and `skipped` (appended by `standing_route_note_skip`).

The close then:

- **Emits one `ROUTE_LAP` event** with those figures and the route and fleet names. It reaches
  History through the existing `world.ledger`. The client adds one headline arm in
  `src/features/ledger/headline.ts` and puts `ROUTE_LAP` and `ROUTE_PAUSED` on the **voyage** face
  in `LedgerScreen.tsx:53-62`.
- **Prunes** that route's lap rows beyond `standing_route_lap_keep`.
- **Prunes the lap's route-born `orders` rows** in status `done` / `skipped` from every lap but the
  newest closed one. `orders` is not append-only (only `events` / `ledger` carry
  `forbid_mutation`, `…0004…:135-150`), and `cmd.queue` shows only pending/active/failed.
  Without this, `orders` grows by about 10 rows per lap for ever.

What stays unbounded is what is already unbounded: `events`, `ledger` and `voyage_events`. §9
measures it.

---

## 7. The UI (owner rules: minimal words, fold in place, no new screen, map is output only)

**Home: COMMAND.** One row, `RouteFold`, sits **above the queue** in
`src/features/command/CommandScreen.tsx` (the `<Queue …>` mount at `:101`).

- **Folded** (one line): `Route · Lisbon ⇄ Cadiz · Lap 12 · +1,240 🪙`. Or `No route` with a
  `Set up route` button. Or a state word: `Paused`, `Stopped`, `Next lap 14:32`.
- **Unfolded, in place** (the row does not move; content below pushes down, which is the
  FleetFold rule, rows 6/15/25/28/45): the stops as rows, `Lisbon — Sell all · Buy salt, 60
  units, Max 12 🪙 each`. Below them, `Pause` / `Resume` and `Edit`, and the last three laps as
  figures. `Stopped` shows the refusal's own sentence and figures (the `Queue.tsx:52-56` Note
  already renders a failed order) with the existing fix, `Clear`.
- **Editing** happens inside the same fold (slice 1: two stops). It uses the existing port picker
  and good picker; the implementer locates them and writes no new picker. Each leg's course comes
  from `proposeCourse` (`src/domain/passage/index.ts:160`), the same author the SAIL order uses.
- **FLEETS:** the fleet row gains a caption word (`On route` / `Stopped` / `Paused`) from the
  served state. There is no fourth column (`FleetFold.tsx` header).
- **MAP (slice 3):** draws the player's own fleet's route line from the served stop courses,
  through `src/chart`'s entrance, with no controls. The module must not be named `route.ts`
  (`src/chart/route.ts` is the voyage track). Use `standingRoute.ts`.
- **No client arithmetic.** Every figure (lap net, next-lap time, keep days, Max) is served. The
  client formats with `src/lib/format`.
- **No cross-port suggestions.** The editor never ranks or proposes ports. The owner removed
  cross-port comparison: "the game is to challenge players" (`…0071…:5-15`,
  `src/features/command/README.md:66`).

**Words (D6; new rows in `docs/WORDS.md`, bans added to `tests/words.spec.ts`):**

| Concept | Say | Never |
|---|---|---|
| a loop of ports a fleet sails by itself | **Route** (`Set up route`, `Route · Lisbon ⇄ Cadiz`) | trade route, circuit, template, standing route (wire only) |
| one full turn of it | **Lap** (`Lap 12 · +1,240 🪙`) | circuit, round, cycle |
| a route not running by the player's choice | **Paused** / **Resume** | suspended, idle |
| a route halted by a refusal | **Stopped** + the refusal's sentence | failed, halted, error |
| pacing | `Next lap 14:32` | cooldown, fatigue |
| money kept back | **Keep at least** `5,000 🪙` | reserve, floor |
| "only sell at a profit" | **Only sell above cost** | at profit, basis |

---

## 8. Balance: can an AFK route print infinite money?

**What already damps it (all live).**

1. **Daily cap** per (company, port, good, game-day) = 0.35 × `stock_target` × skill
   (`world.daily_cap_remaining`, `…0027…:445`; DESIGN G.7 rule 1). It is keyed on the **company**,
   not the fleet, so ten fleets on one pair share one cap.
2. **Price impact is mandatory** (G.7 rule 2), and the price band is clamped to [0.35, 3.50] ×
   base (rule 3).
3. **Regeneration** closes 15 % of the gap to target per game-day (`…0010…:111-117`). A sustained
   buy of more than about 15 % of target per game-day drains stock and drives the ask toward the
   clamp. A sustained sell floods stock and drives the bid down. The spread between two ports
   narrows toward what the regeneration rate can refill.
4. **Spread plus tax** make a same-port round trip a loss (rule 4).
5. **Wages per sea-day** (0086), supplies, the port fee in every quote, repairs.
6. **Danger:** STORM and SHOAL damage, PIRATES up to STRIPPED (cargo emptied), crew loss
   (`…0027…:326-381`). No ship is lost; UNABLE_TO_SAIL stops the route.

**Verdict.**

- **It is not infinite money.** Per (company, port, good), income per game-day is bounded by the
  cap and by the regeneration equilibrium, and pacing (D2) keeps laps to about one per game-day,
  which is where the cap resets anyway. Income is **linear in the number of distinct (port, good)
  pairs a company works**, not in laps.
- **It is not enough on its own**, for three reasons:
  - (a) Passive income scales with the number of fleets on different pairs.
  - (b) **Rank inflates.** Trading XP reads `BOUGHT`/`SOLD` (`…0069…:149`), and route fatigue
    (DESIGN.md:1112) was never built.
  - (c) Nobody has measured the equilibrium income of a saturated two-port route.
- **Dampers this design adds:** `standing_route_max` (3 per company, D7); pacing (D2); the losing-lap
  guard.
- **Owner rulings needed:** D4 (rank). Slice 4's measurement must also run before the switch is on
  for everyone: a 30-game-day PGlite run of one two-port route with `scripts/db/tune-balance.mjs` /
  `breaktest-balance.mjs`, reporting net per lap until it converges.

---

## 9. Hazards of running for ever, and what handles each

| Hazard | Handled by |
|---|---|
| A trade line is refused AFK (E_DAILY_CAP, E_NO_CARGO after STRIPPED, E_HOLD_FULL, E_NO_STOCK, E_INSUFFICIENT_FUNDS, E_PRICE_LIMIT, E_UNAVAILABLE on REPAIR with nothing to repair) | D1: `skipped`, noted on the lap, the lap continues |
| SELL ALL over the day's cap refuses the **whole** sale, so cargo rides round unsold | Partly by pacing, which gives a fresh cap each visit. Fully by **D3** (slice 2): `SELL … ALL` sized to the day's allowance, a sibling of `fleet_buy_capacity`, in the one authority `do_sell` |
| SAIL refused (E_ENDURANCE after FOUL_WATER, E_CREW_SHORT after a raid, E_FLAGSHIP_DISABLED, E_NO_COURSE / E_LAND) | The existing halt law. The route shows `Stopped` and the player's `Clear` resumes. Slice 2 option: a "Hire to full crew" stop line (HIRE is a queue verb) |
| A transient lock (deadlock with the drift tick's whole-table `port_goods` update, named in the 0083 header) is recorded as a refusal | Trade line: skipped, retried next lap. SAIL: `Stopped`, which is conservative. Slice 2: treat SQLSTATE 40P01/55P03 on a route order as "leave pending, retry next tick" |
| A bug in the generator aborts every player's arrivals for that minute | The generator's own `exception when others` pauses that route only (§4.3). Slice 2: per-fleet sub-transactions in `tick_arrivals` for every fleet |
| Money runs out (wages at the floor, BUY refused) | The `reserve` guard pauses before buying. The losing-lap guard pauses after N losing laps |
| Two devices: a refill bumps `version`, so the player's own `cmd.issue` hits `E_STALE` more often | The existing E_STALE fix (`reload and try again`). The read serves the new version |
| **Row growth / disk.** Each paid sea-day writes one `ledger` WAGES row (live settle, `public.credit(…,'WAGES',…)` in the day loop), and per the mechanism audit one `voyage_events` row. At `time_compression` 9600 a sea-day is 9 real seconds (`…0045…`), so a fleet at sea non-stop writes up to about 9,600 ledger rows and about 9,600 voyage-event rows **per real day**. `events` / `ledger` can never be pruned. The project is believed to be on the Free plan (500 MB; a past read-only outage is recorded at `…0057…:8-16`). **Current size is unverified** | Pacing (D2) cuts a fleet's sea time to lap time × laps per real day, and the orders/laps pruning in §6 applies. **D5 is an owner and ops decision:** read `pg_database_size` on production and measure a paced route's rows per lap in PGlite **before** the switch goes on. A per-voyage wage roll-up would be its own migration and must keep proof 01's arithmetic |
| Rank inflation from AFK BOUGHT/SOLD | D4 |
| Requests (0087) cannot be fulfilled AFK: `cmd.fulfil` is client-direct with no queue verb (`…0087…:481`) | Out of scope. A later FULFIL stop line composes `cmd.run_fulfil` |

---

## 10. Slices

### Slice 1: the server, plus the smallest client that shows it running (migration **0092**)

**Migration `supabase/migrations/20260818000092_a_route_is_a_standing_order_that_sails.sql`**
adds a new file and edits no existing one. If another PR claims 0092 first, take the next free
number. Its contents, in order:

1. The knobs (§3.2), with the switch **off**.
2. Tables, cap triggers, RLS, read grants (§3.1), and `orders.route_lap_id`.
3. `cmd.enqueue`, and the slice of `cmd.issue` that calls it (§4.1).
4. `cmd.standing_route_lines`, `cmd.run_standing_route`, `cmd.standing_route_note_skip`, and lap
   close and prune (§3.3, §4.3, §6).
5. Re-cuts, each hunk exactly once, LF-normalised, with pre-images saved for parity:
   - `cmd.advance`, hunks A and B (§4.2);
   - `cmd.run_standing_provision`, the route early return (§3.4);
   - `public.tick_arrivals`, the wake loop (§4.3).
6. The read and the four verbs (§5); the `client_rpc_entry_points` slice; grants and revokes.
7. **Self-asserts.** Each runs in the migration's transaction, turns the switch on locally, and
   restores it:
   - **PARITY:** `cmd.issue` responses are byte-identical before and after on a probe fleet
     (including E_QUEUE_FULL at 13). `cmd.advance` on a route-less fleet with
     `[failed, pending]` still halts with the pending order untouched. **The law is unchanged
     for ordinary orders.**
   - **AFK LAP:** a two-stop route on a probe fleet. Assign at A: SELL / PROVISION / BUY / SAIL
     are enqueued with `route_lap_id` and the fleet is SAILING. Warp the ETA, then call
     `tick_arrivals()` **only**, with no read. The fleet arrives at B, B's lines run, and it sails
     back. Arriving at A closes lap 1: `net` = Σ executor results − wages; a `ROUTE_LAP` row is
     visible through `world.ledger`; the pruned orders are gone.
   - **PACING:** at `laps_per_game_day = 1` the second lap is held (`hold_until` = next game-day)
     and no order is written. After warping past it, `tick_arrivals()` wakes the fleet and the lap
     starts.
   - **SKIP:** zero the stock of the BUY good. The BUY becomes `skipped`, the lap notes
     `E_NO_STOCK`, and the SAIL still departs.
   - **STOP:** set flagship durability to 0 before the SAIL. The SAIL is `failed`, the read says
     `stopped`, and the next `advance` writes nothing. CLEAR plus `advance` resumes.
   - **GUARDS:** purse < reserve leads to `paused:reserve`. N forced losing laps lead to
     `paused:losing`. Moving the fleet by hand to a third port leads to `paused:off_route`. A
     4th route is refused by the cap.
   - **CONTAINMENT:** make the generator raise (a probe route whose stop port has been
     un-harboured inside the transaction). `tick_arrivals()` still returns, the route is
     `paused:error`, and a second fleet's arrival in the same tick settled.
   - **DARK:** with the switch off, an assigned route writes nothing and the four verbs refuse
     `E_UNAVAILABLE`.
   - **RESUPPLY:** a route fleet arriving full writes no PROVISION_REFUSED. Its keep level is
     reached by the queued PROVISION after the SELL.
   - **GRAMMAR:** every line kind renders and parses round-trip through `cmd.parse`.
   - **DOORS:** every new registry row resolves; the executors are revoked;
     `client_write_grants()` has no row for the new tables.

**Other server files:**
- `supabase/migrations/CHAIN.md`: a 0092 row.
- `tests/db.chain.spec.ts:262`: the `LAST` pin moves to 0092.
- `scripts/db/proofs/11_standing_route.sql` (new): the client door as `authenticated` (the proof
  07 shape, `scripts/db/proofs/07_standing_provision.sql:1-30`). It covers the read and the four
  verbs, RLS isolation between two companies, and the AFK lap through `tick_arrivals` with no
  read.
- `scripts/db/breaktest-0092.mjs` (optional, the repo pattern).

**Client files:**
- `src/lib/rpc/catalog.ts`: five entries beside the 0034 block (`:266-293`). One catalogue builds
  both backends (`tests/rpc.surface.spec.ts:1311`).
- `src/lib/rpc/types.ts`: `StandingRoute`, `StandingRouteBook`, lap types.
- `src/features/command/RouteFold.tsx` (new), with its §7B header.
- `src/features/command/standingRouteDraft.ts` (new, pure): editor draft → `p_stops` payload.
  Legs come from `proposeCourse`. No figures.
- `src/features/command/CommandScreen.tsx`: mount above `<Queue>` (`:101`).
- `src/features/command/README.md`.
- `src/features/fleets/FleetsScreen.tsx` (or the row component it uses): the caption word.
- `src/features/ledger/headline.ts` and `LedgerScreen.tsx:53-62`: `ROUTE_LAP`, `ROUTE_PAUSED`.
- `tests/layout.spec.ts`: RouteFold folds in place at 390×844.
- `tests/wide.layout.spec.ts`.
- `tests/words.spec.ts`: the new bans.

**Docs:**
- `docs/WORDS.md` (§7 rows).
- `docs/TRADE_ROUTES.md` (this file).
- `docs/DEV_LOG.md`.
- `docs/OWNER_REQUESTS.md` (new row).
- `docs/DESIGN.md`: notes at §D.2 (lines 427-431), §F.3 templates (932-934) and G.7.5 (1112),
  pointing here.
- `docs/DEPLOY_RUNBOOK.md`: step 4 is now required before routes are switched on.

**Slice 1's client scope is deliberately small:** create a two-stop route from the fleet's current
port and one picked port, one SELL-everything line and one optional BUY (good, units, Max) per stop,
a keep level, then assign, pause and resume, and watch the laps arrive in History.

**Before the switch goes on in production (a separate owner-approved step, not part of the PR):**
- deploy 0092 by the runbook;
- `select public.wind_the_clock();` and re-read `public.clock_jobs()`, which must show all
  `active`;
- D5's size read;
- then `update world_config set value='true' where key='standing_routes_enabled'`.

### Slice 2: the rich editor and AFK hardening (migration **0093**)
- Editor: up to 6 stops, reordering, several lines per stop, `Only sell above cost`, `Keep at
  least`, losing-laps setting, and editing while running (the re-anchor rules in §5).
- **Repair if damaged over X %:** a served worst-damage figure. Today the client computes
  `1 - worst` in `src/features/port/PortShipyard.tsx:63`; it moves to one server reader, and
  PortShipyard reads it too, so there is one authority.
- **D3:** `SELL … ALL` sized to the day's allowance.
- A "Hire to full crew" line.
- Deadlock retry on route orders.
- Per-fleet sub-transactions in `tick_arrivals`.

### Slice 3: map line and lap analytics (client, plus a read if needed)
- MAP draws the player's own route through `src/chart/standingRoute.ts`, from the served courses.
- History groups route-born BOUGHT/SOLD under their lap line. This needs a decision on how an
  event names its lap. Candidate: the `orders.route_lap_id` → order `result` join served by the
  read, **not** a side channel into `emit_event`.
- A lap trend (net per lap) as a served series.

### Slice 4: balance (migration **0094** if knobs or rules change)
- The PGlite saturation measurement (§8).
- D4: rank. Either build route fatigue (DESIGN.md:1112) on trading XP, or have route-born trades
  earn reduced XP.
- Tune `standing_route_max` and pacing from the measured numbers.

---

## 11. Decisions only the owner can make

| # | Question | This design's default |
|---|---|---|
| **D1** | A route's trade line is refused while you are away. Stop the route, or step over the line and keep going? | Step over trade lines and note them on the lap. **Stop on a refused SAIL** (never sail without supplies or crew). This is a bounded exception to DESIGN F.3 (DESIGN.md:928-931), for route lines only |
| **D2** | How often may a route start a lap? | Once per game-day (48 real minutes), because the day's trade allowance resets then. 0 = as fast as the ship sails, which costs disk (§9) |
| **D3** | Should `SELL x ALL` sell what today's allowance takes instead of refusing the whole sale? This changes manual play too | Yes, in slice 2, matching what `BUY ALL` already does |
| **D4** | Should AFK trading raise your rank as much as hand trading? | No. Build route fatigue or a reduced XP rate in slice 4 |
| **D5** | Disk. Measure first; if routes would outgrow the free plan, cut sea-day rows or upgrade? | Measure before switching on. No change until numbers exist |
| **D6** | Words: **Route**, **Lap**, **Paused**, **Stopped**, **Keep at least**, **Only sell above cost** | As in §7 |
| **D7** | Routes per company, stops per route | 3 and 6 |

---

## 12. Known state at the time of writing (deploy reality, read on 2026-09-30)

- Production DB head is **0091**: `supabase migration list --linked` shows 0086-0091 on both
  sides. `docs/DEV_LOG.md:8,44` still says they must be pushed; the log is behind production.
- **pg_cron on production: all five `byeharu-voyage:*` jobs defined, all `active: false`.**
  Arrivals, drift, reconcile, price snapshot and the buff calendar are not running on schedule.
  Restarting them is a production write (`docs/DEPLOY_RUNBOOK.md:113`) and needs the owner.
- The live site is built from `a613a05` and pointed at production (`olaquvizoavjeiricyxk`).
- Not verified here:
  - the production database size (D5);
  - whether the drift cadence mismatch matters (`drift_slot_seconds` 900 since `…0071…:81-87`
    against cron `*/10`);
  - do_provision's result key (§6) — **since verified: `cost`** (§13);
  - REPAIR's exact grammar form (§3.3) — **since verified: `REPAIR`** (§13).

---

## 13. Slice 1 as built (2026-09-30, branch `osn-trade-routes`)

**Built and proven locally (PGlite, real Postgres 18.3). NOT merged, NOT deployed; the switch ships
OFF.** What differs from the plan above, each for a stated reason:

- **`cursor` is `stop_cursor`** in the table (a plpgsql keyword avoided); the read still serves the
  key `cursor`.
- **REPAIR's grammar** is `REPAIR` alone (`cmd.parse`'s REPAIR arm defaults `to_pct` to 100).
- **do_provision returns `cost`** (read in the live body), so `supplies` sums `result->>'cost'`.
- **One judge for "is the keep level met":** `public.keep_level_met(fleet, days)` holds 0034's
  0.01-day tolerance; `cmd.run_standing_provision` is sliced to call it (a second hunk, parity
  proven) and the renderer calls it, so the route renders `PROVISION DAYS n` only when the level
  is not met — otherwise every lap would carry a skipped `E_HOLD_FULL`.
- **Lines per stop** are capped at `order_queue_max − 3` by a table trigger (room for PROVISION,
  REPAIR, SAIL); only the "sell everything" expansion can overflow, and it is trimmed with
  `E_QUEUE_FULL` notes as planned.
- **A lap is opened at the first stop worked** if none is open, so a route assigned at stop k > 0
  still tags its orders with a lap.
- **`cmd.issue` parity** is proven on 18 orders (BUY, SELL, E_PARSE, E_STALE, SAIL, 12 queued, then
  E_QUEUE_FULL), against the pre-image re-created as `pg_temp.issue_before_0092`, with uuids
  normalised.
- **The port picker moved, it was not copied.** A screen may not import another screen
  (`tests/sections.spec.ts`), so `PortField` moved from `features/port/` to `src/live/PortField.tsx`
  (it gained an optional `onPick`) and its ranking `nearbyHarbours` moved to `src/domain/port`. The
  editor's "good picker" is the stop port's served market (`world.market`) as chips.
- **The route words** (state word, pause sentence, stop line, FLEETS caption) live in
  `src/domain/route` because FLEETS and COMMAND both read them.
- **The keep level is set on FLEETS**, not in the route editor; the editor prints the server's
  `E_NO_KEEP` refusal.

**Measured (PGlite, the migration's probe and proof 11):** a two-stop Lisbon ⇄ Funchal route
carrying 20 units of iron ran **four laps from `tick_arrivals` alone** and **lost money every time it
was measured**: −152 🪙 over four laps on one apply (wages 80 🪙 a lap), −543 🪙 over four laps in the
full `npm run db:proof` run (each apply deals a different market). The purse moved exactly the laps'
net, to the ducat, in both. This is one route with one good, not the §8 saturation measurement — it
only shows that a route is not profitable by construction, and that the lap line is the money.

### 13.1 The adversarial review of 0092, applied forward as 0093 (2026-09-30)

0092 was reviewed before it was merged or deployed. It is **not edited** (the no-edit law); migration
`20260818000093_a_route_is_known_by_its_id_and_waits_behind_its_fleet.sql` supersedes it forward,
and **the two are pushed together or not at all**.

| # | Finding | Outcome |
|---|---|---|
| MUST 1 | A refused Start (`E_NO_KEEP`) left a route with no fleet that the fold never listed; the next Start (same generated name) was `E_NAME_TAKEN` with no way out, and it held a place under the cap of 3. | **Fixed.** The name index is dropped (a name is a label; every verb takes the id) and save's `E_NAME_TAKEN` arm goes with it. `RouteFold` lists routes without a fleet (`routesWithoutFleet`) with Start (on this fleet, by id), Edit and Delete. Two fleets may now run the same pair of ports. |
| SHOULD 2 | assign / pause locked the route, then the fleet (via `cmd.advance`); settle, issue, the tick and the read lock the fleet, then the route — a deadlock with the minute tick. | **Fixed.** assign, pause and delete lock the fleet(s) first (in id order), then the route; a route that changed fleets in between answers `E_BUSY`. The read settles its fleets in id order. The lock at `run_standing_route`'s head was left where it is: with one lock order it no longer waits in the wrong direction. |
| SHOULD 3 | Pause sentences printed port codes and a bare number; `E_ROUTE_BROKEN` sentences printed raw order text and error codes. | **Fixed.** Server sentences name ports and carry no figure; `E_ROUTE_BROKEN` says what happened in words. History words `ROUTE_PAUSED` from the REASON in `src/domain/route` (the server sentence only for `error`). |
| SHOULD 4 | A fleet unable to sail read "On route" for ever. | **Fixed.** The read serves `blocked` for any status but DOCKED / SAILING / REPAIRING; the fold says so; FLEETS says `Blocked`. |
| SHOULD 5 | The arrival order stood aside whenever a route was running, even when the route would not refill (the player's own onward order queued, or an off-route port) — the fleet sailed unsupplied. | **Fixed.** It stands aside only when nothing is pending or failed in the queue and the fleet is at the stop the route is bound for. |
| SHOULD 6 | The editor offered goods the port does not sell (`offered:false`, `available:false`). | **Fixed** in `RouteEditor`. |
| NIT 7 | The skip rule ran with the switch off. | **Fixed:** gated on `standing_routes_on()`. |
| NIT 8 | After CLEAR only a read (or an order) restarts the route. | **Not changed.** `cmd.clear` is 0007's and every client CLEAR re-reads the world (`worldStore.clear` → `refresh`); a caller other than the app must read or issue. Recorded here. |
| NIT 9 | Lap summaries did not add up to the net. | **Fixed:** History lists supplies and repairs; the fold's lap line lists repairs when there were any. |
| NIT 10 | Assign cleared `lap_id` without closing the lap. | **Fixed:** the one closer runs when a route changes fleet or is taken off one. |
| NIT 11 | Edit dropped lines the editor cannot show. | **Fixed:** the draft carries REPAIR, the sell-all floor and every other line through untouched. |
| (found in the re-cut) | A REFUSED assign to another fleet had already released the old fleet's pending route orders. | **Fixed:** every check runs before anything changes. |

### 13.2 Driven in a browser, fixed forward as 0094 (2026-09-30)

The branch was driven as a player in Chrome against `vite preview` with PGlite in the tab (switch
turned on in the tab's own database for the drive; no migration edited). Everything in slice 1's
client scope worked: set up, the refused Start listed as `No fleet`, Start, laps by themselves,
History lap lines, Pause / Resume / Edit / Delete, `Blocked`. Two defects, fixed by migration
`20260818000094_a_resumed_route_sails_and_a_deleted_one_closes_its_lap.sql` (0092/0093 not edited;
the three are pushed together):

| # | Finding | Outcome |
|---|---|---|
| 1 | After a `losing` pause, Resume re-judged the same closed laps and paused again on the spot; no lap ran, and only Delete got out. | **Fixed.** The loss guard is judged only when the call has just closed a lap. Resume sails one more lap; if it loses too, the route pauses again at its end. |
| 2 | Delete mid-lap cascaded the open lap away with no ROUTE_LAP line, so its trades had no lap in History. | **Fixed.** Delete closes the open lap with the one closer first. |

**Measured profitability.** Lisbon ⇄ Porto (cork) lost every lap (−210, −259, −36, −455 🪙 on the
first build). Beirut ⇄ Tripoli (pistachios, Max 180, unpaced) made **+2,531, +1,399, +250, −18 🪙**:
a route pays on a real margin and saturates in about three laps without pacing. The §8 saturation
measurement at the default pace is still owed.

**Seen, not this PR's code:** an UNABLE_TO_SAIL fleet cannot be repaired in port (REPAIR stays
pending; Port → Repair says the fleet is at sea), so `Blocked` has no way out in play; History ties
within one transaction are unordered; FLEETS prints `hull`; History says `arrived to`.


### 13.3 Built by the merchant work (0096, 2026-10-08, `docs/NPC_TRADERS.md`) — and a stated change for live players

- **D3 is built.** `SELL <good> ALL` over the day's allowance now sells what the allowance takes instead
  of refusing the whole parcel (one hunk in `cmd.do_sell`); an EXPLICIT quantity over the allowance still
  refuses whole, byte-identically. Self-asserted in 0096.
- **THE PACING RULE IS AN INTERVAL, NOT A CALENDAR.** 0092 held every route until the next game-day
  BOUNDARY — one instant for every route on earth. 0096 re-cuts that one hunk: a lap may start
  `game_day_seconds / N` after the LAST lap started (N = the route's own `laps_per_game_day`, else the
  knob, 1). **For a player the number is unchanged — one lap per game-day — but its anchor moves from
  the calendar to the lap.** 0092's "six unpaced ticks run three laps" is re-stated for the interval form.
- **`crew_up`** — a stop option (hire back to `crew_required` before sailing on), rendered by ONE tail
  (`cmd.standing_route_tail`) that both refill branches now call, so the sail-on branch can hire too. The
  editor carries the flag through untouched, as it does `repair`, until it gains the checkbox.
- **The repeated-harbour anchor** (`min(ord)` in save and assign) prefers the stop the cursor names, so a
  loop that calls at one harbour twice no longer resets to the first visit on an edit.
