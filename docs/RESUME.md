# RESUME — where the work stands

**If you are picking this project up cold: read the anchor immediately below, then
`docs/DEV_LOG.md`'s top two entries (D27, then D26), then `docs/OWNER_REQUESTS.md`. Everything
under `LANDED 2026-08-24` and lower is older and is kept as record.**

---

# ▼ RESUME ANCHOR — 2026-08-26 ▼

## THE HEADLINE: PRODUCTION IS FULLY DEPLOYED

**`supabase migration list --linked` reads 52 of 52 applied, head 0058, nothing outstanding.**
Verified on the target on 2026-08-26, not inferred from a green exit code. Both blockers the
2026-08-25 anchor named are gone:

* **The Postgres-17 failure in 0053 is fixed** (`ffbaf9c` — the generic plan was the villain; the
  neighbourhood walk is pinned to a custom plan). 0053 applied to the real Postgres 17.
* **0057 landed**, after failing its first production push. See DEV_LOG D27 — it is the most
  important thing written this week.

The site was already deployed and still is. **So for the first time the live client and the live
database agree.** `docs/DEV_LOG.md` D27 is the full record.

## THE LESSON FROM D27 — read this before writing any migration that WRITES

0057 was green on PGlite and green on CI's disposable Supabase, and could not apply to production.
Both test engines **boot `price_history` empty**; production has a live tick that has been writing
every ten minutes for days. 0057 seeded a precondition with a bare INSERT and hit a primary-key
collision on the only database that matters.

**"Green on both engines" is not evidence a migration will apply to production.** Any migration that
WRITES a precondition rather than only reading one carries this exposure. The fix was
`on conflict ... do nothing` — 0013's own idempotence rule — plus an assert that the precondition
actually holds, since `do nothing` can silently do nothing.

## WHAT IS LIVE NOW THAT WAS NOT

0051 rarity re-tiered (171 goods moved) · 0052 Bristol snaps 0.00 nm and the overland course is
refused · 0053 `world.market` 1,442 → 241 ms · 0055 ten encounter mixes, **still DARK** · 0056
`drift_sigma` 0.020 so geography beats noise (1.17× → 1.64×) · 0057 `price_history` bounded at 57
slots / 623,627,424 bytes · 0058 every harbour offers capital 10 / mid 4–8 / small exactly 4.

## TWO DECISIONS TAKEN, WITH THEIR REASONS

* **`VACUUM FULL` on `price_history`: NO.** The ~800 MB of dead space is already reusable and the
  table is permanently bounded, so the file cannot grow past what it is. `VACUUM FULL` would take an
  ACCESS EXCLUSIVE lock on a live game (blocking both the chart read and `tick_price_snapshot`) and
  need ~600 MB transient disk, to buy ~800 MB back on an 8 GB disk. Separately, it is not runnable
  from this machine: the CLI has no arbitrary-SQL subcommand and no DB password is stored here
  (`db push` provisions a temporary login role from the access token). It would need the dashboard.
* **Supabase Pro: STAY.** Checked against supabase.com/pricing: Free is a **500 MB** database, Pro is
  from **$25/month with 8 GB** included. Production settles near **620 MB** (595 MB `price_history` +
  23 MB `port_goods` + <2.3 MB). Even at the 48-slot floor the chart requires, `price_history` alone
  is 501 MB. **No setting of 0057's budget fits 500 MB while the world samples 54,432 pairs.**

## THE FINDING THAT DESERVES THE OWNER'S EYE — row 48 may not be satisfied

`public.port_goods` carries **all 243 goods at all 224 ports = 54,432 rows. Every port trades every
good.** 0058 implemented row 48 as `port_specialties` — **1,288 rows, about 5.75 per port**.

So a city **specialises** in 4–10 goods and still **offers** 243. Row 48's words are *"min 4, max 10
trades goods per city … capital cities - 10 items, mid sized cities - 4~8, small cities 4"*, which
reads more like what a city SELLS than what it is good at. **This is a real design question and it
has not been put to the owner.** It is also the only lever on the plan arithmetic above: sampling
only the roster would be 1,288 × 48 × 201 = **12.4 MB** and the free tier would fit easily.

## WHAT THE NEXT WORK IS

1. **Resolve row 48's reading** — does a city TRADE 4–10 goods, or trade 243 and SPECIALISE in
   4–10? Owner's call. It decides both whether row 48 is closed and whether Pro is forced.
2. **Light 0055, or decide not to.** Now that 0055 is applied to production it is FROZEN — lighting
   it means a new migration that re-cuts, never an edit. Measured cost: Barbary raid-days 43.0% →
   20.4% of event-days. In flight as 0059.
3. **The other harbour snaps.** Bristol was one of a set that snap more than 20 nm to sailable water
   — same class of breach of the never-touch-land law, same fix shape as 0052. In flight as 0060.
   The figures in the old anchor (40 harbours, Longyearbyen 67.68 etc.) are UNVERIFIED and are being
   re-measured from the running chain rather than trusted.
4. **`public.good_rarity`, 87 ms of the ~240 ms left in `world.market`** — the largest single item
   left in that read, named by 0053 and left for its own slice.
5. **Hit-test the label's box, not a radius** — `Strait of Gibraltar` is 119.6 px wide and its far
   end is 129 px from the mark. Needs the label plan lifted out of `ChartCanvas`.
6. **Drive the pre-built image in a browser.** Proven in Node only (`tests/db.image.spec.ts:5` says
   so of itself). Nobody has watched a browser reach a live purse in 7.1 s.
7. **Drive the map's ratio control on production**, and drive the newly-live economy generally —
   0051/0056/0058 changed what a player sees and none of it has been driven since it went live.

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
