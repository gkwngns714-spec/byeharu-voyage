# Pirate ships sail (W17, migration 0339, owner row 284): the Brethren's ships, the hazard hand-off, stow, RANSOM, the book

Owner, 2026-11-05: *"pirate headquarters with pirate cities, npcs that attack these ships as well as merchants"*; *"pirates are like countries - power, where they can also invest. pirate merchants too"*. 2026-11-06 (row 306): *"use your recommended defaults for the rest"*. 2026-11-07: *"do it fast"*. Step 2 of 4 (W16 to W19) of `docs/WORLD_POWERS.md` Part 5; the design row is 7.7 W17: "Kind, size, map, hazard hand-off, stow, RANSOM, book". Built on W16 (0338, PR #552).

**State: contract written; the slice is being built.** Prod head 0337; 0338 is W16's; this is 0339.

## CONTRACT (what W18 and W19 may rely on)

Everything below is server-only unless it says "entry point". `PIR` is the pirate nation of 0338 (`public.pirate_power`). "The homes" are the four free ports of 0338 (POR, LGA, GOT, DJE). Names may still move; the hand-back lists every change against this text.

### The switch

| Knob (`world_config`) | Default | Meaning |
|---|---|---|
| `pirates_bite` | `false` | THE switch of the pirates' ships, read only through `public.pirates_on()`. False (shipped): nothing is built or paid, a ship that exists sails home and is laid up, no voyage's segment names a raider (raids are anonymous xebecs as today), nothing is stowed, no RANSOM moves, `public.sea_pressure` stays empty. Owner only. W18 reads the same switch for founding and investing (one switch for the pirates' doings; W18 adds no second one unless the owner asks). |

### Knobs (all `world_config`, read with `public.wc_num` / `wc_int` / `wc_text`)

| Key | Default | Meaning |
|---|---|---|
| `pirate_ship_class` | `'xebec'` | `ship_classes.code` of a pirate hull. Shipped equal to `fight_raider_class`, so a named raider and the anonymous raider are the same hull. |
| `pirate_max` | `30` | the most ships, whatever the hoard |
| `pirate_min` | `4` | ships allowed before the hoard counts |
| `pirate_hoard_unit` | `100000000` | `pirate_size = least(pirate_max, pirate_min + floor(hoard / this))` |
| `pirate_hoard_cap` | `2000000000` | a hoard at or above this takes no gold in: RANSOM and a looted book pay 0 (goods still stow) |
| `pirate_spend_day_pct` | `0.005` | what the power may spend in one UTC day, as a share of the hoard: THE one cap on every outflow from the hoard, ships (W17) and merchants (W18) alike |
| `pirate_pressure` | `0.5` | what one pirate ship at work in a sea adds to that sea's pressure (`voyage.sea_danger` reads `public.sea_pressure`; 0330) |
| `pirate_haunt_hours` | `12` | how long she lies at the haunt harbour of her cruise before she sails home |
| reused from the navy, not duplicated: `navy_upkeep_day` (60,000 d. a ship a day, hourly slices), `navy_build_hours` (one ship added in that many hours), `navy_reach_nm` (how far from her home she cruises), `navy_store_days`, `navy_steps_per_run` | | the same concept, one knob |

### Money kinds

| Kind | Side | From | To | Writer |
|---|---|---|---|---|
| `RANSOM` | new word, **moved** (`stats_flow_words`; and a ledger kind on the company's side) | the raided company's purse (player or NPC merchant) | her home port's purse | `public.pirate_ransom` |
| `LOOT` | exists (0327), moved | a pirate ship's book (`convoy_cargo`, the gold she took from a cargo ship) | her home port's purse, when she docks home | `public.pirate_ship_step` |
| `BUILD_NAVY` | exists, moved | the hoard's purse (the pirate capital, Port Royal) | the nearest yard by sea, whoever holds it (`public.refit_yard(home)`) | `public.pirate_commission` |
| `NAVY_PAY` | exists, moved | the hoard's purse | the harbour she lies at or last called at | `public.pirate_pay_hour` |
| `REFIT` | exists, moved | her home's purse (`public.fleet_origin` answers her home) | the refit yard | 0322's `npc_refit_step`, untouched |

Nothing is minted. W (Σ players + merchants + purses + set aside + funds aboard) is unchanged by every move above.

### Tables

```
public.pirate_ships                        -- THE kind: a row here is a pirate ship, as public.navy_ships is a navy ship
  fleet_id    uuid primary key references public.fleets(id) on delete cascade
  player_id   uuid not null unique references public.players(id) on delete cascade   -- her house: is_npc, purse 0, nation PIR
  ord         integer not null unique check (ord >= 1)                                -- her slot inside pirate_size (one roster for the whole power)
  home_port   uuid not null references public.ports(id)                               -- the PIR home she sails from, stows into and delivers her book to: ord 1 -> the capital, then the homes by code, wrapping
  sea_id      uuid references public.seas(id)                                         -- THE POSITION FOR "WHO RAIDS": the sea she is cruising (set as she leaves home, cleared as she docks home); null at home
  mission     text not null default 'HOME'                                            -- HOME (at or bound for home) | CRUISE (out on her sea)
  haunt_port  uuid references public.ports(id)                                        -- the harbour of this cruise (a harbour in sea_id within navy_reach_nm of home)
  last_port   uuid not null references public.ports(id)
  fought_at   timestamptz                                                             -- W19 writes it: her last fight with a navy ship (at most once an hour); W17 never writes it
  unpaid_since timestamptz
  laid_up_at  timestamptz
  created_at  timestamptz not null default now()
public.pirate_ships_at_work   view: pirate_ships where laid_up_at is null
public.pirate_spend_day (day date primary key, spent bigint not null default 0)      -- what the hoard paid out on each UTC day; read by pirate_spend_room only
```

A pirate ship is a real `fleets` row with one hull of `pirate_ship_class`, owned by a house of her own (`players.is_npc`, nation PIR, purse 0), no `npc_houses` row, so she is never tended, invested, gifted or refunded (0308's table). The voyage engine takes her with no fork. Hands from the quay and free stores at each departure (0328's `fleet_hands`, 0331's `fleet_stores`), no wage, no dock fee (`public.crown_house` answers true for her house).

### Functions

| Function | Returns | Volatility | What |
|---|---|---|---|
| `public.pirates_on()` | boolean | stable | `pirates_bite`. THE one reader of the switch. |
| `public.pirate_nation()` | uuid | stable | the nation that is the pirates (`great_powers.pirate`), null if none |
| `public.pirate_capital()` | uuid | stable | the port of `nations.capital_port_code` for PIR (Port Royal): THE purse the hoard pays from |
| `public.pirate_hoard()` | bigint | stable | THE hoard reader: Σ `public.treasury_balance` over every city PIR holds (`port_allegiance.nation_id` = PIR) |
| `public.pirate_size()` | integer | stable | `least(pirate_max, pirate_min + floor(pirate_hoard() / pirate_hoard_unit))` |
| `public.pirate_spend_room(p_now timestamptz)` | bigint | stable | **THE one authority for "how much may the Brethren spend today"**: `floor(pirate_hoard() x pirate_spend_day_pct) - pirate_spend_day.spent` for the UTC day of p_now, never below 0. W17 (hull, upkeep) and W18 (founding, investing) read it before every outflow and never pay more than it answers. |
| `public.pirate_pay(p_kind text, p_amount bigint, p_now timestamptz, p_port uuid default null, p_player uuid default null)` | bigint | volatile | **THE one way the hoard pays.** Whole or nothing: answers 0 and writes nothing when `pirate_spend_room(p_now) < p_amount`, when the capital's `public.city_surplus` is under it, or when the capital is busy (`public.treasury_try_lock`). Else `treasury_post(capital, kind, -amount)` and either `treasury_post(p_port, kind, +amount)` or (p_player given) `public.city_pays(capital, p_player, kind, amount)` as one move, then records the spend in `pirate_spend_day`. Answers the ducats moved. W18 founds a merchant with `pirate_pay('NPC_FOUND' or its own kind, cost, now, p_player := her house)` and nothing else. |
| `public.pirate_ship_in_sea(p_sea uuid)` | uuid | stable | **THE one reader of "which pirate ship is in this sea"**: the lowest-ord ship at work whose `sea_id` = p_sea and whose fleet is not `IN_BATTLE`; null if none. `voyage.depart` (through `voyage.freeze_raiders`) names her in the frozen segment; W19's hunt asks it with the navy ship's own sea. |
| `public.pirate_side(p_fleet uuid)` | jsonb | stable | her hulls as a side for `public.fight_sides`, the same shape `voyage.fight` builds for a player fleet (one object a hull: id, name, tier, hull, maxd, crew, attack, accuracy, reach, armour, sighting, boarder_pct). W19 passes it as `p_a` (the side set upon) when the navy closes. |
| `voyage.pirate_strength(p_fleet uuid)` | numeric | stable | her strength as a raider figure for `voyage.fight` (Σ over her hulls of `attack / 10 + crew_required x 0.02 + tier x 3`, scaled by the hull left), so the hazard engine builds her as hulls of `fight_raider_class` with no second fight path |
| `voyage.freeze_raiders(p_segments jsonb)` | jsonb | stable | dark: p_segments unchanged, byte for byte. Lit: each segment whose sea has a pirate ship gains `"raider": <fleet_id>`. Read by `voyage.depart` only. |
| `voyage.leg_raider(p_leg jsonb)` | uuid | stable | the frozen raider of a leg; null for an anonymous day. THE one reading. |
| `public.pirate_stow(p_fleet uuid, p_taken jsonb)` | jsonb | volatile | the result of `voyage.raid_takes` into her home's stock, each good up to 2 x that row's `stock_target`; beyond that lost. Answers {good code: units stowed}. |
| `public.pirate_ransom(p_fleet uuid, p_company uuid, p_basis bigint, p_event uuid)` | bigint | volatile | RANSOM: `least(public.ransom_take(p_basis), the company's purse)`, 0 when the hoard is at or above `pirate_hoard_cap`; from the company's purse (ledger kind RANSOM) to her home's purse (`treasury_post` RANSOM). Answers the ducats moved. |
| `public.pirate_loot_book(p_fleet uuid, p_victim uuid, p_share numeric, p_event uuid)` | bigint | volatile | the plundered share of a cargo ship's funds aboard: the victim's book closes LOOTED by that much (0327's `public.convoy_book`), the same ducats open on her own book (stage LOADED, her fleet); delivered to her home purse (LOOT) by `pirate_ship_step` when she docks home. Set aside is unchanged in all. |
| `public.pirate_pressure_write(p_now timestamptz)` | integer | volatile | THE first and only writer of `public.sea_pressure` (0330): one row a sea with k ships at work there, `value = pirate_pressure x k`, `updated_at = p_now`; a sea with none loses its row. Answers rows standing. Called by `tick_pirates` only. |
| `public.pirate_commission(p_ord integer, p_home uuid, p_yard uuid, p_now timestamptz)` | uuid | volatile | THE one place a pirate ship is made: the hoard pays the yard (`pirate_pay` BUILD_NAVY), her house and fleet are formed by `public.form_fleet` and `public.commission_ship`, crewless, laid at her home. Answers her fleet. |
| `public.pirate_add(p_now timestamptz)` | text | volatile | at most one ship a run and one in `navy_build_hours`: the lowest ord inside `pirate_size()` not at work wakes (laid up) or is built; a hoard that cannot pay just waits. BUILT, WOKEN or null. |
| `public.pirate_pay_hour(p_now timestamptz)` | bigint | volatile | one hour of upkeep, `navy_upkeep_day / 24` a ship at work, by ord, as far as `pirate_pay` allows; a ship not paid is marked unpaid and goes home. |
| `public.pirate_ship_step(p_fleet uuid, p_now timestamptz)` | text | volatile | what she does in port, in one place: BUSY, AWAY, WRECK, IN_PORT, IDLE, LAID_UP, SAILED, DELIVERED. On duty at home: her book is delivered (LOOT), she is mended free, picks a haunt (the harbour within `navy_reach_nm` of home whose sea is the most dangerous as authored, ties by code, spread by ord) and sails (`sea_id` := the haunt's sea, mission CRUISE). At the haunt past `pirate_haunt_hours`: sails home. Off duty (switch off, unpaid, ord above size): sails straight home and is laid up. |
| `public.tick_pirates(p_now timestamptz default now())` | jsonb | volatile | THE job: pg_cron `byeharu-voyage:pirates`, every minute, never in the beat, `SKIP LOCKED`, at most `navy_steps_per_run` ships a run; lit: pressure written, one ship added, one hour paid. Answers {steps, added, paid, pressure}. W19's hunt lives in `tick_navy`, not here. |
| `world.pirate_ship_card(p_fleet uuid)` | jsonb | stable | **entry point** (in `public.client_rpc_entry_points`, granted to authenticated): everything a player may know of one pirate ship: fleet, home (code), mission, `to`, `eta`, ships, `attack` while attacks are lit. E_NOT_FOUND for any other fleet. |

### Hunks on live bodies (each once, reversing; the newest body that defines each, 0338 included, is the pre-image)

- `public.fleet_kind(p_fleet)`: answers `'PIRATE'` for a row of `pirate_ships`, after the NAVY test, so a merchant's, a cargo ship's and a navy ship's reads are what they were.
- `public.sea_houses()`: serves her with `kind = 'PIRATE'` while at work; `world.sea_roster` and `world.sea_traffic` need no change (they serve `kind` from here). The chart draws kind `pirate` from `KIND_LOOK` (section 9 of the design: crescent hull, an X, red by night).
- `public.fleet_origin(p_fleet)`: her home port, so 0322's wreck and refit take her unchanged.
- `public.crown_house(p_player)`: true for her house (no dock fee, no wage, outside tend and invest).
- `voyage.depart`: the frozen segments are `voyage.freeze_raiders(...)` after `voyage.freeze_danger(...)`.
- `voyage.settle`, the PIRATES arm: `v_pirate := voyage.leg_raider(leg)`; a named raider's strength is `voyage.pirate_strength` (else today's figure, byte for byte); after `raid_takes`: `pirate_stow`; outcome RANSOM: `pirate_ransom` on the cargo's cost basis; a cargo ship with funds aboard PLUNDERED or STRIPPED: `pirate_loot_book` with the day's plunder share. The day's payload gains `pirate: {fleet, name, home}` only when a raider was named, so an anonymous day's payload is byte-identical.
- `public.tick_market_drift`: with the switch on, the four homes' rows are left alone (no regen up, no drift down): the set is read ONCE a run, never per row. Switch off: the body runs as today.
- `public.attack_for`: kind PIRATE with regard `regard_pirate` (dark: `attack_enabled` stays false). `world.navy_ship_card`-shaped card for her.
- `public.client_rpc_entry_points()`: the card.

### What W19 may rely on, exactly

1. Finding her: `public.pirate_ship_in_sea(p_sea)` with the navy ship's own sea (her port's `ports.sea_id` in port; at sea, the `sea_id` of her voyage's current segment). Null means no fight.
2. The fight: `public.fight_sides(p_seed := the navy ship's fleet id, p_round := floor(extract(epoch from p_now) / 3600)::int, p_a := public.pirate_side(pirate), p_b := <the navy ship's side, built as voyage.fight builds a player fleet's>, '{}')`. One call, no timer. Hull loss lands on both through the hull writer 0327 / 0333 use at a battle's close (`public.battle_resolve`'s); her hull at 0 is a wreck by 0322's rule (`npc_wrecked` → `npc_refit_step` from her home's purse, kind REFIT) with no new path. Her `fought_at` is W19's column to write: at most once an hour a ship.
3. Reporting: the world feed line is W19's; W17 only serves her name and home through `public.sea_houses` and the card.
4. W19 never writes `sea_id`, `mission`, `haunt_port` or `laid_up_at`; W17's step owns them.

### What W18 may rely on, exactly

1. The switch `pirates_bite` (through `public.pirates_on()`), the hoard (`public.pirate_hoard()`), the capital (`public.pirate_capital()`), and the ONE cap `public.pirate_spend_room(now)` with the ONE payer `public.pirate_pay(kind, amount, now, p_player := her house)`. A founding that `pirate_pay` answers 0 for did not happen.
2. The kind `PIRATE` is a pirate SHIP; a pirate merchant is a merchant of nation PIR (`npc_houses`), drawn by the client as the pirate merchant look (design 9.3 row "Pirate merchant": `sea_houses` needs the merchant's nation only, which it already serves).
3. `public.pirate_stow` is the one way goods enter a home's stock from plunder; W18's merchants buy from that stock as from any market.

## Consumer audit (every reader of a ship kind, and what each does with a pirate ship after this slice alone)

(filled in as the build proceeds)
