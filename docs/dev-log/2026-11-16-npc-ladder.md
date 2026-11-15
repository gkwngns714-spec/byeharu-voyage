# 2026-11-16 - A fleet is as strong as her rank (0451; the server half of "every pirate ship's graphic is same")

The owner: "every pirate ship's graphic is same. the one with stronger ships, multiple fleets should have different graphics. this goes to
every kinds of ship too".

The pictures are #748 (client): a fleet is drawn from her served `hulls`, each class by its size (1 sloop, 2 brig, 3-4 frigate, 5-6
flagship), with a mark for her count. But the world gave every navy ship the same hull and every cargo ship the same hull, so they still
looked alike. 0451 makes the fleets themselves differ, so the pictures and the fights differ.

## What was there (prod 2026-11-15 17:26 UTC, head 0448; three reads, gate green: 722 MB, 0 waiting on the disk)

| kind | fleets | hulls | what they were |
|---|---|---|---|
| Navy | 48 | 48 | every one ONE `galion` (size 4), in ten navies of 2 to 6 ships |
| Cargo | 112 in service (265 retired) | 112 | every one ONE `navire` (size 3) |
| Pirate | 121 (1 laid up) | 193 | 36 `brigantin`, 18 `fusta` (size 1); 31 `xebec` (13 of them 0339's "Pirate ship N"), 18 pairs of `xebec` (size 2); 14 `galeoncete` + 3 `xebec`, 4 `korsan` + 3 `xebec` |

So the brief's "every pirate ship is one xebec" is true only of 0339's 13 ships; 0414's roster already differs. But no fleet anywhere had a
hull above size 4, so nothing drew as a flagship, and the navy and the cargo ships were one picture each. Every hull is level 5 (0372).

The pirates' last 24 hours by hull (public.fleet_book): the 36 brigantins won 24 raids and lost 138, wrecked 58 times; the 31 lone xebecs won
96, lost 51, wrecked 65 times; the 18 squadrons won 80, lost 0, wrecked 0 times. 0339's 13 ships fight 29 of the last 100 raids (they
are homed on the old trade lanes). Refits cost the pirate purses about 4.3 M that day; the hoard is 895 M (floor 100 M).

**The before-check** (`scripts/ops/harness/npc-ladder/dist.sql`, prod 17:56 UTC, head 0450, gate green, beat 119 ms): applied false; each of
the three hunks once in the live bodies; the 8 roster squadrons 0451 makes Dread are there; through `public.fleet_census`: cargo 110
fleets (`navire*1`: 82 at sea, 28 in port), navy 48 (`galion*1`: 40 / 8), pirates 121 fleets and 193 ships in six shapes. What the
pictures draw: cargo 110 frigates, navy 48 frigates, pirates 54 sloops, 53 brigs (31 alone, 18 pairs, 4 fours), 14 frigates with three
brigs. No flagship anywhere.

## The ladder (decided by default; all of it is data the owner can change)

`public.npc_ladder` (a kind's rungs) and `public.npc_ladder_hulls` (the hulls of a rung for a ship line). Only classes that exist.

| kind | rung | hulls | the picture |
|---|---|---|---|
| Pirate | 1 Raider | 1 brigantin (the roster's fusta too) | sloop |
| | 2 Corsair | 1 xebec | brig |
| | 3 Consorts | 2 xebec | brig, 2 |
| | 4 Squadron | galeoncete + 3 xebec (Flores: korsan + 3 xebec) | frigate, 4 |
| | 5 Dread | kalyon + 3 xebec | flagship, 4 |
| Navy | 1 Cutters | 2 hulls of size 1 | sloop, 2 |
| | 2 Brigs | 2 hulls of size 2 | brig, 2 |
| | 3 Frigate | 1 hull of size 4 (the galion, or her country's) | frigate |
| | 4 Ship of the line | 1 hull of size 5-6 + 1 frigate | flagship, 2 |
| Cargo | 1 Small | 1 trader of size 2 | brig |
| | 2 Medium | 1 trader of size 3 (the navire, or her country's) | frigate |
| | 3 Large | 1 trader of size 5-6 (an Indiaman) | flagship |

A country's navy and cargo ships are its OWN line's hulls (`public.ship_lines`): the cheapest hull of the line at the rung's size and role
that has guns and is not a famous ship; where the line has none, the `*` hull (brigantin, fregcourse, galion, grandnav; caravelao, navire,
indiaman). Examples: Spain's navy is galeón real + galeón / galeón / 2 zabra / 2 brigantin; the Ottomans' kalyon + baştarda / baştarda /
2 xebec / 2 firkate; Joseon's panokseon / 2 byeongseon; Portugal's cargo ships nau da carreira / nau / caravelão. The Mughal crown, which
no line names, builds the Indian Ocean line's small hulls and the `*` big ones (decided by default).

## How strength is assigned (`public.npc_rung_rule`, pure; `public.npc_rung_of` reads a fleet into it)

Nothing that moves by the minute, so no fleet flips back and forth.

- **Navy: by station.** Ord 1 serves rank 1, the capital. Of a navy of S ships: the capital's is the Ship of the line when S >= 4 (a
  small navy keeps a Frigate there); then by quarters: the first half Frigates, the third quarter Brigs, the last Cutters. S = 6: Line,
  Frigate, Frigate, Brigs, Brigs, Cutters. S = 2: Frigate, Brigs. A rich country keeps more ships (0331's root of its purse), so only it has
  a Ship of the line. On prod's ten navies: 8 Ships of the line, 17 Frigates, 15 Brigs, 8 Cutters (48 fleets, 79 hulls).
- **Cargo: by her country's share and her seniority.** The first quarter of the share (by ord) Large, to 65 % Medium, the rest Small. A
  share of 16: 4 / 7 / 5. On the hundred: 30 Large, 41 Medium, 29 Small.
- **Pirates: a roster fleet is her roster row** (`public.pirate_roster_hulls`, 0414's authority). Eight of the eighteen squadrons (the
  first of every three in each hub: Pitcairn 3, Tristan 2, Flores 2, Diego Garcia 1) are now led by a `kalyon`: the Dread, 8 of 121
  fleets (6.6 %). Each hub's ship count, the owner's order of 0414, is unmoved (only the lead ship changes). 0339's 13 ships: a pattern of
  six by ord (Corsair, Raider, Corsair, Raider, Consorts, Corsair): 7 xebec, 4 brigantin, 2 pairs.
- Not done, and why: a rank earned by raids won or loot (it would promote the fleets that already never lose, and a rung that follows a
  running total re-rates fleets every day); a cargo ship's rank by her home's purse (a purse moves by the hour; a ship is sent to a new
  home often). Both can be laid over the same rule function later.

## How the living world is changed (`public.npc_ladder_refit`, the one way)

Only in a harbour (DOCKED, or a pirate wreck being reborn). Never at sea, never on a side of a battle being fought, never busy, never a navy
ship called to a fight or escorting, never with goods in a hold (27 of 84 single pirates carried goods at the read; none of the 18
squadrons did; a wreck's hold is lost, so a reborn fleet is always taken). Her old hulls go and `public.commission_ship` lays the new;
the lead ship keeps the fleet's name, the others are numbered as 0414 numbers them. Her hands go over to the new hulls by their complement,
the rest back on the quay; none is made, so a bigger fleet sails short until the quays man her (as every NPC does). Her hulls keep the share
of health she had. Her level is written at once. **No gold moves** (0328's law for a cargo ship's refit).

Who calls it:
- `public.npc_ladder_pass`, from `public.tick_pirates` (the minute job that is there; no new job): docked navy and pirate fleets;
- `public.pirate_reborn`: a wreck is reborn as her rung;
- `public.cargo_hull`: a cargo ship's own refit moment (idle at home, no load).

A new fleet is laid down by the door that always laid it (and pays what it paid) and is re-rated in her first minute in harbour; a new
ROSTER fleet is built as her rung at once (the roster's rows are read at the build).

**Pace:** at most `npc_ladder_per_minute` (2) of a kind a minute, so at most 6 a minute in the world. About 155 fleets change (45 navy, 8
Dread and 6 of 0339's, about 96 cargo ships): one to three hours, the cargo ships as each comes home and idles. The weak pirates
change at their next wreck or their next two minutes in a harbour with an empty hold.

## Balance

By the raider figure (`voyage.pirate_strength`'s: attack / 10 + hands x 0.02 + tier x 3 a hull), prod's fleets under the rule:

| kind | before | after | |
|---|---|---|---|
| Navy | 1,901 | 1,894 | -0.4 %; the same 48 fleets, 48 -> 79 hulls |
| Pirate | 2,345 | 2,585 | +10 %, all of it the eight Dread fleets; 0339's ships 165 -> 161 |
| Cargo | 2,320 | 2,149 | -7 % (of the last 100 raids none was on a cargo ship) |

**The 100 newest frozen raids, re-fought** (`scripts/ops/harness/npc-ladder/replay.mjs` on `sheets.sql`'s read; the same seeds and dice in
both arms; the engine is 0450's, on sheets frozen before it, so without its per-ship cards in either arm):

| | plundered | ransom | driven off | evaded |
|---|---|---|---|---|
| as prod fought them | 23 | 4 | 23 | 50 |
| old hulls, re-fought here | 25 | 8 | 23 | 44 |
| new hulls (0451) | 24 | 8 | 27 | 41 |

The pirates won 33 with the old hulls and 32 with the new. Nine outcomes moved, all on changed fleets: 8 raids by 0339's ships that become
Raiders (4 plundered -> 0 plundered, 2 ransoms, 3 driven off); 3 by the two that become Consorts (1 ransom -> 2 plundered); 6 by Dread
fleets (4 plundered + 1 ransom -> 5 plundered). 65 raids by unchanged roster fleets and 18 by 0339's Corsairs are the same fight.
A new hull is fought at her full complement; a Dread sails short of hands at first (her lead needs 250, a galeoncete's 67 go over).

**Pay and upkeep.** The pay is by the FLEET (`navy_upkeep_day` / 24 an hour, `public.navy_pay`, `public.pirate_pay_hour`), not by the hull:
0451 moves none of it. 121 pirate fleets x 12,000 = 1.45 M a real day, as before; the navy's the same.

**Refits** (25 % of her hulls' build cost, when she is a wreck):

| | before | after |
|---|---|---|
| 0339's ship | 40,000 | Raider 20,000 / Corsair 40,000 / Consorts 80,000 |
| a squadron made Dread | 354,000 (Flores 220,000) | 595,000; none of the 18 squadrons was wrecked in the day read |
| a navy ship, the mean of the 48 | 289,000 | 286,000 (Cutters 40,000 ... a Ship of the line with her frigate 750,000 to 1,260,000) |
| a cargo ship, the mean of the 100 | 157,500 | 191,000 (Small 35,000, Medium 157,500, Large 420,000) |

A Dread's house, when its purse is empty, is given half her hulls' cost by the hoard (0415): 1,190,000, was 708,000; eight houses.
The hoard (895 M) pays a pirate's hour and a wreck's refit down to its 100 M floor whatever the day's room says (0429), so no pirate is
laid up by this. A navy capital too poor for a wreck's refit waits as it did (Joseon's purse was 3,034 at the read; its two ships become
a Frigate and Brigs, cheaper to refit than two galions).

## Budget

No job, no cron. A re-rating writes about 20 rows (her old hulls and their level rows out, the new in, her fleet, her rung row, the kind's
clock row, at most one quay): at most 6 a minute, **under 120 rows a minute** while the world is re-rated (one to three hours), then only a
new, woken or reborn fleet. In the first quarter of an hour the pass also writes the rung row of each fleet that is already her rung (most
pirates), once a fleet, at most 40 a minute: **under 160 rows a minute** then. The pass reads the docked navy and pirate fleets each minute
(about 30 rows by key) and writes nothing when none is due. Four small tables, bounded by construction (12, ~103, ~550 and 3 rows). 31 more navy hulls and 0 more fleets: no more voyages.

## Measured here (PGlite, this machine)

0451 on main's chain (0450): 120-190 ms, self-assert ok (12 rungs, 103 hull rows, 8 Dread, 3 hunks, 10 functions; the probe: a pirate, the
pace, a navy ship, a cargo ship lit and dark; no gold moved). Proof 154: 10/10 in 0.3 s. The three hunks each occur once in prod's live
bodies (read 17:25 UTC; `dist.sql` checks it again before the deploy).

## Decided by default

- The switch `npc_ladder_enabled` ships TRUE (the owner asked for the fleets to differ). False is the quick stop; the cargo ships then turn
  back to the navire by themselves.
- A re-rating is free; a new hull is still paid for by the door that lays it, at the old class's price (builds are rare: the navies and
  the pirates are at their numbers).
- National lines for the navy and the cargo ships, so a hull's name fits her flag.
- The Codex's `crown` mark (0332) still names the three standard hulls (galion, navire, queen's pinnace). Not moved here.
- No word on a card for the rank ("Dread", "Ship of the line"): the picture says it. The names are in `public.npc_ladder` (EN, KO) for
  the day a card wants them.

## Proofs amended (they drive the bodies as they were; each says so in its scene)

- Proof 36 (armed cargo): `npc_ladder_enabled` false in its scene. It proves 0328's own refit (one class for every cargo ship), which is
  `public.cargo_hull`'s body with the ladder dark. Lit: proof 154.
- Proof 114 (a pirate ship trades): the first squadron's roster row is put back to a galeoncete in its scene; its figures (a gift of
  708,000) are that squadron's.
- `tests/battleWorld.fixture.ts`: `npc_ladder_enabled` false; its specs' figures are an armed navire's and a galion's.
- Not touched, and red on main without 0451: proof 152 (0450) raids from a quay, which 0445 stopped; it needs proof 136's own line
  (`pirate_strike_from_port` true, `pirate_port_minutes` 720). With that line it passes with 0451 too (10/10, tried here, not committed).

## After the deploy (30 minutes; it alters live play)

`scripts/ops/harness/npc-ladder/dist.sql` before and after, `after.sql` at +10 and +30 minutes: `rated_10m` at most 20 a kind, `due` falling,
`unpaid` and `laid_up` as before, the hoard's spend in line, the beat under 1 s. For the fight: `scripts/ops/harness/raid/after-check.sh
<start> <end>`. Rollback: `scripts/ops/harness/npc-ladder/rollback-0451.sql` (three depths; the first is one knob).
