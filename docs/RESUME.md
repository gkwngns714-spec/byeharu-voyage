# RESUME — where the work stands

**If you are picking this project up cold: read the anchor immediately below, then
`docs/DEV_LOG.md`'s entries for 2026-09-09, then `docs/OWNER_REQUESTS.md`, then
`docs/WORK_PLAN.md` §4 for which slice is next. Everything under `LANDED 2026-08-24` and lower
is older and is kept as record.** *(This pointer named D27/D26 until 2026-09-06 — eight entries
out of date. A cold-start pointer that names the wrong entries sends the reader to the wrong
month, so it moves with the anchor.)*

---

# ▼ RESUME ANCHOR — 2026-09-09 ▼

**The anchor below this one (2026-09-06) is now HISTORY.** Its central warning — *"production's
database head is UNVERIFIED, and it is almost certainly behind"* — was resolved on 2026-09-09: the
Supabase CLI on the 디폴리스 machine **is** authenticated and linked, and production was read,
pushed and read back. Do not act on that warning again; act on this.

Every line is labelled with how it was checked. **Anything not checked says so.**

## The state of the world — VERIFIED 2026-09-09

| | | how |
|---|---|---|
| `main` head | `352c130` | `git log origin/main -1` |
| Chain head | **0080** `one_authority_for_a_culture_that_will_not_trade`, **73** migration files | listing `supabase/migrations/` |
| **Production database head** | **0080 — IN STEP WITH `main`** | `supabase migration list --linked` after `supabase db push --linked`, read back from the target: `{"local":"20260818000080","remote":"20260818000080"}` |
| Site | deployed from every merge to `main` | `deploy-pages.yml` runs on push |
| Live URL | https://gkwngns714-spec.github.io/byeharu-voyage/ | fetched the deployed bundle and grepped it |
| Branch protection on `main` | **`acceptance` + `build` required**; admin override ON (`enforce_admins: false`); force-push and deletion blocked | added 2026-09-09, `gh api .../branches/main/protection` |

**Why only two checks are required, and do not "fix" this:** `migrations-apply-proof.yml` is
path-filtered to `supabase/**`, `scripts/db/**` and `package.json`. A UI-only PR never produces
`pglite-gate` or `disposable-chain`, so requiring them makes every UI PR wait forever for a check
that will never run. This was tried and reverted within the hour. The apply-proofs still run on
migration PRs and still gate by discipline — read them.

## What landed 2026-09-09 — the UI remodel

The owner's verdict on the running game was *"so many unnecessary info, old fashioned component
structure."* An audit at 390x844 measured it: 81 explain-dots, 93 lines of fine print, 31 uppercase
section labels, 33 bordered cards, ten type sizes, three families, and a 2008 admin-document
structure under a brass skin. `docs/UI_DIRECTION.md` is that audit and the direction it produced; it
**supersedes the 2026-08-20 version** and is the spec of record for any UI work.

| step | what | measured result |
|---|---|---|
| 1 | Token layer | material deleted; one family, five type sizes, 8pt rhythm, both schemes first-class |
| 2 | Twelve primitives | `Sheet` `Tray` `Corner` `Row` `Figure` `Tile` `Bar` `Chip` `Button` `Field`/`Stepper` `Note` `Hint` `Nav` |
| 3 | Shell | TopBar to a 32px status strip; wordmark and telemetry dot gone |
| 4 | PORT | first price **645px to 257px**; trade face 1,843 to 1,174px |
| 5 | COMMAND | first price **~1,900px to 641px**; feature 3,459 to ~1,350 lines |
| 6 | MARKET | port picker **5,566px / 238 chips to 1,246px / 10**, ordered by sailed distance |
| 7 | FLEETS | **964px to 108px**; 14 elements shearing at 390px to **0**; the last data table gone |
| 8 | MAP | unobstructed chart **78.0% to 85.1%**; `SendFleet` 753 lines to six files |
| 9 | RANK, CODEX, LEDGER, PROFILE | RANK 1,236 to 844px and 36 shearing to 0; CODEX captains 6,370 to 3,314; LEDGER 393 to 165; PROFILE 986 to 578 |
| — | one authority | PORT's and COMMAND's duplicate buy-trays folded into one `TradeTile`/`TradeTray` plus `src/live/useTrade.ts` |

`INLINE_SKIN_DEBT` is **empty** and `INLINE_SKIN_TOTAL` is **0** — no file under `src/features/`
draws its own surface any more. It was 12 when the ban was written that morning. One arbitrary size
remains: `SignTheBook.tsx`'s 11px refusal code.

## Also landed 2026-09-09

- **Migration 0059's self-assert was non-deterministic and is now provably not.** It pinned one
  weather kind and asserted that kind fired, guarding the day with a one-sided `rng >= 0.01`. But
  `voyage.sea_mix` lays its bands out in **ordinal** order, so the unpinned tail sits in two pieces —
  one below the pinned kind and one at the **top** of `[0,1)`, which the guard could not see. Under
  a CALM pin, `SHOAL_WATER` occupies `[0.9999, 1.0)`. Both sites now read
  `between 0.01 and 0.99`; margin 14x; residual failure probability **zero, not smaller**.
  Reproduced on a hunted seed (RED before, GREEN after) and all 15 break-test mutations still bite.
  It failed roughly 1 in 620 chain applies — including during a production `db push`.
- **PR #5 closed** after two weeks blocked. Its defect was killed by 0076 (course endpoints moved to
  the roadstead; `snap_nm + 25` became a flat 25) and 0079 (the canal). Measured: 1,429 real
  client-proposed courses touching the forty harbours, judged at a flat 25nm, **zero land
  refusals**; Panama City to Port Royal 560.9nm to 10,577.6nm. **Do not regenerate that branch** —
  it still carries `irrawaddy-sittaung` and would re-dig the canal 0079 filled in. Its 36 historical
  channel justifications are preserved in **issue #48**.

## What is still open

| | |
|---|---|
| **PR #47** | Six screens in one branch (MARKET, RANK, CODEX, MAP, LEDGER, PROFILE). Supersedes #43–#46. Waiting on `acceptance` with auto-merge armed. **Check whether it merged before doing anything else.** |
| **Step 10** | Delete the now caller-free table apparatus (`Table.tsx`, `tableLayout.ts`, `scrollAffordance.ts`, `useClipped.ts`) and the deprecated primitives; fold the duplicate `verbWord` (COMMAND's `verbIcons.ts` vs MAP's `fixWord`) into one in `domain/order` beside `orderText`; assign the deferred DEV_LOG entry numbers. |
| **MARKET into PORT fold** | Recommended by the agent that built both: with a fleet alongside, MARKET's body *is* PORT's trade face under a port field. Costs `PortTrade` a read-only mode (`TradeTile` has none, so every sell cell says "none aboard" on a distant quay). Gains one screen, one nav cell, one reader of the harbour store. **Owner's call, not taken.** |
| **Issue #48** | Harvest 0060's channel research against today's generator. |

## Procedures learned the hard way on 2026-09-09

1. **A re-run is a diagnostic, never a verdict.** A proof that goes red then green on the same
   commit is a broken proof, and the flakiness IS the finding. Re-running until green launders a
   failure into a result.
2. **Run everything in the FOREGROUND.** Four agents that day finished their code and then parked
   themselves indefinitely waiting on a background build or test notification that never arrived.
   If a build takes nine minutes, run it and wait nine minutes.
3. **Parallel screens need ONE integration branch.** Six screens each lowering their own entries in
   `tests/duplication.spec.ts` meant every merge invalidated the others' arithmetic — the same two
   files conflicted six times. Merge them into one branch, resolve once, prove once. And state the
   ledger from the **merged tree**, measured, not from whichever side of a conflict won.
4. **Do not number DEV_LOG entries in a parallel branch.** Four agents each claimed the same
   D-number. Write the date and title; number it at merge.
5. **Never `git add -A` in a scratch clone.** One did, swept an unrelated embedded repository in as
   a gitlink, and pushed it. Use explicit paths.
6. **A name collision only appears at the merge.** FLEETS and MAP each wrote a `FleetTray` and
   neither branch could see the other; `duplication.spec`'s same-name guard caught it in the
   integration branch. The map's is now `VoyageTray`, which is what it always showed.
7. **Kill your preview servers.** Sixteen abandoned `vite` processes were found running, one having
   burned 21,060 CPU-seconds. Builds were taking 13 minutes instead of 9 because agents were
   competing with the corpses of earlier agents.

## Machine note

The above was done on the **디폴리스** Windows machine. Paths quoted in agent reports under
`C:\Users\디폴리스\` and any `.claude/worktrees/agent-*` are local to it and do not exist
elsewhere. Everything that matters is on GitHub. On a new machine: `gh auth login`, then
`supabase login` if `supabase projects list` fails, then `npm ci`.

---

# ▼ RESUME ANCHOR — 2026-09-06 (HISTORY) ▼

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
| **#30** `0077: one authority for a gun slot` | A real bug found by playing: `ship_classes.guns` and `public.class_slots` are two authorities for one number and `cmd.do_fit` read the wrong one, so a **barca could mount no weapon at all** and a nau would have taken twelve. | Green. Supersedes **#28**, which claimed a version already taken on `main` and was closed with its reasons. |
| **0078** `the chain does not race its own clock` | The deadlock below, fixed at its cause. Adds `docs/DEPLOY_RUNBOOK.md`. | Stacked on #29 and #30 — **merge those two first**. |
| **#5** `[BLOCKED] 0060: forty harbours stop sailing overland` | DRAFT, blocked on purpose | **CLOSED 2026-09-09 (see the top anchor). Was: must be regenerated, not merged** — 0076 rewrote `sea_reaches` and 0060 as drafted would null the two columns 0076 declares NOT NULL. |

## THE DICE WERE LOADED, AND THEY ARE NOT ANY MORE (0078)

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
red that matters gets waved through. It had already failed **`main`** the same evening
(run `33691161924`).

**FIXED 2026-09-06 by 0078** — 0012 now schedules its three jobs and leaves them **INACTIVE**, and no
migration ever starts them, so the chain has no tick to race whatever lands later. `wind_the_clock()`
and `unwind_the_clock()` are the two calls that make that operable, and **`docs/DEPLOY_RUNBOOK.md` is
now the procedure for pushing to production** — which matters immediately, because four unpushed
migrations (0062, 0065, 0066, 0071) write the tick's own tables and a deadlock during `db push`
aborts the push part-way through the chain. **A database built from scratch now ends with its clock
stopped**; that is the deliberate trade, and starting it is one call.

## WHAT THE OWNER IS STILL OWED

* **Rows 51, 53 and 63 were built and the ledger never said so** — corrected 2026-09-06, with the
  pattern named in `OWNER_REQUESTS.md`'s rules: **all three landed in client-only PRs**, which touch
  no migration and so slip past the habit that makes anyone open the ledger. The dev log missed the
  same three for the same reason.
* **Nobody has driven the running game since 0070.** Rows 48, 52, 53, 63 and 72 are all built and
  none is verified under rule 2. **0076 in particular has never been looked at** — the dotted
  roadstead line, the mark, and a SAIL whose track begins at the roads rather than at the city.
* **⚠ 309 PORT PAIRS ARE SOLD A ROUTE ACROSS THE MALAY PENINSULA.** One `CHANNELS` record names two
  rivers and carves a canal through the Tenasserim mountains; Thanlyin → Ayutthaya answers 323 nm
  against 1,977 nm of real sea. Measured 2026-09-06, `docs/LAND_CARVE_RECON.md`. **The repair is a
  two-raster slice with a balance pass and the decision is the owner's** — it was attempted and
  stopped at the generator's own cross-check rather than shipped half-done. `tests/seaCarve.spec.ts`
  now pins the carve so it cannot change again unnoticed.
* **Stage 2 has one slice left**: *Regions and the map split* (owner row 59), still design-only.
  Stage 3 is untouched: crafting recipes · captain ranks/roles/cabins (rows 61/66) · homesickness.
* **Row 65's role half does not exist.** `ship_classes.tier` is real and 0074 gave slots by tier,
  but `family` carries a culture ('Western'), not trading/exploration/combat.
* **Row 67 is unanswered**: the owner called the good categories a dump — *"wtf is foodstuff?"*
* ~~**Named spaghetti, still not fixed:** `culture = any(g.culture_mask)` is written **five** times in
  the live schema (`do_buy`, `do_sell`, `world.market`, `trade_routes`, `cmd.haggle`).~~
  **FOLDED 2026-09-08 by migration 0080** into `public.culture_refuses(text, text[])` — and the
  count was five FUNCTIONS but **six SITES**, because `world.trade_routes` asks it twice. Proven a
  no-op on all 124,474 (port, good) pairs, each body its own pre-image with only the declared hunks
  swapped in. **On a branch, not merged, not deployed.** DEV_LOG D41. It also found something the
  repo did not know: **the culture rule is unreachable on the quay** — 254 refused pairs, all
  stocked, **0** on any roster, so `world.market` serves `available = true` on every row at all 224
  harbours. 0062's origin-based roster strictly shadows 0002's culture gate for BUY and the market
  screen; it stays live for SELL, haggle and `trade_routes`'s destination. **That is a design
  question for the owner and 0080 deliberately asserts nothing about it.**
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
