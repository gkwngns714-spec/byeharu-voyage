# 2026-10-19 — stores, repairs and wages cost a fifth (migration 0210, `osn-running-costs-d5`)

**The order.** The owner, 2026-10-19, after 0208: "supplies and repairs yes" (÷ 5 like goods). On wages: "wages are in % so
it will be same right?" They are not a percentage (crew × wage_per_crew_day × short-rations mult × running_cost_mult).
**Decided by default** (the owner may reverse it): wages ÷ 5 too, so running costs keep pace with the ÷ 5 prices.

## What the migration does (one knob, `running_cost_level` 0.2, applied once in each cost's one authority)

| cost | the one place | follows with no hunk |
|---|---|---|
| stores | `public.stores_cost` | `cmd.do_provision`, `npc_provision_for`, `npc_plan` |
| hull repair | `cmd.do_repair`'s charge line | `cmd.preview` (runs do_repair) |
| gear repair | `public.unit_repair_cost` (recipe value is the DESIGN value since 0208, so it needed the term explicitly) | `gear_repair_quote`, `unmount_fitting` |
| wages | `public.crew_wages` | `fleet_wage` → `voyage.settle`, `world.crew_cost`, `cmd.do_dismiss`, `world.good_board`; `npc_leg_lines` |

**Wage rounding.** `crew_wages` now returns the exact numeric (crew 2 → 0.4/day; it used to round per call, which at 0.2
would owe 0 for ever, or 1 instead of 0.6). `fleet_wage` rounds to 4 places; `voyage.settle`'s day wage is numeric;
`fleet_wages.owed` is numeric; `owe_wages` takes numeric; `pay_wages` (the one mover) pays `floor(...)` whole ducats and
the fraction stays owed. Over a voyage the crew is paid the exact sum, less under one ducat still owed.
(crew_wages, fleet_wage, owe_wages are dropped + recreated, with the pre-image ACL and comment restored.)

**Decided by default:** existing owed wages × 0.2 (prod 838 rows, 410,260 → 82,052 at the read-only check). Kept: tow,
hire fee, officers' wages, ship prices, cash, purses, profit-tax rates, the 0208 knobs, wages_owed_cap_days, npc_cost_mult.

**Client:** the Inn's wages row prints with `formatPrice` (0.60 🪙, not 1). `tests/rpc.surface.spec.ts` holds
`per_day` to the exact `crew × wage × running_cost_level`; `tests/layout.spec.ts` reads a decimal figure.

## Measured / proven so far

- Self-assert on the local head-0208 image: green. Receipt: PROVISION FULL 46.3 t / 34.7 t cost 53 (old 266); crew 3:
  7 sea-days owed 4.2 exactly (rounded per day would be 7), paid 4, 0.2 still owed; crew 313: 5 sea-days owed 313.0
  (rounded per day 315), profit 100 paid 100; owed 2.6 paid 2 left 0.6; REPAIR 200 points cost 66 (old 328).
  Timings ×8 flat: crew_wages / fleet_wage / stores_cost / unit_repair_cost ~0–1 ms, npc_provision_for 24 then 1–5 ms,
  voyage.settle 0–5 ms per step.
- Break tests (each fails with its own message): wage 0.25, settle variable left bigint, pay_wages left at round,
  stores / hull / gear without the level. VACUOUS locally: owed scaling (0 owed rows in the image) and the ACL restore
  (the browser image has owner-only ACLs) — not yet broken on a world that has them.
- Prod, read-only at head 0208: every hunk occurs exactly once; the 8 live md5s equal the local pre-images; the
  old-arithmetic copies equal the live bodies on all 675 gear, 98 stores and 802 crew grid rows; knob absent.
- Proof 05 (a starter's best first voyage, % of stake): before **18.2** {15.5, 19.8, 19.1}, worst 11.2 / best 24.8;
  after **18.2** {15.2, 19.3, 19.5}, worst 10.9 / best 24.2. Band 14.7–21.7 not moved.
- Proofs with 0210: 02 ledger ✓, 05 ✓, 11 standing route ✓, 07 standing provision ✗ (5/6) — read and fixed 10-20, below.

## 2026-10-20: finished (the hand-off's five items)

**1. Proof 07's red, to its root cause.** One diagnostic run with a notice at the drained arrival: purse 0, and a sixth
PROVISIONED event — the last top-up (1.280 t water, 0.960 t food, a 1.6-day passage) cost **1** ducat at a fifth of the
price (old: 1.28 × 2 + 0.96 × 5 = 6.9 → 7, more than her last ducat). The order bought, and nothing was refused. The proof
had BORROWED a precondition (that a short top-up costs more than a ducat) from the price level. Fixed in the proof, not
the pin: before she sails, her casks are run down to three days of stores (the passage takes under two), so the standing
order has some forty days to buy. 6/6 markers with 0210 in the chain (1.0 s).

**2. The paired merchant sim**, on the post-0208 world (837 merchant fleets; prod's knobs, stocks, purses, treasuries,
loops and lap counts read read-only 2026-10-19 23:33 UTC; `mkworld` on the head-0208 image; both arms 25 min side by
side on one PC, the migration applied after the setup as prod will apply it; harness = PR #267's
`scripts/ops/harness/arrfast`, local copy in `.arrwork/`). Sweeps ran slow on both arms alike (avg 7.1 / 7.2 s: the two
arms and a spec shared the CPU), so the lap counts are small and the timings are not this measurement.

| | before (0208) | after (0208 + 0210) |
|---|---|---|
| laps closed | 171 | 154 |
| laps ≤ 0 | 59 (35 %) | 57 (37 %) |
| …of which traded (sold > 0) and still lost | 23 | **4** |
| …of which sold nothing (cargo bought, sold next lap) | 36 | 53 |
| total lap net | 141,076 | 130,675 |
| median lap net | 38 | **65.5** |
| lay-ups at kickoff → end (of 837) | 83 → 61 | **29 → 11** |
| sailing at the end | 760 | 807 |
| routes with laps / all their laps ≤ 0 | 118 / 29 | 113 / 29 |
| Comptoir Chastellain lap 239 net | 112 | 193 |
| stranded (error / idle / failed orders) | 0 / 0 / 0 | 0 / 0 / 0 |

Read: the lay-ups 0208 caused (26 → 84 of 837 in its paired sim) come back under the pre-0208 figure (11), and the
laps that trade and still lose fall 23 → 4. The ≤ 0 share is flat (35 → 37 %) and is now mostly laps that bought and
have not sold yet. The total lap net is 7 % lower on 10 % fewer laps (the median lap is 72 % higher): a 25-minute
window closes only the shortest loops, so the sum is the noisier figure. Nothing stranded in either arm.

**The starter's first voyage** (proof 05, % of the stake, the previous session's logs on this PC): before **18.2**
{15.5, 19.8, 19.1}, worst 11.2 / best 24.8; after **18.2** {15.2, 19.3, 19.5}, worst 10.9 / best 24.2. Band 14.7–21.7
not moved. CI's pglite-gate (the rest) re-runs proof 05 with 0210 on this PR.

**3. Prod, read-only, 2026-10-20 at head 0208** (`begin transaction read only`; every function called is `provolatile`
's', checked first): knob absent; goods_price_level 0.2; `fleet_wages.owed` bigint; every one of the 12 hunks occurs
exactly once in its live body (the new text 0 times); the old-arithmetic copies equal the live bodies on all 675 gear,
98 stores and 802 crew grid rows (442 gear prices ≥ 25); the 12 kept knobs at their values; the three dropped-and-
recreated functions' ACL `{postgres=X/postgres,service_role=X/postgres}`, owner postgres, stable / volatile-definer as
expected; `owe_wages(uuid, numeric)` absent; the walls stable; hull_recipes 103 rows 8,498,500; probe uid free, LIS and
FNC have reaches, LIS has a yard. Owed: **838 rows, 448,598 → 89,719.6** (827 non-zero, max 5,400; 215 rows get a
fraction). `new_house` is the 0096 nine-argument form with defaults, so the probe's four-argument call resolves.

**4. The two vacuous breaks, on a world that has what prod has:** the head-0208 image seeded with 850 owed rows
(0–5,400) and prod's `service_role` EXECUTE on crew_wages / fleet_wage / owe_wages. Real file: owed 453,824.2 after
(678 fractional rows), all three ACLs `{postgres=X/postgres,service_role=X/postgres}`. Break "owed not scaled": `850 of
850 owed wage row(s) are not 0.2 × what was owed`. Break "ACL not restored": `public.crew_wages(integer, boolean) changed
its ACL ({postgres=X/postgres,service_role=X/postgres} → {postgres=X/postgres})`. Each fails with its own message.

**5. Locally:** `tsc --noEmit` on tsconfig.app and tsconfig.test: 0 errors. `tests/db.chain.spec.ts` 9 passed (5.3 min;
the 55-minute growth test left to main, as CI's rule has it; it has no hard pin — LAST is read from disk).
`tests/rpc.surface.spec.ts` did not finish locally in the window (no built image in the worktree, so its fixture applies
the chain from zero, starved by the two sim arms): CI's selected run covers it. The NOT FOR DEPLOY header is removed.
