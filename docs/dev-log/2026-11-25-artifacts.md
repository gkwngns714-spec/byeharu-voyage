# 2026-11-25: 0523 `sea-expedition`, 0524 `artifacts` (dark; proofs 227, 228)

0523: gold 30 a round from the country's capital (kind EXPEDITION, moved; unpaid waits in the run), 2 Reputation, half the provisions from Exploration 8;
called in, the rounds done are paid. 0524: 4 / 1.5 / 0.5 % a round, twice from level 15, kept with the fleet; `cmd.artifact_report` at the capital.

Measured (PGlite): the settle of an expedition with gold, Reputation and artifacts 9 ms. An artifact is kept in `fleet_artifacts` (at most 3 rows a fleet),
not in `player_items`, and takes no hold space: differs from the design (decided by default).
