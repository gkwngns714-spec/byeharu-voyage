# 2026-11-20 - An anchorage is measured to the roadstead (0462)

0459 ("Not changed", `docs/dev-log/2026-11-19-quote-faults.md`) left one fault: for a ship at an anchorage the board measures the first leg
to the harbour's quay, the SAIL goes to its roadstead.

## Cause (reproduced first, local chain at 0461, a scratch run of proof 162's anchorage block)

A barca at anchor 0.4 degrees west of Lisbon's roadstead, a day and a half of casks:

    board: where {kind at_sea, via LIS, miles_left 42}; the LIS row: days 0.12, sail_days 0.12, supplies 0, wages 20
    SAIL LIS: total_nm 18.8 at 14.8323 kn (0.053 voyage-days); bought 0, owed 20

- `world.board_origin` (0348, the only place that measures the way in from an anchor) chose "the nearest harbour" and the lead by the great-circle
  miles to `ports.lat, ports.lon`, the quay (41.8 nm).
- `cmd.do_sail` (0076) ends a course at `public.sea_reaches`' roadstead of the destination (18.8 nm). The Map's Send fleet (`world.trip_cost`) is
  not affected: it measures the course it is given. Every other board function only reads `board_origin`'s `lead_nm` and `lead_at`.

## Fix

One body, one hunk: `world.board_origin` picks the harbour whose ROADSTEAD is nearest her anchor and takes the miles to that roadstead (a join to
`sea_reaches`, every harbour has a row; the migration refuses otherwise). No second copy of the distance. From a harbour or under sail nothing moves:
the self-assert shows a docked board's whole `board_origin` answer the same before and after, on a rolled-back probe.

    0462 self-assert ok: ... at anchor off Lisbon the lead was 41.8 nm (to the quay of LIS) and is 18.8 nm (to the roadstead of LIS); grants as before

Proof 165 sails the scene: board 19 nm in against the SAIL's 18.8 (the board shows whole miles), row 0.05 d against 0.053 d, stores 0 and 0, wages 20 and 20.

## Not changed

A client-drawn course round land may be longer than the straight miles the board reads (as before). The longest leg's `days` and
`supplies.days` / `fits` are still at her speed now.
