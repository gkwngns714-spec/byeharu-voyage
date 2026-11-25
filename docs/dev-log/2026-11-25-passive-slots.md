# 2026-11-25: `passive-slots`: 0509 (dark: `passive_slots_enabled`), proof 211

Stacked on 0498. Server only. Nothing touched production; no production read.

- 1 / 2 / 3 / 4 / 5 / 6 fleets may trade passively at Trading 3 / 5 / 8 / 11 / 14 / 17 (knob `passive_slots_levels`).
- Passive: a Best run, a near round, a repeating fixed run (a stopped or waiting one counts). Not passive: a hand trade, a single run,
  Bring home once, a land haul (decided by default).
- Only the job door asks (E_PASSIVE_SLOTS, with the level). A job already held keeps running, above the level too, and may be changed.
- `world.workers` serves `passive` {level, used, max, next, next_max}; `world.actions` marks a refused option `locked` (and `once` where a
  single run is still taken). Dark: neither key is there.
- Her level is the one last paid for and shown (`house_level_marks`, as `level_perk`); the record is not summed on a 60 s poll.

Not built: the client ("Passive 2 / 3", the locked row); `players.passive_kept`; the old standing routes (their own cap).
**Before the light:** `locked` must be drawn by the client, and a new company's Repeat is refused until Trading 3.
