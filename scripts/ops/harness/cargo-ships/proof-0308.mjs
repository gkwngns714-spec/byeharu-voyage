// ═════════════════════════════════════════════════════════════════
// proof-0308.mjs — CARGO SHIPS EXIST (migration 0308): the red-first proof. LOCAL ONLY (PGlite); not in CI.
// ═════════════════════════════════════════════════════════════════
//
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/cargo-ships/proof-0308.mjs
//
// Restores the cached world at head 0307 (never from zero), then applies 0308 to it several times inside savepoints:
//   MUTATION CONTROLS - deliberate breakages of the file, each required to FAIL its self-assert for the intended reason;
//   POSITIVE CONTROL  - the real file, which must pass and print its receipt.
// The harness reads the migration from supabase/migrations; it does not edit it.

import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { migrationFiles, MIGRATIONS_DIR, PREFIX_CACHE_DIR, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'

const NAME = '20260818000308_cargo_ships_exist.sql'
const failures = []
const say = (...a) => console.log(...a)

const names = await migrationFiles()
const files = []
for (const n of names) if (n !== NAME) files.push({ name: n, sql: await readFile(path.join(MIGRATIONS_DIR, n), 'utf8') })
const file = (await readFile(path.join(MIGRATIONS_DIR, NAME), 'utf8')).replaceAll('\r', '')
const out = await applyWithPrefixCache({
  variant: await preambleVariant(), files, cacheDir: PREFIX_CACHE_DIR, log: say, required: true, snapshots: false,
})
const db = out.db
say(`world: head ${files.at(-1).name.slice(0, 14)}, ${out.restored} of ${files.length} restored from the prefix cache, ${out.applied.filter((r) => !r.restored).length} applied here`)

function swap(sql, from, to) {
  if (sql.split(from).length !== 2) throw new Error(`mutation text occurs ${sql.split(from).length - 1} times: ${from}`)
  return sql.replace(from, to)
}

const BEFORE_ASSERT = `  -- ── 6. THE SELF-ASSERT: the catalog; nothing else moved ──\n`
const addBeforeAssert = (s, sql) => swap(s, BEFORE_ASSERT, `${sql}\n${BEFORE_ASSERT}`)
const MADE = `    insert into public.cargo_ships (fleet_id, player_id, nation_id, home_port_id, ord)\n`

const MUTATIONS = [
  ['the knob is ignored: the commission works dark', (s) => swap(s,
    `  if not public.convoys_on() then\n    return 0;\n  end if;\n  select n.code, p.id`,
    `  select n.code, p.id`),
    /dark, a cargo ship was made/],
  ['the file ships lit', (s) => swap(s,
    `('convoys_enabled', 'false'::jsonb,`, `('convoys_enabled', 'true'::jsonb,`),
    /cargo ships are not dark/],
  ['she enters the merchants: a row in npc_houses', (s) => swap(s, MADE,
    `    insert into public.npc_houses (player_id, roster_ord, ink, blurb, master, home_port_id, capital, patience)
    values (v_player, 900000 + v_n, 'eng', 'A cargo ship house.', 'Crown', v_cap, 1000, 0.1);\n${MADE}`),
    /entered merchant logic/],
  ['the commission gives her a route', (s) => swap(s, MADE,
    `    insert into public.standing_routes (player_id, name, fleet_id) values (v_player, 'A lap', v_fleet);\n${MADE}`),
    /left an event or a route/],
  ['she is crewed: wages and stores', (s) => swap(s,
    `format('Cargo ship %s', v_n), true, false);`, `format('Cargo ship %s', v_n), true, true);`),
    /not one empty hull/],
  ['the house is a player, not an NPC', (s) => swap(s,
    `values (format('Crown Cargo %s %s', v_code, v_n), p_nation, 0, true)`, `values (format('Crown Cargo %s %s', v_code, v_n), p_nation, 0, false)`),
    /house is not a purse of 0/],
  ['the house is founded with gold', (s) => swap(s, MADE,
    `    perform public.credit(v_player, 'FOUNDING', 1000, null);\n${MADE}`),
    /E_NO_NEW_GOLD|house is not a purse of 0/],
  ['the commission takes from the capital', (s) => swap(s, MADE,
    `    perform public.treasury_post(v_cap, 'CONVOY_LOAD', -1, null, null);\n${MADE}`),
    /house is not a purse of 0/],
  ['the commission is not idempotent: a second call makes more', (s) => swap(s,
    `    continue when exists (select 1 from public.cargo_ships c where c.nation_id = p_nation and c.ord = v_n);\n`, ``),
    /cargo_ships_nation_id_ord_key|players_company_name_key|duplicate key/],
  ['she is based away from the capital', (s) => swap(s,
    `    v_fleet := public.form_fleet(v_player, format('Cargo ship %s', v_n), v_cap);`,
    `    v_fleet := public.form_fleet(v_player, format('Cargo ship %s', v_n), (select id from public.ports where kind = 'HARBOUR' and id <> v_cap order by code limit 1));`),
    /not docked at her capital/],
  ['the kind answers MERCHANT', (s) => swap(s, `then 'CARGO_SHIP'\n`, `then 'MERCHANT'\n`),
    /does not read as her kind/],
  ['a flow kind is minted', (s) => swap(s, `('CONVOY_DELIVER', 'moved', 'Funds delivered', 45)`, `('CONVOY_DELIVER', 'minted', 'Funds delivered', 45)`),
    /a flow kind is not moved/],
  ['the book lets more out than was loaded', (s) => swap(s,
    `  if v_shut + new.ducats > l.ducats then
    raise exception 'E_CARGO_OVER: load % carried %, % is closed, % more is too much', new.load_id, l.ducats, v_shut, new.ducats using errcode = '23514';
  end if;\n`, ``),
    /the book let more out than was loaded/],
  ['a ship closes another ship\'s load', (s) => swap(s, `l.stage <> 'LOADED' or l.fleet_id <> new.fleet_id or `, `l.stage <> 'LOADED' or `),
    /was not true to its load/],
  ['funds return to another port', (s) => swap(s, ` or (new.stage = 'RETURNED' and new.port_id <> l.port_id)`, ``),
    /was not true to its load/],
  ['the book is not append-only', (s) => swap(s,
    `  create trigger convoy_cargo_append_only
    before update or delete on public.convoy_cargo
    for each row execute function public.forbid_mutation();\n`, ``),
    /the book is not append-only/],
  ['a load may name a load', (s) => swap(s, `    constraint convoy_cargo_a_load_has_no_load check ((stage = 'LOADED') = (load_id is null))`, `    constraint convoy_cargo_a_load_has_no_load check (ducats > 0)`),
    /neither a load nor a closing/],
  ['a client can read the kind', (s) => swap(s, `  revoke all on table public.cargo_ships from public, anon, authenticated;\n`,
    `  revoke all on table public.cargo_ships from public, anon, authenticated;\n  grant select on table public.cargo_ships to authenticated;\n`),
    /a client can reach what it should not/],
  ['no row security on the book', (s) => swap(s, `  alter table public.convoy_cargo enable row level security;\n`, ``),
    /has no row security/],
  ['a client can commission', (s) => swap(s, `  revoke all on function public.cargo_ships_commission(uuid) from public, anon, authenticated;\n`,
    `  revoke all on function public.cargo_ships_commission(uuid) from public, anon;\n  grant execute on function public.cargo_ships_commission(uuid) to authenticated;\n`),
    /a client can reach a new function/],
  ['a live function was touched', (s) => addBeforeAssert(s,
    `  execute replace(replace(pg_get_functiondef('public.crown_call_room(uuid)'::regprocedure), E'\\r', ''), 'select greatest(0,', 'select greatest(0 ,');`),
    /another function moved/],
  ['a live knob was touched', (s) => addBeforeAssert(s,
    `  update public.world_config set value = to_jsonb(21) where key = 'crown_call_cover';`),
    /a world_config row moved/],
  ['a live trigger was added', (s) => addBeforeAssert(s,
    `  create trigger cargo_watch after update on public.fleets for each row execute function public.tg_house_caps();`),
    /a trigger moved/],
  ['a live word was touched', (s) => addBeforeAssert(s,
    `  update public.stats_flow_words set word = 'Crown money' where kind = 'CROWN_AID';`),
    /a word moved/],
]

async function attempt(sql) {
  const notices = []
  const t = performance.now()
  await db.exec('begin')
  try {
    await db.exec(sql, { onNotice: (n) => notices.push(n.message ?? String(n)) })
    return { ok: true, error: null, notices, ms: performance.now() - t }
  } catch (e) {
    return { ok: false, error: String(e?.message ?? e), notices, ms: performance.now() - t }
  } finally {
    await db.exec('rollback')
  }
}

for (const [what, mutate, why] of MUTATIONS) {
  const r = await attempt(mutate(file))
  const good = !r.ok && why.test(r.error)
  if (!good) failures.push(what)
  say(`${good ? 'RED, as it must be' : 'FAIL'}  ${what}\n    ${r.ok ? 'it passed' : r.error.slice(0, 260)}`)
}

const green = await attempt(file)
if (!green.ok) failures.push(`the real file: ${green.error}`)
say(`\n${green.ok ? 'GREEN' : 'FAIL'}  the real file, ${Math.round(green.ms)} ms\n    ${green.ok ? green.notices.find((n) => n.includes('self-assert ok')) : green.error}`)

await db.close()
if (failures.length) {
  say(`\n${failures.length} FAILED:\n  ${failures.join('\n  ')}`)
  process.exit(1)
}
say(`\nall ${MUTATIONS.length} mutations red, the real file green`)
