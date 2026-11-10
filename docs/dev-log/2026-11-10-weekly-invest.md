# 2026-11-10 — owner row 173 (weekly reset of city investment and lap records): already live, no new build

## The brief
Build owner row 173 (2026-10-20): *"The investment in city, Lap records should be reset every week. There will be a
history tab where you can see the last week's investment records when pressing a city."* Planned as migration 0345,
dark behind a new switch.

## What the chain already holds
- **0275** (#391, 2026-10-29) built row 173 exactly: the week is a KEY (`world.week_of`), two append-only books
  (`city_week_book`, `route_week_laps`), the Town Hall board and route lap counters read this week, and the City
  page gained the History tab (`world.city_history`, `src/live/CityHistory.tsx`). Nothing deleted; no cron.
- **0278** (#395, 2026-10-30): the OWNER rewrote it — *"money stays; only the ranking and the name reset"*. The key
  became the calendar month (`world.month_of`, `month_anchor` 2026-10-01), the books were renamed
  (`city_month_book`, `route_month_laps`), and the money became all-time: the Town Hall investors board and the route
  `total` sum every month. The History tab folds months (current + past 8).
- **0301** (2026-11-02): owner *"route lap history - we actually don't need this. 100 would be good"* —
  `standing_route_lap_keep` 200 → 100.
- Row 173's state cell was never updated after 0275/0278; it still read "OPEN — not started". That stale cell is what
  produced this brief.

## Prod before-check (read-only, 2026-11-10 11:50 UTC)
One file, `begin transaction read only; select …; rollback;`, catalogs and plain tables only (no function called):
- prod head `20260818000344`;
- functions present: `world.month_of:s`, `world.month_start:s`, `world.city_history:s`, `public.city_month_post:v`;
  `week_of` / `week_start` / `city_week_post` absent;
- tables: `city_month_book`, `route_month_laps` (the week books are gone, renamed);
- `city_month_book`: 6,474 rows — month 0 (Oct) 2,056, month 1 (Nov) 4,418;
- `route_month_laps`: 1,679 rows — month 0 823, month 1 856;
- knobs: `month_anchor` 2026-10-01T00:00:00Z, `standing_route_lap_keep` 100, `town_hall_investors_max` 50;
- `standing_route_laps`: 86,412 rows.

## Decided by default
- **No migration 0345, no switch.** A weekly reset would reverse the owner's own later decision (10-30: monthly
  history, all-time money). The rollover-with-history the row asks for is live; only its period and the board's
  "reset" were changed, by the owner.
- Row 173's state is corrected to say so. If the owner wants the WEEK back, the build is small and has a template:
  re-key the two books (a third book, or a `period` column) and re-cut `city_history` / `town_hall` — the 0278
  pattern in reverse, dark behind a switch.

## Open question for the owner (not acted on)
"Only the ranking resets" could mean the Town Hall ranking should reset each month while shares/influence stay;
0278 read it as an all-time board. Live play follows 0278. Not changed here.
