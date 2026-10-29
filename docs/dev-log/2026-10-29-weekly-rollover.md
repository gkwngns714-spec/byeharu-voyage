# 2026-10-29 — the weekly rollover (owner row 173): the week is a key

**Slice:** `osn-w-rollover` — migration **20260818000275_the_week_is_a_key.sql** + the client faces (W3/W4).
Owner row 173 (2026-10-20): *"The investment in city, Lap records should be reset every week. There will be a
history tab where you can see the last week's investment records when pressing a city."* The owner accepted ALL
defaults of `docs/WEEKLY_ROLLOVER.md` on 2026-10-25: Monday 00:00 UTC; the Investors board and the route lap
counters reset; shares, works, influence and flags do not; no backfill; the History tab keeps 8 weeks; no cron.

**The one idea.** A "reset" is not a delete and not a job that zeroes rows. **The week is a KEY.** Every figure
the owner wants reset is written under the week it happened in; the live faces read the current week's key and
the History tab reads the earlier keys of the same table. Nothing is ever deleted; `events` and the ledger are
untouched; no row is rewritten at the boundary.

## The build (W1-W4 in ONE migration + the client, so the slice is never half-shipped)

The design splits W1 and W2 into two migrations; the slice reserves ONE number (0275), so W1 and W2 land as one
file in two labelled sections — the same content, one deploy. Said here because the design's own §5 says "each
migration slice is ONE migration": decided by the reservation, not by the design's split.

- **§1 the week.** `week_anchor` knob (`2026-10-26T00:00:00Z`), `world.week_of(p_at default now())`,
  `world.week_start(p_week)` — the pair beside `world.game_day`, stable, security definer, server-only.
- **§2 the city book.** `public.city_week_book` + `public.city_week_post` (its ONE writer), called from
  `public.pay_city`'s SHARE/DONATION branch — the same branch 0144 gave `influence_post`. Upsert ADDS
  (`gifts += 1` on a DONATION — decided by default: a "gift" is a donation; an investment is a share).
- **§3 the lap book.** `public.route_week_laps` (PK route_id+week, no FK on route_id: a deleted route keeps its
  history), written by `cmd.standing_route_close_lap` alone, one hunk after the lap row closes, stamped
  `world.week_of(p_now)`.
- **§4 the read.** `world.city_history(p_port, p_weeks default 8)` — the current week and the past
  `min(p_weeks, 8)`, newest first; the door serves eight even if asked for more. Registered in
  `client_rpc_entry_points`; authenticated only, like the Town Hall.
- **The six re-cuts** (each hunk occurs exactly once and reverses to its pre-image; ACL/volatility/definer/
  config unmoved; the md5 of every other function in the four schemas unmoved):
  1. `public.pay_city` — the branch gains `city_week_post` (the book's one writer).
  2. `world.town_hall` — `investors` re-cut to THIS week's `city_week_book` (`{name, merchant, invested,
     donated, total}`, capped 50); the share register and `you.holdings` are untouched.
  3. `cmd.standing_route_close_lap` — the closed lap upserts into this week's book row.
  4. `public.route_earnings` — gains `week` / `last_week`; `laps_done` becomes this week's count;
     `laps_done_all` keeps the old figure for one release, then goes.
  5. `world.standing_routes` — each route gains the served `earnings` object (composed, never recomputed).
     **This re-cut is not named in the design**: §5 W4 names the faces (RouteFold, VoyageTray) but not the
     serve that reaches them, and those two faces read only the routes book. Decided by default and declared
     in the migration header; the alternative (a new door) would be a second earnings reader.
  6. `public.client_rpc_entry_points` — the `city_history` row.

**The client (W3/W4).** `src/live/CityHistory.tsx` (new face), the sixth tab (`src/features/map/cityTab.ts`,
`CityTabs.tsx`), the Town Hall board re-cut (`CityTownHall.tsx`), the weekly counters on the route fold
(`RouteFold.tsx`) and the voyage tray (`VoyageTray.tsx`), the typed door (`catalog.ts`, `index.ts`, `types.ts`),
the words (`dict/town.ts`, `dict/map.ts`, `dict/routes.ts` — EN + KO, nothing hard-coded). A press SELECTS: the
History tab is a segmented tab; a week's row is a fold that opens downward, moving only what is below it.

**The week guard.** `tests/duplication.spec.ts` gains one rule: `604800`, `getDay(` and `startOfWeek` may not
appear in `src/` or in any migration after 0275 — the client never computes a week; it prints the week, starts
and ends served. `tests/rpc.surface.spec.ts` pins the three new server-only functions.

## The probe plan (inside the migration's self-assert; every planted row rolls back)

- **(a) the re-cuts:** the six hunks each occur once in the new bodies and reverse to the pre-images; the four
  new functions are the only ones minted (one place each); the registry +1 (city_history, authenticated only);
  the books server-only under RLS; `city_week_post` called by `pay_city` alone, `route_week_laps` written by
  `close_lap` alone.
- **(b) the clock:** `week_of(anchor − 1 s) = −1`, `week_of(anchor) = 0`, `week_of(anchor + 7 d − 1 s) = 0`,
  `week_of(anchor + 7 d) = 1`, and `week_start(week_of(now())) ≤ now() < week_start(week_of(now()) + 1)`.
- **(c) the city book, through the real doors:** a probe house invests N shares (the first harbour by code whose
  works offer a stake, with the fewest book rows so the probe is served under every cap): EXACTLY one SHARE row
  with `ducats = price × N` (the amount), under `week_of(now())`; two gifts (1000 + 500) ADD to one DONATION row
  (1500, gifts 2) — no duplicate; `world.town_hall`'s board serves the probe at those figures; `city_history`
  folds the current week with them and an empty earlier week (9 folds, `starts` = `week_start(week)`); the
  house's events are exactly the founding, the invest's own and the two gifts' own — 4 in all, none from the
  book. The two switches the probe lights (city_treasury_enabled, influence_enabled) are snapshotted and must
  read back as found.
- **(d) the lap book:** one probe route, one probe fleet; laps 1-2 close at `week_start(week_of(now())) − 2 h` and
  `− 1 h` (the week before this one, an hour before the boundary), lap 3 closes at `now()` (this week). Each lap
  carries one done SELL (1,000 total, 10 tax, 50 wages → net 940). The book holds two rows: `{laps 2, net 1880}`
  (last week) and `{laps 1, net 940}` (this week), sold/wages summed to the ducat; `route_earnings` reads
  `week.laps = 1`, `last_week.laps = 2`, `laps_done = 1`, `laps_done_all = 3`; the served route book carries the
  same object; deleting the probe route keeps the week rows (no cascade) while the lap rows go as today.
- **(e) the probes left nothing:** players and both books back to their counts, the switches as found.

**The OLD/NEW switch:** the chain's other probes compare old vs new bodies; this slice ADDS, it changes no
existing answer except the two readers, whose re-cuts reverse to their pre-images hunk by hunk (a). There is no
"old" behaviour of a book that did not exist, so the old side IS the reversal; the positive controls are (c)'s
second-gift add and (d)'s boundary crossing.

**Prod-proof audit (the 0273 rule, applied before the gate).** No probe asserts a write against a price, offer,
quote or stock read taken BEFORE it: the (c) probe's cost is the invest receipt's OWN reported figure (the
earlier draft compared it with a pre-read `price × offer` — removed), the book rows are asserted against that
receipt figure and against the exact amounts the gifts carried (donate/invest are all-or-nothing: they land
fully or refuse loudly), and the (d) probe's nets derive from the planted orders' own results on the probe's own
route and fleet. Nothing in the file reads `world.quote` or a stock.

## PROD CHECKS (before the push; read-only, in the PR body)

```sql
-- the six live bodies are the ones the hunks were cut against (their md5s, from the local chain's receipt)
select md5(pg_get_functiondef('public.pay_city(uuid,uuid,text,bigint,uuid)'::regprocedure)) as pay_city,
       md5(pg_get_functiondef('world.town_hall(uuid)'::regprocedure)) as town_hall,
       md5(pg_get_functiondef('cmd.standing_route_close_lap(uuid,timestamptz)'::regprocedure)) as close_lap,
       md5(pg_get_functiondef('public.route_earnings(uuid)'::regprocedure)) as route_earnings,
       md5(pg_get_functiondef('world.standing_routes()'::regprocedure)) as standing_routes,
       md5(pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure)) as registry;
-- the city book's size: today's giving is a few hundred rows a week across the harbours
select count(*) from public.city_shares;
select count(*) from public.events where kind in ('INVESTED', 'DONATED') and created_at > now() - interval '7 days';
-- the lap book's size: one row per route per week (~up to a few hundred a week)
select count(*) from public.standing_route_laps where closed_at > now() - interval '7 days';
-- the week does not exist yet
select to_regprocedure('world.week_of(timestamptz)') is null;
```
The prod reads run `begin transaction read only`; every function called is `s`/`i` volatility.

## After-check (30 minutes, from the push)

1. The first INVESTED / DONATED after the push land rows under `world.week_of(now())`
   (`select * from public.city_week_book order by updated_at desc limit 5`).
2. The first closed laps land rows under the current week (`select * from public.route_week_laps order by
   updated_at desc limit 5`); the `laps` column grows on the next close of the same route.
3. The Town Hall board reads this week alone; the History tab folds the current week open with the served total.
4. The command fold prints "N laps this week" from the served figure; the lap counters read the week's, not the
   all-time count (`laps_done` vs `laps_done_all`).
5. Economy numbers unchanged: the book writes no events, no ledger lines, no flows; the treasury and the
   influence books move exactly as before (the hunk adds one upsert to a write that already did three).

## Forward rollback (if the slice must come off)

Reverse the six hunks to their pre-images (the re-cut loop's own reversal, re-run with old and new swapped);
`drop function world.city_history(uuid, int), public.city_week_post(uuid,uuid,text,bigint),
world.week_of(timestamptz), world.week_start(bigint)`; drop the two tables and their indexes; delete the
`week_anchor` knob; reverse the registry hunk. The books can stay: append-only, read by nothing once the readers
reverse — the same forward shape 0144 chose for its book.

## Ambiguities and what was decided by default

1. **One migration, not two.** The design's W1 and W2 are separate migrations; the slice holds ONE reserved
   number (0275), so they land as one file, two sections. (Declared in the file's header.)
2. **The serve that reaches RouteFold/VoyageTray.** §5 W4 names the faces but no door; the one serve both faces
   read is `world.standing_routes`, so it gains the composed `earnings` key — an extra re-cut, named in the
   header and here.
3. **`gifts` counts donations only.** "An upsert adds ducats and gifts += 1" — a SHARE is an investment, not a
   gift, so `gifts` increments on DONATION alone (the column is not served anywhere yet).
4. **The door's eight is a cap.** `city_history` serves the current week plus `min(p_weeks, 8)`; the table keeps
   every week.
5. **`route_earnings.week` is always an object** (zeros while no lap closed this week — the reset reads "0 laps
   this week", the owner's own ask); `last_week` is null while none closed, and the faces print it only then.
6. **Dependency on 0273/0274.** The pre-images are cut against the bodies at prod head 0272. Neither 0273
   (resolve_qty) nor 0274 (the clear's advance) re-cuts a body this file cuts against — if one lands differently,
   the hunk self-asserts fail loudly at apply, which is the safe failure.

## The gate (2026-10-29): `node scripts/db/proof.mjs standing`, one cached run

`prefix cache: restored 261/262 …; applying 1` → `chain: 262 migration(s) — 261 restored from the prefix cache,
1 applied here — 262 with a self-assert receipt (268 receipt line(s)); chain key baed8aef323ea4fb, 9.2 s` →
`world-guard ok: the applied world EQUALS data/*.json …` → `11_standing_route.sql — 5/5 PASS markers in 0.5 s`
(ROUTE_CLIENT_PATH, ROUTE_AFK_LAPS, ROUTE_BOOKS_BALANCE, ROUTE_DARK, ROUTE_0096_DOOR) → `PROOFS PASSED: 1
file(s), 5/5 PASS markers seen`.

**The verbatim self-assert receipt (0275):**

```
0275 self-assert ok: THE WEEK IS A KEY. The six bodies (pay_city, town_hall, close_lap, route_earnings,
standing_routes, the registry) reverse to their pre-images hunk by hunk, ACLs unmoved, every other function in
the four schemas unmoved (md5), exactly world.week_of / world.week_start / public.city_week_post /
world.city_history minted, the registry +1 (city_history, authenticated only), the two books server-only under
RLS, one writer each (pay_city alone, close_lap alone). The clock: week_of(anchor - 1 s) = -1, week_of(anchor)
= 0, week_of(anchor + 7 d - 1 s) = 0, and now() stands inside its own week. The city book through the real
doors: an Invest of 2000 lands one SHARE row under the current week, two gifts add to one DONATION row of 1500
with gifts 2, the Town Hall board serves the probe at those figures, the History read folds the current week
with them and an empty earlier one, and the events stream is untouched (the founding and the two verbs' own).
The lap book: three probe laps — two an hour apart before the boundary, one now — land as two week rows
(laps 2/1, nets 1,880/940 to the ducat), route_earnings reads week / last_week / laps_done 1 with laps_done_all
3, the served route book carries the same object, and deleting the route keeps the week rows while the lap rows
go. Rolled back.
```

**Gate-found defects, fixed before green** (the first apply attempts failed on these; each is recorded so the
class is not re-authored):
1. `to_jsonb('2026-10-26T00:00:00Z')` — parse-time `42804 … input has type unknown` (to_jsonb takes
   `anyelement`; an untyped string literal cannot feed it). The chain's own pattern is `::text`
   (0001's `world_secret`): `to_jsonb('2026-10-26T00:00:00Z'::text)`.
2. `world.city_history` had one extra closing paren at the investors tail (mismatched parentheses).
3. The registry hunk's pre-image was WRONG: the first draft anchored on 0144's preview_donate row, but the
   registry has been re-cut by many slices since (last: 0246's stats rows; the live tail ends at 0235's
   money_feed) — my earlier "no re-cuts after 0144" recon used greps that miss the hunks-table style. The
   self-assert's occurs-once check caught it (occurs 0 times). Re-anchored to the live tail.
4. `world.city_history`'s plpgsql variable `w` was ambiguous with the `generate_series(...) w` alias — renamed
   the variable to `v_w`.
5. The (c) probe asserted 3 events where the two gifts legitimately emit two DONATED — the verbs' own four
   (FOUNDED + INVESTED + 2×DONATED). The assert now pins exactly those, proving the book wrote none.

## Not proven (said plainly)

The deploy week's board starts empty — no backfill (the merchants' events are compacted, so a backfill would
show players and not merchants); by default the board simply starts. `laps_done_all` must be removed in a later
slice once the faces have moved off it. The two books grow by a few thousand rows a week and need no compaction
for years; no table is scanned at the boundary.
