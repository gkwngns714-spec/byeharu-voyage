// ═════════════════════════════════════════════════════════════════
// bytes-0316.mjs — WHAT A ROW OF 0316 COSTS ON DISK. LOCAL ONLY (PGlite, the same 8 KB pages and the same row format as prod); not in CI.
// ═════════════════════════════════════════════════════════════════
//
//   node scripts/ops/harness/history/bytes-0316.mjs
//
// One year of each table with prod's subject counts (246 harbours, 629 goods, 840 companies) and figures of prod's size. Prints bytes a row, bytes a day and MB a year: heap + the primary key.
// No chain: the four CREATE TABLEs below are 0316's, copied, and this file reads nothing else.

import { PGlite } from '@electric-sql/pglite'

const db = new PGlite()
const uuid = `md5('s' || s)::uuid`
const big = (lo, hi) => `(${lo} + floor(random() * ${hi - lo}))::bigint`
const price = `round((10 + random() * 900)::numeric, 4)`

const TABLES = [
  { name: 'history_world_day', subjects: 1, ddl: `(day date primary key, players bigint not null, merchants bigint not null, cities bigint not null, set_aside bigint not null,
      minted bigint, removed bigint, sold bigint, bought bigint)`,
    fill: `insert into history_world_day select date '2026-01-01' + d, ${big(1e6, 1e8)}, ${big(1e9, 1e10)}, ${big(1e10, 4e10)}, ${big(1e9, 2e9)}, ${big(1e6, 1e8)}, ${big(1e6, 1e8)}, ${big(1e8, 1e9)}, ${big(1e8, 1e9)} from generate_series(0, 364) d` },
  { name: 'history_city_day', subjects: 246, ddl: `(port_id uuid not null, day date not null, purse bigint not null, income bigint, spending bigint, profit bigint, primary key (port_id, day))`,
    fill: `insert into history_city_day select ${uuid}, date '2026-01-01' + d, ${big(1e4, 1e9)}, ${big(1e4, 1e8)}, ${big(1e4, 1e8)}, ${big(-1e7, 1e7)} from generate_series(1, 246) s, generate_series(0, 364) d` },
  { name: 'history_good_day', subjects: 629, ddl: `(good_id uuid not null, day date not null, open numeric(12,4), high numeric(12,4), low numeric(12,4), close numeric(12,4), sold bigint, bought bigint, primary key (good_id, day))`,
    fill: `insert into history_good_day select ${uuid}, date '2026-01-01' + d, ${price}, ${price}, ${price}, ${price}, ${big(0, 1e6)}, ${big(0, 1e6)} from generate_series(1, 629) s, generate_series(0, 364) d` },
  { name: 'history_company_day', subjects: 840, ddl: `(player_id uuid not null, day date not null, earned bigint not null default 0, lost bigint not null default 0, primary key (player_id, day))`,
    fill: `insert into history_company_day select ${uuid}, date '2026-01-01' + d, ${big(1e4, 1e8)}, ${big(1e4, 1e8)} from generate_series(1, 840) s, generate_series(0, 364) d` },
]

let daily = 0
for (const t of TABLES) {
  await db.exec(`create table ${t.name} ${t.ddl}`)
  await db.exec(t.fill)
  await db.exec(`vacuum analyze ${t.name}`)
  const { rows } = await db.query(`select count(*)::bigint n, pg_total_relation_size('${t.name}')::bigint b from ${t.name}`)
  const n = Number(rows[0].n)
  const b = Number(rows[0].b)
  const perRow = b / n
  const perDay = perRow * t.subjects
  daily += perDay
  console.log(`${t.name.padEnd(22)} ${String(n).padStart(8)} rows  ${perRow.toFixed(0).padStart(4)} B a row  ${(perDay / 1024).toFixed(1).padStart(6)} KB a day  ${((perDay * 365) / 1048576).toFixed(1).padStart(6)} MB a year`)
}
console.log(`${'all four'.padEnd(22)} ${' '.repeat(8)}       ${' '.repeat(4)}          ${(daily / 1024).toFixed(1).padStart(6)} KB a day  ${((daily * 365) / 1048576).toFixed(1).padStart(6)} MB a year`)
await db.close()
