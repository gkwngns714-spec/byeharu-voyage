# Armada: two to six fleets as one

Owner row 323 (2026-11-13), said right after asking for more trade, cargo and combat ships and for fights to
show on the map as a red ring that grows with the fleets in it:

> "with more than one fleet, max 6 fleet - an armada."

**The lead's reading, decided by default (the owner may reverse it):** an armada is a named group of two to
six of ONE company's fleets that act as one. They gather in one port, sail together on one order at the
slowest fleet's speed and arrive together, and when a fight comes all of them stand on the same side. It
changes nothing about how many ships a fleet holds, and no player ever fights a player.

Every rule below that is mine and not the owner's is listed again in section 14, each as a default.

Built: sections 1 to 11 for sailing and raids, migration 0367, **lit**; and the battle she starts (section 7),
migration 0379, behind the owner's switch `attack_enabled` (off: nothing changes; on: a lone fleet fights as she did).

---

## 1. What an armada is

- A name (3 to 24 letters, her company's own) and 2 to `armada_fleet_max` (6) fleets of one company.
- One of her fleets is the **flagship fleet**: the first one picked when she is formed. Her course is
  plotted from where that fleet lies, her standing order when raiders close (Fight, Flee, Pay) is that
  fleet's, and on the map the armada's mark stands where that fleet is.
- A fleet is in one armada at most. A company may keep several armadas.
- Each fleet stays a fleet: her own ships, hold, casks, crew, captains, wages and insurance. The armada
  adds nothing to a ship and takes nothing from one.

## 2. Forming and disbanding

**Forming** (`cmd.armada_form(fleets, name)`) is paper at the quay: no ship, cargo or gold moves. Every
fleet named must be:

| rule | why | refusal |
|---|---|---|
| hers | | `E_NO_SUCH_FLEET` |
| 2 to 6 of them | the owner's number | `E_ARMADA_SIZE` |
| in no armada already | one armada a fleet | `E_IN_ARMADA` |
| **docked** (not at sea, not at anchor) | NO-HOME law: fleets gather where they physically are | `E_NOT_DOCKED` |
| in the **same port** as the first | the same | `E_NOT_SAME_PORT` |
| holding at least one ship | an empty fleet cannot sail | `E_FLEET_EMPTY` |
| with no order waiting and not in a battle | her queue would run under the armada | `E_FLEET_BUSY` |
| on no trade route | a route would send her alone | `E_ARMADA_ROUTE` |
| named in 3 to 24 letters, a name she does not already use | | `E_BAD_NAME`, `E_NAME_TAKEN` |

A fleet under way cannot join: she joins in port. Same port, not same anchorage: an anchorage is a point of
open sea and nothing is formed at sea.

**Disbanding** (`cmd.armada_disband`) works anywhere, at any time, and with the switch off. Fleets at sea
sail on to the port they were bound for and still arrive together (the shared schedule is kept on the
voyages, not on the armada). `E_NO_SUCH_ARMADA` if it is not hers.

**Changing who is in her:** disband and form again. Both are free. A door to add or drop one fleet is
left out (section 12).

**Ships still move between her fleets in port** (`cmd.move_ship`, when fleet room is lit). A fleet left
with no ship stops the armada from sailing (`E_FLEET_EMPTY`) until a ship joins her or the armada is
disbanded.

## 3. The name

Her own, like a fleet's: 3 to 24 letters, unique among her company's armadas whatever the case. Never cut
with dots on any screen. Korean: **대함대** (a fleet is 선단 in this game; 함대 on its own reads as "fleet"
too, so the armada is the "great fleet").

## 4. Sailing

**One order** (`cmd.armada_sail(armada, port, course, insured)`), sent from the map's city panel.

- Every fleet leaves through `cmd.do_sail`, the one mover a fleet alone uses: her own supplies are bought
  for the passage, her own gates judge her (crew, flagship, navigation, the sea, her casks), her own
  insurance is written on her own hold.
- **All or none.** If one fleet cannot make the leg, the whole armada is refused, under that fleet's name,
  with her code and her figures ("Almiranta: 1 ship(s) are short of crew"). Nobody is left behind
  silently. The player fixes that fleet, or disbands.
- **Speed: the slowest fleet's.** A fleet of an armada reads the armada's speed everywhere a fleet's speed
  is read (`voyage.fleet_speed_at`): the departure, the supplies a leg asks, the casks gate, the quotes.
  So a fast fleet in a slow armada buys the casks the slow passage needs.
- **One schedule.** All fleets leave at the same instant on the same course at the same speed, and a
  voyage sailed in an armada rolls her **lead voyage's** days (the flagship fleet's): the same storm, calm,
  fair wind and raid on the same day for every fleet. Delays are equal, so they arrive at the same
  instant.
- **Supplies and wages stay per fleet.** Each fleet drinks from her own casks and owes her own crew.
- **A fleet of an armada does not sail or turn alone** (`E_IN_ARMADA` from `cmd.do_sail` and
  `cmd.divert`). Buying, selling, repairing, hiring and fitting in port are untouched.
- The armada sails **port to port**. A point of open sea, and a turn at sea, are left out (section 12).
- **Before the press, the screen shows the order's own figures:** `cmd.preview_armada_sail` runs the real
  order and throws it away, and answers the arrival, the speed and the cost (every fleet's supplies and
  insurance, summed). The press then sends that same order.

What can part an armada at sea: a fleet that runs dry is turned for port alone (the existing rule,
`FORCED_HOME`); the rest sail on. In port she then reads **Apart**: disband and form again in one port.

## 5. Trading while in an armada

Each fleet still has her own hold and trades for herself at the quay. Nothing is pooled. On Trade, a trip
of one passage for a fleet of an armada is sent as: what she buys here, then the armada's one order to the
trip's city, then what she sells there (kept in her queue until she lands). A trip of several passages is
refused in the server's words (`E_IN_ARMADA`): the armada has no queue of her own yet.

## 6. A raid on a voyage day (the heart)

Today: a raid day is one fleet's hulls against one squadron of raiders, through `public.fight_sides`, where
a side is a list of hulls.

**In an armada the raid meets all of her as one side.** On a raid day (the same day for every fleet, by
section 4):

1. **The side.** Every hull of every fleet of hers still sailing, the flagship fleet's first, in one list
   (`voyage.armada_side`, built from `voyage.fleet_hulls`, the one reading of a fleet as a side).
2. **The raiders.** A named pirate ship is real hulls and is met as she is. An anonymous raid is sized by
   the sea alone (danger × 40 × (0.5 + magnitude)), not by what is carried, so it grows with her:
   **strength × (1 + `armada_raid_scale` × (fleets − 1))**. At the knob's 1, she draws the raiders each of
   her fleets would have drawn sailing alone, and they come together.
3. **The fight.** Fought once (`voyage.armada_fight`, through `voyage.raid_report`, the skin every raid
   goes through), seeded by the lead voyage, with the flagship fleet's standing order. It is kept, so
   every fleet of hers reads the same fight whichever is settled first.
4. **What each fleet takes from it,** by the arm that was already there:
   - each ship loses the hull that one fight says for her;
   - each fleet loses crew by the outcome, as ever;
   - **plunder: each hold is searched on its own roll.** PLUNDERED takes 25 to 50 % of every good in a
     fleet's own hold, by that fleet's own day roll; STRIPPED takes all of it;
   - a ransom is paid on each fleet's own cargo;
   - each fleet's own insurance pays for her own loss.

### The arithmetic (measured, 150 fights a row, `docs/dev-log/2026-11-13-armada.md`)

A trader fleet here is 2 barcas (no guns). A war fleet is 2 byeong (6 guns each). R is the raid one fleet
draws alone. "scale 0" is one squadron whatever her size; "scale 1" is the knob as shipped.

| who sails | R = 12, scale 0 | R = 12, **scale 1** | R = 24, scale 0 | R = 24, **scale 1** |
|---|---|---|---|---|
| 1 trader fleet alone | ransom 79 %, plundered 21 % | the same | plundered 100 % | the same |
| armada of 2 trader fleets | driven off 100 % | vs 24: ransom 82 %, plundered 18 % | ransom 82 %, plundered 18 % | vs 48: plundered 100 % |
| armada of 4 trader fleets | evaded 100 % | vs 48: ransom 90 %, plundered 10 % | driven off 100 % | vs 96: plundered 100 % |
| armada of 6 trader fleets | evaded 100 % | vs 72: ransom 95 %, plundered 5 % | driven off 100 % | vs 144: plundered 100 % |
| 1 war fleet alone | evaded 100 % | the same | driven off 30 %, ransom 61 %, evaded 9 % | the same |
| 1 war + 1 trader | evaded 100 % | vs 24: driven off 91 %, evaded 9 % | driven off 91 % | vs 48: plundered 60 %, ransom 39 % |
| 1 war + 3 traders | evaded 100 % | vs 48: ransom 97 % | driven off 91 % | vs 96: plundered 100 % |
| 1 war + 5 traders | evaded 100 % | vs 72: ransom 100 % | evaded 100 % | vs 144: plundered 100 % |

Read it this way:

- **Scale 0 would make six fleets a free pass.** Four trader fleets with no guns never lose anything at
  any danger measured. That is the trivially-safe armada, and it is not shipped.
- **Scale 1 is neutral for like fleets:** two, four or six trader fleets together do about what one does
  alone (a little better: plundered 21 % → 5 % at R = 12).
- **What an armada buys is that warships fight for traders.** A trader fleet alone at R = 12 pays a ransom
  or is plundered; with one war fleet beside her she drives the raiders off 91 % of the time. One war
  fleet covers about one trader fleet; it does not cover five.
- **Plunder across holds:** each fleet loses her own roll's share of her own hold. In proof 68's run the
  lead lost 14 of 40 and 3 of 9 (35 %), her sister 5 of 21 (24 %), on the same PLUNDERED day.

## 7. A battle she starts (built: 0379, behind `attack_enabled`)

Battles (`public.battles`, `public.battle_sides`) exist only behind `attack_enabled`. With the switch off
nothing below runs for anyone; with it on, a fleet in no armada attacks exactly as she did. Built on the
round-by-round battle (0357) and the map's ring (0364):

- **Who takes part.** When a fleet of an armada attacks, every other fleet of hers **that is there** and has
  a ship fights on her side (`public.battle_armada`, the one reading):
  - she lies in port: the fleets of hers docked in that same port;
  - she is at sea: the fleets sailing under the same lead voyage **and** within `attack_reach_nm` (240) of
    her, so a fleet turned for port alone is not there;
  - she lies at anchor: nobody.
  A fleet of hers that is elsewhere takes no part and is not held.
- **All or none.** Each fleet that would take part is judged before anything moves: free to fight
  (`E_FLEET_BUSY`), her hold empty (`E_HOLD_NOT_EMPTY`), no battle within the cooldown
  (`E_ATTACK_COOLDOWN`). One refused refuses the attack, under her name. The fleet that attacks keeps the
  gates she had (her own guns, the reach, the target's).
- **The sheet.** Each joins as `ATTACKER` with `how = 'ARMADA'` in `public.battle_open`, before 0357 freezes
  the sheet: the fleet that attacked first, then the armada's order (flagship fleet first). Side `b` holds
  all their hulls; the sheet says the armada's name and her fleets. The engine and the freeze are not cut.
- **Held and freed.** Every one of them is held for the battle (in port: in battle; at sea: a free hold)
  and freed at its end. At sea they are held for the same span, so they still arrive together.
- **The stance.** One for the side. Fight or Flee, pressed once from any of her fleets' cards, acts for all.
- **Hull damage.** Each ship loses what the one fight says for her: the guns choose among all the hulls.
- **Crew loss.** Thrown back, broken off or fled: every fleet on her side loses the same share of each
  ship's hands (`attack_crew_lost.beaten`, 10 %), each softened by her own surgeon.
- **Loot.** Loot is gold, and it goes to the company's one purse, once, as before (the day's cap once). The
  report says each fleet's **share**: in proportion to the guns she brought, rounded down, the remainder to
  the fleet that attacked.
- **One report** a battle, under the fleet that attacked, with each fleet's share.
- **The preview** (`cmd.preview_attack`) is the real attack rolled back, so it reads all of this: the
  strength word is the armada's, it names her and her fleets, and a sister's refusal is its refusal.
- **The ring** (0364) counts the fleets that are there, so it grows with the armada with no change to it.
- **The card** of any fleet of hers in the battle shows the one battle: the armada's name, her fleets, the
  side's stance and, at the end, each fleet's share.
- **No player fights a player.** Both refusals (`E_HUMAN_TARGET`) are untouched and come first.

Where this section used to be silent, and what was decided, is in section 14 (D21 to D28).

## 8. What the map draws

- **At sea: one mark** for the armada, under her name, where the flagship fleet is, carrying every hull of
  her fleets (the chart's own hull group draws them as a line of ships when zoomed in, one hull when zoomed
  out, as for any fleet). Her sister fleets are not drawn under it.
- **In port:** her fleets lie at the quay as they always did.
- A raid has no ring (a raid is a day's event, not a timed battle). A battle's ring grows by section 7.

## 9. The screens

- **Fleets page:** under the fleets, an **Armadas** list: one row an armada (name, where she is, her
  fleets by name, and her totals: fleets, ships, attack, hull, crew, wages a day, speed) and a **New
  armada** row. The totals are sums of the fleets' own served totals (`public.fleet_totals`); the speed is
  the server's. Shown to a company of two fleets or more.
- **New armada:** pick the fleets (docked, with a ship, in no armada; the first picked is the flagship
  fleet; fleets in another port than the first are greyed and say where they are), name her, **Form**.
- **Her page:** totals, her fleets with the flagship fleet marked, **Disband**.
- **Map, city panel, Send fleet:** the armada is ONE row above the fleets: name, fleets by name, the time
  of the passage and the cost for all of them. Press the row, then **Send**. Her fleets are not listed
  again under her.
- **A raid's fight log:** each fleet is named above her own ships.
- **History:** "Armada X formed: A, B." / "Armada X departed for Cádiz." / "Armada X disbanded."

## 10. Insurance

Per fleet, as today: each fleet's policy is written on her own hold when she leaves and pays for her own
loss. Trade's sail passes "insured" to every fleet of the armada. The map's armada row sends her
uninsured in this slice (section 12).

## 11. Standing routes

A fleet on a trade route cannot join (`E_ARMADA_ROUTE`), and a fleet of an armada that is put on a route
afterwards is refused at her first SAIL (`E_IN_ARMADA`), which stops the route with that reason. An armada
has no route of her own (section 12). Routes are dark today.

## 12. Deliberately left out

| what | why not now |
|---|---|
| A split of the loot into holds | loot is gold and a company has one purse; the report says each fleet's share instead |
| A navy called against an armada in proportion to her size | the navy's call is 0333's, unchanged: it answers the ship set upon |
| A fleet joining or leaving without disbanding | disband and form again is free and does the same |
| An armada's own queue, and a trade route for an armada | a second order queue is a slice of its own |
| A point of open sea as her destination, and a turn at sea | an armada re-forms only in port; a turn would need all fleets cut at one instant |
| Insurance from the map's armada row | a fleet's own row quotes hers; six quotes on one row needs a design |
| Pooled cargo, pooled casks, pooled crew | each fleet is a fleet: one authority for a hold |
| A navy meeting (`NAVY` day) as one side | navy is dark; each fleet is met alone as today |
| Merchants forming armadas | no player fights a merchant armada yet; the fight ring would need it first |

## 13. Risks to the live world

- **Does six fleets together make raids trivially safe?** At scale 0, yes (section 6). The counter is the
  knob `armada_raid_scale` = 1: the armada draws the raiders her fleets would have drawn apart. The total
  raider strength a company meets is the same together or apart. Measured, section 6.
- **A named pirate ship is not scaled** (she is real hulls). An armada beats her more easily than a fleet
  does. That is intended: it is what warships are for.
- **Who can reach it today.** While `fleet_room_bite` is off no player can start a second fleet
  (`cmd.move_ship` is dark with the room). `docs/FLEETS_AND_SLOTS.md` read prod on 2026-10-25 and found
  every human company with exactly one fleet; that was not re-read for this slice (the before-check
  `scripts/ops/harness/armada/before.sql` reads it). If it still holds, an armada, lit as it is, becomes
  reachable only when the owner lights fleet room.
- **Cost on every fleet of the world** (merchants too): a fleet's speed reads one more primary-key probe
  of an empty table; a hazard roll one more; a raid day one call that answers null. Measured in the
  migration's own notice.
- **Forward rollback:** `armada_enabled` false shuts forming and sailing at once. An armada already at sea
  finishes her voyage as one.

### The owner's knobs (not touched)

The owner's number is six. A company holds `fleet_max` = **2** fleets while `fleet_room_bite` is off, and
`fleet_hard_max` is **5**. So:

- today an armada is **2 fleets** at the most, and only for a company that already holds two;
- with fleet room lit, up to **5**;
- **six needs the owner to raise `fleet_hard_max` to 6** (and a sixth step on the fleet ladder).

`armada_fleet_max` = 6 is the armada's own cap, a new knob, and waits for that.

## 14. Every default I decided

| # | question | default |
|---|---|---|
| D1 | What is an armada? | 2 to 6 fleets of one company that sail and fight as one (the lead's reading) |
| D2 | Which fleets may join? | Docked, in the same port, with a ship, no order waiting, on no route. Not at anchor, not under way |
| D3 | Who leads? | The first fleet picked: the flagship fleet. Her standing order is the armada's |
| D4 | The name | Her own, 3 to 24 letters, unique in her company. Korean: 대함대 |
| D5 | Speed | The slowest fleet's, read everywhere a fleet's speed is read |
| D6 | One fleet cannot make the leg | The armada is refused with that fleet's reason. Nobody is left behind |
| D7 | Arriving together | One schedule: the same days rolled for every fleet |
| D8 | A fleet of an armada sailing alone | Refused. Disband first |
| D9 | Supplies, wages, cargo, insurance | Per fleet, unchanged |
| D10 | A raid | One side of all her hulls, fought once |
| D11 | Raid strength | × (1 + 1 × (fleets − 1)) for an anonymous raid; a named pirate ship as she is. Knob `armada_raid_scale` |
| D12 | Plunder | Each hold on its own roll's share |
| D13 | Disbanding | Anywhere, any time, free; fleets at sea still arrive together |
| D14 | Changing members | Disband and form again |
| D15 | The map | One mark at sea under her name with every hull; fleets at the quay in port |
| D16 | Trade's sail | A one-passage trip sends the armada; longer trips are refused |
| D17 | Lit or dark | Lit, with a switch `armada_enabled` for a forward rollback |
| D18 | The battle | Built in 0379 on 0357 + 0364, behind `attack_enabled` |
| D19 | Several armadas a company | Allowed |
| D20 | Who sees the Armadas list | A company of two fleets or more |
| D21 | Who is "there" for a battle | Same port; or the same lead voyage and within `attack_reach_nm` of her. Nobody for a fleet at anchor |
| D22 | A sister that cannot fight (busy, cargo aboard, cooldown) | The whole attack is refused under her name. Nobody is left out silently |
| D23 | A sister with no guns | She joins: her hulls and hands stand in the line. Only the fleet that attacks must have guns |
| D24 | The cooldown | Every fleet that fought has it, so an armada cannot attack again by having another fleet open |
| D25 | The stance | One for the whole side, set by the company from any of her fleets' cards |
| D26 | Crew loss | The same beaten row (10 %) for every fleet on her side, each by her own surgeon |
| D27 | Loot | Gold to the one purse, as before. Shares are said by the guns each fleet brought; the remainder to the fleet that attacked |
| D28 | `armada_enabled` off | The battle does not read it: fleets still in an armada still fight together. `attack_enabled` is the switch |
