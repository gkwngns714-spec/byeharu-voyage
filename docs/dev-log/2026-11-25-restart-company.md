# 2026-11-25 — `restart-company`: 0509 (dark: `restart_enabled`, `hq_cities_enabled`), proofs 213, 214

The owner (R1): *"Right now my account does not have a designated HQ. I need a way to restart the game."* (R2): *"The specific requirement
will be set by me after reviewing all the contents that has been made."* Branch `restart-company`, on `company-name` (0503) with
`origin/main` merged. Nothing touched production; no live company is restarted by the file, by a proof or by a person: the owner presses.

## 1. Why a company shows no HQ (read in the code)

There was no HQ on record. `CityScreen.tsx` drew `?port=`, else the harbour of the FLEET IN HAND (docked, or where she is bound), else the
first fleet's. A fleet bound for open water showed "No city in hand". The one served idea of a home, `public.home_port_of` (the port of
the founding event), is read by requests, land, and bring-home jobs, never by the HQ screen; `world.player` serves `lying_at` (a fleet's
place) and says so itself. Nothing is wrong with the owner's account in particular; H4 was not built.

## 2. HQ

- `public.company_hqs(player, slot 1..5, port)`. Row 1 of every existing company: **her country's capital; her founding port where she has
  no country or its capital is no harbour.** A company that changed its country gets the NEW country's capital (the owner: "your first HQ
  will be in your CAPITAL CITY"). New companies get row 1 in `public.new_house`. A later change of country moves it not.
- `world.player().hq` = `{at, list, next}`. HQ shows `?port=` (the HQ chosen, or the Map's "HQ here"), else `hq.at`, never a fleet's city.
  The city's name is the press that opens the list (a pop-up page; nothing moves).
- No switch for this: it fixes what HQ shows and moves no coin, good, right or price.
- Dark (`hq_cities_enabled`): the ladder is data (`public.hq_steps`, plan 0.4's placeholders, NOT approved); **no door opens an HQ**; lit,
  `home_port_of` becomes slot 1. It is under the switch because it would move the home of a company that changed its country (its shed,
  requests and land party). `before-0509.sql` prints how many (`moves_home`).

## 3. Restart: every place that resolves the signed-in player

`current_player_id()` (the one reader of `auth_uid`, used by the doors and 15 policies); `found_house`; `new_house` (writes it);
`fleet_jobs_due` / `fleet_job_open` / `tick_fleet_jobs` (the tick acts as the account); `houses_week_settle`, `settle_standings` (a board
place asks for a login); `world.building_yard`, `inn`, `warehouse`, `workstation` (read `auth_uid` themselves); three policies
(`players`, `player_items`, `player_storage`); `assume_identity`. All of them go through the one column, so retiring = `auth_uid` null on
the old row, and founding puts it on the new one, in one transaction.

## 4. What happens to each holding (45 references of `players`, 22 unconstrained columns)

| Holding | At the restart |
|---|---|
| The row of `players` | stays: `retired_at` set, no account, no country, purse 0, name "Closed company xxxxxxxx" (her name is free at once) |
| `events`, `ledger`, `level_book`, `reputation_book`, `capital_gifts`, `treasury_flows`, `contract_deliveries`, `world_news` | stay, untouched (one closing event and the closing ledger rows are added) |
| Purse | paid to her country's capital (ledger and flow `COMPANY_CLOSED`); no influence, no investment, no city profit, so no dividend from it |
| Debts to cities | paid first from the purse (`port_fee_collect`); what it cannot pay is written off (a debt is no coin) |
| Market requests | closed; the coin held returns first |
| Courier contracts she posted, nobody took | taken down by the one settler; reward and goods back |
| Courier contract she carries | fails by the ordinary rule: what she still has goes back, the poster gets her collateral |
| Courier contract of hers another carries | **refused** (`E_CONTRACT_OUT`): its coin cannot be settled before delivery or deadline |
| Shares, set-aside and dripping dividends | the set-aside is paid to her; the shares end; the works stay built and pay her nothing |
| Ships and cargo: in port, at sea, wrecked, adrift, under repair | gone, with cargo, stores, crew, fittings and their experience. Goods are no coin and go with the hull (as in a wreck): no city's stock or price moves |
| In battle (or a wreck on a side of one) | **refused** (`E_IN_BATTLE`) |
| Fleets, orders, jobs, routes and laps, armadas, voyages, choices at sea, early sightings, raid orders, wages owed | deleted with the fleets |
| Insurance | the voyage ends, the policy lapses, no claim (the premium was paid to the city) |
| Sheds, gear, presets, captains and their seats and traits, land party and its tools, ships on order, skill queue | deleted (what was paid is already in cities) |
| Mayor's seat | empty until the next daily count |
| Influence, regard, wanted, country race, week board, Rank | deleted: she votes and ranks nowhere |
| Reputation, levels, skills, logbook, goods mastery, first voyages, month books, history | the old row's record; unreachable; the new company starts at nothing |
| City month book (gifts of all time) | stays in the city's totals; her line is not shown |
| An old request she fulfilled (`trade_contracts`) | keeps her id and figures, no longer names the fleet (status `spent`) |
| `company_hqs` | deleted |

Boards that now leave a closed company out: Rank (`settle_standings`), the leaderboard (`stats_me`), the Town Hall's givers and gifts,
the city's history. A feed of past trades or money may show "Closed company xxxxxxxx" until it rolls off.

## 5. Decided by default (the owner may reverse each)

1. Everyone, once a real day (UTC) an account. 2. The ordinary start; starting money is `founding_credit`'s (closed: the capital pays).
3. Europe = a capital in one of the eight European regions: Portugal, Spain, England, the Netherlands, France, the Ottomans. Founding
itself is not changed (slice `europe-start`). 4. Her own old name may be taken again; the new company has its one free rename.
5. Confirmation is the company's name, exact. 6. No undo.

## 6. Safety

House row first, then her fleets SKIP LOCKED (`E_BUSY` when the beat holds one), `lock_timeout` 3 s inside the core, a deadlock or
lock wait answers `E_BUSY`; any refusal, also of the founding, undoes everything. Dark: `E_NOT_IN_USE`.

## 7. Risks for live players

- HQ no longer follows the fleet. A player who used HQ for a fleet's city now uses the Map's "HQ here" (or Trade's link).
- **A restart a day is 40,000 starting money a day from a capital.** It is moved, not made, but an account could give it away (a courier
  reward to a friend) and restart. Watch `COMPANY_CLOSED` against `FOUNDING` before and after the light; a lower start for a restart is
  the owner's call.
- A rich company's purse lands in its capital in one piece (its bid factor and restock react as to any inflow; it is no profit).
- Cascade time on a company with thousands of voyages was not measured on production data (`voyages_rows` in before-0509).
- Lighting `hq_cities_enabled` moves the home of companies that changed country.

## 8. Verified

Local PGlite on main's chain + 0498 + 0503: 0509 applies in 0.8 s with its probe; proofs 213 (8 markers: every holding, closed economy,
world sum to the coin) and 214 (4 markers) green; before / after harness run; `tsc`, `eslint`, `vite build`; `tests/restartCompany.spec.ts`
at 390, 320 and 1440 px. The results of the other specs are in the report.

## 9. Not verified

Real PostgreSQL (CI), production, the stack 0499 to 0508 under this file (hunks refuse if a body moved), two sessions racing a restart
with the beat, the full suites.

## Rollback (forward, owner only)

`restart_enabled` false closes the door. A migration reversing the twelve hunks (OLD texts verbatim in the file). A closed company is
not reopened: `company_retirements` keeps her name, country and account for the record.
