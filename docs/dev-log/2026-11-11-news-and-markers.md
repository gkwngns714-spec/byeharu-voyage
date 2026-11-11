# 2026-11-11 — 0347: the world keeps its news, and a chart shows its news (owner row 216)

Owner, 2026-10-26: *"i want all the chart recods to be saved, and when an update or a happening is made, it should make a
point on the chart, and i will be able to press it to see what caused it (major event, real time news-like feature)"*.

Design: `docs/NEWS_AND_MARKERS.md`. N1 (records kept) was already live (0226, 0246, 0316). This slice is **N2 + N3** in one
migration, 0347. N4-N6 (big trades, price spikes, pirates, the E-slices' kinds) are not built.

## What shipped

- `public.news_kinds` — the kinds are rows: importance, scope, one headline template per language. Seeded `UPDATE`,
  `NEW_HARBOUR`, `RELATIONS`. A new kind is a row plus a `news_post` call in the transaction that causes it.
- `public.world_news` — append-only (its own refusal trigger: 0004's `forbid_mutation` reads `old.player_id`, which a news row
  has not, and PL/pgSQL fails on that field before its `tg_op` test — found on the first local apply).
- `public.news_post` — the one writer. `public.news_update(number, en, ko)` — a migration's own row, idempotent by key.
- Writers: AFTER INSERT on `ports` (a new HARBOUR) and AFTER INSERT/UPDATE/DELETE on `power_relations` (a stance change).
- Reads: `world.news_feed` (World 2+ / My cities, paged by id, `head`) and `world.news_marks` (price / city / world / merchants,
  a union of index range scans, bounds inclusive, a null bound open).
- Hunks: `world.stats_now` + `news_head`; `client_rpc_entry_points` + the two reads (anchored on the `stats_now` row).
- This file posts its own row: "Update: News" / "업데이트: 소식".
- CI law (`tests/news.lint.spec.ts`): every migration from 0347 on has one `public.news_update(` call or a `-- news: none` line.

## Lit, no switch — why

Both writers hang on tables nothing in the live game writes. Read on prod 2026-11-11 (`scripts/ops/harness/news/writers-quiet.sql`):
no function body inserts into `ports` or writes `power_relations`, and neither table carries a trigger. So no tick, trade or voyage
fires a writer: live play and tick cost do not move. The reads, the News face and the dots ship lit; the dots are empty until news
exists (on prod: 0347's own UPDATE row is the first).

## Client

- `src/components/ui/newsMarksModel.ts` (pure: a dot on the floor at its instant, none outside the axis, marks under 12 px apart
  are one dot, newest first, highest importance) and `NewsDots.tsx` (a layer of 24-px buttons over the chart's svg, out of the flow).
- Both chart models now expose `axis` (the stretch of time their width spans); `PriceChart` and `SeriesChart` take `news`.
- `src/live/useChartNews.tsx` (the read per chart, asked again every 30 s), `NewsCard.tsx` (the card: a Tray), `newsWords.ts`
  (the template filled in the reader's language; proper names through `properName`).
- Dots on: Stats Overview (world money, sold, bought), Stats Merchants (their money, earned), Stats City (purse), the desk's
  Buy / Sell good chart, the City page's market chart. Not yet: `PriceRows` (the map's good panel and the quay trays).
- Stats gets a sixth face, **News / 소식**, after Overview: World / My cities, 50 a page, Older, live on `news_head`.

## Measured

- Local apply of 0347 on the cached chain: 0.5 s; the six timed reads in its receipt: price 23 ms (first, cold), city 7,
  world 1, merchants 4, feed world 5, feed cities 5 ms.
- Proof 54: 4/4.

## Decided by default

- The kinds table is `news_kinds` (the design's `news_words`), because it carries importance and scope too.
- The "My goods" filter waits for the first kind that names a good (N4).
- The card has no link to the city or company yet; a feed row is not pressable (it already says everything the card says).
- Marks are re-read every 30 s, not every second; the News face is the live list.
