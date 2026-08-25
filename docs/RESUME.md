# RESUME — where the work stands

**If you are picking this project up cold: read the anchor immediately below, then
`docs/DEV_LOG.md`'s top two entries (D26, then D25), then `docs/OWNER_REQUESTS.md`. Everything
under `LANDED 2026-08-24` and lower is older and is kept as record.**

---

# ▼ RESUME ANCHOR — 2026-08-25 ▼

## WHERE THE CODE IS

* **`supabase/migrations/` holds 50 `.sql` files, ending at 0056.** The ranges are 0001–0037,
  0040/0041, 0045–0053, 0055/0056. The gaps 0038/0039, 0042–0044 **and 0054** are deliberate:
  versions are arbitrated by `npm run db:check-versions`, **never by counting**. 0054 is a gap because
  the slice that took that number turned out to need no migration at all — it moved the balance proof
  onto a fixture and changed no schema, and cutting a file to look busy would have been a lie in the
  chain. `supabase/migrations/CHAIN.md` is the current per-migration list.
* **CORRECTED 2026-08-25, later the same day: it has been pushed, and the SITE is deployed.**
  `origin/main` is now at `15bd8c3` (the code that had been sitting on local `main` only). CI's
  `Build`, `Acceptance`, and `Deploy (GitHub Pages)` workflows all ran **green** on that push (run
  `32857651456` for Acceptance), and GitHub Pages served the new build — the owner drove the live
  game at `https://gkwngns714-spec.github.io/byeharu-voyage/` and saw the one-row six-cell nav bar.
  **Keep the distinction this file has always insisted on: the SITE is deployed; the MIGRATIONS are
  not.** `Migrations — apply proof`'s `disposable-chain` job is **red** on that same push — see
  "OPEN BLOCKER" below — which is a separate thing from whether the frontend shipped.
* **What that means for production's database:** verified 2026-08-25 with `supabase migration list
  --linked`: the live project is on **0050**. Migrations 0051, 0052, 0053, 0055 and 0056 all show an
  empty remote column — none of them has been applied to production. **Do not tell anyone to refresh
  into 0051–0056's effects** (the retuned rarity tiers, the Bristol fix, the faster market read, the
  encounter mixes, the lower drift) — none of it is live yet, even though the client code that
  expects it now is.

## THE OUTAGE — 2026-08-25, not previously recorded anywhere in this repo

The production Supabase project filled its disk and Postgres put the **whole project into
READ-ONLY mode**. Every write failed; `POST /auth/v1/token?grant_type=refresh_token` returned
**500**, so no player could even hold a session, and the live game hung on loading skeletons.
`supabase db push` and `supabase migration list` both died with
`ERROR: 25006: cannot execute GRANT ROLE in a read-only transaction`.

**Cause, measured in the dashboard SQL editor:** `public.price_history` was **1,410 MB across
7,347,231 rows — 98% of a 1.43 GB database**, where a freshly built world from the same chain is
21 MB. The owner upgraded the org to Pro and raised the disk from 2 GB to 8 GB; read-only cleared
at 23:34 and the game came back.

**The underlying defect** is that the retention window `price_history_slots = 288` was calibrated
for a 14,980-pair world, and migration 0041 grew the world to 54,432 pairs without resizing that
window — a designed ceiling of **15.7M rows / ~3.0 GB**, well past what a free-tier project can
hold. It is **being fixed as migration 0057 by another agent, in another worktree, as of this
writing. It has not landed here** — do not claim it is fixed until `supabase/migrations/` actually
carries an 0057 file and its self-assert has been proven.

## OPEN BLOCKER — migration 0053 fails on Postgres 17, and production runs Postgres 17

`supabase/config.toml` pins `major_version = 17`, which is what production runs. PGlite (the local
apply/proof gate) runs Postgres 18, and 0053 passes there — **but CI's `disposable-chain` job,
which boots a real disposable Supabase (Postgres 17), fails on it**: run `32857650723`, job
`disposable-chain`:

```
ERROR: 0053 self-assert FAIL: one world.market() read still touches 314337 buffer(s) against the
old body's 270277 — less than the 3x this file exists to buy. The read has gone back to walking
the neighbourhood once per good. (SQLSTATE P0001)
```

**This blocks every migration deploy**, since `supabase db push` applies migrations in order and
dies at 0053. Another agent (worktree `bv-pg17`, branch `pg17-0053`) is working on a fix as of this
writing. **It has not landed on `main`** — do not report this as fixed until it has, and until the
`disposable-chain` job is green on a real run.

## WHAT LANDED ON 2026-08-25 (local `main`, not deployed)

Five migrations, one no-migration slice, and three client slices. `DEV_LOG.md` D25 is the full record
with every measurement; this is the index.

| slice | what it is |
|---|---|
| **0051** | Rarity thresholds stop being three absolute producer counts calibrated for 70 goods (243 goods were **54.7% exotic**) and become fractions of the world's own mean producer count: **47 / 86 / 58 / 52**. Proven scale-free at k = 2/3/7/17/50. |
| **0052** | The Severn is water. Bristol snapped **64.55 nm to Lyme Bay**, and because `snap_nm` is granted to a course as its head allowance she carried a **~90 nm land-exempt corridor the pathfinder used** — a live breach of the owner's never-touch-land law that the docs had filed as a labelling issue. Now 0.00 nm. The Antarctic closure also folds three statements into one `ICE` rule, 0 cells different. |
| **0053** | `world.mid_price` re-read four knobs on every call — **38,880 plpgsql calls per quay for four constants, 62% of the mid's cost**. Bordeaux `world.market` **1,442 → 241 ms**, buffers **331,470 → 40,530**. All 54,432 mids proven byte-identical. |
| **0054** (no migration) | The balance proof's market is PINNED on one fixture authority, `proof.pin_market`. The lottery is dead — and it was hiding the finding below. |
| **0055** | Encounters, **landed DARK**. `hazard_base`/`piracy_index` took **three distinct value-pairs across 51 seas — 71% of the world's water was mechanically identical**. Now ten mixes derived from the sea's own danger and piracy. `FAIR_WIND` is the first event kind that is not a loss. |
| **0056** | `drift_sigma` **0.040 → 0.020**. See the finding below. |
| nav | The tab bar was **three rows, 390×168 px, 19.9% of a phone viewport**. Now one row of six: the five voyage tabs stay direct, the four that do not act on the world sit behind CABIN. **390×56 px.** |
| map | The harbour hit-target was 22 px while the centre of a harbour's own printed name sits **24.8–31.0 px** from its mark. `hitRadius` is now derived (**38 px**). The fold gained a provision-ratio control that COMPOSES 0034's presets. `openingBounds` widens until a harbour is on the sheet. |
| boot image | `vite build` applies the chain once and emits `dist/db/world-<fingerprint>.tar.gz`. Cold boot **171.7 s → 7.1 s**, +4.75 MB fetched only when a world must be built. |

## THE FINDING THAT MATTERS MOST

**A number this project quoted in its own docs for a week was measuring the test harness.**

Proof 05's *"a first voyage returns 12–18%"* was a count of how many drift ticks the harness happened
to run before it looked. A freshly applied chain has stepped the drift **once** on the 14,980 rows
0003 seeded and **never** on the 39,468 that 0041 added, so **72% of its prices sit at drift 0**.
**Every deployed world — every world whose clock has run, which is all of them — was paying ≈37.4%.**

And the deciding number was not that one. `BALANCE_DISTANCE_PAYS` had fallen to **18.87% long vs
16.19% short — 1.17×**, where the world's own geography makes distance worth **3.31×**. The noise had
all but erased the reason to leave home waters. 0056 pulls `drift_sigma` to 0.020 and geography
recovers to **9.66 vs 5.88 = 1.64×**, with the quay's offer shape moving too: 85 near routes fall to
55 while 360 far ones rise to 405. **0.020 was chosen over 0.015 because 0.015 thins the near market
to 39 short routes, and that is the water a new captain starts in.**

The claim is now two markers rather than one widened band: `BALANCE_MEDIAN_IN_BAND` (13.0–20.0, and
it says out loud that it is a **regression tripwire** on the settled market) and
`BALANCE_GRADIENT_IN_BAND` (the design's original 4–16, measured on a FLAT market — the economy the
affinity knobs actually author, where it reads **7.0%** against the 7.5 they were tuned to). **The
authored economy was already doing exactly what it was designed to do. Everything above 7.5 was
noise.**

## WHAT THE NEXT WORK IS

In the order a cold reader should consider them, **re-derived 2026-08-25 after the push, the
outage, and the 0053 discovery — the old item 1 ("push and deploy, or decide not to") is done and
removed; everything below is what is actually left**:

1. **Fix migration 0053 for Postgres 17, or decide to re-cut it.** This is the hard blocker: it
   stops `supabase db push` from reaching 0054 or anything after it, so 0051, 0052, 0055 and 0056
   are also stuck behind it even though none of them are themselves at fault. See "OPEN BLOCKER"
   above. In flight in worktree `bv-pg17` / branch `pg17-0053` as of this writing.
2. **Confirm migration 0057 (the `price_history` retention fix) lands, is proven, and actually
   prevents a recurrence** before deploying anything else — the outage's root cause is not fixed by
   raising the disk quota; that bought time, not headroom. Re-check the designed row ceiling against
   the resized retention window once 0057 exists.
3. **Deploy 0051–0056 (and 0057, once both land) to production, or decide not to.** Two of them
   change a live economy (0051 re-tiers 171 goods, 0056 halves the price noise) and one changes
   sailed distances (0052 moves 468 pair readings, all Bristol's). **This is a real
   ~30-player-class deploy decision, not a formality**, and it is the owner's. The frontend already
   expects this schema; the longer the deploy waits, the longer the live client and the live
   database disagree.
4. **Light 0055, or decide not to.** It is one migration and four statements, named in 0055's own
   header, and the measured cost is Barbary raid-days 43.0% → 20.4% of event-days. Owner's call.
5. **`public.good_rarity`, 87 ms of the ~240 ms left in `world.market`** — now the largest single item
   in that read, named by 0053 and deliberately left for its own slice.
6. **The other 39 port snaps.** Bristol was one of **40 harbours that snap more than 20 nm** to
   sailable water (13 over 30 nm): Longyearbyen 67.68, Hanoi 58.68, Khambhat 57.77, Tokyo 47.69 lead
   it. Same class of breach of the never-touch-land law, same fix shape as 0052.
7. **Hit-test the label's box, not a radius** — `Strait of Gibraltar` is 119.6 px wide and its far end
   is 129 px from the mark. Needs the label plan lifted out of `ChartCanvas`; a second author of where
   a name is would be worse than the miss.
8. **Drive the pre-built image in a browser.** It is proven in Node only (`tests/db.image.spec.ts:5`
   says so of itself). Nobody has watched a browser arrive at a live purse in 7.1 s.
9. **Drive the map's ratio control on production.** It landed after the day's drive and has never been
   pressed on the live game.

# ▲ RESUME ANCHOR ▲

---

Everything below was written 2026-08-23 23:00, before the owner's 01:20 session reset, and updated in
place since. It is history and context, not a to-do list.

The owner's standing authority, in their words:

> *"do all the work in appropriate order, after research, build what you think it is best without
> ruining this game… you will pause everything when you reach 99% of tokens used, and resume work at
> 1:21 without me giving you orders. Remember our rule, do the work properly, do not leave anything
> left out."*

So: **build without asking, but do not skip the gate, and do not silently narrow anything.**

---

## LANDED 2026-08-24 — the free-sea mover is IN THIS CHAIN

Everything the section below asks for is BUILT and LANDED, regenerated against this chain as
migrations **0046–0049** (the helm worktree cut it as 0038/0039/0041 against a 37-migration base;
generated migrations are regenerated, never textually merged):

* **0046 — the water knows the way**: the navigable sea as ONE raster + `sea_reaches` (all-pairs
  sailed nm) + `voyage.path_nm`/`voyage.path_refusal`. Cross-checked cell-for-cell against 0040's
  sea-membership raster at generation.
* **0047 — the sea is a free plane**: ONE mover. The client proposes a course, the server verifies
  it against its own raster and measures it itself; any water point is a destination; divert turns
  where she is; `voyage.sea_near` COMPOSES 0040's `sea_at` (the helm cut's interim body was never
  created). The four graph movement authorities are DROPPED, not joined.
* **0048 — the quay reprices the honest sea**: affinity knobs retuned to honest distances.
* **0049 — the graph is history**: `public.legs` dropped, `data/sea-routes.json` and its
  generator deleted, the world guard repointed (still able to fail: planted-drift controls kept).

The Arctic defect is dead: Lisboa→Nagasaki is served at ~13,052 nm round the Cape with a maximum
course latitude of 38.7°N, where the leg graph served 7,565 nm over the pole at 88.6°N. The client
clock mirror moved with 0045 (480 → 9600; a voyage-day is 9 real seconds) and rpc.surface asserts
the served knob equals the mirror. See DEV_LOG's top entry for the full landing record and every
gate's measurement.

> **CORRECTION 2026-08-25.** The ~13,052 nm above is not reproducible from anything in this repo and
> should not be quoted. The chain's own served figure for Lisboa→Nagasaki is **12,989.3 nm**
> (`sea_reaches` row `LIS`, migration 0046), which is the number 0046's header and
> `docs/DESIGN_RESEARCH_NAVIGATION.md:356` both carry. The 38.7°N and 7,565 nm / 88.6°N figures do
> check out (`docs/NAVIGATION_PLAN.md:33-34`, 0046's header).

**Also landed since this was written:** **0050 — a refusal is two numbers and a verb** (2026-08-25).
Every arithmetic refusal now serves `{have, need, unit}` as DATA beside its sentence, so the client
never parses a served sentence for numbers; `cmd.refuse` / `cmd.refusal_caught` replace SIX
hand-copied refusal splits and the eight-character truncation all six carried; `public.orders`
gained `error_figures`. DEV_LOG D24 is the record.

---

# ▼ HISTORY BELOW THIS LINE — NOT A TO-DO LIST ▼

**Everything from here to `STATE AT THE MOMENT OF WRITING` was DELIVERED on 2026-08-24 as migrations
0046–0049 (see the section above and DEV_LOG D24).** It is kept only as the record of WHY the
movement model was replaced. Nothing in it is outstanding work. Read it as history — if you are
looking for what to do next, it is not here.

## WHY THE MOVEMENT MODEL WAS REPLACED — delivered 2026-08-24, kept for the record

**The movement model was replaced.** This is `OWNER_REQUESTS.md` rows 42 and 43, and it is the
largest correction of the project. It is DONE; the present tense below is the tense it was written
in, on 2026-08-23, before the work landed.

byeharu-voyage models sailing as a **fixed graph of 782 precomputed legs between ports**. That is the
wrong game. The owner's words:

> *"First it is a fleet game, moving by seas, and you've decided to make routes (constant) — a fixed
> method of reaching to the place. it should go by sea without the fixed route — but fastest way
> possible. Also, in map, i should be able to pinpoint anywhere in the ocean to make a fleet move."*

And the failure was ours to catch: `docs/DESIGN_RESEARCH.md` §1.11 already recorded that in the
reference game *"navigation is **manual** or automatic by picking the destination harbour"* — manual
listed first. Only the automatic mode was ever built.

**Four defects found today were all this one assumption surfacing:**

| symptom | cause |
|---|---|
| Lisbon→Recife routed 8,885 nm via Porto→Cork→**Reykjavik** | ocean crossings exceed the generator's 1,300 nm candidate limit, so the pathfinder detours through the only edges that exist |
| ships drawn straight **over land** | 782 legs, **zero** carry a path; `nm/gc_nm` runs to 4.37, so the generator walked the water, kept the length and discarded the shape |
| **41 ports teleport** their last 20–72 nm (Suez 72, Bristol 65, Hanoi 59) | inland ports snap to the nearest water cell, silently, costing no time and no stores |
| sea lanes drawn **across continents** | `src/chart/route.ts` draws straight lines *deliberately*, to agree with the server's straight-line interpolation. Both are wrong together. |

### The replacement, as the owner specified it

- **The sea is a free plane.** Any water point is a destination — pinpoint the ocean and go.
- **Auto-sail pathfinds** the fastest way through the 0.25° water raster, computed at departure.
- **Wind and current change speed**, and the point of that is **provision risk** — a slow passage
  burns more stores.
- **NPCs distributed by area, with levels.** A small panel on the map lists nearby contacts and
  their **distance**; the player clicks one to engage.
- **The empty ocean is filled by consequence**: attacks and disasters that take crew, stores, cargo.

**A path found through water cells cannot cross land by construction** — so row 41's never-touch-land
law stops needing a bolted-on guard and becomes a property of how a route is made.

### The two constraints that must not be lost

1. **ONE mover.** This REPLACES `voyage.reach_from`, `voyage.sail_refusal`, `voyage.route_direct`
   and `voyage.route`. It does not join them. byeharu's recorded catastrophe was four overlapping
   movement paths: four ships stuck, five teleported to wrong ports, a player's fleet destroyed
   because the brake refused, and *"is this fleet docked?"* in **eleven** hand-copied definitions.
2. **Offline settlement must stay byte-identical.** `voyages.speed_profile` is frozen at departure
   and proof 01 rests on it; it is why a voyage settles while the player is asleep. Variable wind
   *appears* to break this and must not: wind has to be a **pure function of (position, time, world
   secret)** — the shape `voyage.rng` already has, `immutable` so Postgres itself forbids it reading
   the clock. Integrate a known field over a known path and any two evaluations agree to the digit.
   Losing this means the game only advances while someone is watching.

Consequence to handle: **if wind moves speed, the ETA quoted at departure is a forecast, not a
promise.** `docs/UI_DIRECTION.md` forbids printing a number the game will not honour.

---

# ▲ HISTORY ABOVE THIS LINE ▲

---

## STATE AT THE MOMENT OF WRITING (2026-08-23), production line corrected 2026-08-25

**Production — corrected 2026-08-25, three times now; SEE THE ANCHOR AT THE TOP, WHICH SUPERSEDES
THIS.** The line here used to read *"35/35 migrations, matching local"*, and that was false; it was
then corrected to **45 `.sql` files**, and by the end of the same day that was stale too — **the
chain is 50 files ending at 0056, and at the time of the probe below, the last five were on local
`main` only, unpushed.** They have since been pushed (see the anchor) but production's database is
still on 0050 — pushing the client code did not deploy the migrations. What the probe below
established, and all it established, is that the live project was on **0050** — the head of the chain
*as it stood that morning* — verified directly with the anon key on 2026-08-25, not asserted from
memory:

* `GET /rest/v1/legs` → **404**. The table is gone, so **0049** is applied.
* `GET /rest/v1/orders?select=error_figures` → **`42501 permission denied for table orders`**, where
  the same request for a made-up column answers **`42703 column … does not exist`**. The column
  exists, so **0050** is applied. (Neither probe reads a row; the read wall is intact.)

Since Supabase applies the chain in order, 0045–0048 are on it too. Site live at
`https://gkwngns714-spec.github.io/byeharu-voyage/`, cloud build, behind a login. The repo is public;
the world secret was rotated off disk first (0031) and a CHECK constraint refuses the old literal.

**Agents in flight AS OF 2026-08-23 — HISTORICAL, all of this landed on `main`.** None of these are
running now; the table is kept because the merge order and the reasons are the record of how the
work was partitioned. Do not read it as live status:

| worktree | slice |
|---|---|
| `bv-mover` | **the navigation research + proposal + costed pathfinder prototype.** Research first; NOT authorised to rebuild the mover. The owner asked to see the plan. |
| `bv-ports` | real island ports, 4–9 offers per port by tier, goods-aware rosters. **Movement work was taken off it.** |
| `bv-seaplaces` | sea places + diverting mid-voyage. Told to report what survives the model change. |
| `bv-clarity` | Issue button to the top (was 2,112px down); Codex filter chips (2.5 screens before content). |
| `bv-goods` | **finished** — 243 goods delivered, not 1,000, with arithmetic. **Do not merge before `bv-ports`**, or 173 goods are orphaned. |

**Merge order was: `bv-ports` → `bv-goods` → everything else.** Re-run `db:proof` after, because
sailed distances move. **All five merged on 2026-08-24** — the world growth landed as 0041 (DEV_LOG
D23), the seas as 0040 (D22), and the mover was regenerated against this chain as 0046–0049 (D24).

**Killed by the owner, do not restart without asking:** the ship-stats/market-port agent (`stats`).

---

## KNOWN, WRITTEN DOWN, NOT LOST

- ~~**Rarity thresholds do not scale.** Fixed at ≤2/≤5/≤12 producers, calibrated for 70 goods. At 243
  the catalogue is **54.7% exotic** — exotic has become the default and therefore means nothing.~~
  **FIXED 2026-08-25 by migration 0051** — the cuts are now fractions of the world's own mean producer
  count and the catalogue reads 47 / 86 / 58 / 52, proven scale-free at k = 2/3/7/17/50. On local
  `main`, not deployed.
- ~~**Cold boot 78.8 s** measured with 243 goods (was ~30–55 s). The world builds in the player's
  tab.~~ **FIXED 2026-08-25** — `vite build` applies the chain once and ships the world as an image
  named by the chain's own fingerprint; the tab restores it instead of replaying the chain.
  **171.7 s → 7.1 s** measured back to back on the same build. On local `main`, not deployed, and
  **proven in Node rather than in a browser**.
- ~~**Proof 05's balance band is a genuine lottery** — an unchanged chain measured
  15.1/9.0/12.4/14.4/12.4/12.1 against a 4–16 band, and once 16.2. A gate that cries wolf gets
  ignored.~~ **FIXED 2026-08-25 by the 0054 slice, and it was hiding a real defect** — see the anchor
  at the top of this file. The market is pinned on one fixture authority, five `db:proof` runs now
  agree to the digit, and the 12–18% this proof reported turned out to be a count of how many drift
  ticks the harness ran. Every deployed world was paying ≈37.4%.
- `db.chain`'s rebuild spec builds the world twice and grows with every migration; timeout raised to
  360 s deliberately. If it times out again the answer is a lighter fixture, not a bigger number.
- The Supabase access token on this machine **expires ~2026-09-23** and was pasted into a chat
  transcript; worth rotating.

---

## HOW TO WORK HERE

`docs/NO_SPAGHETTI.md` is the law — §7B (decide where a concept lives *before* the second caller
exists) and §7C (a conditional may choose between two ACCEPTABLE outcomes, never between an
acceptable and an unacceptable one) are the two newest and the two most often needed.

**The owner's standing rules, learned the hard way today:**

- **Pressing a control SELECTS. It never collapses, re-flows, replaces or destroys the surface it was
  pressed on, and nothing docks and follows the scroll.** Said four times; I built the opposite twice.
- **Labels are NAMES, not sentences.** No jargon — `hands`→crew, `yard`→shipyard, `crimps` deleted.
- **One word per idea across the whole game.** One figure was found carrying three names.
- **Every agent gets an isolated worktree** and `model: 'fable'`.
- **Verify on target.** An agent's report is a claim. Drive the real game in a browser before saying
  anything works — and a guard nobody has watched fail is a guard nobody should trust.
- **`docs/OWNER_REQUESTS.md` is the source of truth for what was asked.** Keep it current: a stale row
  is a lost instruction wearing a tick.
