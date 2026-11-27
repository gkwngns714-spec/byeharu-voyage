# 2026-11-25: `seas-by-continent`: 0510 (dark: 0215's `sea_conditions_bite`, false), proof 215

Stacked on 0508. Nothing touched production; no switch moved; no production read.

- 42 of 64 seas take the level of their continent (plan 0.1, read from its table by script and checked against the world: the old levels and every wave matched).
  One sea asks MORE: the Arctic Ocean (3, now 8). Every other change asks less.
- One gate: `public.sea_refusal`, untouched. The level is `public.title_level` (the lower of Trading and Exploration).
- **Decided by default:** what a company can reach today stays hers: read as what the OLD levels open to a company founded before 0510 (`public.seas_kept`). It is not
  "every sea", which is what a switched-off gate gives: that reading would make the rungs mean nothing to the 19 companies. Where her fleets lie is `pass-home`'s (0513).
- **Found:** the merchants' rule (0400) groups home waters by the same level column, so moving levels would have moved merchants if `sea_conditions_bite_npc` is lit.
  They now read `title_was`: 60 fleets' legs are identical either way (SC_MERCHANT).
- `voyage.reach_passage` judges a pair by its seas (`public.sea_closed`), not by its highest ask, so the board and the door agree.
- Measured (PGlite): 40,736 pair rows rewritten once, the file 2.4 s; `seas_kept` 0.65 ms a lit departure; the beat reads none of it.
- Files that asked the old levels: proofs 95 (the merchants' groups) and 96 (Japan's home rank read, not the number 7).
