#!/usr/bin/env bash
. "$(dirname "$0")/_link.sh"
read_now() { timeout 60 supabase db query --linked --output-format json "select extract(epoch from now()) as t, wal_bytes::numeric as wal, wal_fpi as fpi, (select n_tup_upd from pg_stat_user_tables where relid='public.port_goods'::regclass) as upd, (select n_tup_hot_upd from pg_stat_user_tables where relid='public.port_goods'::regclass) as hot from pg_stat_wal" 2>/dev/null | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const r=JSON.parse(s.slice(s.indexOf("{"))).rows[0];console.log([r.t,r.wal,r.fpi,r.upd,r.hot].join(" "))})'; }
A=$(read_now); echo "A: $A"
target=$(( $(date +%s) + 240 )); while [ "$(date +%s)" -lt "$target" ]; do sleep 5; done
B=$(read_now); echo "B: $B"
node -e '
const [a,b]=[process.argv[1],process.argv[2]].map(x=>x.split(" ").map(Number));
const min=(b[0]-a[0])/60;
console.log("window", min.toFixed(1), "min | WAL", ((b[1]-a[1])/1048576/min).toFixed(1), "MB/min | FPI", Math.round((b[2]-a[2])/min), "/min | port_goods updates", Math.round((b[3]-a[3])/min), "/min, HOT", (100*(b[4]-a[4])/(b[3]-a[3])).toFixed(1)+"%")' "$A" "$B"
