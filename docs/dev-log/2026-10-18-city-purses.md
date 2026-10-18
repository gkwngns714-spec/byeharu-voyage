# 2026-10-18 — a city is rich, and its money comes back — `osn-city-purses` (migration 0172, provisional)

**The owner, 2026-10-17 ~23:50 UTC:** *"Right now you said that london does not have enough money to
do a trade. But this should not happen. Cities are powerful, and they should have some millions of
gold as a start. Especially capitals. Provide capitals to capital cities, and then make the economy
circulate."* Numbers (brief, default yes): a city 2,000,000 d., a capital 10,000,000 d. The
circulation design came from the coordinator (default yes; the owner may reverse it): six points,
answered one by one in §2.

## 1. Why London was broke (prod, read-only, head 0169, 2026-10-17 23:51 UTC)

All figures are from `treasury_daybook` + `treasury_flows` since the switch (`seeded_at` 11:19 UTC):
15 full game-days (622304–622318; a game-day is `game_day_seconds` = 2,880 s = 48 real minutes).

- **The seed was 20,000 d. for every harbour.** 0122 seeds `greatest(city_seed_min, 10 × mean SELL
  day)`, and at the first switch there were no books, so every one of the 238 harbours got the floor:
  Σ SEED 4,760,000.
- **London's trade was flat, not losing.** Paid for its goods (BUY) 1,234,736; paid for cargo (SELL)
  1,292,186; services +26,553; works −29,115; shares +51,712; bounties −11,194; coupons −468: net −19,962 since the switch (rolled and unrolled), i.e.
  +4,344 a game-day over the full days, then −205,070 in the last two (22:24 and 23:12 UTC). Its day
  swings ±100–200 k. With a 20 k purse it sat at **4,129 rolled (59 live)**, reserve 220,305 (3 × its
  SELL day 73,435), **bid factor 0.509**.
- **So no inflow was missing at London — the purse was too small for its own turnover.** 142 of 238
  harbours were under their reserve, 23 under 1,000 d., all for the same reason.
- **The whole world:** cities paid 74,215,168 for cargo and were paid 72,984,417 for goods; services
  into cities 4,323,000 (TAX 825,240 · WAGES 1,843,249 · PROVISION 725,575 · REPAIR 694,849 · TUITION
  157,500 · TOW 67,578 · HIRE 8,500); SHARE 9,501,119; DONATION 546,305; out NPC_REFOUND 2,226,563,
  DIVIDEND 111,234, BOUNTY 41,481; WORKS_OUT = WORKS_IN 21,578,062 (city → region). Over the full
  days the cities as a whole **gained** +761,566 a game-day; 120 harbours lost, together −105,938 a
  game-day. The worst losers sit at ≈ −1,320 a game-day — that is the 20 k seed running out over 15
  days, not their demand: the half bid hid how much they would buy.
- World money now: merchants 39,469,552 (capital 26,061,000, 821 companies), 17 players 210,673,
  city purses 16,439,551 rolled — **≈ 56.1 M**.

## 2. The six circulation points

| # | Point | Found on prod | Done here |
|---|---|---|---|
| 1 | A city earns from what it makes (players AND merchants) | **Already true.** `cmd.do_buy` → `pay_city(…'BUY'…)` for every house; merchants trade through the same body. 72,984,417 in 15 game-days. | nothing |
| 2 | Every port service pays the port | **Already true.** Every `credit()` debit outside the founding goes through `pay_city`: BUY, TAX, PROVISION, REPAIR (and gear repair, `unmount_fitting`), HIRE, BUILD, TUITION, OFFICER_WAGE, TOW, SHARE, DONATION, WAGES. Direct `credit()` calls left: FOUNDING (new house; a merchant's founding tuition, paired with its TUITION flow), DIVIDEND/PREMIUM (paid from money the city already set aside), NPC_REFOUND (the dark branch). **Harbour dues: not added** — the owner's 2026-10-15 decision (`docs/ECONOMY_LOOP.md` §11, "no harbour dues"). | nothing |
| 3 | Wages are spent ashore | **Already true, not a sink.** 0122 pays a voyage's `wages_paid` into the harbour she makes (`voyage.settle` → `treasury_post(dest, 'WAGES', …)`): 1,843,249. | nothing |
| 4 | The capital is the crown treasury | missing | `CROWN_TAX`: 10 % of each city's daily TAX to its capital. `CROWN_AID`: a city under its reserve is topped up to it from what its capital holds above its own reserve. City → city, conserved. Country = `port_nation` (0143), so a country with more cities has a richer crown. |
| 5 | Goods a city buys don't vanish | **Already true.** A city's purchase enters its `port_goods` stock and is sold to later buyers (BUY ≈ SELL world-wide, above); drift is the population consuming. Their "payment" is (6) — a separate consumption flow would count it twice. | (6) |
| 6 | Development income | missing | `EARNINGS` = 100 × (dev_industry + dev_commerce + dev_military) × (1 + 0.10 × Σ works levels) a game-day — 1,700–5,000 at level 0, up to 3× with twenty levels — **only up to the standing purse**. Investment raises the levels, so it raises the earnings; coupons are paid from a city's surplus, so from this. |

## 3. The fix (migration 0172)

- `public.city_standing(port)` — 10,000,000 for a country's capital (`nations.capital_port_code`, 23
  on prod), 2,000,000 else. The reserve rule is untouched: the largest reserve is 534,414, so a
  capitalised city bids 1 (asserted for every harbour).
- **The GRANT**: every harbour under its standing purse is topped up to it (never down) through
  `treasury_post`, kind `GRANT`, one flow each, under the harbour's lock; `world_config.city_grant_0172`
  records when, how many, how much. Measured gap today: **644,632,294 d. over 238 harbours**. It
  reaches the bid at the next `:37` roll. Dark (a fresh chain), nothing is posted; the switch's seed
  is now `greatest(standing, city_seed_min, 10 × outflow)`.
- `public.city_day(p_now)` — tick_city's new step 6b: CROWN_TAX and EARNINGS once per completed
  game-day (`port_treasury.earned_day`), CROWN_AID every hour.
- **The self-build gate.** tick_city step 4 subscribed a city's own works from everything above its
  reserve. With 2 M every harbour would buy all twenty levels (~1.26 M) within a day: no share left
  for a house, so a merchant's surplus could never come back as shares and influence through shares
  would stop. Step 4 now builds only from what a city holds above `greatest(reserve, standing)`.
- Town Hall "Yesterday" names Grant, Earnings, From the crown, To the crown.

## 4. The 7-day replay (scratch `sim.mjs`, prod daybook, read-only)

Each city's 15 full game-days are replayed in a loop for 210 game-days (7 real days) from
`max(today's balance, standing)`, with CROWN_TAX, CROWN_AID and EARNINGS as built. Two cases:
**base** = the books as they happened; **stress** = every SELL divided by the bid factor the city was
making that day (reconstructed from seed + cumulative books and the 3 × SELL-day reserve), i.e. what
the cities would have paid at full bid for the same cargo.

| case | knobs | below reserve | below zero | worst (min − reserve) | EARNINGS minted / 7 d |
|---|---|---|---|---|---|
| base, no earnings/crown | — | 0 | 0 | +1,572,671 | 0 |
| stress, no earnings/crown | — | 1 (Palermo) | 1 | −515,331 | 0 |
| stress, crown only | share 0.10 + aid | 0 | 0 | 0 (Palermo held at its reserve by Seville, its capital) | 0 |
| **base, as built** | 0.10 / 100 / 0.10 | **0** | **0** | **+1,572,699** | **23,417,994** |
| **stress, as built** | 0.10 / 100 / 0.10 | **0** | **0** | **+356,882** (Palermo min 582,837) | **47,818,709** |

London (as built): base min 10,000,000, end 10,927,248; stress min 9,824,251. No harbour's bid falls
under 1 in either case. Limits, stated: the replay holds trade fixed (merchants would re-route toward
full bids); it repeats the merchants' SHARE investments, which their purses could not keep paying, so
its "cities end richer" is not a forecast — the drains are what it measures.

## 5. Money in and out of the world, before and after

| per real day | before 0172 | after 0172 |
|---|---|---|
| minted | FOUNDING of new houses (~0.3 M in the 12 h measured, incl. merchants' founding tuition) | the same + **EARNINGS 3.3–6.8 M** (replay base–stress) |
| one-time | SEED 4.76 M (2026-10-17) | **GRANT 644.6 M** |
| destroyed | ≈ 0 (the two stated leaks of ECONOMY_LOOP §1.2) | ≈ 0 |
| world money | ≈ 56.1 M | ≈ 700 M at the grant; +0.5–1 % a day while cities refill |

Knock-on, measured or read:
- **Prices**: no price reads the world's money (`world.quote` reads stock, affinity, spread, tax and
  the bid factor); the only price move is the bid factor going to 1 at the 142 thin harbours.
- **Merchant purses** (39.5 M vs a 52.1 M cap at `npc_invest_above` 2 × capital): refounds, coupons
  and bounties were starved at thin harbours and will now be funded — merchant purses rise toward the
  cap and the surplus returns as shares (more shares are on offer now that cities stop buying their
  own). Coupons at `works_coupon_pct` 0.003 a game-day on 9.5 M paid ≈ 0.86 M a real day.
- **Influence**: `influence_post` counts the coin a house gives (DONATION, SHARE); no purse figure
  enters it, so Donate (min 100, claim 10,000, day cap 20,000) costs exactly what it did. Shares stay
  buyable because of the self-build gate; without it the share route would have closed within a day.
- **The brake**: EARNINGS stop at the standing purse, so a city above it mints nothing; the world's
  money grows only by what cities lose to houses and earn back.

## NOT the owner's — confirm
- crown_tax_share 0.10, city_earnings_per_dev 100, city_earnings_per_level 0.10 (each one knob).
- Earnings stop at the standing purse; the self-build gate.
- No harbour dues (kept per 2026-10-15); no new sink.

## Verify
Run once each, this worktree (off main `1001a13`, no `.env.local`):
- **Hunks against prod**: `tick_city` (5) and `city_treasury_switch` (1) re-dumped from prod at head
  0171 with `pg_get_functiondef` (read-only) — each hunk occurs exactly once.
- **Cached-prefix build** (`BYEHARU_PREFIX_CACHE=required npm run build`, tsc -b + vite): restored
  162/164 from `browser-p0162-909b21f66e87d5be`, applied 0171 + 0172, chain 11.6 s, built 17.6 s. The
  0172 receipt on the fresh (dark) chain: no GRANT; THE DAY probe crown/earnings/aid exact; THE BUILD
  probe — under standing 0 shares (the old rule bought 50), above standing exactly 50; one lit
  tick_city with the day step 39 ms.
- **A lit world** (PGlite, snapshot p0162, switched on, purses made uneven, then 0172 applied):
  receipt ok — 167 harbours granted 458,731,301 d. (London 3,214,286 → 10,000,000); THE DAY
  "crown 1000, earnings 5940, aid 35060; again 0; at standing 0"; 287 ms. After it 0 harbours under
  their standing purse; the next tick_city: 0 thin, no errors, 71 levels built only by the 80 harbours
  the test had put above 2 M.
- **eslint .** clean. **Playwright** (preview on localhost:4275), the specs `select-specs` picks for
  this diff except the two Node-chain ones: 67 passed of 67 listed (map.townhall, map.flag,
  rank.countries, route.stopface, rpc.outlook, rpc.surface, sea.dateline, duplication). **db.chain /
  db.image were not run locally** (no Node chain-prefix cache on this machine — it would apply from
  zero); CI runs them.
- Migration renumbered 0170 → 0171 → **0172** as main moved; numbered head + 1 at deploy.
