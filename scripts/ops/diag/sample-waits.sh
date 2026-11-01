#!/usr/bin/env bash
. "$(dirname "$0")/_link.sh"
end=$(( $(date +%s) + ${1:-150} ))
while [ "$(date +%s)" -lt "$end" ]; do
  timeout 30 supabase db query --linked --output-format json "select to_char(now(),'HH24:MI:SS') as t, coalesce(wait_event_type,'-')||'/'||coalesce(wait_event,'-') as wait, round(extract(epoch from now()-query_start)::numeric) as secs, left(regexp_replace(query,'\s+',' ','g'),58) as q from pg_stat_activity where datname='postgres' and state <> 'idle' and pid <> pg_backend_pid() and query !~* 'pg_stat_activity' and backend_type='client backend' order by query_start" 2>/dev/null | node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const j=JSON.parse(s.slice(s.indexOf("{")));for(const r of j.rows)console.log(r.t,r.wait.padEnd(26),String(r.secs).padStart(4)+"s",r.q)}catch(e){}})'
  echo "--"
done
