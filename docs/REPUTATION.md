# REPUTATION: one balance earned on success, spent on captain skills (design R0, slices R1-R4)

**Status: design only, 2026-11-11. Nothing built, no database or prod read.** Written from the repo (migrations up to 0350). Owner row 317; the frame is `docs/SUCCESS_PLAN.md` section B.

Three things the code changed against that frame:

1. **A per-sale profit figure does exist.** `cmd.do_sell` has computed `v_profit` since 0081 (`q.total - round(fleet_cargo_basis × units)`, null when the hold does not know its cost), taxes it (0122) and writes it into the `SOLD` event. `src/app/ArrivalCard.tsx` reads that same `payload.profit`. So "a sale at a gain" costs nothing new to know.
2. **No `events` row per earn.** The book row is the append-only fact. A second row in `events` would record the same thing twice and fill `world.ledger`'s 50-row page. Earns are served from the book; only spends and level-ups write an event.
3. **`REQUEST_FILLED` is not a player's success.** `public.market_request_fill` (0288) is a merchant delivering into the player's own buy request. The player's delivery is `cmd.run_fulfil` (0087, re-cut 0311), event `FULFILLED`. That is the hook.

Every choice below is **decided by default**; the owner may reverse any.

---

## 1. Data model

### 1.1 Tables (R1)

```sql
create table public.reputation_kinds (
  code   text primary key,
  sign   smallint not null check (sign in (-1, 1)),
  capped boolean  not null default false,   -- counts against the daily cap
  word   text     not null,                 -- the server's English word for sentences
  check (not (sign = -1 and capped))
);

create table public.reputation_balance (
  player_id  uuid primary key references public.players(id) on delete cascade,
  balance    int     not null default 0 check (balance >= 0),
  seq        int     not null default 0 check (seq >= 0),      -- the newest book row
  day        int     not null default 0,                        -- public.real_day of day_earned
  day_earned int     not null default 0 check (day_earned >= 0),
  carry      numeric not null default 0 check (carry >= 0)     -- profit not yet turned into a point
);

create table public.reputation_book (
  player_id     uuid not null references public.players(id) on delete cascade,
  seq           int  not null check (seq >= 1),
  kind          text not null references public.reputation_kinds(code),
  delta         int  not null check (delta <> 0),
  balance_after int  not null check (balance_after >= 0),
  key           text,                         -- "once ever" guard, e.g. landfall:LIS
  note          jsonb not null default '{}'::jsonb,
  created_at    timestamptz not null default now(),
  primary key (player_id, seq)
);
create unique index reputation_book_once on public.reputation_book (player_id, key) where key is not null;
```

All three: RLS on, `revoke all ... from public, anon, authenticated` (0162's posture). Copy the FK and trigger shape of 0228's append-only table, which already combines `on delete cascade` with `public.forbid_mutation` (re-cut by 0097).

### 1.2 The reconcile rule (bounded: no sum, ever)

The gold book sums the whole ledger on every write (`public.ledger_sum`). This book is a chain instead:

| Trigger | When | Checks | Cost |
|---|---|---|---|
| `reputation_book_append_only` | before update or delete, each row | `public.forbid_mutation()` (the one append-only function) | none |
| `reputation_book_chains` | before insert, each row | `seq = 1` and `balance_after = delta`, or row `(player, seq-1)` exists and `balance_after = its balance_after + delta` | 1 primary-key probe |
| `reputation_reconciles` | deferred constraint trigger, after insert on the book and after insert or update of `balance, seq` on the balance | `(seq = 0 and balance = 0)` or book row `(player, seq)` has `balance_after = balance`; and no row `(player, seq+1)` exists | 2 primary-key probes |

The primary key forbids a fork, so by induction `balance = Σ delta`. Folding old rows into one carried row later is possible because the rule only reads the previous row; not built.

### 1.3 The one writer

`public.reputation_credit(p_player uuid, p_kind text, p_amount int, p_key text default null, p_note jsonb default '{}') returns int` (what was booked; security definer, server-only).

Order inside (a merchant leaves at step 2 after one `players` probe, as `promotion_credit` does):
1. `p_player` null or `p_amount = 0` → return 0.
2. `is_npc` → return 0.
3. knob `reputation_on` false → return 0.
4. `p_key` already in the book → return 0.
5. Insert-if-missing, then lock the balance row `for update`.
6. A capped kind: roll `day` to `public.real_day(now())` (0312's one day), then `amount := least(amount, rep_day_cap - day_earned)`; 0 → return 0, **no row written**.
7. A spend (`sign = -1`): `balance < amount` → raise `E_NOT_ENOUGH_REPUTATION` with figures.
8. Insert the book row (`seq + 1`), update the balance row.

Because a capped earn past the cap writes nothing, the cap also bounds the book: at most 600 rows a house a day from capped kinds.

Helpers (R1, all server-only):
- `public.reputation_sale(p_player, p_profit bigint, p_note jsonb)`: adds profit to `carry`, books `floor(carry / rep_profit_per_point)` capped by `rep_sale_max`, keeps the remainder. Null or non-positive profit: nothing.
- `public.reputation_arrival(p_player, p_voyage uuid)`: miles, pirates, landfall (section 2).
- `public.reputation_card(p_player) returns jsonb` (stable): `{balance, today, cap, seq, recent: [the 8 newest rows {seq, kind, delta, at}]}`.

### 1.4 Captain skill ranks (R2)

```sql
create table public.captain_trait_rank (
  player_officer_id uuid not null references public.player_officers(id) on delete cascade,
  trait             text not null references public.traits(code),
  rank              int  not null check (rank >= 1),
  primary key (player_officer_id, trait)
);
alter table public.captain_grades add column max_rank int check (max_rank >= 1);   -- C 3, B 5, A 7, S 10
```

Per signing (O8). A merchant's captain never has a row. Written only by `public.captain_skill_up_for`. `captain_grades` is guard-held data (`data/captains.json`, `scripts/db/world-guard.mjs`): R2 edits both.

### 1.5 Level marks (R4)

```sql
create table public.house_level_marks (
  player_id uuid not null references public.players(id) on delete cascade,
  track     text not null check (track in ('trading', 'exploration', 'combat')),
  level     int  not null check (level >= 1),
  primary key (player_id, track)
);
```

### 1.6 Events

| Kind | Slice | Written by | Payload |
|---|---|---|---|
| none for earns | R1 | — | the book row is the record |
| `CAPTAIN_SKILL` | R2 | `captain_skill_up_for` | `{officer, name, trait, rank, cost}` |
| `CAPTAIN_PROMOTED` | R3 | `promote_captain_for` (it writes none today) | `{officer, name, grade, cost}` |
| `LEVEL_UP` | R4 | `level_marks_settle` | `{track, level, reputation}` |

### 1.7 What each new thing must NOT duplicate

| New thing | Must not become |
|---|---|
| `reputation_balance.balance` | a purse: never through `public.credit`, `ledger`, `mint_guard`, `stats_live` |
| `reputation_book` | a second `events` stream; no `REPUTATION` event |
| `reputation_kinds` | amounts: every number is a `world_config` knob read in one helper |
| `day_earned` | a second "day": only `public.real_day` |
| `carry` | a profit record: profit stays `do_sell`'s `v_profit` |
| `captain_trait_rank` | a trait value: the value stays `public.crew_terms`; the multiplier is `public.captain_rank_mult` only |
| `house_level_marks` | a level: the level stays derived by `public.player_progress`. Only `level_marks_settle` writes it; only it and `reputation_card` read it (proved by a `pg_proc` scan) |

---

## 2. The earn table

Magnitudes found in the repo:
- Starting purse 40,000; median best first voyage 18.0 % of the stake, about 7,200 profit (proof 05, `docs/dev-log/2026-10-31-goods-price-level.md`).
- A starter's reach is 1,700 nm; ships make about 230-290 nm a real minute (`2026-11-05-cargo-ships.md`, measured on merchants and cargo hulls, **not on a starter barca**), so a 1,200 nm leg is about 5 real minutes.
- The busiest human has 123 voyage reports and about 300 ledger rows in total; 18 of 19 humans are level 1 in both tracks (`2026-11-06-levels-are-lit.md`).
- Levels: 100 ducats of turnover = 1 point; level L begins at 25 × (L-1)² points.

| Kind | Capped | Amount | Source of truth | Once-key / anti-farm | Hook |
|---|---|---|---|---|---|
| `sale` | yes | 1 per 250 profit (`rep_profit_per_point`), remainder carried, at most 120 a sale (`rep_sale_max`) | `do_sell`'s `v_profit` (the `SOLD` event's `profit`) | must be at a gain; unknown cost earns nothing; buy-and-sell in one port loses the spread; splitting a lot gains nothing (carry) | `cmd.do_sell` |
| `miles` | yes | `floor(total_nm / 100)` (`rep_nm_per_point`), at most 40 an arrival, voyage ≥ 100 nm, arrival at a port | `voyages.total_nm` | `miles:<voyage id>` | `voyage.settle` |
| `pirates` | yes | `voyage_xp_tracks(v).combat × 2` (`rep_per_fight_point`): evaded 10, driven off 30 | `voyage_events` PIRATES rows through `public.fight_points` | `pirates:<voyage id>` | `voyage.settle` |
| `landfall` | no | 25 (`rep_landfall`) | no `VOYAGE_REPORT` to that port code with `created_at < v.departed_at` | `landfall:<port code>` | `voyage.settle` |
| `request` | no | `floor(premium / 250)`, at least 5, at most 100 | `FULFILLED` event's `premium` (`v_pay`) | supply is the cities' own contracts | `cmd.run_fulfil` |
| `built` | no | 100 (`rep_built`) | `HULL_LAID_DOWN` | `built:<ship id>`; a gold and materials sink | `cmd.do_build` |
| `lap` | yes | 10 if the lap's `net > 0` (`rep_lap`) | `standing_route_laps.net` | `lap:<lap id>` | R4 |
| `battle` | no | 40 a win (`rep_battle`) | `BATTLE_REPORT` outcome | `battle:<battle id>` | C5, not R1 |
| `level` | no | 10 × the level reached | `player_progress` against the mark | `level:<track>:<n>` | R4 |
| `convert` | no | section 4 | `player_items`, `promotion_progress` | `convert:items` | R3 |
| `skill`, `promote` | spend | sections 3, 4 | — | — | R2, R3 |

**Daily cap: 600** (`rep_day_cap`) over capped kinds, per UTC day. Buys never earn. No back-pay: it banks from the deploy, as 0162 did.

**Why `lap` and `battle` are not in R1.** A lap's sales and arrivals already earn; `cmd.standing_route_close_lap` is named by 15 migrations and runs in the merchants' lap job. Battles are dark and C1/C2 re-cut those bodies next; two PRs slicing one body in one pipeline is the risk. R1 seeds both kinds and knobs.

### Arithmetic

First session, R1 + R2 only, one 1,200 nm voyage:
- sale: 7,200 / 250 = **28**
- miles: 1,200 / 100 = **12**
- landfall: **25**
- total **65** ≥ 50, the first skill step (she needs a hired, seated captain; whether hire wages were scaled ×5 on 2026-10-31 is not verified).

With R4: a 30,000 buy is 300 points → Trading level 4; the 37,000 sale brings 670 points → level 6. Gifts 10 × (2+3+4+5+6) = **200**. First session about 265: steps 1 and 2 of one skill (50 + 150).

A mid day, 10 voyages: 10 × (28 to 60 sale + 12 miles) = 400 to 720, so at or near the cap. A standing route running all day reaches the cap: **600 a day is the steady income**.

Last steps: step 10 alone costs 2,750 = 4.6 days at the cap. One skill to 10 costs 11,000 = 18 days. An S captain's five skills in use: 55,000 = 92 days. Level gifts to 20 total 2,090 a track.

---

## 3. The spend: captain skill ranks (R2)

**Cost of step r: `50 × r × (r+1) / 2`** (`rep_skill_base` 50).

| Step | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
|---|---|---|---|---|---|---|---|---|---|---|
| Cost | 50 | 150 | 300 | 500 | 750 | 1,050 | 1,400 | 1,800 | 2,250 | 2,750 |
| Total | 50 | 200 | 500 | 1,000 | 1,750 | 2,800 | 4,200 | 6,000 | 8,250 | 11,000 |

**Max by grade** (`captain_grades.max_rank`): C 3, B 5, A 7, S 10. Totals 500 / 1,750 / 4,200 / 11,000.

**What a step adds: +4 % of that skill's own value** (`captain_skill_rank_pct` 4), as one multiplier:

`public.captain_rank_mult(p_rank int)` = `1 + p_rank × captain_skill_rank_pct / 100` (sql, stable). The one arithmetic; `crew_terms` and the read both call it.

Her term becomes `greatest(base, grade floor) × effect mult × level mult × rank mult × cabin rate × homesick`. Every reader takes it through `crew_terms`: `crew_pct` (speed, hold, spread, crew saved, storm, supplies, category spread), `ship_crew_terms` (fight stats), `world.crew_bonuses`, `world.captain_stats`.

Example: a 9 % S navigator at step 10 gives 12.6 %; at captain level 20 (×1.38) 17.4 %.

- **The 25 % cap does not move.** It is the crew's, in `crew_pct`; Command lifts under it as today. Ranks get one captain near the cap; they never pass it.
- **Grade floors**: the multiplier applies after the floor, so a promoted captain's ranks are worth more.
- **Promotion** keeps every rank and raises `max_rank`.
- **`crew_bite` dark** (its prod value was not read): the dark arm reads only her job, so the multiplier is cut into both arms and dark only her job's rank counts. The door refuses a skill nothing reads.

### The `crew_terms` hunks

Live body = 0157 create + 0160 (4 hunks) + 0161 (signature gains `p_at`, 1 hunk) + 0166 (2 hunks, dark arm). 0162, 0168, 0179, 0189, 0198, 0250, 0323, 0337 name it and leave it unchanged. **Slice from `pg_get_functiondef` at the head, LF-normalised**; the texts below are rebuilt from those files, not read from prod.

| # | Arm | OLD (occurs once) | NEW |
|---|---|---|---|
| 1 | dark | `             j.job_pct * public.captain_level_mult(po.id, jt.focus)` + newline | same line, then `             * case when tr.rank is null then 1 else public.captain_rank_mult(tr.rank) end` |
| 2 | dark | `        join public.trait_effects te on te.trait = j.job` + newline | same, then `        left join public.captain_trait_rank tr on tr.player_officer_id = po.id and tr.trait = j.job` |
| 3 | lit | `             * te.mult * public.captain_level_mult(po.id, t.focus)` + newline | same, then the same `case` line |
| 4 | lit | `        join public.trait_effects te on te.trait = ca.trait` + newline | same, then `        left join public.captain_trait_rank tr on tr.player_officer_id = po.id and tr.trait = ca.trait` |

The `case` keeps the knob unread for a captain with no rank row. That matters: `wc_num` was measured at 2.7 ms a call inside `crew_terms` on prod (`2026-11-07-a-captain-has-a-sheet.md`), and 498 merchant fleets have captains. A merchant pays one primary-key probe into a table that holds only players' rows.

### The door

`cmd.captain_skill_up(p_code text, p_trait text)` → `public.captain_skill_up_for(p_player, p_code, p_trait)`. Returns 0162's envelope `{ok, error_code, error_message, fixes}`.

| Refusal | When | Sentence |
|---|---|---|
| `E_NOT_SIGNED_IN` | no caller | Nobody is signed in. |
| `E_NOT_SIGNED` | not her captain | You do not keep that captain. |
| `E_TRAIT_NOT_KNOWN` | not among her grade's known skills | Ana de Sousa does not know PILOT. |
| `E_TRAIT_IDLE` | nothing reads it today (`trait_in_use` false, or dark and not her job) | Pilot does nothing yet. |
| `E_NOT_IN_PORT` | seated in a fleet that is not docked | Ana de Sousa is at sea aboard Gaivota. A skill is raised in port. |
| `E_TOP_RANK` | at her grade's max | Navigator is 3 of 3: a B captain reaches 5. |
| `E_NOT_ENOUGH_REPUTATION` | balance below cost | Needs 150 Reputation: you have 90. |

Ashore is allowed. At sea is refused because `voyage.storm_hull_lost` reads `crew_pct` during settlement; a rank raised mid-voyage would make a settlement depend on when it runs.

**No refund, no respec.** No door dismisses a captain today (none found in the chain), so a rank is never lost.

`world.captain_skills(p_code text)` (stable, definer, ACL as `world.levels()`): `{reputation, skills: [{trait, word, rank, max, pct_now, cost, in_use, can, why}]}`. `pct_now` is the rank's own bonus (`rank × 4`). Absolute figures stay on the sheet's stat lines, so no trait value is computed twice.

---

## 4. R3: promotion costs Reputation

**Rule: one item = 100 Reputation** (`rep_per_promotion_item`). Promotion costs become B 1,000 / A 2,000 / S 4,000. The level gates (5 / 10 / 15) and "aboard, in port" stay.

**Conversion, per human company:**
`floor(100 × (Σ qty of the three items over every port + Σ over tracks of promotion_progress.points / promotion_items.points))`, booked once as `convert`, key `convert:items`, note `{charts, seals, honours, banked}`.

Arithmetic: 6 Sea Charts at Lisbon and 50 of 100 exploration points banked → 100 × 6.5 = 650. Six charts were 60 % of a B promotion; 600 of 1,000 is 60 %. Nobody's promotion power falls, and the three tracks become one pool.

What goes:

| Thing | Fate | How |
|---|---|---|
| `promotion_credit` calls | removed | hunks removing 0162's added lines from `voyage.settle`, `cmd.do_buy`, `cmd.do_sell` (0162 hunks n3, n4, n5 reversed; in settle, cut against R1's text) |
| `public.promotion_credit` | dropped | no caller left (`pg_proc` scan) |
| `promotion_progress` | dropped after conversion | history is the `convert` book row's note |
| `player_items` rows of the three items | deleted after conversion | the table is not append-only |
| `promotion_items`, the three `item_kinds` rows, their `item_use` rows (0166) | deleted, after asserting no `player_items` row holds one (0162's own rollback rule) | edits `data/captains.json` and the world guard |
| `captain_grades.promote_items` | replaced by `promote_reputation` (1000 / 2000 / 4000) | lock-retry `alter`, 0162's pattern |
| `public.promotion_next` (0162 + one 0166 hunk) | hunks: drop item fields; serve `cost`, `reputation`, `line` = "Promote to B · 1,000 Reputation · Exploration level 5" | |
| `public.promote_captain_for` (0162 only) | hunks: `E_NOT_ENOUGH_ITEMS` → `E_NOT_ENOUGH_REPUTATION`; the `player_items` update → `reputation_credit(..., 'promote', -cost)`; emit `CAPTAIN_PROMOTED`; the `E_LEVEL_TOO_LOW` sentence takes its track word from `trait_foci` directly | |

`reputation_credit` stays the one place the balance falls; two verbs call it.

---

## 5. R4: a level-up moment

Levels stay derived. The mark records only which crossings were paid.

`public.level_marks_settle(p_player) returns jsonb`: merchant → null. One `player_progress` read. For each track (combat only when `playable`), for each L from mark + 1 to the derived level: `reputation_credit(player, 'level', 10 × L, 'level:<track>:<L>')`, emit `LEVEL_UP`, then raise the mark. Two guards make it idempotent: the mark and the book key.

Callers:
1. `public.reputation_arrival` (a re-cut of R1's own function, so **no new hunk on `voyage.settle`**): an offline arrival pays at its own moment.
2. `cmd.level_up()`: `reputation_card` serves `level_marks`; the client calls the door once when a served level stands above its mark.

`cmd.do_sell` is not a caller: `player_progress` costs about 22 ms warm for the busiest human and a manifest sells several goods.

**Back-pay: none.** The migration seeds a mark at every human's level at deploy (19 `player_progress` reads). A new house has no row and counts as 1.

R4 also carries the `lap` hook: one line in `cmd.standing_route_close_lap` after its `ROUTE_LAP` emit.

---

## 6. The slices

Common to all: number = prod head + 1 at build time; 0162's shape (guard with `statement_timeout` and `lock_timeout 5s`, pre-images, a hunks table, each hunk once and reversing, ACL / volatility / definer / config unmoved); probes are `new_house` rows rolled back by a raised sentinel; no assert counts or sums a live table; proofs take the next free number in `scripts/db/proofs/` (54 is the last); PROD CHECK files are one pure SELECT each under `scripts/ops/harness/reputation/`.

### R1: the book, the earn hooks, the figure

| Function | Create / hunk | History |
|---|---|---|
| `reputation_credit`, `reputation_sale`, `reputation_arrival`, `reputation_card`, the two trigger functions | create | — |
| `cmd.do_sell(uuid, jsonb)` | 1 hunk: after 0162's two `promotion_credit` lines add `perform public.reputation_sale(f.player_id, v_profit, jsonb_build_object('port', f.port_id, 'good', g.code));` | created 0007; hunk files found by exact search: 0050, 0061, 0081, 0096, 0122, 0128, 0147, 0160, 0162, 0194, 0212, 0224, 0317; 35 files name it |
| `voyage.settle(uuid, timestamptz)` | 1 hunk: after 0162's `promotion_credit ... from public.voyage_xp_tracks(v.id) x;` statement, inside 0127's players-only block | hunk files found: 0127, 0154, 0155, 0157, 0158, 0160, 0162, 0163, 0168, 0189, 0202, 0213; about 70 files name it |
| `cmd.run_fulfil(uuid, uuid)` | 1 hunk after `perform public.credit(f.player_id, 'PREMIUM', v_pay, v_event);` | 0087, 0311 (0315 names it) |
| `cmd.do_build(uuid, jsonb)` | 1 hunk after the `HULL_LAID_DOWN` emit | 0072; named by 0074, 0096, 0122, 0130, 0133, 0135, 0138, 0154, 0159, 0165, 0180, 0184 |
| `world.player()` | 1 hunk: after `      'levels',        public.player_progress(v_id),` add `      'reputation',    public.reputation_card(v_id),` | 0014, 0069, 0143, 0215, 0241 |

The hunk lists were found by text search over differing hunk styles and may miss a file; the builder confirms each OLD text occurs once on the live body before the PR. The `run_fulfil` and `do_build` hooks are droppable if their live text does not slice cleanly.

- **Self-assert (probe, rolled back):** chain: three credits give seq 1-3 and the balance equals the last `balance_after`; a hand-inserted row with a wrong `balance_after` is refused; an update of a book row is refused; a balance update with no book row fails at the deferred check. Sale: profit 7,200 → 28, carry 200; 100 then 150 → 0 then 1; a loss and a null profit → 0. Cap: `day_earned` 590 + 28 → 10, the next → 0 and no row. Landfall twice → once. A merchant: 0, no row. `reputation_on` false: 0. A real probe sale through `cmd.do_sell` books what `reputation_sale` says. Hunks reverse; 0 client write grants.
- **Proof** `NN_reputation.sql`: `REP_CHAIN`, `REP_SALE_GAIN_ONLY`, `REP_CARRY`, `REP_CAP`, `REP_ONCE`, `REP_MERCHANT_NOTHING` (`pg_stat_xact_user_tables` on the three tables = 0 after 50 merchant sales), `REP_NOT_GOLD` (purses, ledger and `stats_live` unmoved by a credit), `REP_ARRIVAL` (a probe voyage settles: miles + landfall).
- **Specs:** `tests/reputation.spec.ts` (top bar figure, arrival card line, EN and KO, 390 and 1280), `rpc.surface`, `words`, `i18n.keys`.
- **PROD CHECK:** `before-hunks.sql` (each OLD text's count in each live body = 1), `before-beats.sql` (`arrivals_beats` avg and p95), `after.sql` (tables, kinds, knobs, ACLs, volatility), `after-beats.sql`.
- **Hot path:** a merchant sale gains one function call and one `players` probe, the cost `promotion_credit` already has there. Settle's hunk is inside the players-only block: merchants pay nothing. A human arrival adds about 3 balance-row writes and one events probe. Measure: OLD against NEW `do_sell` on 200 probe merchant sales, interleaved (0250's method), printed as a notice; `arrivals_beats` 30 minutes before and after (target avg ≤ 3 s, p95 < 5 s).
- **Rollback:** `reputation_on` false stops every write at once; forward migration restoring the OLD hunks. Tables stay.
- **Client:** `src/app/TopBar.tsx` (a `Figure` left of the purse, `data-testid="reputation"`), `src/app/ArrivalCard.tsx` (sum of `player.reputation.recent` rows with `seq` above the last seen and an earn kind, on the read that brings the report; printed as `+65 Reputation`), `src/features/you/YouScreen.tsx` (balance and `today / cap`), `src/lib/rpc/types.ts`, `src/lib/i18n/dict/shell.ts` and `feed.ts`. Words: **Reputation / 평판**; `+{n} Reputation` / `평판 +{n}`; `Today {a} / {b}` / `오늘 {a} / {b}`.

### R2: captain skill ranks

| Function | Create / hunk |
|---|---|
| `captain_rank_mult`, `captain_skill_up_for`, `cmd.captain_skill_up`, `world.captain_skills` | create |
| `public.crew_terms(uuid, timestamptz)` | 4 hunks (section 3) |
| `public.client_rpc_entry_points()` | 1 hunk, +2 rows, at the head as 0337 did |

- **Self-assert:** OLD = NEW `crew_terms` for every fleet at one instant with no rank rows (0166's `pg_temp.old_` method). Probe: step 2 on a navigator → her speed term × 1.08 exactly, her other terms and other captains unmoved, dark and lit (the switch set and restored inside the probe, as 0162 does); two captains past 25 % still read 25 % from `crew_pct`; each refusal with its figures; cost 50 then 150 leaves the book chained; a promoted captain keeps her ranks and may go past the old max.
- **Proof** `NN_captain_skills.sql`: `SKILL_ONE_TERM` (speed, hold, spread, the sheet and `crew_bonuses` all move by the same factor), `SKILL_CAP`, `SKILL_FLOOR`, `SKILL_MAX_BY_GRADE`, `SKILL_MERCHANT_EQUAL` (every merchant fleet × 4 effects unmoved), `SKILL_FIGHT_BYTES` (30 seeded fights byte-equal with no ranks, different with one, as proof 44).
- **PROD CHECK:** `switches.sql` (`crew_bite`, `levels_bite`, `combat_bite`), `before-crew-terms.sql` (the four OLD texts once each), `after.sql`.
- **Hot path:** `crew_terms` gains one left join on a primary key. Bound: merchant speed + hold and 200 `spread_effective` quotes NEW ≤ OLD × 1.05 + 10 ms, the faster of two passes at `random_page_cost` 1.1, printed in CI's chain, never raised on prod.
- **After-check:** 30 minutes (it alters live play once a player spends). **Rollback:** forward migration reversing the four hunks; rank rows stay and read as nothing.
- **Client:** `src/live/CaptainStats.tsx` or a new `CaptainSkills.tsx` in `CaptainSheet`, `src/live/YourCaptains.tsx`, `useCaptainSkills.ts` (`useServedRead`), `catalog.ts`, `types.ts`, `index.ts`, `dict/books.ts`. The upgrade row, in text:

  `Navigator · 2 / 5 · +8 %          [ Upgrade · 300 ]`
  `항해사 · 2 / 5 · +8 %             [ 강화 · 300 ]`

  A greyed button with the server's `why` under it when `can` is false. Words: heading **Captain skills / 선장 스킬** (the card's "Traits / 특성" becomes "Skills / 스킬"; the Academy keeps "Skills / 기술"); **Upgrade / 강화**. The step has no noun: `2 / 5` only, because "rank", "level", "grade" and "tier" are all taken or banned by `docs/WORDS.md`.

### R3: promotion costs Reputation

Functions: section 4's table. `voyage.settle`, `cmd.do_buy` (hunk files found: 0050, 0061, 0083, 0122, 0160, 0162, 0224) and `cmd.do_sell` lose one statement each.

- **Self-assert:** probe with 6 charts and 50 banked → 650, key once, a second run 0; a level-5 C with 999 refused with figures, with 1,000 promoted, balance 0, event written; no `promotion_` function left but `promotion_next`; no body names `promotion_credit`; hunks reverse.
- **Proof:** `PROMO_CONVERT_ARITH`, `PROMO_POWER_KEPT` (items / needed before = Reputation / cost after, for 10 random holdings), `PROMO_COSTS`, `PROMO_NO_ITEMS_LEFT`.
- **PROD CHECK:** `before-holdings.sql` (every human's items by port and banked points: the expected conversion, printed in the PR), `after-holdings.sql` (each `convert` row beside it).
- **Hot path:** one call fewer on every merchant buy, sale and human arrival. **Rollback:** forward migration restoring 0162's hunks; converted Reputation is not taken back.
- **Client:** `YourCaptains.tsx` `Promote` (reads `cost` and `reputation`), `types.ts`, `dict/books.ts`: `Promote to B · 1,000` / `B(으)로 승급 · 1,000`; item words leave the dictionary and `docs/WORDS.md`.

### R4: the level-up moment

| Function | Create / hunk |
|---|---|
| `level_marks_settle`, `cmd.level_up` | create |
| `public.reputation_arrival` | 1 hunk (R1's own body) |
| `public.reputation_card` | 1 hunk (`level_marks`) |
| `cmd.standing_route_close_lap(uuid, timestamptz)` | 1 hunk; created 0092, named by 0093, 0094, 0096, 0116, 0121, 0122, 0128, 0129, 0213, 0266, 0275, 0278, 0301, 0315 |
| `public.client_rpc_entry_points()` | 1 hunk, +1 |

- **Self-assert:** probe at mark 1 with turnover for level 4 → three `LEVEL_UP` events, 20 + 30 + 40 = 90, mark 4; a second call writes nothing; combat untouched while not playable; a merchant: null; a positive lap pays 10 once, a negative lap 0.
- **Proof:** `LEVEL_ONCE`, `LEVEL_NO_BACKPAY` (a seeded mark pays nothing), `LEVEL_STAYS_DERIVED` (`player_progress` byte-equal before and after; only two bodies name the table).
- **Hot path:** one `player_progress` per human arrival, about 22 ms warm and 688 ms cold on prod (measured 2026-11-07); merchants leave first. 30-minute after-check on `arrivals_beats`. **Rollback:** forward migration reversing the hunks; `rep_level_per_level` 0 stops the gift.
- **Client:** `ArrivalCard.tsx` (its level line reads `LEVEL_UP` events instead of comparing two reads, and prints `Trading level 5 · +50 Reputation` / `교역 5레벨 · 평판 +50`), `AppShell` or `worldStore` (one `cmd.level_up()` call when a level stands above its mark), `src/features/command/levels/Levels.tsx` (next level's gift beside each bar: `Next +60` / `다음 +60`).

---

## 7. Risks and open points

| # | Point | Default |
|---|---|---|
| 1 | Hunk texts here are rebuilt from migration files, not read from prod | the builder slices from `pg_get_functiondef` at the head and runs `before-hunks.sql` first |
| 2 | `crew_bite` on prod is unknown; dark, only a captain's job can be raised | build both arms; read `switches.sql` before R2 |
| 3 | 600 a day may be too fast or slow; no human plays daily yet | every number is a knob; re-read the book after two weeks |
| 4 | The veteran earns landfall only on ports new to her | accepted: no back-pay |
| 5 | Level gifts give a new player about 200 in the first voyage | intended: the first session's hook |
| 6 | Reputation is company-wide, items were per port | accepted; promotion still needs her aboard in port |
| 7 | Deleting three `item_kinds` rows touches guard-held data and any Codex list | if the guard or a list makes it wide, keep the rows one slice and delete them in a follow-up |
| 8 | KO words 평판, 선장 스킬, 강화 are the designer's | the owner sees them on the PR's screenshots |
| 9 | No noun for a skill step | `2 / 5` only |
| 10 | `E_TRAIT_IDLE` is a new refusal on a spend | kept: spending on a skill that does nothing is a trap, not a gate |
| 11 | The book grows without a compactor | bounded by the cap (≤ 600 rows a house a day); fold later |
| 12 | A starter barca's real speed and the ×5 on hire wages were not verified | measure in R1's proof with a probe barca |
| 13 | `REP_MERCHANT_NOTHING` relies on `is_npc` being read before anything else | asserted by write counts, not by reading the code |

### Critical files for implementation
- `supabase/migrations/20260818000162_a_captain_is_promoted_for_what_her_company_has_done.sql` (the migration shape to copy; the hunks R1 anchors on and R3 reverses)
- `supabase/migrations/20260818000160_a_captain_learns_in_three_trades_and_misses_home.sql` (with 0157, 0161, 0166: the live `crew_terms` text)
- `supabase/migrations/20260818000081_the_hold_knows_what_it_cost.sql` (with 0122: `v_profit` in `cmd.do_sell`)
- `supabase/migrations/20260818000004_a_house_its_fleets_and_an_honest_ledger.sql` (`forbid_mutation`, the reconcile triggers this book must not copy)
- `src/app/ArrivalCard.tsx` (with `src/app/TopBar.tsx` and `src/live/YourCaptains.tsx`: the client surfaces)
