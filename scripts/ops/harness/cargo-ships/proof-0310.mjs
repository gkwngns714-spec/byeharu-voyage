// ═════════════════════════════════════════════════════════════════
// proof-0310.mjs — CARGO SHIPS YOU CAN SEE (migration 0310): the red-first proof. LOCAL ONLY (PGlite); not in CI.
// ═════════════════════════════════════════════════════════════════
//
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/cargo-ships/proof-0310.mjs
//
// Restores the cached world at head 0309 (never from zero), then applies 0310 to it several times inside rolled-back transactions:
//   MUTATION CONTROLS - deliberate breakages of the file, each required to FAIL its self-assert for the intended reason;
//   POSITIVE CONTROL  - the real file, which must pass and print its receipt.
// The harness reads the migration from supabase/migrations; it does not edit it.

import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { migrationFiles, MIGRATIONS_DIR, PREFIX_CACHE_DIR, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'

const NAME = '20260818000310_cargo_ships_you_can_see.sql'
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
  return sql.replace(from, () => to)
}

const BEFORE_ASSERT = `  -- ── 3. THE SELF-ASSERT: hunks, grants, nothing else moved ──\n`
const addBeforeAssert = (s, sql) => swap(s, BEFORE_ASSERT, `${sql}\n${BEFORE_ASSERT}`)
const ROSTER_KIND = `           || case when h.kind is null then '{}'::jsonb else jsonb_build_object('kind', h.kind) end   -- 0310: on a cargo ship alone\n`
const TRAFFIC_KIND = `           || case when pick.kind is null then '{}'::jsonb else jsonb_build_object('kind', pick.kind) end   -- 0310: on a cargo ship alone\n`
const DOOR = `    from public.cargo_ships c\n$body$\n  $f$;\n  revoke all on function public.sea_houses()`

const MUTATIONS = [
  ['a merchant row gains a kind key', (s) => swap(s, ROSTER_KIND, `           || jsonb_build_object('kind', h.kind)\n`),
    /dark, world\.sea_roster is not its pre-image/],
  ['a merchant window row gains a kind key', (s) => swap(s, TRAFFIC_KIND, `           || jsonb_build_object('kind', pick.kind)\n`),
    /dark, world\.sea_traffic is not its pre-image/],
  ['the roster serves no kind', (s) => swap(s, ROSTER_KIND, ``), /does not serve the ships and the merchants/],
  ['the window serves no kind', (s) => swap(s, TRAFFIC_KIND, ``), /is not honest about her/],
  ['no cargo ship in the houses', (s) => swap(s, DOOR, `    from public.cargo_ships c where false\n$body$\n  $f$;\n  revoke all on function public.sea_houses()`),
    /does not serve the ships and the merchants/],
  ['her row has no ink', (s) => swap(s, `order by count(*) desc, m.ink limit 1), 'east'),`, `order by count(*) desc, m.ink limit 1), null),`),
    /her row is not whole/],
  ['the journal still counts her a merchant', (s) => swap(s, `      select p.is_npc and not exists (select 1 from public.cargo_ships c where c.player_id = p.id) into v_npc from public.players p   -- 0310: a cargo ship is at sea, and no merchant\n`,
    `      select p.is_npc into v_npc from public.players p   -- 0310: a cargo ship is at sea, and no merchant\n`), /journalled as a merchant/],
  ['the card answers for any fleet', (s) => swap(s, `  if c.fleet_id is null then\n    raise exception 'E_NOT_FOUND: there is no such cargo ship' using errcode = 'P0001';\n  end if;\n`, ``),
    /the card answered for another fleet|violates|null value/],
  ['the card serves a ship id', (s) => swap(s, `world.ship_view(s.id) - array['id', 'water_t', 'food_t'] order by s.is_flagship desc, s.name), '[]'::jsonb)\n                from public.ships s where s.fleet_id = p_fleet));`,
    `world.ship_view(s.id) order by s.is_flagship desc, s.name), '[]'::jsonb)\n                from public.ships s where s.fleet_id = p_fleet));`), /the card is not whole/],
  ['the card is open to anon', (s) => swap(s, `  grant execute on function world.cargo_ship_card(uuid) to authenticated;\n`, `  grant execute on function world.cargo_ship_card(uuid) to authenticated, anon;\n`),
    /not exactly authenticated-only/],
  ['the card is not registered', (s) => swap(s, `      ('world',       'cargo_ship_card',       'uuid'),\n`, ``), /is not registered/],
  ['a helper is open to clients', (s) => swap(s, `  revoke all on function public.funds_on_way(uuid) from public, anon, authenticated;\n`, `  grant execute on function public.funds_on_way(uuid) to authenticated;\n`),
    /a client can reach a helper/],
  ['funds on the way ignores what the city lacks', (s) => swap(s, `least(a.aboard, public.city_aid_target(p_port) - public.treasury_balance(p_port)) as give`, `a.aboard as give`),
    /at her next stop/],
  ['funds on the way counts stops wrong', (s) => swap(s, `l.ord - c.leg - (case when w.status = 'SAILING' then 0 else 1 end) as stops`, `l.ord as stops`),
    /at her next stop/],
  ['funds on the way promises the capital', (s) => swap(s, `and c.home_port_id = public.city_capital(p_port) and c.home_port_id <> p_port`, `and c.home_port_id = public.city_capital(p_port)`),
    /at her own capital/],
  ['the hall does not serve it', (s) => swap(s, `    || public.town_hall_people(p_port)\n    -- 0310: what a cargo ship is bringing this city, served only while one is.\n    || public.funds_on_way(p_port);\n`, `    || public.town_hall_people(p_port);\n`),
    /occurs 0 time|the hall does not serve/],
  ['stats_now has no figures', (s) => swap(s, `  select case when exists (select 1 from public.cargo_ships)\n              then jsonb_build_object('cargo_ships'`, `  select case when false\n              then jsonb_build_object('cargo_ships'`),
    /does not serve the figures/],
  ['dark, stats_now gains a key', (s) => swap(s, `              else '{}'::jsonb end\n$body$`, `              else '{"cargo_ships":0}'::jsonb end\n$body$`),
    /dark, world\.stats_now is not its pre-image/],
  ['a hunk against another body', (s) => swap(s, `$h$    || public.town_hall_people(p_port);\n$h$,\n$h$'counted_at'`, `$h$    || public.town_hall_people(p_port) ;\n$h$,\n$h$'counted_at'`),
    /occurs 0 time/],
  ['a live function was touched', (s) => addBeforeAssert(s,
    `  execute replace(replace(pg_get_functiondef('public.crown_call_room(uuid)'::regprocedure), E'\\r', ''), 'select greatest(0,', 'select greatest(0 ,');`),
    /another function moved/],
  ['a live knob was touched', (s) => addBeforeAssert(s, `  update public.world_config set value = to_jsonb(21) where key = 'crown_call_cover';`),
    /a world_config row moved/],
  ['the file ships lit', (s) => addBeforeAssert(s, `  update public.world_config set value = 'true'::jsonb where key = 'convoys_enabled';`),
    /a world_config row moved|not dark and empty/],
  ['a live word was touched', (s) => addBeforeAssert(s, `  update public.stats_flow_words set word = 'Crown money' where kind = 'CROWN_AID';`),
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
