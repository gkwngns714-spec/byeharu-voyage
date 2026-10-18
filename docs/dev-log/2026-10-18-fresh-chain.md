# 2026-10-18 — the chain applies from zero again (0137, 0156: self-assert only) — `osn-fresh-chain`

**The red.** The nightly from-zero run (Migrations — apply proof, schedule, 2026-10-17T20:43Z,
run 39067931842) failed in `disposable-chain` on real Postgres at **0156**:
`world.inn at … serves the captains of today differently`. A local `npm run db:proof` failed
earlier in the chain, at **0137**: `the quay probe priced 4 / 4 of 4 harbour(s), or one served no
goods`. PR CI stayed green only because it restores a world saved past both files.

Both are the same class, and the class is not the clock. **Port ids are `gen_random_uuid()` (0002),
so every from-zero world draws a new set**, and each probe read something that depends on that draw.
Prod and the saved snapshots happened to draw well.

## 0137 — a sea place in the drift sample

`drift_sample_0137` picks one harbour per arm. The `works` arm ranked **every port** (`from
public.ports`) by `works_factor`, tie-broken by id. In a fresh world no port has works, so every
factor is 1 and the arm takes the **lowest uuid of all 252 ports**. 14 of them are `SEA_PLACE`s:
no `port_goods`, no roster, so `world.market` lists nothing. The drift half still passes (it groups
by sample rows, and a sea place has none), the quay half fails. Roughly 1 world in 18.

Reproduced on a from-zero world built here (snapshot after 0128 plus 0129–0136): every arm picked a
harbour (HAD, STJ, CAP), and 0137 passed. Then, in the same transaction, one sea place was copied
under id `00000000-0000-4000-8000-000000000001` (now the lowest). The prod-identical 0137 failed with
the exact message, `4 / 4 of 4`. The fixed 0137 passed on that world, with 3 harbours, 1665 rows and
13 goods.

**Fix:** the `works` arm ranks only ports with a market (`po.id in (select port_id from per_port)`).
The assert "the world has a works-bent harbour but the sample does not" uses the same domain.

## 0156 — two captains named Virji Vora

`world.inn` (0073/0119/0154 body, until 0166) seats its room `order by o.specialty, o.name`.
MUGPURSER (0073) and NPCPURSERMUG (0098) are both PURSERs named Virji Vora, so their relative order
belongs to the plan and heap, not to the read. The nightly log shows the same four guests in both
arrays, with only those two swapped. 0166 later fixed the body (`… o.name, o.code`) and compares
through `canon_0166`. 0156's assert compared order-exact.

**Fix:** both sides are compared in one canonical order `(specialty, name, code)`, as 0166 does. A new
check asserts that the read's own order is `(specialty, name)`, so the order the body states is still
proven. Checked on the nightly's literal arrays: the old compare fails, the new one passes, the order
check passes, and the new compare still catches a missing guest.

## Prod is untouched

Both edits are inside the self-assert only:

- 0137: a `create temp table … on commit drop` CTE that feeds the probe, plus one condition inside
  the `do $$` assert.
- 0156: one `do $$` assert block.

No `create function`, slice, hunk, grant, `insert`/`update` of a real table or comment changed. Prod
applied both files long ago, and nothing re-runs them there. Precedent: #178 (0150, self-assert only).

## Other self-asserts of the same class

The CI log and the local runs stop at the first failure, so the whole chain was applied twice after
the fixes:

1. **Cached:** the 0128 snapshot of the first from-zero world, plus 0129–0178, then the 12 proofs.
   Green, 85/85 PASS markers, 19 min 20 s.
2. **From zero:** a new world (new uuids), with `node scripts/db/proof.mjs --fresh`. Result in the
   PR body.

I also scanned 0130–0179 for port picks that do not filter `kind`. The one other hit (0137:1129) is a
prod body, not a probe.

## CI

This edits two applied migrations, which is the no-from-zero law's one exemption (`select`'s
`cold`). So this PR's `disposable-chain` applies from zero on real Postgres and says so. That is
also the engine the 0156 red came from.
