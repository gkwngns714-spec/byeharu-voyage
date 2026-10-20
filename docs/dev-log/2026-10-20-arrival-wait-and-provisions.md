# 2026-10-20 — the arrival wait, and what the hold is made of (owner rows 170 and 179, `osn-arrival-and-provisions`)

Two owner questions from 2026-10-20. Both are "why does it do this", so **the answer is the deliverable**. Nothing in this
branch is a migration and nothing in it changes a rule: one client-only fix, one new reading, and this note.

---

# Question A (row 170) — the arrival wait

> *"When arriving a city, why is there a waiting time? Arrives in (min)??? This should be gone, meaning it should arrive
> at city as soon as it reaches it."*

## The short answer

**There is no waiting time at the city. Your fleet is already docked the moment she arrives.** What you were reading as a
wait was the voyage's own remaining time — the countdown to her arrival — and on the COMMAND tab it was drawn in a way
that made a moving figure look like a stationary one. That is fixed in this branch, and it is a drawing change only: no
rule, no knob, no migration.

Two things were wrong with how that one figure was drawn, and both of them are exactly the thing you saw:

1. **It did not tick.** It counted against the instant of the **last server read**, not against the clock. Between two
   reads it did not move at all: the row said "arrives in 1m" and went on saying "arrives in 1m".
2. **It was rounded to whole minutes.** It used the repo's short-duration format, which deliberately throws the seconds
   away so a figure fits a narrow cell. Its own comment in the code says a countdown drawn with it *"would only move once
   a minute and read as stuck"* — and that is what had happened. So the last thing you saw before she docked was a whole
   minute, standing still. Hence "(min)???".

The MAP tab never had this: its voyage tray has always counted down second by second on the live clock. The two tabs were
showing the same arrival two different ways, and the COMMAND one looked like a wait.

## The four candidate waits, each measured

These are every wait that could plausibly have been it, and what each one really is.

| | what it is | how long, really | does it delay YOUR arrival? |
|---|---|---|---|
| **1. The arrivals sweep** | `byeharu-voyage:arrivals` → `public.tick_arrivals()`, on pg_cron every **15 seconds** (set by migration 0125; `* * * * *` before that) | 15 s between runs, ~3.5 s a run | **No.** See below — this is the important one |
| **2. The served ETA** | the voyage's own remaining sailing time, which is what "arrives in" means | the rest of the passage | No. It *is* the passage |
| **3. A merchant's rest in port** | `route_rest_voyage_days`, cut to **120 real seconds** by migration 0116 | 2 real minutes | **No.** Merchants only, and it is a rest before *departing* |
| **4. An arrival held by the hour** | a fleet coming due while the hourly reconcile held its locks | **up to ~72 seconds** — and it was real | **No**, and migration 0137 removed it |

### 1. The 15-second sweep does not gate your own fleet

This is the one worth stating plainly, because it is the natural suspicion and it is wrong.

A player's fleet is **not** docked by the sweep. It is docked by the read. Migration 0009 ("THE WORLD READS BACK") opens
with this as its first law:

> *"EVERY READ SETTLES FIRST: every read RPC that touches a fleet first calls `voyage.settle(fleet_id)`. A player who
> opens the app after nine hours offline must not see a stale fleet and then watch it teleport; the read IS the catch-up."*

It asserts it, too: `world.fleets()` alone reports a nine-hour-stale voyage as DOCKED at its destination **with no tick
having run**. So whenever the client asks, the asking is what lands her.

And the client asks often. `AppShell.tsx` reads the world several times per voyage-day, derived from the served clock
rather than typed: `86400 / time_compression / 12` seconds, clamped to 3–30 s. At the live compression of **960** that is
**7.5 seconds**. It also reads immediately whenever the tab regains focus.

So the true figure is: **your fleet is docked within about 7.5 seconds of her real arrival, and instantly if you come back
to the tab.** Not minutes. The 15-second sweep matters to the world's own merchants and to what happens *after* an
arrival — trading, closing a lap, the next departure — never to whether your own hull is on the quay.

Migration 0125 then went further for the merchants: "in port" became a pure function of time (`voyage.where_now`), so a
merchant is shown docked the moment she truly arrives rather than when the sweep reaches her.

**What dropping the sweep's 15 seconds would cost, since the question invites it.** It should not be touched for this.
The cadence is an economy-wide knob, not a display setting: that one job also runs every merchant's trading, every lap
close and every next departure, under a 10-second wall-clock budget (`arrivals_tick_budget_ms`). Making it faster
multiplies the whole merchant economy's tick rate and the lock traffic against the market drift and the hourly reconcile
— which is precisely the class of problem migration 0137 was written to clean up. It buys a player nothing, because a
player's own arrival does not wait for it. If it is ever changed it needs its own measured window, not a UI slice.

### 4. The one wait that really was minutes-shaped — and is already gone

Worth recording, because it is the only thing in the history that genuinely stalled an arrival for something like a
minute. Migration **0137** ("AN ARRIVAL NEVER WAITS FOR THE HOUR") measured it on prod over 2026-10-15/16: every arrivals
run over 12 seconds in that window ended within half a second of another job's commit. `public.npc_tend`, inside the
hourly reconcile, took a lock on **every** merchant fleet on its walk (837 of them) and held it until the whole hour
committed 60–80 seconds later. `voyage.settle` opens with a *waiting* lock on the fleet row, so a merchant who came due
during the reconcile was held at that line until the hour finished. Observed arrivals runs: 17–72 seconds.

0137 cut the hour into per-merchant transactions, so a merchant's locks now live for her own step (milliseconds) instead
of for the hour. It was merchant business in any case — the hour walks merchant routes, not players' fleets — but it is
the only "arrival waited for minutes" in the record, and it is fixed.

## What changed in the code (client only)

| file | change |
|---|---|
| `src/features/command/Queue.tsx` | the sailing row and the "arrives in" caption now count down on the shell's one clock with `formatCountdown` (`0:48`, ticking every second) instead of a minute-rounded figure frozen at `readAt`. Past the instant the word is **"due"**, never "arrived" — the next read is what lands her, and the client still never decides an arrival on its own |
| `src/features/command/FleetPicker.tsx` | its where-line countdown moves to the same clock, so the picker and the queue still never show two different arrivals (the invariant its header has always carried) |
| `src/features/command/plans/Plans.tsx` | stops threading the now-unused `readAt` prop |

No server change. No migration. The instant itself is untouched: it is still the server's `eta`, read once in
`domain/fleet`, and the clock is a display value only, exactly as `shellState.ts` requires.

---

# Question B (row 179) — provisions and cargo

> *"I told you that cargo space should also consider provision. Right now provision cargo is separate, but I may be wrong.
> If so, show how much cargo is consist of. % of provision, % of trade goods and so on. The provision should also depend
> on how many crews we are holding. Less crew will be needing less food. But each ship should have minimum crew number to
> have the ship specs 100% losing crew will diminish the 100% potency."*

You said "I may be wrong", so here is the truth first. **You were wrong on the first two, and the third already exists in
part.** All three of the rules you asked for are, substantially, already in the game.

## 1. Do provisions already come out of the same hold as trade goods? — YES

They always have. There is no separate provisions pool. The one answer to "how much room is left" is
`public.fleet_free_hold` (migration 0017, superseding 0007), and it reads, in full:

```sql
sum(greatest(0, public.ship_hold_capacity(s.id)
                - public.ship_cargo_tuns(s.id) - s.water_t - s.food_t))
```

`water_t` and `food_t` are subtracted from the **same** stowed capacity as the cargo. The design puts it in one line:
**"every tun of water is a tun of pepper you did not carry."** `docs/SHIPS_AND_GEAR.md` lists the hold stat's readers as
"cargo, stores, speed-by-load" — one hold, three claims on it.

So nothing needed building. What was missing was not the rule but **the reading**: the hold gauge prints `51 / 60 tons`
and says nothing about which of the 51 are barrels and which are pepper. That is the one thing this branch builds — see
below.

## 2. Do provisions already scale with crew? — YES

Per ship, per day at sea (`voyage.settle`, since migration 0007):

```sql
water_t = greatest(0, water_t - s.crew * wc_num('water_per_crew_day'))
food_t  = greatest(0, food_t  - s.crew * wc_num('food_per_crew_day'))
```

Endurance is the same arithmetic backwards — `water_t / (crew × water_per_crew_day)`, the smaller of water and food — and
the standing provisioning order tops up to `days × crew × per_crew_day`. So **a smaller crew already eats less, carries
fewer barrels, and leaves more hold free for cargo.** Your sentence "less crew will be needing less food" is already the
rule; discharging hands in port is already a real trade of fighting strength and speed for cargo space.

## 3. Is there a minimum crew per class, and does falling below it hurt? — YES, but as a cliff, not a curve

- **The minimum exists per class.** `ship_classes.crew_required` (and `crew_max` as the berth ceiling), both served to the
  client on every ship row. Examples: barca 8/20, carlat 12/30, xebec 28/90, nau 60/140.
- **Falling below it is refused outright for a departure.** `cmd.do_sail` returns `E_CREW_SHORT` with the two figures if
  any hull is under its complement. You cannot *set out* short-handed at all.
- **Falling below it at sea costs speed.** `voyage.ship_speed`: `M_crew = crew_short_speed_mult` when
  `crew < crew_required`, and that knob is **0.70**. A hull that loses hands to a storm or a raid sails at 70 % for the
  rest of the passage.

So what you asked for exists, with one honest gap: it is **one flat cliff on one stat**, not a potency curve across the
ship's specs. At `crew_required` she is at 100 %; one hand below it she is at 70 % speed and nothing else moves. Handling,
accuracy, sighting and the escort score do not read the shortfall at all (the escort reads the crew *count*, `crew × 0.02`,
which is a different thing). That is the part that is genuinely not built.

## What this branch builds: the cargo breakdown (client only)

Your fallback ask — *"show how much cargo is consist of. % of provision, % of trade goods and so on"* — is purely a
reading, so it is safe and it is here.

**Where to find it:** FLEETS tab → press a fleet to unfold her → the **Cargo** column, under the goods rows.

**What it shows:** her stowed hold split three ways, each as a percentage **and** a tonnage, because a share never prints
without its whole:

- **Trade goods** — the served `cargo_tuns`, bulk already applied
- **Provisions** — water and food, the stores that compete for the same hold
- **Empty** — the rest

| file | change |
|---|---|
| `src/domain/fleet/derive.ts` | `fleetHoldBreakdown(fleet)` — the one fold, pure, over figures the server already serves. Exported through `src/domain/fleet/index.ts` |
| `src/features/fleets/FleetHold.tsx` | the face: three `Bar`s of the game's one bar primitive, not a new split-bar primitive |
| `src/features/fleets/FleetCargo.tsx` | mounts it under the cargo rows |
| `src/lib/i18n/dict/fleets.ts` | the words, English and Korean |

Two deliberate restraints:

- **It is not a second answer to "is there room".** `domain/fleet/index.ts` carries a standing rule that the client may
  never re-derive the free hold: that is the server's `FleetView.free_hold`, and the three client copies that once
  answered it were deleted (one of them had been wrong for its whole life). The "Empty" share here is the remainder of
  the same `used / total` the gauge beside it already draws, so the picture can never contradict the bar. The served
  `free_hold` remains the only figure anything decides on, and it still owns the gauge's warning colour.
- **Three bars, not one stacked bar.** `Bar` is deliberately one primitive with two forms; a three-segment stack would be
  a third, and a 4 px track split three ways is unreadable on a phone besides.

## What this branch deliberately does NOT build

The other three parts of row 179 all change live play, so each needs a migration and its own measured window. Nothing
below is in this branch. What each would involve:

### (a) Provisions scaled by crew — **already done; nothing to build**

Covered above. If what you actually want is for the *standing provisioning order* to re-aim itself when you hire or
discharge, note that it already does: it tops up to `days × crew × per_crew_day` at every port, so the barrels follow the
headcount by themselves. No change needed.

### (b) A per-class minimum crew — **already done; nothing to build**

`ship_classes.crew_required` exists per class, is served to the client, is refused at departure (`E_CREW_SHORT`) and is
already read by the speed penalty. No change needed.

### (c) A potency curve below the minimum — **the one real gap**

Today: one cliff, `crew_short_speed_mult` 0.70, on speed alone. What you described is a *curve* — effectiveness falling
with the shortfall, across the ship's specs rather than one of them.

| | |
|---|---|
| **the shape** | one new reading, say `public.crew_potency(ship)` → `clamp(crew / crew_required, floor, 1)`, with a `crew_potency_floor` knob so a skeleton crew is crippled and not zero |
| **where it bites** | `voyage.ship_speed` (replacing the 0.70 cliff with the curve — at `crew = crew_required` it must return exactly 1.0, so the hunk is provably a no-op for every fully-manned hull), and `world.ship_stats` for handling / accuracy / sighting. `voyage.escort_score` is the open question: it already reads the crew count, so multiplying by potency as well would double-count the same shortfall |
| **the migration** | supersede `voyage.ship_speed` by slicing the one `v_crew :=` line out of its live body, plus the new function and two knobs. `voyage.ship_speed` is also re-cut in 0203 for merchants, so **two** bodies carry that line and both must be sliced in the same file |
| **the proof it needs** | every currently-manned hull's speed byte-identical on a pre-image (the knob set so the curve returns 1.0 at the complement); the curve monotone; a probe hull at half complement measurably slower; no fleet's stored ETA moved by the apply |
| **why it needs a window** | it silently re-prices every passage whose hull is under complement — storm and raid survivors, mainly — and ETAs are money. It is a 30-minute after-check with a forward rollback (the knob to 1.0 flattens the curve back to no effect), per the repo's rule for changes that alter live play |
| **decided by default** | ship the curve on speed first, alone, and leave the combat stats for a second slice. The combat stats are themselves still behind the `combat_bite` switch (0168, dark), so wiring potency into them now would be building on an unlit floor |

---

## What was run

`npm ci`, `npx tsc -b` (clean), `npx eslint .` (clean), and the pure (non-world) specs: `duplication` (10/10),
`i18n.keys`, `format` — 36 passing.

**`npm run build` was started and deliberately stopped.** Its `tsc -b` half completed clean, which is the half that
judges this branch; its `vite build` half then began rebuilding the **PGlite world image** from the migration chain
(207 migrations, 64 restored from the prefix cache, 143 to apply). That is the rebuild CLAUDE.md forbids in a sandbox,
and it proves nothing about a client-only change to four `.tsx` files and a dictionary. CI builds it properly on the PR.

Two `i18n.ko` specs failed on `browserType.launch: Executable doesn't exist` — chromium is not installed in this
sandbox. Not this change; the pure `i18n.keys` spec, which is what validates the new dictionary entries, passed.

## Figures I did not read live

Stated plainly rather than guessed, so they can be checked against prod when someone is at a console. Nothing in this
branch depends on them; they would only sharpen the note.

- `cron.job` → the `byeharu-voyage:arrivals` row's current `schedule` and `active` flag (expected `15 seconds`, active).
- `world_config` → `time_compression` (expected 960, from migration 0100) and `arrivals_tick_budget_ms` (expected 10000).
- `cron.job_run_details` → the arrivals job's last hour: average and maximum run time. 0125 measured avg 17 s / max 39.8 s
  on the old minute cadence; 0137 measured ~3.5 s normal on the 15-second one. A current maximum anywhere near a minute
  would mean 0137's stall has returned, and that would change the answer to question A.
- `world_config` → `crew_short_speed_mult` (expected 0.70) and `route_rest_voyage_days` (expected the 120-second value
  from 0116).
