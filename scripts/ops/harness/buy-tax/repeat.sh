# WHAT THE BUY TAX (0507) DOES TO A WAITING REPEAT over three game days: hq-figures/measure-cap.mjs (its Repeat only, the allowance as it is),
# with the city purses lit. Local PGlite only; rolled back. BV_CACHE_DIR=<a private dir> bash scripts/ops/harness/buy-tax/repeat.sh
H=scripts/ops/harness/hq-figures
sed "s#cacheDir: PREFIX_CACHE_DIR#cacheDir: process.env.BV_CACHE_DIR#" $H/q.mjs > $H/_q.mjs
sed "s#'./q.mjs'#'./_q.mjs'#; s#^await db.exec('begin')#await db.exec('begin'); await db.exec(process.env.SETSQL)#; s#^async function rotationHome(nation, port) {#async function rotationHome(nation, port) { return { runs: 0, homes: 0, kinds: 0, why: {}, coin: 0, aboard: 0, secs: END }#" $H/measure-cap.mjs > $H/_m.mjs
U="update public.world_config set value='true'::jsonb where key"
L="$U = 'city_treasury_enabled'; insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing; update public.port_treasury set ducats = 50000000;"
run(){ echo "== $1"; SETSQL="$L $2" timeout 500 node $H/_m.mjs --fractions 0.35 2>&1 | grep -E "WAITING REPEAT |rror" | cut -c1-150; }
run none "select 1"
run half "$U in ('buy_tax_enabled','tax_thirty_enabled')"
run city "$U in ('buy_tax_enabled')"
run flat3 "$U in ('buy_tax_enabled'); update public.world_config set value='1000'::jsonb where key='buy_tax_share'"
rm -f $H/_m.mjs $H/_q.mjs
