# 2026-11-25: 0519 `rounds-log` (dark: `rounds_enabled`; proof 223)

`docs/design/rounds-2026-11-25.md`, second slice: `cmd.round_send`, `cmd.round_home`, `world.rounds`, the job kind `round` (repeat or home: sail to the
base, hire, provision, repair, send; wait with the reason when short), and `round_settle_due` at the head of the jobs' tick (not the beat).

Measured (PGlite, proof 223): the jobs' tick 0.2 ms with no fleet out, 0.3 ms with 100 out, 14 ms when it brings 20 in (a tick brings in 20 at most).
A `tick_fight` x 16 at Send (the later combat slice): 20 to 150 ms by fleet size, so 8 fights are planned there, not 16.

Rows, lit, fleets on runs of 4 hours, 6 fleets a company: about 0.25 a minute for 1 company, 25 for 100. Dark: none.

Found and fixed in the proof: a hull's most hands is rolled (0276), so a set number of hands must come from the hull.
