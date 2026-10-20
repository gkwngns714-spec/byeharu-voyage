# Deploying from a cloud session: 0214, 0215 and 0216, 2026-10-20

Three migrations went live this afternoon from a claude.ai cloud session, not from a PC. This is
what that took, what broke, and what the next person should know.

## Why the usual script cannot run there

`bv-deploy.sh` ends in `supabase db push`, which opens a Postgres connection. A cloud container
cannot: every outbound call goes through an HTTP proxy, and libpq does not speak one. Probed
directly — `pooler.supabase.com:6543`, `:5432` and `db.<ref>.supabase.co:5432` are all unreachable,
and **no allowlist entry fixes that**, because the problem is the protocol, not the destination.
Tunnelling raw TCP through the proxy is blocked by the sandbox, correctly.

What DOES work is the Supabase **Management API**: `POST /v1/projects/<ref>/database/query`. It
runs as `postgres`, can do DDL and can write `supabase_migrations.schema_migrations`. The agent
proxy supplies the credential, so **no `SUPABASE_ACCESS_TOKEN` is needed** — the hand-off note's
"one-time unblock" for that token can be struck.

`scripts/ops/bv-deploy-cloud.py` is the counterpart: same gates, HTTPS instead of psql.

## What broke, in order

**1. A fixed expectation of 8 clock jobs.** 0214 adds `byeharu-voyage:stats`, and since 0078 a job
lands INACTIVE with `wind_the_clock()` lighting it. The script read "9/8" and cried wolf. It now
reads `active == defined`, both from the database.

**2. 0215's registry hunk had gone stale.** It anchored on `('world','insurance','')` being the LAST
row of `client_rpc_entry_points()`. 0214 appended six `stats_*` rows after it that morning, so the
anchor occurred **0 times** in the live body and the self-assert would have refused the push. It was
re-sliced onto 0214's last row and verified read-only first: old anchor occurs 1, new text 0,
reverses to the pre-image.

> **The lesson.** A sliced hunk is only valid against the body it was cut from. Any migration that
> lands in between can displace it. Verify every hunk against the LIVE body immediately before a
> push, not during it. Before 0216 went out, all 14 of its hunks were checked this way; all held.

**3. A dropped HTTP call is not a rollback.** 0215's push returned `upstream request failed` — the
API gateway giving up on a long migration — and a single head read straight after still said 0214.
Read too early: the transaction was still committing, and 0215 landed seconds later. The script said
"NOT MERGING", so production went to 0215 while main stayed behind, and it had to be merged by hand.
It now polls the head for up to four minutes before calling a dropped push a failure.

**4. A merge made with a session token triggers no workflow.** GitHub suppresses that deliberately.
So the 0214 merge fired no Acceptance and — the one that bites — **no Pages deploy**: the server had
the Stats tab and the site did not, for 17 minutes. (`af8d00f`, the Korean merge, shows
`event=workflow_dispatch` for the same reason.) The script now dispatches `deploy-pages.yml` and
`acceptance.yml` after it merges. **Not** `migrations-apply-proof.yml` — a `workflow_dispatch` sets
`FROM_ZERO` there and rebuilds the world from scratch.

## After-check, all three (read-only on prod, 14:58 UTC)

| | |
|---|---|
| head | **0216** |
| clock | **9/9** active |
| probe leftovers | **0** |
| `sea_conditions_bite` | **false** — 0215/0216 are dark, as designed |
| stats rollup | 3 runs, 0 failed; 3 world rows, 714 city rows, newest 14:51 |

Arrivals pace, unchanged across all three pushes:

| window | n | avg s | max s |
|---|---|---|---|
| before 0214 | 140 | 3.32 | 7.78 |
| after 0214 | 135 | 3.37 | 10.13 |
| after 0215 | 65 | 3.15 | 8.37 |

**Cron failures: 3 of 232 arrivals runs, all inside a deploy window** — two `job canceled` (the
unwind killing a run mid-flight) and one `deadlock detected` on a `player` tuple moments after a
clock restart. There were **0 failures in the six hours before** the first push and none since.
Winding the clock back costs about one failed run per deploy; it is not a regression in any of the
three migrations. Worth watching if it ever becomes more than one.

## A test that aimed at a word, 2026-10-20 (row 172)

Worth keeping, because it cost three CI runs and the cause was not where it looked.

`tests/map.merchants.spec.ts` (`openHarbour`) and `tests/map.goto.spec.ts` (`openACity`) both opened a
harbour by pressing the **centre of its printed name**. For a long name that centre is open water
beside the mark, and `openHarbour`'s own header had carried the receipt since 2026-10-16 — a CI run
that opened `28.1°N 13.9°W · Open sea` off the Canaries while aiming for a city.

It only passed by **two accidents**:

1. A press on open water opened a tray. A tray is a `CHART_CHROME` box, and the label planner keeps
   names out of those (`useChromeBoxes`), so a missed aim **moved the word** and the next of the three
   aims landed somewhere new.
2. The open-sea panel carries the same `map-place-name` as a city, so `openACity`'s assertion passed
   on a panel that was reading a coordinate rather than a city at all.

Row 172 — a single press on open water opens nothing — removed both accidents, and three aims at one
patch of water became three misses. The first fix attempted (re-read the name's box before every aim)
could not work: the box had stopped moving, so a fresh read returned the same wrong point.

**The fix is to aim at the thing the player aims at.** Both helpers now press
`[data-port-mark][data-port-code=…]`, whose group is concentric about the harbour's own point, so the
box centre is what `hitTest.ts` resolves. The harbour is still *chosen* by its name; the word is the
fallback when no mark is on the glass.

**Left alone deliberately:** `tests/map.goto.spec.ts:304` still presses a label box centre for Lisbon.
"Lisbon" is short enough that its name centre falls inside the mark's 38 px reach, and the test is
green. Convert it to a mark aim the next time anyone is in that file.

**The general lesson:** when a drive helper passes because of what a *wrong* press happens to open, it
is not testing what it claims to. Aim at the element the player aims at.
