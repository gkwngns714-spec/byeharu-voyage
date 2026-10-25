# arrfast: the paired arrivals sim of 2026-10-19 (0207)

Run every script from the repo root. The scripts expect their data in `.arrwork/`, which is never committed: it holds prod's state.

1. Read prod's state, read-only:
   - `bash pq.sh q_state.sql .arrwork/state.json`
   - `bash pq.sh q_lapno.sql .arrwork/lapno.json`
   - then `node mkstate.mjs`.
2. Build the chain image at prod's head. Run `npm run db:image` with any newer migration moved aside.
3. Put the merchants to sea: `node mkworld.mjs <chain image> .arrwork/world.tar.gz`. It lights `npc_traders_switch(true)` and should give 837 fleets.
4. Run each arm:
   - `node sim.mjs .arrwork/world.tar.gz 20 out.json [migration.sql]`. The migration is applied AFTER prod's knobs are laid over the world.
   - `ARRFAST_SETUP=0 node sim.mjs <prepared world> ...` skips the setup: the world already carries prod's state
     (`../speed/prep.mjs` dumps one after the migrations prod applied since that state), so a pair shares one setup.
   - Compare the arms with `node cmp.mjs a.json b.json`. It also counts how many merchants' plans after the
     kickoff (stops, lines, pause: `plans_after_kick`) differ from the first arm's. A change that must not move
     any choice (0209) shows "837 of 837 identical"; the 20-minute windows then differ only by timing.
   - Run the two arms of a pair side by side, started together: absolute times are ~2–3× prod's, and only the
     ratio within a pair means anything.
   - `node shadow.mjs .arrwork/world.tar.gz 20 <0209 migration>` runs the 0209 arm with every leg priced by
     BOTH the pre-image and the new body in the same state, and counts the differences (0209 shipped at 0).
5. Delete `.arrwork/` when done: it is prod's state. It is never committed.
