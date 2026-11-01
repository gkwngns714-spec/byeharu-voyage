#!/usr/bin/env bash
# Which tables are read FROM DISK (cache misses) and which are scanned sequentially? Two read-only readings N seconds apart; rank by blocks read per minute.
# Usage: bash table-reads.sh [seconds=180]
. "$(dirname "$0")/_link.sh"
SECS=${1:-180}; SCD="${TMPDIR:-/tmp}"
SQL="select s.relname, coalesce(i.heap_blks_read,0) as heap_r, coalesce(i.heap_blks_hit,0) as heap_h, coalesce(i.idx_blks_read,0) as idx_r, coalesce(i.idx_blks_hit,0) as idx_h, coalesce(i.toast_blks_read,0)+coalesce(i.tidx_blks_read,0) as toast_r, s.seq_scan, s.seq_tup_read, s.idx_scan, pg_relation_size(s.relid)/1048576 as mb, extract(epoch from now()) as t from pg_stat_user_tables s left join pg_statio_user_tables i on i.relid = s.relid where s.schemaname = 'public'"
read_now() { timeout 90 supabase db query --linked --output-format json "$SQL" 2>/dev/null | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s.slice(s.indexOf("{")));console.log(JSON.stringify(j.rows))})'; }
read_now > "$SCD/RA.json"; echo "reading A taken $(date -u +%H:%M:%S)"
target=$(( $(date +%s) + SECS )); while [ "$(date +%s)" -lt "$target" ]; do sleep 5; done
read_now > "$SCD/RB.json"; echo "reading B taken $(date -u +%H:%M:%S)"
node -e '
const fs=require("fs");const A=JSON.parse(fs.readFileSync(process.argv[1],"utf8")),B=JSON.parse(fs.readFileSync(process.argv[2],"utf8"));
const a=new Map(A.map(r=>[r.relname,r]));const out=[];
for(const r of B){const p=a.get(r.relname);if(!p)continue;const min=(Number(r.t)-Number(p.t))/60;
 const hr=(r.heap_r-p.heap_r)/min, ir=(r.idx_r-p.idx_r)/min, tr=(r.toast_r-p.toast_r)/min, hh=(r.heap_h-p.heap_h)/min, ih=(r.idx_h-p.idx_h)/min;
 const reads=hr+ir+tr, hits=hh+ih;
 out.push({t:r.relname,mb:Number(r.mb),reads:Math.round(reads),heap:Math.round(hr),idx:Math.round(ir),toast:Math.round(tr),hit:reads+hits>0?Math.round(100*hits/(reads+hits)):null,seq:Math.round((r.seq_scan-p.seq_scan)/min*10)/10,seqrows:Math.round((r.seq_tup_read-p.seq_tup_read)/min),idxs:Math.round((r.idx_scan-p.idx_scan)/min)})}
out.sort((x,y)=>y.reads-x.reads);
let tot=0;for(const o of out)tot+=o.reads;
console.log("blocks read from disk/OS per minute, all public tables:",Math.round(tot),"=",(tot*8/1024).toFixed(0),"MB/min");
console.log("table                      size_mb  reads/min   heap    idx  toast  hit%  seqscans/min  seq_rows/min  idxscans/min");
for(const o of out.slice(0,14))console.log(o.t.padEnd(26),String(Math.round(o.mb)).padStart(7),String(o.reads).padStart(10),String(o.heap).padStart(7),String(o.idx).padStart(6),String(o.toast).padStart(6),String(o.hit??"-").padStart(5),String(o.seq).padStart(12),String(o.seqrows).padStart(13),String(o.idxs).padStart(13));
console.log("--- biggest sequential readers (rows/min):");
for(const o of out.slice().sort((x,y)=>y.seqrows-x.seqrows).slice(0,6))console.log(o.t.padEnd(26),"seq_rows/min",String(o.seqrows).padStart(10),"seqscans/min",o.seq,"size_mb",Math.round(o.mb))
' "$(win "$SCD/RA.json")" "$(win "$SCD/RB.json")"
