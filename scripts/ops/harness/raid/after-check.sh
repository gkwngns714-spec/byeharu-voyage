#!/usr/bin/env bash
# after-check.sh <start> <end> — THE PAIRED AFTER-CHECK for a re-light of the fight (0204), READ-ONLY on prod.
#
# Why paired: a 30-minute window against the 30 minutes before it passes a CORRECT engine only ~52–67 % of the time
# at 16–19 raids a window (docs/dev-log/2026-10-18-auto-fight.md, "0202 — the raid balance"). This compares every
# PIRATES day resolved inside [start, end) — its recorded (lit) outcome and crew loss — against DESIGN B.6's dark
# ratio table recomputed on that SAME raid (the fleet's class-figure escort, the day's own raider strength). That
# is paired.sql, parameterised.
#
# Prints: the paired lost share and crew loss, lit vs the dark table on the same raids; the arrivals sweep's avg and
# p95 (cron job byeharu-voyage:arrivals) with their bounds; the reconcile runs' durations; E_ENDURANCE refusals and
# REPAIR orders in the window; and whether every PIRATES day carries `rounds`. Ends with one PASS / FAIL line.
#
# Bounds (a FAIL is a rollback — 0201's file, renumbered):
#   paired lost (PLUNDERED + STRIPPED) share  <= dark table's on the same raids + 5 points
#   paired crew lost per raid                 <= dark table's on the same raids + 1 point
#   arrivals avg <= 3 s, arrivals p95 < 5 s
#   every PIRATES day in the window carries `rounds` (a day without one was not fought: the switch is not on)
#   at least one PIRATES day in the window (else nothing was measured — widen the window)
#
# Usage: after-check.sh '2026-10-18 20:50' '2026-10-18 21:20'      (UTC unless a zone is given)
# It runs `supabase db query --linked` from the byeharu-voyage clone (BV_REPO overrides), inside
# `begin transaction read only` — nothing here can write.
set -u

if [ $# -ne 2 ]; then echo "usage: $0 <start> <end>   e.g. $0 '2026-10-18 20:50' '2026-10-18 21:20'" >&2; exit 64; fi
TS_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}(:[0-9]{2})?(Z|[+-][0-9]{2}(:?[0-9]{2})?)?$'
for t in "$1" "$2"; do
  [[ "$t" =~ $TS_RE ]] || { echo "REFUSING: '$t' is not a timestamp like '2026-10-18 20:50' (optional :ss and zone)" >&2; exit 64; }
done
zone() { case "$1" in *Z|*+[0-9][0-9]|*+[0-9][0-9]:[0-9][0-9]|*+[0-9][0-9][0-9][0-9]|*-[0-9][0-9]:[0-9][0-9]) echo "$1";; *) echo "$1+00";; esac; }
A="$(zone "$1")"; B="$(zone "$2")"
REPO="${BV_REPO:-$HOME/dev/byeharu-voyage}"
[ -d "$REPO/supabase" ] || { echo "REFUSING: $REPO is not the byeharu-voyage clone (set BV_REPO)" >&2; exit 66; }
command -v node >/dev/null || { echo "REFUSING: node is needed to read the query's JSON" >&2; exit 69; }

SQL="$(mktemp -t after-check-XXXXXX.sql)"
trap 'rm -f "$SQL"' EXIT
cat > "$SQL" <<EOF
begin transaction read only;
with w as (select timestamptz '$A' a, timestamptz '$B' b),
-- ── the raids of the window, paired: each day's recorded outcome against the dark table on the SAME raid ──
d as (
  select ve.payload p, v.fleet_id, ve.resolved_at,
         (select coalesce(sum(c.guns + sh.crew * 0.02 + c.tier * 3), 0) from public.ships sh join public.ship_classes c on c.id = sh.class_id
           where sh.fleet_id = v.fleet_id) as esc_dark
    from public.voyage_events ve join public.voyages v on v.id = ve.voyage_id, w
   where ve.kind = 'PIRATES' and ve.resolved_at >= w.a and ve.resolved_at < w.b),
t as (
  select d.*, (d.p->>'raider')::numeric r,
         case when (d.p->>'raider')::numeric <= 0 then 'EVADED'
              when d.esc_dark / (d.p->>'raider')::numeric >= 2.0 then 'EVADED'
              when d.esc_dark / (d.p->>'raider')::numeric >= 1.2 then 'DRIVEN_OFF'
              when d.esc_dark / (d.p->>'raider')::numeric >= 0.7 then 'RANSOM'
              when d.esc_dark / (d.p->>'raider')::numeric >= 0.3 then 'PLUNDERED' else 'STRIPPED' end as table_outcome
    from d),
paired as (
  select json_build_object(
    'n', count(*),
    'with_rounds', count(*) filter (where p ? 'rounds'),
    'without_rounds', count(*) filter (where not p ? 'rounds'),
    'lost_pct', round(100.0 * count(*) filter (where p->>'outcome' in ('PLUNDERED', 'STRIPPED')) / nullif(count(*), 0), 1),
    'lost_pct_table', round(100.0 * count(*) filter (where table_outcome in ('PLUNDERED', 'STRIPPED')) / nullif(count(*), 0), 1),
    'stripped', count(*) filter (where p->>'outcome' = 'STRIPPED'),
    'stripped_table', count(*) filter (where table_outcome = 'STRIPPED'),
    'won_pct', round(100.0 * count(*) filter (where p->>'outcome' in ('EVADED', 'DRIVEN_OFF')) / nullif(count(*), 0), 1),
    'won_pct_table', round(100.0 * count(*) filter (where table_outcome in ('EVADED', 'DRIVEN_OFF')) / nullif(count(*), 0), 1),
    'crew_pct', round(100.0 * avg((p->>'crew_lost')::numeric / nullif((p->>'crew_before')::numeric, 0)), 2),
    'crew_pct_table', round(100.0 * avg((select sum(sh.crew - floor(sh.crew * (1 - case table_outcome when 'DRIVEN_OFF' then 0.02 when 'PLUNDERED' then 0.10
                                                                                     when 'STRIPPED' then 0.30 else 0 end)))
                                           from public.ships sh where sh.fleet_id = t.fleet_id) / nullif((select sum(sh.crew) from public.ships sh where sh.fleet_id = t.fleet_id), 0)), 2),
    'outcomes', (select json_object_agg(o, n) from (select p->>'outcome' o, count(*) n from t group by 1) z),
    'outcomes_table', (select json_object_agg(o, n) from (select table_outcome o, count(*) n from t group by 1) z)) j
    from t),
-- ── the sweeps ──
runs as (
  select j.jobname, d.status, d.start_time, extract(epoch from d.end_time - d.start_time) s, d.return_message
    from cron.job j join cron.job_run_details d on d.jobid = j.jobid, w
   where j.jobname in ('byeharu-voyage:arrivals', 'byeharu-voyage:reconcile') and d.start_time >= w.a and d.start_time < w.b),
arr as (
  select json_build_object('n', count(*), 'avg', round(avg(s)::numeric, 2),
           'p95', round((percentile_cont(0.95) within group (order by s))::numeric, 2), 'max', round(max(s)::numeric, 2),
           'failed', count(*) filter (where status <> 'succeeded'),
           'failed_msgs', (select json_agg(distinct return_message) from runs r2 where r2.jobname = 'byeharu-voyage:arrivals' and r2.status <> 'succeeded')) j
    from runs where jobname = 'byeharu-voyage:arrivals'),
rec as (
  select json_build_object('n', count(*), 'avg', round(avg(s)::numeric, 2), 'max', round(max(s)::numeric, 2),
           'failed', count(*) filter (where status <> 'succeeded'),
           'runs', (select json_agg(json_build_object('at', to_char(start_time at time zone 'UTC', 'HH24:MI:SS'), 's', round(s::numeric, 2), 'status', status) order by start_time)
                      from runs r2 where r2.jobname = 'byeharu-voyage:reconcile')) j
    from runs where jobname = 'byeharu-voyage:reconcile'),
-- ── the queue ──
ord as (
  select json_build_object(
    'e_endurance', (select count(*) from public.orders o, w where o.error_code = 'E_ENDURANCE' and o.executed_at >= w.a and o.executed_at < w.b),
    'e_endurance_fleets', (select count(distinct o.fleet_id) from public.orders o, w where o.error_code = 'E_ENDURANCE' and o.executed_at >= w.a and o.executed_at < w.b),
    'refused_orders', (select count(*) from public.orders o, w where o.error_code is not null and o.executed_at >= w.a and o.executed_at < w.b),
    'repair_issued', (select count(*) from public.orders o, w where o.verb = 'REPAIR' and o.issued_at >= w.a and o.issued_at < w.b),
    'repair_done', (select count(*) from public.orders o, w where o.verb = 'REPAIR' and o.status = 'done' and o.executed_at >= w.a and o.executed_at < w.b)) j)
select json_build_object(
  'window', json_build_object('a', (select a from w), 'b', (select b from w), 'read_at', now()),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'switches', (select json_object_agg(key, value) from public.world_config where key in ('combat_bite', 'armour_turns_pct')),
  'paired', (select j from paired), 'arrivals', (select j from arr), 'reconcile', (select j from rec), 'orders', (select j from ord));
rollback;
EOF

head -c 40 "$SQL" | grep -qi "begin transaction read only" || { echo "REFUSING: the query is not read only"; exit 3; }
WIN="$SQL"; command -v cygpath >/dev/null && WIN="$(cygpath -w "$SQL")"
OUT="$(cd "$REPO" && npx --yes supabase@2.120.0 db query --linked --output-format json -f "$WIN" 2>&1)"
RC=$?

printf '%s' "$OUT" | node -e '
let s = ""; process.stdin.on("data", d => s += d).on("end", () => {
  const i = s.indexOf("{"), k = s.lastIndexOf("}");
  let j = null; try { j = JSON.parse(s.slice(i, k + 1)); } catch (e) {}
  if (!j || j._tag === "Error" || !j.rows || !j.rows[0]) { console.log(s.trim()); console.log("FAIL: the read-only query did not answer (exit " + process.argv[1] + ")"); process.exit(2); }
  const r = j.rows[0].json_build_object, P = r.paired, A = r.arrivals, R = r.reconcile, O = r.orders;
  const f = (x, d = 2) => x == null ? "n/a" : Number(x).toFixed(d);
  const fails = [];
  console.log("PAIRED AFTER-CHECK  window " + r.window.a + " -> " + r.window.b + "  (read " + r.window.read_at + ", prod head " + r.head + ", combat_bite " + JSON.stringify(r.switches.combat_bite) + ", armour_turns_pct " + JSON.stringify(r.switches.armour_turns_pct) + ")");
  console.log("");
  console.log("RAIDS, PAIRED (each PIRATES day vs DESIGN B.6 dark table on the SAME raid): n = " + P.n);
  if (P.n === 0) { fails.push("no PIRATES day resolved inside the window: nothing measured — widen the window"); }
  else {
    const lostOk = Number(P.lost_pct) <= Number(P.lost_pct_table) + 5;
    const crewOk = P.crew_pct_table == null ? false : Number(P.crew_pct) <= Number(P.crew_pct_table) + 1;
    console.log("  lost share (PLUNDERED+STRIPPED)  lit " + f(P.lost_pct, 1) + " %   dark table " + f(P.lost_pct_table, 1) + " %   bound <= table + 5  -> " + (lostOk ? "holds" : "BROKEN"));
    console.log("  crew lost per raid               lit " + f(P.crew_pct) + " %   dark table " + f(P.crew_pct_table) + " %   bound <= table + 1  -> " + (crewOk ? "holds" : "BROKEN"));
    console.log("  won share (EVADED+DRIVEN_OFF)    lit " + f(P.won_pct, 1) + " %   dark table " + f(P.won_pct_table, 1) + " %");
    console.log("  STRIPPED                         lit " + P.stripped + "   dark table " + P.stripped_table);
    console.log("  outcomes lit " + JSON.stringify(P.outcomes) + "   table " + JSON.stringify(P.outcomes_table));
    console.log("  rounds: " + P.with_rounds + " of " + P.n + " day(s) carry rounds" + (P.without_rounds > 0 ? "   " + P.without_rounds + " WITHOUT -> BROKEN" : "   -> holds"));
    if (!lostOk) fails.push("paired lost share " + f(P.lost_pct, 1) + " % > dark table " + f(P.lost_pct_table, 1) + " % + 5");
    if (!crewOk) fails.push("paired crew lost " + f(P.crew_pct) + " % > dark table " + f(P.crew_pct_table) + " % + 1");
    if (P.without_rounds > 0) fails.push(P.without_rounds + " PIRATES day(s) in the window carry no rounds");
  }
  console.log("");
  console.log("ARRIVALS SWEEP (cron byeharu-voyage:arrivals, runs started in the window): n = " + A.n);
  if (A.n === 0) { fails.push("no arrivals run in the window"); console.log("  none"); }
  else {
    const avgOk = Number(A.avg) <= 3, p95Ok = Number(A.p95) < 5;
    console.log("  avg " + f(A.avg) + " s   bound <= 3 s -> " + (avgOk ? "holds" : "BROKEN"));
    console.log("  p95 " + f(A.p95) + " s   bound <  5 s -> " + (p95Ok ? "holds" : "BROKEN"));
    console.log("  max " + f(A.max) + " s   failed runs " + A.failed + (A.failed > 0 ? " " + JSON.stringify(A.failed_msgs) : "") + "   (printed, not bounded)");
    if (!avgOk) fails.push("arrivals avg " + f(A.avg) + " s > 3 s");
    if (!p95Ok) fails.push("arrivals p95 " + f(A.p95) + " s >= 5 s");
  }
  console.log("");
  console.log("RECONCILE (cron byeharu-voyage:reconcile, :07 hourly): n = " + R.n + (R.n ? "   avg " + f(R.avg) + " s   max " + f(R.max) + " s   failed " + R.failed : ""));
  for (const x of (R.runs || [])) console.log("  " + x.at + " UTC  " + f(x.s) + " s  " + x.status);
  console.log("");
  console.log("QUEUE: E_ENDURANCE refusals " + O.e_endurance + " (" + O.e_endurance_fleets + " fleet(s)) of " + O.refused_orders + " refused order(s) answered in the window; REPAIR orders issued " + O.repair_issued + ", done " + O.repair_done);
  console.log("");
  console.log(fails.length ? "FAIL: " + fails.join("; ") : "PASS: paired lost and crew within the dark table + 5 / + 1 on the same raids; arrivals avg <= 3 s and p95 < 5 s; every PIRATES day fought in rounds");
  process.exit(fails.length ? 1 : 0);
});' "$RC"
