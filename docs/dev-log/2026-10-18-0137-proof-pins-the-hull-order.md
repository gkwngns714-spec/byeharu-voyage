# 2026-10-18 — 0137's self-assert corrected after deploy: the proof pins the hull order — `osn-fix-0137-proof`

**Defect:** main's full acceptance went red on 162c230 (job 117389612522). The growth test
(`tests/db.chain.spec.ts:677`) failed 0137 §4 on one merchant: *"the run wrote a different state"*.
Old and new `npc_tend` wrote the same receipt, ducats, quay, ledger and counts everywhere except
`public.ships` (10 updates against 8), with different `orders` and `voyages` rows.

**Cause (reproduced, not inferred):** a false negative of the proof. 0137 did not change behaviour.
- `public.fleet_load` (`order by cap desc`) and `public.fleet_unload` (`order by have desc`) leave a tie
  between equal hulls to the heap's physical order. 0137 touches neither function.
- The first run of each §4 pair is rolled back, but its dead tuples stay on the pages. The second run's
  updated rows therefore land somewhere else, and the tie can break the other way.
- The result is that one parcel is stowed in the other hull. That changes the laden speed, so the
  voyage's `speed_profile`, the SAIL order's `voyage_days` and the number of hull updates all move.
- Reproduced on the growth-path world (PGlite: 0001–0040, a house founded and buying, then 0041–0136).
  Running NEW `npc_tend` against NEW `npc_tend` on all 837 merchants with the same `p_now` gave one
  merchant whose two parcels went into one hull in the first run and two hulls in the second
  (6.1547 kn against 6.3263 kn, 4.63 days against 4.50). She did the same on every repeat. With the
  hull order pinned, the same pair of runs differs on 0 merchants of 837.
- On that world the unchanged 0137 happened to pass, both with the 12-merchant sample and with all 837.
  The outcome depends on where rows lie on disk, which is why only CI's world tripped it.

**Fix:** a change to the proof only. No function body and no data changed.
- New `pg_temp.pin_hull_order_0137`, called at the top of every rolled-back run. It re-creates both
  loaders from their live text, adding `, s.id` to that one ORDER BY. The line must occur exactly once
  in each function, and that is asserted.
- The pin is undone along with each run, so old and new break the tie the same way.
- The compare is unchanged: the receipt plus every row the run itself wrote.
- **Production ran the earlier text, and that text passed.** 0137 is recorded on prod and is not
  re-applied. Nothing live changes.
- The file's header says the assert was corrected after deploy.

**Left as found (not this slice):** in the game itself, which of two equal hulls takes a parcel, and so
the fleet's laden speed, still depends on the heap. A deterministic tie-break in the live loaders would
be a new migration. That is the owner's call.

**CI consequence:** the edit changes 0137's file hash. An edited migration is the exemption in
docs/CI.md §2: a from-zero apply is allowed there (with a warning) whenever no kept snapshot fits.
