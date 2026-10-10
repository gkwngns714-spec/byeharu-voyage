# RESUME — NPC traders (branch `osn-npc-traders`)

Stopped by the owner 2026-10-08 17:12 KST; the review's findings were **fixed 2026-10-10**. This
file is the resume anchor; delete it in the commit that opens the PR.

## State — 2026-10-10 (evening)

- Branch: **0096-0100**, proof 12, the chart and the sheet. Plan = `docs/NPC_TRADERS.md`. Dark behind
  `npc_traders_enabled`. **Production head is still 0095.**
- **The owner opened the game mid-session and gave five more instructions** (rows 109(b), 112, 113).
  Done: the roster grown threefold (26 → 70 companies, 35 → 107 fleets authored; `npc_fleet_max`
  40 → 120), **0100** the sea ten times slower (`time_compression` 9600 → 960 — the CLOCK, not the
  hull's knots, and 0100's header argues why at length), and **row 112** the merchants' whole routes
  drawn on the chart from the baked courses their card now serves.
- **Row 113 — levels, requirements, captain traits, and restrictions by route length, carrying
  capacity and region entry — is DESIGNED IN THE LEDGER AND NOT BUILT.** It is the next slice and a
  migration of its own (0101). It was deliberately not bolted onto this one.
- A second preview with the merchants switched ON is built by hand for looking at a dark feature:
  `node <scratch>/make-npc-demo.mjs` writes `dist-npc-demo/` (git-ignored) and
  `vite preview --outDir dist-npc-demo --port 4174` serves it.
- **TWO adversarial reviews, and every finding of both is fixed** — the first 1 blocker + 4 majors +
  6 minors, the second 11 more (lap 1 was still inside the lap average; the crew-pool floor could
  strand a merchant for ever; a traffic read already on the wire could land after its release; a
  docked merchant's drawn place moved when a NEIGHBOUR docked). The account is `docs/DEV_LOG.md`
  2026-10-10, both entries.
- The owner-visible problems from the screenshots are fixed too, except the one named below.
- The two test edits the hand-off asked to audit (`a038f69` proof 11, `feeec66` the merchant spec)
  were audited and **both stand**; the reasons are in the dev log.
- A flaky browser test was found and made deterministic: a drifting hull could lose its tap to the
  player's own fleet (which wins a tie by design), so the tap is aimed again rather than hoped for.

## Gates run on this branch, 2026-10-10

| gate | result |
|---|---|
| `npm run db:apply` (whole chain on PGlite, every self-assert) | **exit 0** |
| `npm run db:proof` | **12 files, 85/85 PASS markers** (Node 26) |
| `npm run db:check-versions` | 92 migrations, no collisions, positive control seen |
| `npx tsc -b` | 0 |
| `npx eslint .` | 0 |
| `vite build` | 0 — **on Node 26**; see the note below |
| `npx playwright test tests/map.merchants.spec.ts` | **10 / 10**, screenshots re-shot |
| `layout` · `words` · `sections` · `duplication` · `flicker` · `route.stopface` · `trade.ceiling` · `wide.layout` · `firstRead.empty` · `primitives.geometry` | green — run them with the machine to themselves; eleven spec files in one worker beside `db:proof` lost four of them to 60-second boot timeouts, and all four passed on their own (18 / 18) |

Proof 12 now reads **`87 merchant laps closed by 33 of 33 fleets`** — before the blocker fix it
tolerated fleets left laid up for want of a paying cargo, which is the state no merchant could ever
leave again.

**Node note.** `vite build` fails on this machine's default Node 20 (`TypeError: Unknown file
extension ".ts"` from the `byeharu:world-image` plugin) and succeeds on Node 26. It fails the same
way on a clean `main`, so it is the toolchain, not the branch (`TOOLCHAIN.md` records Node 24).

## Next steps, in order

1. **Have the fix pass adversarially reviewed** before the PR, as the build was.
2. Push, open a **DRAFT** PR, let CI (build · pglite-gate · disposable-chain · acceptance) go green.
   Before deploy: regenerate 0098 with `--taken` (production's company names).
3. **Do not merge or deploy without the owner.** The deploy is the runbook (clock off → `supabase db
   push --linked` by hand → clock on → read the heads back), and the switch is one statement the
   owner runs after the soak: `select public.npc_traders_switch(true);`.

## The one open question for the owner — "the sea must look busy"

Row 109's other half. Measured on the built roster
(`node scripts/db/measure-merchants.mjs --ticks 20`, driven UNPACED, which is the **ceiling** the
`npc_laps_per_game_day` lever can buy):

| | |
|---|---|
| hulls in the Lisbon 12° frame | **mean 3.4, min 2, max 5** |
| rows per closed lap | 161.9 · **1,076 retained** after `npc_compact`, against a budget of 100,000 |
| `world.sea_traffic()` | **7.07 ms/call**, 12.7 KB, 32 fleets at sea |

So the pace knob cannot make the sea busier: the binding constraint is the **roster** (23 companies
/ 32 fleets over 214 harbours). The cost figures say there is room for more. But more fleets means a
roster past this plan's own maxima (26 companies / 35 fleets) and more hands trading in the market
players trade in — a gameplay decision, so it waits for the owner. One contributor WAS a defect and
is fixed: merchants lying in one port were drawn on top of one another, so three at Lisbon looked
like one.

## The Fable review findings, and where each one landed

| # | finding | fixed in |
|---|---|---|
| blocker | a laid-up merchant route could never be resumed (`updated_at` vs the plan's receipt) | 0097 `npc_tend` + its self-assert, with a positive control |
| major | the card moved the selected hull (teleport on every beat) | `src/chart/liveWorld.ts` `trackedVoyage` + two specs |
| major | stale traffic painted on return to MAP, then every hull leapt | `src/live/worldStore.ts` `wantTraffic` |
| major | `A lap ≈ −116,690` on a merchant whose cargo paid +139,165 next lap | `public.route_earnings` + `MerchantSheet.tsx` (the boundary itself is the owner's call) |
| major | flag-off was not inert: `npc_compact` ran dark | 0097, gated + the DARK assert extended |
| minor | docked merchants stacked at one point; a hull stole a dot city's tap | `liveWorld.ts` `fannedBerth`, `hitTest.ts` |
| minor | `refounded … last 14:32` for an event days old | `MerchantSheet.tsx`, the relative form off the one clock |
| minor | the card served `voyage.id`, a callable handle | 0099, stripped + key set asserted |
| minor | the carried ledger row's `balance_after` picked the highest of a tick | 0097, computed exactly |
| minor | the "stock floor" assert could not fail for its stated reason | 0097, the ceiling proven directly at `world.quote` |
| minor | merchants would drain `ports.crew_pool`, which nothing regenerates | `cmd.standing_route_tail` re-cut by 0097, new knob `npc_crew_pool_floor` |
