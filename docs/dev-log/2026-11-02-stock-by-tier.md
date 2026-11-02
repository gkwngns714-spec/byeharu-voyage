# 0303 — the higher the good, the fewer on the quay (owner order, 2026-11-02)

Owner: "higher tier items should have less quantity for purchase. Also designate rare raw materials such as gold, diamond, and make the quantities less."

## What went live (prod head 0303, PR #470)
- `goods.is_rare` column; 24 raw goods designated rare: gold, gold-dust, andacollo-gold, platinum, silver, potosi-silver, zacatecas-silver, diamonds, golconda-diamonds, rubies, burma-rubies, emeralds, emerald-muzo, ceylon-sapphires, opals, peridot, lapis-lazuli, jade, nephrite, malachite, onyx, pearls, seed-pearls, baja-pearls. Left out: quicksilver, amber, spices.
- Knobs: `stock_tier_scale` [1, 0.6, 0.35, 0.15] (production tier 0..3), `stock_rare_scale` 0.15 (a rare good takes the smaller of the two), `stock_floor_units` 5. One reader: `public.good_stock_scale(uuid)`.
- One-time re-cut of `port_goods`: stock_target, base_target, production_rate and stock moved by ONE ratio per row, so stock/max (the price input) does not move.

## Prod measurements (read-only SELECTs)
| | before | after |
|---|---|---|
| sum stock_target | 202,763,250 | 146,013,850 |
| sum stock | 256,354,401 | 184,297,399 |
| mean max stock, tier 0 plain raw | 1,228.5 | 1,228.5 |
| mean max stock, tier 3 | 1,428.4 | 214.3 |
| mean max stock, rare goods | 1,319.0 | 197.8 |
| port_goods rows | 154,734 | 154,734 |

## What the first prod deploy taught
The first push was REFUSED by 0303's own self-assert and rolled back (prod head stayed 0302, 12 cron jobs active): 55,358 rows would have changed their stock/max ratio. Cities hold a surplus (stock over max); the first draft clamped stock to the new, lower max, which would have raised those prices. The local PGlite world has no surplus, so only prod could show it. Fix: stock moves by exactly the max's ratio, no clamp. LESSON: a re-cut of live market rows must be proved against prod's real distribution (read-only SELECT of the projected result) before the push.

## After-check (30 minutes)
To be filled: cron failures since the deploy, voyage lag, market job time, a price spot-check on 10 cut goods.
