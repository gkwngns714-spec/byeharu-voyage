# RESUME — where the work stands

**If you are picking this project up cold: read the anchor immediately below, then
`docs/DEV_LOG.md`'s top two entries (D34b, then D34), then `docs/OWNER_REQUESTS.md`, then
`docs/WORK_PLAN.md` §4 for which slice is next. Everything under `LANDED 2026-08-24` and lower
is older and is kept as record.** *(This pointer named D27/D26 until 2026-09-06 — eight entries
out of date. A cold-start pointer that names the wrong entries sends the reader to the wrong
month, so it moves with the anchor.)*

---

# ▼ RESUME ANCHOR — 2026-09-06 ▼

**The anchor this replaces was written 2026-08-26 and had gone FALSE, not merely stale** — it said
production was at `0059`, `main` was at `642063c`, and PRs **#3**, **#4** and **#5** were the open
ones. Since then 0060–0076 were authored, #3 and #4 merged, and `main` moved fourteen commits. Every
line below is labelled with how it was checked, and **anything not checked says so** rather than
being asserted in the voice of something that was.

## `main` — VERIFIED 2026-09-06 by reading git and the GitHub API

| | | how |
|---|---|---|
| `main` head | **`728da87`** — *"0076: a harbour is reached from its roads (row 72)"*, 2026-09-04 | `git log -1 main` |
| Chain head | **0076** `a_harbour_is_reached_from_its_roads`, **69** migration files | listing `supabase/migrations/` |
| CI on that head | **all green** — build · pglite-gate/disposable-chain · acceptance · Pages | `gh run list` |
| Locally re-proven | `db:apply` **69/69 self-assert receipts** · `db:proof` **62/62** · `tsc -b` and `eslint` clean · browser suite **232 passed / 0 failed** | run on this machine 2026-09-06 |

## ⚠ PRODUCTION'S DATABASE HEAD IS **UNVERIFIED**, AND IT IS ALMOST CERTAINLY BEHIND

**Nothing here deploys a migration.** `.github/workflows/` has `build`, `acceptance`,
`migrations-apply-proof` and `deploy-pages` — **no deploy-migrations job**. Pages has been deployed
from every merge, so the SITE is current with `main` while the DATABASE need not be.

The last figure this repo actually recorded is **0059, on 2026-08-26**. Migrations **0060–0076**
have no recorded deploy. **This was not re-checked on 2026-09-06 because the machine has no
Supabase access token** (`supabase projects list` answers `LegacyPlatformAuthRequiredError`; the
token noted in this file expired ~2026-09-23 and lived on the other machine).

**So the first thing the next session does is find out, not assume:**

```
supabase login
supabase migration list --linked      # the truth
supabase db push --linked             # if it is behind
```

Until that is run, treat every "LIVE" claim about 0060 and later as UNPROVEN.

## OPEN PULL REQUESTS — verified 2026-09-06

| PR | what | state |
|---|---|---|
| **#28** `0075: one authority for a gun slot` | A real bug found by playing: `ship_classes.guns` and `public.class_slots` are two authorities for one number and `cmd.do_fit` read the wrong one, so a **barca could mount no weapon at all** and a nau would have taken twelve. | **CONFLICTING**, and its version `20260818000075` **collides** with `the_leg_she_is_on_has_a_length` already on `main`. Being regenerated as **0077**. |
| **#5** `[BLOCKED] 0060: forty harbours stop sailing overland` | DRAFT, blocked on purpose | **Must be REGENERATED, not merged** — 0076 rewrote `sea_reaches` and 0060 as drafted would null the two columns 0076 declares NOT NULL. |

## ⚠ PR #28's RED WAS DICE, AND THE DICE ARE STILL LOADED

`disposable-chain` failed on that branch (run **`33695216552`**) and **not for anything the branch
changed**. The log reads:

```
ERROR: deadlock detected (SQLSTATE 40P01)
Process 214 waits for ShareLock on transaction 1391; blocked by process 265.
Process 265 waits for ShareLock on transaction 1372; blocked by process 214.
At statement: 15
```

— inside **migration 0041**'s `port_goods` re-derive. That is the game's own `pg_cron` market tick
firing mid-chain and deadlocking with the migration that is rewriting the same table. It is
`WORK_PLAN.md` §6's *"a red that was dice"*, and it is worse than a wasted run: **a gate that fails
at random teaches people to re-run reds instead of reading them**, which is precisely how the one
red that matters gets waved through. The chain should not race the clock; fixing that is its own
slice.

## WHAT THE OWNER IS STILL OWED

* **Rows 51, 53 and 63 were built and the ledger never said so** — corrected 2026-09-06, with the
  pattern named in `OWNER_REQUESTS.md`'s rules: **all three landed in client-only PRs**, which touch
  no migration and so slip past the habit that makes anyone open the ledger. The dev log missed the
  same three for the same reason.
* **Nobody has driven the running game since 0070.** Rows 48, 52, 53, 63 and 72 are all built and
  none is verified under rule 2. **0076 in particular has never been looked at** — the dotted
  roadstead line, the mark, and a SAIL whose track begins at the roads rather than at the city.
* **Stage 2 has one slice left**: *Regions and the map split* (owner row 59), still design-only.
  Stage 3 is untouched: crafting recipes · captain ranks/roles/cabins (rows 61/66) · homesickness.
* **Row 65's role half does not exist.** `ship_classes.tier` is real and 0074 gave slots by tier,
  but `family` carries a culture ('Western'), not trading/exploration/combat.
* **Row 67 is unanswered**: the owner called the good categories a dump — *"wtf is foodstuff?"*
* **Named spaghetti, still not fixed:** `culture = any(g.culture_mask)` is written **five** times in
  the live schema (`do_buy`, `do_sell`, `world.market`, `trade_routes`, `cmd.haggle`).
* **`pglite-gate` has `timeout-minutes: 15`** and the chain has been taking ~13. It gets worse with
  every migration; the answer is a faster gate or a lighter fixture, not a bigger number.

## STARTING ON A NEW MACHINE

`docs/NEW_MACHINE.md` is the setup, with two things that cost time on 2026-09-06:

* **Node 24+ is required, not optional** — `scripts/db/*` import `src/lib/sea/*.ts` and rely on
  Node's type stripping (default from 23.6). Node 20 cannot run `db:apply` at all.
* `git config core.autocrlf false` **before** anything else; the chain guard refuses CRLF.


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
