# PIRATES AND HAVENS — danger zones, pirate fleets, pirate havens, escort contracts

**Status: DESIGN v1, 2026-10-19. No code, no migration, no production change.** Written against `main`
`fe15252` (production head **0208**; the fight is LIT since 0204: `combat_bite` true, `armour_turns_pct`
0.5). Every production number quoted below comes from the dev-logs named beside it; nothing here was
measured on production for this document. Every rule is tagged **OWNER** (his words) or **DEFAULT** (mine,
reversible); §9 lists every DEFAULT with what happens if he says no.

**The owner, 2026-10-18/19:** danger zones; pirate fleets; pirate havens with boss captains and famous-gear
loot (the "dungeons"); escort contracts. And on famous gear (0184's header, 2026-10-18 13:25): *"yes famous
gear can be made, but later. there will be other items that needs to be gained in act of pirating, trading,
and all. i will set them later."* Famous gear has had no source since 0184: `public.item_unmade` holds all
11 famous pieces, so no workshop makes one and no famous ship can be laid down. **This document makes the
havens that source.**

**Laws this design is bound by** (`docs/DESIGN.md`): no PvP, ever; no visual combat, ever; the map is an
output device that never takes an order and never draws a rival player; danger is resolved server-side and
reported as prose; one authority per concept, compose don't fork, retire the old (`docs/NO_SPAGHETTI.md`);
plain modern words, no number without what it is out of (`docs/WORDS.md`).

**Insurance is being built beside this.** Cargo insurance (port underwriters, a premium priced from the
voyage's danger, payout less a 10 % deductible from the city purse, merchants insured in place of a free
refound) must price off **the same danger authority** this document defines (§2.4, §7.2). The two designs
share one function and one frozen number per voyage; neither invents a second one.

---

## 0. The answer in twelve lines

1. **A danger zone IS a sea.** No new geometry, no polygon, no zone table. The 51 seas the world already
   has (`public.seas`, `danger_level` 1–5 authored in `data/seas.json`, `piracy_index` derived) are the
   zones. Nine of them are the historical pirate waters of 1500–1650 and are authored as such (§2.1).
2. **Danger is ONE served number per sea**, `voyage.sea_danger(sea, at)` ∈ [0, 1]: the authored
   `piracy_index` × a live pressure that pirate fleets raise and a cleared haven lowers. It replaces the two
   places that read `piracy_index` today (the mix of what the sea breeds, and the raiders' strength) and is
   read by nothing else except the map, the desk's plan line, and insurance.
3. **Danger is frozen into the voyage at departure**, beside the speed, so a voyage settled nine hours
   late rolls exactly what it would have rolled on time (DESIGN D.2), and so an insurance premium quoted
   at departure is priced on exactly the danger the voyage will meet.
4. **Pirate fleets are named captains who roam their zone's seas.** They are world rows, not companies:
   no purse, no route, no trading. Where one is, the sea is more dangerous and a raid there is fought
   against *his* hulls instead of the anonymous xebecs. A raid never becomes a new combat; it is the same
   `voyage.fight_resolve`, handed real hulls (§3).
5. **Pirate havens are places**, nine `ports` rows of a new `kind = 'HAVEN'`, exactly as a sea place is a
   `ports` row of `kind = 'SEA_PLACE'` (0036). You can SAIL to one once you know of it; you learn of it
   from an inn rumour or from a raider who ran for it (§4.2).
6. **The assault is one verb, `ATTACK <fleet>`**, resolved at once on the server in waves (the guard
   ships, then the captain's ship and the shore battery), each wave a `fight_resolve` call, and written as
   one History report in the same shape as today's battle report (§4.3–4.4).
7. **Loot**: the haven's hoard (money pirates actually took from merchants and players in that zone, so
   it is money returning, not money printed), Battle Honours, freed crew, and — on the captain's ship —
   **his famous piece**, the one he fights with. A company keeps one of each (the 0165 rule, extended).
8. **A cleared haven lowers its zone's danger for three real days** and respawns after them with a new
   captain. That is the whole "zone changes over time" mechanism: presence raises, clearing lowers.
9. **Escort contracts are posted on the Requests face** by the city, for a merchant fleet about to sail
   into danger: accept at the quay, your fleet sails in company with hers, her raids are fought with your
   guns, and the city pays you on her safe arrival (§5).
10. **The economy stays bounded** (§6): the hoard is recycled money with a cap; famous pieces are capped
    by one-of-each and a shared 72-hour respawn; the sinks are real (repairs, crew, supplies, time).
11. **Every slice lands dark**, byte-parity against today's answers, and is lit by its own switch with a
    measured 30-minute window and a forward rollback (§8). Seven slices, Z1–Z7.
12. **Learned from the old space game**: a polygon that exists "therefore pirates attack here", a second
    danger scale, client-creatable zones and a 17-PR stack that never deployed. Here the zone is the sea the
    game already has, the scale is one function, nothing a client can write, and each slice ships alone.

---

## 1. The player fantasy and the loop

In plain words, for the player:

> Some waters are dangerous. The map shows you which, in one shade. Cargo carried through them pays
> more and costs more to insure. If you carry it with guns, the pirates mostly leave you alone; if you
> carry it with none, you will meet them. Some pirates have names. A named pirate has a home, a hidden
> harbour on a coast nobody patrols, and in that harbour is his hoard and the ship he fights from — and
> that ship carries something no workshop in the world can make. Find the harbour, bring enough guns, and
> take it. While he is gone, his waters are quiet, and everyone trading through them is a little richer.
> Or stay a trader: take a city's money to sail beside a merchant who is afraid of those waters.

Three reasons to sail into danger, each with its own money:

| Why | What you get | Who pays |
|---|---|---|
| **Profit** | The distance premium already exists (0173, halved by 0208): far goods pay more, and the far waters are the dangerous ones. Danger adds nothing to the price; it adds the risk the premium already pays for. Insurance makes the risk a number you can buy out of. | the market |
| **Famous gear** | The only source of the 11 famous pieces, each the key to one famous ship (0165). | the haven's captain |
| **Contracts** | Escort fees from cities, Battle Honours for your captains' promotion (K8), the company's Combat track. | the city purse |

The loop in one session: read the map (where is it dark); read the inn (who is said to lie where); fit
guns; sail; read the report; repair; come back richer, or with a piece of history on your deck.

---

## 2. Danger zones

### 2.1 What a zone is — the sea, authored to history [DEFAULT Z-A]

A zone is a sea. `public.seas` already carries `danger_level` (1 home waters … 5 deadly, 0040:27-36,
authored in `data/seas.json`) and `piracy_index` (derived in `scripts/lib/world-derive.mjs:565-571`:
0.45 in the nine `PIRATE_SEAS`, 0.12 in open ocean, 0.20 elsewhere). The world generator already knows
which waters are pirate waters. What is missing is that those nine were picked for mechanics, not for
history, and some of history's worst water is not among them.

The nine historical pirate waters of 1500–1650, and what the data says of each today:

| Zone (sea rows) | Who, when | `danger` today | Haven (§4.1) | Change proposed |
|---|---|---|---|---|
| **Barbary coast** — Mediterranean Sea (Maghreb side) | the Barbary corsairs of Algiers, Tunis, Tripoli and Djerba; Turgut Reis (d. 1565), Uluç Ali | 3 · piracy 0.45 | **Djerba** | danger 3 → 4 |
| **Atlantic Morocco** — North Atlantic off Salé | the Salé rovers (the pirate republic of Salé, 1627–); Murat Reis the Younger | 2 · 0.12 (open ocean) | **Salé roads** | the haven's own leg carries the danger (§2.2); the ocean row is not raised |
| **The Caribbean** — Caribbean Sea, Gulf of Mexico | French corsairs from the 1530s (François le Clerc, "Jambe de Bois", 1553), the buccaneers of Tortuga (1620s–) | 4 / 3 · 0.45 / 0.20 | **Tortuga** | Gulf of Mexico piracy 0.20 → 0.30 |
| **The Strait of Malacca** — Strait of Malacca, Andaman Sea approaches | the orang laut and Aceh raiders; Johor–Portuguese war | 5 · 0.45 | **Lingga** | none |
| **The Malabar coast** — Arabian Sea, Laccadive Sea | the Kunjali Marakkars of Kottakkal (1507–1600), who fought the Portuguese for a century | 4 / 2 · 0.45 / 0.20 | **Kottakkal** | Laccadive piracy 0.20 → 0.35 |
| **The Gulf** — Persian Gulf, Gulf of Oman | the raiders of Qeshm, Hormuz and Musandam | 3 / 3 · 0.45 / 0.20 | **Qeshm** | Gulf of Oman piracy 0.20 → 0.35 |
| **The China coast** — South China Sea, Taiwan Strait, East China Sea | the wokou (Wang Zhi, d. 1560), Lin Feng / Limahong (1574), Zheng Zhilong (1620s) | 4 / 3 / 3 · 0.45 / 0.20 / 0.20 | **Shuangyu** (Liampo, the wokou mart destroyed 1548) | Taiwan Strait and East China Sea piracy 0.20 → 0.35 |
| **The Korea Strait and Kyushu** — Korea Strait, Sea of Japan (south) | the wokou bases of Tsushima and the Gotō islands | 2 · 0.20 | **Gotō** | Korea Strait piracy 0.20 → 0.30 |
| **The Adriatic** — Adriatic Sea | the Uskoks of Senj (1537–1618) | 1 · 0.20 | **Senj creek** | Adriatic danger 1 → 2; piracy 0.20 → 0.30 |

The changes are data rows in `data/seas.json` and the generator's two sets, held by the world guard; they
are a slice's data, not a new rule. The Gulf of Guinea and the Red Sea stay in `PIRATE_SEAS` as they are
(fever coast, reef water) but get no haven: a haven is a named pirate base of the period, and those waters
had none a sailor of 1550 would name.

**Why the sea and not a drawn region.** 0035's platform audit already refused zones for this game
(`docs/OWNER_REQUESTS.md` row 40: *"the leg is already voyage's exposure surface"*), and 0055's own comment
forbids a second scale: *"there is no per-(kind, sea) weight table and there must never be one, or the sea
would carry two danger scales."* The old space game drew polygons and then found that any active polygon
was an ambush region whatever it called itself (`byeharu-zone-platform` memory, trap 7). A sea has a name
the player knows, a raster the map already paints, and one row the rules already read.

### 2.2 Danger is one number [DEFAULT Z-B]

**The authority:** `voyage.sea_danger(p_sea uuid, p_at timestamptz) returns numeric` — server-only,
stable:

```
pressure(sea, at) = presence(sea, at)                       -- +pirate_presence_pressure (0.5) per named
                                                             --  fleet in the sea at `at`, not retreating
                  + relief(sea, at)                          -- −haven_cleared_relief (0.5) while the zone's
                                                             --  haven is cleared (cleared_at + 72 h > at)
                  + wins(sea, at)                            -- sea_pressure.value × 0.9 ^ hours since
                                                             --  updated_at: raids DRIVEN_OFF here lower it
                                                             --  by win_pressure (0.02) each; decays home
sea_danger        = clamp( piracy_index × (1 + pressure), 0, 1 )
```

With no pirate fleet, no cleared haven and no wins written, `pressure = 0` and `sea_danger =
piracy_index` **to the digit**. That is the dark parity Z1 proves for every sea.

**Where `piracy_index` is read today, and what reads `sea_danger` after:**

| Reader | Today | After Z1 |
|---|---|---|
| the mix of what a sea breeds, `voyage.sea_mix(sea)` (0055:361-401) | `s.piracy_index` into `v_p` | the segment's **frozen** danger (§2.3), passed in: `voyage.sea_mix(sea, danger)` |
| the raiders' strength, `voyage.settle` PIRATES arm (0027:337) | `piracy_index × 40 × (0.5 + magnitude)` | `frozen danger × 40 × (0.5 + magnitude)` |
| the map and the desk | nothing | `world.sea_danger()` — every sea's live number and word, one read |
| insurance | — | `voyage.risk_quote(plan)` over the planned segments' `sea_danger` now, and the frozen figure after departure (§7.2) |

Nothing else may read `piracy_index` directly after Z1; the self-assert scans every live body for the
token with a positive control, the 0184 method.

**The word the player reads.** The five words are the authored `danger_level`'s, served once by
`world.sea_danger()`: **Calm · Watchful · Dangerous · Severe · Deadly** — and the live number moves the
word only when it crosses a band (bands at 0.1 / 0.25 / 0.4 / 0.6 of `sea_danger`). The player never sees
the number. *"Strait of Malacca · Deadly"*; *"Barbary coast · Dangerous (Turgut Reis's fleet seen here)"*;
*"Caribbean · Watchful — Tortuga was cleared 2 days ago"*.

### 2.3 Frozen at departure, like the speed [DEFAULT Z-C]

DESIGN D.2's law: a voyage is a pure function of time. `voyage.hazard_roll` reads `voyage.leg_at_day`'s
frozen segment and the sea's `hazard_base` and rolls three `voyage.rng` streams (0055:412-475). If it read a
LIVE pressure, the same day settled at two different times could roll two different fights, and the
offline-equivalence proof (DESIGN App. 2, proof 1) would fail.

So `voyage.depart` gains one hunk: each frozen segment gets `danger := voyage.sea_danger(sea_id, now())`
and `raiders := the named fleet present (its id) or null` beside its `sea_id`. `hazard_roll` and the
PIRATES arm read the segment. The voyage then meets exactly the danger it departed into — a fleet that left
Algiers while Turgut Reis was out meets Turgut Reis, even if he has gone home by the time the day settles.
The insurance quote at departure and the raid roll at sea use the same frozen figure, so a premium is never
priced on a danger the voyage did not sail.

### 2.4 How the map shows it — output only [DEFAULT Z-D]

- **One shade per sea.** The chart already paints a sea raster with one ordinal per sea
  (`seas.raster_ordinal`, `scripts/build-sea-raster.mjs`) and names the seas (`src/chart/seaNames.ts`).
  Z2 reads `world.sea_danger()` once a minute and tints each sea's raster by its band: five steps of the
  `loss` token at low alpha over the sea, `Calm` adding nothing. No outline, no hatch, no icon, no legend:
  darker water is more dangerous, which is what a sailor's chart has always meant.
- **The sea's line in the detail panel.** Tapping water already selects a sea place or a sea; the
  bottom-right corner panel adds one line: the word, and the one reason if there is one (*"Turgut Reis's
  fleet seen here"*, *"Djerba cleared 2 days ago"*). Corner, foldable, no sentence longer than that
  (`byeharu-map-ux-principles`).
- **Havens** are drawn as ports are, once known (§4.2): the port triangle in `loss` ink with no ring; a
  cleared haven in `ink-3`. Unknown havens are not drawn at all.
- **Pirate fleets are not drawn** (DEFAULT; §9 Q1). A named fleet's position is a sea, not a point, and a
  hull on the chart would make the chart a thing to steer around — the targeting surface law 3 protects
  against. The shade and the panel's line carry what the player needs.
- **The desk.** The plan builder's SAIL line and the Sell-at rows gain one quiet word where the course
  crosses a sea at Dangerous or worse: *"through the Strait of Malacca · Deadly"* — the same words, from the
  same read (`reachWords` in `src/features/command/plans/planLines.ts` is the one place that words a plan
  line).

### 2.5 How danger feeds raids and insurance

- **Raids.** Danger sets how often the sea breeds pirates (through `sea_mix`'s PIRATES weight: `0.035 ×
  (1 + 30 × danger_level/5 × sea_danger)`, 0055:278-283) and how strong the raiders are (`sea_danger × 40 ×
  (0.5 + magnitude)`). Today, per voyage-day: ~0.4 % in a `piracy 0.45`, danger-5 sea against ~0.07 % in a
  danger-1 sea (hazard 0.012 × PIRATES share ≈ 31 %, against 0.008 × ≈ 8.5 %). A present fleet
  (`pressure +0.5`) raises both by half; a cleared haven lowers both by half. The *fight itself* is unchanged
  (0189/0202): range, accuracy, attack, armour, boarding, surrender.
- **Insurance** (the parallel design) prices a voyage's premium from `voyage.risk_quote(plan)`: Σ over the
  plan's voyage-days of `p_hazard × PIRATES share × expected loss fraction by outcome band`, every term read
  from the same functions the roll uses (`hazard_base`, `hazard_mult`, `sea_mix`, the fight's measured
  outcome shares by escort band — dev-log 2026-10-18-auto-fight §Balance). It computes nothing the roll
  does not. After departure it reads the frozen segments. One number, two readers.

---

## 3. Pirate fleets

### 3.1 What a pirate fleet is [DEFAULT Z-E]

A **named captain with a fleet**, a world row, not a company. He has no purse, no route, no market and
never trades, so he does not go through the merchant executor (`npc_plan`, `npc_tend_route`) and is not a
`players` row — *"is this a merchant?"* stays `players.is_npc` and nothing else (0097:124-126), and the
arrivals sweep does no work for him.

```
pirate_captains (code, name, zone_code, haven_port_id, flagship_class, famous_item_code, hulls jsonb, blurb)
    -- authored data (data/pirates.json), held by the world guard; one captain per haven
pirate_fleets   (captain_code PK, hull_pct numeric, retreat_until timestamptz, beaten_count int, updated_at)
    -- the live state: how hurt he is, whether he has run home, how often he has been beaten
```

`hulls` is his fleet as the fight engine already understands a fleet — the `p_ships` shape of
`voyage.fight_resolve` (0189:188): `{class, name, gear[]}` per hull, built into the full
`{id, name, tier, hull, maxd, crew, attack, accuracy, reach, armour, sighting, boarder_pct, boarder, gunner,
gear[]}` by ONE builder, `voyage.raider_hulls(…)` (§3.3), from the class's own figures and the named gear's
`item_effects` — exactly how today's anonymous raiders are read as xebecs (`fight_raider_class`).

**The nine captains** (DEFAULT; each is a real person or a real band of the period, DESIGN law 6):

| Captain | Haven · zone | Flagship | His famous piece (the loot, §4.5) | Fleet (hulls) |
|---|---|---|---|---|
| **Turgut Reis** | Djerba · Barbary | xebec (galley-built) | Turgut Reis Swivels | 1 xebec (flag) + 4 xebecs |
| **Murat Reis** | Salé roads · Atlantic Morocco | xebec | Madre de Deus Holds (the Azores prize) | 1 xebec + 3 xebecs |
| **François le Clerc** | Tortuga · Caribbean | carred | Drake's Culverins · San Martín Tercio Arms | 1 carred + 2 xebecs + 1 pinnace |
| **The Lingga orang laut** | Lingga · Malacca | junk | Batavia Double Planking | 1 junk + 4 pinnaces |
| **Kunjali Marakkar** | Kottakkal · Malabar | dhow (war-built) | Rahimi Pilgrim Holds | 1 dhow + 4 dhows |
| **The Qeshm rovers** | Qeshm · the Gulf | dhow | none — the biggest hoard instead (§9 Q7) | 1 dhow + 3 dhows |
| **Wang Zhi** | Shuangyu · China coast | junk | Zheng He Bulkheads | 1 junk + 3 junks |
| **The Gotō wokou** | Gotō · Korea Strait | junk | Dragon-head Cannon · Date Masamune Charts | 1 junk + 3 pinnaces |
| **Ivan Vlatković** | Senj creek · Adriatic | xebec | Duodo Bow Guns · La Couronne Battery | 1 xebec + 3 pinnaces |

*(The piece-to-haven mapping is a first proposal and §9 Q7 asks the owner to confirm it; two havens carry two
pieces because there are 11 pieces and 9 havens. The Qeshm row shows the one place the mapping is thin: no
famous piece of the catalogue is Gulf-born. DEFAULT: Qeshm drops no famous piece and pays the largest
hoard instead; if the owner prefers, La Couronne moves there.)*

### 3.2 Where he is — roaming without a cron [DEFAULT Z-F]

A captain's zone is a list of sea codes (`pirate_zones (zone_code, sea_code)`, data). **Which sea he is in
on a given game day is a pure function**: `voyage.pirate_sea(captain, game_day) = the zone's seas, picked
by voyage.rng_raw(captain_uuid, game_day, 'roam', world_secret)` (0006:127). It needs no tick and cannot be
predicted by a client (the secret is the server's, 0031). Once a game day (48 real minutes, `game_day_seconds`
2,880) he may move; most days he stays — the draw keeps him where he is with chance `pirate_stay_chance`
(0.6). His home sea (the haven's) is weighted double.

He is **not** in any sea while `retreat_until > now()`: beaten (hull_pct below `pirate_retreat_at` 0.25) he
runs for his haven and lies there `pirate_retreat_hours` (12), regaining hull at `pirate_regen_per_hour`
(0.1). While home he adds nothing to any sea's pressure, and he is at home when the haven is attacked
(§4.3): a captain you have just beaten at sea is a captain you can catch in harbour.

### 3.3 How he meets a fleet — the raid, with his hulls

Nothing new is rolled. On a PIRATES day (0055's mix), the frozen segment says whether a named fleet was in
that sea at departure (§2.3). `voyage.settle`'s PIRATES arm already calls `voyage.fight(voyage, day, fleet,
raider_strength)` (0189:498). One change, in one place:

- **`voyage.fight_resolve` takes the raiders as hulls**, `p_raiders jsonb`, in the same shape as
  `p_ships`. Today it takes a strength and builds xebecs from it inside; that building moves out into **one
  builder**, `voyage.raider_hulls(p_voyage, p_day)`: if the day's segment names a captain, his `hulls` (at
  his `hull_pct`, read at the voyage's departure and frozen too — a fleet that sailed when he was hurt meets
  him hurt); otherwise `strength / xebec escort` anonymous xebecs, byte-identical to today. The dark parity
  (no captain anywhere) is asserted on 0202's own 960-day probe: every fight word for word.
- **The fight writes back.** A raid DRIVEN_OFF or EVADED against a named captain writes
  `pirate_fleets.hull_pct -= the share of hull his side lost` (the fight already counts `damaged_pct` for the
  raiders) and `sea_pressure.value -= win_pressure`. One writer: the PIRATES arm, the same hunk that writes
  the player's hull loss today.
- **The report names him.** `rounds` already carry *"Raiders: one small Galeão, 14 crew."*; with a
  captain it reads *"Turgut Reis, with four sail out of Djerba."* and, when he breaks off, *"They ran for
  Djerba."* — which is how the haven is discovered (§4.2). The History tray's `payloadFights` reader
  (`src/features/ledger/headline.ts`) needs no change: the sentences are the server's.

### 3.4 Win and loss, said plainly

| Outcome (unchanged five) | Against a named captain, in addition |
|---|---|
| EVADED / DRIVEN_OFF | he is hurt by what you hit (`hull_pct`); the sea is a little safer (`win_pressure`); your captains earn Combat experience and the company's track moves (`fight_points`, as today); **a Battle Honour** is put into storage at your arrival port (K8's item, through its existing credit) |
| RANSOM | as today (−8 % of cargo value); the ransom goes **into his haven's hoard** (§4.5) |
| PLUNDERED | as today (cargo −25…50 %, crew −10 %); the cargo's value goes into his hoard |
| STRIPPED | never, lit (0202: the crew surrenders → PLUNDERED) |

The flagship is never taken; no hull is ever taken (DESIGN B.6; 0189's "not built", confirmed as DEFAULT
here, §9 Q2). Merchant fleets meet him exactly as players do — they sail the same engine — and what he takes
from them funds the hoard the player later takes from him.

---

## 4. Pirate havens — the "dungeons"

### 4.1 Where they are [DEFAULT Z-G]

Nine `ports` rows with `kind = 'HAVEN'`, placed by hand at the real places (§2.1's table), joined to the leg
graph by generated spur legs exactly as `scripts/build-sea-places.mjs` joins a sea place (0036; the
generator refuses a point that is not water or is within 15 nm of a harbour). A haven has no market, no
buildings, no purse, no flag and no influence; it is in no country's race (GREAT_POWERS keeps its
invariants: the `port_allegiance` foreign keys never see a haven, because a haven has no allegiance row). It
is a place a fleet can SAIL to and lie off, and that is all it is until the verb (§4.3).

Two consequences of "a haven is a port row", both wanted:
- `cmd.do_fit` works there (docked only, no building needed for a High/Mid/Low fitting, 0074/0158), so a
  piece taken from the captain's ship can be fitted to yours on the spot.
- A haven's spur leg carries its own `hazard_mult` (1.5), so the approach is dangerous water even in a
  quiet sea (the Salé roads in the open Atlantic).

### 4.2 Finding one — rumour and pursuit [DEFAULT Z-H]

A haven is **unknown** to a company until learned, and an unknown haven is not on the map, not in the SAIL
picker, and refused by `voyage.sail_refusal` with the one sentence *"You have not heard where Djerba is."*
(`E_UNKNOWN_PLACE`). It is learned two ways, both written to `haven_known (player_id, haven_port_id,
learned_at, how)` by one function, `public.learn_haven_for`:

1. **A raider who ran for home.** A fight against a named captain that ends EVADED or DRIVEN_OFF writes
   *"They ran for Djerba."* and the company learns the haven. Pursuit is the honest way in: you met him,
   you beat him, you know where he went.
2. **Word at the inn.** The inn (`world.inn`, the **Captains here** face) gains one line for a city whose
   sea is in a zone with a haven: *"Word at the inn: Turgut Reis lies at Djerba with four sail."* It is
   there with chance `haven_rumour_chance` (0.35) per inn shift (the room already turns every 15 minutes,
   0119), derived from (port, shift, secret) like who is in the room — never rolled, never farmed. Reading it
   learns the haven. It costs nothing (DEFAULT; §9 Q4 offers a price).

Learned is permanent for the company. The map draws the haven from then on (§2.4), the Codex's **Places**
gain a **Pirate havens** group listing the known ones with the captain's blurb and *"Cleared 2 days ago"* /
*"Held by Turgut Reis"*.

### 4.3 The verb — `ATTACK <fleet>` [DEFAULT Z-I]

In DESIGN F.2's grammar:

**`ATTACK <fleet>`**
Assaults the pirate haven the fleet lies at.
- **Pre:** fleet `DOCKED` or `ANCHORED` at a port of `kind = 'HAVEN'`; the haven is not cleared
  (`cleared_at + haven_respawn_hours < now()` or null); the fleet's attack is above 0 (at least one gun
  somewhere — `world.ship_stats` 'attack' > 0 on any hull); not already attacked by this fleet in the last
  `attack_cooldown_minutes` (30).
- **Cost:** 0 at issue. Hull and crew by the fight's outcome; the fleet stays where it lies.
- **Queues:** nothing — it **resolves synchronously**, like INVEST, and returns the report. (A haven is
  not a voyage; there is no checkpoint to wait for.)
- **Fails:** `E_NOT_AT_HAVEN` (*"Ponente is not at a pirate haven."*), `E_HAVEN_CLEARED` (*"Djerba was
  cleared 2 days ago; the pirates have not come back."*), `E_NO_GUNS` (*"Ponente has no guns to attack
  with."*), `E_ATTACK_COOLDOWN`, `E_STALE`.

`cmd.preview_attack(fleet)` is the dry-run every verb has: it does not fight (a random fight previewed once
would lie); it serves **the sides**: *"Your 3 ships, 40 guns' worth, 164 crew — against Turgut Reis's 5
ships, the shore battery, and about 190 crew. They are stronger."* The word is one of **weaker · about
even · stronger · far stronger** from the escort-score ratio (`voyage.escort_score` on both sides, the
bands 0.7 / 1.2 / 2.0 the fight already uses). The composer's verb pad gains ATTACK beside REPAIR; the
map's haven panel offers it as its one action when the fleet lies there (law 3 as amended, DESIGN E.5).

**Words** (`docs/WORDS.md` rows to add in Z4/Z5): **pirate haven** (never den, lair, dungeon); **Attack**
(never assault, raid, storm); the captain is **pirate captain** (never boss); his fleet is **his fleet** /
**N sail**; danger words **Calm · Watchful · Dangerous · Severe · Deadly**; **hoard**; **Taken from the
haven** on the receipt; **Escort** for the contract.

### 4.4 How it is resolved — waves of the one fight

`cmd.run_attack(fleet)` is the one body (door + core, 0083's basket pattern). It calls
`voyage.fight_resolve` **once per wave**, with the haven's assault id as the seed uuid and the wave number as
the day — `fight_resolve(p_voyage, p_day, …)` is seeded on (uuid, int) and nothing in it reads the voyage row,
so this is a use, not an abuse; its comment is extended to say so. Each wave's raiders come from the one
builder `voyage.raider_hulls(…)` given the haven's defenders instead of a segment:

| Wave | Raiders (`p_raiders`) | What ends it |
|---|---|---|
| **1 · the guard** | the captain's fleet **less his flagship** (his `hulls[1..]`, at his `hull_pct`) | the fight's own outcome: EVADED / DRIVEN_OFF = the guard is beaten (for the attacker, EVADED here reads "they would not come out", and the assault goes on); RANSOM / PLUNDERED = **the attack fails** at this wave |
| **2 · the captain** | his flagship, **carrying his famous piece** (its `item_effects` count: Drake's culverins hit harder and further), plus **the shore battery**: one hull `{class 'battery', attack 60, accuracy 50, reach 70, armour 60, hull 1,500, crew 40, sighting 20}` that never breaks off and is never boarded | DRIVEN_OFF or EVADED = **cleared**; else failed |

The fight's standoff rule (`fight_standoff_ratio` 2.0, raiders do not close on a fleet twice their
strength) is passed as 0 for an assault: a defender in his harbour does not stand off. The sighting round is
kept (the attacker may get the first broadside). Hull loss on both sides is the fight's own (lit since 0204);
crew loss by `raid_crew_lost` for the attacker's outcome; a failed attack costs what a lost raid costs
(PLUNDERED's crew −10 %) **and no cargo** (there is no cargo to take from an attacker who withdraws; DEFAULT,
§9 Q5). The fleet stays anchored off the haven, free to REPAIR nowhere (a haven has no yard) and SAIL away.

**The report.** One History event `ATTACK_REPORT` with `{haven, captain, waves: [{line, rounds}], outcome,
loot}` — `waves` in the same shape as the voyage report's `fights`, so the History tray's `payloadFights`
reader prints each wave under its line with no new reader. A real one would read:

```
● 14:22  PONENTE — ATTACK · Djerba
  Wave 1. Four sail came out of the creek to meet us.
    Ready for them: Bom Jesus (Broadside Guns), Santa Clara (Chase Guns).
    We saw them first.
    Round 1 · long range — you hit with 3 of 5 shots; they cannot reach you.
    Round 2 · long range — you hit with 2 of 5 shots; they cannot reach you. The guard is 34% damaged.
    …
    They broke off and ran for the harbour.
  Wave 2. Turgut Reis came out himself, and the battery on the point opened on us.
    Round 1 · long range — you hit with 2 of 5 shots; the battery hits Bom Jesus for 4% damage (armour turned 2%).
    …
    Close quarters: your 164 crew against his 70. You carry his deck.
  ── taken from the haven ─────────────────────────────────────
  Turgut Reis Swivels        fitted to no ship · in storage at Djerba
  hoard                      +11,240 🪙
  Battle Honour × 2          in storage at Djerba
  freed captives             +9 crew (Bom Jesus 104 / 140)
  damage                     Bom Jesus 92% → 71% · Santa Clara 88% → 80%
  crew lost                  3
```

Plain words throughout; every number with what it is out of (WORDS law 2).

### 4.5 Loot [DEFAULT Z-J]

The loot table is data (`haven_loot (haven, item_code, chance, wave)`), authored in `data/pirates.json`.

| What | Rule | Why bounded |
|---|---|---|
| **The hoard** (money) | `pirate_hoards (haven_port_id, ducats)` grows by `hoard_share` (0.5) of every RANSOM and of the mid-price value of every PLUNDERED cargo that this zone's raids took — from merchants and players alike — written by the PIRATES arm beside the loss it already writes. On a clear the attacker is paid `hoard_payout` (0.6) of it, at least `hoard_floor` (2,000) and at most `hoard_cap` (60,000); the rest is lost (the pirates spent it). A ledger row `LOOT`, event `ATTACK_REPORT`. | It is money that left the economy coming back, less half. The floor is the only new money: ≤ 9 × 2,000 per 72 h world-wide (§6). |
| **The captain's famous piece** | On wave 2 cleared: chance `famous_drop_base` (0.25) + `famous_drop_pity` (0.25) × this company's clears of this haven since its last piece (`haven_runs (player, haven, clears_since_piece)`), so the 4th clear is certain. The piece lands in `player_items` **at the haven** (items have a location, 0068); FIT it there, or come back for it. **One of each to a company**: `public.famous_held` (0165) is extended from hulls to pieces; a company that holds the piece (fitted, in storage anywhere, or on a famous hull) is rolled for gold instead. | 9 havens / 72 h → at most 3 pieces a day in the whole world; a company can hold 11 ever; nothing converts a piece to money (no P2P trade, SCRAP refunds hull value only). |
| **Battle Honours** | 1 for wave 1, 2 for wave 2 (K8's `battle-honour` item, into storage at the haven) — the Combat promotion item the owner asked for (*"items … gained in act of pirating"*). | Items with one use (promotion), no resale. |
| **Freed captives** | crew up to the fleet's free `crew_max`, `captives_per_wave` (0–6 drawn), as a HIRED-shaped event with no cost. | Crew are a cost to keep (wages, supplies); no money. |
| **Combat experience** | `fight_points` gains a `HAVEN_CLEARED` row (30, twice DRIVEN_OFF) read by the same `voyage_xp_tracks` / company Combat track. | Points, not money. |

What is **not** looted: ships (no hull is ever taken, §9 Q2), cargo (pirates hold no goods the game tracks),
and nothing of any other player's.

### 4.6 Cooldown, respawn, and the zone after a clear [DEFAULT Z-K]

- `pirate_havens (haven_port_id PK, captain_code, cleared_at, cleared_by, clears int)` is the haven's state.
- **Cleared** sets `cleared_at`, pays the loot, zeroes the hoard, and puts the captain's fleet `retreat_until
  = cleared_at + haven_respawn_hours` (72 real hours = 3 game months on the calendar clock; a season).
- **While cleared:** the zone's seas carry `−haven_cleared_relief` pressure (§2.2); ATTACK is refused
  `E_HAVEN_CLEARED`; the Codex and the map say *"Cleared 2 days ago"*; the captain is in no sea.
- **Respawn:** at `cleared_at + 72 h` the captain is back at full hull with his fleet rebuilt (data, not
  state: `hulls` is authored), the hoard at `hoard_floor`, the haven attackable. The same captain returns
  (DEFAULT; a roster of successors is a data extension, §9 Q8).
- **Per-company:** no lockout beyond the shared respawn. Whoever clears first takes the hoard; the next
  company waits 72 hours. That is a race through a shared world (DESIGN J.1), not PvP.

---

## 5. Escort contracts

### 5.1 Who offers them, and what for [DEFAULT Z-L]

**The city posts them**, on the **Requests** face the desk already has (COMMAND_DESK §2.2; `world.contracts`,
0087). The city has the interest (its trade) and the purse (0172: millions). A request is posted when a
**merchant fleet docked here is about to sail a leg whose frozen danger would be Dangerous or worse** — the
merchant executor knows her next leg at plan time (`npc_plan`, 0120), so `tick_contracts` (the one writer of
the board, 0087) gains a second kind of row:

```
escort_contracts (id, port_id, merchant_fleet_id, dest_port_id, posted_at, leaves_by, fee_ducats,
                  status: open | accepted | under_way | paid | failed | expired,
                  escort_fleet_id, accepted_at, voyage_id, settled_at)
```

The board row reads: *"Escort · Casa da Índia's **Carreira** to Funchal · leaves within 25 min · through the
Barbary coast (Dangerous) · 1,840 🪙"*. One per merchant fleet; at most `escort_posts_per_day` (2) per port
per game day; it expires when she sails without you.

**Fee:** `escort_fee_pct` (0.03) × the mid-price value of her cargo at posting, clamped to
[`escort_fee_min` 300, `escort_fee_max` 5,000], times `escort_danger_mult[word]` (Dangerous 1, Severe 1.3,
Deadly 1.6). Escrowed from the city purse at posting, like a request's premium (0087's pattern), released
back on expiry or failure.

### 5.2 The obligation — sailing in company

`cmd.accept_escort(contract, fleet)` (door; core `public.accept_escort_for`): your fleet is docked at the
port, has attack > 0, and has an empty queue or a queue whose head is nothing but this (the contract holds
the fleet: its queue shows one line, *"Waiting to sail with Carreira · leaves within 25 min"*). Then:

- **When she departs** (the merchant executor's `voyage.depart` for her fleet), one hunk: if an accepted
  contract names her, **your fleet departs with her** on the same course at the convoy's speed — the slower
  of the two, passed to `voyage.depart` as a speed cap (one new optional argument, null = today) — so the
  two voyages have the same `eta`. Her voyage records `escort_fleet_id`; yours records `convoy_of = her
  voyage` and freezes its segments with **PIRATES danger 0**: a convoy is raided once, on her voyage.
- **Her PIRATES days are fought with both fleets:** `voyage.fight`'s hull gathering (0189:498) adds the
  escort's hulls when `escort_fleet_id` is set — one hunk, one builder. Hull loss is written to the hull
  that took it, on whichever fleet. Her storms and calms are hers; yours are yours (your voyage still rolls
  its own weather).
- **Arrival:** `voyage.settle`'s arrival arm, on her voyage with an escort: if no raid ended RANSOM or
  PLUNDERED, the contract is `paid` — the escrow goes to you (`ESCORT_FEE` ledger row, event `ESCORTED`);
  if a raid ended RANSOM, half; if PLUNDERED, `failed` and the escrow returns to the city. Your captains and
  the company's Combat track earn the same `fight_points` the fights earned.

### 5.3 Failure, said plainly

| What happened | Contract | You |
|---|---|---|
| she sailed before you accepted / you were not docked | `expired` | nothing |
| you accepted, then CLEARed or SAILed your fleet away before she left | `failed` | nothing; no penalty beyond the lost fee (DEFAULT; §9 Q9) |
| she was plundered in company | `failed` | nothing; your hull and crew losses are yours; History says so |
| she paid a ransom in company | `paid` at half | half the fee |
| she arrived whole | `paid` | the fee; Battle Honours for any fight won |

Merchants gain nothing new here beyond a real escort: no merchant pays, no merchant's route changes, no
merchant waits for an escort (she sails when her plan says; the contract's `leaves_by` is her plan's
departure, read, not promised).

---

## 6. Economy and balance (post-0208)

**The money the players have.** Post-0208 a starter has 40,000 🪙 and makes about 18 % of the stake on a
first voyage (dev-log 2026-10-19-economy §4); merchant lap nets have a median of 46 🪙 and 36 % of laps close
at or below zero; ship prices are unchanged (barca 12,000, caravela 26,000, nau 120,000, galleon 150,000;
Golden Hind 118,000). A laden barca (180 t) carries roughly 3,000–5,000 🪙 of cargo at the new prices; a
laden nau (1,200 t) 25,000–60,000.

**Faucets and sinks this design adds:**

| Flow | Direction | Size, expected | Bound |
|---|---|---|---|
| Hoard payout | faucet, but **recycled**: the hoard is money raids already removed (RANSOM 8 % of cargo value; PLUNDERED cargo at mid) × 0.5 | prod rolls ~118 PIRATES days a day (236 in ~55 h, dev-log auto-fight §0202); ~25 % end RANSOM/PLUNDERED → ~30 takes a day world-wide; at ~1,500 🪙 a take → ~45,000 🪙/day into all hoards, ~5,000 a haven a day. A haven cleared every 3 days pays ~0.6 × 15,000 ≈ **9,000 🪙** | cap 60,000; floor 2,000 (the only new money: ≤ 18,000 🪙 per 72 h world-wide, ≈ 0.1 % of what merchants turn over) |
| Famous pieces | item faucet | ≤ 3 a day world-wide (9 havens / 72 h); with the pity rule a company needs ≤ 4 clears (≤ 12 days) for a given piece | one of each per company; no resale; 11 exist |
| Battle Honours | item faucet | a few a day; the K8 promotion sink consumes 10 / 20 / 40 | one use |
| Freed crew | small faucet | 0–6 crew a wave | wages and supplies are a sink per day |
| Escort fees | faucet from city purses | 3 % of escorted cargo, 300–5,000; ≤ 2 posts a port a game day in zone ports (~30 ports) → at most ~60 contracts a day, realistically a dozen accepted → ~15,000 🪙/day | escrowed, clamped, cities have millions (0172) and already pay request premiums (0087: 1.80 M open on prod at 0208) |
| Insurance premiums | sink, into city purses | the insurance design's; it offsets escort fees from the same purses | — |
| Repairs after fights | sink | REPAIR orders doubled when the fight was lit (dev-log auto-fight §Live) | the hull a fight takes is measured and bounded (lost ≤ 32.1 %, crew ≤ 7.48 % per raid, 0202) |
| Hull, crew, supplies, time on the way to a haven | sink | a haven is off the trade routes by construction (its spur leg) | — |

**What an assault should cost to win.** Tuned by the existing simulator (`fight/sim.mjs`, the 0189 method)
before Z5 is lit, to these targets (DEFAULT): a lone nau with Broadside Guns clears a danger-3 haven (Djerba,
Qeshm, Senj) about half the time and loses ~15 % hull doing it; a danger-4 haven (Tortuga, Kottakkal,
Shuangyu) wants two armed naus or a galleon; Lingga (danger 5) wants a galleon pair or three naus. An
unarmed fleet is refused at the door (`E_NO_GUNS`), never sent to lose. Measured, not reasoned: the sim
replays each haven 500 times against production's real fleets exported read-only, and the dev-log prints the
clear rate by fleet band before the switch is thrown.

**No flood, stated as rules the self-asserts can check:** the hoard is paid only from `pirate_hoards`
(no payout exceeds the row's balance + floor); a famous piece is inserted only by `cmd.run_attack` and only
when `famous_held` is null for that piece; a captain's `retreat_until` is set on every clear; the escrow row
balances (Σ escrowed = Σ open contracts' fees), the 0087 invariant.

---

## 7. The data model and the verb surface

### 7.1 Tables (sketch)

```
-- authored data, held by the world guard (data/pirates.json, data/seas.json)
pirate_zones     (zone_code, sea_code)                                  -- which seas a captain roams
pirate_captains  (code PK, name, zone_code, haven_port_id → ports, flagship_class, famous_item_code → item_kinds,
                  hulls jsonb, blurb)
haven_loot       (haven_port_id, item_code, wave, chance)

-- live state, server-written only
sea_pressure     (sea_id PK, value numeric, updated_at)                 -- wins, decaying; presence and relief are derived
pirate_fleets    (captain_code PK, hull_pct, retreat_until, beaten_count, updated_at)
pirate_havens    (haven_port_id PK, captain_code, cleared_at, cleared_by → players, clears)
pirate_hoards    (haven_port_id PK, ducats bigint)
haven_known      (player_id, haven_port_id, learned_at, how)            -- PK (player_id, haven_port_id)
haven_runs       (player_id, haven_port_id, clears_since_piece)
escort_contracts (id, port_id, merchant_fleet_id, dest_port_id, posted_at, leaves_by, fee_ducats, status,
                  escort_fleet_id, accepted_at, voyage_id, settled_at)

-- columns added to rows that exist
ports.kind                 gains 'HAVEN' (beside 'HARBOUR', 'SEA_PLACE'; 0036)
voyages.segments[]         gain  danger numeric, raiders text (captain code or null)   -- frozen at depart
voyages.escort_fleet_id    uuid null ;  voyages.convoy_of uuid null
```

RLS on every table; no client role may read or write any of them directly. The doors are below. Every
event is an `events` row; every coin an append-only ledger row (`LOOT`, `ESCORT_FEE`); nothing stores a
total that the ledger does not derive.

### 7.2 Functions, and which existing authority each composes

| Concept | ONE home | Composes (does not fork) | Read by |
|---|---|---|---|
| how dangerous a sea is now | `voyage.sea_danger(sea, at)` | `seas.piracy_index`; `pirate_fleets`, `pirate_havens`, `sea_pressure` | `voyage.depart` (freeze), `world.sea_danger()`, `voyage.risk_quote` |
| what a sea breeds | `voyage.sea_mix(sea, danger)` (0055, re-cut to take the frozen figure) | — | `voyage.hazard_roll` |
| where a captain is | `voyage.pirate_sea(captain, game_day)` | `voyage.rng_raw` (0006), `world.game_day` | `sea_danger`, `voyage.depart` |
| the raiders as hulls | `voyage.raider_hulls(voyage, day)` / `(haven, wave)` | `ship_classes`, `item_effects`, `fight_raider_class` — the xebec building moved out of `fight_resolve` | `voyage.fight`, `cmd.run_attack` |
| the fight | `voyage.fight_resolve(seed, round, raiders jsonb, escort, ships)` (0189, one re-cut: strength → hulls) | unchanged otherwise | `voyage.fight`, `cmd.run_attack` |
| a fleet's raid | `voyage.fight(voyage, day, fleet, …)` (0189) | + the escort's hulls when `escort_fleet_id` | `voyage.settle` |
| what a raid writes back | the PIRATES arm of `voyage.settle` (one hunk) | `pirate_fleets.hull_pct`, `sea_pressure`, `pirate_hoards` | — |
| learning a haven | `public.learn_haven_for(player, haven, how)` | — | the PIRATES arm (pursuit), `world.inn` (rumour) |
| the assault | `cmd.run_attack(fleet)` core; `cmd.attack` / `cmd.preview_attack` skins | `fight_resolve` per wave, `raid_crew_lost`, `fight_points`, `player_items` (0068), `famous_held` (0165), the ledger | the composer, the map's haven panel |
| escorts | `public.tick_contracts` (0087, gains the escort kind); `cmd.accept_escort`; one hunk in `voyage.depart`; one in `settle`'s arrival arm | `world.contracts` (the board), the city purse escrow (0087), `voyage.depart` (speed cap) | the Requests face |
| the risk a voyage runs (insurance) | `voyage.risk_quote(plan or voyage)` | `hazard_base`, `hazard_mult`, `sea_mix`, the fight's measured outcome shares (a knob table `fight_outcome_shares_by_band`, filled from the dev-log's measurement and re-measured after Z3) | the insurance quote, the desk's plan line |
| the map's read | `world.sea_danger()` → `[{sea_code, word, reason}]` | `sea_danger` | the chart (shade), the detail panel |
| the Codex's read | `world.havens()` → the known havens with captain, state, blurb | `haven_known`, `pirate_havens` | Codex, map |

**Guards written with the slices** (NO_SPAGHETTI §7B q4): a second reader of `piracy_index` (token scan,
positive control); a second writer of `pirate_hoards` / `pirate_fleets` / `haven_known` beside the named
one (scan of live bodies for the insert/update token); a famous piece inserted into `player_items` by any
body but `cmd.run_attack` while `item_unmade` still holds it; `fight_resolve` reading any table (it must
stay a pure function of its arguments — its body may name no relation but `world_config`).

### 7.3 Client

- **COMMAND**: ATTACK on the verb pad (only offered when the fleet lies at a known haven); Requests face
  rows for escorts with **Escort** as the button; the queue's *"Waiting to sail with …"* line.
- **MAP**: the sea shade; the detail panel's danger line; haven glyph; the haven panel's one action.
- **HISTORY**: `ATTACK_REPORT` and `ESCORTED` headlines; the waves under their lines through
  `payloadFights` (no new reader).
- **CODEX**: a **Pirate havens** group under Places.
- **Words**: the rows in §4.3, added to `docs/WORDS.md` and `tests/words.spec.ts` by the slice that first
  prints them.

Nothing on the client decides anything: it prints the served word, the served sides, the served report.

---

## 8. Build order — seven slices, each dark then lit

Sizes: **S** ≤ half a day of one agent (one PR), **M** one day (one migration PR + one client PR), **L**
two days. Every migration slice follows the house method: pre-images, hunks that occur exactly once and
reverse, self-asserts that count their own rows, a prod-shaped apply, a 30-minute after-check with bounds
and a forward rollback (`docs/dev-log/2026-10-18-auto-fight.md` is the template).

| # | Slice | Lands dark as | Lit by | Window and bounds | Size |
|---|---|---|---|---|---|
| **Z1** | **Danger is one number.** `sea_pressure`, `voyage.sea_danger`, segments frozen with `danger`, `sea_mix(sea, danger)` and the PIRATES arm re-cut to read the frozen figure; `world.sea_danger()`; `voyage.risk_quote` (the insurance interface). | parity: `sea_danger = piracy_index` for all 51 seas; a probe passage settled by the old body and the new is byte-equal; no body but `sea_danger` reads `piracy_index` | nothing to light — it changes no answer | arrivals avg ≤ 3 s, p95 < 5 s (the hunk adds one column read per segment) | **M** |
| **Z2** | **The map shows it.** Sea shade by band; the detail panel's line; the desk's plan word; `data/seas.json` re-authored to §2.1 (danger/piracy rows) with the world guard. | client only + a data migration (the `seas` UPDATE is a rule change for raids and is lit the moment it lands) | the data row itself | PIRATES days by sea for 24 h: the nine zones' share rises, the rest holds; lost share within 0202's bound | **S** + data |
| **Z3** | **Pirate fleets.** `pirate_zones`, `pirate_captains`, `pirate_fleets`; `voyage.pirate_sea`; `raider_hulls` lifted out of `fight_resolve` (hulls in, strength out); presence in `sea_danger`; depart freezes `raiders`; the PIRATES arm names him, hurts him, writes `sea_pressure` and `pirate_hoards`. | `pirates_bite` false: no captain is in any sea; `raider_hulls` builds today's xebecs; 0202's 960-day probe fights word for word | `pirates_bite` true | the paired raid check (`paired.sql`, 0202's method) on raids against named captains: lost ≤ dark + 5 pts, crew ≤ dark + 1 pt; arrivals bound; hoards grow only from recorded takes | **L** |
| **Z4** | **Havens as places.** Nine `ports` rows kind HAVEN with spur legs; `pirate_havens`, `haven_known`, `learn_haven_for`; `E_UNKNOWN_PLACE` in `sail_refusal`; the inn rumour line; *"They ran for …"*; `world.havens()`; the map glyph and Codex group. | `havens_bite` false: no haven is learnable (rumour chance 0, no pursuit line), so none appears or is sailable; every SAIL answer is today's | `havens_bite` true | SAIL refusals by code for 30 min (no new refusal but `E_UNKNOWN_PLACE`); inn reads' cost unchanged (+1 read) | **M** |
| **Z5** | **ATTACK.** `cmd.attack` / `preview_attack` / `run_attack`; waves through `fight_resolve`; `haven_loot`, `pirate_hoards` payout, the famous piece through `famous_held` extended to pieces, Battle Honours, captives; `ATTACK_REPORT`; relief and respawn; the verb pad and the haven panel. **The sim runs first** (§6's targets, printed in the dev-log). | `attack_bite` false: the door refuses `E_NOT_IN_USE` (*"Havens cannot be attacked yet."*); no row can be written | `attack_bite` true | every ATTACK_REPORT in the window: loot ≤ hoard + floor, ≤ 1 famous piece, `famous_held` honoured; clears per haven ≤ 1 per 72 h; arrivals bound (the verb is synchronous, not in the sweep) | **L** |
| **Z6** | **Escort contracts.** `escort_contracts`; `tick_contracts`' escort kind; `cmd.accept_escort`; `voyage.depart`'s speed cap and convoy hunk; `voyage.fight`'s escort hulls; the arrival arm's pay / fail; the Requests rows and the queue line. | `escorts_bite` false: no row posted, so nothing to accept; `depart`'s hunk is a no-op without a contract | `escorts_bite` true | escrow balances every minute; merchants' lap nets not lower (their speed is capped only when escorted); arrivals bound | **L** |
| **Z7** | **Insurance hook-up** (with the insurance slice): the premium reads `voyage.risk_quote`; the payout reads the frozen `danger`; merchants' refound replaced per that design. | — | that design's switch | that design's | **S** here |

Order of deploy: Z1 → Z2 → Z3 → Z4 → Z5 → Z6; Z7 when insurance lands. Z2's client and Z4's client can be
built in parallel worktrees while Z1 and Z3 deploy. Nothing lights before the previous slice's window has
held; a broken bound is a forward rollback of that slice's switch, and nothing written lit becomes
unreadable dark (reports keep their rounds; a learned haven stays learned; a hoard keeps its balance).

**Total:** about seven working days of one agent, or four with two worktrees.

---

## 9. Open questions for the owner, each with a recommended default

| # | Question | **Default (built unless you say otherwise)** | If you say no |
|---|---|---|---|
| **Q1** | Should pirate fleets be drawn on the map, like merchants? | **No.** A captain is in a sea, not at a point; the sea's shade and the panel's line say he is there. A hull would make the chart a thing to steer around. | Draw him at his sea's centroid as a hull in `loss` ink; a tap opens his card. One client slice. |
| **Q2** | May pirates ever take a ship (an attacker's or a raided fleet's)? | **No.** DESIGN B.6 stands: the flagship is never taken, and 0189 left "ship taken" unbuilt on purpose. The worst case stays expensive, not fatal. | A TAKEN outcome below PLUNDERED for a non-flagship hull: one band in `fight_board_bands`, one hunk, and the hull's gear and captains go with it. |
| **Q3** | How often does a cleared haven come back? | **72 real hours** (one game season), with its zone at half danger meanwhile. | 24 h (more loot, more flood) or 7 days (a cleared zone stays safe a week). One knob. |
| **Q4** | Should a rumour at the inn cost money? | **Free**, 35 % chance per shift in a zone city. | A price (say 500 🪙) and a certainty: *"Buy the word"*. One knob and one button. |
| **Q5** | What does a failed attack cost? | **Hull by the fight, crew −10 %, no cargo**, and a 30-minute cooldown before trying again. | Add cargo loss (PLUNDERED's 25–50 %) — harsh for an attacker who carries trade goods to the fight. |
| **Q6** | Who can attack? | **Any fleet with a gun.** No title, level or skill gate (you have reversed every gate I invented; the fight's own odds are the gate). | A Combat level or Gunnery skill gate: one `E_` code in the door. |
| **Q7** | Which famous piece does each haven drop? | **§3.1's table**: Turgut Reis Swivels at Djerba, Drake's Culverins and the San Martín Tercio Arms at Tortuga, Zheng He Bulkheads at Shuangyu, Dragon-head Cannon and Date Masamune Charts at Gotō, Duodo Bow Guns and La Couronne Battery at Senj, Batavia Double Planking at Lingga, Rahimi Pilgrim Holds at Kottakkal, Madre de Deus Holds at Salé; **Qeshm drops no piece and pays the biggest hoard.** | Any other mapping: it is one data file. |
| **Q8** | After a clear, does the same captain return? | **Yes**, the same name, at full strength. | A roster of successors per haven (Turgut → Uluç Ali → Murat), each a data row. |
| **Q9** | Is there a penalty for abandoning an accepted escort? | **No**, beyond the lost fee. | A cooldown before the next contract, or a standing score with cities (would need a new concept). |
| **Q10** | Should danger raise the price of goods that come through it? | **No.** The distance premium (0173) already pays for far water; insurance prices the risk directly. | A hazard term in `mid_from_terms` — a PRICE_FACTORS slice, not this design's. |
| **Q11** | Do merchants meet named captains and fund the hoards? | **Yes.** They sail the same engine; insurance (the parallel design) keeps them whole. | Exempt merchants from named captains (anonymous raiders only): one `is_npc` read in `raider_hulls` — a second spelling of "merchant" I would rather not add. |
| **Q12** | Hoard payout share and cap? | **60 % of the hoard, floor 2,000, cap 60,000.** | Other knobs; the floor is the only new money and can be 0. |

---

## 10. What this design deliberately does not do

- No new combat, no battle board, nothing drawn fighting. Every fight is `voyage.fight_resolve`.
- No zone geometry, no zone editor, no client-writable row. The zone is the sea the game has.
- No pirate company: a captain has no purse, no route, no trade, and costs the arrivals sweep nothing.
- No gate on who may attack or escort beyond the fight's own odds and "has a gun".
- No PvP: havens are a race through a shared world, like markets; no player's fleet is ever a target.
- No new money beyond the hoard floor; famous gear is the faucet, and it is capped three ways.
- No second danger scale: `piracy_index` keeps one reader, and insurance reads the same frozen number the
  raid rolls.
