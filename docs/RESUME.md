# RESUME — where the work stands

**If you are picking this project up cold: read the anchor immediately below, then
`docs/DEV_LOG.md`'s top two entries (D27, then D26), then `docs/OWNER_REQUESTS.md`. Everything
under `LANDED 2026-08-24` and lower is older and is kept as record.**

---

# ▼ RESUME ANCHOR — 2026-08-26, end of session ▼

**Written as a handoff: the owner is moving to another computer. Everything below is pushed.**

## PRODUCTION — live and playable

* `supabase migration list --linked`: **53 of 53 applied, head 0059, nothing outstanding.** Verified
  on the target, not inferred from a push.
* The site is deployed and the database agrees with it:
  **https://gkwngns714-spec.github.io/byeharu-voyage/**
* Probed live: `voyage.encounter_at` -> `PGRST202` (0059's drop really happened), `hazard_roll` and
  `sea_mix` -> `42501` (present, server-private), auth -> `400` not the outage's `500`.
* **Nothing in the open PRs below is on production.** Prod is 0059 and only 0059.

## `main` IS AT `642063c`

Merged today: **`docs/OWNER_AUDIT.md`** (all 48 owner instructions re-checked against the code) and
the **goods grid** (COMMAND's buy/sell picker was 243 goods in a column **44,212 px tall**; the
compendium's Ships face was a 680 px table inside a 332 px box).

## THREE OPEN PULL REQUESTS — none merged, all pushed

| PR | What | State |
|---|---|---|
| **#3** `osn-0062-regional-goods` | The 243 goods become regional. `origin_regions` + `entrepot_ports`; **every offer is native or a named entrepôt — 1,241 native, 47 entrepôt, 0 neither.** Repairs what 0058's hash did: Königsberg had lost amber; `allspice`, `pistachios` and `lac` had each lost their only port and were **buyable nowhere on earth**. `docs/REGIONAL_GOODS.md`, 1,164 lines. | `build` + **`disposable-chain` GREEN on PG17**, `acceptance` green; **`pglite-gate` RED — see the timeout below** |
| **#4** `osn-0061-city-trades-its-roster` | A city SELLS only its roster (owner row 48). BUY gated through the `E_UNAVAILABLE` the chain already raises; **SELL deliberately NOT gated** or cargo strands. `world.market` 219.8 -> **57.4 ms**; price-history ceiling **594.7 MiB -> 14.1 MiB**. | CI running at handoff |
| **#5** `osn-0060-harbour-snaps` | **DRAFT, BLOCKED ON PURPOSE.** All 40 harbours that snapped over 20 nm to water are fixed (Longyearbyen 67.68 -> 0.00). Its `db:proof` is RED and **the red is honest**. | do not merge until the land repair lands |

**Merge order matters:** 0061 applies before 0062 in the chain. 0062 was authored against a chain
*without* 0061 — if any of its asserts assume `world.market` serves 243 goods or `price_history`
holds 54,432 pairs, they need repointing where the branches meet.

## THE BIGGEST OPEN DEFECT — the never-touch-land law is breached LIVE

The owner's law is absolute: *"i don't want the fleet to ever touch land"* (row 41).

1. **`src/lib/sea/pathfind.ts:317`** — `if (f * nm < headNm || (1 - f) * nm < tailNm) continue`
   skips the land check entirely inside a segment's approach allowance. **Panama City -> Port Royal
   is served at 560.9 nm ACROSS THE ISTHMUS OF PANAMA** against 10,479.8 round the Horn. A Panama
   Canal, 1914. Panama -> Santiago de Cuba: 1,944.6 against 11,023.4. **This is live right now.**
2. **Six `CHANNELS` entries draw a canal through land.** `irrawaddy-sittaung` opens 30 land cells,
   one **85.6 nm up in the Tenasserim mountains**, joining the Gulf of Thailand to the Andaman Sea
   in 382 nm instead of ~2,300. `elbe-weser`, `thames-scheldt`, `gironde`, `baltic-gulfs` and
   `gambia-senegal` spill 31-63 nm inland.
3. **The guard is not vacuous — it is UNDER-SCOPED.** Proof 09 is green on `main` (62/62) and its
   control really bites (`NEVER_TOUCH_LAND_BITES`, a planted Iberia crossing refused). It checks
   courses it plants itself and never asks about the courses the game actually serves. Fixing the
   breach without fixing the scope resets the clock.
4. **The sound repair moves 50,868 of 56,406 readings and DISCONNECTS 10 ports** whose channels are
   only diagonally linked. It was built and deliberately reverted. It is a world repricing that
   would invalidate 0048's price tuning — its own slice, its own justifications, its own balance
   pass.

A 15-agent workflow was authored for exactly this and stopped for machine memory before it ran.
**The script is saved and can be re-run without re-authoring it** — look under the session's
`workflows/scripts/never-touch-land-*.js` (measure -> judged design panel -> implement ->
adversarial refute). Next free migration number is **0063**.

## THE TIMEOUT THAT WILL KEEP BITING

`pglite-gate` has **`timeout-minutes: 15`** (`.github/workflows/migrations-apply-proof.yml:74`) and
the chain now takes ~13 minutes on wasm Postgres. PR #3 was **cancelled at 15m14s with no assertion
failure** — the last receipt was 0056 and then nothing. `disposable-chain` (real Postgres 17, a
30-minute limit) passed the same commit in 5m45s. **This is capacity, not a defect**, and it gets
worse every time the world grows. Raise the limit or make the gate faster — but read the log
before ever calling that job's red a defect.

## THE LESSON THIS SESSION KEPT RE-LEARNING — read before writing any migration

**Green on PGlite AND green on CI's disposable Supabase still does not mean it applies to
production.** 0057 proved it twice in one day:

* Its step-3 seed used a bare `INSERT`, which collided with rows a live tick had already written.
  Fixed with `on conflict do nothing` — 0013's own idempotence rule.
* Then a *second* assert in the same file demanded every good carry an identical point count, which
  is only true where the table began empty. Green on PGlite (empty) and on production (a tick had
  sampled everything uniformly), **red on a disposable Supabase** where the tick fires mid-chain and
  any tick landing before 0041 grew the catalogue leaves the older goods one point ahead. It is now
  a floor on the thinnest good, not an equality.

Both edits touch a migration applied to production, which this project otherwise forbids. They are
**assert-only** — no schema, function body or grant differs, so production is byte-identical
either way — and the chain must be applicable from scratch or CI proves nothing.

## WHAT THE OWNER IS STILL OWED

* **Row 48 stays OPEN** under rule 2 — 0061 is built but has not been driven in the running game.
* **Nobody has played the newly-live economy.** 0051/0056/0058/0059 changed what a player sees and
  none of it has been driven since it went live.
* **Gochujang** (row 38) is proposed in `REGIONAL_GOODS.md` §H, not silently added — a new good
  moves `rarity_scale()`'s whole histogram. Korea has 21 goods in its origin but only `tiger-skins`
  exclusively.
* **Named spaghetti, not fixed:** `culture = any(g.culture_mask)` is written **five times** in the
  live schema (`do_buy`, `do_sell`, `world.market`, `trade_routes`, `cmd.haggle`).
* **The ledger no longer tallies** how many times an instruction had to be given; rule 5 forbids it.

## STARTING ON THE OTHER MACHINE

`docs/NEW_MACHINE.md` is the setup. Then read `docs/OWNER_AUDIT.md` (what is actually true),
`docs/DEV_LOG.md` D27 and D28, and this anchor. **Re-read the deploy state from
`supabase migration list --linked` rather than trusting any prose, including this file.**

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
