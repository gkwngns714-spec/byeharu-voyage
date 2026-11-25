# 2026-11-25: 0520 `ammo`, 0521 `combat-rounds` (dark; proofs 224, 225)

- 0520: a round spends 0.2 of Gunpowder and of Shot and Ball for every 100 points of attack (about 175 coin a 100 attack at base values). The design's 20
  would have been 17,000 coin a round: corrected.
- 0521: 8 `tick_fight`s (4 over 3 hulls), kept for a fleet while nothing of her has changed by a tenth (`round_fights_kept`), so a job's Send in the tick
  plays none.

Measured (PGlite, proof 225, the most dangerous sea there can be, strength 40): Send 41 ms (one xebec), 139 ms (eight), 78 ms (one San Martin), 35 ms
(eight); with the fights kept 2 to 8 ms; a tick that sends a combat job 7 ms.
The largest EVEN fight (eight San Martin, strength 795): 98 ms one fight, 715 ms eight. No sea reaches it: danger x 40 is at most 40.

A round against an even sea costs 4 to 13 % of the hull and ends beaten off at 15 %: near an even strength a run lasts 3 to 8 rounds before 60 %.
