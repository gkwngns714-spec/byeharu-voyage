#!/usr/bin/env bash
# THE GAME'S HEALTH, in one read-only pass (2026-11-01, after the Stats-count outage and the every-minute-market overload).
# Run it at the START of every session and after EVERY deploy. Pure SELECTs through `supabase db query --linked`; nothing is written.
# It prints the numbers, then ALERT lines for each threshold that trips — thresholds are the ones that would have caught the 10-30 → 11-01 incident
# hours or days earlier. Usage: bash scripts/ops/health.sh
export PATH="$HOME/tools/supabase:$PATH"
# `supabase db query --linked` needs the project link (supabase/.temp): a fresh worktree has none, so go where it is.
if [ ! -d supabase/.temp ]; then for d in "$HOME/dev/byeharu-voyage" "$HOME/byeharu-voyage"; do [ -d "$d/supabase/.temp" ] && { cd "$d" || exit 1; break; }; done; fi
# A check that could not run is NOT a clean bill: every failed query is written here and the last line says so (2026-11-02: a run from a worktree
# printed "no thresholds tripped" over eight "(query failed)" lines).
FAILS=$(mktemp); trap 'rm -f "$FAILS"' EXIT
Q() { local out n; for n in 1 2; do out=$(timeout 120 supabase db query --linked --output-format json "$1" 2>/dev/null); case "$out" in *'"rows"'*) printf '%s' "$out"; return 0 ;; esac; sleep 2; done; echo x >> "$FAILS"; printf '%s' "$out"; }
rows() { node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const j=JSON.parse(s.slice(s.indexOf("{")));for(const r of j.rows)console.log("  "+Object.entries(r).map(([k,v])=>k+"="+(v&&typeof v==="object"?JSON.stringify(v):v)).join("  "))}catch(e){console.log("  (query failed)")}})'; }
val() { node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const j=JSON.parse(s.slice(s.indexOf("{")));console.log(j.rows[0]["'"$1"'"])}catch(e){console.log("")}})'; }
ALERTS=0; alert() { echo "ALERT: $1"; ALERTS=$((ALERTS+1)); }

echo "== head / clock / restart"
Q "select (select max(version) from supabase_migrations.schema_migrations) as head, now() as utc, to_char(pg_postmaster_start_time(),'MM-DD HH24:MI') as started, round(extract(epoch from now()-pg_postmaster_start_time())/3600,1) as up_hours" | rows
UP=$(Q "select round(extract(epoch from now()-pg_postmaster_start_time())/3600,1) as v" | val v)
[ -n "$UP" ] && awk "BEGIN{exit !($UP < 6)}" && alert "the database restarted ${UP} h ago (an outage or a crash: caches are cold; check cron gaps)"

echo "== cron: last 2 h per job (runs, failed, avg s, max s)"
Q "select j.jobname, count(*) as runs, count(*) filter (where d.status='failed') as failed, round(avg(extract(epoch from d.end_time-d.start_time))::numeric,1) as avg_s, round(max(extract(epoch from d.end_time-d.start_time))::numeric,1) as max_s from cron.job_run_details d join cron.job j using(jobid) where d.start_time > now() - interval '2 hours' and d.end_time is not null group by 1 order by 1" | rows
BAD=$(Q "select string_agg(j.jobname || ' ' || round(100.0*count(*) filter (where d.status='failed')/count(*))::text || '% failed', '; ') as v from (select 1) x, cron.job_run_details d join cron.job j using(jobid) where d.start_time > now() - interval '2 hours' and d.end_time is not null group by j.jobname having count(*) filter (where d.status='failed') * 5 > count(*)" | val v)
[ -n "$BAD" ] && [ "$BAD" != "null" ] && alert "cron jobs failing more than 20% over 2 h: $BAD"

echo "== cron: last 15 min per job (what it is like NOW)"
Q "select j.jobname, count(*) as runs, count(*) filter (where d.status='failed') as failed, round(avg(extract(epoch from d.end_time-d.start_time))::numeric,1) as avg_s, round(max(extract(epoch from d.end_time-d.start_time))::numeric,1) as max_s from cron.job_run_details d join cron.job j using(jobid) where d.start_time > now() - interval '15 minutes' and d.end_time is not null group by 1 order by 1" | rows

echo "== the Stats count (every 15 min): freshness and the journal"
Q "select to_char(max(at),'MM-DD HH24:MI') as newest_count, round(extract(epoch from now()-max(at))/60) as age_min from public.stats_world" | rows
AGE=$(Q "select round(extract(epoch from now()-max(at))/60) as v from public.stats_world" | val v)
[ -n "$AGE" ] && awk "BEGIN{exit !($AGE > 45)}" && alert "the Stats count is ${AGE} min old (it runs every 15): it is failing or stopped — read the last stats cron runs and public.stats_runs"
Q "select count(*) as journal_rows_up_to_1m from (select 1 from public.stats_live_deltas limit 1000000) x" | rows
J=$(Q "select count(*) as v from (select 1 from public.stats_live_deltas limit 1000000) x" | val v)
[ -n "$J" ] && [ "$J" -gt 300000 ] && alert "the stats journal holds ${J}+ rows (> 300,000): world.stats_now() sums all of it on every call"

echo "== the tables that matter (size, visibility map, dead rows, last autovacuum)"
Q "select c.relname, pg_size_pretty(pg_total_relation_size(c.oid)) as total, round(100.0*c.relallvisible/nullif(c.relpages,0),1) as pct_allvisible, s.n_dead_tup as dead, to_char(s.last_autovacuum,'MM-DD HH24:MI') as last_vac, round(100.0*s.n_tup_hot_upd/nullif(s.n_tup_upd,0)) as hot_pct from pg_class c join pg_stat_user_tables s on s.relid=c.oid where c.relnamespace='public'::regnamespace and c.relkind='r' and pg_total_relation_size(c.oid) > 100*1024*1024 order by pg_total_relation_size(c.oid) desc" | rows
# port_goods is the one table the every-minute market rewrites in full: its map is cleared by design (nothing is lost: its updates are 100 % HOT and the next check reports that)
L=$(Q "select string_agg(c.relname || ' ' || round(100.0*c.relallvisible/nullif(c.relpages,0))::text || '% mapped', '; ') as v from pg_class c where c.relnamespace='public'::regnamespace and c.relkind='r' and c.relname <> 'port_goods' and c.relpages > 12000 and 100.0*c.relallvisible/nullif(c.relpages,0) < 90" | val v)
[ -n "$L" ] && [ "$L" != "null" ] && alert "big tables with a stale visibility map (< 90% all-visible; index-only scans become heap fetches): $L"
L=$(Q "select string_agg(c.relname || ' ' || s.n_dead_tup::text || ' dead of ~' || c.reltuples::bigint::text, '; ') as v from pg_class c join pg_stat_user_tables s on s.relid=c.oid where c.relnamespace='public'::regnamespace and c.relkind='r' and c.relname <> 'port_goods' and c.reltuples > 20000 and s.n_dead_tup > 1.0*c.reltuples" | val v)
[ -n "$L" ] && [ "$L" != "null" ] && alert "tables with more dead rows than live ones (bloat): $L"
PGB=$(Q "select (pg_total_relation_size('public.port_goods')/1048576)::int as v" | val v)
[ -n "$PGB" ] && [ "$PGB" != "null" ] && [ "$PGB" -gt 250 ] && alert "port_goods is ${PGB} MB (0292 rewrote it to ~120 MB; before it was 307 MB): bloat is back — in-page updates are failing or autovacuum is blocked; it needs the rewrite again"

echo "== write load: WAL over a 30 s window, port_goods HOT share, and the heaviest statements (since restart)"
R() { Q "select extract(epoch from now()) as t, wal_bytes::numeric as w, wal_fpi as f, (select n_tup_upd from pg_stat_user_tables where relid='public.port_goods'::regclass) as u, (select n_tup_hot_upd from pg_stat_user_tables where relid='public.port_goods'::regclass) as h from pg_stat_wal" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const r=JSON.parse(s.slice(s.indexOf("{"))).rows[0];console.log([r.t,r.w,r.f,r.u,r.h].join(" "))}catch(e){console.log("")}})'; }
WA=$(R); sleep 30; WB=$(R)
WRATE=$(node -e 'const a=process.argv[1].split(" ").map(Number),b=process.argv[2].split(" ").map(Number);if(a.length<5||b.length<5||isNaN(a[0])||isNaN(b[0])){console.log("");process.exit(0)}const m=(b[0]-a[0])/60;console.log(((b[1]-a[1])/1048576/m).toFixed(1)+" "+Math.round((b[2]-a[2])/m)+" "+(b[3]-a[3]>0?(100*(b[4]-a[4])/(b[3]-a[3])).toFixed(0):"-"))' "$WA" "$WB")
set -- $WRATE; echo "  wal_mb_per_min=${1:-?}  fpi_per_min=${2:-?}  port_goods_hot_pct=${3:-?}   (baseline after the 0292 rewrite: ~47 MB/min, 100 % HOT; the every-minute market itself is ~30 MB/min of it)"
[ -n "$1" ] && awk "BEGIN{exit !($1 > 70)}" && alert "WAL is ${1} MB/min (> 70, the post-0292 baseline is ~47): the write path is saturating the disk — check the minute jobs and what else started writing"
[ -n "$3" ] && [ "$3" != "-" ] && [ "$3" -lt 80 ] && alert "port_goods updates are only ${3} % HOT (the rewrite's fillfactor 30 should give ~100 %): a long snapshot is pinning dead versions, or the table needs the rewrite again"
Q "select calls, round(mean_exec_time) as mean_ms, round(total_exec_time/1000) as total_s, shared_blks_dirtied as dirtied, left(regexp_replace(query,'s+',' ','g'),70) as q from pg_stat_statements order by total_exec_time desc limit 5" | rows

echo "== what a player waits for (timed through the CLI; baseline select 1 first)"
t() { local a=$(date +%s%N); timeout 120 supabase db query --linked "$2" >/dev/null 2>&1 || { sleep 2; a=$(date +%s%N); timeout 120 supabase db query --linked "$2" >/dev/null 2>&1 || echo x >> "$FAILS"; }; local b=$(date +%s%N); awk "BEGIN{printf \"  %-28s %6.1f s\n\", \"$1\", ($b-$a)/1e9}"; }
t "baseline select 1" "select 1"
t "world.stats_now()" "select world.stats_now() ->> 'at'"
t "world.sea_roster(1 day)" "select length(world.sea_roster(now() - interval '1 day')::text)"

echo
NF=$(wc -l < "$FAILS" | tr -d ' ')
if [ "$NF" -gt 0 ]; then echo "HEALTH: UNKNOWN - $NF query(ies) failed above, so this is NOT a clean bill (is supabase linked? is the network up?)."; exit 2
elif [ "$ALERTS" -eq 0 ]; then echo "HEALTH: no thresholds tripped."
else echo "HEALTH: $ALERTS alert(s) above."; exit 1; fi
