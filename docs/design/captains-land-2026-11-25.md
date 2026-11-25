# Captains and the land: works, crews, HONOR BADGES (2026-11-25)

**DESIGN ONLY. Nothing is built, no production read was made.** Work order item 7: the owner's R4 and section 2's rows `captain-works`,
`land-expedition`, `honor-badge` (`owner-spec-red-2026-11-25.md`). Every figure is a row of data and **decided by default**; the owner may
reverse any. The round, its settle, its log and its stop rule are `rounds-2026-11-25.md`'s (branch `rounds-design`); nothing of them is
designed twice. Read in the code on origin/main (migrations to 0498): 0157 / 0166 (seats), 0160 (captains' levels), 0162 (promotion), 0355 (captain skills),
0352 (Reputation), 0411 (levels), 0455 / 0458 / 0461 (the land). Names marked NEW do not exist.

## 1. What the owner asked (R4), and what is there

| Asked | There today |
|---|---|
| An expedition with captains, provisions and crews | One party a company (`land_parties`, `check (ord = 1)`), with no captain, no crew, no provisions |
| Crew by the COMBAT level; crew carry the provisions | `player_progress.combat`: counted from pirates evaded (5) and driven off (15) alone. **A new company has 0 points, level 1**; with `levels_bite` off the answer is always level 1 |
| Captains have levels by designated work | Three tracks a signing (`captain_xp`: exploration, trading, combat), short curve to 20, never above the company's level (`captain_level`) |
| Start with 2; more by levels, RP, gold | **A new company has none** (`new_house` signs nobody). Any number is hired at an Inn, paid once; nothing limits it |
| Land site or a ship, with perks | `captain_seats`: one row a signing (its primary key), ship only. Perks: `crew_terms` / `crew_pct` |
| HONOR BADGE, from land, for captains | Nothing. Captain skill steps cost Reputation (0355); promotion costs items (0162) |

## 2. This reverses hq-corp A2.3, in one line

Company levels still say **what is open**. A captain's levels now also say **how well the worker does it**, works included. Still one system:
the same signing, seats, writer and reading, widened; no second captain-stat table of another kind.

## 3. Captain levels per work (`captain-works`)

- **`captain_work_xp` (NEW): (signing, track, xp)**, primary key both. The three tracks of `captain_xp` **stay where they are**.
- **One writer.** `captain_xp_credit` (fleet, seats) and a NEW `captain_work_credit(signing, track, amount)` (land); each is the only writer of
  its table. Leadership's % applies to both. A merchant's captain has no row and earns nothing.
- **One reading.** `captain_level(signing, track)` gains an arm: for one of the three, exactly today's body; for a work, the long curve
  (`level_of`, 1 to 100). **No company cap on a work:** the captain does it, and the company's level already opened it.
- **Tracks to begin with:** Mining, Smithing (exist as company levels), Woodcutting, Arms (land raids: `land-2026-11` L3's own skill). Sailing
  work is the three tracks, as now. A new work is a row.
- **Grant:** the same experience the round gives the company's skill, to the captain too. Where there is no company skill, the captain alone.
- **What a level gives** (data, `captain_work_perks` NEW; all frozen in `terms` at Send):
  time a round -0.25 % a level (most 25 %); crew lost a round -0.5 % of itself a level (most 50 %); from level 40 one round in six gives
  provisions, from 80 one in three (R3's "give and take").
- **On a ship** she gives what she gives today (traits, three tracks). Works give nothing at sea, so no fleet changes by this slice.

## 4. Two to start, then more

- **Founding:** `new_house` signs **two C-grade captains of her own country** (then her region), one whose job is Trade or Exploration, one
  Combat, unseated, at wage 0 (`sign_officer`'s rows; no coin moves, so nothing is minted). Deterministic by officer code; fewer than two
  to choose from cannot happen (one character may serve any number of companies: `unique (player, officer)`).
- **Existing companies** with fewer than two are topped up once, in the migration, by the same function. **Captains above two are kept, always.**
- **Places:** `captain_places` (NEW data): place, total level, RP, gold. Places 1 and 2 are free. **Places 3 and up have NULL prices: the owner
  sets them.** The read says "not open yet" for a NULL and no door opens it, so it can be deployed and lit with two.
- `cmd.captain_place()` (NEW) opens the next one: levels read, RP by `reputation_credit` (a new spend kind `captain_place`), gold by `pay_city`
  to her capital; all three or nothing.
- **The Inn:** lit, hiring past her places is refused ("2 of 2 captains"). A company over its places keeps everyone and hires nobody until it
  has room. A dismissal frees one. Dark: the Inn as today. Wages stay once, at signing.

## 5. One seat each: a ship or the land

- `captain_seats` widened: `ship_id` and `seat` nullable, `party_id` (NEW), and a check that exactly one of ship or party is set.
  **The primary key already makes one seat a captain**; a unique index keeps one captain a party.
- `captain_seat_put` stays the one writer. Every ship reader joins on `ship_id` (the two that left-join by signing, the roster reads, are
  re-read in the build), so a party's captain adds nothing to a fleet. `seat_captain_for`'s law stays: only in port, so a captain
  at sea cannot be sent ashore; NEW: a party out must be home before she changes seat.
- **A party is a captain's.** `land_parties.ord` may run 1 to the number of places; a second party needs a captain on it. Party 1 without a
  captain works as today (mining and smithing, exact terms). So nobody loses the dig they have.

## 6. The land expedition (`land-expedition`)

- **Send:** captain, site, work, crew, provisions, stop rule. A round is `rounds` kind `land`; the worker is the party.
- **Crew cap: 10 + 2 a COMBAT level above 1** (10 at level 1, 48 at 20). Checked: the first crew needs no combat. Only sea combat raises the
  level (as today; `combat-rounds` 0521 makes it earnable). The cap is read once, at Send (`player_progress` scans events; never in a settle).
- **Crew** are hired from her home harbour's pool at the Inn's price (`crew_hire_cost`'s arithmetic for a party, coin to that city). Survivors
  stay with the party for the next Send; dismissed, they return to the pool. The dead leave the world. Pay: one day's wage a man a day out,
  owed and taken at Send for the trip, to the home city. No wage means no Send: never a debt.
- **Crew carry the stores.** Each carries 1.0 t. A round eats `0.3 + 0.01 x crew` t, half food and half water, at the quay's price
  (`stores_cost`). So 10 crew last 25 rounds and 48 last 61: **more crew, longer out**, with less each time. Goods found share the load, and
  stores eaten make room. (Figures to be tuned on the first measure.)
- **The stop:** MIN crew (or the player's number), no stores for a round, a full load, or the **12-hour away cap of today**
  (`land_away_hours`), whichever comes first; arithmetic on frozen terms, so watching and not watching give the same. Then she walks to the
  **nearest city** and books there; `repeat` restocks (coin asked first, 0502's rule of thumb: never spend the repair reserve of a fleet) or stays.
- **Works:** mining and woodcutting give goods of the catalogue at cost 0 into Storage, under the land's market guard (0457). Raids
  (dungeons) are Arms bouts by `tick_fight` as `land-2026-11` 6.4 designed (16 frozen fights, as sea rounds): **no new combat.**
- **Yield:** goods; gold from the purse of the country's capital (`capital_pays`, cut to its purse; nothing minted); RP through one kind with the
  day cap; artifacts as `rounds` 8; badges (section 7). Combat's company level is **not** raised by land.
- **Crew lost a round:** mining and woodcutting 0.1 %, raids 1.5 %, less the captain's and Arms levels; never under a tenth of it. Dice by
  `voyage.rng` on the Send, so a press at any instant gives the same dead.
- **Log:** the run's own 20 lines (rounds 5); the captain's level-up is a line.

## 7. HONOR BADGE

- **`honor_kinds`, `honor_balance`, `honor_book` (NEW)**, the shape of Reputation's three (0352): one balance a company, an append-only chain
  (`forbid_mutation`), a once-ever key, a reconcile check at commit. **Its own book, not the coin ledger** (it is not coin) and not Reputation.
- **`honor_credit(player, kind, amount, key, note)` (NEW) is the one writer.** Earn kinds: `land` alone. Spend kinds: `captain_upgrade` alone.
  The sign is checked against the kind, and **a self-assert holds that no other kind and no other caller exists.** Never bought, sold,
  traded, refunded or given to another company; not from sea combat or a sea expedition (R5).
- **Earned** when a party is home and booked: 1 badge a 6 raid rounds, 1 a 24 gathering rounds, x1 to x2 by the site's level. So about 2 to 12
  a full 12 hours. No day cap (the clock and the crew are the cap).
- **Spent on captains** (`captain_upgrades` NEW: signing, upgrade, rank 0 to 5; price 5 r (r + 1): 10, 30, 60, 100, 150, 350 in all):

| Upgrade | A rank gives |
|---|---|
| Quartermaster | +4 % carried by each of her crew |
| Surgeon's hand | -6 % crew lost a round |
| Pathfinder | -3 % time a round |
| Drill | +3 % attack of her party in a raid |

- They act on **her land party alone**. Through `crew_terms` at sea they would move every figure of trade and combat.
- **Reputation keeps the captain skill steps (0355) and promotion keeps its items (0162), untouched.** A dismissed captain's upgrades go with her
  (as her skills do); the press says so.

## 8. The slices, smallest first (numbers move with the prod head)

| # | Slice | What | Rows a minute, lit | What a player sees | Switch |
|---|---|---|---|---|---|
| 0527 | `captain-tracks` | `captain_work_xp`, `captain_work_credit`, the long arm of `captain_level`; the land's captain grant (with no captain: nothing) | 0.1 a party out (one update a Collect, at most one in 10 min) | Captain card: her works beside her three levels | `captain_works_enabled` |
| 0528 | `captain-seats-land` | the widened seat, its check, the party's captain, parties 1 to N | 0 (a press writes 1) | Captain: "Ship" or "Land"; a second party | same |
| 0529 | `captain-places` | two at founding, the top-up, `captain_places` (NULL prices), the Inn's gate, `cmd.captain_place` | 0 | Captains "2 / 2", next place "Not open yet" | `captain_places_enabled` |
| 0530 | `honor-badge` | the three tables, `honor_credit`, the reconcile | 0 (no earner yet) | nothing | `honor_enabled` |
| 0531 | `land-expedition` | crew, stores, the crew cap, kind `land` on 0518's round, mining and woodcutting, badges | one row update a press or stop; 3 to 6 rows a run home (event, badge, RP, Storage, level) | Land: crew, stores, rounds it lasts, the log | `land_expedition_enabled` |
| 0532 | `land-raids` | Arms works on `tick_fight`, 16 frozen fights, gold from the capital | the same | Raids: what a round costs, no odds | `land_raids_enabled` |
| 0533 | `captain-upgrades` | the four upgrades and their door | 0 (a press writes 2) | Captain card: badges, the next rank's price | `honor_enabled` |
| client | `captains-land-client` | one page: captains, seat, works, badges; Land's send sheet | none | | follows the switches |

**Load:** 60 companies with two parties out, two runs a day: 240 runs x 6 rows = **1 row a minute at most**, no cron, no beat step (0519's tick
settles a stopped run). `captain_work_xp` is bounded (captains x works); `honor_book` grows with runs, about 240 rows a day: `-- retention:`
append-only, as `reputation_book`. `captain_upgrades` is bounded.

**Order:** 0518 and 0519 (rounds) before 0531; 0527 to 0530 wait for nothing. 0509 `restart-company`'s list of a closed company's rows must gain the
new tables (`captain_work_xp` and `captain_upgrades` go with the signing by cascade; balance deleted; `honor_book` stays, append-only).

## 9. Self-assert rules (each migration)

1. Hunks once and reversing; no other function moved; grants, volatility and definer unmoved; knobs: only its own, false.
2. **Dark parity, by value:** `captain_level` for the three tracks, `crew_pct` for probe fleets, `land_terms` / `land_progress` at fixed
   instants, the Inn's answer: equal before and after.
3. Seats: a signing in two seats is refused **by the table**; a ship reader gives the same with a party's captain present.
4. The probe is one company of its own, rolled back; **it counts only its own rows**, takes no price, purse or dice from the world
   (`world_secret` pinned; amounts set against the read's own answer) and passes with every switch lit and every switch dark.
5. Settle: booked in one go = booked in ten, at any instant (goods, dead, badges, experience).
6. Coin: crew, stores, wages and places are `pay_city` rows; gold is `capital_pays` rows; the sum of the world's coin is the same before and
   after the probe. Badges: balance = the newest book row.
7. The top-up at 0529 counts nothing on live: it asserts only that its own probe company, with none and with three, ends with two and three.

## 10. Measured before any light

1. Rounds and badges in 12 hours for levels 1, 20, 50 and crews 10, 30, 48; coin out against goods and gold in (a new company must not go
   bankrupt on its first four hours; target: gathering earns 30 to 60 % of a near trading run).
2. Crew pools: hires a day against what home harbours refill.
3. `captain_level` and the captain roster read: ms before and after (no new events scan).
4. The capitals' purses after three simulated days; the gate 30 minutes after each light.

## 11. Decided by default

- Company levels open, captains' levels improve. No company cap on a work track. Woodcutting and Arms get company levels only when their
  own land slices arrive.
- Two free captains, C grade, own country; nobody is ever dismissed by the rule.
- Promotion and skill prices do not move. Badges act on land alone.
- Land crew paid for the trip at Send; the party's first crew of 10 needs Combat 1.

## 12. Not known

- Prod's `levels_bite`, how many captains companies hold, how many companies have fewer than two (one read by the lead before 0529).
- Whether a level-1 party wins a raid at the first site (needs 0532's build).
- The stores and load figures on real prices.

## 13. Questions for the owner (at most three)

1. **What do captain 3, 4 and more cost** (total level, RP, gold)? Default: not open until you set them.
2. **May you hire at the Inn when all your places are full by swapping (dismiss first), or never above the places?** Default: dismiss first;
   captains you already have stay.
3. **Should land raids raise the company's COMBAT level (and so the crew cap), or only sea combat?** Default: only sea combat.
