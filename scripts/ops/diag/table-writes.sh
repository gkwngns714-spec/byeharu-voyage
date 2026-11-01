#!/usr/bin/env bash
# Which tables write the most? Two read-only readings of pg_stat_user_tables N seconds apart; rank by rows changed per minute and by an estimated byte rate.
# Usage: bash table-writes.sh [seconds=180]
. "$(dirname "$0")/_link.sh"
SECS=${1:-180}
SCD="${TMPDIR:-/tmp}"
SQL="select s.relname, s.n_tup_ins as ins, s.n_tup_upd as upd, s.n_tup_del as del, s.n_tup_hot_upd as hot, (case when c.reltuples > 0 then pg_relation_size(c.oid)::numeric / c.reltuples else 100 end) as row_bytes, extract(epoch from now()) as t from pg_stat_user_tables s join pg_class c on c.oid = s.relid where s.schemaname = 'public'"
read_now() { timeout 90 supabase db query --linked --output-format json "$SQL" 2>/dev/null | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s.slice(s.indexOf("{")));console.log(JSON.stringify(j.rows))})'; }
read_now > "$SCD/A.json"; echo "reading A taken $(date -u +%H:%M:%S)"
target=$(( $(date +%s) + SECS )); while [ "$(date +%s)" -lt "$target" ]; do sleep 5; done
read_now > "$SCD/B.json"; echo "reading B taken $(date -u +%H:%M:%S)"
node -e '
const fs=require("fs");const A=JSON.parse(fs.readFileSync(process.argv[1],"utf8")),B=JSON.parse(fs.readFileSync(process.argv[2],"utf8"));
const a=new Map(A.map(r=>[r.relname,r]));const out=[];
for(const r of B){const p=a.get(r.relname);if(!p)continue;const min=(Number(r.t)-Number(p.t))/60;
 const ins=(r.ins-p.ins)/min,upd=(r.upd-p.upd)/min,del=(r.del-p.del)/min,hot=(r.hot-p.hot);
 const rows=ins+upd+del;out.push({t:r.relname,rows:Math.round(rows),ins:Math.round(ins),upd:Math.round(upd),del:Math.round(del),hotpct:r.upd-p.upd>0?Math.round(100*hot/(r.upd-p.upd)):null,mb:+(rows*Number(r.row_bytes)/1048576).toFixed(1)})}
out.sort((x,y)=>y.mb-x.mb);
console.log("table                     rows/min   ins     upd     del   hot%   est MB/min (row bytes x rows)");
for(const o of out.slice(0,12))console.log(o.t.padEnd(24),String(o.rows).padStart(8),String(o.ins).padStart(7),String(o.upd).padStart(7),String(o.del).padStart(7),String(o.hotpct??"-").padStart(6),String(o.mb).padStart(8))
' "$(win "$SCD/A.json")" "$(win "$SCD/B.json")"
