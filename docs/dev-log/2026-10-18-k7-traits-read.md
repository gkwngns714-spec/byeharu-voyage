# 2026-10-18 — 0161: K7, a captain reads the weather, keeps the casks and knows her goods — `osn-k7-traits` (stacked on K6)

`docs/SKILLS_AND_CAPTAINS.md` §4.2, §4.4, §4.9 / §8 row K7 (D14, D15 by default). **Dark** (`crew_bite` off);
provisional 0161 (S13 0158, K6 0160). Hunks sliced from the bodies live after K6 over production's 0157.

- **Pilot** → `voyage.storm_hull_lost` × (1 − the fleet's `storm`), read **at the voyage's departure**.
- **Provisioner** → `voyage.endurance_days` × (1 + `supplies`).
- **Goods traders** → `world.spread_effective` adds `category_spread` for THIS good: `crew_pct` counts only the
  traders whose `traits.goods` is the good's category, capped per category at 20.
- **Language** → `public.haggle_odds` gains `p_fleet` (drop + create): + `language_haggle_points` (5) when a captain
  seated in the fleet speaks the port's language (`public.crew_speaker`, the one answer; lit only). `cmd.haggle`
  and `world.haggle_state` pass the fleet; the haggle row prints the server's `language_line`.
- **The instant**: `crew_terms` / `crew_pct` gain `p_at` (default now(); drop + create, ACLs kept) — the K6 edge
  (homesickness judged at now()) is closed for the storm arm.
- **Proof**: dark = pre-image over 4,910 answers (endurance, every voyage's storm loss at 3 magnitudes, spreads,
  every player's odds, the live effects); probe (lit, rolled back): Gem trader narrows a gem's spread not a grain's,
  Provisioner lengthens supplies, a Spanish-only captain adds nothing at Lisbon and a Portuguese speaker 5 points,
  a Pilot shrinks a storm read at the departure and it does not move when homesickness turns on afterwards.
