#!/usr/bin/env bash
# THE GAME'S HEALTH, in one read-only pass (2026-11-01, after the Stats-count outage and the every-minute-market overload).
# Run it at the START of every session and after EVERY deploy. Pure SELECTs through `supabase db query --linked`; nothing is written.
# It prints the numbers, then ALERT lines for each threshold that trips — thresholds are the ones that would have caught the 10-30 → 11-01 incident
# hours or days earlier. Usage: bash scripts/ops/health.sh
export PATH="$HOME/tools/supabase:$PATH"
Q() { timeout 120 supabase db query --linked --output-format json "$1" 2>/dev/null; }
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

echo "== the Stats count (every 15 min): freshness and the journal"
Q "select to_char(max(at),'MM-DD HH24:MI') as newest_count, round(extract(epoch from now()-max(at))/60) as age_min from public.stats_world" | rows
AGE=$(Q "select round(extract(epoch from now()-max(at))/60) as v from public.stats_world" | val v)
[ -n "$AGE" ] && awk "BEGIN{exit !($AGE > 45)}" && alert "the Stats count is ${AGE} min old (it runs every 15): it is failing or stopped — read the last stats cron runs and public.stats_runs"
Q "select count(*) as journal_rows_up_to_1m from (select 1 from public.stats_live_deltas limit 1000000) x" | rows
J=$(Q "select count(*) as v from (select 1 from public.stats_live_deltas limit 1000000) x" | val v)
[ -n "$J" ] && [ "$J" -gt 300000 ] && alert "the stats journal holds ${J}+ rows (> 300,000): world.stats_now() sums all of it on every call"

echo "== the tables that matter (size, visibility map, dead rows, last autovacuum)"
Q "select c.relname, pg_size_pretty(pg_total_relation_size(c.oid)) as total, round(100.0*c.relallvisible/nullif(c.relpages,0),1) as pct_allvisible, s.n_dead_tup as dead, to_char(s.last_autovacuum,'MM-DD HH24:MI') as last_vac, round(100.0*s.n_tup_hot_upd/nullif(s.n_tup_upd,0)) as hot_pct from pg_class c join pg_stat_user_tables s on s.relid=c.oid where c.relnamespace='public'::regnamespace and c.relkind='r' and pg_total_relation_size(c.oid) > 100*1024*1024 order by pg_total_relation_size(c.oid) desc" | rows
Q "select string_agg(c.relname || ' ' || round(100.0*c.relallvisible/nullif(c.relpages,0))::text || '% mapped', '; ') as v from pg_class c where c.relnamespace='public'::regnamespace and c.relkind='r' and c.relpages > 12000 and 100.0*c.relallvisible/nullif(c.relpages,0) < 90" | val v | { read -r L; [ -n "$L" ] && [ "$L" != "null" ] && alert "big tables with a stale visibility map (< 90% all-visible; index-only scans become heap fetches): $L"; }
Q "select string_agg(c.relname || ' ' || s.n_dead_tup::text || ' dead of ~' || c.reltuples::bigint::text, '; ') as v from pg_class c join pg_stat_user_tables s on s.relid=c.oid where c.relnamespace='public'::regnamespace and c.relkind='r' and c.reltuples > 20000 and s.n_dead_tup > 1.0*c.reltuples" | val v | { read -r L; [ -n "$L" ] && [ "$L" != "null" ] && alert "tables with more dead rows than live ones (bloat): $L"; }

echo "== write load: WAL since the last restart, and the heaviest statements"
Q "select round(wal_bytes/1048576.0/greatest(extract(epoch from now()-stats_reset)/60,1),1) as wal_mb_per_min, wal_fpi from pg_stat_wal" | rows
W=$(Q "select round(wal_bytes/1048576.0/greatest(extract(epoch from now()-stats_reset)/60,1),1) as v from pg_stat_wal" | val v)
[ -n "$W" ] && awk "BEGIN{exit !($W > 30)}" && alert "WAL is ${W} MB/min (> 30): the write path is saturating the disk — check port_goods (HOT share, fillfactor) and the minute jobs"
Q "select calls, round(mean_exec_time) as mean_ms, round(total_exec_time/1000) as total_s, shared_blks_dirtied as dirtied, left(regexp_replace(query,'\s+',' ','g'),70) as q from pg_stat_statements order by total_exec_time desc limit 5" | rows

echo "== what a player waits for (timed through the CLI; baseline select 1 first)"
t() { local a=$(date +%s%N); timeout 120 supabase db query --linked "$2" >/dev/null 2>&1; local b=$(date +%s%N); awk "BEGIN{printf \"  %-28s %6.1f s\n\", \"$1\", ($b-$a)/1e9}"; }
t "baseline select 1" "select 1"
t "world.stats_now()" "select world.stats_now() ->> 'at'"
t "world.sea_roster(1 day)" "select length(world.sea_roster(now() - interval '1 day')::text)"

echo
if [ "$ALERTS" -eq 0 ]; then echo "HEALTH: no thresholds tripped."; else echo "HEALTH: $ALERTS alert(s) above."; fi
