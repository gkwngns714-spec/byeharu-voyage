# 2026-10-31 — Status and Relationship, served

Owner: *"status and relationship too"* (2026-10-31) — the two remaining figures on the City page's
card must be filled like Population, honestly, from served data.

## What the server already carries (chain read, and prod read-only)

| Fact | Where | What it is |
|---|---|---|
| The company's nation | `public.players.nation_id` → `public.nations` (`PlayerHouse.nation` / `nation_name`, 0014/0028/0187) | The code the company sails for; a company may have none. |
| The city's holder | `public.port_nation(port)` → `world.allegiance` (`PortAllegiance.nation/home/ruler`, 0143–0148) | The country that holds the harbour today; `home` marks a city that never changes hands. |
| How two powers stand | `public.power_relations` + `public.power_stance(a,b)` (0196) | 'home' when the same power, else the authored row ('ally' / 'rival' / 'war'), else 'peace'. 13 authored pairs. |
| The harbour's stance toward the company | `world.town_hall(port).dues` → `public.port_dues` (0237) | `{stance, factor, fee, …}` — the SERVED relation between the company's nation and the city's holder, or `{}` while the economy is open / the purses are dark / the port has no treasury. |
| The company's standing in one city | `public.port_influence` (0144) → `world.town_hall.influence.you` | `points` (coin given here under the country it sailed for then, weighted and decaying), `given_today`, `cap`, `min`; `shares` per country; the weekly `investors` board (0275) and `city_history` (0278) list the city's givers by name. |
| The company's rank among the givers | `public.investor_rank(player, port)` (0191) | 1 + the companies with more points here; null with none. Not needed for the card. |
| Per-port acts | `public.ledger.port_id/fleet_id/voyage_id` (0284) | Every ledger line names its city, so standing can be audited from acts. |

There is no separate reputation/trust table: the influence book IS the per-company per-city standing,
and `power_relations` IS the relation between nations.

Prod read-only confirmation (2026-10-31, head 0285): `power_relations` 5 ally / 6 rival / 2 war (13);
`port_influence` 3,806 rows, 814 companies, 236 cities, all with points > 0; company nations
OTT 126 · PRT 121 · ESP 111 · NLD 94 · MUG 78 · ENG 77 · JPN 66 · MNG 66 · FRA 65 · JOS 36; a real
Lisbon dues sample: PRT company → stance `home` (factor 0.25, fee 63), JPN company → `peace`
(factor 1, fee 250). Every function called here is STABLE (`power_stance`, `port_nation`, `port_dues`,
`economy_closed`, `city_treasury_on`, `investor_rank` — all `s`).

## What each cell shows now

- **Status** = `world.town_hall.influence.you.points` — the company's own influence in THIS city, as a
  grouped figure (0 = no standing yet). No estimate, no new read: it rides the hall's one block the
  page already reads for the city's purse.
- **Relationship** = the harbour's served stance `world.town_hall.dues.stance` when it is served
  (Home port / Ally / Peace / Rival / War — `public.power_stance`). While the dues block is not
  served (economy open, purse dark, or no company) the card compares the two SERVED nations — the
  same `world.allegiance` holder the header's flag reads and the company's own nation: same nation
  is a fact (Home port), different nations are a fact (Different nation), a free city is a fact
  (Free port), no company is a fact (No nation). It never guesses an ally or a war.
- The "next slice" caption is removed: nothing in the card is absent any more. Population keeps its
  own "estimated from the city's size" caption; Status and Relationship carry no estimate.

## Measured (headless chromium, local build, port 4206)

- 390×844: `status: Status 0`, `relationship: {"text":"Relationship Home port","stance":"none",
  "nation":"PRT"}` — the local world does not meet the dues guards, so the served-nation fallback
  applies; the holder is PRT and the local company sails for PRT. Summary card 437 px, no scroll.
- 1280×900: same words; summary 154 px (the caption line's removal made the card's content floor
  smaller); no scroll; the whole city still drawn.
- The spec waits for the served reads (the cell prints '—' until the hall's block lands): Status
  until the dash clears, Relationship until `data-nation` carries the served holder code.

## Gates

- `npx tsc -b`, `npx eslint src/features/city src/lib/i18n/dict/city.ts`, `npm run build` — clean.
- `tests/duplication.spec.ts` — 11/11.
- `tests/city.page.spec.ts` — PASS (42.9 s): Status shows a served number and is not a placeholder;
  Relationship prints one of the city's words and carries the served holder nation (or the served
  stance when prod-like guards are met); no page scroll at 390/320/360/1280/1440; the whole-city,
  figures-card, population, tile-face and walker proofs stay green.

## Screenshots (DPR 2, test-results/, gitignored)

`sr-full-390x844`, `sr-full-1280x900`, `sr-panel-390x844`, `sr-panel-1280x900`. Judged: the card at
390 and wide reads Population ≈ 160,000 (estimate caption), Gold 0, Status 0, Relationship Home port;
the caption line is gone; no overflow.
