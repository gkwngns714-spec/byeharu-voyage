# 2026-11-23 — 0479 goods mastery: a ladder per good (dark: `goods_mastery_enabled`)

Roadmap slice 11 (`docs/design/roadmap-2026-11-23.md`; the roadmap numbered it 0480, the logbook took 0478). Melvor's mastery per item.

## What it does (lit)
- **One table**, `public.goods_mastery` (player, good; its primary key the guard): her units sold of the good and the level they make.
  At most 629 rows a company. Merchants keep none.
- **The ladder** (`goods_mastery_units`): levels 1..10 at 1, 100, 250, 500, 1,000, 2,000, 3,500, 6,000, 10,000, 16,000 units sold.
  Level 1 is her first sale; a hold is ~100-300 units, so 2-4 come in a few loads and 10 in about a hundred.
- **Each level** (the level she holds before the sale):
  - **price** x (1 + level x `goods_mastery_price_step` 0.005): +5 % at 10, through THE ONE place a sale is priced, the bid factor of
    `world.quote_terms` (one hunk → `public.goods_mastery_bid`). `world.quote`, `cmd.do_sell`, the Trade desk's cards (`world.best_sales` →
    `world.board_sell` → `world.quote`, a per-row factor), the goods board and the dry runs all agree. Held under the quay's own ask
    ((1 + s/2) / (1 - s/2) for her spread s), so a buy and the sale of the same units at one quay never pays. It binds below a 4.9 %
    spread: Setubal's andalusian horses (4.2 %) give +4.3 % at 10.
  - **allowance** x (1 + level x `goods_mastery_cap_step` 0.05): +50 % at 10, through THE ONE reading of the day's allowance,
    `world.daily_cap_remaining` (one hunk → `public.goods_mastery_cap`). The allowance is one figure for buying and selling a good at a
    harbour (`trade_daily`), so both grow.
- **Written at the one sale point**, `cmd.do_sell`'s SOLD payload (one hunk → `public.goods_mastery_sale`): a quay sale and a standing
  route's lap (`cmd.run_manifest` calls `cmd.do_sell`); `voyage.settle` sells nothing itself. The event gains `mastery` {good, level, from,
  units, at, next, up}.
- **The read** `world.goods_mastery()` (registered): her goods by level, her specialty, the ladder, the steps.

## The money law
The economy is closed and the purses are lit: the city's purse pays a sale's WHOLE total (0233: `public.city_pays`, a treasury row
-total and her credit +total). The better price is inside that total, so the purse pays it; a purse short of the dearer lot shrinks it
or refuses as before. Proof 182 `GM_MONEY`: W (purses + houses + coin aboard) unchanged to the ducat across a level-10 sale, the SELL
flow equal to the SOLD total.

## Client
- The logbook's Goods page: every good she has sold wears its level as a ring round its mark (gold at the top).
- You's plate: her specialty (her highest good) under the company's name, as its mark in its ring and its name.
- Gold names at level 10: the Trade desk's cards (`TradeCard`), the From here tiles (the good's mark), the arrival card's sale line.
- A level-up: a chip under the arrival card's sale line; a toast for a quay sale (`src/live/MasteryUp.tsx`).
- One recipe: `components/ui/Mastery.tsx` (`MasteryRing`) and `masteryStyles.ts` (`masteredTone`).

## Back-fill (once, in the migration, dark)
Companies only: the units of her SOLD events by good. Prod's read 2026-11-23: 33 SOLD events of 19 companies → 19 rows for 6 companies,
levels 1 x12, 2 x6, 3 x1 (most 440 units). Dark both factors are 1, so it moves nothing a player sees.

## Measured (local PGlite)
- Self-assert: 4 hunks once and reversing; probe dark/lit; ~160 ms.
- Proof 182: 9/9. Both factors lit 0.024 ms, for a merchant 0.018 ms, dark 0.010 ms; a quote's terms 0.25 ms (the factor ~2-4 % of it).

## Decided by default (the owner may reverse)
- Units sold (not value): every good climbs by the loads she sells; bulk spans 0.2-1.5 t, value 70-1,800, so value would favour dear goods.
- The price bonus is held under the quay's ask (no round-trip loop at a shaved spread); at most quays +5 % stands.
- The allowance multiplies the whole day's allowance of the good (buying too, and a pirate home's ceiling).
- Merchants get no rows and no bonus. Rank rows do not show a specialty (it would hunk the board's read; not cheap).
- The mastery view lives on the logbook's Goods page (lit with the logbook, as prod runs it).
