# 2026-11-14: a coast sails as a coast (0401)

Owner rows 166 and 324. The players' sea switch has been lit since 2026-11-14 15:56 UTC, so this is live play. Nothing here is deployed by this work.

## The defect, proved on the cached world before the fix

The design (docs/SEA_CONDITIONS_AND_REGIONS.md section 2) says "coastal means any hull of the game sails it" and "the crossings carry the whole weight".
Four coasts were drawn inside a crossing. Proved on the courses the world remembers (`public.npc_courses`: 1,061 real sailed lines, sampled as the sail
door samples a course), not on the pair table's straight lines:

| Coast | What was wrong | Evidence before 0401 |
|---|---|---|
| Guinea | The North Atlantic below 10 N was ONE box, The Doldrums (wave 24), from Brazil to Africa. The coast of Sierra Leone and Liberia lay in it. | All 21 remembered courses from Europe and Macaronesia to the Gulf of Guinea cross it; so do Accra to Soyo and Elmina to Luanda. A barca (12) from Lisbon reached 95 harbours at title 3 and 95 at title 11: none in Guinea or Angola, at any title. |
| The Guianas | The same box on the American side. | Belem to Willemstad, Cumana to Belem, Santo Domingo to Belem cross it; Paramaribo lay in it. A barca at Belem reached 5 harbours. |
| The Philippines' Pacific side | The Philippine Sea (wave 50) ran to the shore of Luzon, Samar and Taiwan. | Tainan to Cebu, Manila to Naha, Tongyeong to Manila, Macau to Tidore, Ternate to Guangzhou cross it. |
| The way out of the Seto Inland Sea | The Kuroshio strip off Shikoku and Kyushu, itself a coastal zone, asked 16. | Every remembered course out of Osaka and Sakai crosses it. A barca at Sakai, Japan's capital, reached 0 harbours. |

How the scan was made: (a) every remembered course of 1,700 nm or less between two harbours of one title rank whose seas ask more wave than both its
ends' own seas (27 found); (b) every pair of harbours of one rank within 700 sailed miles whose pair row asks more than both ends (17 found). All of them
are one of the four coasts above, or one of the cases left alone below. Nothing of this class was found on the Caribbean's ocean edge, the Arabian Sea,
the Bay of Bengal or the China seas.

A player's own course is plotted by her client, which the server cannot run; the remembered courses are the nearest real lines there are. The claim "a
player's barca could not reach Guinea" rests on all 21 of them crossing the box, not on a driven session.

## The fix: data, not the rule

`data/sea-zones.json` and migration 0401 (the world guard holds the tables to the file):

| Change | Box | Becomes |
|---|---|---|
| Coastal strip | North Atlantic, south of 10 N, east of 20 W | Gulf of Guinea (title 3, wave 12) |
| Coastal strip | North Atlantic, south of 10 N, west of 45 W | Caribbean Sea (title 4, wave 12) |
| Coastal strip | Philippine Sea, west of 128 E (where the Kuroshio box does not already speak) | Visayan Sea (title 7, wave 12) |
| One ask | The Kuroshio off Shikoku and Kyushu | wave 12 (it was 16); title 7 unchanged |
| **Ocean box** | South Atlantic, north of 30 S, between 30 W and 0 | The Doldrums (title 4, wave 24) |

**The ocean box was not asked for and is needed.** The South Atlantic was cut in two coastal zones at 20 W (Angola, Brazil, each wave 12) with no ocean
between them. That hole did not matter while no hull under 24 could reach Guinea or Angola. With the Guinea coast open, the first run of this fix let a
barca from Lisbon reach 129 harbours at title 11: Angola to Recife on wave 12. The box keeps what the way there asked before (24). The self-assert holds
that no remembered course between the old world's Atlantic shore and the Americas can be sailed on a barca's wave.

Then the derivations, re-run as their own files ran them: the zone raster (0215's statement, copied), the pair table (`public.sea_leg_asks_derive`,
0222), the merchants' remembered seas (`public.npc_course_zones_fill`, 0397). `world.sea_zone_map` and `world.sea_conditions` read those tables, so the
map's shade and the Seas face follow with no client change. The client keeps the zone map for a session with no version key: a player sees the new
shade on her next load; the door and the Send row answer by the new data at once.

One harbour's own sea changes: Paramaribo, The Doldrums to the Caribbean Sea (both title 4). No harbour changes rank.

## What a barca reaches, before and after (local cached world, remembered courses, wave 12)

| From | Title | Before | After |
|---|---|---|---|
| Lisbon | 1 | 82 | 82 |
| Lisbon | 3 | 95 | 104 (Accra, Calabar, Cape Coast, Elmina, Lagos, Luanda, Ouidah, Sao Tome, Soyo) |
| Lisbon | 11 | 95 | 104 (no harbour of the Americas) |
| Belem | 11 | 5 | 24 |
| Osaka, Sakai | 11 | 0 | 80 |
| Manila | 11 | 76 | 80 |

67 remembered courses that asked more than 12 now ask 12 or less. The crossings ask what they asked: Lisbon to Recife 24, Cape Verde to Recife 24,
Lisbon to Havana 30, Manila to Guam 50; Luanda to Recife asks 24 (it asked 12 by the hole).

## Left alone, and why

- Ayutthaya to Malacca crosses the South China Sea (12) between seas asking 10: not an ocean, and a hull of 12 holds it.
- The Sea of Japan (16) on straight lines from Mokpo and Busan to Osaka: the sailed courses go by the Kuroshio strip, now 12.
- Cebu to Ternate and Tidore by the open Philippine Sea east of 128 E on the pair table's straight line: an ocean line; the coastal way is the Molucca Sea.
- `public.npc_coast_courses` (0400) was derived under the old boxes and is not re-derived: its rows are still open water and still coastal.

## The two Trade gaps (asked for "if small": neither is)

- **A Trade row's `sea` tag reads the plain rule** (`public.sea_routes`), so a row in her home or lie-in rank can wear "Shut" while the passage is offered.
  The function takes a title and a wave, not a fleet; giving it the floors means a new argument and hunks in `world.good_board` (re-cut by 0361) and
  wherever else it is called. Small to medium, its own migration.
- **The pair table from sailed courses** (the Suez to Alexandria and Arkhangelsk to Bergen joins): the table is derived from the straight line between
  two roadsteads. A sailed course between two harbours is plotted by the client's pathfinder; the server has none, only the 1,061 remembered courses.
  Re-deriving 62,001 pairs needs either a server-side pathfinder over the sea raster or a generator run offline that ships its courses as data. Large; not
  a data refresh.

## Checks

- 0401 applies on the cached chain at head 0400 with its self-assert (13 s on PGlite; budget 120 s).
- Proofs 96 (new, 5 markers), 91, 92, 93, 94, 95, 8, 45 and 69 green after it.
- `before.sql` on the world before it, `after.sql` and `barca-from-lisbon.sql` before and after: the figures above. The tables equal `data/sea-zones.json` box for box (71) after the file.
- `tsc`, `eslint`, build (the world image is built with 0401 in).
- One run, 86 passed, 0 failed: `seas.lit`, `trade.flow`, `trade.layout`, `map.sendfleet`, `map.autoroute` (without its sailed trip), `rpc.surface`. `news.lint`, `harness.guard`, `duplication`: 23 passed.
- Not run: the world guard itself (CI's disposable chain runs it), the full proof suite.

## Not verified

- Nothing was read on prod. Prod's remembered courses differ from the local world's; `barca-from-lisbon.sql` reads the same figures there, before and after.
- No browser session was driven to Guinea: the door's answer is held by proof 96 on remembered courses.
- The Korean news line is an unchecked translation.

## Decided by default

1. The Guinea strip is the Gulf of Guinea's (rank 3), not Macaronesia's (rank 2): it lies beyond Macaronesia.
2. The Guianas strip is the Caribbean Sea's; the Philippines' strip the Visayan Sea's. No zone is added (64), so no new name is needed on any screen.
3. The Kuroshio strip asks 12, reversing one approved number (16), because at 16 it walled Japan's capital in for the hull every company starts with.
4. The South Atlantic's middle is The Doldrums, not a new zone.
