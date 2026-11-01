#!/usr/bin/env bash
# Sample the hourly reconcile session while it runs: its wait event and WHO blocks it (pg_blocking_pids), every ~4 s.
# Usage: bash reconcile-watch.sh <start HH:MM:SS UTC> <seconds>
. "$(dirname "$0")/_link.sh"
start=$(date -u -d "$1" +%s); end=$(( start + ${2:-150} ))
while [ "$(date +%s)" -lt "$start" ]; do sleep 2; done
while [ "$(date +%s)" -lt "$end" ]; do
  timeout 30 supabase db query --linked --output-format json "select to_char(now(),'HH24:MI:SS') as t, a.pid, coalesce(a.wait_event_type,'-')||'/'||coalesce(a.wait_event,'-') as wait, round(extract(epoch from now()-a.query_start)::numeric) as q_s, (select string_agg(b.pid||' '||left(regexp_replace(b.query,'\s+',' ','g'),38)||' xact '||round(extract(epoch from now()-b.xact_start))||'s '||coalesce(b.wait_event,'-'), ' | ') from pg_stat_activity b where b.pid = any(pg_blocking_pids(a.pid))) as blocked_by from pg_stat_activity a where a.query ilike 'call public.tick_reconcile%' and a.state = 'active' and a.pid <> pg_backend_pid()" 2>/dev/null | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const j=JSON.parse(s.slice(s.indexOf("{")));if(!j.rows.length)console.log("-- no reconcile session");for(const r of j.rows)console.log(r.t,"pid",r.pid,r.wait.padEnd(24),"q",String(r.q_s).padStart(4)+"s","blocked_by:",r.blocked_by||"(nobody)")}catch(e){console.log("?")}})'
done
echo "reconcile-watch done $(date -u +%H:%M:%S)"
