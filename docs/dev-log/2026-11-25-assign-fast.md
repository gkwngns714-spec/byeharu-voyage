# 2026-11-25: `assign-fast`: 0504 (a repair; nothing dark) and the Assign sheet's quiet retry

Owner's live bug: Assign said "the quotes are slow just now: ask again in a moment" (public.sea_actions_for past its 5 s guard).

## Where the time goes (local PGlite, `track_functions`; Guayaquil, the worst harbour, a 3,000,000 purse in the largest hull)

1,825 ms tracked (1,600 untracked): `job_trip` 1,129 (18 trips; 248 legs judged, 80 of them different; `voyage.reach_passage` 20 times
from 11 harbours; `voyage.segments_from_course` 477 times, for the miles alone), `world.best_sales` 602. Bring home's loop is NOT it: a
harbour sells 10 goods at most (629 is its market rows), its `fleet_job_ends` 25 ms and `run_day` 15 ms in all. The numeric power() of
a price step is 8 us here, so quotes weigh more in PGlite than on prod.

## Before and after, every harbour (254), byte for byte the same answer in every one

| world | worst before -> after | mean before -> after |
|---|---|---|
| A: 200,000 purse, first hull | ROT 941 -> 510 (worst after: ALE 546) | 450 -> 315 ms |
| B: 3,000,000 purse, largest hull, jobs wait and near round lit | GUA 1,560 -> 911 (worst after: BUS 933) | 701 -> 456 ms |
| Colombo, A with jobs wait | 521 -> 417 | |

The part beside best_sales is about 0.4 to 0.5 of what it was (the sweeps ran the same bodies while they stood in 0499; 0504's own assert compares her whole read in 14 worlds). The 800 ms target holds in A and NOT in B's worst (933): what is left there is
world.best_sales (about 500), which this file does not touch. Measured with 0499's dark switches as named.

## Contention

- Busy loops beside it, 32 threads, world B: 24 of them: GUA 2,128 -> 1,242, COL 893 -> 661 ms; 40: GUA 3,501 -> 2,067, COL 1,590 -> 1,172.
- 96 of them: old and new BOTH pass 5 s (the guard), COL too: no cut of repeated work outruns such a machine.
- The job tick's plan (a Best job at Colombo): 230 ms before, 232 after: it is world.best_sales; this file gives it nothing there.

## Still slow: proposed, not built

The guard's rule (a slow machine serves the same list, or says so) stands. The honest form of "serve what is priced": a separate read that
prices only the Best run (and Trade nearby), asked first; the list read stays whole-or-E_SLOW beside it. Two reads, each complete for what it
says; no list is ever shorter. It asks best_sales twice unless the first one's answer is handed over.

## The client

E_SLOW is asked again by itself after 2, 5 and 10 s while the sheet stands (its skeleton shows); only then the sentence and Try again.
`land_actions_for` (the other E_SLOW) is served by the same retry; its body prices no trip and was not cut.

## Not verified

Prod (nothing was read): `scripts/ops/harness/assign-fast/split.sql` splits the time there; what the crowd at each full minute adds.
