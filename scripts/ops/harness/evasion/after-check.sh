#!/usr/bin/env bash
# after-check.sh <start> <end> — THE 30-MINUTE AFTER-CHECK OF 0453 (a run is a chase; a fight change), READ-ONLY on prod.
#
#   a. ../db-health/gate.sql                  the beat, the database's size, the disk waits (gate_ok true)
#   b. check.sql                              the same read as BEFORE the deploy (its header says what is wanted after), judged here on the fail lines:
#                                               FAIL (each a rollback by the owner's knob chase_enabled false): the beat over 2,000 ms; a raid stuck FIGHTING;
#                                               a roll outside 1..50; of 30 or more runners none away, or more than 3 in 10.
#                                             and printed: head, applied, new (every count 1), cards_ev_1h, open_pct and rolls_pct medians, evasion_xp.
#   c. ../raid/after-check.sh <start> <end>   the arrivals beat and the jobs for the window (its "no PIRATES day" line alone is not a fail of this change:
#                                             0453 does not touch the voyage day's round engine).
#
# Usage: after-check.sh '2026-11-16 03:10' '2026-11-16 03:40'      (UTC unless a zone is given; the window starts at the deploy)
# On PC 디폴리스 the clone is ~/byeharu-voyage: BV_REPO=~/byeharu-voyage bash scripts/ops/harness/evasion/after-check.sh <start> <end>
set -u
if [ $# -ne 2 ]; then echo "usage: $0 <start> <end>   e.g. $0 '2026-11-16 03:10' '2026-11-16 03:40'" >&2; exit 64; fi
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="${BV_REPO:-$HOME/dev/byeharu-voyage}"
[ -d "$REPO/supabase" ] || { echo "REFUSING: $REPO is not the byeharu-voyage clone (set BV_REPO)" >&2; exit 66; }
OUT="$(mktemp)"
RC=0

for f in "$HERE/../db-health/gate.sql" "$HERE/check.sql"; do
  echo "== $(basename "$f") =="
  node "$HERE/../read-only.mjs" "$f" || exit 3   # the one judge of "read only": first statement, last statement, no write verb
  WIN="$f"; command -v cygpath >/dev/null && WIN="$(cygpath -w "$f")"
  (cd "$REPO" && npx --yes supabase@2.120.0 db query --linked --output-format json -f "$WIN") > "$OUT" || { echo "FAIL: $(basename "$f") did not answer"; RC=1; continue; }
  node -e '
    const raw = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")); const row = raw.rows[0]
    if (process.argv[2] === "gate.sql") { console.log(row.gate_line); if (!row.gate_ok) { console.log("FAIL: the gate is red: " + row.gate_why); process.exit(1) } process.exit(0) }
    const r = row.r, bad = []
    if ((r.beat?.mean_ms ?? 0) > 2000) bad.push("the beat " + r.beat.mean_ms + " ms")
    if (r.stuck > 0) bad.push(r.stuck + " raid(s) stuck FIGHTING")
    if (r.rolls_pct?.n > 0 && (r.rolls_pct.min < 1 || r.rolls_pct.max > 50)) bad.push("a roll outside 1..50: " + JSON.stringify(r.rolls_pct))
    const ran = r.raids_1h?.ran ?? 0, fled = r.raids_1h?.fled ?? 0
    if (ran >= 30 && (fled === 0 || fled / ran > 0.3)) bad.push(fled + " of " + ran + " runners away")
    if (!r.applied || Object.values(r.new ?? {}).some((n) => n !== 1)) bad.push("0453 is not in the live bodies: applied " + r.applied + ", new " + JSON.stringify(r.new))
    console.log("head " + r.head + "; chase " + JSON.stringify(r.chase) + "; cards with ev " + r.cards_ev_1h + " of " + r.tick_1h + " (newest without: " + r.no_ev_newest + ")")
    console.log("runners " + ran + ", away " + fled + "; open " + JSON.stringify(r.open_pct) + "; rolls " + JSON.stringify(r.rolls_pct) + "; span " + JSON.stringify(r.span_s) + "; evasion_xp " + JSON.stringify(r.evasion_xp))
    if (bad.length) { console.log("FAIL: " + bad.join("; ")); process.exit(1) }
  ' "$OUT" "$(basename "$f")" || RC=1
  echo
done
rm -f "$OUT"

echo "== c. the arrivals beat and the jobs (../raid/after-check.sh) =="
bash "$HERE/../raid/after-check.sh" "$1" "$2" || echo "(c) did not end PASS: read its ARRIVALS BEATS lines; 'no PIRATES day in the window' alone is not a fail of this change"
echo
[ $RC -eq 0 ] && echo "PASS: the gate green, 0453 in place, no fail line of check.sql (read (c)'s beat lines yourself)" || echo "FAIL: a fail line above; the rollback is chase_enabled false (the owner's knob)"
exit $RC
