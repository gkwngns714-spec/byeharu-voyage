# 2026-11-25: captains and the land: 0527, 0528 (dark: `captain_works_enabled`), proof 235

Branch `captain-works`, on `seas-relit` with `management-level` and `premium-goods` merged (that stack holds the FIRST 0502; `no-ruinous-run`
58919d8e is the fixed one). The design: `docs/design/captains-land-2026-11-25.md` (branch `captains-design`). Nothing touched production.

## 0527 `captain-tracks`
- `captain_works` (Mining, Smithing, Woodcutting, Arms), `captain_work_xp`, one writer `captain_work_credit`, one reading `captain_work_level`
  (the long curve, no company cap). `captain_level` gains one arm; the three sea tracks are the body as it was.
- `captain_work_perk`: 0.25 % of a round's time a level (most 25), 0.5 % of the crew lost (most 50), one round in six gives provisions from 40,
  one in three from 80. `world.captains` serves `works` while lit.

## 0528 `a-captain-goes-ashore`
- A seat is a cabin or a land party, by the table's own check; one seat a captain is its primary key, as before.
- `cmd.captain_land(code, party)`; `land_terms` shortens a turn by her level (frozen at Send, her name on the terms); a Collect's experience is
  hers too. A party that is out keeps its captain.
- **Not as the design says:** `ord` may now be more than 1 in the table, but **no door makes a second party**: today's land doors know party 1
  alone, so a second one would be a party nobody can send. 0531 opens it with its own doors.

## Restart (0509)
Nothing to add for these two: it deletes `land_parties`, then `player_officers`; seats and works go with them by cascade (CW_CLOSE plays that order).

## Checked
Self-asserts 0.1 s each; proof 235 7/7; 158, 164, 44, 58 again; perturb 18 worlds (17 pass, 1 known: a founding Lisbon cannot pay). tsc, eslint,
`db.budget`, `news.lint`. Rows: 1 a press; 1 more a Collect at most once in 10 minutes a party; 0 a minute otherwise.

## Not verified
`rpc.surface` (a browser image), `vite build`, the client (after). Prod: nothing read; `scripts/ops/harness/captain-works/state.sql` is the lead's.
Experience due from a trip before she joined (at most 10 minutes' worth) goes to whoever leads the party when it is booked.

# 0529, 0530 (dark: `captain_places_enabled`, `honor_enabled`), proof 236

The stack now holds the fixed 0502 (`no-ruinous-run` 58919d8e merged).

## 0529 `captain-places`
- Two captains at a founding (lit), and by the one light step `public.captain_places_light()` for every player's company: two kinds (combat and
  not), the lowest grade, her country first; no wage, no coin. Captains above the places are kept.
- `captain_places`: 3 to 8 are NULL (the owner prices them); `cmd.captain_place` opens the next for total level, Reputation and coin (ledger
  kind SLOT, to her home city), all or nothing. The Inn's door refuses a full company; the HQ board offers it no hire.
- **`cmd.captain_dismiss` is new: no door dismissed a captain before**, and "dismiss first" needed one.
- `sign_officer`'s rows moved whole to `captain_sign_rows`; a merchant's signing is untouched and asks no place.
- `total level` here is the sum of the levels the Skills list shows. 0509's `hq_steps` names a total level too and has no reader yet: one
  function should serve both when it gets one.

## 0530 `honor-badges`
Three tables in Reputation's shape, one writer, one earn kind (`land`) and one spend kind (`captain_upgrade`) held by the table's own check;
the self-assert holds that no other body names them. Nothing earns until 0531.

## Restart (0509): still nothing to add
`captain_places_open`, `honor_balance` and `honor_book` stay with the retired row, as `reputation_balance` and its book do; the new company
starts at two places and no badges.

## Checked
Self-asserts about 0.1 s each; proof 236 6/6; 235, 44, 58, 176 again; perturb 18 worlds (16 pass; 2 known: a city that cannot pay a founding).
tsc, eslint, `db.budget`. **0508's own self-assert failed once more while the chain was rebuilt (line 451): it is still flaky in this stack.**

## Not verified
As above. E_CAPTAIN_ROOM and E_NOT_ENOUGH_HONOR have no words in the client's dictionary yet (the client slice).

# 0532, 0533 (dark: `land_raids_enabled`, `honor_enabled`), proof 237

## 0532 `land-raids`: the fight, and only the fight
- `land_foes` (7, data), a party as one hull, the crew cap (10 + 2 a COMBAT level above 1), `land_raid_terms` (16 `tick_fight`s frozen at Send),
  `land_raid_round` (one of the 16, whole hands, pure in terms, party and round), `land_raid_card` (the mean hands a round; no chance, no result).
- **The Send, stores, log, gold from the capital and badges are 0531's**: the rounds' tables are keyed by fleet and know `combat` and `sea` alone
  (0518), so a party cannot be sent on them yet. 0532 is what 0531's Send and settle call. No door, no body cut.
- Foe figures tuned on the local fight knobs (20 fights each, a captain of the foe's level): 10 hands win Wolves 0.75 and Boar 0.85, lose to
  Brigands (0.10); 20 hands win Brigands and Bear (1.00), Deserters 0.60, Great beast 0.10; 48 hands win all. **Production's fight knobs were not
  read**; they decide it. A defeat is the fight's own break-off (15 % of the party's strength). `land_raid_crew_share` 0.15.
- A Send's 16 fights: 145 ms here. COMBAT is not raised by a raid.

## 0533 `captain-upgrades`
Four upgrades, five ranks, 350 badges each (10, 30, 60, 100, 150); `cmd.captain_upgrade`; they change `captain_work_perk` alone, which no body at sea
reads (asserted). Surgeon's hand and the level together can take 80 % of the crew lost (50 + 30), Pathfinder and the level 40 % of the time (25 + 15).

## Restart (0509): nothing to add for 0532 and 0533
`captain_upgrades` goes with the signing; `land_foes` is data.

## Checked
Self-asserts 0.1 s; proof 237 6/6, 236 6/6, 235 7/7; perturb 18 worlds over all six files (16 pass, 2 known). tsc, eslint.

## Not verified
The six files over 0518 and 0519 (`rounds-log`): they cut other bodies but for the registry, on other lines; not run together. `rpc.surface`, `vite build`.

# 0534 `land-expedition` (dark: `land_expedition_enabled`), proof 238. The design's 0531, numbered after the two it stands on

- **The widening of 0518**, in 0534's own tables section, and no body of 0518 to 0524 is cut for it: `round_runs.fleet_id` and `sea_id` nullable; `party_id`
  (unique, cascade); `worker` generated as coalesce(fleet_id, party_id), the primary key; `round_runs_one_a_fleet unique (fleet_id)`, so every
  `on conflict (fleet_id)` still works; check: exactly one of the two, and a fleet's run has its sea. `round_works.kind` may be `land`; the two land
  works wait for `land_works_are_no_fleets` (never true), so no fleet door or list shows them. One hunk on `round_settle_due` (its return).
- A captain, a target (a mining job or a foe), crew (10 + 2 a COMBAT level), provisions, a stop (MIN, rounds), home or repeat. One party a captain
  (number 2 and up); party 1 stays the dig's with its exact terms.
- Coin: hands, provisions and a day's pay to her home city; a raid's gold from the capital (LX_COIN: three purses to the coin).
- Called home: no new round; the rounds passed are kept; they march back.
- **Woodcutting is not built**: no land job gathers wood. **Not tuned**: 20 hands gather 10 Sea Coal (5 rounds, stopped by the load); 30 hands raid wolves 50
  rounds. Gathering's yield a round does not grow with the crew (the crew is the stores and the load).
- Restart (0509): nothing to add; its delete of `land_parties` takes the runs (LX_CLOSE).
