# 2026-10-19 — stores, repairs and wages cost a fifth (migration 0210, `osn-running-costs-d5`) — WIP, NOT FOR DEPLOY

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
- Proofs with 0210: 02 ledger ✓, 05 ✓, 11 standing route ✓, **07 standing provision ✗ (5/6 markers) — not read yet.**

## HAND-OFF

**Done:** the migration (green self-assert locally), the client caption, the two spec repoints, the prod read-only check.
**Not done / not verified:**
1. **Proof 07 is red** with 0210 — read `node scripts/db/proof.mjs 07_` to its failing marker (likely a pinned
   provisioning cost or owed figure that moved ÷ 5; fix the cause or move the pin deliberately).
2. **The paired merchant sim was stopped** before it finished: no before/after lap numbers yet. Re-run per
   origin/osn-arrivals-fast `scripts/ops/harness/arrfast/README.md` (state from prod read-only, `mkworld` on the
   head-0208 image, then `sim.mjs world 25 out.json [0210.sql]` for each arm, side by side; `cmp.mjs`).
3. Typecheck / lint / duplication / sections / db.chain specs were not run to completion. `tests/db.chain.spec.ts`
   pins the chain's last migration and will need its pin moved to 0210.
4. Break the owed-scaling and ACL-restore asserts on a world that has owed rows and Supabase ACLs (CI's apply-proof does).
5. Then open the PR (branch `osn-running-costs-d5`), read every check, remove the NOT FOR DEPLOY line.
