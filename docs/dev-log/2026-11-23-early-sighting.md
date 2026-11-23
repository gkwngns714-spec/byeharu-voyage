# 2026-11-23 — 0477 early sighting (roadmap slice 7), dark: `early_sighting_enabled`

Roadmap `docs/design/roadmap-2026-11-23.md` slice 7: "Something can go wrong, a little, early". Slice 8's "survive the sighting"
can read `world.early_sighting().state = 'done'`.

## What it does (lit)
- **Set at departure** (`voyage.depart`'s human arm, one hunk → `public.early_sighting_plan`): a company with no sighting yet, Trading
  mark ≥ `early_sighting_trading_min` (3), title under `raid_company_title_min` (0464's beginner's peace, Master), sailing harbour to
  harbour with cargo on a trip of 240–1800 real seconds. One row in `public.early_sightings` (key = company), DUE at 0.4 of the trip.
- **Sighted** (the pirates' minute job, `public.tick_pirates`, one hunk → `public.early_sighting_step`): the nearest pirate at work, free,
  afloat, rung ≤ 1 (a Raider: the roster's lone fustas and brigantines, each named), with no open bounty, opens THE battle (`battle_open`,
  kind RAID). Her standing order is her opening stance; Run / Pay / her abilities on the battle card as for any raid.
- **Weak**: the pirate's sheet attack × `early_sighting_strength` (0.5), re-run; while the timeline would take any of her hulls under
  `early_sighting_hull_floor` (0.5) of its max, halved again (×3), then 0. Nobody joins (`battle_npc_joins`, one hunk).
- **Closed** by the raids' own close (ransom = `ransom_share` of her cargo at cost from her purse, hands). The next step tells it once:
  `EARLY_SIGHTING` event {pirate, outcome, lost, insured, insurance_paid / insurance_back, guns, guns_outcome, ...}; an insured voyage is
  claimed (`insurance_claim`, cause EARLY_SIGHTING); with no guns, the same sheet re-run with her hulls armed like the pirate's.
- A trip that ends before the sighting: MISSED, set again at her next such departure.

## Client
- Buy & sell sheet: "If attacked" + Fight / Flee / Pay (THE standing order, `cmd.raid_order`), shown only while `world.early_sighting().on`.
  The insurance tick was already there (`plan-insure`, 0213).
- Arrival card: the sighting's lines (`src/live/ArrivalSighting.tsx`); told at sea it waits for her arrival, told after it shows at once.
- History: one line ("Red Shark · Ransom").

## Measured (PGlite)
- Self-assert probe 281 ms (dark nothing; lit DUE at 0.4; Raider opens; told once; set once).
- Proof 180: lit plan 0.05 ms per departure (row done), empty step < 0.01 ms; a fusta at half guns took 7 of a Barca's 403 hull.
- Engine reading (8 seeds, gunless Barca vs half-gun fusta): FIGHT ends RANSOM or PLUNDERED (boarding: 8 hands vs 19), FLEE escapes in
  3 of 8; arming her like the fusta did not change the end (the boarding decides). So the guns line will mostly say the same end: honest.

## Prod (one read, before-0477, 2026-11-23)
- 120 pirates at work, 58 Raiders, 57 free; fight switches lit; ransom_share 0.08, insurance_keep_pct 0.1; knobs {}, table absent; voyage.depart's hunk old 1 / new 0 (the other three hunks' lines and `eligible` were cut off in the builder's
  terminal: re-read before-0477 before deploying).

## Decided by default (the owner may reverse)
- Trigger at departure, sighting in the pirates' minute job (not the beat); "between Trading 3 and Master" = Trading mark ≥ 3 and title
  under `raid_company_title_min`; the nearest Raider anywhere (no reach limit) so it always happens; the loss is the existing raid ransom.
- Insurance pays back a sighting's ransom (ordinary raids' ransoms are still not covered: a gap in the live game, not touched here).
