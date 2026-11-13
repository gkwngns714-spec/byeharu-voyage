// sim.mjs - LOCAL ONLY (PGlite, the cached world, the whole chain as it stands; never from zero; not in CI; it opens no network connection).
// THE ATTACK SIM ON WHAT REALLY SAILS (owner row 324; docs/COMBAT_LOG.md 3.6, R11): who wins when a company attacks a cargo ship, a navy ship or a pirate ship, what it earns and what it costs.
//
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/attacks/sim.mjs [--seeds=400] [--aboard=100000,400000] [--md] [--only=<attacker label words>]
//
// EVERY HULL IS A REAL SHIP OF THE WORLD, made by the game's own hands in one transaction that is rolled back:
//   the attackers   public.new_house + public.commission_ship (a new company: level 1, no captain, no gear, no skill), each hull at her full complement (the best case for the attacker);
//   the cargo ships public.tick_cargo_ships with convoy_armed_enabled lit (the armed navire, 0328) and dark (the old crewless qpinnace), FIVE of each so one hull's roll is not the answer;
//                   her hands are then set to 100 %, 50 %, 25 % and 0 % of her crew_required (what public.fleet_hands gives her when the quay has them, and when it has not);
//   the navy ships  public.navy_commission; the pirate ships as proof 48 makes them (public.form_fleet + public.commission_ship + a pirate_ships row); both crewed to crew_required, as a departure crews them;
//   level 5         npc_ship_level_enabled lit and public.crown_hull_level_fix run (0344): the same hulls read again.
// Each side is then read by voyage.fleet_hulls, THE reading public.battle_sheet_freeze writes to a battle's sheet, and fought by public.fight_sides seeded (a uuid, 1) with no order: exactly
// public.battle_fight's call for a battle where nobody changes stance. THE NAVY'S ANSWER is a called ship on the sheet with `from` = 3 (she comes up for round 3), as public.battle_advance joins her.
// The dice are this desk's world_secret: other worlds roll otherwise, so the shares move by a few points. Hundreds of seeds a cell.
//
// What a cell prints: won % (boarded + paid off: what pays gold), the attacker's hull lost (share and points), the share of fights that cost her hands (beaten or broke off: attack_crew_lost.beaten of her crew),
// the loot of one battle at each --aboard figure under loot_share, ransom_share and loot_per_ship, the ducats the battle costs her (repair by public.fleet_repair_cost's rate + hands at hire_crew_rate),
// and how many battles fill loot_per_company_day.
import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { MIGRATIONS_DIR, PREFIX_CACHE_DIR, migrationFiles, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'

const arg = (k, d) => process.argv.find((a) => a.startsWith(`--${k}=`))?.slice(k.length + 3) ?? d
const SEEDS = Number(arg('seeds', '400'))
const ABOARD = arg('aboard', '100000,400000').split(',').map(Number)
const ONLY = arg('only', '')
const BEFORE = arg('before', null)   // --before=20260818000374 : the chain without a later file (the sim before a fix)
const files = []
for (const name of await migrationFiles()) {
  if (BEFORE && name >= BEFORE) continue
  files.push({ name, sql: await readFile(path.join(MIGRATIONS_DIR, name), 'utf8') })
}
const t0 = Date.now()
const out = await applyWithPrefixCache({ variant: await preambleVariant(), files, cacheDir: PREFIX_CACHE_DIR, log: () => {}, required: process.env.BYEHARU_PREFIX_CACHE === 'required', snapshots: false })
const db = out.db
if ((await db.query(`select inet_server_addr() is not null as real`)).rows[0].real) throw new Error('local PGlite world only: this sim writes')
console.log(`world: head ${files.at(-1).name.slice(0, 18)}, ${out.restored} of ${files.length} restored, ${((Date.now() - t0) / 1000).toFixed(1)} s; ${SEEDS} seeds a cell`)

// the fleets a new, a mid and a rich company would own (codes of public.ship_classes; build cost in the label)
const ATTACKERS = [
  ['new: 1 Barca (no guns)', ['barca']],
  ['new: 1 Kobaya (70k, the cheapest warship)', ['kobaya']],
  ['mid: 1 Haringbuis (120k, armed trader)', ['buss']],
  ['mid: 2 Haringbuis', ['buss', 'buss']],
  ['mid: 1 xebec (160k)', ['xebec']],
  ['mid: 2 xebecs', ['xebec', 'xebec']],
  ['mid: 1 Nau (600k)', ['nau']],
  ['rich: 2 Galion (2 x 1,156k)', ['galion', 'galion']],
  ['rich: 1 Great Galley (0366 gunship)', ['greatgalley']],
  ['rich: 1 Nef (0366 line ship)', ['nef']],
  ['rich: Great Galley + Nef', ['greatgalley', 'nef']],
  ['rich: 2 Nau capitania (0366 line, tier 5)', ['naucap', 'naucap']],
].filter(([label]) => !ONLY || ONLY.split(',').some((w) => label.includes(w)))

await db.exec('begin')
await db.exec(`
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'convoys_enabled', 'navy_enabled');
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set ducats = 500000000, reserve = 0;
  create temp table sim_side (tag text, k int, fleet uuid, sheet jsonb);
`)
const q = async (s, p = []) => (await db.query(s, p)).rows
const nation = async (code) => (await q(`select g.nation_id as id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = $1`, [code]))[0].id
const ESP = await nation('ESP')
const FRA = await nation('FRA')

// the old hull (dark) in France, the armed hull (lit) in Spain: five of each
for (let i = 0; i < 2; i++) await q(`select public.tick_cargo_ships(now(), $1::uuid)`, [FRA])
await db.exec(`update public.world_config set value = 'true'::jsonb where key = 'convoy_armed_enabled'`)
for (let i = 0; i < 2; i++) await q(`select public.tick_cargo_ships(now(), $1::uuid)`, [ESP])
const cargo = async (nat) => q(`select c.fleet_id, k.code, k.crew_required, k.attack from public.cargo_ships c join public.ships s on s.fleet_id = c.fleet_id join public.ship_classes k on k.id = s.class_id where c.nation_id = $1 order by c.ord limit 5`, [nat])
const armed = await cargo(ESP)
const old = await cargo(FRA)
if (armed.length < 5 || old.length < 5 || armed.some((r) => r.code !== 'navire') || old.some((r) => r.code !== 'qpinnace')) throw new Error(`the cargo ships are not as expected: ${JSON.stringify([armed, old])}`)

// navy ships of Spain and pirate ships, five each, crewed as a departure crews them
await db.exec(`
  do $$
  declare
    v_nat uuid := '${ESP}';
    v_cap uuid := public.realm_capital('${ESP}');
    v_pir uuid := (select n.id from public.nations n where n.code = 'PIR');
    v_pl  uuid;
    v_f   uuid;
    i     int;
  begin
    insert into public.navy_realms (nation_id, ships, read_at) values (v_nat, 25, now()) on conflict (nation_id) do update set ships = 25, read_at = now();
    for i in 1 .. 5 loop
      v_f := public.navy_commission(v_nat, 100 + i, v_cap, public.refit_yard(v_cap), v_cap, now());
      insert into sim_side values ('navy', i - 1, v_f, null);
      insert into public.players (company_name, nation_id, ducats, is_npc) values ('Brethren sim ' || i, v_pir, 0, true) returning id into v_pl;
      v_f := public.form_fleet(v_pl, 'Pirate ship sim ' || i, v_cap);
      perform public.commission_ship(v_pl, v_f, public.wc_text('pirate_ship_class'), 'Pirate ship sim ' || i, true, false);
      insert into public.pirate_ships (fleet_id, player_id, ord, home_port, sea_id, mission, haunt_port, last_port, created_at)
      values (v_f, v_pl, 900 + i, (select p.id from public.ports p where p.code = 'POR'), (select p.sea_id from public.ports p where p.id = v_cap), 'CRUISE', v_cap, v_cap, now());
      insert into sim_side values ('pirate', i - 1, v_f, null);
    end loop;
    update public.ships s set crew = c.crew_required from public.ship_classes c where c.id = s.class_id and s.fleet_id in (select fleet from sim_side);
  end $$;
`)
const kinds = await q(`select tag, count(*)::int n, min(public.fleet_kind(fleet)) kind, bool_and(public.crown_house((select f.player_id from public.fleets f where f.id = fleet))) crown from sim_side group by tag order by tag`)
console.log('targets made:', JSON.stringify(kinds), `cargo ${armed[0].code} (crew_required ${armed[0].crew_required}), old ${old[0].code}`)

// the attackers
let n = 0
const attackers = []
for (const [label, codes] of ATTACKERS) {
  n += 1
  const uid = `00000000-0375-4000-8000-${String(n).padStart(12, '0')}`
  await q(`select public.new_house($1::uuid, $2, 'PRT', 'LIS', $3, $4, $3, null, false)`, [uid, `Sim house ${n}`, `Sim fleet ${n}`, codes[0]])
  const fleet = (await q(`select f.id from public.fleets f join public.players p on p.id = f.player_id where p.auth_uid = $1::uuid`, [uid]))[0].id
  for (const [i, code] of codes.slice(1).entries()) await q(`select public.commission_ship(f.player_id, f.id, $2, $3, false, true) from public.fleets f where f.id = $1`, [fleet, code, `Sim hull ${n}.${i + 2}`])
  // her full complement: a company that means to board fills her
  await q(`update public.ships s set crew = (select b.crew_max from public.ship_base(s.id) b) where s.fleet_id = $1`, [fleet])
  const info = (await q(`select voyage.fleet_hulls($1) as sheet, (select coalesce(sum(world.ship_stat(s.id, 'attack')), 0) from public.ships s where s.fleet_id = $1) as guns,
                                (select sum(s.crew)::int from public.ships s where s.fleet_id = $1) as crew, (select sum(s.durability)::int from public.ships s where s.fleet_id = $1) as hull,
                                (select sum(c.build_cost)::bigint from public.ships s join public.ship_classes c on c.id = s.class_id where s.fleet_id = $1) as cost,
                                public.fleet_repair_cost($1, 1000) / 1000.0 as repair_point`, [fleet]))[0]
  attackers.push({ label, fleet, ...info, guns: Number(info.guns), repair_point: Number(info.repair_point) })
}
const HIRE = Number((await q(`select public.wc_num('hire_crew_rate') v`))[0].v)
const BEATEN = Number((await q(`select (public.wc('attack_crew_lost')->>'beaten')::numeric v`))[0].v)
const CAPS = (await q(`select public.wc_num('loot_share') as share, public.wc_num('ransom_share') as ransom, public.wc_num('loot_per_ship') as ship, public.wc_num('loot_per_company_day') as "day", public.wc_int('attack_cooldown_minutes') as wait`))[0]
// 0374: loot follows the risk taken (public.loot_risk: the share of her own hull the attacker lost in THIS fight). Before that file every won fight paid the whole share.
const RISK = (await q(`select to_regprocedure('public.loot_risk(jsonb)') is not null as there`))[0].there ? 'public.loot_risk(f.f)' : '1'
console.log(`loot rule: ${RISK === '1' ? '0327 (every won fight pays the whole share)' : `0374, loot_risk_full ${(await q(`select public.wc('loot_risk_full') v`))[0].v}, loot_risk_floor ${(await q(`select public.wc('loot_risk_floor') v`))[0].v}`}`)

/** The target sheets of one level: tag -> [five sheets]. */
async function sheets() {
  const s = {}
  const read = async (fleets) => { const r = []; for (const f of fleets) r.push((await q(`select voyage.fleet_hulls($1) h`, [f]))[0].h); return r }
  for (const pct of [100, 50, 25, 0]) {
    await q(`update public.ships s set crew = round(c.crew_required * $2::numeric / 100) from public.ship_classes c where c.id = s.class_id and s.fleet_id = any($1::uuid[])`, [armed.map((r) => r.fleet_id), pct])
    s[`armed navire, ${pct === 100 ? 'full crew (60)' : pct === 0 ? 'no hands' : `${pct} % crew`}`] = await read(armed.map((r) => r.fleet_id))
  }
  s['old unarmed pinnace, no hands'] = await read(old.map((r) => r.fleet_id))
  s['navy ship (galion)'] = await read((await q(`select fleet from sim_side where tag = 'navy' order by k`)).map((r) => r.fleet))
  s['pirate ship (xebec)'] = await read((await q(`select fleet from sim_side where tag = 'pirate' order by k`)).map((r) => r.fleet))
  return s
}

async function cell(tag, b, targets, navy) {
  // a called navy ship comes up for round 3, as public.battle_advance joins her (`from`, `fleet`)
  const sides = targets.map((t, i) => (navy ? [...t, ...navy[i % navy.length].map((h) => ({ ...h, from: 3, fleet: '00000000-0000-4000-8000-000000000333' }))] : t))
  const r = (await q(`
    with f as materialized (select public.fight_sides(md5($1 || ':' || i)::uuid, 1, ($2::jsonb) -> (i % $4::int), $3::jsonb, '{}'::jsonb) as f from generate_series(1, $5::int) i)
    select count(*) filter (where f->>'outcome' = 'PLUNDERED')::int as boarded, count(*) filter (where f->>'outcome' = 'RANSOM')::int as paid,
           count(*) filter (where f->>'outcome' = 'PLUNDERED' and coalesce((f #>> '{board,surrender}')::boolean, false))::int as struck,
           count(*) filter (where f->>'outcome' = 'DRIVEN_OFF' or coalesce((f->>'broke_off')::boolean, false))::int as beaten,
           count(*) filter (where f->>'outcome' = 'EVADED' and not coalesce((f->>'broke_off')::boolean, false))::int as slipped,
           avg((f->'hull'->>'b_start')::numeric - (f->'hull'->>'b')::numeric)::float8 as b_lost, avg(((f->'hull'->>'b_start')::numeric - (f->'hull'->>'b')::numeric) / (f->'hull'->>'b_start')::numeric)::float8 as b_share,
           max(((f->'hull'->>'b_start')::numeric - (f->'hull'->>'b')::numeric) / (f->'hull'->>'b_start')::numeric)::float8 as b_worst,
           avg(((f->'hull'->>'a_start')::numeric - (f->'hull'->>'a')::numeric) / nullif((f->'hull'->>'a_start')::numeric, 0))::float8 as a_share,
           count(*) filter (where (f->'hull'->>'a')::numeric <= 0)::int as sunk,
           avg(case when f->>'outcome' in ('PLUNDERED', 'RANSOM') then ${RISK.replace('f.f', 'f')} end)::float8 as part,
           (select jsonb_object_agg(a.a::text, (select avg(public.loot_due(f.f->>'outcome', floor(a.a * ${RISK})::bigint, 0))::float8 from f)) from unnest($6::bigint[]) a(a)) as loot
      from f`, [tag, JSON.stringify(sides), JSON.stringify(b.sheet), sides.length, SEEDS, ABOARD]))[0]
  return r
}

const pc = (x) => (x * 100).toFixed(1)
const rows = []
for (const level of [1, 5]) {
  await db.exec(`update public.world_config set value = '${level === 5 ? 'true' : 'false'}'::jsonb where key = 'npc_ship_level_enabled'; select public.crown_hull_level_fix();`)
  const s = await sheets()
  const sample = Object.fromEntries(Object.entries(s).map(([k, v]) => [k, v[0][0]]))
  console.log(`\nNPC level ${level}: one hull of each target as the sheet reads her:`)
  for (const [k, h] of Object.entries(sample)) console.log(`  ${k.padEnd(34)} hull ${h.hull}/${h.maxd} crew ${h.crew} attack ${h.attack} accuracy ${h.accuracy} reach ${h.reach} armour ${h.armour} sighting ${h.sighting}`)
  for (const b of attackers) {
    if (b.guns <= 0) { rows.push({ level, attacker: b.label, refused: 'E_NO_GUNS' }); continue }
    for (const [name, targets] of Object.entries(s)) {
      for (const navy of name.startsWith('navy') || name.startsWith('pirate') ? [null] : [null, s['navy ship (galion)']]) {
        const t1 = Date.now()
        const r = await cell(`${level}:${b.label}:${name}:${navy ? 'n' : ''}`, b, targets, navy)
        if (process.env.SIM_PROGRESS) console.error(`  L${level} ${b.label} | ${name} | navy ${navy ? 'yes' : 'no'}: ${Date.now() - t1} ms`)
        const pB = r.boarded / SEEDS, pR = r.paid / SEEDS, pL = r.beaten / SEEDS, pS = r.struck / SEEDS
        const cost = r.b_lost * b.repair_point + pL * Math.floor(b.crew * BEATEN) * HIRE
        const row = { level, attacker: b.label, target: name, navy: navy ? 'comes for round 3' : 'none', won: pc(pB + pR), boarded: pc(pB), struck: pc(pS), part: r.part == null ? '-' : pc(r.part), paid: pc(pR), beaten: pc(pL), slipped: pc(r.slipped / SEEDS),
          herHull: pc(r.a_share ?? 0), sunk: pc(r.sunk / SEEDS), myHull: pc(r.b_share), myWorst: pc(r.b_worst), cost: Math.round(cost), loot: {}, net: {}, fill: {} }
        for (const a of ABOARD) {
          const kind = name.startsWith('navy') || name.startsWith('pirate') ? 0 : 1   // a navy ship and a pirate ship carry no book: public.loot_take answers 0
          const e = kind * Number(r.loot[String(a)] ?? 0)
          row.loot[a] = Math.round(e)
          row.net[a] = Math.round(e - cost)
          row.fill[a] = e > 0 ? Math.ceil(Number(CAPS.day) / e) : null
        }
        rows.push(row)
      }
    }
  }
}
await db.exec('rollback')
await db.close()

console.log(`\nCaps: loot_share ${CAPS.share}, ransom_share ${CAPS.ransom}, loot_per_ship ${CAPS.ship}, loot_per_company_day ${CAPS.day}; one battle a fleet in ${CAPS.wait} minutes (48 a day at most).`)
console.log(`Cost of a battle = hull points lost x the repair rate at Lisbon + (share of fights beaten or broken off) x ${BEATEN * 100} % of her hands x ${HIRE} d. a hand.`)
for (const level of [1, 5]) {
  console.log(`\n## NPC hulls at level ${level}\n`)
  console.log(`| Attacker | Target | Navy | Won % | Boarded | of which she struck | Share of the loot a won fight earns % | Paid off | Beaten | She slipped | Her hull lost % | She sank % | Attacker hull lost % (worst) | Cost d. | ${ABOARD.map((a) => `Loot a battle, ${a / 1000}k aboard | net | battles to the day cap`).join(' | ')} |`)
  console.log(`|---|---|---|---|---|---|---|---|---|---|---|---|---|---|${ABOARD.map(() => '---|---|---|').join('')}`)
  for (const r of rows.filter((x) => x.level === level)) {
    if (r.refused) { console.log(`| ${r.attacker} | any | | refused: ${r.refused} | | | | | | | | | | |${ABOARD.map(() => ' | | |').join('')}`); continue }
    console.log(`| ${r.attacker} | ${r.target} | ${r.navy} | ${r.won} | ${r.boarded} | ${r.struck} | ${r.part} | ${r.paid} | ${r.beaten} | ${r.slipped} | ${r.herHull} | ${r.sunk} | ${r.myHull} (${r.myWorst}) | ${r.cost} | ${ABOARD.map((a) => `${r.loot[a]} | ${r.net[a]} | ${r.fill[a] ?? '-'}`).join(' | ')} |`)
  }
}
// THE VERDICT, by the figures: a cell is "free gold" when the attacker is paid in at least 9 fights of 10 and never loses a twentieth of her hull in any of them
const free = rows.filter((r) => !r.refused && r.loot[ABOARD[0]] >= 0.05 * ABOARD[0] && Number(r.won) >= 90 && Number(r.myWorst) < 5)
const paying = rows.filter((r) => !r.refused && r.net[ABOARD[0]] > 0)
console.log(`\nVERDICT: ${free.length} cell(s) pay at least a twentieth of what is aboard in at least 90 % of fights with never 5 % of the attacker's hull lost (FREE GOLD); ${paying.length} of ${rows.filter((r) => !r.refused).length} cells have a positive expected net at ${ABOARD[0]} aboard.`)
for (const r of free) console.log(`  FREE GOLD: level ${r.level} | ${r.attacker} | ${r.target} | navy ${r.navy} | won ${r.won} % | worst hull lost ${r.myWorst} % | loot ${r.loot[ABOARD[0]]}`)
console.log(`${((Date.now() - t0) / 1000).toFixed(0)} s`)
