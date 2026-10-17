# 2026-10-18 — 0153: two equal hulls are told apart by their id — `osn-hull-tie-by-id`

**Defect (found by the 0137 proof fix, PR #169):** `public.fleet_load` (`order by cap desc`) and
`public.fleet_unload` (`order by have desc`) left a tie between equal hulls to the heap's physical
order (`public.ships` has no index on `fleet_id`). Which hull took a parcel, and so the fleet's laden
speed, could change whenever a row was updated. The owner's default was yes: break the tie by ship id.

**Fix (migration 0153, provisional number):** adds `, s.id` to exactly those two ORDER BYs. The bodies
were sliced from production's live text, read-only on 2026-10-18 at head 0152 (last cut by 0081). Each
hunk is asserted to occur exactly once. No data is rewritten, and no other hull order is touched.

**Self-assert:**
- Parity by reverse substitution. ACL, language, volatility, SECURITY DEFINER and config are unchanged.
- The probe uses a house of its own with two hulls of one class, founded inside a block that is rolled back.
- A one-tun load and a one-tun unload each go to the lower id. Each runs in its own subtransaction,
  once with each hull's row moved to the end of the heap.
- On unequal hulls (re-classed, both directions, both heap orders) and on unequal holds to unload, the
  new bodies write exactly what the old bodies write in 8 cases. Every load splits across both hulls,
  so the compare is not vacuous.

**Measured locally** (cached-prefix `npm run build`, 128 of 144 files restored, 16 applied):
- `0153 loads and unloads timed: 12 call(s), mean 1.333 ms`.
- `the old bodies, on the same 4 equal-hull runs, put the tun in (or took it from) the higher id 2 time(s)`.
  This is the defect reproduced: moving a row flipped the old answer. It is reported as a notice only.
- The `0153 self-assert ok` receipt printed.

**Not done:** merge, `db push`, or anything written to production. The number may move to head+1 at
merge. skills K2 is also claiming 0153.
