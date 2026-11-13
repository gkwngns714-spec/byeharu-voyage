# 0373: a company stands with each country (lights `regard_enabled`)

Owner, 2026-11-13 (row 324): *"do all, make everything work. open them if everything is built and is workable."* Row 288: *"we need to build systems such as affinity prior to the system"*.

0319 built regard dark (`docs/dev-log/2026-11-06-a-house-has-a-regard.md`). This is the light: one migration in the form of 0178 and 0179. It comes before attacks on purpose: an attack costs regard only while this is lit. **Nothing here was run on production. No switch was touched.** Measured on the local PGlite world, cached prefix at `origin/batch-6`.

## What lit regard does, in one table
| Stance of her power with the city's holder | Day-one score | Band | Tax and dock fee |
|---|---|---|---|
| Home | 200 | Friendly | **x0.9** |
| Ally | 100 | Neutral | x1 |
| Peace | 0 | Neutral | x1 |
| Rival | −100 | Neutral | x1 |
| War | −200 | Wary | **x1.25** |
| A free city (no holder) | none | none | x1 |

Gifts and stakes earn 10 points a 100,000 d. Earned points halve every 72 hours. 150 is Friendly, 500 Honoured (x0.8); −150 is Wary, −300 Hostile (x2). A merchant, a cargo ship, a navy ship and a pirate ship have no regard.

**So on day one, with no row written: every company pays 10 % less tax and dock fee at home, and 25 % more in every city of a country her power is at war with.** Nobody else moves.

On the local world (13 companies, all Portuguese, 11 countries that hold a harbour): 143 pairs, 13 Friendly (home), 26 Wary, 104 Neutral. Each Portuguese company pays less in Portugal and more in two countries: the Netherlands (NLD) and the Brethren (PIR), the two Portugal is at war with there. `before-light.sql` reads the same list for prod's companies.

**One thing the owner should know: the tax reads the factor only where the city purses, the influence race and the closed economy are all on** (`world.tax_rate` returns earlier otherwise). All three are recorded true on prod; `before-light.sql` and `after-light.sql` print it as `tax_reads_regard`. The dock fee reads it wherever a dock fee is charged.

## What was owed, and what was found
1. **An after-light check** (the audit: none existed). `scripts/ops/harness/regard/after-light.sql`, new, read-only, one statement, a 30-minute window: the companies' taxes and dock fees taken, by the band the payer stands in with the city's holder (payments, coin, factor); earned rows (count, below zero, a merchant's: wanted 0) and the events that wrote them; FINE flows (count, coin into the capitals, against the ledger's FINE rows).
2. **A before-light read of who pays more.** `scripts/ops/harness/regard/before-light.sql`, new, read-only, one statement: one row a company with `pays_less` and `pays_more` (country, stance, band, factor) and how many countries stay at x1; the last row is the world (the switch, earned rows, pairs by band, `bad`, `tax_reads_regard`). **If it errors with `E_NO_REGARD_BASE`, do not light**: a stance has no base and every tax quote in that country's cities would fail. The migration holds the same read as an assert.
3. **Do 0360 / 0361 (the trip's price, Trade's true cost) carry the multiplier lit?** Yes. **Nothing needed fixing**: both ask `public.port_fee` and `world.tax_rate`, the two bodies 0319 cut. Proof 74 measures it instead of reasoning it:

| Marker | Result |
|---|---|
| LIT_BY_0373 | switch true, no earned regard, one news row |
| LIT_DAY_ONE | at home Friendly x0.9; in Amsterdam (at war) Wary x1.25; a free city and a merchant x1; Lisbon's dues carry {score 200, band friendly, factor 0.9} |
| LIT_TRIP_FEES | `world.trip_cost`, Lisbon to MID and back: MID (x1.25) dock fee 625 (dark 500); Lisbon (x0.9) dock fee 56 (dark 63) |
| LIT_TRIP_CHARGED | sailed by the real commands: MID charged 625 and Lisbon 56, as the read named |
| LIT_BOARD | Trade's board, 63 one-leg sell rows over 12 goods, 24 of them in a city where her factor is not 1: each dock fee is the dark row's times her factor there, to the ducat; no tax moved against it |
| LIT_GIFT_EARNS | a gift of 100,000 at Lisbon through `cmd.donate`: regard with Portugal 200 to 210, one row, one event, the hall's score follows |

4. **The Levels page and the Town Hall band, lit, at 390 and 320, EN and KO.** See "In a browser" below.

## What the file does
`supabase/migrations/20260818000373_a_company_stands_with_each_country.sql`, one DO block:
1. **Refuses** unless the switch reads exactly false and nobody holds earned regard (`house_regard` empty: every writer was dark).
2. **Refuses** if, for any company and any country that holds a harbour, `public.regard_of` fails or `public.regard_band` finds no band with a factor (the day-one read).
3. Writes the one row.
4. A probe company of Portugal and a probe merchant, rolled back, with the closed economy, the purses and the influence race set inside the probe (as on prod): at home the Friendly factor, her tax rate the dark rate times it and her dock fee the dark fee times it; in a city at war the Wary factor; a free city and a merchant x1; the hall's line; 25 points earned are her row, her event and her score; the rollback played (factor 1, the dark figures, no line, the fine refused `E_NOT_IN_USE`).
5. No function moved, no other knob moved. News: **"Standing with each country: tax and dock fee" / "나라별 평판: 세금과 입항료"**. Budget 30 s. Locally 0.07 s (the day-one read of 143 pairs 15 ms).

A mistake of mine, found by the file's own assert on its first run: the probe called `world.tax_rate(player, port)`; the signature is `(port, player)`. Then the same assert showed the tax did not move at all on the local world, which is how the three-switch condition above was found (the local world has the influence race off).

## Proofs with 0373 in the chain
- Proof 74: 6 of 6. Proof 27 failed on "regard is not dark in this world": it now sets the switch back at its start (rolled back), and is 12 of 12.
- Every proof that touches tax, dock fees or regard was run with regard lit in the chain (23 files): results in the PR.

## In a browser, lit (headless, port 4421)
New `tests/regard.lit.spec.ts`, at 390 and 320 px, English and Korean (8 tests, 8 passed after the fixes below; the pictures were read):
- **The Levels page**, the world as shipped: the Countries list no longer says "Not open yet."; ten countries, each with her band and score: Portugal Friendly 200, Castile-Spain and England Neutral 100, the Ottoman Empire Neutral −100, The Netherlands Wary −200. Nothing cut, no sideways scroll.
- **The Town Hall's band**: the City page's Relationship cell reads "Friendly" / "우호" at home (`data-band` friendly) in place of the stance's word.

**Found and fixed: the Levels page named the countries in English on the Korean page** ("⚓ Portugal 우호 200"). The list was dark until now, so nobody had seen it. `src/features/command/levels/Levels.tsx` now names a country through `properName('nation', code, name)`, the one authority for a proper noun; the spec holds that no row of the Korean list carries an English name ("포르투갈 우호 200", "네덜란드 경계 −200").

**Found, a fact about the hall and not a fault:** the hall serves its dues, and so her band, only where the city purses are lit and the economy is closed. Both are true on prod. The shipped local world has neither, so its hall shows the stance's word; the hall test runs on a copy of the image with the purses lit by the chain's own switch and the economy closed. Regard itself is never set by a patch: it is the chain's.

My spec was wrong twice on its first run, the page was right both times: a score below zero is printed with the minus sign (−, as every figure is), and the hall test had not closed the economy.

Other specs on the lit build: `rpc.regard`, `map.townhall` (the fine paid at the capital), `city.page`, `city.live`, `hq.design`, `goal.card`, `desk.inplace`, `reputation`: results in the PR.

## Specs and proofs that assumed regard dark (each changed)
| File | What it assumed | Change |
|---|---|---|
| `scripts/db/proofs/27_regard.sql` | "regard is not dark in this world" was a failure | Sets the switch back at its start (rolled back with the proof) |
| `scripts/db/proofs/33_levels_page.sql` | the same, "the proof owns the dark start" | The same |
| `scripts/db/proofs/45_the_brethren.sql` | Lisbon's dues factor is the home factor alone | Sets the switch back at its start; it lights regard itself where it reads the Levels list |
| `tests/rpc.regard.spec.ts` | the built world is dark | Sets its own database dark first |

## Rollback
One line (owner only): `update public.world_config set value = 'false'::jsonb where key = 'regard_enabled';` Every factor is 1 at once; earned rows and FINE rows stay. As a migration: `scripts/ops/harness/regard/rollback-0373.sql` (draft; run on the local world after 0373).

## Not proven
- Nothing ran on prod. Who really pays more is `before-light.sql`'s answer on prod, not this file's.
- `Pay fine` with a real player: nothing lowers regard until attacks are lit, so no fine can be owed yet (`tests/map.townhall.spec.ts` plants one and pays it).
- Whether the bands and the half-life feel right: only play shows.

## Found on the combined tree (batch-7): the port dues seam assumed regard dark
`tests/rpc.portDues.spec.ts`, "a Dutch company at Lisbon reads tax 2x (at war)", pinned `factor: 2, fee: 500` and received `factor: 2.5, fee: 625`. **The server is right.** 0319 cut the regard factor into `public.port_dues` and `public.port_fee`: a company at war stands Wary on day one, so she reads the war factor 2 times 1.25 = 2.5, and a dock fee of 250 x 2 x 1.25 = 625. The hall's words say what she pays: "Tax 2.5x (at war) · Dock fee 625 · Wary -200". The spec was written before regard and I had not run it (it does not name the switch).

It now states both arms by name: regard put off in its own world (factor 2, fee 500, no regard line: the figures before 0373 and after its rollback), and regard as the world ships (factor 2 x the war band's factor, fee 250 x that, the regard line with her band, and three parts in the words). The band's factor is read from the knob, never pinned.
