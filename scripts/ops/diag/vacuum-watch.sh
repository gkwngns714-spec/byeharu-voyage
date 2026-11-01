#!/usr/bin/env bash
# Sample pg_stat_progress_vacuum every ~5 s for N seconds: which tables autovacuum works on, in which phase, how big each pass is.
. "$(dirname "$0")/_link.sh"
end=$(( $(date +%s) + ${1:-120} ))
while [ "$(date +%s)" -lt "$end" ]; do
  timeout 30 supabase db query --linked --output-format json "select to_char(now(),'HH24:MI:SS') as t, p.relid::regclass::text as tbl, p.phase, p.heap_blks_total as total, p.heap_blks_scanned as scanned, p.heap_blks_vacuumed as vacuumed, p.index_vacuum_count as idx_passes, p.num_dead_item_ids as dead_ids, extract(epoch from now()-a.xact_start)::int as age_s from pg_stat_progress_vacuum p join pg_stat_activity a on a.pid=p.pid" 2>/dev/null | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const j=JSON.parse(s.slice(s.indexOf("{")));if(!j.rows.length)console.log("-- idle");for(const r of j.rows)console.log(r.t,r.tbl.padEnd(22),r.phase.padEnd(22),"scanned",String(r.scanned).padStart(6),"/",String(r.total).padEnd(6),"idx_passes",r.idx_passes,"dead_ids",r.dead_ids,"age",r.age_s+"s")}catch(e){console.log("?")}})'
done
