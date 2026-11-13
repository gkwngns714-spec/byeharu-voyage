#!/usr/bin/env bash
# after-check.sh <start> <end> — THE 30-MINUTE AFTER-CHECK OF LIGHTING attack_enabled (migration 0375), READ-ONLY on prod.
#
# The seven lines of docs/COMBAT_LOG.md 3.6, each answered by a file that is one statement inside `begin transaction read only`:
#   a. ../raid/after-check.sh <start> <end>   line 6: THE ARRIVALS BEAT (avg <= 3 s, p95 < 5 s, no failed minute run), with the paired fight check of the raids of the window.
#                                              Its own FAIL for "no PIRATES day in the window" is not this light's: read the ARRIVALS BEATS lines.
#   b. after-battles.sql                       line 1: no battle FIGHTING past its clock + 2 minutes (`late` 0).
#                                              line 4: no fleet IN_BATTLE or busy after its battle closed (`stuck_in_battle`, `stuck_busy`, `stuck_navy` all 0).
#   c. after-rounds.sql                        line 2: every battle's battle_rounds equal to a re-run of its sheet (`rounds_differ`, `count_differs`, `result_differs` all 0).
#   d. after-loot.sql                          line 3: LOOT in the ledger = the battles' loot = the reports' loot; no company over loot_per_company_day (`over_day_cap` 0, `over_ship_cap` 0).
#   e. after-job.sql                           line 5: no failed run of byeharu-voyage:battles (`job_active` true, `failed` 0, `last_run` within 2 minutes).
#   f. after-held.sql                          line 7: a held voyage's settled days = its unheld days (`wrong_days`, `over_days`, `function_differs` all 0).
#   g. cargo-at-sea.sql                        what sails now: `unsafe.share` (the lighting guard's figure) must not have risen above 0.10.
#
# Run it at +30 minutes; b, c and d are worth reading by hand at +5 and +15 as well (each is one command, at the top of its file).
# PASS: (a)'s ARRIVALS BEATS hold; every WANTED-0 figure above is 0; d's three sums are equal; e's job ran every minute.
# With no battle in the window (nobody attacked yet) b, c, d and f answer 0 everywhere: that is a pass of nothing. Say so, and run it again after the first battles.
# A FAIL is the rollback: attack_enabled false (scripts/ops/harness/attacks/rollback-0375.sql as the next migration, or the owner's one line). Running battles finish; loot taken stays.
#
# Usage: after-check.sh '2026-11-14 03:10' '2026-11-14 03:40'      (UTC unless a zone is given)
set -u
if [ $# -ne 2 ]; then echo "usage: $0 <start> <end>   e.g. $0 '2026-11-14 03:10' '2026-11-14 03:40'" >&2; exit 64; fi
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="${BV_REPO:-$HOME/dev/byeharu-voyage}"
[ -d "$REPO/supabase" ] || { echo "REFUSING: $REPO is not the byeharu-voyage clone (set BV_REPO)" >&2; exit 66; }

RC=0
echo "== a. the arrivals beat (and the paired fight check of the window's raids) =="
bash "$HERE/../raid/after-check.sh" "$1" "$2" || echo "(a) did not end PASS: read its ARRIVALS BEATS lines; 'no PIRATES day in the window' alone is not a fail of this light"

for f in "$HERE/after-battles.sql" "$HERE/after-rounds.sql" "$HERE/after-loot.sql" "$HERE/after-job.sql" "$HERE/after-held.sql" "$HERE/cargo-at-sea.sql"; do
  echo
  echo "== $(basename "$f") =="
  node "$HERE/../read-only.mjs" "$f" || exit 3   # the one judge of "read only": first statement, last statement, no write verb
  WIN="$f"; command -v cygpath >/dev/null && WIN="$(cygpath -w "$f")"
  (cd "$REPO" && npx --yes supabase@2.120.0 db query --linked -f "$WIN") || RC=1
done
echo
[ $RC -eq 0 ] && echo "RAN: read the answers against the WANTED lines at the top of each file (every WANTED-0 figure 0, the three loot sums equal, the job active and run every minute)" || echo "FAIL: a step failed or did not answer"
exit $RC
