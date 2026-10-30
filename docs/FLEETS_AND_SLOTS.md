# Fleets and slots: several fleets of up to 7 ships

Owner row 180 (2026-10-20): *"Fleet, I want to create multiple fleet... assign multiple ships (total of 7).
Show stats of individual ship and also as a fleet... I want to have more fleet. You will be able to unlock
slots by purchasing with gold, and some with levels."*

Design only. No code, no migration in this PR. Every rule that is mine and not the owner's is marked
**NOT the owner's - confirm**.

**Decided by default: 7 ships per fleet.** Row 1 said *"This game fleet will be comprised with 8 ships"*;
row 180 says 7. Row 180 is the owner's latest word, so it wins. Nobody loses a ship by this: no fleet on
prod holds more than 3 (checked 2026-10-25, below).

---

## 1. How fleets work today (read off the chain and prod, 2026-10-25, prod head 0216)

### The tables
- `public.fleets` (0004): `player_id`, `name` (3–24 letters, unique per company), `status`
  (`DOCKED`, `ANCHORED`, `SAILING`, `REPAIRING`, `ADRIFT`, `UNABLE_TO_SAIL`), `port_id`.
  Rule `fleets_position_is_unambiguous`: a fleet at sea has no port; a fleet not at sea MUST have a port.
- `public.ships` (0004): every ship has a `fleet_id` (NOT NULL). There is no ship outside a fleet.
  Cargo, water, food and crew are stored **per ship**, not per fleet. One flagship per fleet
  (unique index `ships_one_flagship_per_fleet`). A ship cannot sit in another company's fleet (composite key).
- Officers are posted to a fleet (`player_officers.fleet_id`, 0015), not to a ship.

### The caps (three of them), and who checks them
One function checks all three: `public.assert_house_caps`. It runs on a trigger on `ships` and `fleets`
(0021), so any code that writes a ship gets the rule for free.

| cap | knob today (prod) | what a player actually gets today | where |
|---|---|---|---|
| ships in one fleet | `fleet_ship_max` = 8 | **2 + Seamanship level**, never above 8. Seamanship tops out at 5, so the most a player can reach is **7** | `public.earned_caps` (0107) |
| fleets per company | `fleet_max` = 2 | **1 + Trading level**, never below 2. No top | `public.earned_caps` (0107) |
| ships per company | `ship_max` = 8 | **8 + Command level** (Command lit since 0178, `skills_bite` true) | `public.house_ship_max` (0133) |

Merchants (NPC companies) skip the level rules: they get the flat numbers, 2 fleets and 8 ships per fleet.

### What a player can do today
- **Build** a ship (`cmd.do_build`, 0072): the new ship joins **the fleet that gave the order**, at that
  fleet's port, if that fleet has room.
- **There is no way to start a second fleet, and no way to move a ship from one fleet to another.**
  `public.form_fleet` (0096) exists, but only the founding of a company and the merchants call it. Its own
  comment names "a player verb to form a second fleet" as the caller still to come.

### What prod looks like (read-only, 2026-10-25)
- 18 human companies. **Every one has exactly 1 fleet.** 15 have 1 ship, 3 have 2.
- **No human has any Seamanship level**, so every human fleet is capped at **2 ships** today.
- 821 merchants: 786 fleets of 1 ship, 44 of 2, 7 of 3. None near 7.
- Human purses: 16,000 to 235,000 ducats (most at the starting 40,000). Humans hold about 0.03 % of the
  world's 812 M ducats; merchants hold the rest.

### The NO-HOME law
There is no home base. **Ports are the only base, and a ship acts from wherever it is docked.** Nothing in
this design adds a home, a shipyard storage, or a way to move a ship without sailing it. Every action
below happens **in one port, between ships that are physically there**.

### Fleet figures that already exist (they are reused, not rebuilt)
| figure | how the fleet's number is made | function |
|---|---|---|
| speed | the slowest ship, times the fleet's officer bonuses | `voyage.fleet_speed` |
| days of stores | the ship that runs out first | `voyage.endurance_days` |
| cargo room | the sum of the ships' holds | `public.fleet_free_hold`, `fleet_buy_capacity` |
| crew | the sum per ship; hiring fills each ship's empty bunks | `cmd.do_hire` |
| wave resistance | **the average of the ships' waves, rounded down** (0215; the brief said "per 0215", and 0215 says average, not the worst ship) | `public.fleet_wave` |
| fighting | every ship fires on its own; the fleet's hull is the sum | `voyage.fight` (0189) |

All of these already add up any number of ships correctly; 0021 measured them at 8.

---

## 2. The design

### 2.1 Two numbers the player sees, not three
Today there are three caps and the player can only read two of them. After this design the player sees
**two numbers**: how many fleets, and how many ships each fleet may hold.

- **Ships per fleet: up to 7.** `fleet_ship_max` goes 8 → 7.
- **Fleets: up to 5.** A new knob `fleet_hard_max` = 5. **NOT the owner's - confirm.**
- **The company-wide ship cap stops being a separate limit.** It becomes
  `(fleets you have opened) × (ships per fleet you have opened)`, so it can never refuse a ship that a fleet
  has room for. **NOT the owner's - confirm.** (Command's "+1 ship per level" moves to the ship ladder below.)

### 2.2 Opening more room: by gold or by level
The owner's words: *"unlock slots by purchasing with gold, and some with levels."* Two ladders. Each step
says how it opens: by level, by gold, or either. All prices are knobs in `world_config`.
**Every step, level and price below is NOT the owner's - confirm.**

**Fleets** (replaces 0107's "1 + Trading level, no top"):

| fleet | opens with | or |
|---|---|---|
| 1st | free (the founding fleet) | |
| 2nd | free (today's rule; nobody loses it) | |
| 3rd | Trading level 3 | **60,000** ducats |
| 4th | Trading level 6 | — (level only) |
| 5th | — (gold only) | **1,000,000** ducats |

**Ships per fleet** (this counts for every fleet the company has):

| room for | opens with | or |
|---|---|---|
| 1st and 2nd ship | free | |
| 3rd to 7th ship | +1 per level of Seamanship **or** Command, whichever is higher | **10,000 · 20,000 · 40,000 · 80,000 · 160,000** ducats, one step at a time |

Levels and gold add up, up to 7: Seamanship 2 plus two bought steps gives 2 + 2 + 2 = 6 ships.
When the levels alone already give 7, the buy button is gone. Gold already paid is never refunded.

*Why Seamanship stays:* 0107 made it the owner's "how many you can carry" (row 113). It happens to top out at
exactly 7 (2 + 5), so the owner's 7 and the older rule agree.

### 2.3 Sizing the gold against the money supply (0212)
- **The gold is destroyed, not paid to anyone.** One ledger line, kind `SLOT`, through `public.credit`, and
  no city or company receives it. That makes it a pure money sink: it can only shrink the money supply,
  never add to it. 0212 fixed where money was being *created* (the distance premium paid by the city's
  people); this removes some.
- **Scale it against what players actually buy.** The ships that go into the room cost
  tier 1 ≈ 15,000, tier 2 ≈ 47,000, tier 3 ≈ 222,000 on average (`ship_classes.build_cost`). Every price
  above is about the price of one ship of the tier a player has at that stage, so the room never costs more
  than what goes into it.
- **Total to open everything: 310,000 (ships) + 1,060,000 (fleets) = 1.37 M ducats.** A full 5 × 7 of
  tier-2 ships costs about 1.6 M, so the room is roughly half again on top of the ships.
- **Against income after 0212.** The haul sweep (`docs/dev-log/2026-10-20-haul-cap.md`, haul_max 3) puts a
  good trader's best route at about 270 ducats a sea-day (short routes) to 840 (10,000 nm and more), per
  fleet. A sea-day is 90 real seconds and a route starts one lap per game-day (48 real minutes). That
  gives a working fleet somewhere between tens of thousands and a few hundred thousand ducats a real day,
  depending on the route. So the 3rd fleet (60k) is a first-week buy, the ship steps are a buy every few
  days, and the 5th fleet (1 M) is a long goal. **These are estimates from a model, not measured on real
  players** — real humans have earned far less (the richest holds 47,000).
- **Effect on the world:** humans hold 0.03 % of the money, so this sink cannot fix the money supply on its
  own and does not need to; it must only not create money, and it does not. If merchants are made to buy
  room too (open question Q5), it becomes a real sink on the 812 M they hold.
- **Before lighting:** measure what humans actually earn per real day for one week after the client is out,
  and retune the price knobs in one forward migration if a step is out of reach or trivial.

### 2.4 Moving ships between fleets (same port only)
One new command: **move a ship**. Its rules (**NOT the owner's - confirm**, except "same port" which the brief asks for):
- Both fleets must be **docked at the same port**. Not at sea, not anchored, not under repair, and with no
  order waiting or running on either fleet (`E_FLEET_BUSY`).
- The ship takes **everything aboard with it**: its cargo, water, food and crew. Officers stay with their fleet.
- **To start a new fleet**, move one or more ships into "a new fleet" and give it a name. It is formed at that
  port through `public.form_fleet`. It needs a free fleet room (2.2).
- **The flagship:** if a fleet's flagship leaves, the biggest ship left (tier, then hold) becomes the flagship.
  A ship that arrives in a fleet that already has a flagship is not the flagship.
- **The last ship can leave.** The fleet is then **empty**: a name with no ships. It keeps its history and
  its officers, cannot sail, and still counts as an open fleet. It is placed at the port of the next ship that
  joins it, from any port (an empty fleet has nothing physical anywhere, so this does not break NO-HOME).
  No fleet row is ever deleted (its voyages and events point at it).
- **A fleet on a trade route** may lose or gain ships while docked; its next lap uses the new speed and hold.
  A fleet left empty pauses its route ("Blocked").
- The caps trigger (0021) already checks a moved ship, because it runs on `update of fleet_id`. Nothing new
  has to be taught about caps.

### 2.5 Ship figures and fleet figures
Ship (already served by `world.ship_view`): class, tier, speed, hold, crew now / needed / max, hull %,
waves, guns, armour, level.

Fleet, as one line on top of its ships (new fields on `world.fleets`, from the functions in §1):

| figure | rule |
|---|---|
| speed | the slowest ship (× officers), with **which ship is the slowest** named |
| cargo | sum of holds, and how much is free |
| crew | sum aboard / sum needed / sum of bunks; a ship short of crew is named |
| days of stores | the ship that runs out first |
| waves | 0215's average of the ships (rounded down), and the seas it opens |
| fighting | sum of guns and attack, total hull, crew able to board |
| cost per day | sum of wages |

**One warning that matters:** because waves is an *average*, adding a small ship can lower it and close a
sea (once `sea_conditions_bite` is lit). When moving a ship, the screen shows the before and after:
*"Waves 24 → 21. The North Atlantic will be closed to this fleet."*

### 2.6 NPC merchants
- Their per-fleet cap goes 8 → 7. **No merchant is affected today** (the largest fleet has 3 ships).
- They keep the flat rules (2 fleets, 7 ships) and **do not buy room** in the first slices.
  **NOT the owner's - confirm** (Q5).
- 0180's reinvestment (a merchant buys a ship when she has the money and room) keeps working; its room
  check already reads `earned_caps` and `house_ship_max`, which this design re-cuts in one place.
- Merchant fleet sheets show the same fleet line (2.5), so a player can compare.

### 2.7 The screens (following `docs/UI_DIRECTION.md` §6 FLEETS and MAP: no new screen, things unfold,
short words, no jargon)
Words (per `docs/WORDS.md`, which already bans "slot" and "berth" for cabins): the player reads
**"room for N ships"** and **"open a fleet"**, never "slot".

```
════════════════════════════════════
 Fleets  2 / 5
 ▲ Gaivota      Lisbon           ›
   6.1 kn · 840 t · 112 crew · waves 24
 • Andorinha    → Cádiz · 1.2 d  ›
 ＋ Open a third fleet    60,000 🪙 or Trading 3
 🔒 Fourth fleet          Trading 6
────────────────────────────────────
 TRAY: Gaivota
 [Ships ◆][Cargo][Stores]
 Slowest: Kobune 5.0 kn · free 120 t · days of stores 15
 ┌───────┐┌───────┐┌───────┐┌───────┐
 │⚑Gaivo.││Segunda││ + Add ││🔒 room │
 │Barca  ││Kobune ││ a ship ││20,000🪙│
 └───────┘└───────┘└───────┘└───────┘
 (tap a ship → it unfolds:  Move to ▸  Andorinha · New fleet)
```

- A ship tile unfolds in place to show its figures and **Move to**. Move lists only fleets docked in the same
  port, plus **New fleet**. A fleet in another port is not shown, not greyed.
- The before / after line (speed, cargo, waves) shows under the choice before the press.
- An unlock row says the price and the level on one line, and the button is one press with the money shown.
- MAP: the fleet pill counts fleets (`⛵ 3`); nothing else on the map changes.
- YOU tab (row 181): "Fleets 2 / 5 · room for 4 ships each".

---

## 3. Build order (slices)

Migration numbers are the prod head + 1 at push (0217 is taken by the new-harbours lane, so these start
at 0218 or later). Each migration self-asserts on its own probe rows only, and is rolled back, never deleted.

| # | slice | what | live play changes? |
|---|---|---|---|
| F1 | migration: **the room is counted** | `fleet_ship_max` 8 → 7, `fleet_hard_max` 5, the price and level knobs, table `public.house_room` (company, kind FLEET or SHIP, steps bought). Re-cut `earned_caps` and `house_ship_max` by hunks to read the ladders. Switch `fleet_room_bite` = false: while off, every company reads exactly today's caps | No (dark). Prove: dark caps equal today's for every company |
| F2 | migration: **a ship changes fleets** | `public.move_ship` core + `cmd.move_ship` door (same port, docked, not busy, flagship rule, empty fleet, new fleet via `form_fleet`) | No while F1 is dark beyond today's 2 × 2, but it is the first time a player can make a 2nd fleet, so it gets its own window |
| F3 | migration: **room is bought** | `cmd.buy_room(kind)`: price from the ladder, `credit(-price, 'SLOT')`, event `ROOM_OPENED`, one step at a time, refuses past the top | No while dark |
| F4 | migration: **the fleet reads its totals** | `world.fleets` gains the fleet line (2.5); `world.house_room()` serves open / locked / price / level | No (reads) |
| F5 | client | FLEETS: fleet line, 7 tiles, Move to, unlock rows; YOU tab line; map pill | No |
| F6 | migration: **light it** | `fleet_room_bite` = true, then a 30-minute after-check (caps per company, any `E_SHIP_MAX` / `E_FLEET_MAX` refusals, ledger `SLOT` sum = what was bought); forward rollback ready (set it false) | **Yes** |
| F7 | measure | one week of human earnings per real day; retune prices in one forward migration if needed | Prices only |

F2 and F3 can be built in parallel worktrees after F1; F4 and F5 after F2/F3.

---

## 4. Open questions, each with the default I will use

| # | question | default |
|---|---|---|
| Q1 | 7 or 8 ships per fleet? | **7** (row 180, the owner's latest words) |
| Q2 | How many fleets at most? | **5** |
| Q3 | Which fleets open by level and which by gold? | 3rd: Trading 3 or 60,000 · 4th: Trading 6 only · 5th: 1,000,000 only |
| Q4 | Prices for ship room? | 10k / 20k / 40k / 80k / 160k for the 3rd to 7th ship, shared by all fleets |
| Q5 | Do merchants buy room too? | **No** at first (flat 2 fleets × 7). Making them pay later would be a real sink on their 812 M |
| Q6 | Does the gold go anywhere? | **Destroyed** (a money sink); no city receives it |
| Q7 | What happens to Command's "+1 ship per level"? | It counts like Seamanship for ship room (the higher of the two) |
| Q8 | Can ships move between fleets when anchored, or only docked? | **Docked only**, same port, no order running |
| Q9 | What happens to a fleet whose last ship leaves? | It stays as an **empty fleet**: name, history and officers kept; it takes the port of the next ship that joins |
| Q10 | Can a fleet be disbanded to free its room? | **Not in these slices**; an empty fleet can be renamed and refilled |
| Q11 | Refund when a level later gives room already bought? | **No refund**; the buy button hides once levels give 7 |
