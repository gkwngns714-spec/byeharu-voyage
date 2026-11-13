// proof-0375.mjs - LOCAL ONLY (PGlite, the cached world before 0375; never from zero; nothing is written to the cache). THE LIGHTING FILE'S GUARD, CASE BY CASE.
//
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/attacks/proof-0375.mjs [--file=<path to 0375, when it is not in supabase/migrations>] [--proofs]
//
// 0375 lights attack_enabled and refuses unless public.attack_ready() (0374) says ready. Each case restores the world at head 0374, lays a scene, and applies the REAL file:
//   1  the chain's own world (no cargo ship sails: nothing to protect)                        APPLIES      (this is CI's world and the shipped image's)
//   2  cargo ships sail, nothing lit (the old unarmed hull, no regard, no navy)                REFUSES
//   3  scene-lived.sql: production as it will be (regard, crown level, armed cargo, navy)      APPLIES
//   4..7  that world with ONE switch off: regard, the crown level, the armed cargo ship, navy  REFUSES, each naming its reason
//   8  that world with the crown level lit but not written on the hulls                        REFUSES
//   9  that world with 3 of its 10 cargo ships at sea in the old unarmed hull (30 %)           REFUSES
//   10 that world with 1 of 10 unarmed at sea (10 %: at the threshold)                         APPLIES
//   11 that world with the loot rule of 0374 off (loot_risk_full 0)                            REFUSES
//   12 that world with attacks already lit                                                     REFUSES
//   13 applied twice                                                                           the second REFUSES
// After every APPLIES: attack_on() is true, the news row is there once in English and Korean, no probe company is left, and every other world_config row is as it was.
// After every REFUSES: attack_on() is what it was and no news row is written (the file is one transaction).
// --proofs then runs proof 75 on case 3's world (0375 applied on the lived world), under 10 other worlds' dice.
import { readFile, readdir } from 'node:fs/promises'
import path from 'node:path'
import { MIGRATIONS_DIR, PREFIX_CACHE_DIR, migrationFiles, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'

const arg = (k) => process.argv.find((a) => a.startsWith(`--${k}=`))?.slice(k.length + 3) ?? null
const NAME = '20260818000375_'
const here = path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'))
const filePath = arg('file') ?? path.join(MIGRATIONS_DIR, (await readdir(MIGRATIONS_DIR)).find((f) => f.startsWith(NAME)) ?? 'missing')
const FILE = (await readFile(filePath, 'utf8')).replaceAll('\r', '')
const LIVED = (await readFile(path.join(here, 'scene-lived.sql'), 'utf8')).replaceAll('\r', '')
const files = []
for (const name of await migrationFiles()) {
  if (name >= NAME) continue
  files.push({ name, sql: await readFile(path.join(MIGRATIONS_DIR, name), 'utf8') })
}
const world = async () => (await applyWithPrefixCache({ variant: await preambleVariant(), files, cacheDir: PREFIX_CACHE_DIR, log: () => {}, required: process.env.BYEHARU_PREFIX_CACHE === 'required', snapshots: false })).db

const OLD_HULL = (n) => `update public.ships s set class_id = (select c.id from public.ship_classes c where c.code = public.wc_text('convoy_ship_class'))
  where s.fleet_id in (select x.fleet_id from public.cargo_ships x join public.fleets f on f.id = x.fleet_id where f.status = 'SAILING' order by x.nation_id, x.ord limit ${n});`
const CASES = [
  ['1 the chain\'s own world: no cargo ship sails', '', true, null],
  ['2 cargo ships sail, nothing lit', `update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'convoys_enabled');
     insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
     select public.tick_cargo_ships(now(), g.nation_id) from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'ESP';`, false, /regard_enabled is off/],
  ['3 production as it will be (scene-lived.sql)', LIVED, true, null],
  ['4 regard off', `${LIVED} update public.world_config set value = 'false'::jsonb where key = 'regard_enabled';`, false, /regard_enabled is off/],
  ['5 the crown level off', `${LIVED} update public.world_config set value = 'false'::jsonb where key = 'npc_ship_level_enabled';`, false, /npc_ship_level_enabled is off/],
  ['6 the armed cargo ship off', `${LIVED} update public.world_config set value = 'false'::jsonb where key = 'convoy_armed_enabled';`, false, /convoy_armed_enabled is off/],
  ['7 the navy off', `${LIVED} update public.world_config set value = 'false'::jsonb where key = 'navy_enabled';`, false, /navy_enabled is off/],
  ['8 the crown level lit, not written', `${LIVED} delete from public.ship_xp e using public.ships s join public.cargo_ships x on x.fleet_id = s.fleet_id where e.ship_id = s.id;`, false, /level is not written yet/],
  ['9 three of ten at sea unarmed', `${LIVED} ${OLD_HULL(3)}`, false, /3 of the 10 cargo ships at sea are unarmed/],
  ['10 one of ten at sea unarmed (the threshold)', `${LIVED} ${OLD_HULL(1)}`, true, null],
  ['11 the loot rule of 0374 off', `${LIVED} update public.world_config set value = '0'::jsonb where key = 'loot_risk_full';`, false, /the loot rule of 0374 is off/],
  ['12 attacks already lit', `${LIVED} update public.world_config set value = 'true'::jsonb where key = 'attack_enabled';`, false, /attack_enabled is already on/],
]
let bad = 0
const t0 = Date.now()
for (const [label, scene, wantApplies, wantText] of CASES) {
  const db = await world()
  if (scene) await db.exec(scene)
  const before = (await db.query(`select public.attack_on() as lit, md5(string_agg(c.key || c.value::text, ',' order by c.key)) as cfg from public.world_config c where c.key <> 'attack_enabled'`)).rows[0]
  let err = null
  try { await db.exec(FILE) } catch (e) { err = e.message }
  const after = (await db.query(`select public.attack_on() as lit, md5(string_agg(c.key || c.value::text, ',' order by c.key)) as cfg,
      (select count(*)::int from public.world_news n where n.key = 'update:0375') as news,
      (select n.detail #>> '{words,title,en}' from public.world_news n where n.key = 'update:0375') as en, (select n.detail #>> '{words,title,ko}' from public.world_news n where n.key = 'update:0375') as ko,
      (select count(*)::int from public.players p where p.company_name like 'Probe 0375%') as probes
    from public.world_config c where c.key <> 'attack_enabled'`)).rows[0]
  let verdict
  if (wantApplies) {
    const ok = !err && after.lit === true && after.news === 1 && after.en && after.ko && after.probes === 0 && after.cfg === before.cfg
    verdict = ok ? `APPLIES: lit, news once ("${after.en}" / "${after.ko}"), no probe left, no other knob moved` : `WRONG: wanted it to apply: ${err ?? JSON.stringify(after)}`
    if (!ok) bad += 1
    if (ok && label.startsWith('3')) {
      // 13: applied twice
      let again = null
      try { await db.exec(FILE) } catch (e) { again = e.message }
      const twice = again && /already on/.test(again) && (await db.query(`select count(*)::int n from public.world_news where key = 'update:0375'`)).rows[0].n === 1
      console.log(`13 applied twice | ${twice ? 'REFUSES the second time, one news row' : `WRONG: ${again}`}`)
      if (!twice) bad += 1
    }
  } else {
    const ok = err && wantText.test(err) && after.lit === before.lit && after.news === 0 && after.cfg === before.cfg
    verdict = ok ? `REFUSES: ${err.slice(0, 150).replace(/\s+/g, ' ')}` : `WRONG: wanted a refusal matching ${wantText}: ${err ?? 'it applied'}`
    if (!ok) bad += 1
  }
  console.log(`${label} | ${verdict}`)
  await db.close()
}
console.log(bad === 0 ? `all ${CASES.length + 1} cases as wanted, ${((Date.now() - t0) / 1000).toFixed(0)} s` : `${bad} case(s) WRONG`)
process.exit(bad === 0 ? 0 : 1)
