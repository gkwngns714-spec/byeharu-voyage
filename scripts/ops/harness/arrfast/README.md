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
   - Compare the arms with `node cmp.mjs a.json b.json`.
