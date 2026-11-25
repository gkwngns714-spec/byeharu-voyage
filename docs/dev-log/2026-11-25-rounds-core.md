# 2026-11-25: 0518 `rounds-core` (dark: `rounds_enabled`; proof 222)

`docs/design/rounds-2026-11-25.md`, first slice. `round_works` (data, empty), `round_runs` (one row a fleet), one clock (`round_clock`, the land's
own sum moved there), one settle (`round_settle`). She works the sea of the harbour she puts out from, under the new status `ROUNDS` with her
base kept; `fleet_census` reads it `sea`; `cmd.advance` settles her past her stop. Nothing is wired to a beat.

Measured (PGlite, 100 fleets): Send 0.28 ms, settle midway 0.32 ms, settle past the stop 0.63 ms; a row is about 630 bytes with no log.
Proofs 222 (6), 158, 164, 150 green.

Differences from the design (decided by default): the stores are taken at the settle, so no voyage is written; the nearest city is the base
itself; the log is in the row from the start.
