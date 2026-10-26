# NEWS_AND_MARKERS — every chart kept, news markers you can press

**Status: DESIGN, build-ready (2026-10-26). No migration, no code.** Owner row 216. Prod head at writing:
**0226** (870 MB of 8 GB). Slices are numbered "next" at build time. Every **(D)** is decided by default —
the owner reverses.

**The owner (2026-10-26):** *"i want all the chart recods to be saved, and when an update or a happening is
made, it should make a point on the chart, and i will be able to press it to see what caused it (major event,
real time news-like feature)"*

## 0. The answer in six lines

1. **Kept forever, tiered:** fine → hourly → daily, the 0226 pattern, for every Stats table too. A fold
   **sums** a bucket's flows (today's compaction keeps the day's LAST slot and throws the other 95 slots'
   trades away).
2. **One news table**, `public.world_news`, append-only. One writer per kind, inside the transaction that
   causes it.
3. **A dot on the time axis** of every chart, for the news that chart is about. Press → a small card.
4. **A Stats "News" face**, newest first, live each second (piggybacks on `world.stats_now`).
5. **Two reads:** `world.news_marks` (one per chart, the visible window) and `world.news_feed`.
6. **Six slices**, N1 (stop losing figures) first.

---

## 1. Every chart kept forever

### 1.1 What every chart draws, and what is kept today (prod, measured 2026-10-26 ~02:10 UTC)

| Chart (file) | Series | Table | Rows / size now | Kept today |
|---|---|---|---|---|
| Good page + trays (`GoodChart.tsx`, `PriceRows.tsx` → `PriceChart`) | ask, bid, stock of (city, good) | `price_history` → `_hour` → `_day` (0226) | 75,742 / 24 MB · 19,265 / 4.4 MB · 0 (first day not folded yet) | fine 24 h · hourly 30 d · **daily forever** |
| Stats → Overview (`Overview.tsx`) | world total; players, merchants, cities, set aside (sparklines); sold; bought | `stats_world` | 293 / 0.97 MB (288 fine + 5 day rows) | fine 72 h, then **one row a day = that day's last slot** |
| Stats → Merchants (`Merchants.tsx`) | profit (24 h), fleets sailing | `stats_merchants` | 293 / 0.67 MB | same |
| Stats → City (`CityDetail.tsx`) | city purse (+ its goods' figures) | `stats_city`, `stats_city_good` | 70,126 / 24 MB · 333,864 / 108 MB | 72 h · 48 h, then last slot of the day |
| Stats → Markets (`Markets.tsx`) | (tables, no line chart) | `stats_good` | 163,105 / 37 MB | 72 h, then last slot of the day |
| Live band (`LiveNow.tsx`) | this second only | `stats_live` (+ deltas) | 1 row | not a history |

Rows per 15-min slot: world 1 · merchants 1 · city 239 · good 557 · city-good ≈ 1,611. Bytes a row: world
3.3 KB (jsonb `period`/`recent`) · merchants 2.3 KB · city 342 B · good 227 B · city-good 323 B.

**What is lost today:** (a) intra-day shape past 72 h (one point a day), and (b) worse, the **flows** of 95 of 96
slots a day — `sold`, `bought`, `units`, `trades`, `minted`, `removed`, `period`, `flows` are per-slot figures,
and the kept last slot carries 15 minutes of them. 10-20 → 10-23 is already compacted this way: those flows
cannot be restored.

### 1.2 The change (N1)

The 0214 retention `delete … where exists (a later slot the same UTC day)` becomes a **fold**, then a prune:

| Column type | Folded as |
|---|---|
| state (purse, holders, stock, mid, houses, sailing …) | the bucket's **last** value |
| flow (sold, bought, units, trades, minted, removed, moved, *_ducats) | **sum** |
| jsonb flow maps (`period`, `flows`) | key-wise sum |
| `top` / `bottom` / `recent` | the last row's |
| new column `n smallint default 1` | slots folded (the read shows "hour" / "day" points honestly) |

| Table | Fine (15 min) | Hourly | Daily |
|---|---|---|---|
| `stats_world`, `stats_merchants` | 72 h | **forever** (D: they are tiny) | — |
| `stats_good`, `stats_city` | 72 h | 30 d | forever |
| `stats_city_good` | 48 h | **7 d** (D: 30 d would be 375 MB) | forever |
| `price_history*` | 24 h (0226) | 30 d (0226) | forever (0226) — **unchanged** |

Buckets are the row's own UTC hour / day (`date_trunc` of `at`), never `now()`'s hour. The fold runs in
`tick_stats` (no new cron job), set-based, only on finished buckets older than the fine window.

### 1.3 Size

| Table | Steady (hourly window) | Growth a year |
|---|---|---|
| `stats_world` + `stats_merchants` (hourly forever) | — | 24 × 365 × 5.6 KB = **49 MB** |
| `stats_good` | 557 × 720 × 227 B = 91 MB | 557 × 365 × 227 B = **46 MB** |
| `stats_city` | 246 × 720 × 342 B = 61 MB | **31 MB** |
| `stats_city_good` | 1,611 × 168 × 323 B = 87 MB | **190 MB** (as today) |
| price tiers (0226 dev-log) | 211–518 MB | **101–248 MB** |
| `world_news` (§2; ~1,000 rows/day × ~350 B with indexes) | — | **≈ 130 MB** |
| **Total** | **≈ 0.55–0.85 GB** | **≈ 0.55–0.7 GB / year** |

870 MB today + about 0.6 GB a year → the 8 GB plan holds **~10 years**. The day rows stay forever; nothing
here needs a bigger plan.

---

## 2. News rows

### 2.1 The table

```
public.world_news (
  id          bigint generated always as identity primary key,
  at          timestamptz not null default clock_timestamp(),
  kind        text not null references public.news_words(kind),
  importance  smallint not null check (importance between 1 and 3),   -- 3 headline, 2 notable, 1 local
  scope       text not null check (scope in ('world','power','port','good','company')),  -- widest place it shows
  port_id     uuid null, good_id uuid null, company_id uuid null, power text null,      -- the refs
  key         text null unique,     -- idempotence ('update:0231', 'spike:<port>:<good>:<hour>')
  detail      jsonb not null        -- the template's words + before / after
)
indexes: (scope, at desc) · (port_id, at desc) where port_id is not null · (good_id, at desc) where good_id is not null
```

- **Append-only** (the 0004 `forbid_mutation` trigger). RLS read-all; no client grant; written only by
  `public.news_post(kind, importance, scope, refs…, key, detail)` (security definer, revoked from clients).
- **Headlines are not stored** — `public.news_words(kind, en, ko)` holds the one template per kind (the
  `stats_flow_words` idiom); the read fills it from `detail`. One spelling per kind, both languages.
- `company_id` = `players.id`. Company names in news are public (they are on the map today) **(D)**.

### 2.2 The kinds

| Kind | Writer (ONE, in the causing transaction) | Threshold (anti-spam) | Imp. / scope | EN | KO |
|---|---|---|---|---|---|
| `UPDATE` | the migration's last statement, `select public.news_update('<title en>', '<title ko>', …)`; and `economy_close_switch` (E7) | owner-visible migrations only; a lint in CI: every new migration has ONE `news_update(` or a `-- news: none` line **(D)** | 3 / world | Update: {title} | 업데이트: {title} |
| `NEW_HARBOUR` | AFTER INSERT trigger on `ports` where `kind = 'HARBOUR'` | every one | 3 / world (+port) | New harbour: {city} | 새 항구: {city} |
| `RELATIONS` | AFTER INSERT/UPDATE/DELETE trigger on `power_relations` (0196; 13 rows, static today) | every change | 3 / world | {a} and {b}: now {stance} | {a}–{b}: {stance} |
| `WANTS` | the daily wants draw (E6b) | one row per city per draw (imp. 1) + one world row "New city wants" (imp. 2) | 1 / port · 2 / world | {city} wants {goods} | {city} 수요: {goods} |
| `CAPITAL_GIFT` | the gift pass in `npc_tend_houses` (E4) | every gift (< 50 / day, CLOSED_ECONOMY §5.2) | 2 / company (+port = capital) | {capital} gave {company} {n} | {capital}, {company}에 {n} 지원 |
| `MERCHANT_BROKE` | the same pass, on the **crossing** (worth < 20 % of capital, was not last hour) | once per company per 7 d | 2 / company | {company} is broke | {company} 파산 |
| `BIG_SALE` | `cmd.do_sell` | total ≥ `news_big_trade` **250,000** (prod sample: p99.9 of a sale = 319 k, p99 = 171 k → ≈ 30 / day) | 2 / port+good+company | {company} sold {qty} {good} at {city}: {n} | {company}, {city}에 {good} {qty} 판매: {n} |
| `BIG_BUY` | `cmd.do_buy` | the same knob (p99.9 of a buy = 281 k) | 2 / port+good+company | {company} bought {qty} {good} at {city}: {n} | {company}, {city}에서 {good} {qty} 구매: {n} |
| `PRICE_SPIKE` | `tick_price_snapshot`'s hour fold (where the hour row is written: close vs the previous close) | \|Δ\| ≥ `news_spike_pct` **20 %** (prod: 20 of 17,876 pair-hours ≥ 20 % → ≈ 37 / day); the 5 largest an hour; one per pair per 6 h | 2 / port+good | {good} at {city} {±p} in an hour | {city} {good} 1시간 {±p} |
| `RESTOCK` | `tick_city`'s roll when `restock_rate(port)`'s band (slow / normal / fast) changes (E5) | once per city per day | 1 / port | {city} restocks {faster/slower} | {city} 보충 {빨라짐/느려짐} |
| `PIRATES` | `voyage.settle` at a `PLUNDERED` / `RANSOM` outcome | a player's ship always; a merchant's when loss ≥ 50,000 (prod: ≈ 33 plundered / day in all) | 2 / company | Pirates took {n} from {company} | 해적이 {company}에서 {n} 약탈 |

- `detail` always carries `before` / `after` where a figure moved (price, purse, stance, rate band) and
  the template's words (`city`, `good`, `company` as served names; the client localises with `properName`).
- **No "depth reset" kind (D):** a stock / depth reset is done by a migration, so it is an `UPDATE`.
- **War:** there is no war state in the game; `RELATIONS` covers "rival". If war is built, its writer adds a kind.
- Volume: ≈ 3 + 246 + 1 + < 50 + few + 60 + 37 + few + ~10 ≈ **≈ 450–1,000 rows / day**.

---

## 3. Markers

### 3.1 Which chart shows which news

| Chart | Shows | Min imp. |
|---|---|---|
| Price chart (city P, good G) | `port_id = P and (good_id = G or good_id is null)` ∪ `scope = 'world'` | 1 for P's own; 3 for world |
| City purse (Stats → City P) | `port_id = P` (any good) ∪ world | 2 for goods; 3 for world |
| Stats → Overview (world money, sold, bought) | `scope = 'world'` | 3 |
| Stats → Merchants | world ∪ kinds `CAPITAL_GIFT`, `MERCHANT_BROKE`, `PIRATES` | 2 |
| Sparklines (Overview holders, Markets) | none — too small to press **(D)** | — |

### 3.2 Drawing and pressing

| | Rule |
|---|---|
| Dot | r = 3 px on the plot's time axis (the floor line) at the news instant; `accent` for imp. 3, `ink-muted` for 1–2. Hit target 24 px. Pure geometry in a new `newsMarksModel.ts` (both charts call it; the two chart models stay separate, NO_SPAGHETTI §5) |
| Cluster | dots closer than 12 px merge into one dot with a count ("3"); the dot takes the highest importance in it |
| Press a dot | a `Popover` card: **headline** (EN/KO) · **"5 min ago"** (`agoLabel`-style, plus the UTC time small) · **before → after** when `detail` has them (e.g. "Pepper 412 → 506") · **link** to the city (city view) or the company (merchant sheet) |
| Press a cluster | the same card listing up to 5 items, newest first; "+N more" opens the News face filtered to that window |
| Panning / spans | marks are re-read with the chart's window (`useChartSpan`'s span, `chartPan` window); on the daily tier a mark still stands at its own instant |

---

## 4. News feed

| | Decided **(D)** |
|---|---|
| Where | a 6th Stats face **"News" / "소식"** (after Overview) + a one-line strip on the desk showing the newest **imp. 3** item for 10 min (press → the card). Imp. 1–2 never reach the desk (clean desk) |
| Order | newest first; 50 a page; "Older" asks the next 50 (`p_before` id) |
| Live | `world.stats_now()` gains `news_head` (= `max(id)`, one index probe). The 1-second live read (0224; row 213 makes all Stats live) already runs; when `news_head` moves, the face asks `news_feed(p_after = last id)` and prepends. No second poll |
| Filters | **World** (imp. ≥ 2) · **My cities** (ports where you hold `city_shares`, or a fleet is docked / heading) · **My goods** (goods aboard your fleets or in your warehouses). Computed in the read from `auth.uid()` |
| Row | headline · ago · a small kind chip; press → the same card as a marker |

---

## 5. Reads

| Read | Args | Returns | Index |
|---|---|---|---|
| `world.news_marks(p_chart text, p_port uuid, p_good uuid, p_from timestamptz, p_to timestamptz)` | `p_chart` ∈ price / city / world / merchants | ≤ 300 rows: id, at, kind, importance, headline en/ko, detail, refs | `(port_id, at)` ∪ `(scope, at)`, union of two index range scans |
| `world.news_feed(p_filter text, p_after bigint, p_before bigint, p_limit int)` | filter ∈ world / cities / goods | ≤ 50 rows, same shape | PK desc; filter by `port_id = any(…)` / `good_id = any(…)` |

Both `stable`, security definer, in `client_rpc_entry_points()`.

**Plan cost, measured on the nearest prod-sized analogue** (the table does not exist yet): `public.events`
(216,531 rows ≈ 7 months of news at 1,000 / day), index `(player_id, created_at desc)`, one key's 7-day window,
200 rows: **35.8 ms execution, cold heap**, 2.3 ms planning. A chart's window holds 5–50 marks, not 200, and
`world_news` rows are ~4× narrower → expected **< 5 ms** per chart. N3's self-assert times 6 reads on probe rows;
the after-deploy check re-times one on prod.

---

## 6. Slices — one migration each ("next"), smallest risk first, client in the same PR

Common self-assert rules (every slice): count **only probe rows** (probe ids / `id >` a mark taken in-block);
**never count or sum a growing table**; **never DELETE from append-only tables** (`world_news`, `events`,
`ledger`, …) — probes run in a sub-transaction rolled back, and asserted gone; **no hour-of-day dependence**
(probe rows planted at fixed instants; buckets from the row's `at`); every replaced body is the LIVE body
(`pg_get_functiondef`, LF-normalised), each hunk occurs exactly once and reverses; ACL / volatility / definer
unchanged; files saved LF.

| # | Name | Does | Self-asserts | Client + tests |
|---|---|---|---|---|
| **N1** | `every_figure_is_kept` | §1.2: `n` column on the five stats tables; `tick_stats`'s retention hunks → fold (last / sum / key-sum) then prune per tier; knobs `stats_hour_days` 30, `stats_city_good_hour_days` 7; the `world.stats_*` reads take a span like `price_series` | planted probe slots across 2 hours and 2 days on a probe port: fold sums flows exactly, keeps the last state, `n` right, fine rows of the window untouched, a daily row never deleted | Stats charts get the shared `SpanPicker` (1d · 1w · 1m · 1y · All); spec: series from folded rows |
| **N2** | `the_world_keeps_its_news` | `world_news`, `news_words`, `news_post`, `news_update`; triggers `NEW_HARBOUR`, `RELATIONS`; `world.news_feed`; `stats_now` + `news_head`; one `UPDATE` row for itself; CI lint for `news_update(` / `-- news: none` | probe insert → one row, template fills EN + KO; UPDATE/DELETE refused; a probe harbour insert writes one row; a probe stance change writes one; `key` makes a second post a no-op | Stats → **News** face + filters + desk strip; specs: feed order, live prepend on `news_head` |
| **N3** | `a_chart_shows_its_news` | `world.news_marks` | probe rows on a probe port: the price chart's set = own + world, imp. filter right, window bounds inclusive; 6 timed reads printed | `newsMarksModel.ts` (dots, cluster at 12 px), `PriceChart` + `SeriesChart` draw it, the card; specs: cluster, press, ago |
| **N4** | `a_big_trade_is_news` | hunks: `cmd.do_sell` → `BIG_SALE`, `cmd.do_buy` → `BIG_BUY`, `tick_price_snapshot`'s hour fold → `PRICE_SPIKE`; knobs `news_big_trade`, `news_spike_pct` | a probe sale under the knob writes 0 rows, over it 1 (same transaction: a refused sale writes 0); probe hour rows +25 % → one spike, +10 % → none, the 6-h cooldown holds | words EN/KO; card shows before → after |
| **N5** | `pirates_are_news` | hunk in `voyage.settle` at PLUNDERED / RANSOM | probe player voyage plundered → 1 row; probe merchant under 50 k → 0 | words |
| **N6** | (no file of its own) | `CAPITAL_GIFT`, `MERCHANT_BROKE` ride in E4; `WANTS` in E6b; `RESTOCK` in E5 (CLOSED_ECONOMY §8) — **each E-slice built after N2 calls `news_post` itself**. Any E-slice already shipped before N2 gets its hunk in one catch-up file | each E-slice's own probe asserts one news row per probe event, none dark | words |

Order **(D)**: N1 first — figures are being lost every day. N1 touches `tick_stats` / the stats reads, which
row 213 (`osn-stats-all-live`) also re-cuts: **build N1 after 213 lands**, against the live body.

---

## 7. Risks

| Risk | Answer |
|---|---|
| Hot path: `do_sell` / `do_buy` run ~60 k / day | one comparison; the insert happens ≈ 30 times a day. N4 times a probe trade before / after |
| Feed spam (wants = 246 / day; closed economy makes prices swing more) | importance + per-kind cooldowns + knobs; World filter hides imp. 1; the spike knob is retuned after the switch (CLOSED_ECONOMY §7 expects p90 3–12 % per 10 min) |
| A migration forgets its `UPDATE` row | the CI lint (N2); `key` = 'update:<number>' keeps a re-run idempotent |
| From-scratch CI replays every migration's `news_update` | idempotent by `key`; only probe rows are asserted |
| `tick_stats` already takes 12–18 s on prod (row 213) | the fold is set-based over finished buckets only — at most one hour's slots per run; N1 prints its own timing |
| Lost history 10-20 → 10-23 (stats flows) | cannot be rebuilt; stated in N1's header. The price day tier started with 0226 |
| Disk | ≈ 0.6 GB / year (§1.3); 8 GB lasts ~10 years; the knobs halve the hourly windows if ever needed |
| Names of player companies in news | public by default (D); a flag can hide players and keep merchants |
| Collision with E-slices on the same functions | N6: whichever lands second carries the news hunk; never both |
