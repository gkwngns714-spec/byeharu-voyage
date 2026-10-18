# 2026-10-18 — 0173: a good is worth the sea it crossed (the distance term) — `osn-distance-prices`

**The owner's order (2026-10-17 ~23:50 UTC):** *"i told you, the distance ratio should make kimchi higher for
cash. for example korea - london is one of the longest trip. you bought for 100, it should sell for like 50k
each. Or something like that. Do a thorough research on 대항해시대 오리진 again, and check for trading prices
and apply. This is also very important."*

**Not deployed.** Migration 0173, on prod head 0172 (the city purses, #194). Renumber to head + 1 at deploy if
another file lands first. Cut against main 70f606f (head 0172).

## What prod did (read-only, 2026-10-18)

Kimchi is made at Mokpo only (`port_specialties`). It cost ~100.70 a jar there. London's middle price was ~130
(prod's London row: affinity 1.425, mid 129.99). That is 1.3×, for a passage of 14,006 sailing nm (Mokpo →
London round the Cape, `sea_reaches`).

The only distance in the price was `port_goods.affinity` (0005). It is a **great-circle** gradient, and it
saturates: `affinity_home 1.00 + affinity_span 0.76`, so at most 1.76×. Distance from the maker could not move a
price any further than that.

## The research

The research is in `docs/research/UWO_TRADE_PRICES.md`. Every number in it has a URL, and sourced facts are kept
apart from inference.

What it found:
- Origin's sale multiplier is distance-based. Since its 2024-12 notice it is measured on the **sailing** distance.
- The ratios players quote, sell ÷ buy:

  | haul | ratio |
  |---|---|
  | adjacent sea | 1.2–1.5× |
  | one ocean | 3–5.5× (~10× for a cheap specialty) |
  | the far side of the world | 16–40× (nutmeg ~16×; Origin's East Asian perfume ~40k net a unit) |

- The shape is convex: flat near home, steep over an ocean.
- No source publishes the formula itself.

The owner's number sets the scale: ~500× for Korea → London. That is an order of magnitude past the games' own
figures, and the research doc records it as a deliberate choice.

## The design

    haul(nm) = haul_max ^ ((min(nm, haul_reach_nm) / haul_reach_nm) ^ haul_curve)
    haul_max 600 · haul_reach_nm 14,500 · haul_curve 2.0          (world_config, described)

| sailing nm from the nearest maker | 1,000 | 2,000 | 3,000 | 5,000 | 7,000 | 10,000 | 12,000 | 14,006 | ≥ 14,500 |
|---|---|---|---|---|---|---|---|---|---|
| haul | 1.03 | 1.13 | 1.32 | 2.14 | 4.45 | 20.9 | 79.8 | 391 | 600 |

Combined with affinity's own slope, the whole distance gradient reads:
- adjacent sea ≈ 1.1–1.3×;
- one ocean ≈ 3×;
- 10,000 nm ≈ 30×;
- Mokpo → London ≈ 390× on the haul alone.

That is the research's shape, with its far end stretched to the owner's figure.

**One authority each.** Nothing outside this list prices the haul:

| concept | its one home |
|---|---|
| the arithmetic | `world.haul_at(nm, max, reach, curve)` (immutable, server-only) |
| the derivation, every market row at once | `world.haul_rows()`: the nm by sea (`public.sea_reaches`, the water raster's own nm) from the nearest city whose roster offers the good (`public.port_offered_goods`, the authority `world.affinity_for` reads). 0 nm at a maker, null where no lane reaches (haul 1). |
| the stored term | `port_goods.haul_nm numeric(8,1)` and `port_goods.haul numeric(10,4) ≥ 1`, filled from it. A quote reads one more column and does no new arithmetic. |
| kept | `scripts/db/world-guard.mjs` compares every row with `world.haul_rows()` on every chain apply, with its own planted-bend positive control. A roster, sea or knob change that forgets to refill is a red. |
| the one price expression | `world.mid_from_terms` gains `p_haul` (after `p_demand`), multiplied onto the **banded** product. The 12-argument form is dropped. |
| the one reader of a row's terms | `world.mid_terms` gains `OUT m_haul`. It is dropped and recreated because its OUT row changes; its ACL is put back and compared. |

**Re-cut to pass it:** these are every body that names `world.mid_from_terms`. The set was found by a catalogue
search on prod and asserted before and after.
- `world.mid_price` (1 hunk)
- `world.quote_priced` (2 hunks: both sides' steps)
- `public.price_path` (3 hunks: 0170's mid, lo and hi)
- `world.market` (2 hunks: range_lo and range_hi)

Everything else reads the haul through them without a hunk: `world.price`, `world.quote`, `world.trade_routes`,
the NPC planner (`npc_leg_lines`, `npc_buy_ceiling`), `tick_price_snapshot`, 0170's `world.price_outlook`, and
0171's `world.good_board` / `world.watchlist`.

**The band.** `price_band_lo/hi` (0.35–3.5 × base) would have clipped the haul to 3.5×. It is not removed. It
now bounds the market's own swing (stock, drift, season, demand) **around** the haul: `band × base × haul`. So it
is widened exactly by the distance, and no further.

**What a player can buy does not move.** A quay sells only what its roster offers, and every offered row has haul
1 (asserted: 1,348 rows). So the term is a pure rise in what a far city **pays**.

**Selling volume still depresses the price.** The stock term √(target / stock) is untouched and still walks
10 tuns at a time. 100 jars sold at once in London average 46,834 against a 52,170 bid.

## Before / after (fresh chain at head 0172 + 0173)

Measured with `node scripts/measure-haul.mjs` (kept under scripts/, not scripts/db/, so a PR that adds it does not
trip the chain-machinery growth test). "Before" holds every haul at 1, which 0173's own self-assert
proves is the pre-image's price to the digit. Mids are in ducats. The bid is after the port fee. On a fresh chain
the city purses are dark (bid factor 1). The local drift is not prod's, so prod's figures differ by a few per
cent.

### Kimchi from Mokpo

| port | sailing nm | haul | mid before | mid after | bid after | 100 sold at once, after (avg) |
|---|---|---|---|---|---|---|
| Mokpo (maker) | 0 | 1.00 | 91.90 | 92 | 87 | 8,102 (81) |
| Busan | 191 | 1.00 | 100.07 | 100 | 96 | 9,276 (93) |
| Nagasaki | 226 | 1.00 | 99.58 | 100 | 96 | 9,230 (92) |
| Macau | 1,067 | 1.04 | 111.75 | 116 | 111 | 10,647 (106) |
| Malacca | 2,508 | 1.21 | 122.42 | 148 | 142 | 13,477 (135) |
| Surabaya | 2,730 | 1.25 | 124.57 | 156 | 148 | 13,050 (131) |
| Hormuz | 5,763 | 2.75 | 126.47 | 347 | 332 | 29,659 (297) |
| Aden | 6,060 | 3.06 | 145.17 | 444 | 424 | 36,624 (366) |
| Zanzibar | 6,416 | 3.50 | 151.34 | 530 | 505 | 41,215 (412) |
| Acapulco | 6,926 | 4.30 | 157.31 | 677 | 646 | 50,324 (503) |
| Rio de Janeiro | 11,047 | 40.98 | 192.16 | 7,874 | 7,508 | 585,242 (5,852) |
| Cadiz | 12,947 | 164.07 | 144.48 | 23,704 | 22,763 | 1,943,461 (19,435) |
| Lisbon | 12,969 | 166.86 | 148.66 | 24,806 | 23,821 | 2,036,113 (20,361) |
| Genoa | 13,826 | 335.50 | 139.19 | 46,699 | 44,845 | 4,017,161 (40,172) |
| **London** | **14,006** | **390.98** | **138.95** | **54,327** | **52,170** | 4,683,409 (46,834) |
| Amsterdam | 14,095 | 421.75 | 138.98 | 58,615 | 56,288 | 5,083,106 (50,831) |
| Hamburg | 14,338 | 520.41 | 136.17 | 70,865 | 68,051 | 6,183,329 (61,833) |
| Bergen | 14,510 | 600.00 | 142.13 | 85,279 | 81,314 | 7,069,385 (70,694) |
| Boston | 14,608 | 600.00 | 147.90 | 88,741 | 84,529 | 6,589,091 (65,891) |
| Havana | 14,672 | 600.00 | 173.31 | 103,986 | 99,857 | 7,783,960 (77,840) |
| Alexandria | 14,780 | 600.00 | 139.54 | 83,724 | 80,400 | 7,283,659 (72,837) |
| Venice | 14,782 | 600.00 | 139.49 | 83,692 | 80,369 | 7,240,488 (72,405) |
| Veracruz | 15,586 | 600.00 | 161.89 | 97,136 | 93,280 | 7,271,214 (72,712) |

The owner's example: bought at Mokpo for ~92 + fee (ask ~96), sold in London at a 52,170 bid. That is **~540×**,
on the order the owner asked for.

The Mediterranean pays more than London. There is no Suez in 1550, so Alexandria and Venice lie round the Cape
and farther by sea.

### Five goods from other regions (mid before → after)

| port | nutmeg (Banda/Ambon/Jakarta) | tea (Fuzhou/Guangzhou/Ningbo) | tobacco (Americas) | coffee (Mocha/Alexandria/Suez) | wine (Atlantic islands) |
|---|---|---|---|---|---|
| Malacca | 1,134 → 1,145 (575 nm) | 597 → 644 (1,582) | 394 → 26,483 (11,762) | 811 → 1,211 (3,630) | 172 → 3,555 (9,981) |
| Nagasaki | 1,398 → 1,623 (2,214) | 504 → 506 (425) | 345 → 152,261 (14,147) | 686 → 2,230 (6,225) | 171 → 16,649 (12,269) |
| Hormuz | 1,600 → 2,407 (3,663) | 720 → 1,460 (4,819) | 413 → 16,322 (10,992) | 585 → 629 (1,556) | 132 → 1,707 (9,175) |
| Lisbon | 1,849 → 48,201 (10,353) | 976 → 90,660 (12,204) | 261 → 325 (2,677) | 649 → 741 (2,093) | 112 → 113 (505) |
| London | 1,811 → 92,124 (11,364) | 1,208 → 245,322 (13,216) | 303 → 408 (3,130) | 703 → 948 (3,132) | 132 → 141 (1,477) |
| Venice | 1,698 → 137,757 (12,020) | 1,059 → 369,215 (13,871) | 299 → 571 (4,615) | 649 → 676 (1,173) | 128 → 150 (2,310) |
| Havana | 1,954 → 159,427 (12,028) | 874 → 319,054 (13,926) | 249 → 256 (940) | 829 → 2,294 (5,784) | 153 → 199 (2,940) |
| Busan | 1,437 → 1,703 (2,364) | 505 → 509 (483) | 360 → 175,121 (14,260) | 788 → 2,625 (6,287) | 174 → 19,886 (12,483) |

The full per-port tables for all six goods are in the measurement output (23 ports each).

## Knock-on economics, measured

**Merchants (lap-start planning, `public.npc_plan`, the first 60 routes in roster order).** Each route was set at
her stop 0 with an empty hold and her purse as found. "Before" holds every haul at 1. Everything was rolled back.

| | plan failed | ballast at stop 0 | loops planned at a loss | planned loop profit, mean | mean loop |
|---|---|---|---|---|---|
| before (haul 1) | 0 | 13 | 0 | 24,123 d. | 3,706 nm |
| after (0173) | 0 | 11 | 0 | **575,401 d.** (× 24) | 4,878 nm |

- No plan fails, no loop is planned at a loss, and fewer merchants sail in ballast.
- Merchants chase longer loops (+32 % nm), as intended.
- They buy only at makers, where the haul is 1, so no merchant can be ruined by a dearer purchase.

**Cost (no regression).** A second run alternated the order (after, before, after, before; 40 routes).
- `npc_plan` mean: 255 / 217 ms after against 286 / 301 ms before. The first run's 200 → 323 was order and
  warm-up.
- `world.trade_routes` from 30 harbours: 1,279 → 856 ms (faster of 2).
- `world.mid_terms` × 2,000: 1,066 → 1,028 ms.
- The arrivals sweep prices only through these, and a quote does no new arithmetic (one more stored column read).

**The city purses: the measured flow against the money.** Prod now holds the purses at head 0172 (read-only,
2026-10-18): 238 purses, **660 M** d. in all, median 2.0 M; London **10.0 M** against a 242 k reserve.
- One 100-jar kimchi sale in London is ~4.7 M, so a capital can pay for about two before it reaches its reserve.
- Merchants' planned loop profit rises × 24 (above): from ~24 k to ~575 k a loop.
  - 861 merchant fleets × ~575 k is ~500 M a round of laps, paid out of 660 M of purses.
  - The money a city takes in is unchanged (BUYs at makers, charges).
  - So the purses will drain toward the bid floor (`city_bid_floor` 0.5, linear below the reserve). Then they
    refuse `E_CITY_BROKE` (0122's hard half: a sale shrinks to the 10-tun steps the purse covers). That is
    already 204 refusals in prod's last 6 hours, before this term.
- The reserve (3 × a city's SELL day) rises with the sale values by itself.
- **This is the one knock-on 0173 does not fix: whether cities can keep paying distance prices is the purse
  economy's (0172's) question.** The numbers are stated here so its incomes and grants can be sized for them.
  Deploying 0173 does not break anything that is not already broken today: a broke city already refuses, and a
  purse cannot go below zero.
- The merchants' planner prices a SELL with the bid factor, not with the refusal. So at a drained city a
  merchant's line is refused and the cargo stays aboard for her next stop, as today.

**Also moved, by design, and left as is:**
- `price_history` mids jump at the deploy. The market chart shows a step at that slot.
- `trade_contracts` premiums (0–20 % of the mid at posting) scale with the mid. Their escrow is still gated by the
  city's surplus (`bounty_reserve_mult`), so far cities post fewer contracts until purses grow.
- Ledger, cost basis and lap books are bigint ducats or numeric. The largest mid in the world after 0173 is about
  10 M (3,300 base × 1.76 × 3.5 band × 600). That fits `price_history.mid numeric(12,4)` and
  `trade_contracts numeric(12,2)` with room.

## Proof (in the file; production is lived in while it runs, so only OWN state is asserted)

- **(a)** All 132,090 market rows equal `world.haul_rows()` on both columns. The 1,348 offered rows sit at haul 1
  and 0 nm. 19,514 rows are above × 100. The haul is monotone in nm.
- **(b)** The one expression over every row: new = the 12-argument pre-image (a pg_temp copy) × haul, to the
  4-dp rounding; equal to the digit where haul = 1.
- **(c)** Old tree (pg_temp copies of `mid_price`, `quote_priced`, `price_path`) against new, **in one statement
  each**, so a trade elsewhere cannot come between them. Over 626 sample rows (every kimchi row, a quarter of
  Mokpo's and of the far harbour's, an md5 sample):
  - `mid_price`;
  - 3,756 quotes: buy and sell × 10 / 50 / 200 t. Units and end stock are unmoved, the average is × haul, and the
    quote is the same to the cent where haul = 1;
  - a limited buy at the makers fills the same;
  - 1,631 path steps of `price_path`: stock and drift unmoved, mid / lo / hi × haul.
- **0170's outlook does not fork.** On 427 rows its now equals `world.price` on mid, ask and bid, including the
  rows above × 100.
- **(d)** `world.market` at Mokpo and London, in a rolled-back sub-block because it winds the drift tick:
  range_lo / range_hi equal the old expression × haul; buy / sell / mid equal `world.price`.
- **(e)** Catalogue:
  - The callers of `mid_from_terms` are exactly the four re-cut, and each passes the haul at every call.
  - One 13-argument form is left.
  - The leaves are server-only, and no client write grant exists.
  - 6 bodies reverse to their pre-images. ACL, owner, volatility, definer and config are unchanged, including
    `mid_terms` and `mid_from_terms`, which were recreated; their ACL is revoked down to the owner, with
    service_role included, as on prod.
- **Timings: notices only.**

**Prod vs fresh chain:** prod's live bodies of the six functions cut here have the same
`md5(pg_get_functiondef)` as the fresh chain's at head 0172. Read-only, re-dumped at prod head 0172, 2026-10-18. So the hunks
apply on prod. The callers of `mid_from_terms` on prod are the same four.

## Measured locally

- Cached-prefix build (`npm run build`), receipt:
  - "prefix cache: restored 164/165 migration(s) … applying 1";
  - the world image: chain applied in 40.3 s (164 of 165 restored, 1 applied), certified, 132,090 market rows;
  - world-guard ok, including "132090 market rows' hauls = world.haul_rows() (a planted bend seen)";
  - `tsc -b` + vite build passed, 1 m 08 s.
- The `0173 self-assert ok` receipt printed. It applied in 28.0 s on the cached head-0172 world (PGlite):
  - the fill (UPDATE of 132,090 rows) took 5.4 s;
  - rankings from the two sample harbours took 181 → 94 ms.
- `npx tsc -b` and `npx eslint .` both clean.
- `tests/rpc.outlook.spec.ts` (touched: its band row-picker passes `m_haul` and scales the band by it): 4 of 4
  passed (`npx playwright test`, node-side, no browser page).
- `node scripts/db/proof.mjs` (all proofs, the preamble variant, from zero locally): running at the first push; result in the next commit.
- **Push time:** estimated at about 10–30 s on prod. It is one UPDATE of every market row (each row is locked
  until commit, so a trade waits that long) plus the comparisons. Deploy with the clock unwound.
- **CI wall-clock:** recorded after the run.

## Not done

- No merge, no `db push`, no production write.
- Only read-only catalogue and table reads were made on prod (`db query --linked`). No function was called on
  prod.
