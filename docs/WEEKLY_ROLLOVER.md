# Weekly rollover: city investment and lap records start fresh each week, and keep their past

Owner row 173 (2026-10-20): *"The investment in city, Lap records should be reset every week. There will be
a history tab where you can see the last week's investment records when pressing a city."*

Design only. No code, no migration in this PR. Every rule that is mine and not the owner's is marked
**decided by default**; the owner may reverse any of them.

**The one idea.** A "reset" here is not a delete and not a job that zeroes rows. **The week is a KEY.**
Every figure the owner wants reset is written under the week it happened in, the live faces read the
current week's key, and the history tab reads the earlier keys of the same table. Nothing is ever deleted,
`events` and the ledger are untouched, and there is no moment at which a row is rewritten.

---

## 1. The current model (read off the chain, 2026-10-25, prod head 0216)

### City investment: two books, one door
- **The share register** `public.city_shares` (`supabase/migrations/20260818000123_a_city_builds_with_other_peoples_money.sql:122-131`):
  one row per (port, work kind, house) with `shares`, `paid`, `accrued` coupons. It is **money**: a share
  earns `works_coupon_pct` of what was paid per game-day (0123:83-84). The works themselves are
  `public.city_works` (0123:108-118): `level` built, `subscribed` shares of the next level.
- **The influence book** `public.port_influence` (`…000144_a_city_counts_who_gives.sql:116-129`): coin given
  (Invest or Donate), weighted and decayed 10 %/day (`influence_decay`, 0146), by the country the house sailed
  for at the moment of giving. It decides who holds the city (`public.port_allegiance`, 0143:139-146) and the
  investor-rank price shave (`public.investor_rank`, `…000191_…:85-99`).
- **The one door coin enters a city:** `public.pay_city` (0122:344), re-cut in 0144:367-375 so that
  `SHARE` and `DONATION` also call `public.influence_post`, the one posting authority (0144:173-192).
  Writers upstream of it: `public.invest_for` (0123:200, players via `cmd.invest` 0123:324 and merchants via
  `npc_invest` 0123:668) and `public.donate_for` (0144:215, `cmd.donate` 0144:270).
- **Readers:** `world.town_hall` (0123:776-848) serves `investors` = **the all-time** `city_shares` rows by
  `paid desc`, capped by `town_hall_investors_max` (50), plus the viewer's own `holdings`;
  `world.town_hall_influence` (0144:331-366) serves each country's share and the viewer's points.
- **Faces:** the city's Town Hall tab, `src/live/CityTownHall.tsx:129-144` ("Investors", `town.investors`),
  holdings at `:113`, influence at `:76-78` (`src/live/TownHallInfluence.tsx`). The tabs are the registry
  `src/features/map/cityTab.ts:13-18` (market, port, inn, townhall, info) drawn by
  `src/features/map/CityTabs.tsx:68-74`. Words: `src/lib/i18n/dict/town.ts:22` / `:116` (투자자).

### Lap records: one closer, one earnings reading
- **The table** `public.standing_route_laps` (`…000092_a_route_is_a_standing_order_that_sails.sql:196-214`): one row
  per lap of a standing route with `sold, bought, supplies, repairs, wages, net`, summed from the executors'
  own results. **Already bounded:** `cmd.standing_route_close_lap` (0092:516-575, hunks re-cut in 0128, 0129,
  0213) deletes laps past `standing_route_lap_keep` (200 since 0097:101-102). So today a lap record is
  forgotten by count, not by week.
- **The reading** `public.route_earnings` (`…000097_…:191`): `day` = Σ net of laps closed in the last 24 real
  hours, `lap` = mean of the last seven closed laps from the second onwards, `laps_done`, `laps_recent`
  (`src/lib/rpc/types.ts:2230-2250`). `world.standing_routes` (0092:788) serves the last ten laps per route
  (`types.ts:1972-1973`); `world.fleet_trades` (0121:211) serves a lap's trades.
- **Faces:** `src/features/command/RouteFold.tsx:89,184-190` (last three laps),
  `src/features/map/VoyageTray.tsx:160-196,346` (seven lap pills), `src/features/routes/RoutesScreen.tsx:41`
  (how far a lap sails, what a lap earns), the History tab line `ROUTE_LAP` (`src/features/ledger/headline.ts:210-224`).

### What already keeps time
- `world.game_day` (0005:294-300): `floor(epoch / game_day_seconds)`, 2880 s, so **a real week is 210 game days**.
- 0214's stats keep fine rows for 72 h and **one row per UTC day forever** (0214:64-65, 122-124).
  Every clock in the chain is UTC; nothing anywhere knows a "week". `week` appears only in 0097's merchant
  refound cap, which 0115 deleted.

---

## 2. The rollover

### The boundary — decided by default: Monday 00:00 UTC
`week_anchor` = `2026-10-26T00:00:00Z` (a Monday), a `world_config` knob read by one function (§3).
Why UTC Monday: every other clock in the chain is UTC (game days, 0214's day rows, the crons), so a week
edge that coincides with a stats day edge lets a week's totals be reconciled against 0214's day rows.
For the Korean players it is Monday 09:00 KST. If the owner wants midnight KST, the knob becomes
`2026-10-25T15:00:00Z` and nothing else changes.

### What resets (is read by the current week's key) and what does not

| thing | resets weekly? | why |
|---|---|---|
| **Town Hall "Investors" board** (who gave what to this city) | **YES** — shows this week's giving | the owner's words |
| **Lap counters** on a route: laps done, Σ net, sold/bought/… | **YES** — this week's laps | the owner's words ("lap records") |
| `city_shares` (shares held, paid, coupons owed) | NO | it is the player's money and the deed to what she bought; a weekly wipe would confiscate it |
| `city_works` levels | NO | buildings do not fall down on Monday |
| `port_influence` and who holds a city (`port_allegiance`) | NO | the owner approved INFLUENCE.md with its own daily decay (D6); a weekly zero would replace that approved rule. **Flag: if the owner meant the influence race itself, that is a change to INFLUENCE.md, not to this design** |
| investor-rank price shave (0191) | NO | it reads `port_influence`, above |
| `route_earnings.lap` (mean of the last seven laps) | NO | it is a measure of what a lap earns, not a record; a Monday-morning route would print null for hours |
| `events`, the ledger, `treasury_daybook`, 0214 stats | NO | append-only; untouched |

**Nothing is deleted and no row is rewritten at the boundary.** The weekly books (§3) are append-only
tables keyed by week; a "reset" is only that the live faces ask for `world.week_of(now())`.

### Deploy week — decided by default: no backfill
The weekly books start empty when the migration lands, so the first week's board shows only what was
given after the deploy. A backfill from `events` is not honest: the merchants' events are compacted
(0097:889), so the board would show players and not merchants. The face says so for that one week
("since 26 Oct" in place of "this week") only if the owner asks; by default it simply starts.

---

## 3. One authority for "the current week"

**`world.week_of(p_at timestamptz default now()) returns bigint`** =
`floor((epoch(p_at) − epoch(week_anchor)) / 604800)`, and
**`world.week_start(p_week bigint) returns timestamptz`** = `week_anchor + p_week weeks`. Both `stable`,
`security definer`, server-side; they live next to `world.game_day` (0005) because they are the same kind of
thing: the one clock reading. Every week number anywhere is one of these two calls. **The client never
computes a week**: it is served `week`, `starts` and `ends` and prints them. Guard: `tests/duplication.spec.ts`
gains one rule, no `604800`, `getDay(` or `startOfWeek` in `src/` or in any later migration body.

Two append-only books, each with ONE writer, both inside the writers that already exist:

- **`public.city_week_book`** `(port_id, week bigint, player_id, kind text in ('SHARE','DONATION'),
  ducats bigint, gifts int, updated_at)`, PK `(port_id, week, player_id, kind)`, index `(port_id, week)`.
  Written by **`public.city_week_post(p_player, p_port, p_kind, p_amount)`** alone, called from the same
  `pay_city` branch 0144 added for `influence_post` (one sliced hunk, exactly once, reverses). An upsert adds
  `ducats` and `gifts += 1`. RLS on, revoked from clients, read through `world.*` only. Never deleted.
- **`public.route_week_laps`** `(route_id uuid, week bigint, player_id, route_name, laps int, sold, bought,
  supplies, repairs, wages, net bigint, updated_at)`, PK `(route_id, week)`, index `(player_id, week)`.
  Written by **`cmd.standing_route_close_lap`** alone (one hunk after the lap row is closed, 0092:550-554),
  stamped `world.week_of(p_now)`. `route_id` is a plain uuid with no FK: a deleted route keeps its history
  (today `standing_route_laps` cascades away with the route). `player_id` cascades with the house.

Readers (callers, not authors): `world.town_hall` (`investors` re-cut to this week's `city_week_book`),
`world.city_history` (new, §4), `public.route_earnings` (adds `week` and `last_week`, §5 W2).

---

## 4. The history tab

Pressing a city opens its tabs (`cityTab.ts:13-18`); a sixth tab **History** is added after Info.
It is one new face, `src/live/CityHistory.tsx`, reading one new door, `world.city_history(p_port, p_weeks)`.

**Served:** `{port, week, weeks: [{week, starts, ends, current, total, investors: [{name, merchant,
invested, donated, total}] }]}` — the current week first, then the past **8 weeks (decided by default)**,
newest first; the table keeps every week, the door serves eight. Investors are ordered `total desc, name`,
capped by the existing `town_hall_investors_max` (50). Names are public already (Town Hall shows them).
Gated like the Town Hall (authenticated); no tier gate, because the Town Hall's investor board is not gated today.

**Shown:** one fold per week, the current week open, the others closed, each with its dates and total; a
week with no giving reads one muted line. A player's own row is marked ("you").

| key | English | 한국어 |
|---|---|---|
| `map.History` (tab) | History | 내역 |
| `town.thisWeek` | This week | 이번 주 |
| `town.lastWeek` | Last week | 지난 주 |
| `town.weekOf` | Week of {date} | {date} 주 |
| `town.weekTotal` | {amount} given | {amount} 투자 |
| `town.weekNobody` | Nobody invested this week. | 이번 주에 투자한 사람이 없습니다. |
| `town.weekNobodyPast` | Nobody invested that week. | 그 주에는 투자한 사람이 없습니다. |
| `town.invested` / `town.donated` | invested / donated | 투자 / 기부 |
| `town.investorsWeek` (Town Hall heading) | Investors this week | 이번 주 투자자 |
| `routes.weekLaps` | {n} laps this week · {net} | 이번 주 {n}바퀴 · {net} |
| `routes.lastWeekLaps` | Last week: {n} laps · {net} | 지난 주: {n}바퀴 · {net} |

KO "기록" is already the shell's History tab (`shell.ts:42`); the city tab uses **내역** so the two are not
confused in one screen. "Lap" keeps `docs/WORDS.md`'s word; 바퀴 is its KO counter.

---

## 5. Build slices, with their proofs

Each migration slice is ONE migration, deployed with `~/bin/bv-deploy.sh`, self-asserting on its own probe
rows and rolling them back. Prod checks run read-only (`begin transaction read only`) BEFORE the PR.

**W1 — the week and the city book (migration).** `week_anchor` knob; `world.week_of`, `world.week_start`;
`city_week_book` + `city_week_post`; the `pay_city` hunk; `world.town_hall.investors` re-cut to this week;
`world.city_history` registered in `client_rpc_entry_points`.
- Self-assert: `week_of(anchor − 1 s) = −1`, `week_of(anchor) = 0`, `week_of(anchor + 7 d − 1 s) = 0`,
  `week_start(week_of(now())) ≤ now() < week_start(week_of(now()) + 1)`. A probe house (created in the
  transaction, docked at a probe-chosen harbour picked by a stable `order by`) invests N shares: the book
  gains **exactly one row** with `ducats = price × N` (the AMOUNT, 0014's rule), `town_hall.investors`
  lists the probe at that figure, `city_history` holds it under the current week and serves an empty
  earlier week; a second gift in the same week adds and does not duplicate; `events` row count for the
  probe is unchanged by the book. Pre-image of the `pay_city` hunk occurs exactly once and reverses.
- Prod read-only before the PR: `pg_get_functiondef('public.pay_city(...)')` contains the 0144 hunk once;
  `select count(*) from city_shares` and `INVESTED`/`DONATED` events in the last 7 days per port (sizes the
  book: today's giving is a few hundred rows a week across 238 harbours); `week_of` does not exist yet.

**W2 — the lap week (migration).** `route_week_laps`; the `close_lap` hunk; `route_earnings` adds
`week {laps, net, sold, bought, supplies, repairs, wages}` and `last_week {laps, net}`, and `laps_done`
becomes this week's count (`laps_done_all` keeps the old figure for one release, then goes).
- Self-assert: a probe route closes two laps at fixed `p_now` values inside one week and one just across
  the boundary: the week row holds `laps = 2`, `net = Σ` of the two lap rows to the ducat; the third lap
  opens a new week row; `route_earnings.week.laps` reads 1 after the boundary and `last_week.laps` reads 2.
  Delete the probe route: the week rows remain (no cascade), the lap rows go as today.
- Prod read-only: `close_lap` pre-image once (after 0213's two hunks); `count(*)` of laps closed in the
  last 7 days (~6 laps a game-day per merchant × 837 fleets: expect low tens of thousands, which is the
  upsert count per week, one row per route per week, i.e. ≤ ~900 rows a week).

**W3 — the city faces (client, no migration).** `CityHistory.tsx`, the sixth tab, the Town Hall heading
"Investors this week", the dict rows above. Proof: an acceptance spec opens a city, finds
`map-city-history`, the current fold open with the served total, and that no number is computed in the
face (`tests/sections.spec.ts`: the face imports no arithmetic helper; the week guard in §3).

**W4 — the route faces (client).** RouteFold and VoyageTray print `week` and `last_week` from
`route_earnings`; the seven pills stay. Proof: the existing route specs plus one that asserts the served
`week.laps` string.

**W5 — NOT built (decided by default): no cron.** The rollover needs no job: the key does it. A weekly
`WEEK_CLOSED` receipt into each house's History tab would be the only reason for one; if the owner wants
it: `cron.schedule('byeharu-voyage:week', '2 0 * * 1', …)` (two minutes past the boundary, UTC), one
`insert … select` over `city_week_book` and `route_week_laps` for `week_of(now()) − 1` grouped by
player — about 900 houses, one statement, under a second; idempotent by week; defined inactive and
started by `wind_the_clock()` like 0125:423-426.

**Performance notes.** No table is scanned at the boundary. `town_hall` and `city_history` read
`(port_id, week)` by index; `route_earnings` reads `(route_id, week)` by primary key, the same cost as its
24-hour lap window today. Each book grows by at most one row per (giver, port, kind) and one per (route)
a week: a few thousand rows a week in all, no compaction needed for years. The two hunks add one upsert to
a write that already does an event, a treasury post and an influence post.

### Open to the owner
1. Boundary: Monday 00:00 UTC (default) or Monday 00:00 KST — one knob.
2. Influence race and city flags: kept on INFLUENCE.md's daily decay, NOT reset weekly (default).
3. Eight past weeks shown (default); the table keeps all.
4. Shares and coupons are money and never reset (default).
