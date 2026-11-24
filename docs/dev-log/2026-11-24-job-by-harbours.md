# 2026-11-24 — 0494 `job-by-harbours`: a job sails harbour by harbour (a repair, proof 197)

The owner's report (prod, read by the lead): a `land` job, settings `{"to": "CAD"}`, stopped with `E_LEG_TOO_FAR`; its last word was
"Line 1 (SAIL LIS): that leg is 7052 nm and your navigation carries you 1700 nm — study navigation". Plan:
`docs/design/remaster-2026-11-24.md`, "One travel rule".

## The cause (read in the bodies, then reproduced)

- Why LIS when the settings say CAD: `to` is the yard the Land's goods are carried to. The fleet lay at Island of Mozambique, not at the
  Land's harbour, and a land job that is anywhere else first sails back to the party's harbour (`public.fleet_job_plan`, the land
  branch: `fleet_job_sails(f.id, f.port_id, array[v_land])`, `v_to := v_land`). A party lives in the company's home city
  (`public.land_party`, 0455): Lisbon. So the plan was the single line `SAIL LIS`.
- Why it was refused: `public.fleet_job_sails` writes one SAIL for each harbour it is sent, with the course `public.fleet_job_course`
  gives. With `sea_courses_enabled` lit (0482) there is a stored course between every two harbours, so ISL -> LIS got one: 7,052 nm in
  one leg. `cmd.issue_lines`' reach gate (0188, `public.passage_gate`) refused it against 1,700 nm.
- The same fault in every kind: fixed and bring-home legs are one SAIL each; `best` asked the harbours between only by the miles table.
  The door (`public.fleet_job_set_for`) asked only whether a course exists.
- Reproduced locally: the same scene gives the owner's sentence to the letter (7052 nm, 1700 nm) before the change.

## The fix (one authority, no second pathfinder, no table, no knob)

`public.fleet_job_sails` is the one writer of every job's SAIL lines. It now asks `public.fleet_job_legs(fleet, from, to)` for each
harbour: the course measured as the door measures it, judged by `voyage.leg_refusal`; open -> the one SAIL as before; shut by its
length or its stores -> the harbours between from `voyage.reach_passage` (capped by `public.supply_reach`, as `world.route_legs`' `via`
asks it), each hop with its own course and judged the same way; no chain -> `{pause: <the judge's code>, sentence: "she cannot sail
from A to B harbour by harbour: ..."}`.

- The door refuses a fixed, bring-home or land job with no chain when it is set (out, back, and her first sail from where she lies).
- A job stopped on `E_LEG_TOO_FAR` or `E_ENDURANCE` is due again 10 minutes after its last word (`public.fleet_jobs_due`); a start
  lifts the stop (`public.fleet_job_open`); every try stamps `last.at` (`public.tick_fleet_jobs`), so at most one plan in 10 minutes.
  So the reported job goes on by itself after the deploy.
- Decided by default: 10 minutes is a constant; stops on other codes still wait for the player; the news line is English in both slots.

Ten hunks over seven bodies, two new STABLE server-only functions. No knob or switch is changed.

## Measurements (local, PGlite, the chain's world at 0492 + 0494)

- The migration: 845 ms, self-assert included.
- The tick's plan step, same scene before and after the hunks: a near fixed job (cork at Porto) 1.0 -> 2.0 ms, same lines to the
  letter (digest `17d85f48`); the reported land job 2.0 ms (stopped) -> 43 ms (started: one `voyage.reach_passage`, 17-29 ms, and
  seven courses measured and judged).
- The reported case after: `SAIL SOF / SAIL CPT / SAIL LUA / SAIL CAP / SAIL SAI / SAIL LPA / SAIL LIS`, the longest leg 1,630 of
  1,700 nm. Proof 197 sails all seven legs: she lies at Lisbon, no order failed.
- A stopped job: before, never planned again; after, at most one plan in 10 minutes.
- Proof 197: 7/7 PASS (each kind, the retry, no hot loop, the door's refusals). Proofs 183, 184, 185, 186, 195 pass with 0494.

## Not verified

- Nothing on production: no prod read was run by the builder. `scripts/ops/harness/job-by-harbours/before-0494.sql` reads the seven
  bodies' digests, the scene's chain and the stopped jobs the tick will retry; `after-0494.sql` reads what came of them.
- 0493 was not in this branch's chain (it touches none of these bodies).
- No client change: HQ still prints the stop's code and sentence as it did.
