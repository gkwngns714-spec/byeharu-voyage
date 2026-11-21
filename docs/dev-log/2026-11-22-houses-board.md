# 2026-11-22: The houses' board (0467, proof 170)

The design: `docs/design/content-plan-2026-11.md` 5.3 item 5 and 5.6; `docs/design/playable-2026-11-22.md` P2.
Ships **dark** behind `houses_board_enabled` (false). Lighting it is the owner's.

## What a player sees, lit

Rank gets a first face, **Week** (KO 주간), before Captains and Countries. It ranks every merchant house and every company with a
login by **this week's profit**, and the player's own row always shows, in its place or under its own heading: "#37 of 874", the
profit, and "Next: Casa da Índia, 3,100 ahead". Test companies leave the Week board and the Captains board too. They stay in the database.
Dark, the read answers `{"on": false}`, the face is not offered, and Rank looks as it does today.

## Decided by default

- **The measure is profit this week:** `sum(earned - lost)` of `public.history_company_day` (0316) over the UTC week (Monday to
  Sunday, `public.history_bucket`). Both kinds already have it: the history job adds a company's and a merchant's ledger rows to it
  every run. It is cash in less cash out, so a cargo bought on Sunday and sold on Monday counts as a loss in one week and a gain in the next.
- **A test company is a company with no login:** a `players` row (not `is_npc`) whose `auth_uid` has no `auth.users` row.
  Production, read 2026-11-21 (`scripts/ops/harness/houses-board/before-0467.sql`): 19 companies, all with an `auth_uid`. 5 have a login.
  14 have none: 10 carry a probe's `00000000-` id and 4 carry an id no login matches. So "auth_uid is null" would catch none of them,
  and only the `auth.users` lookup tells them apart.
- **No new cron.** `public.houses_week_settle` runs at the end of each `byeharu-voyage:history` run (12, 27, 42, 57), right after
  that run adds the ledger. No read pays for the count, and the read itself writes nothing (it is `stable`).
- **The week is a key, not a wipe.** `houses_week` keeps this week and the last. Older weeks are deleted on each run.
- **Board size** reuses `standings_board_size` (10): one knob for how many rows a Rank board shows.
- **Rows show another house's weekly profit.** 0025 refused to serve another company's purse. A week's profit is a deed, like fame,
  and the merchants' daily profit is already public on Stats. The owner may reverse this.
- **The local world:** PGlite has no `auth.users`, so 0467 adds a one-column shim holding the local sign-in (`LOCAL_AUTH_UID`).
  This only happens where the table is absent, which is never on Supabase, the same way 0001 shims `auth.uid()`.

## Load (DATABASE_BUDGET)

- **Dark: 0 extra rows a minute.** The settle returns null before it reads anything. The read answers from one config key.
- **Lit:** about 1,750 rows in `houses_week` (2 weeks × ~874 houses). Each run rewrites only the rows whose figure moved. The
  merchants trade all day, so expect about 800 updates a run, 4 runs an hour: **about 55 extra row versions a minute**. That is on a
  1,750-row table with no index beside its key, so most updates are HOT. No new cron, job, index or fillfactor.
- **Settle cost:** about 1,750 primary-key ranges of `history_company_day` (about 7 rows each) per run. Local PGlite, 849 houses: 5 ms.
- **Read cost:** on each Rank open, and on the world's beat while Rank is open, `world.houses_week` reads at most ~874 rows of one
  tiny table plus 11 primary-key lookups. No function is called per row.
- `history_company_day` **is filled on production** (the content plan had not checked this): 14,915 rows from 2026-08-23 to
  2026-11-21, about 900 a day, mark at 2026-11-21 19:17. No company has earned anything this week (0 rows since 2026-11-16).

## Proof

- 0467's self-assert, on rolled-back probes: every hunk occurs once and reverses; no other function moved; the grants of the
  hunked functions are unmoved; the registry holds the read for `authenticated` only. Dark, the settle writes nothing and Captains
  keeps the test company. Lit, the merchant is on the Week board and the test company is on neither board. In PGlite, a company with
  a login is on both.
- Proof 170 (`node scripts/db/proof.mjs 170_`: 6/6 PASS, local): HB_DARK, HB_BOARD (competition ranking, ties, the company flag),
  HB_YOU ("#3 (tied) of 849", next house and gap), HB_TEST_OFF, HB_WEEKS (last week kept, older week deleted, a house gone from the
  roster removed), HB_JOB (the history job's run settles it).

## Rollback

- Quick: set `houses_board_enabled` back to false.
- Full: a new migration that reverses the five hunks, then drops `world.houses_week`, `public.houses_week_settle` and
  `public.houses_week`, and deletes the knob.

## Not done

- The week's top three as a line in the News (the design's pitch).
- A "last week" view in the client: the server keeps last week's rows, but the client does not show them.
