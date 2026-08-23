# byeharu-voyage — Game Design Document

**Status:** v1.0 design, 2026-08-18. Buildable spec.
**Research basis:** `docs/DESIGN_RESEARCH.md` — every claim about *Uncharted Waters Origin* is cited there
with a source-quality marker. Where Origin publishes no numbers, this document says so and the number is
ours, not theirs.
**Core reuse:** the byeharu stack — React 19 + Vite + TypeScript + Tailwind 4 + Zustand + Supabase,
server-authoritative RPCs, ordered migration chain, CI apply-proof.

### The eight laws

These come from the owner's brief and override anything else in this document.

1. **Words, not pixels.** Every screen is text, tables and lists.
2. **Commands live on their own tab.** All player agency is exercised there.
3. **The map is an output device.** It renders position and heading. It never accepts input.
4. **No visual combat, ever.** Danger resolves server-side and is reported as written prose.
5. **Fleets, plural.** Many ships, organised into many fleets, commanded simultaneously.
6. **Real world.** Real countries, real ports, real coordinates, real goods, 1500–1650.
7. **City investment and rank are first-class**, not side content.
8. **Server-authoritative.** Every state change is an RPC. Time passes on the server. A fleet at sea keeps
   sailing while the player is offline.

---

## A. The pitch

You are a trading house of the Age of Sail: you own ships, you group them into fleets, and you tell those
fleets what to do in written orders that the server carries out while you are gone. A session is five
minutes of reading — check which fleets arrived, read the after-action reports, see that pepper is at 71%
of its neighbours in Calicut and 284% in Lisbon — and then two minutes of typing orders that will run for
the next four hours. Over a week you learn a route, then you learn the wind that makes it faster, then you
learn the season that makes it worthless, and you send three fleets on three different routes so that one
of them is always paying. Over a month you stop being a carrier and start being a power: you pour ducats
into Antwerp's Bureau until its Development Level lifts every price band you trade against, you climb the
title ladder by keeping Trade, Adventure and Naval fame in balance, and your name sits on the Antwerp
investors' board where every other player can see it. There is no battle to watch and nothing to click on
a map — the whole game is *knowing where the money is, and getting there before the other readers do*.

---

## B. The world model

### B.1 Entities

| Entity | What it is | Key fields |
|---|---|---|
| **Port** | A real historical port city | `code`, `name`, `country`, `nation_id`, `lat`, `lon`, `sea_id`, `region_id`, `culture`, `size_tier`, `dev_industry`, `dev_commerce`, `dev_military`, `languages[]`, `is_open_from` (year) |
| **Sea** | A named body of water | `code`, `name`, `hazard_base`, `wind_regime_id` |
| **Region** | Trade region, the unit that price-affinity is authored against | `code`, `name`, `sea_ids[]` |
| **Leg** | A curated sailing edge between two ports | `from_port`, `to_port`, `distance_nm`, `hazard_mult`, `wind_profile_id`, `min_year`, `notes` |
| **Nation** | One of eight powers | `code`, `name`, `capital_port`, `flag_char` |

**Nations (V1):** Portugal, Castile-Spain, England, France, Dutch Republic, Venice, Ottoman Empire, Ming.
Ports may also be `free` (unaligned) — free ports are the ones players' investment can flip (§H.5).

### B.2 Ports — the real cities

V0 ships twelve ports; V1 reaches ~40; V2 ~90. Coordinates are decimal degrees, WGS84, rounded to 0.01°.

> **Data provenance note.** These coordinates are the modern city centroids to 0.01° (~1.1 km), which is
> ample for a great-circle model. They are authored by hand here. At data-load time
> (`scripts/seed_ports.ts`) they must be reconciled against a geodata source and the seed asserts that no
> two ports are within 15 nm of each other and that every port's `lat/lon` falls in its declared sea's
> bounding box. Do not treat the table below as verified geodata until that seed check is green.

**V0 port set — Iberia, the Atlantic islands, the Maghreb, the western Mediterranean:**

| Code | Port | Country (1550) | Nation | Lat | Lon | Sea | Culture |
|---|---|---|---|---|---|---|---|
| `LIS` | Lisboa | Portugal | Portugal | 38.71 | −9.14 | Atlântico Ibérico | Latin |
| `OPO` | Porto | Portugal | Portugal | 41.15 | −8.61 | Atlântico Ibérico | Latin |
| `SVQ` | Sevilla | Castile | Spain | 37.39 | −5.99 | Atlântico Ibérico | Latin |
| `CAD` | Cádiz | Castile | Spain | 36.53 | −6.29 | Atlântico Ibérico | Latin |
| `CEU` | Ceuta | Portugal (to 1580) | Portugal | 35.89 | −5.32 | Strait of Gibraltar | Latin/Maghrebi |
| `SAF` | Safi | Morocco | free | 32.30 | −9.24 | Atlantic Morocco | Maghrebi |
| `FNC` | Funchal | Madeira, Portugal | Portugal | 32.65 | −16.91 | Atlantic Islands | Latin |
| `LPA` | Las Palmas | Canarias, Castile | Spain | 28.13 | −15.43 | Atlantic Islands | Latin |
| `MRS` | Marseille | France | France | 43.30 | 5.37 | Golfe du Lion | Latin |
| `GOA` | Genova | Republic of Genoa | free | 44.41 | 8.93 | Ligurian Sea | Latin |
| `TUN` | Tunis | Hafsid/Ottoman | Ottoman | 36.80 | 10.18 | Sicily Channel | Maghrebi |
| `NAP` | Napoli | Spanish Naples | Spain | 40.85 | 14.27 | Tyrrhenian Sea | Latin |

**V1 additions (~28):** Valencia, Barcelona, Palma, Palermo, Messina, Venezia, Ragusa, Athína (Piraeus),
İstanbul, İzmir, Alexandria, Tripoli, Alger, Bordeaux, Nantes, Brest, Bristol, London, Antwerpen,
Amsterdam, Hamburg, Lübeck, København, Bergen, Stockholm, Gdańsk, Rīga, Ribeira Grande (Cabo Verde).

**V2 additions (~50):** Dakar/Gorée, Elmina, São Tomé, Luanda, Santa Helena, Cidade do Cabo,
Ilha de Moçambique, Zanzibar, Mombasa, Aden, Mokha, Masqaṭ, Hurmuz, Basra, Surat, Diu, Goa, Calicut,
Cochin, Colombo, Masulipatnam, Chittagong, Malaca, Bantam, Ternate, Banda Neira, Manila, Macau,
Guangzhou, Quanzhou, Ningbo, Nagasaki, Sakai, Busan, Havana, Santo Domingo, San Juan, Cartagena de
Indias, Portobelo, Veracruz, Acapulco, Callao, Valparaíso, Salvador da Bahia, Recife, Rio de Janeiro,
Buenos Aires, Nieuw Amsterdam, Boston, St. John's.

### B.3 Distance and sailing time

**Distance** between two ports is the **great-circle (haversine) distance in nautical miles**:

```
R      = 3440.065 nm            -- mean Earth radius
Δφ     = φ2 − φ1                -- latitudes in radians
Δλ     = λ2 − λ1
a      = sin²(Δφ/2) + cos φ1 · cos φ2 · sin²(Δλ/2)
d_nm   = 2R · asin(√a)
```

Implemented once, in SQL, as `voyage.gc_distance_nm(lat1, lon1, lat2, lon2)` — **immutable, one authority,
never re-derived client-side.** The client may compute the same number for display only.

Great-circle distance ignores continents. We do not simulate coastlines; we simulate **legs**. A leg is a
curated edge in the `legs` table with a **`distance_nm` that may exceed the great-circle figure** where the
real route detours. Example: Lisboa→Malaca is 6,310 nm great-circle straight through Africa; as sailed, via
Las Palmas → Ribeira Grande → Santa Helena → Cidade do Cabo → Ilha de Moçambique → Goa → Calicut, it is
**11,736 nm**. The router never draws a line through land because it only ever composes authored legs.

**Routing.** `SAIL <fleet> TO <port> [VIA ...]` resolves to a path through the leg graph by Dijkstra on
`distance_nm`, honouring the fleet's endurance (§C.5) and any explicit `VIA` waypoints as hard
intermediate nodes. If no path exists within endurance, the order is rejected before it is queued (§F.5).

**Sailing time.** Everything reduces to one formula:

```
v_eff  = v_base × M_wind × M_hull × M_load × M_crew × M_officer × M_control     [knots]
v_fleet = min(v_eff over ships in fleet) × M_formation
t_sim_hours = Σ_legs ( leg.distance_nm / v_fleet_on_leg )
t_real_seconds = t_sim_hours × 3600 / TIME_COMPRESSION
```

with `TIME_COMPRESSION = 480` (§D).

| Modifier | Range | Source |
|---|---|---|
| `v_base` | 3.0 – 6.5 kn | ship class (§C.2) |
| `M_wind` | 0.70 – 1.30 | leg's wind profile × season × ship's sail rig (§B.5) |
| `M_hull` | 0.60 – 1.00 | `0.60 + 0.40 × (durability / max_durability)` |
| `M_load` | 0.75 – 1.00 | `1.00 − 0.25 × cargo_fill_fraction` |
| `M_crew` | 0.70 or 1.00 | `1.00` if crew ≥ ship's `crew_required`, else `0.70` |
| `M_officer` | 1.00 – 1.12 | fleet's aggregate Navigation expertise, `1 + 0.004 × nav_score` capped at 1.12 |
| `M_control` | 1.00 / 1.04 / 1.08 | your nation holds 50–99% / 100% of the destination region's investment score (§H.5). *Taken from Origin's +1/+2 sailing speed occupation bonus — `DESIGN_RESEARCH.md` §1.6.* |
| `M_formation` | 0.95 – 1.00 | `1.00` for ≤3 ships, `0.98` for 4–6, `0.95` for 7+ |

**Worked distances** (haversine, computed from the coordinate table):

| Leg | nm | @5 kn, sim days | @5 kn, real time |
|---|---|---|---|
| Lisboa → Cádiz | 188 | 1.6 | **4.7 min** |
| Cádiz → Ceuta | 61 | 0.5 | 1.5 min |
| Lisboa → Funchal | 525 | 4.4 | 13.1 min |
| Lisboa → Marseille | 712 | 5.9 | 17.8 min |
| Lisboa → Las Palmas | 709 | 5.9 | 17.7 min |
| Ceuta → Tunis | 751 | 6.3 | 18.8 min |
| Lisboa → Amsterdam | 1,007 | 8.4 | 25.2 min |
| Venezia → Alexandria | 1,185 | 9.9 | 29.6 min |
| Cádiz → Havana | 3,944 | 32.9 | **98.6 min** |
| Cidade do Cabo → Goa | 4,338 | 36.2 | 108.5 min |
| **Lisboa → Malaca, full Carreira da Índia (8 legs)** | **11,736** | **97.8** | **4 h 53 min** |

### B.4 Seasons and the calendar

There are **two clocks and they are deliberately different** (§D.3 justifies this).

- **Calendar clock:** 1 real day = 1 game month. A game year is 12 real days. Season boundaries land on
  game-month starts, i.e. every ~3 real days.
- **Voyage clock:** compressed 480×. 1 voyage-day = 3 real minutes.

Four seasons drive wind, hazard and a small number of goods:

| Season | Game months | Effects |
|---|---|---|
| Spring | Mar–May | Baseline. NE trades steady. |
| Summer | Jun–Aug | SW monsoon in the Indian Ocean (`M_wind` +0.25 eastbound, −0.20 westbound). Mediterranean calms: `M_wind` ×0.92. |
| Autumn | Sep–Nov | Caribbean hurricane window: `hazard_storm` ×2.2 in `Mar Caribe` and `Golfo de México`. |
| Winter | Dec–Feb | NE monsoon (reverses the summer bonus). North Sea and Baltic: `hazard_storm` ×1.8, and Baltic ports **close** (`is_ice_closed`) for one game month. |

Culture and season also gate goods, following Origin's rule that "certain items are unavailable by season
or culture, e.g. alcohol in Islamic regions" (`DESIGN_RESEARCH.md` §1.5). Implemented as
`port_good.availability_mask`.

### B.5 Wind

Wind is **never drawn and never steered**. It is a number that multiplies speed, and the player sees it as
a word and a percentage on the Map and Command tabs.

Each leg carries a `wind_profile_id` giving a prevailing bearing per season. Each ship has a rig:

| Rig | Tailwind | Beam / crosswind | Headwind (beating) |
|---|---|---|---|
| Square (carrack, galleon, fluyt) | ×1.30 | ×1.00 | ×0.72 |
| Lateen (caravela latina, dhow, xebec) | ×1.10 | ×1.15 | ×0.90 |
| Mixed (caravela redonda, junk) | ×1.20 | ×1.10 | ×0.82 |
| Oared (galley, turtle ship) | ×1.05 | ×1.05 | ×1.00, but −40% endurance |

*This split is lifted from Origin's `Vertical Sail` (crosswind) vs `Horizontal Sail` (tailwind) stats —
`DESIGN_RESEARCH.md` §1.3. It is the one wind model that is entirely a coefficient.*

`M_wind = rig_factor(angle between leg bearing and seasonal prevailing wind)`, computed **once per leg per
departure** and frozen for that voyage, so an ETA quoted at departure never moves. Predictability is worth
more than fidelity in a game the player reads twice a day.

### B.6 Danger — risk numbers, never a fight scene

**This is the section that replaces combat.** Nothing here renders. Everything here writes.

A voyage is divided into **checkpoints, one per voyage-day**. At each checkpoint the server rolls a hazard:

```
p_hazard(day) = clamp( sea.hazard_base
                     × leg.hazard_mult
                     × season_mult
                     × (1 − 0.35 × escort_score_norm)
                     × (1 − 0.20 × lookout_expertise_norm)
                     , 0.000, 0.060 )
```

Typical `sea.hazard_base` is 0.006–0.020 per voyage-day, so a 98-day Carreira runs roughly a 45–65% chance
of *at least one* incident — dangerous enough to matter, survivable enough to be worth doing.

**Determinism is a hard requirement.** The roll is:

```
rng = hash_seed( voyage_id || day_index || world_secret )
```

A pure function of the voyage and the day index — **not** of when the tick happened to run. This is what
makes offline correctness true rather than approximate: whether the server evaluates day 43 at the moment
it occurs or four hours later when the player opens the app, the outcome is byte-identical, and it can be
recomputed and audited forever.

**Hazard table:**

| Hazard | Trigger | Outcome, resolved server-side |
|---|---|---|
| `STORM` | weather roll | Durability −8…−25%; if `seaworthiness` < threshold, cargo jettison of 5–15% (heaviest goods first); +1.5 voyage-days |
| `CALM` | wind roll | Voyage extended 1–4 voyage-days; supplies consumed as normal |
| `LEAK` | hull condition | Durability −5%/day until a port; cargo spoilage 2%/day on perishables |
| `SCURVY` | provisions quality, >30 voyage-days at sea | Crew −3…−8%; `M_crew` may drop to 0.70 |
| `SHORT_RATIONS` | food or water < 15% remaining | Crew morale −20; wages ×1.5 to hold them |
| `STARVATION` | food or water = 0 | Crew −10%/voyage-day; at crew < `crew_required/2`, fleet becomes **ADRIFT** |
| `PIRATES` | sea's piracy index | **Resolved instantly against `escort_score`.** Outcome drawn from the table below |
| `REEF` | uncharted leg, low `Scouting` | Durability −15…−40%; small chance one non-flagship ship is lost |

**Pirate outcome table** — the *entire* combat system:

| `escort_score` vs raider strength | Outcome | Report reads |
|---|---|---|
| ≥ 2.0× | `EVADED` | "Sighted three sail off the Barbary coast at dawn. They stood off and did not close." |
| 1.2 – 2.0× | `DRIVEN_OFF` | Crew −2%, durability −5%. **+Naval Fame.** |
| 0.7 – 1.2× | `RANSOM` | −8% of cargo value in ducats, no ship lost |
| 0.3 – 0.7× | `PLUNDERED` | −25…−50% cargo (by value), crew −10%, durability −20% |
| < 0.3× | `TAKEN` | The **rearmost non-flagship ship** is lost with its cargo. If the fleet is a single ship, it is stripped: all cargo lost, crew −30%, and the fleet is set ADRIFT and towed to the nearest port |

```
escort_score = Σ_ships ( guns × 1.0 + crew × 0.02 + hull_class × 3 ) × (1 + 0.02 × naval_officer_score)
```

**The flagship is never captured.** This is a deliberate anti-frustration rule: a player who logs in to
find their account gutted does not log in again. The worst realistic case is expensive, not fatal — which
is also why the previous game's total-loss canary is a lesson encoded here rather than repeated.

**ADRIFT** is the one hard failure state, inherited from UW2's "run out of provisions and the game ends"
(`DESIGN_RESEARCH.md` §2.1) but declawed: an ADRIFT fleet does not die. It stops, its Ledger prints
`FLEET ADRIFT`, and after 6 real hours it is towed to the nearest port at a salvage cost of 30% of the
value of everything aboard. Losing a week of profit is a story; losing the account is a churn event.

---

## C. Ships and fleets

### C.1 The three-way triangle

Every hull is a point on the same triangle Origin, UW2 and UWO all use — **speed / cargo / protection**
(`DESIGN_RESEARCH.md` §1.3, §2.1, §2.2). A ship is good at one, adequate at a second, poor at the third.

### C.2 Ship classes (V0–V2)

`hold` in **tuns** (1 tun ≈ 954 L, the period cargo unit). `speed` in knots. `guns` = broadside pieces.

| Class | Family | Rig | Hold | Crew req / max | Speed | Durability | Guns | Draft | Role | Available |
|---|---|---|---|---|---|---|---|---|---|---|
| Barca | Western | Lateen | 60 | 8 / 20 | 5.0 | 400 | 0 | 1 | Starter coaster | V0 |
| Caravela latina | Western | Lateen | 90 | 12 / 30 | 6.0 | 550 | 2 | 1 | Fast explorer | V0 |
| Caravela redonda | Western | Mixed | 120 | 16 / 40 | 6.2 | 650 | 4 | 2 | Explorer/light trader | V0 |
| Nau / Carrack | Western | Square | 400 | 60 / 140 | 4.4 | 1,800 | 12 | 3 | Bulk ocean trader | V0 |
| Galleon | Western | Square | 550 | 90 / 220 | 4.8 | 2,600 | 30 | 3 | Armed treasure hauler | V1 |
| Fluyt | Western | Square | 500 | 24 / 60 | 5.2 | 1,500 | 4 | 2 | **Cheap crew** bulk carrier | V1 |
| Galley | Western | Oared | 80 | 90 / 180 | 3.6 | 900 | 6 | 1 | Mediterranean, wind-immune | V1 |
| Xebec | Western | Lateen | 140 | 30 / 80 | 6.5 | 800 | 10 | 1 | Fast Maghrebi escort | V1 |
| Pinnace | Western | Mixed | 70 | 10 / 26 | 6.3 | 500 | 2 | 1 | Dispatch / scouting | V1 |
| East Indiaman | Western | Square | 800 | 100 / 240 | 4.6 | 3,000 | 36 | 4 | Endgame Carreira hull | V2 |
| Dhow (baghlah) | Eastern | Lateen | 180 | 18 / 45 | 5.5 | 700 | 2 | 2 | Monsoon trader | V2 |
| Junk (fuchuan) | Eastern | Mixed | 600 | 40 / 110 | 4.5 | 2,000 | 8 | 3 | East-Asian bulk, storm-hard | V2 |
| Panokseon | Eastern | Oared | 150 | 80 / 160 | 3.8 | 1,900 | 20 | 2 | Coastal Joseon warship | V2 |
| Geobukseon (turtle ship) | Eastern | Oared | 90 | 100 / 160 | 3.2 | 2,800 | 24 | 2 | Extreme escort, tiny hold | V2 |
| Kobaya / Sekibune | Eastern | Oared | 110 | 50 / 120 | 4.2 | 1,100 | 6 | 1 | Japanese coastal | V2 |

### C.3 Why each stat earns its place

Nothing is on this list unless a player decision hangs off it.

| Stat | Earns its place because |
|---|---|
| `hold` (tuns) | The *whole* economic decision. Every tun of water is a tun of pepper you did not carry. This one number creates the game's central tension. |
| `crew_required` / `crew_max` | Below required, `M_crew` = 0.70. Crew is also a per-day ducat cost and a per-day food/water cost, so a fluyt's low crew requirement is a genuine strategic edge — exactly why the real fluyt won the Baltic. |
| `speed` (kn) | Converts directly to real-world minutes of the player's life. The most legible stat in the game. |
| `durability` | The buffer that absorbs storms and pirates. **Flagship durability at 0 ⇒ the fleet cannot sail** (Origin's rule, `DESIGN_RESEARCH.md` §1.3). |
| `guns` | Feeds `escort_score` — the *only* combat number, and it is an input to a probability, never to a battle. |
| `draft` | Gates ports: `port.max_draft`. This is what makes a small ship permanently useful — Sevilla up the Guadalquivir and a hundred island ports refuse deep hulls. |
| `rig` | Selects the wind multiplier column (§B.5). Makes seasonal routing a real skill. |
| `seaworthiness` | Storm damage reduction, derived: `0.4·(durability/1000) + 0.6·(hold/500)`. Not authored per-ship; **derived so there is one authority.** |

**Deliberately absent:** cannon types, boarding strength, melee, ramming, ammunition, formation slots,
`Momentum`, `Ice Breaking`. All of these presuppose a combat or navigation engine we are not building
(`DESIGN_RESEARCH.md` §3.2 D1, D8). Ice survives as a *port closure flag*; rough water as a *leg modifier*.

### C.4 Fleet composition

- A **fleet** is 1–8 ships with exactly one **flagship**.
- A player's **Company Level** caps both fleets and total ships:

| Company LV | Max fleets | Max ships | Unlocked by |
|---|---|---|---|
| 1 | 1 | 2 | start |
| 2 | 2 | 4 | Title LV 2 |
| 3 | 3 | 7 | Title LV 3 |
| 4 | 3 | 10 | Title LV 5 |
| 5 | 4 | 14 | Title LV 7 |
| 6 | 5 | 18 | Title LV 9 |
| 7 | 6 | 24 | Title LV 11 |

*(Origin gates fleet size on Company LV but publishes no table — `DESIGN_RESEARCH.md` §4.1. This table is ours.)*

- **Fleet speed = the slowest ship**, then `M_formation`. One tired carrack ruins a fast squadron; that is
  the point of `SPLIT`.
- **Fleet endurance = the shortest-ranged ship.** Stores are pooled but each hull carries its own.
- **The flagship** contributes the fleet's officer bonuses, is never lost to pirates, and if its durability
  hits 0 the fleet is **UNABLE TO SAIL** until repaired.
- Fleets are **only** created, merged, split and re-flagged **in port**.

### C.5 Crew, provisions, wages

Per **voyage-day** (= 3 real minutes), per ship:

```
water_consumed = crew × 0.020 tuns
food_consumed  = crew × 0.015 tuns
wages_due      = crew × 1 ducat  × (1.5 if SHORT_RATIONS)
```

Origin/UWO's constant is 0.1 barrel each per sailor per day (`DESIGN_RESEARCH.md` §2.2 **[S]**). We use
0.020/0.015 tuns, **because at 0.1 a Carreira is physically unprovisionable** — which historically it very
nearly was, and which would make the game's flagship voyage impossible rather than hard.

**Endurance**, shown on every fleet row:

```
endurance_days = min over ships of  min( water_aboard / (crew × 0.020),
                                         food_aboard  / (crew × 0.015) )
```

Worked example — a Nau with 120 crew burns 2.40 tuns of water + 1.80 of food = **4.20 tuns/day**. Load 200
of its 400 tuns as stores and it has **47.6 voyage-days** of range, leaving 200 tuns for cargo. The
longest single leg on the Carreira (Ilha de Moçambique → Goa, 2,686 nm ≈ 22.4 days at 5 kn) fits with
comfortable margin; the direct Cape → Goa run (4,338 nm ≈ 36.2 days) fits but leaves little slack for a
`CALM`. **This is the game.**

`SAIL` refuses to queue if `endurance_days < leg_days × 1.15` (a 15% safety margin), and says so (§F.5).

### C.6 Officers

Officers ("mates" in Origin) are hired at a port's Inn with **ducats and reputation only** — no gacha, no
grades, no rank-up materials (`DESIGN_RESEARCH.md` §3.2 D6). Each officer holds one job and a small vector
of expertise, and each expertise is literally a coefficient in a formula defined elsewhere in this document:

| Expertise | Feeds |
|---|---|
| `purchasing` | buy-side discount, §G.4 |
| `sales` | sell-side surcharge, §G.4 |
| `negotiation` | chance and size of a price-negotiation event, §G.5 |
| `navigation` | `M_officer`, §B.3 |
| `supply` | reduces water/food consumption by up to 20% |
| `scouting` | reduces `REEF` and improves survey yield, §B.6 |
| `gunnery` | `escort_score` multiplier, §B.6 |
| `medicine` | reduces `SCURVY` incidence and crew loss |

Officers are assigned to a **ship**, and their expertise applies to the **fleet** only when assigned to the
flagship; on a non-flagship it applies at 50%. *(Origin's compatible-cabin rule at −50%, simplified —
`DESIGN_RESEARCH.md` §1.4.)* No loyalty timers (D4). No energy (D5).

---

## D. Time

### D.1 The two clocks

| Clock | Rate | Governs |
|---|---|---|
| **Voyage clock** | `TIME_COMPRESSION = 480` — **1 real minute = 8 voyage-hours; 1 voyage-day = 3 real minutes** | Sailing, provisions, wages, hazard checkpoints, exploration days |
| **Calendar clock** | **1 real day = 1 game month** (game year = 12 real days) | Season, wind regime, port ice closure, seasonal goods, investment season boundaries |

### D.2 Movement is closed-form; only events tick

This is the central architectural decision and it is what makes law 8 (server-authoritative, offline
progress) actually true rather than approximately true.

**A fleet's position is a pure function**, not a simulated state:

```
progress(t) = clamp( (t − departed_at) × TIME_COMPRESSION × v_fleet / 3600 , 0, total_nm )
```

`v_fleet` per leg is **frozen at departure** into `voyages.speed_profile jsonb`. Therefore:

- The client can render an exact position with zero server round-trips, at 60 fps if it wants, from one row.
- No tick can ever drift, stall or double-apply. There is no position to corrupt.
- A fleet that departs while the player sleeps arrives at exactly the right moment whether or not any job ran.

**Only discrete events need a tick**, and each is idempotent and keyed:

| Job | Cadence | Work |
|---|---|---|
| `tick_arrivals` | every 60 s (pg_cron) | For every voyage with `eta <= now()` and `status='SAILING'`: resolve all unresolved day-checkpoints, apply consumption, write the after-action report, dock the fleet, advance the order queue |
| `tick_market_drift` | every 10 min | OU drift step + stock regeneration for all `port_goods` (§G.2) |
| `tick_calendar` | every 60 min | Advance the game month if crossed; apply season flips |
| `tick_investment_week` | Monday 00:00 UTC | Award Mayor, pay dividends, roll the weekly window (§H) |
| `tick_investment_season` | quarterly | Season reset (§H.6) |

**Lazy catch-up:** every read RPC that touches a fleet first calls `voyage.settle(fleet_id)`, which resolves
any checkpoint whose deterministic time has passed. **A player who opens the app after 9 hours offline gets
identical results to one whose ticks all ran on time**, because the hazard RNG is seeded by
`(voyage_id, day_index, world_secret)` and not by wall-clock (§B.6). The cron job is an optimisation for
leaderboard freshness, not a correctness requirement. This is verified by a CI apply-proof test that
disables cron, sleeps a simulated interval, and asserts the settled state matches the ticked state exactly.

### D.3 Why two clocks

One clock cannot serve both. If the calendar ran at voyage speed (480×), a game year would elapse in 1.9
real days and seasons would flicker faster than a player could plan around. If voyages ran at calendar
speed, Lisboa → Malaca would take **92 real days**. The two demands are irreconcilable, so we separate them
and say so out loud in the UI: the Map tab prints `⏱ 1 min = 8 h sail` in its corner, permanently, so no
player ever has to reverse-engineer it. Sailing time is a *pace*; the calendar is a *rhythm*.

### D.4 The resulting cadence

| Voyage kind | Example | Real time | Session shape |
|---|---|---|---|
| Coastal hop | Lisboa → Cádiz, 188 nm | **4.7 min** | Do three while you sit there |
| Regional | Lisboa → Marseille, 712 nm | **17.8 min** | A commute |
| Sea crossing | Lisboa → Amsterdam, 1,007 nm | **25 min** | A lunch break |
| Ocean crossing | Cádiz → Havana, 3,944 nm | **1 h 39 min** | An evening |
| Grand voyage | Lisboa → Malaca, 11,736 nm | **4 h 53 min** | Overnight, or a working day |

The design intent is that a player should always have **at least one fleet due back within 15 minutes and
at least one that will not return today**. That is what makes multiple fleets (law 5) mechanically
necessary rather than decorative, and it is why the fleet-capacity table (§C.4) opens the second fleet slot
so early.

### D.5 What happens while the player is offline

Everything except issuing orders. The fleet sails, eats, pays wages, meets storms and pirates, arrives,
docks, and **executes the next order in its queue**. A queue of `SAIL → SELL → BUY → SAIL` runs to
completion unattended. The player returns to a stack of after-action reports and a changed balance. That
is the product.

---

## E. The tabs

Eight tabs. Bottom tab bar on mobile, left rail on desktop. Every tab is text; the Map tab is the single
exception and it renders geometry only.

```
┌───────────────────────────────────────────────────────────────┐
│  CMD   FLEETS   PORT   MARKET   MAP   LEDGER   RANK   ME      │
└───────────────────────────────────────────────────────────────┘
```

A **badge** on CMD shows fleets idle with an empty queue. A badge on LEDGER shows unread reports. Nothing
else animates.

### E.1 CMD — the command tab

The only tab that changes the world. Fully specified in §F.

```
╔═ CMD ═════════════════════════════════════ ducats 412,880 ═╗
║ > SAIL Ponente TO Calicut VIA Cidade do Cabo_               ║
║   ───────────────────────────────────────────────────────   ║
║   ✓ parsed   fleet=Ponente(3 ships)  8 legs  11,020 nm      ║
║   ETA 4h 12m real · 92.4 voyage-days · wind favourable      ║
║   stores 47.6 d endurance ▸ NEEDS 106 d  ✗ E_ENDURANCE      ║
║   fix: PROVISION Ponente FULL   (est. 8,240 d.)  [insert]   ║
║                                                             ║
║ ┌ verbs ──────────────────────────────────────────────────┐ ║
║ │ SAIL  BUY  SELL  LOAD  UNLOAD  PROVISION  HIRE  REPAIR  │ ║
║ │ INVEST  SPLIT  MERGE  DOCK  ANCHOR  RECALL  EXPLORE     │ ║
║ │ SURVEY  ASSIGN  FLAG  BUILD  CANCEL  CLEAR              │ ║
║ └─────────────────────────────────────────────────────────┘ ║
║                                                             ║
║ QUEUES                                                      ║
║  Ponente     [1] SAIL→Calicut        pending  ✎ ✕           ║
║  Aurora      [1] SAIL→Amsterdam      ACTIVE  eta 11m  ✕     ║
║              [2] SELL cloves 40                             ║
║              [3] BUY  copper 180 AT ≤34                     ║
║              [4] SAIL→Lisboa                                ║
║  Gaivota     — empty —                              ⚠       ║
╚═════════════════════════════════════════════════════════════╝
```

The verb pad makes every command **tappable**: tap `SAIL`, and the line becomes `SAIL ▸[fleet]` with a
picker; tap through fleet, `TO`, port, and the same string appears in the box that a desktop player would
have typed. **One grammar, two input methods** — never two code paths.

### E.2 FLEETS — the roster

```
╔═ FLEETS ═══════════════════════════════════════════════════╗
║ NAME      SHIPS  STATUS      WHERE            ETA    END.  ║
║ Ponente     3    DOCKED      Lisboa            —    47.6d  ║
║ Aurora      2    SAILING     → Amsterdam      11m   22.1d  ║
║ Gaivota     1    DOCKED      Cádiz             —     9.4d  ║
║ Levante     4    REPAIRING   Napoli          1h02m  31.0d  ║
║────────────────────────────────────────────────────────────║
║ ▾ Aurora — flag: Santa Clara (Caravela redonda)            ║
║   SHIP           CLASS      HULL   CREW   HOLD    LOAD     ║
║   Santa Clara ⚑  Car.red.   92%    34/40  120    98 (82%)  ║
║   Bom Jesus      Nau        71%   104/140 400   310 (78%)  ║
║   ── cargo ────────────────────────────────────────────    ║
║   cloves        40 t   avg cost 214 d.   →  8,560 d.       ║
║   porcelain     28 t   avg cost 480 d.   → 13,440 d.       ║
║   water        180 t  · food 150 t  · 22.1 days at present ║
║   ── officers ─────────────────────────────────────────    ║
║   Duarte Pires   navigator  nav 9  supply 4   ⚑flagship    ║
║   Beatriz Alves  factor     purch 7 sales 6   (50%: Bom J.)║
╚════════════════════════════════════════════════════════════╝
```

No commands here. Every row is a **read**; tapping a row copies its name into the CMD line.

### E.3 PORT — where you are

```
╔═ PORT · Lisboa ═══════════════ Portugal · Latin · draft 4 ═╗
║ Development   industry 12   commerce 17   military  8      ║
║ Nation share  Portugal 71%  Castile 12%  free 17%          ║
║ Mayor (wk 34) Casa Aveiro  ·  market tax 4.0%              ║
║ Your standing reputation 2,140 (Trusted) · tax you pay 3.0%║
║────────────────────────────────────────────────────────────║
║ HARBOUR   3 fleets docked · repair yard · max draft 4      ║
║ MARKET    38 goods · 4 specialties · see MARKET tab        ║
║ SHIPYARD  tier 3 — Nau, Caravela redonda, Fluyt, Pinnace   ║
║ INN       crew pool 240/400 · 6 officers seeking a berth   ║
║ BUREAU    invest ▸ min 50,000 d. · your total 1.20M        ║
║────────────────────────────────────────────────────────────║
║ SPECIALTIES  vinho do Porto · sal · azeite · cortiça       ║
║ LANGUAGES    Portuguese (you: fluent)                      ║
╚════════════════════════════════════════════════════════════╝
```

### E.4 MARKET — the reading room

The most important table in the game. It carries Origin's percent-of-neighbours convention wholesale
(`DESIGN_RESEARCH.md` §1.5), because it is what turns an economy into something a person can *read*.

```
╔═ MARKET · Lisboa ══════════════ prices vs ports within 600 nm ═╗
║ sort: [%↑] name  price  stock          filter: [all] buy sell  ║
║ GOOD          BUY    SELL    %NBR   STOCK   7-DAY      NOTE    ║
║ ▾ BUY  (< 90%)                                                 ║
║   sal          11      10     62%   ██████  ▃▃▂▂▁▂▂   specialty║
║   vinho        46      43     71%   ████░░  ▄▄▅▄▃▃▄   specialty║
║   cortiça      29      27     78%   █████░  ▂▃▃▄▃▂▂   specialty║
║ ▾ SELL (> 110%)                                                ║
║   pimenta     318     301    284%   ▓░░░░░  ▅▆▇█▇██   SOARING ↑║
║   cravo       690     652    241%   ▓░░░░░  ▆▆▇▇███            ║
║   porcelana   540     512    166%   ██░░░░  ▄▅▅▆▆▆▇            ║
║ ▾ hold                                                         ║
║   cobre        34      31     98%   ████░░  ▄▄▄▅▄▄▄            ║
║   trigo         8       7    104%   ██████  ▃▄▃▃▄▄▃            ║
║────────────────────────────────────────────────────────────────║
║ tax 3.0% (you) · spread 6% · daily cap per good 3,400 t        ║
║ tap a row → BUY/SELL prefilled on CMD                          ║
╚════════════════════════════════════════════════════════════════╝
```

`%NBR` is the whole game in one column: below 90 buy, above 110 sell, and the rest is your judgement.

### E.5 MAP — where things are, and the one place you can act on it

**Law 3 — AMENDED 2026-08-23. You act FROM this tab; you do not COMPOSE on it.**

This paragraph used to read: *"This tab has no interactive elements except pan, zoom and folding the two
corner panels. There is no command, no drag, no target, no context menu."* The tab printed that law to the
player as a permanent caption — **view only · orders on Command** — and the owner's verdict was that a map
you cannot act from is a picture: you could see your fleet lying in Lisbon and 214 harbours around her, and
to sail to one of them you had to remember its name, leave the tab, and find it in a list.

The old law protected the right thing and stated it as the wrong rule. **What must never be duplicated is
the COMPOSER, the GRAMMAR and the JUDGE** — one `features/command`, one `cmd.verb_schema()`, one
`cmd.preview()`. A tap that hands an INTENT to the composer duplicates none of the three. So:

- **Tapping a harbour selects it, and the detail panel offers ONE action: sail there.** It names an intent
  (`SAIL`, this port, the fleet the composer's draft already has in hand), asks `cmd.preview()` — the real
  verb, run and rolled back — what that exact line would do, prints the answer, and hands the intent to
  `domain/order`'s draft before going to COMMAND, which composes it. That is the same hand-off FLEETS, PORT
  and MARKET have always used; the map is its fourth caller, not a new mechanism.
- **Nothing is ever greyed out silently.** Where she may sail, the panel prints the SERVER's own sailed
  miles and voyage-days. Where she may not, it prints `voyage.sail_refusal`'s sentence — the one
  `cmd.issue` would have raised — beside a button that is still live, because COMMAND renders that
  refusal's *fixes* as tappable orders and the fix is what the player actually wants.
- **No argument picker, no quantity control and no client-side legality check may live in
  `src/features/map`.** That list is the real law, and it is the one to defend.
- **Every control is anchored to the glass, never to a map coordinate.** A chart pans and zooms, so an
  action drawn at a coordinate is an action the player can send off the screen. The action lives in the
  corner panel, which is chrome.

Otherwise unchanged and still binding — per the owner's standing map rules: clean map, minimal words and
icons, no jargon, panels in the corners not the centre, everything foldable.

```
╔═ MAP ═════════════════════════════════════════════════════════╗
║ ┌ FLEETS ─────┐                                               ║
║ │ ▲ Ponente   │            ....___                            ║
║ │   Lisboa    │        ..:'      ':.._                        ║
║ │ ▲ Aurora    │      .'  E U R O P E  ':.                     ║
║ │   11m       │     :        ▲······▲    :                    ║
║ │ ▲ Gaivota   │     '.   Lisboa    Amsterdam                  ║
║ │   Cádiz     │       ':.  ▲                                  ║
║ │ [fold ▸]    │     ▲ Cádiz  '·..                             ║
║ └─────────────┘        ·         A F R I C A                  ║
║                         ·..                                   ║
║                            '·..                               ║
║                                '▲ Las Palmas                  ║
║                                               ┌ AURORA ─────┐ ║
║                                               │ → Amsterdam │ ║
║                                               │ 812/1007 nm │ ║
║                                               │ eta 11m     │ ║
║                                               │ [fold ▸]    │ ║
║                                               └─────────────┘ ║
║ ⏱ 1 min = 8 h sail                                    [＋][－]║
╚═══════════════════════════════════════════════════════════════╝
```

Rendering rules, binding:

- **Three glyphs only.** `▲` a port, `▲` filled + label a fleet at anchor, a moving dot on a dotted track
  for a fleet at sea. Nothing else is drawn.
- **Coastlines are a single pale stroke on a quiet body.** No terrain, no bathymetry, no borders, no
  relief, no second land colour. **Amended 2026-08-23, from "no fill".** The original ban was written
  for austerity and it was measured out of the game: an outline alone leaves the player deciding
  which side of a line is water, and the values shipped in its place put land at **1.23 : 1** against
  the chart's sea — **1.03 : 1** against what was actually behind it, because the chart painted no
  sea of its own and sat on the `.bv-sea` gradient. At 390 px Iberia and the Atlantic were one
  object, which is a chart failing at its only job. The rule is now a pair of numbers rather than a
  prohibition: the **stroke stands clear of the water at 3 : 1** — WCAG 1.4.11's floor for a graphic
  that carries meaning, and what makes "a single pale stroke" true rather than aspirational — and
  the **body at ~2 : 1**, kept deliberately below the marks so the coast stays the ground and the
  ports stay the subject. `src/index.css` carries the tokens and the arithmetic;
  `src/chart/ChartCanvas.tsx` paints the sea those figures are measured against.
- **A port's mark is ranked by its `size_tier`,** on two channels and no others: how big the triangle
  is and how firm its line is. The same column already decides which ports are drawn at each zoom,
  so the chart has one idea of importance and it is the world's, not the renderer's.
- **Labels appear at zoom ≥ 2** and only for ports the player has visited or has a fleet bound for.
- **A name is never printed under the chrome.** A label may not be placed inside a rectangle the
  screen has declared opaque — the zoom column, the corner panels. Measured at 390×844 before the
  rule existed: `Saint-Malo` read as `Sain` and `Nantes` as a bare `s`, both placed entirely inside
  the glass and both painted behind a button. Half a name is worse than no name, because it cannot
  be told apart from another port's whole one. Where nothing fits, the name is dropped and the
  detail panel still carries it.
- **The track is the authored leg path**, dotted behind the fleet and fainter ahead of it.
- **Two panels, both in corners, both foldable to a chevron**: fleet list (top-left), selected fleet or
  port detail (bottom-right). Tapping a fleet on the map selects it — that is a *view* change, not a
  command; it also points the composer's draft at her, so the harbour tapped next sails the ship just
  pointed at. The bottom-right panel is where Law 3's one action lives when a PORT is what is selected.
- **One tap finds her.** The third view control returns to the opening frame, which is built around what
  the house HAS — its fleets and the harbours they are using — not around the 214-port world. It is
  labelled `find`; it read `fit` until 2026-08-23, which is a chart programmer's word for the thing a
  player calls "where is my ship".
- **Nothing blinks, nothing pulses, nothing pops.** Position updates by re-evaluating the closed-form
  progress function (§D.2) on a 1 Hz timer.
- The only persistent text is the time-scale hint in the bottom-left corner.

### E.6 LEDGER — the log and the after-action reports

The narrative organ of the game. This is where "combat" lives, as prose.

```
╔═ LEDGER ═══════════════ [all] voyages trade reports finance ═╗
║ ● 14:22  AURORA — VOYAGE REPORT · Lisboa → Amsterdam         ║
║   Day 3.  A gale off Finisterre. We ran under bare poles for ║
║   a day and a half and lost a spar. Hull 92% → 79%.          ║
║   Day 6.  Two sail shadowed us into the Channel and sheered  ║
║   off at nightfall without closing.                          ║
║   ── ledger ──────────────────────────────────────────────   ║
║   wages          8 days × 138 crew            −1,104 d.      ║
║   provisions     water 22 t, food 17 t        (consumed)     ║
║   damage         hull 92% → 79%                              ║
║   fame           adventure +20 (1,007 nm, first call)        ║
║                  naval     +6  (raider evaded)               ║
║                                                              ║
║ ○ 12:04  GAIVOTA — SOLD  sal 60 t @ 10 d.        +600 d.     ║
║ ○ 11:58  GAIVOTA — BOUGHT sal 60 t @ 7 d.        −420 d.     ║
║ ○ 09:30  BUREAU  — INVESTED 200,000 in Lisboa (commerce)     ║
║                    development 16 → 17 · rank 4th of 22      ║
║ ○ 08:00  MARKET  — pimenta SOARING in Lisboa (+38%, 2 days)  ║
╚══════════════════════════════════════════════════════════════╝
```

Every row is an immutable `events` record. **The Ledger is not a UI convenience — it is the source of
truth from which rank is computed** (§I.4).

### E.7 RANK

```
╔═ RANK ══════════════════════════════════════════════════════╗
║ ADMIRAL  Casa Aveiro          TITLE  LV 6 · Cavaleiro       ║
║          Portugal             tax relief 3% where PT ≥10%   ║
║────────────────────────────────────────────────────────────║
║  TRADE      14,820  ████████████░░░░  next 22,500           ║
║  ADVENTURE   9,140  ███████░░░░░░░░░  next 22,500           ║
║  NAVAL       3,206  ██░░░░░░░░░░░░░░  next 22,500  ◂ lowest ║
║  Title LV 7 requires ALL THREE ≥ 22,500.                    ║
║  Your naval fame is the binding constraint.                 ║
║  Earn it: escort contracts · surviving raiders · convoys.   ║
║────────────────────────────────────────────────────────────║
║ LEADERBOARDS   season 3, 41 days remaining                  ║
║  trade profit    #12 of 318      investment  #4 in Lisboa   ║
║  distance sailed #7  of 318      discoveries #19 of 318     ║
╚═════════════════════════════════════════════════════════════╝
```

### E.8 ME (profile)

Company name and flag, home nation, per-nation reputation, language levels, ship roster with build state,
officer roster, discovery journal, settings (unit system, notification thresholds, order-queue defaults),
and the raw session log for support.

---

## F. The command language

**This is the heart.** Everything the player does passes through this grammar. There is exactly one parser,
it runs on the server, and the tap-builder emits the same string the keyboard does.

### F.1 Grammar

```ebnf
order        = verb , { argument } ;
verb         = "SAIL" | "DOCK" | "ANCHOR" | "RECALL" | "WAIT"
             | "BUY"  | "SELL" | "LOAD"   | "UNLOAD" | "TRANSFER"
             | "PROVISION" | "HIRE" | "DISCHARGE" | "REPAIR"
             | "SPLIT" | "MERGE" | "FLAG" | "RENAME" | "ASSIGN"
             | "INVEST" | "BUILD" | "SCRAP"
             | "EXPLORE" | "SURVEY" | "REPORT"
             | "CANCEL" | "CLEAR" ;
fleet_ref    = name | "#" , integer ;                (* case-insensitive, prefix-unique *)
port_ref     = name | port_code ;                    (* "Cádiz" | "cadiz" | "CAD" *)
good_ref     = name | good_code ;
qty          = integer | "ALL" | "HALF" | percent ;
price_limit  = "AT" , [ "<=" | ">=" ] , integer ;
```

**Parsing rules.** Case-insensitive. Diacritics folded (`cadiz` = `Cádiz`). Names are matched by unique
prefix; ambiguity is an error that lists the candidates. Numbers accept `_` and `,` separators (`200_000`).
Keywords `TO`, `VIA`, `AT`, `IN`, `AS`, `FROM`, `INTO` are noise-tolerant — omitting them is accepted when
unambiguous, so `SAIL Aurora Amsterdam` parses.

### F.2 Verb reference

Every entry: **shape · preconditions · cost · what it queues · failure.**

---

**`SAIL <fleet> TO <port> [VIA <port> ...] [SPEED cruise|press]`**
Sends a fleet to sea.
- **Pre:** fleet `DOCKED`; destination reachable through the leg graph; `endurance_days ≥ leg_days × 1.15`;
  flagship durability > 0; crew ≥ `crew_required` on every ship; destination `max_draft ≥` deepest ship;
  destination not ice-closed; player's language/permit level admits the port.
- **Cost:** 0 at issue. Wages and provisions accrue per voyage-day while sailing.
- **Queues:** one `VOYAGE` row with the frozen `speed_profile`, `total_nm`, `eta`, and a checkpoint
  schedule. Status `SAILING`.
- **`SPEED press`:** +8% speed, +40% hull wear, +25% hazard. `cruise` is the default.
- **Fails:** `E_NOT_DOCKED`, `E_NO_ROUTE`, `E_ENDURANCE`, `E_CREW_SHORT`, `E_DRAFT`, `E_PORT_CLOSED`,
  `E_FLAGSHIP_DISABLED`, `E_LANGUAGE`.

**`DOCK <fleet>`**
Enters the port the fleet is anchored off. Pre: `ANCHORED` at a port. Cost: port fee `50 × ships`.
Queues an immediate state change. Fails `E_NOT_AT_PORT`.

**`ANCHOR <fleet>`**
Leaves the harbour but stays in the roads: stops paying port fees, halts repairs, keeps the fleet
available for an immediate `SAIL`. Pre: `DOCKED`.

**`RECALL <fleet>`**
Aborts the active voyage and turns for the **nearest reachable port** (which may not be the origin).
Pre: `SAILING`. Cost: nothing refunded — provisions already burned stay burned. Queues a replacement
`VOYAGE` from the fleet's *current interpolated position* to that port. Fails `E_NOT_SAILING`,
`E_ENDURANCE` (if nothing is in reach — in which case the fleet must press on and the error says so).

**`WAIT <fleet> <n> <minutes|hours|days>`**
A deliberate pause in the queue — used to time an arrival to a market event. Queues a `WAIT` order.
Days are **voyage-days** (3 real minutes each).

---

**`BUY <good> <qty> [AT <= price] [FOR <fleet>]`**
- **Pre:** fleet `DOCKED`; port sells the good this season and culture; ducats ≥ estimated cost; free hold
  ≥ qty; qty ≤ remaining daily cap for that (port, good).
- **Cost:** `Σ stepped price × (1 + tax + spread/2)`, debited atomically.
- **Queues:** executes immediately if the fleet is docked; otherwise queued and executed on arrival —
  which is the whole point of the queue: *"sell the cloves when you get to Amsterdam."*
- **`AT <= p`:** a limit. On execution, if the average price would exceed `p`, the order **partially
  fills** to the largest quantity that stays under the limit; if zero units qualify it fails
  `E_PRICE_LIMIT` and the queue **halts** (it does not skip — silently continuing past a failed trade is
  how players lose fortunes).
- **Fails:** `E_NOT_DOCKED`, `E_NO_SUCH_GOOD`, `E_UNAVAILABLE` (season/culture), `E_INSUFFICIENT_FUNDS`,
  `E_HOLD_FULL`, `E_NO_STOCK`, `E_DAILY_CAP`, `E_PRICE_LIMIT`.

**`SELL <good> <qty|ALL|HALF|n%> [AT >= price] [FROM <fleet>]`**
Mirror of `BUY`. Credits `Σ stepped price × (1 − spread/2)` minus tax. Emits a `TRADE` ledger event
carrying realised margin, which is what Trade Fame is computed from (§I.2).
Fails: `E_NOT_DOCKED`, `E_NO_CARGO`, `E_UNAVAILABLE`, `E_DAILY_CAP`, `E_PRICE_LIMIT`.

**`LOAD <good> <qty> ONTO <ship>` / `UNLOAD <good> <qty> [TO WAREHOUSE]`**
Moves cargo between a port warehouse and a ship without a market transaction. Pre: docked; space.
Cost: 1 ducat/tun handling. Warehouse rent 0.5 d./tun/game-day. Fails `E_HOLD_FULL`, `E_NO_CARGO`.

**`TRANSFER <good> <qty> FROM <ship> TO <ship>`**
Redistributes cargo inside a fleet, or between two fleets in the same port. Free.

**`PROVISION <fleet> [FULL | <days> DAYS | WATER <t> FOOD <t>]`**
Buys water and food to a target. `FULL` fills to the ship's `store_ratio` (default 45% of hold,
settable per ship). Pre: docked, funds. Cost: local water and food prices.
Fails `E_INSUFFICIENT_FUNDS`, `E_HOLD_FULL`.

**`HIRE <count> CREW [FOR <fleet>]`**
Pre: docked; port crew pool ≥ count *or* pay the urgent premium; `crew ≤ crew_max` fleet-wide.
Cost: `count × port_crew_rate`, ×2.5 beyond the pool ("urgent recruitment", per Origin —
`DESIGN_RESEARCH.md` §1.11). Fails `E_CREW_POOL`, `E_CREW_MAX`, `E_INSUFFICIENT_FUNDS`.

**`DISCHARGE <count> CREW [FROM <fleet>]`**
Pays off crew. Refunds nothing; reduces daily burn. Blocked below `crew_required` unless `--force`,
which the parser renders as a confirm chip rather than a flag on mobile.

**`REPAIR <fleet|ship> [TO <pct>]`**
Pre: docked at a port with a yard. Cost `= (max_dur − dur) × class_repair_rate × (1 − dev_industry×0.01)`.
Takes voyage-time: `hours = damage_pct × 0.4` sim-hours. Queues a `REPAIRING` state.
Fails `E_NO_YARD`, `E_INSUFFICIENT_FUNDS`.

---

**`SPLIT <fleet> [SHIPS <ship>,...] AS <newname>`**
Pre: both fleets docked in the same port; Company LV allows another fleet; each resulting fleet keeps
≥1 ship and gets a flagship (auto-selected as the largest hull if unspecified).
Fails `E_FLEET_CAP`, `E_NOT_DOCKED`, `E_LAST_SHIP`.

**`MERGE <fleet> INTO <fleet>`**
Pre: both docked in the same port; combined ships ≤ 8. The target's flagship survives.
Fails `E_FLEET_SIZE`, `E_DIFFERENT_PORT`.

**`FLAG <ship> IN <fleet>`** — set the flagship. Pre: docked. Recomputes officer bonuses.
**`RENAME <fleet|ship> <name>`** — cosmetic; 3–24 chars; profanity-filtered; must be unique per player.
**`ASSIGN <officer> TO <ship>`** — pre: officer and ship in the same port. Applies expertise (100% on the
flagship, 50% elsewhere, §C.6).

---

**`INVEST <amount> IN <port> [AS trade|military|culture]`**
*(`trade` maps to Origin's commerce, `military` to military, `culture` replaces industry as the
development track that raises port size, shipyard tier and crew pool.)*
- **Pre:** the player has an agent in the port — i.e. has docked there at least once this season; amount
  ≥ **50,000 ducats** (Origin's minimum, `DESIGN_RESEARCH.md` §1.6); amount ≤ 25% of the port's weekly
  investment cap (§H.3); ducats available.
- **Cost:** the full amount, debited immediately and irrevocably. **There is no un-invest.**
- **Queues:** nothing — it resolves synchronously and returns the resulting development preview
  (before/after level, your new share, your rank among investors).
- **Fails:** `E_MIN_INVEST`, `E_WEEKLY_CAP`, `E_NO_PRESENCE`, `E_INSUFFICIENT_FUNDS`, `E_SEASON_CLOSED`.

**`BUILD <class> AT <port> [NAME <name>]`**
Pre: docked; port shipyard tier ≥ class tier; blueprint owned; materials and ducats available;
ships < Company LV cap. Cost: ducats + materials. Queues a `BUILD` job with a real completion time
(`class.build_hours × (1 − 0.05 × control_bonus)`), delivered to that port.
Fails `E_YARD_TIER`, `E_NO_BLUEPRINT`, `E_SHIP_CAP`, `E_MATERIALS`.

**`SCRAP <ship>`** — pre: docked, not a flagship of a multi-ship fleet. Refunds 25% of hull value and
returns some materials.

---

**`EXPLORE <fleet> [AT <port|coast>] [DAYS <n>]`**
Sends a landing party ashore. Consumes food, water and crew per day; rolls one event per day
(observation / gathering / mishap) exactly as Origin does (`DESIGN_RESEARCH.md` §1.10). Produces a
results report listing actual costs and finds. Adventure Fame and journal entries.
Pre: docked or anchored at an explorable coast; `scouting` ≥ the site's requirement.
Fails `E_SCOUTING`, `E_ENDURANCE`, `E_ALREADY_EXPLORED`.

**`SURVEY <fleet> <leg>`**
Charts an uncharted leg: permanently reduces its `REEF` hazard for **all players** and awards Adventure
Fame to the first surveyor. This is the cooperative-discovery hook (§J).
Pre: the fleet has sailed the leg at least once.

**`REPORT <discovery> [TO <port>]`**
Files journal entries with a port's academy for ducats and Adventure Fame. Pre: docked at a port with an
academy; the discovery is unreported. Fails `E_ALREADY_REPORTED`, `E_NO_ACADEMY`.

---

**`CANCEL <fleet> [<index>]`** and **`CLEAR <fleet>`** — see §F.4.

### F.3 The order queue

- **One FIFO queue per fleet.** Maximum **12 orders**. Orders carry
  `status ∈ {pending, active, done, failed, cancelled, skipped}`.
- The server executes the head of the queue **whenever the fleet's state permits it** — i.e. the moment it
  docks, the moment a repair finishes, the moment a `WAIT` elapses. Advancement is driven by
  `voyage.settle()` (§D.2), so it happens for offline players at exactly the right instant.
- **Execution is atomic per order.** An order either fully applies or fully fails; there is no half-applied
  trade. Partial *fills* on a limit order are a single atomic outcome, not a partial application.
- **On failure the queue HALTS** at that order with `status='failed'` and a reason. It does not skip ahead.
  The fleet sits in port, the CMD tab badges, and the Ledger prints the failure. This is deliberate:
  a queue that quietly continues past a failed `BUY` will sail an empty ship halfway round the world.
- **Templates.** A queue can be saved as a **Route** (`SAVE ROUTE <name>`) and re-applied to any fleet
  (`RUN ROUTE <name> WITH <fleet>`), with port and quantity slots re-bound. This is the mechanism that
  makes commanding six fleets tolerable, and it is the main V2 quality-of-life feature.
- **Concurrency.** Every mutating RPC takes the fleet's `version` and fails `E_STALE` on mismatch, so two
  devices cannot double-issue.

**Cancellation:**

| Order state | `CANCEL` behaviour |
|---|---|
| `pending` | Removed. Free. Later orders shift up. |
| `active`, non-`SAIL` (repair, build, explore) | Aborted. Elapsed cost is **not** refunded; partial progress is lost. |
| `active` `SAIL` | **`CANCEL` on a voyage is a `RECALL`**: the fleet turns for the nearest reachable port from its current position. Nothing is refunded. The parser accepts either word and tells you which one it did. |
| `done`, `failed` | Not cancellable. `CLEAR` removes them from the display. |

`CLEAR <fleet>` drops every `pending` order and leaves the `active` one running. `CLEAR <fleet> ALL` also
recalls an active voyage, and requires a confirm chip.

### F.4 Mobile input

The tap-builder is not a second implementation. It is a **client-side constructor for the same string**:

1. Tap a verb → the client fetches that verb's argument schema (served by `cmd.verb_schema()` so the
   grammar has one authority).
2. Each argument renders as a picker — fleets from the roster, ports from the reachable set, goods from
   the port's market, quantities from a slider with `ALL` / `HALF` chips.
3. The string assembles live in the input box, visible, editable, and copyable.
4. Submit sends the **string**, not a structured object. The server parses it. There is exactly one parser.

A player can therefore learn the language by tapping, then start typing it, and never hit a behaviour
change. This is what makes the game feel like a command deck rather than a form.

### F.5 Validation and how failure reads

Validation runs in three layers, and the first two are advisory only — **the server's is the authority.**

1. **Parse** (client + server): grammar, unknown verb, ambiguous name.
2. **Static check** (client, from cached state): obvious precondition failures, shown live under the input.
3. **Server check** (RPC): the real one, inside the transaction.

Errors are **a code, a sentence, and a fix** — never a bare code:

```
E_ENDURANCE
  Ponente carries 47.6 days of stores. Calicut is 106 voyage-days
  away by the route you gave. You would run out near Santa Helena.
  → PROVISION Ponente FULL          (est. 8,240 d.)   [insert]
  → SAIL Ponente TO Ribeira Grande  (first watering stop)  [insert]

E_PRICE_LIMIT
  Cloves opened at 712 d. in Amsterdam. Your limit was 690.
  Nothing was sold and the queue has stopped at order 2.
  → SELL cloves ALL AT >= 700       [insert]
  → SELL cloves ALL                 (take the market)  [insert]

E_HOLD_FULL
  Bom Jesus has 90 tuns free; you asked for 180.
  → BUY copper 90                   [insert]
  → UNLOAD water 90 TO WAREHOUSE    (drops endurance to 31 d.)  [insert]
```

**Full error code list:** `E_PARSE`, `E_AMBIGUOUS`, `E_NO_SUCH_FLEET`, `E_NO_SUCH_PORT`, `E_NO_SUCH_GOOD`,
`E_NO_SUCH_SHIP`, `E_NO_SUCH_OFFICER`, `E_NOT_DOCKED`, `E_NOT_SAILING`, `E_NOT_AT_PORT`, `E_NO_ROUTE`,
`E_ENDURANCE`, `E_CREW_SHORT`, `E_CREW_MAX`, `E_CREW_POOL`, `E_DRAFT`, `E_PORT_CLOSED`,
`E_FLAGSHIP_DISABLED`, `E_LANGUAGE`, `E_INSUFFICIENT_FUNDS`, `E_HOLD_FULL`, `E_NO_CARGO`, `E_NO_STOCK`,
`E_UNAVAILABLE`, `E_DAILY_CAP`, `E_PRICE_LIMIT`, `E_MIN_INVEST`, `E_WEEKLY_CAP`, `E_NO_PRESENCE`,
`E_SEASON_CLOSED`, `E_FLEET_CAP`, `E_FLEET_SIZE`, `E_SHIP_CAP`, `E_LAST_SHIP`, `E_DIFFERENT_PORT`,
`E_YARD_TIER`, `E_NO_YARD`, `E_NO_BLUEPRINT`, `E_MATERIALS`, `E_SCOUTING`, `E_ALREADY_EXPLORED`,
`E_ALREADY_REPORTED`, `E_NO_ACADEMY`, `E_QUEUE_FULL`, `E_RANK_LOCKED`, `E_STALE`.

---

## G. Economy

### G.1 Price formation

Every `(port, good)` pair is one row. Price is derived, never stored as a free variable:

```
mid = base_value
    × affinity                                    -- structural, authored: 0.25 … 3.00
    × (stock_target / max(stock, 1)) ^ 0.5        -- elasticity ε = 0.5
    × (1 + drift)                                 -- stochastic, ±0.25
    × (1 + season_mod)                            -- −0.30 … +0.30
    × (1 − 0.004 × dev_commerce)                  -- developed ports trade cheaper
mid = clamp(mid, 0.35 × base_value, 3.50 × base_value)

ask (you pay)     = mid × (1 + tax_rate + spread/2) × (1 − purchasing_bonus)
bid (you receive) = mid × (1 − spread/2) × (1 + sales_bonus) × (1 − tax_rate)
spread            = 0.06 − 0.002 × dev_commerce   (floor 0.02)
```

- `base_value` is **global per good** — one number, one authority.
- `affinity` is the authored soul of the world: pepper 0.30 at Calicut, 2.80 at Lisboa; Baltic grain 0.35
  at Gdańsk, 1.90 at Sevilla; silver 0.40 at Callao, 1.60 at Sevilla, **2.90 at Nagasaki** (the real
  bimetallic arbitrage that funded the Manila galleon).
- `drift` is an Ornstein–Uhlenbeck step every 10 minutes: `drift ← 0.90 × drift + N(0, 0.04)`, clamped
  ±0.25. Mean-reverting, so the market wanders but does not run away.

### G.2 Stock, and why trading moves the market

```
stock ← stock + (stock_target − stock) × 0.15   per game-day       -- regeneration
stock ← stock + production_rate                  per game-day       -- producer ports only
stock ← stock − qty   on a player BUY
stock ← stock + qty   on a player SELL
```

Because `mid` contains `(stock_target/stock)^0.5`, **buying raises the price you are still buying at**.
Orders execute in **10-tun steps**, each repricing, so a large order pays a genuinely worse average. A
player who buys out a port pays visibly for the privilege, and the port stays expensive for the hours it
takes to regenerate — which is the whole basis of route competition between players (§J).

### G.3 Real goods, 1500–1650

**243 goods, all historical** (grown from the original 70 at the owner's direction: real
trade by regions, at the granularity of the reference games). Grouped in seven categories so
a player can reason about a category; rarity (0032) is derived from how many ports produce
each good — 25 common staples, 27 uncommon, 58 rare regionals, 133 exotic one-or-two-port
specialities. The table below names the anchor examples per category, not the full list —
`data/goods.json` is the catalogue.

| Category | Goods | Anchor producers → sinks |
|---|---|---|
| Spice | black pepper, cloves, nutmeg, mace, cinnamon, ginger | Calicut/Malaca, Ternate, Banda, Colombo → Lisboa, Antwerpen, Venezia |
| Textile | Chinese silk, Indian calico, chintz, English broadcloth, Flemish linen, raw cotton | Guangzhou, Surat, Masulipatnam, London, Antwerpen |
| Bullion & metal | silver, gold dust, copper, tin, iron | Callao/Potosí, Elmina, Nagasaki/Sweden, Cornwall |
| Colonial | sugar, tobacco, cacao, coffee, indigo, cochineal, brazilwood | Bahia, Madeira, Habana, Veracruz, Mokha, Gujarat, Recife |
| Naval stores | mast timber, tar, pitch, hemp, sailcloth | Gdańsk, Rīga, Bergen, Stockholm |
| Staple | Baltic grain, salt, dried cod, herring, olive oil, wine | Gdańsk, Setúbal, Bergen, Sevilla, Porto |
| Luxury | porcelain, lacquerware, ivory, pearls, coral, amber, sandalwood, frankincense | Guangzhou/Macau, Nagasaki, Mozambique, Bahrain, Aden |

Each good carries `perishable` (spoilage per voyage-day), `bulk` (tuns per unit — bullion is dense and
cheap to carry, timber is not), and `culture_mask` (wine and pork do not sell in Islamic-culture ports).

### G.4 Why arbitrage between real regions works

Because the real 16th century *was* an arbitrage machine and we simply encode the price gradients that
actually existed. Pepper at 0.30 affinity in Calicut and 2.80 in Lisboa is roughly a 9× structural
gradient — before stock, drift, tax and spread. That gradient is enormous, and the game's answer is
**cost, time and risk**, not a nerf:

- ~98 voyage-days each way — a 10-real-hour round trip.
- ~11,700 ducats of wages one way for a 120-crew Nau, doubled for the return.
- 200 of 400 tuns given over to water and food, halving the cargo.
- A 45–65% chance of at least one hazard on the run.
- Capital locked up for half a real day.

Meanwhile Lisboa → Cádiz at 4.7 minutes offers a ~1.4× gradient on salt. **Return scales with the square
of commitment; frequency scales inversely.** That is the whole shape of the economy, and it is why a
player ends up running a portfolio of fleets on different time horizons (§D.4).

### G.5 Negotiation

On any `BUY`/`SELL`, with probability `0.10 + 0.02 × negotiation_expertise` (cap 0.45), a negotiation
resolves server-side and prints one line in the Ledger: `Beatriz talked them down 6%.` It is a coefficient
and a sentence. It is never a minigame. *(Origin's negotiation events, `DESIGN_RESEARCH.md` §1.5.)*

### G.6 Market events

Server-rolled, visible to every player on the MARKET tab, lasting 1–4 game-days:

| Event | Effect |
|---|---|
| `SOARING` / `PLUNGING` | one good, `season_mod` ±0.25…0.40 in one port |
| `TRENDING` / `OVERFLOWING` | a whole category, ±0.15 across a region |
| `BOOMING` | an unpopular good gets a temporary 2× `stock_target` and demand spike |
| `BLOCKADE` | a port's `spread` doubles and its stock regeneration halves for 2 game-days |

*(Taken from Origin, `DESIGN_RESEARCH.md` §1.5.)*

### G.7 Anti-exploit rules

Bindings, all server-side:

1. **Daily volume cap** per `(player, port, good)`: `0.35 × stock_target` per game-day. Prevents cornering.
2. **Price impact is mandatory** — there is no "market order at the quoted price". §G.2.
3. **Price band** hard clamp at `[0.35, 3.50] × base_value`. No infinite spike is reachable.
4. **Spread + tax always exceed one regeneration step**, so instant buy-then-sell in the same port is
   always a loss. Round-tripping a port is structurally unprofitable.
5. **Route fatigue:** the *fame* (not the ducats) from repeating an identical `(origin, destination, good)`
   triple decays 15% per repetition within a rolling 24 real hours, recovering at 25%/day. Money keeps
   flowing; the ladder stops rewarding a macro.
6. **No player-to-player trading of ducats or goods at V1.** The classic exploit vector. If introduced at
   V2+, only as a taxed, logged, capped consignment market with a floor price.
7. **Server-side wallet only.** The client never computes a price it then submits. Every price is derived
   inside the transaction from the row it just locked.
8. **Ledger-derived rank** (§I.4) means an exploit that inflates ducats does not silently inflate rank;
   the two are separately auditable and can be reconciled.

---

## H. City investment

### H.1 What you buy

`INVEST <amount> IN <port> AS trade|military|culture` converts ducats into **investment points** on one of
three tracks, permanently and irrevocably. Points raise the port's **Development Level** on that track
(0–20), and Development Level pays out to *everyone* trading there — including your competitors. That is
the point: investment is the game's one genuinely cooperative-competitive system.

| Track | Development Level buys |
|---|---|
| **trade** (commerce) | `spread` −0.002/level (floor 0.02) · `mid` −0.4%/level · `stock_target` +4%/level · +1 traded good per 4 levels |
| **military** | `hazard_base` −3%/level in the port's home sea (patrols) · pirate `escort_score` bonus +2%/level for fleets departing · unlocks escort contracts (Naval Fame) at level 8+ |
| **culture** | shipyard tier +1 per 5 levels · Inn crew pool +8%/level · academy at level 6 (enables `REPORT`) · officer quality +1 tier per 7 levels · `max_draft` +1 at levels 10 and 18 (harbour works) |

*(Tracks and the 50,000-ducat minimum follow Origin; the payouts are ours because Origin publishes none —
`DESIGN_RESEARCH.md` §1.6, §4.4.)*

### H.2 Development curve

```
points_needed(level) = 250_000 × level^1.6
```

Level 1 costs 250k; level 10 ≈ 9.96M; level 20 ≈ 30.2M. Cumulative to level 20 ≈ 152M ducats — far beyond
one player, which is exactly the design intent: **development is a shared project.**

### H.3 Influence and shares

For each port and track:

```
your_share    = your_points / total_points
nation_share(N) = Σ points from players whose home nation is N  / total_points
```

- **Weekly cap** per player per port: `max(2M, 0.25 × port's total points at week start)`. This is the
  primary anti-whale rule and it is a hard server check (`E_WEEKLY_CAP`).
- **Mayor of the week:** the largest investor in a port over the Mon–Sun window, ties broken by who
  invested earlier (Origin's rule, `DESIGN_RESEARCH.md` §1.6). The Mayor sets the port's market tax —
  but **only within the band 0%–8%**, adjustable once per real day. Origin allows an uncapped
  player-set tax; that is a griefing lever over other players' economies and we band it
  (`DESIGN_RESEARCH.md` §3.2 D10).
- **Dividends:** each week the port pays `0.5% of its total investment points` in ducats, distributed by
  share, to the top 50 investors. This makes investment an *asset*, not a donation — and it is what
  converts a successful trader into a rentier over a month of play.

### H.4 How investment feeds rank

Investment mints **Trade Fame** on a deliberately shallow curve, so it supplements a trading career rather
than replacing it:

```
trade_fame += floor( 40 × sqrt(amount_invested / 100_000) )
```

100k → 40 fame. 10M → 400. Mayorship: +250 Trade Fame and a permanent Ledger entry. Note the parallel to
UW2, where trade fame came partly from "investing large sums into ports"
(`DESIGN_RESEARCH.md` §2.1).

### H.5 Nations and port control

- A **free port** flips to the nation holding the highest total investment score across all three tracks,
  evaluated weekly. Owned ports never flip — no conquest, because there is no war (§J).
- **Regional control bonus** (Origin's occupation bonus, `DESIGN_RESEARCH.md` §1.6): a nation holding
  50–99% of a region's investment score grants its citizens `M_control = 1.04` and −5% build time; 100%
  grants `1.08` and −10%.
- **Reputation:** investing ≥100,000 ducats at once in a home-nation port raises Company reputation with
  that nation; investing in a rival's port lowers it. Reputation gates officer quality, tax relief and
  Royal Orders. *(Origin's threshold, `DESIGN_RESEARCH.md` §1.6.)*

### H.6 Seasons — designed in, not bolted on

**Investment seasons run 3 real months.** At a season boundary:

- All investment **points decay to 0**. Development Levels **decay by 40%**, not to zero — the world keeps
  a memory of what was built.
- The season's dividend pot pays out, weighted by time-integrated share (so early investors are rewarded
  for holding, not for sniping the last day).
- The investment leaderboard is archived; titles earned are permanent; a seasonal cosmetic (a flag device,
  a ship name prefix, an appellation) is awarded to the top investors in each port.

Origin shipped without this and had to retrofit it after roughly 40 admirals were clearing 50 billion
ducats a week and "Ducats makes additional Ducats" broke the ladder — and the retrofit meant changing the
refund rule between seasons 1 and 2 (`DESIGN_RESEARCH.md` §1.7). **We publish the decay rule before the
first ducat is invested.** That is a trust decision as much as a balance one.

---

## I. Rank and progression

### I.1 Three axes

| Axis | Earned by |
|---|---|
| **Trade** | Realised margin on sales; specialty bonus; investment (§H.4) |
| **Adventure** | Distance sailed on first arrival at a port each season; discoveries; `SURVEY`; `REPORT` at an academy |
| **Naval** | Surviving or driving off raiders; escort contracts; convoy runs; suppression contracts from a military-developed port |

*(The three-axis structure is the series' spine — UW2's explorer/piracy/trade, UWO's
adventurer/merchant/maritimer, Origin's Adventure/Trade/Combat Fame. `DESIGN_RESEARCH.md` §1.8, §2.1, §2.2.)*

**Naval Fame without combat** is the design problem this section solves. The answer: naval fame is
**fame for keeping cargo safe**, not for sinking anyone. You earn it by carrying value through dangerous
water and coming out the other side — which is a risk-roll outcome, a report, and a number.

### I.2 Formulas — all computed from ledger events

```
Δ trade_fame     = floor( 12 × sqrt(realised_margin_ducats / 1000) )
                   × (1.5 if specialty) × route_fatigue_factor        -- §G.7 rule 5
Δ adventure_fame = floor( leg_distance_nm / 50 )                       -- on arrival
                   × (3.0 if first ever call at this port,
                      1.0 if first call this season,
                      0.15 otherwise)
                 + discovery_value + survey_value
Δ naval_fame     = hazard_outcome_value × cargo_value_at_risk_factor
                 + escort_contract_value
```

`Δ adventure_fame` is Origin's "docking in cities, scaled by distance travelled"
(`DESIGN_RESEARCH.md` §1.9) with an anti-farm decay attached.

### I.3 Titles

**Eleven title levels**, and — following Origin exactly — **advancement requires all three fames to reach
the threshold**, so you cannot title up on trade alone (`DESIGN_RESEARCH.md` §1.8).

| LV | Title (PT/ES flavour, localised per nation) | Each fame ≥ | Tax relief | Unlocks |
|---|---|---|---|---|
| 1 | Marinheiro | 0 | 0% | 1 fleet, 2 ships |
| 2 | Piloto | 300 | 0% | 2nd fleet |
| 3 | Mestre | 900 | 1% | 3rd fleet, `INVEST` |
| 4 | Escudeiro | 2,100 | 2% | Nau blueprint |
| 5 | Cavaleiro | 4,200 | 2% | 10 ships, `BUILD` tier 3 |
| 6 | Fidalgo | 7,800 | 3% | Galleon, escort contracts |
| 7 | Comendador | 13,500 | 3% | 4th fleet, 14 ships |
| 8 | Capitão-mor | 22,500 | 3% | East Indiaman blueprint |
| 9 | Almirante | 36,000 | 4% | 5th fleet, 18 ships |
| 10 | Governador | 56,000 | 4% | Royal charters (seasonal contracts) |
| 11 | Vice-rei | 85,000 | **5%** | 6th fleet, 24 ships, name on the world board |

Tax relief applies in ports where your nation holds **≥10% share** — Origin's rule and Origin's numbers
(0% at LV1 rising to 5% at LV11, `DESIGN_RESEARCH.md` §1.8).

Promotion arrives as a **Royal Order** — a written contract from your nation's court ("deliver 400 tuns of
Baltic mast timber to Lisboa within 6 game-months") that must be completed to take the title. It is a
queued order chain, not a cutscene.

### I.4 Rank is derived, never stored

```sql
create materialized view rank_totals as
select player_id,
       sum(delta) filter (where axis = 'trade')     as trade_fame,
       sum(delta) filter (where axis = 'adventure') as adventure_fame,
       sum(delta) filter (where axis = 'naval')     as naval_fame
from   fame_events group by player_id;
```

`fame_events` is append-only and every row carries the `event_id` that produced it. **Any fame total can be
reconstructed from the ledger and reconciled against the balance sheet.** Refreshed every 5 minutes for
leaderboards; computed live on the RANK tab. This is the same discipline as byeharu's migration chain: one
authority, auditable, no cached truth that can drift from the events that made it.

### I.5 Leaderboards

Per season, all derived: total profit · distance sailed · discoveries · investment per port · naval fame ·
fastest Carreira da Índia · most ports called. Per-nation and global. Top 10 shown on RANK; full list
paginated.

---

## J. Multiplayer

### J.1 Shared

- **Markets.** One price per port per good, for everybody. When a player buys out Calicut's pepper, the
  next player finds it dear. This is the *only* direct player-versus-player pressure in the game, and it is
  entirely economic and entirely indirect.
- **City development.** Investment points pool. A port lifted to Development 15 pays better spreads to
  every trader who calls there, including the ones who invested nothing. Free-riding is *permitted*, and
  the counter to it is dividends and the Mayorship (§H.3).
- **Charted legs.** A `SURVEY` permanently reduces a leg's hazard for everyone. Explorers create public
  goods.
- **Weather and season.** Global, identical for all.
- **Leaderboards and the world board.**
- **Nation control** of free ports and regions, and the resulting speed and build bonuses.

### J.2 Never shared — no PvP

**There is no player-versus-player combat of any kind.** No piracy against players, no blockades of
players, no port capture by force, no fleet interception, no duels. This is law 4 and it is not
negotiable. All the raiders in this game are NPC hazard rolls.

Also excluded at V1: direct ducat or goods transfers between players (§G.7 rule 6).

### J.3 Presence

Presence is textual and ambient. It never interrupts.

- **PORT tab:** `3 fleets docked` — count only, no names, unless the player opts into a public flag.
- **MARKET tab:** `pimenta stock falling fast — 4 large purchases in the last 6 h`. The market tells you
  someone is on your route without telling you who.
- **LEDGER:** a world feed of notable public events — a Development Level crossing, a new Mayor, a first
  survey of a leg, a new fastest Carreira.
- **RANK:** your position among named players.
- **MAP:** **only your own fleets are ever drawn.** Other players never appear on the map. Adding them
  would turn the map into a targeting surface, which is exactly what law 3 forbids.

### J.4 Companies (guilds) — V2

Trading companies of up to 40 members, with a **capped per-category weekly contribution table** lifted
straight from Origin's guild contribution design (`DESIGN_RESEARCH.md` §1.12) because it is the best
anti-whale pattern in the reference: login, trade, exploration, investment and contracts each cap
separately, so twenty ordinary members outperform one obsessive one. A company that holds the top
investment share in a port becomes its **Monopoly House**, unlocking a company-exclusive good and a
shipyard discount.

---

## K. The first playable slice

### K.1 V0 — the smallest thing that is genuinely a game

**Scope:** one region, one loop, real money moving.

| | |
|---|---|
| **Tabs** | **CMD · FLEETS · PORT · MARKET · MAP · LEDGER** (6). No RANK, no ME. |
| **Commands** | `SAIL`, `BUY`, `SELL`, `PROVISION`, `HIRE`, `REPAIR`, `CANCEL`, `CLEAR` (8). Typed and tapped. |
| **Ports** | The 12 of §B.2: Lisboa, Porto, Sevilla, Cádiz, Ceuta, Safi, Funchal, Las Palmas, Marseille, Genova, Tunis, Napoli. |
| **Legs** | 22 authored legs connecting them, distances from §B.3. |
| **Goods** | 12: sal, vinho, azeite, cortiça, trigo, lã, cobre, ferro, açúcar, couro, tâmaras, coral. |
| **Ships** | 3 classes: Barca, Caravela latina, Nau. |
| **Fleets** | 2 fleets, **8 ships max** (owner, 2026-08-22: *"This game fleet will be comprised with 8 ships"*). Was 4; §C.4 had always said a fleet is 1-8 hulls, and B.3's formation penalty already had a band for 7+ that no fleet could ever reach. Raised and ENFORCED in 0021 — before it, all three caps were captions no rule read. |
| **Hazards** | `STORM`, `CALM`, `PIRATES`, `SHORT_RATIONS`. Full report prose. |
| **Economy** | Full §G formula: affinity, stock, elasticity, drift, spread, tax, price impact, daily cap. |
| **Time** | Full §D: compression 480, closed-form movement, `settle()` catch-up, `tick_arrivals`, `tick_market_drift`. |
| **Not in V0** | Investment, rank, titles, officers, shipbuilding, exploration, seasons, wind (`M_wind` = 1.00), multiplayer beyond a shared market, other players' presence. |

**The 10-minute first session, beat by beat:**

```
0:00  You are the Casa de Aveiro. One Barca, "Gaivota", docked at Lisboa. 8,000 ducats.
0:20  MARKET tab. Sal is 62% of its neighbours. The BUY block is at the top; you did
      not have to know anything to see it.
0:40  Tap the row. CMD fills in  BUY sal 60.  You submit. −420 d.
1:00  MARKET at Cádiz — reachable in one hop — shows sal at 137%.
1:20  CMD:  SAIL Gaivota TO Cadiz.  The check runs: 188 nm, 1.6 voyage-days,
      endurance 9.4 days. Green. ETA 4.7 minutes.
1:30  MAP. One dot leaves Lisboa on a dotted line. It is the first time the game
      has drawn anything, and it does not ask you for anything.
1:35  You queue the rest while it sails:  SELL sal ALL  ·  BUY couro 60  ·
      SAIL Gaivota TO Lisboa.  Four orders deep. The fleet will do them alone.
6:20  LEDGER pings. "Day 1. A short blow off Cape St Vincent, nothing carried away."
      SOLD sal 60 t @ 10 d. +600 d. BOUGHT couro. Departed for Lisboa.
      Profit on the leg: +180 d., 4% on capital, in five minutes.
11:00 Gaivota is home. You have 8,180 ducats and you have understood the machine.
      And you can see that Funchal is 13 minutes away and pays 210% for couro.
```

**The win-feeling:** *"I gave an instruction in words, went and did something else, and came back to find
that it had happened and I was richer."* Not a battle won. A **ledger that moved while you were away.**
Everything else in this document is an elaboration of that ten minutes.

### K.2 V1 — one paragraph

V1 makes the world big enough to have geography and adds the two systems that turn a trading loop into a
career. Ports go from 12 to ~40 by adding the Atlantic seaboard, the North Sea, the Baltic and the eastern
Mediterranean; wind and seasons switch on (`M_wind` becomes real, Baltic ports ice over, the Mediterranean
goes calm in summer); the RANK and ME tabs ship with all three fame axes, the 11-title ladder and Royal
Orders; `INVEST` opens with the full Bureau, weekly Mayor, dividends and the 3-month season; officers
arrive with the eight expertise coefficients, hired for ducats at Inns; shipbuilding opens with `BUILD`,
`SCRAP` and blueprints, adding Galleon, Fluyt, Xebec, Galley and Pinnace; and `SPLIT`/`MERGE`/`FLAG`/
`ASSIGN`/`EXPLORE`/`SURVEY`/`REPORT` complete the verb list. This is the version that can hold a player for
a month, because it is the first one where the answer to "what do I do now" can be *invest in Antwerp* or
*close the naval gap in my title* rather than only *run another cargo*.

### K.3 V2 — one paragraph

V2 opens the world and the social layer: ports reach ~90 with the Indian Ocean, East Asia and the
Americas, which turns the Carreira da Índia and the Manila galleon into real five-hour destination
voyages and makes the great historical arbitrages — Japanese silver, Banda nutmeg, Potosí bullion —
playable; Eastern hulls arrive (dhow, junk, panokseon, geobukseon) with the draft, monsoon and rowing
rules that make them locally superior rather than cosmetically different; Companies (guilds) ship with the
capped contribution ledger and Monopoly Houses; Routes become saveable and re-bindable templates so six
fleets are commandable in five minutes; and the first full 3-month investment season closes with a
published decay, a dividend payout and an archived leaderboard, which is the point at which the game
acquires a rhythm longer than a week.

---

## L. Open questions — each with my recommended default

Every one of these has a default. **Nothing here blocks the build.**

| # | Question | **Recommended default (build this unless told otherwise)** |
|---|---|---|
| 1 | Is `TIME_COMPRESSION = 480` right? It makes the Carreira a 4h53m voyage. | **Ship 480.** It gives 5-minute coastal hops and a half-day grand voyage — the correct mobile spread (§D.4). Make it a server constant in one row of `world_config` so it can be retuned live without a migration. |
| 2 | Should the flagship ever be capturable? | **No.** Worst case is `PLUNDERED`. A player who logs in to a destroyed account churns, and this project has already paid that bill once. |
| 3 | Free-typed commands, or tap-only? | **Both, one grammar** (§F.4). The tap-builder emits the string the keyboard would. Ship tap-first; typing is the power-user path that costs nothing extra. |
| 4 | Should the order queue skip a failed order or halt? | **Halt.** A queue that quietly continues past a failed `BUY` sends an empty ship to Malacca. Halting is legible and recoverable. |
| 5 | Real-time or turn-based season boundaries? | **Real-time**, calendar clock at 1 real day = 1 game month (§D.1). No lockstep turn a player can miss. |
| 6 | How hard should provisions bite? | **Bite on opportunity cost, not on death.** Running out is `ADRIFT` + a 30% salvage fee, never account loss (§B.6). |
| 7 | Should other players appear on the MAP tab? | **No.** Drawing rivals turns the map into a targeting surface, which law 3 forbids. Presence is textual, in PORT / MARKET / LEDGER (§J.3). |
| 8 | Uncapped Mayor tax like Origin? | **No — band it 0–8%** (§H.3). Origin's uncapped version is a griefing lever over other players' economies. |
| 9 | Player-to-player trading? | **Not at V1.** It is the standard exploit vector. Revisit at V2 only as a taxed, capped, logged consignment market. |
| 10 | Investment season length? | **3 months**, matching Origin, with **the decay rule published on day one** rather than changed between seasons (§H.6). |
| 11 | Should Naval Fame exist at all with no combat? | **Yes** — redefined as *fame for bringing value through danger* (§I.1). Without a third axis the title ladder degenerates into a pure trade grind. |
| 12 | Localisation? | **English first**, with all port and good names carried in their historical local form (Cádiz, Malaca, Ilha de Moçambique). Korean second. Never invent a name. |
| 13 | Where does the port geodata come from? | **Hand-authored in `data/ports.csv`, then asserted by `scripts/seed_ports.ts`** against a geodata source (§B.2). The seed must fail closed on any port whose coordinates fall outside its declared sea. |
| 14 | How many ports at V0 — 12 enough? | **Yes.** Twelve real ports with correct affinities beat forty guessed ones, and the V0 loop needs exactly one interesting price gradient to be a game. |

---

## Appendix 1 — Server data model (sketch)

Enough for a second engineer to start the migration chain. Supabase/Postgres, RLS on every table, all
writes through `security definer` RPCs.

```
-- static world (seeded, read-only to clients)
nations(id, code, name, capital_port_id, flag_char)
seas(id, code, name, hazard_base, piracy_index, wind_regime_id)
regions(id, code, name)
ports(id, code, name, country, nation_id, lat, lon, sea_id, region_id, culture,
      size_tier, max_draft, languages text[], has_yard, yard_tier, has_academy,
      is_ice_closed, opened_year)
legs(id, from_port, to_port, distance_nm, hazard_mult, wind_profile_id, min_year)
goods(id, code, name, base_value, bulk, perishable_pct_day, category, culture_mask)
ship_classes(id, code, name, family, rig, hold, crew_required, crew_max, speed_kn,
             durability, guns, draft, build_hours, build_cost, tier)

-- live world (server-written only)
port_goods(port_id, good_id, affinity, stock, stock_target, production_rate,
           drift, season_mod, updated_at)              -- PK (port_id, good_id)
market_events(id, port_id, good_id, kind, magnitude, starts_at, ends_at)
port_development(port_id, track, level, points)         -- PK (port_id, track)
port_investments(id, player_id, port_id, track, amount, points, invested_at, season_id)
port_mayor(port_id, week, player_id, tax_rate, set_at)

-- players
players(id, auth_uid, company_name, nation_id, ducats, company_level, title_level,
        created_at, version)
ships(id, player_id, fleet_id, class_id, name, durability, crew,
      cargo jsonb, water_t, food_t, store_ratio, is_flagship)
fleets(id, player_id, name, status, port_id, version)
        -- status: DOCKED | ANCHORED | SAILING | REPAIRING | ADRIFT | UNABLE_TO_SAIL
officers(id, player_id, ship_id, name, job, expertise jsonb, hired_at)

-- orders and voyages
orders(id, fleet_id, seq, raw_text, verb, args jsonb, status, error_code,
       issued_at, executed_at)
voyages(id, fleet_id, path jsonb, total_nm, speed_profile jsonb,
        departed_at, eta, status, last_settled_day)
voyage_events(voyage_id, day_index, kind, payload jsonb, resolved_at)
                                                        -- PK (voyage_id, day_index)

-- ledgers (append-only, the source of truth)
events(id, player_id, kind, payload jsonb, created_at)
fame_events(id, player_id, axis, delta, source_event_id, created_at)
ledger(id, player_id, kind, ducats_delta, balance_after, ref_event_id, created_at)

-- config
world_config(key, value)   -- TIME_COMPRESSION, spread_base, elasticity, caps...
```

**Invariants asserted by every migration that touches them:**

- `fleets.status = 'SAILING'` ⟺ exactly one `voyages` row with `status='SAILING'`.
- `voyage_events` is unique on `(voyage_id, day_index)` — the idempotency guarantee for `settle()`.
- `Σ ledger.ducats_delta = players.ducats` per player. Reconciliation job asserts this hourly.
- `Σ fame_events.delta` per axis = the RANK tab's displayed value. No cached fame column exists.
- No client role holds `INSERT`/`UPDATE`/`DELETE` on any table. Verified by a self-asserting migration
  that `REVOKE`s and then re-checks `information_schema.role_table_grants` — the byeharu prod-grant-drift
  lesson, applied from migration 0001.

## Appendix 2 — RPC surface

| RPC | Purpose |
|---|---|
| `cmd.issue(fleet_id, raw_text, expected_version)` | **The only mutating game entry point.** Parses, validates, executes or queues. Returns the parsed order, the resulting queue and any error with its fix suggestions. |
| `cmd.verb_schema()` | Serves the grammar to the tap-builder so there is one authority for arguments. |
| `cmd.preview(fleet_id, raw_text)` | Dry-run: parse + validate + cost/ETA estimate. No writes. Powers the live check under the CMD input. |
| `cmd.cancel(order_id)` / `cmd.clear(fleet_id, include_active)` | §F.3 cancellation. |
| `voyage.settle(fleet_id)` | Idempotent catch-up. Called by every read RPC and by `tick_arrivals`. |
| `world.snapshot()` | Ports, legs, goods, classes — static, cached hard on the client. |
| `world.market(port_id)` | Prices, `%NBR`, stock bands, 7-day history, events. |
| `world.fleets()` | The player's fleets with interpolated positions and ETAs. |
| `world.ledger(cursor)` | Paginated events and after-action reports. |
| `world.rank()` / `world.leaderboard(kind, season)` | Derived from `fame_events`. |
| `invest.commit(port_id, track, amount)` | §H, with the weekly cap check inside the transaction. |
| `invest.preview(port_id, track, amount)` | Development before/after, your share, your rank. |

**CI apply-proof requirements** (the byeharu discipline, carried over): the whole migration chain applies
to a real Postgres via `supabase start`; every migration self-asserts; and three game-specific proofs must
be green before any merge —

1. **Offline equivalence:** a voyage settled lazily after a simulated 9-hour gap produces byte-identical
   `voyage_events` to one settled tick-by-tick.
2. **Ledger reconciliation:** `Σ ledger.ducats_delta = players.ducats` after a randomised 500-order soak.
3. **Grant lockdown:** no client role can write any table.
