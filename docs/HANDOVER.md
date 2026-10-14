# HANDOVER — 2026-10-13, picking this up on another machine

Written to be read FIRST, by whoever (or whichever session) continues. It says where the work got
to, what is green, what is red, and the one thing that is red for a reason nobody has looked into
yet. Everything below is measured, not remembered.

## Where to start

```bash
git clone <repo> && cd byeharu-voyage       # or the worktree: C:\Users\gkwng\bv-npc
git checkout osn-npc-traders                 # PR #94, branched off main
npm ci
npm run build                                # ~19 min on a COLD world-image cache, ~1 s on a warm one
npm run preview                              # serves dist on :4173, which the browser specs need
```

Branch head at handover: **`7911583`**, everything committed and pushed. Nothing is stashed.

## What this branch is

The merchant world (`docs/NPC_FLEET_SCALE.md` slices A–G) plus owner rows 125–127. In order:

| migration | what it does |
|---|---|
| `0101` | a lap ends in a fortnight at home; loops may call at 8 harbours |
| `0102` | `world.sea_traffic` takes a viewport and a cap; also serves hull classes |
| `0104` | a harbour reads back its merchants and what each is doing |
| `0105` | the ×10 roster — 761 fleets over 219 loops |
| `0106` | the ranked ROUTES board |
| `0107`–`0110` | the gates refuse, print the requirement, keep what she can sail, ask once |
| `0111` | **a major fleet draws her lane** — the newest, written this session |

**Production is at `0110`, 102 migrations, merchants abroad, 316 fleets sailing.** `0111` has NOT
been pushed to production. It is proven locally and in the build, but production is a separate,
deliberate step and the branch is not merged.

## Green, and how it was proven

* The whole **103-migration chain** applies clean inside `npm run build` — image
  `world-dddd97f12429af92-103-bf5026.tar.gz`.
* `0111` against the real `0110` state: 240 of 837 fleets served, **49 lanes**, longest exactly at
  the 24-point cap, every loop closing on its home quay.
* **47 browser specs** green — `map.night`, `map.marks`, `map.voyage` at 390×844 and 1440×900, dark
  and light: 252 harbour lights, 0 port marks at the widest zoom, 49 embers with 0 hull paths, 49
  lanes in 8 nation inks, every ember blinking on its own phase.
* `rpc.surface` 28/28. `tsc -b` and `eslint` clean.
* CI: **`build` 39 s**, **`disposable-chain` 31m47s** — both green on the head commit.

## RED, and this is the one to look at first

**`pglite-gate` is failing on REAL PROOF FAILURES, not on its budget.** Run 38259568246, which had
a 150-minute budget and failed at 1h35m — so it finished early with genuine errors:

```
SQL ERROR: PROOF 1 SETUP FAILED: the fleet did not depart for Tunis on attempt 1
SQL ERROR: PROOF 5 FAILED: 8 of 32 (port, market) pairs offer no profitable first voyage at all
PROOFS FAILED: 2 of 12 file(s); 74/85 PASS markers seen
```

These are **market and economy** proofs. Nothing in this session touched the market: the work was
the chart (lights, embers, lanes, the zoom readout, the fleet tray), migration `0111` (one read-only
key on `world.sea_traffic`), and CI budgets.

**The hypothesis, untested, and it should be tested before it is believed:** `0105` founded 761 more
merchant companies, all of them buying and selling. "8 of 32 (port, market) pairs offer no
profitable first voyage" is exactly what a market would say if several hundred new traders had drawn
the spread out of it — and there is a known, unresolved design question in the same area, recorded
with the owner: **two-thirds of the 761 fleets cannot trade at all**, because there is one merchant
buyer per `(port, good)` world-wide — 1,288 slots. Widening that is a market-rule change and the
owner has not decided it.

**How to test the hypothesis cheaply:** apply the chain to `0104` (before the roster) and run
`npm run db:proof`; then to `0105` and run it again. If `0105` is the line, that is the answer and
the decision is the owner's, not an engineer's.

Do **not** merge PR #94 until this is understood. `disposable-chain` — the same chain, on a real
Postgres — is green, so the chain itself is not in question; what is red is the economy the roster
produces.

**`acceptance` is a separate, lesser problem:** it hit its 120-minute budget still running. That is
wall-clock, not an assertion.

## CI, and the fix that is now blocking

Four workflows. Budgets were raised repeatedly this session and the comments in each file carry the
measurements, so read those before touching a number.

| job | budget | last result |
|---|---|---|
| `build` | 60 | pass, 39 s |
| `deploy-pages` | 60 / 10 | not run since before the roster |
| `disposable-chain` | 60 | pass, 31m47s |
| `acceptance` | 120 | fail — hit the budget |
| `pglite-gate` | 150 | **fail — real proof failures (above)** |

Two caches were added and both are measured wins:

* the **world image** (`node_modules/.cache/byeharu-world-image`, keyed on the chain) — `acceptance`
  was the only workflow missing it, and its build step went from **32m33s to 9 seconds**.
* the **merchants-on world** (`node_modules/.cache/byeharu-npc-on`, keyed on the chain AND on a hash
  of `tests/npcOn.fixture.ts` itself) — the fixture took ~9 minutes per Playwright worker.

**Row 124 is the outstanding real fix and it is now load-bearing.** `pglite-gate` spends ~47 minutes
re-applying a chain `disposable-chain` has already applied, green, on the same commit, in ~32
minutes, and then leaves idle. That job's unique value is `npm run db:proof`, not the apply beneath
it. Giving `scripts/db/proof.mjs` a path that does not call `applyChain()` deletes the cost instead
of budgeting for it. It was deliberately not done in a hurry inside a workflow edit.

## The local loop, which is now fast — use it

Both caches work locally too. The practical numbers, measured:

```
npm run build                     ~1 s   (warm world-image cache; ~19 min on a miss)
npx playwright test map.night     ~30 s  (warm npc-on cache; ~10 min on a miss)
```

**The trap that costs 19 minutes, and it is easy to fall into:** editing ANY migration — *even only
its comments* — changes `fingerprintChain`, which invalidates the world image, and then every
browser spec fails with *"A ready-made world that did not match this build was discarded"* while
Chromium applies 103 migrations itself. The spec reads as a chart bug and is not one. **Finish all
migration edits before building for a browser run.** Order: migrations → build → specs → commit.

To check the pairing when something looks wrong, compare `app_local.chain.fingerprint` inside
`dist/db/world-*.tar.gz` against `chainAndFingerprint()` from `scripts/db/build-image.mjs`.

## The demo build the owner looks at

`dist-npc-demo` is `dist` plus the merchants-on world, served on :4174. It is **not** produced by
the build and must be refreshed by hand, or the owner is shown an older build than the one being
verified — which happened twice this session.

```bash
rm -rf dist-npc-demo && cp -r dist dist-npc-demo
cp node_modules/.cache/byeharu-npc-on/world-*.fixture-*.tar.gz \
   dist-npc-demo/db/world-dddd97f12429af92-103-bf5026.tar.gz   # the name the bundle asks for
```

(That takes ~2 seconds now. It used to run the switch over 837 fleets and take ~9 minutes.)

## Open, with the owner

1. **Row 124** — the proof script's database. Blocking `pglite-gate`. Described above.
2. **The tray's empty space.** Drag the map detail tray up on a thin fleet and the bottom is blank:
   `half` is a fixed 50% of the glass. The honest fix is a **content-sized stop**, but that detent
   ladder is shared by every tray in the app (`docs/UI_DIRECTION.md` §5), so it is the owner's call.
3. **The harbour glow on the LIGHT theme.** Lights now burn at every zoom; on the day sea they read
   as pale tan smudges over white land. The dark map is right; the day one wants a deeper, tighter
   pen than the night one.
4. **The merchant market ceiling** — one merchant buyer per `(port, good)`, 1,288 slots against 761
   fleets. Two-thirds cannot trade. Possibly the cause of the red above. A market-rule change.
5. **Row 123** — the wide-zoom viewport cap is centre-weighted, so panning reshuffles which 240
   merchants appear and the edges look empty. An even spatial spread was offered, not yet done.

## Laws that are not negotiable here

* Migrations are **forward-only**. Never edit one that production has applied.
* Every migration **proves itself in its own transaction** and prints a
  `raise notice '<NNNN> self-assert ok: …'` receipt. A vacuous assert is worse than none — `0111`
  passed its parity check on two EMPTY fleet lists this session before that was caught, and it now
  refuses an empty sea before parity is allowed to mean anything.
* Never `git add -A`; stage specific paths.
* Never merge past an unread red.
* Production writes are gated by the permission classifier; do not work around it.
* Supabase project `dlkbwztrdvnnjlvaydut` is the old frozen `byeharu` — **do not touch it**.
* Secrets stay out of the transcript: `supabase login` in your own terminal, or `setx`.
* Node 20 cannot build this repo. Use Node 26 (`C:\Users\gkwng\AppData\Local\nvm\v26.2.0\node.exe`
  on the old machine).
