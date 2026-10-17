# 2026-10-17 — 0150 (provisional number): K0, a merchant pays nothing for skills she cannot use — `osn-k0-skills-cheap`

`docs/SKILLS_AND_CAPTAINS.md` §7.1 / §8 row K0, before anything is lit. **Not deployed**; `skills_bite`
stays false. The number is provisional (0141–0148 are held by in-flight slices): renumber to head + 1 at
merge, and deploy strictly in order.
- **Why lit was 2×**: every hot read of a merchant hull ran `world.skill_bonuses`' whole query (plus the
  SRF call) for a house whose four company skills cannot touch a ship. And `world.ship_view` ran
  `world.ship_stats` **six times** a ship, not once: the planner pulls up `cross join lateral (select
  world.ship_stats(s.id) as st) x` and evaluates it per `x.st` reference (measured: `offset 0` alone takes
  the merchant ship_view from 1,025 to 727 ms dark on the cached world).
- **0150**: `public.house_skill_scopes(player, ship default null)` — THE reading of which non-company
  scopes a house's held skills reach (skill_bonuses' own held set; PL/pgSQL, invoker, no SET). Early exits,
  each after the live switch test (dark runs what it ran before): `world.skill_bonuses`, `world.ship_stats`
  (lit branch only with a SHIP skill), `world.ship_budget`, `world.ship_view` (+ `offset 0`),
  `public.fleet_officer_bonus` (Command term); `world.skill_pct` becomes PL/pgSQL.
- **Proof**: old tree (10 functions, pg_temp) vs new, one statement each, dark and lit (rolled back):
  908 hulls, 850 fleets, 834 houses — 0 differ, md5 equal; scopes = the scopes derived through
  `skill_level`; 4 throw-away houses (Medium Hulls III, Deck Management II, Command II, a finished and an
  unfinished queue entry, company-only) — old = new, and every real bonus still applies.
- **Timing (PGlite, cached world, 892 merchant hulls, random_page_cost 1.1, fastest of 3 interleaved
  passes, notice only)**, two runs on a machine loaded by other agents: speed + cargo space lit 519 → 332 and
  525 → 344 ms (new dark 278 / 252); ship_stats lit 136 → 82 / 137 → 83 (dark 59 / 60); ship_view lit 1,989 →
  912 / 1,966 → 906 ms (dark, now one ship_stats call, 777 / 732). Against the bound lit ≤ new dark × 1.15 +
  50 ms: ship_stats within in both; speed + cargo space and ship_view within in the first run and ~1.5 %
  over in the second — AT the edge, because the new dark is itself 30 % faster. Lit-new is below today's
  DARK ship_view. Re-measure on prod before throwing the switch (§7.6).
