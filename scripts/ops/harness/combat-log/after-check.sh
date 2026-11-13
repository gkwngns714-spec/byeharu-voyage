#!/usr/bin/env bash
# after-check.sh <start> <end> — THE 30-MINUTE AFTER-CHECK OF 0353 (the fight log, standing orders), READ-ONLY on prod.
#
# Run it twice (docs/COMBAT_LOG.md 5.1):
#   1. 30 minutes after the DEPLOY. The log is live at once and is display only: the fight must be the fight it was.
#   2. 30 minutes after raid_orders_enabled is LIT (its own step, owner's, reported the same hour).
#
# It runs, in order, each inside `begin transaction read only`:
#   a. ../raid/after-check.sh <start> <end>   the PAIRED fight check and the arrivals beat (avg <= 3 s, p95 < 5 s, no failed minute run).
#                                              Since 0353 a raid fought under Flee or Pay is left out of the pairing (her choice, not the engine's balance).
#   b. after.sql                               the 20 hunks each once, the 12 functions, the two doors registered, the table closed, the switch and the knobs.
#   c. ../two-sides/golden.sql                 the 1,080-fight digest of voyage.fight_resolve: it must be THE SAME TEXT as the one taken before the deploy.
#   d. after-lit.sql                           the window's company raid days: every fought day has a log, no ship of the world has one, the orders by kind,
#                                              and RANSOM in the ledger against what the Pay days say they paid.
#
# PASS (the deploy): (a) ends PASS; (b) every new_times 1, fns 12, client_fns 2, anon_fns 0, doors 2, order_rows false, switch false;
#                    (c) digest unchanged; (d) with_log = fought, world_with_log = 0, by_order FIGHT only.
# PASS (the light):  (a) ends PASS; (d) with_log = fought, world_with_log = 0, ransom_ledger = ransom_paid_sum + named_ransom_sum.
# A FAIL of (a) or (c) after the deploy is the forward rollback of the whole slice (rollback-0353.sql, as a new migration, owner only).
# A FAIL after the light is raid_orders_enabled false (a new migration): every frozen order is ignored at once and the door refuses.
#
# Usage: after-check.sh '2026-11-12 03:10' '2026-11-12 03:40'      (UTC unless a zone is given)
set -u
if [ $# -ne 2 ]; then echo "usage: $0 <start> <end>   e.g. $0 '2026-11-12 03:10' '2026-11-12 03:40'" >&2; exit 64; fi
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="${BV_REPO:-$HOME/dev/byeharu-voyage}"
[ -d "$REPO/supabase" ] || { echo "REFUSING: $REPO is not the byeharu-voyage clone (set BV_REPO)" >&2; exit 66; }

RC=0
echo "== a. the paired fight check and the arrivals beat =="
bash "$HERE/../raid/after-check.sh" "$1" "$2" || RC=1

for f in "$HERE/after.sql" "$HERE/../two-sides/golden.sql" "$HERE/after-lit.sql"; do
  echo
  echo "== $(basename "$f") =="
  node "$HERE/../read-only.mjs" "$f" || exit 3   # the one judge of "read only": first statement, last statement, no write verb
  WIN="$f"; command -v cygpath >/dev/null && WIN="$(cygpath -w "$f")"
  (cd "$REPO" && npx --yes supabase@2.120.0 db query --linked -f "$WIN") || RC=1
done
echo
[ $RC -eq 0 ] && echo "RAN: read the four answers against the PASS lines at the top of this file" || echo "FAIL: a step failed or did not answer"
exit $RC
