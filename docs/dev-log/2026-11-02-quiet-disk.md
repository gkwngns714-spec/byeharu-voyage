# 2026-11-02 — 0297: the disk gets quiet (stop re-reading `port_goods` for nothing; rewrite `voyages` compact)

**Branch** `quiet-disk` · migration `supabase/migrations/20260818000297_the_disk_gets_quiet.sql` · a LOAD-ONLY slice: one `ALTER TABLE … SET (autovacuum…)`, one `CLUSTER`,
no row, function, knob, switch, cron job or schedule moves. Deploys AFTER 0296 (0295 `stats-period` and 0296 `reconcile-wall` are other branches' migrations).
The database is I/O-bound on Micro compute and code cannot add IOPS, so this removes reads the database does to itself.

**Dates.** The brief dated its evidence "2026-11-02 18:14-18:20 UTC". The database clock reads **2026-11-01** 18:25 UTC at my first query (= 2026-11-02 03:25 KST, this PC's
calendar day); the server has been up since 2026-11-01 09:34:04 UTC, which is the "8.8 h" of the brief. Every time below is UTC from the database's own `now()`.

## 1. What was measured (prod, read-only, head 0294, PG 17.6, 18:25-19:00 UTC)

Every call was a pure SELECT on the catalogs and statistics views, one statement per `supabase db query --linked` call. Exceptions to "no volatile function", stated plainly:
`pg_relation_size`-style size functions were NOT used (sizes are `pg_class.relpages`); one read of `pg_stat_statements` (a view over a volatile read-only C function) for the 0292
CLUSTER's duration; `pg_stat_progress_vacuum` / `pg_stat_activity` / `pg_statio_user_tables` (stable). No `EXPLAIN ANALYZE`, no application function.

### 1.1 Who reads (two `pg_statio_user_tables` snapshots, 18:32:17 and 18:41:23 = 547 s, a Stats count inside)
402,466 block reads of tables and their indexes = **44.2 k a minute** (the brief's `pg_stat_io` reading, a quieter 150 s: 20.7 k a minute, 69 % by autovacuum workers).

| table | reads | share | autovacuum / autoanalyze passes in the 9 min | note |
|---|---|---|---|---|
| standing_route_laps | 102,638 | 25.5 % | 3 / 1 | LEFT ALONE (0291's options keep its map fresh for the Stats count) |
| **port_goods** | 84,435 | 21.0 % | **8 / 6** | 1,547,576 updates, 100 % HOT |
| ledger | 40,277 | 10.0 % | 2 / 0 | |
| **voyages** | 36,559 | 9.1 % | **1 / 1** | next 11 min (poll 18:37-18:48): 70,478 reads, 2 vacuums |
| events | 35,697 | 8.9 % | 1 / 0 | |
| stats_city_good | 34,104 | 8.5 % | 1 / 1 | |

### 1.2 `port_goods` — why the passes buy nothing, and why they never stop
* 154,734 rows, 14,374 pages (112 MB), `reloptions {fillfactor=30}`, indexes 1,072 + 193 + 12 pages. **100 % HOT**: 309,481 of 309,481 updates in a 53 s window, 1,547,576 of
  1,547,576 in 9 minutes, 154,734 of 154,734 in every pass of the 18:51-18:55 trace. No index entry dies, pruning removes the old versions, the visibility map the vacuum sets is
  cleared again within the minute.
* **369 autovacuums and 305 autoanalyzes** since 09:34 (18:56:31); in the last 30 minutes 23 and 20. A pass reads 6-14 k of the 14,374 pages (84,435 reads / 14 passes = 6.0 k each).
* **The brief's model (a pass every ~1.5 min because 31 k dead tuples are crossed "within seconds") is not what happens.** `n_dead_tup` counts dead versions **net of in-page
  pruning** (`heap_page_prune` subtracts what it reclaims), so it never grows with the update rate: it stands at about one market pass. Traced for 14 minutes (72 samples, 18:51-19:06, plus an earlier 24-sample trace):
  **113,345 .. 254,846** between vacuums (0 right after one), and across the pass of 18:52:26 (154,734 rows updated) it rose by only 73,125 — the pass pruned ~81,600 of the previous pass's versions on its way.
  The default trigger is 50 + 0.2 × 154,734 = **30,997**: the table is above it **all the time**, so a pass begins as soon as the last one ends (+ the 60 s naptime).
* `n_mod_since_analyze` (the analyze counter) does count HOT updates and is not reduced by pruning: +154,734 per pass (154,857 → 309,591 at 18:52:26).

### 1.3 `voyages` — 8-9x bloat, and the most expensive single reader per pass
* 25,372 pages (198 MB); `pg_stats` column widths sum to **977-983 B** a row (`path` jsonb 746 B, `speed_profile` 96 B, the rest ~140 B); **21,359 live rows, exact** (19:17:30, 445 SAILING; the brief had 25,447 an hour earlier). The cumulative counters give ~150 deleted and ~73 inserted a minute
  (`n_tup_del` 49,057 → 56,682 and `n_tup_ins` 26,727 → 30,459 between 18:26 and 19:17): the table is draining. `n_live_tup` is only an ESTIMATE here (22,055 at 19:07, **39,358** at 19:17 after a vacuum of
  the bloated heap) and is not relied on. CLUSTER packs pages full: ~7.9 rows a page → **~2,700 pages (~21 MB)** for 21.4 k rows, ~3,200 for the brief's 25.4 k — 8-9x. Synthetic check, a 25,289-row
  table in a 198 MB heap rewritten by this file's code: **3,162 pages (24.7 MB)**, indexes 18.9 MB → 1.9 MB.
* Indexes: 4, **3,019 pages** (23.6 MB) for ~21-25 k entries: `voyages_pkey (id)` 1,221 pages (≈80-90 needed), `voyages_fleet_ended_0249 (fleet_id, eta) WHERE status <> 'SAILING'` 1,759 (≈100-110),
  `voyages_due_at` 28, `voyages_one_sailing_per_fleet` 11. **Only the primary key is a full index** (CLUSTER refuses a partial one), so `CLUSTER … USING voyages_pkey`.
* Options `{autovacuum_vacuum_scale_factor=0, autovacuum_vacuum_threshold=2000}`; 2 foreign keys IN (`voyage_events`, `insured_voyages`, ON DELETE CASCADE), 4 out (ports ×2, fleet, player), 5 checks, trigger
  `voyages_keep_due_at`; no publication, no dependent view, an empty TOAST table.
* **77 autovacuums and 30 autoanalyzes** since 09:34 (**5 and 5 in the last 30 minutes**). An ANALYZE samples min(30,000 rows, all blocks) so on a 25,372-page table it reads **every
  page**; a vacuum pass was watched in `pg_stat_progress_vacuum` (18:38:35-18:38:59: scanning heap → vacuuming indexes → vacuuming heap, ~25 s) and the table's read counters then rose by 31,681 (the
  flush landed 25 s after the pass). Two vacuums in the 11 min poll = 70,478 reads (6.4 k a minute, 14.5 % of the table reads of that window).
* After the rewrite each pass costs ~1/8 of that (heap ~2.7-3.2 k pages, indexes ~230).

### 1.4 What the brief got wrong (so it is not rebuilt on)
* **`price_history_hour` is not bloated** and is NOT in this file: **246,321 rows** in 3,697 pages (66 a page, 174 hours of history). The "14 k live rows" was `n_live_tup`, which restarted from 0
  with the 09:34 restart (`autovacuum_count = analyze_count = 0` since). A rewrite would buy nothing.
* **No threshold gives "a pass about every 30 minutes" on `port_goods`**: the vacuum trigger does not accumulate at 150 k a minute (§1.2). With N = 4.5 M it would never fire (until a leak
  of 4.5 M unpruned versions). Hence two numbers (§2).

## 2. The change
```
alter table public.port_goods set (autovacuum_vacuum_scale_factor = 0, autovacuum_vacuum_threshold = 1000000,
                                   autovacuum_analyze_scale_factor = 0, autovacuum_analyze_threshold = 4500000);
comment on table public.port_goods is '0297: …';     -- why this table has odd autovacuum settings (it had no comment)
lock table public.voyages in access exclusive mode;  -- then count/min/max/sum(hashtext(id)), sizes, index definitions
cluster public.voyages using voyages_pkey;           -- then the same reads again, and the asserts
```
**Chosen N: vacuum 1,000,000, analyze 4,500,000.**
* **Analyze 4,500,000**: it counts every change (§1.2) at 154,734 a pass → one analyze per **29.1 minutes** (was one per ~1.5). The planner's statistics are static (a fixed 246 × 629 catalogue; lookups by key).
* **Vacuum 1,000,000** (not 4.5 M): routine churn peaks at ~255 k, so 1 M is 3.9x above anything seen (and 2.4x above one extra pinned pass, ~410 k): **no routine vacuum**. A safety net remains for what
  pruning cannot clear — a snapshot that pins several passes, or a non-HOT leak (dead index entries that only a vacuum removes): it trips within ~5 market passes of garbage. At 4.5 M that net would be a
  half-hour hole (if HOT broke entirely: 3 index entries × 154 k updates ≈ 9 MB of index growth a minute). One token to change if the coordinator disagrees.
* **Anti-wraparound is unaffected**: `relation_needs_vacanalyze` sets `dovacuum` for `force_vacuum` (age(relfrozenxid) > `autovacuum_freeze_max_age` = 200,000,000) before it reads any threshold. Numbers (read-only):

| quantity | reading | |
|---|---|---|
| age(relfrozenxid) of port_goods | 1,429 (18:26:18) · 3,918 (18:51:18) · 4,880 (18:56:31) · 3,568 (19:00) | the 1.5-min passes keep it near 0 — their only product |
| oldest age in the database | 14,515,309 (18:36:08) — the system catalogs (relfrozenxid ≈ 730) | they reach 200 M no matter what this file does |
| xid consumption | next xid 14,505,921 (18:26:18) → 14,515,993 (18:36:05) → 14,530,726 (18:51:18) → 14,536,345 (18:56:31) = **16.8 a second**, 1.45 M a day | the database's life average (since 2026-08-20): ~0.2 M a day |
| days to 200,000,000 with NO regular pass | 200 M / 16.8 = 11.9 M s = **138 days** | then a forced aggressive pass (112 MB, one pass) |
| margin after the forced pass starts | 2,147,483,647 − 200,000,000 = 1.95 B xids = **3.7 years**; the failsafe is at `vacuum_failsafe_age` 1.6 B | |
| multixacts | ~10 a second (9.4 / 11.1 / 10.3 over 18:36-18:51 / 18:51-19:07 / 18:36-19:07); limit `autovacuum_multixact_freeze_max_age` 400,000,000 → ~450 days | port_goods age_mxid 717-1,881 |

  (And a safety-net vacuum at 1 M dead versions advances `relfrozenxid` as a side effect.)

## 3. The lock, and what a player sees
`CLUSTER` holds ACCESS EXCLUSIVE on `voyages` from the first read to the commit. Calibration, read from `pg_stat_statements` on prod: 0292's `cluster public.port_goods using port_goods_pkey` =
**42.72 s** (1 call, including any wait for the lock; 42,944 blocks = 336 MB read; it wrote a 112 MB heap and 10 MB of indexes) — ~11 MB/s of data, ~14 MB/s with the WAL. `voyages`: 198 MB read, ~25 MB + ~2 MB written →
**expect ~15-30 s of lock on a saturated disk** (40 s as a pessimistic bound if the planner takes the random-order index path; settings: `random_page_cost` 1.1, `maintenance_work_mem` 64 MB, the
sort of ~25 MB fits in memory), **2-5 s if the disk is bursting**. Not measured for voyages — that is the first thing the deploy shows.
What a request does meanwhile: **it waits** for the lock. Role timeouts on prod (`pg_roles`): `anon` statement_timeout 3 s; `authenticated` 8 s; `authenticator` 8 s and lock_timeout 8 s — so a request that touches
`voyages` (the fleets read, issuing a sail order, the arrivals beat — which screens touch it was not traced) fails with a timeout after 3-8 s and works again when the lock ends; a request that does not touch `voyages` is unaffected. `bv-deploy.sh`
unwinds the clock first (`unwind_the_clock()`, waits for running cron jobs), so no beat, count or market run queues behind the lock. The file's own `lock_timeout` is 10 s: a lock that cannot be had
(a long reader) is refused and rolled back, and the file is simply deployed again — all the work is in ONE `DO` block, so nothing is half-applied under any runner.
Autovacuum on `voyages` (every ~6 min, ~25 s) is cancelled by the deadlock detector after `deadlock_timeout` 1 s, as in 0292.

## 4. The self-assert, and what it proves where
One `DO` block after the guard (`set_config(…, false)` session-level `statement_timeout` 10 min / `lock_timeout` 10 s, `reset` at the end of the file — 0293's idiom; no temp tables, no top-level `LOCK`, no `ANALYZE`):
(a) `port_goods` carries exactly `fillfactor=30` + the four options; (b) `voyages`: count, min/max `id`, `sum(hashtext(id))` equal before and after, both read under the lock; (c) the relfilenode changed, the heap never
grew by more than a page, and a heap of ≥ 4,000 pages is at least HALVED (a conditional between two acceptable outcomes: a small table has nothing to compact); (d) the same four indexes with the same definitions,
valid/ready/live, EVERY ONE rebuilt, the primary key marked clustered; (e) `voyages`' own options, constraints (own and referencing) and trigger as found; (f) every other relation's options, every function in
public/cmd/world/voyage (md5, 676 functions), the registry (84), the walls (0/0/0) and both owner switches as found. Printed, never asserted: heap/index sizes before/after, `age(relfrozenxid)`, the seconds.

**Local gates:** `node scripts/db/check-versions.mjs` OK (283, no collisions) · `BYEHARU_PREFIX_CACHE=required node scripts/db/proof.mjs standing`: 282 restored from `p0282`, 1 applied (the file's DO body),
**283/283 with a self-assert receipt**, world-guard ok, `11_standing_route.sql` 5/5 (a second run after the last header-comment edit restored all 283 from the snapshot of the first — the cache key ignores comments, so the executed SQL is the same text) ·
`npx playwright test tests/duplication.spec.ts` 11/11. tsc / eslint / build: not run, no TypeScript touched.
**CI (first run, head `bad17f60`):** every check green incl. `disposable-chain` — the real Postgres 17 behind the CLI's `migration up --local` restored the 281-file snapshot, applied 0294 and `20260818000297_the_disk_gets_quiet.sql` (0.65 s) and passed the chain/ACL/lockdown steps; its `voyages` is empty, so this proves the mechanism, not the 25 k-row identity.
**Extra local proof (scratchpad scripts, not in the repo):** the file applied to private copies of the 0294 world in two runner regimes — (A) the whole file as one multi-statement query, (B) statement by statement,
each its own autocommit transaction (the strictest reading of the CLI pipeline) — both OK; against a synthetic prod-shaped `voyages` (25,289 rows in a 198 MB heap) the rewrite gives 25,346 → 3,162 pages in 0.65 s
on wasm; **16 mutations** of the file (skip the ALTER, a wrong threshold, a dropped fillfactor, skip the CLUSTER, a row deleted / an index dropped / an option, constraint or trigger changed after the rewrite, another table's
option, a function added, an owner switch flipped, a client write grant, the halving and growth bounds, the guard) — each caught by the assert meant for it, and every failed run left `port_goods` and `voyages`
exactly as found (one transaction).

## 5. What I could NOT prove before running on prod
1. **The lock time** — a calibrated estimate (§3), not a measurement. The deploy shows it: read the `cluster public.voyages …` and the last `do $assert$ …` rows of `pg_stat_statements`, or sample `pg_locks`.
2. **The real runner's behaviour of CLUSTER inside a `DO` block** — PGlite runs it in two regimes; the real-Postgres CI job (`disposable-chain`, the CLI's pipeline) is the proof, and prod's `db push` the last word.
3. **That no routine autovacuum runs on `port_goods` afterwards** — derived from the traces (§1.2), not observed with the options in place. The after-check decides it (10 minutes).
4. **The size of the read reduction** — expected, not measured: `port_goods` 43 passes / 30 min of 6-14 k blocks (~8.6 k a minute) → ~1 analyze / 29 min (~0.5 k a minute); `voyages` ~6.4 k a minute → ~0.8 k. About 13-15 k blocks a minute
   (110-125 MB a minute), a third of the 44 k a minute of my windows. The brief's own 20.7 k a minute (a quieter window) cannot be compared with it.
5. **Row identity at scale in CI**: the chain's world has an EMPTY `voyages` (0 rows in 346 pages), so CI proves the mechanism and prod proves the ~21 k rows (under the lock, at deploy).
6. **Row order**: after CLUSTER, `voyages` is stored in `id` (uuid) order; a query that relies on the unspecified order of a seq scan without `ORDER BY` could return rows in another order. I did not audit every function; a regex scan of the live function bodies (`prosrc`) found no `select … from voyages … limit 1` statement at all (crude, but no unordered pick-one-row over this table).
7. **Index-only scans on `voyages`** read the heap until its first autovacuum sets the map (≤ ~6 min; a ~21 MB cached heap).
8. Whether the burst credits of the disk are exhausted at the time of the deploy (decides 5 s vs 30 s of lock).

## 6. PROD CHECKS (read-only) — before the deploy, and the AFTER-CHECK
**Before (the coordinator may repeat):** head `20260818000294`; `select reloptions, relpages from pg_class where oid in ('public.port_goods'::regclass,'public.voyages'::regclass)` → `{fillfactor=30}` / 14,374 and
`{autovacuum_vacuum_scale_factor=0,autovacuum_vacuum_threshold=2000}` / 25,372; no table comment on either (`obj_description` null); `voyages_pkey` valid primary key; 0295 and 0296 live.
**After (10 minutes, read-only; stable functions only — `age()`, `now()`; nothing is written, no game function is called).** One command takes two snapshots and prints the deltas and a verdict
(tested on prod BEFORE the deploy, where it correctly prints CHECK on the unmigrated table). Save the block as `after-check-0297.sh` and run `SLEEP=600 bash after-check-0297.sh` from a clone that has `supabase/.temp`:
```bash
#!/usr/bin/env bash
# after-check-0297.sh — READ-ONLY. Two snapshots SLEEP seconds apart (default 600), then the deltas. Pure SELECTs from system catalogs and
# statistics views (stable functions only: age(), now()); nothing is written, no game function is called. Run from a directory that has supabase/.temp.
#   usage: SLEEP=600 bash after-check-0297.sh
export PATH="$HOME/tools/supabase:$PATH"
SLEEP="${SLEEP:-600}"
T=$(mktemp -d)
Q() { supabase db query --linked --output-format json "$1" 2>/dev/null | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{process.stdout.write(JSON.stringify(JSON.parse(s.slice(s.indexOf("{"))).rows))}catch(e){process.stdout.write("[]")}})'; }
SNAP="select now() as at, c.relname, c.reloptions, c.relpages, c.relallvisible, age(c.relfrozenxid) as age_xid, s.n_live_tup, s.n_dead_tup, s.n_tup_upd, s.n_tup_hot_upd, s.autovacuum_count as av, s.autoanalyze_count as aa, s.last_autovacuum, s.last_autoanalyze, st.heap_blks_read + st.idx_blks_read + st.toast_blks_read + st.tidx_blks_read as reads from pg_class c join pg_stat_user_tables s on s.relid = c.oid join pg_statio_user_tables st on st.relid = c.oid where c.relnamespace = 'public'::regnamespace and c.relkind = 'r' order by c.relname"
IDX="select i.indexrelid::regclass::text as idx, ic.relpages from pg_index i join pg_class ic on ic.oid = i.indexrelid where i.indrelid = 'public.voyages'::regclass order by 1"
echo "snapshot 1 ..."; Q "$SNAP" > "$T/a.json"; Q "$IDX" > "$T/idx.json"
echo "waiting ${SLEEP}s ..."; sleep "$SLEEP"
echo "snapshot 2 ..."; Q "$SNAP" > "$T/b.json"
node - "$T" <<'EOF'
const fs = require('fs'), T = process.argv[2]
const a = JSON.parse(fs.readFileSync(T + '/a.json')), b = JSON.parse(fs.readFileSync(T + '/b.json')), idx = JSON.parse(fs.readFileSync(T + '/idx.json'))
if (!a.length || !b.length) { console.log('NO DATA (the query failed)'); process.exit(1) }
const A = Object.fromEntries(a.map(r => [r.relname, r])), mins = (new Date(b[0].at) - new Date(a[0].at)) / 60000
console.log(`window ${mins.toFixed(1)} min (${a[0].at} -> ${b[0].at})`)
const rows = b.map(r => { const p = A[r.relname]; if (!p) return null; const d = k => Number(r[k]) - Number(p[k]); return { t: r.relname, reads: d('reads'), av: d('av'), aa: d('aa'), upd: d('n_tup_upd'), hot: d('n_tup_hot_upd'), dead: Number(r.n_dead_tup), pages: Number(r.relpages) } }).filter(Boolean)
const total = rows.reduce((s, r) => s + r.reads, 0)
console.log(`user-table block reads: ${total} = ${Math.round(total / mins)} a minute   (before 0297, 18:32-18:41 UTC 2026-11-01: ~44,000 a minute)`)
console.log('table'.padEnd(26), 'reads/min'.padStart(10), 'share'.padStart(6), 'autovac'.padStart(8), 'autoanl'.padStart(8), 'dead now'.padStart(10), 'HOT %'.padStart(6), 'pages'.padStart(7))
for (const r of rows.sort((x, y) => y.reads - x.reads).slice(0, 10)) console.log(r.t.padEnd(26), String(Math.round(r.reads / mins)).padStart(10), (Math.round(1000 * r.reads / total) / 10 + '%').padStart(6), String(r.av).padStart(8), String(r.aa).padStart(8), String(r.dead).padStart(10), (r.upd ? Math.round(100 * r.hot / r.upd) + '%' : '-').padStart(6), String(r.pages).padStart(7))
const pg = b.find(r => r.relname === 'port_goods'), vo = b.find(r => r.relname === 'voyages')
console.log('\nport_goods reloptions:', JSON.stringify(pg.reloptions), ' age(relfrozenxid):', pg.age_xid, ' last autovacuum:', pg.last_autovacuum, ' last autoanalyze:', pg.last_autoanalyze)
console.log(`voyages: ${vo.relpages} pages = ${(vo.relpages * 8 / 1024).toFixed(1)} MB heap (before: 25,372 pages = 198 MB), all-visible ${vo.relallvisible}/${vo.relpages}, live (an ESTIMATE) ${vo.n_live_tup}, reloptions ${JSON.stringify(vo.reloptions)}`)
console.log('voyages indexes (pages; before: pkey 1221, fleet_ended 1759, due_at 28, one_sailing 11):', idx.map(i => i.idx.replace('public.', '') + '=' + i.relpages).join('  '))
const P = rows.find(r => r.t === 'port_goods'), V = rows.find(r => r.t === 'voyages')
console.log('\nVERDICT (what a good result is):')
const ok = (c, m) => console.log((c ? '  ok    ' : '  CHECK ') + m)
ok(JSON.stringify([...pg.reloptions].sort()) === JSON.stringify(['autovacuum_analyze_scale_factor=0', 'autovacuum_analyze_threshold=4500000', 'autovacuum_vacuum_scale_factor=0', 'autovacuum_vacuum_threshold=1000000', 'fillfactor=30']), 'port_goods carries fillfactor=30 and the four options')
ok(P.av === 0, `port_goods autovacuums in the window: ${P.av} (was ~7 per 10 min)`)
ok(P.aa <= 1, `port_goods autoanalyzes in the window: ${P.aa} (was ~7 per 10 min; one per ~29 min expected)`)
ok(P.upd > 0 && P.hot / P.upd >= 0.95, `port_goods updates HOT: ${P.upd ? Math.round(100 * P.hot / P.upd) : '-'} % of ${P.upd} (was 100 %)`)
ok(P.dead < 1000000, `port_goods n_dead_tup ${P.dead} (routine 110 k-215 k; a pass starts at 1,000,000)`)
ok(vo.relpages < 12000, `voyages heap ${vo.relpages} pages (25,372 before; the rewrite expects ~2,500-3,300, less as retention deletes)`)
ok(JSON.stringify(vo.reloptions) === JSON.stringify(['autovacuum_vacuum_scale_factor=0', 'autovacuum_vacuum_threshold=2000']), 'voyages kept its own two options')
ok(total / mins < 0.8 * 44000, `reads ${Math.round(total / mins)} a minute against ~44,000 before (expected ~30,000 or less in a comparable window; the Stats count at :06/:21/:36/:51 adds ~10,000 in its minute)`)
EOF
rm -rf "$T"
```
**A good result:** `port_goods` `reloptions` = fillfactor=30 + the four options; **`av` flat over 10 minutes (was +7)**; `aa` +0 or +1 (was +7; one per ~29 min); `n_dead_tup` between ~110 k and ~410 k and never near 1,000,000;
HOT share of the window's updates ≥ 95 % (was 100 %); relpages 14,374 ± 1 %; `age_xid` rising ~1,000 a minute (fine). `voyages` `relpages` **~2,500-3,300** (≈ 20-26 MB; was 25,372 / 198 MB; 21,359 live rows at 19:17) and shrinking with
the retention, its indexes ~200-300 pages in all (was 3,019), its two options unchanged, `relallvisible/relpages` > 95 % after its first autovacuum (within ~10 minutes). Table reads per minute **≲ 30 k** in a window
that includes no Stats count (44 k before), the two tables' shares 21 % + 9 % → < 3 %. `bash scripts/ops/health.sh` with no new ALERT; the market job (`drift`) no slower (11-25 s), WAL no higher.
**A bad result:** `av` of `port_goods` still climbing (the options did not land: read `reloptions`); HOT < 80 % (a long snapshot is pinning — find it in `pg_stat_activity`); `n_dead_tup` > 1 M (a pass will run; look for the pin);
`voyages` `relpages` > 8,000 (the rewrite did not compact).
**Forward rollback:** `alter table public.port_goods reset (autovacuum_vacuum_scale_factor, autovacuum_vacuum_threshold, autovacuum_analyze_scale_factor, autovacuum_analyze_threshold);` — the rewrite itself is not undone and needs no undo.

## 7. Seen, NOT touched (outside this slice's brief)
* `standing_route_laps` is the largest reader (25 %): 3 vacuum passes in 9 minutes at threshold 500, each ~29 k pages; 0291 chose that on purpose (map freshness for the Stats count). A compaction or a looser threshold is a
  separate decision.
* `orders` is 3.2x bloated (3,673 pages for ~1,200 needed, 29 MB; 114 vacuums, 210 analyzes) and `trade_daily` 51x (1,588 pages for ~30) — small; the next candidates for the same CLUSTER if the reads matter.
* `events`, `voyage_events`, `ledger`, `stats_city_good`: 1.2-1.7x by width — big because their data is big.

## 8. Bookkeeping
Owner row 264 (state only; #453 already carries 263) in `docs/OWNER_REQUESTS.md`. `docs/WORK_QUEUE.md` is the coordinator's (not edited here). PR title `MIGRATION — 0297: the disk gets quiet (deploy AFTER 0296)`; commit trailer
`Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`. Not merged, not deployed: the coordinator runs `~/bin/bv-deploy.sh <pr>` once 0295 and 0296 are live.
