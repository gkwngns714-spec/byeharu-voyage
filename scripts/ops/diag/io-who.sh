#!/usr/bin/env bash
# Who reads and writes the disk right now: pg_stat_io by backend type (2 readings N seconds apart) + autovacuum runs per table.
. "$(dirname "$0")/_link.sh"
SECS=${1:-150}; SCD="${TMPDIR:-/tmp}"
SQL="select 'io' as k, backend_type||'/'||context as who, coalesce(reads,0) as reads, coalesce(writes,0) as writes, extract(epoch from now()) as t, null::bigint as av, null::bigint as dead from pg_stat_io where object='relation' and (coalesce(reads,0)+coalesce(writes,0))>0 union all select 'av', relname, 0, 0, extract(epoch from now()), autovacuum_count, n_dead_tup from pg_stat_user_tables where schemaname='public' and (pg_total_relation_size(relid) > 50*1024*1024)"
rd() { timeout 90 supabase db query --linked --output-format json "$SQL" 2>/dev/null | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{console.log(JSON.stringify(JSON.parse(s.slice(s.indexOf("{"))).rows))})'; }
rd > "$SCD/IA.json"; echo "A $(date -u +%H:%M:%S)"
target=$(( $(date +%s) + SECS )); while [ "$(date +%s)" -lt "$target" ]; do sleep 5; done
rd > "$SCD/IB.json"; echo "B $(date -u +%H:%M:%S)"
node -e '
const fs=require("fs");const A=JSON.parse(fs.readFileSync(process.argv[1],"utf8")),B=JSON.parse(fs.readFileSync(process.argv[2],"utf8"));
const key=r=>r.k+"|"+r.who;const a=new Map(A.map(r=>[key(r),r]));
const io=[],av=[];
for(const r of B){const p=a.get(key(r));if(!p)continue;const m=(Number(r.t)-Number(p.t))/60;
 if(r.k==="io")io.push({w:r.who,rd:(r.reads-p.reads)/m,wr:(r.writes-p.writes)/m});
 else av.push({t:r.who,runs:(r.av-p.av),dead:r.dead,per_h:(r.av-p.av)/m*60})}
io.sort((x,y)=>(y.rd+y.wr)-(x.rd+x.wr));
console.log("blocks per minute (8 KB each) by who, over the window:");
let tr=0,tw=0;for(const o of io){tr+=o.rd;tw+=o.wr}
console.log("  TOTAL reads",Math.round(tr),"="+(tr*8/1024).toFixed(0)+" MB/min   writes",Math.round(tw),"="+(tw*8/1024).toFixed(0)+" MB/min");
for(const o of io.slice(0,8))console.log("  "+o.w.padEnd(34),"reads",String(Math.round(o.rd)).padStart(7),"writes",String(Math.round(o.wr)).padStart(7));
console.log("autovacuum runs started in the window, big tables (runs, dead rows now):");
for(const o of av.sort((x,y)=>y.runs-x.runs))console.log("  "+o.t.padEnd(24),"runs",o.runs,"(~"+o.per_h.toFixed(0)+"/h)","dead",o.dead)
' "$(win "$SCD/IA.json")" "$(win "$SCD/IB.json")"
