# 2026-10-18 — 0160: K6, a captain learns in three trades and misses home — `osn-k6-levels`

`docs/SKILLS_AND_CAPTAINS.md` §4.5, §4.7 / §8 row K6 (D11, D13 decided by default; the owner may reverse either).
**Not deployed; dark** (`levels_bite`, `crew_bite` off). Provisional 0160 (S13 holds 0158). Hunks sliced from
**production's live bodies at 0157** (read-only `pg_get_functiondef`, equal to the chain's).

- **captain_xp** (signing → exploration / trading / combat), a player's signings only; seeded from officer_xp
  (all to Exploration; Σ asserted). officer_xp.xp is written and read by nothing after this (K9 drops it).
- **One writer** `captain_xp_credit(fleet, e, t, c, since)`: every seated captain, each track at her cabin's
  rate (100 % for the track's cabin or the Captain's, `cabin_off_focus_pct` elsewhere) × (1 + Leadership %)
  while skills bite. Called by settle's arrival arm (miles → Exploration, pirates → Combat via
  `voyage_xp_tracks`, which `voyage_xp` now sums — every voyage's number unmoved) and by do_buy / do_sell
  (coin ÷ `fame_ducats_per_point` → Trading).
- **Level in force** `captain_level(signing, track)` = her own, capped at the company's (player_progress, read
  only above level 1); `captain_level_mult(signing, track)` replaces the one-number multiplier (dropped).
- **Homesick**: home clock at hire and when the fleet docks in her home region (the voyage's arrival
  instant); lit, terms × (1 − max(0, 20 − care) / 100), care = Surgeon relief (capped) + Hospitality, computed
  from the same raw terms in one CTE (`crew_terms`). Knobs `homesick_after_hours` 72, `homesick_penalty_pct` 20.
  Known edge (dark): read at now(), so a lit late settlement could see one more day of homesickness.
- **Roster**: `world.captains()` and `cmd.captain_traits_set` (+2 entry points; the verb deferred here from K5);
  client `src/live/YourCaptains.tsx` on FLEETS (grade, job, cabin, three level bars with the cap line, the
  homesick line, the traits editor "Use these traits", only in port).
- **Proof** (cached world): seed; dark = pre-image (every fleet × 4 effects, 2,608 reader answers incl. every
  voyage's experience, world.officers); probe (rolled back): 100/50/50 in an Exploration cabin, 100 each in
  the Captain's, nothing from a voyage before she boarded; Trading level 10 of a level-1 company reads 1,
  Exploration 4 of a far better company 4 (× 1.06 lit); homesick 73 h → × 0.80, more with a Surgeon, whole
  once home; the traits verb refuses 6 on an S / an unknown trait / at sea and takes 5; world.captains words.
