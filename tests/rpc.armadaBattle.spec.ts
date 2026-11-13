import { test, expect } from '@playwright/test'
import { openLocalDb, type LocalDb } from '../src/lib/db/localDb'
import { loadChain } from '../src/lib/db/chainSource.node.mjs'
import { builtWorldImage } from './builtWorld.fixture'
import { clearBackend, cmdArmadaForm, cmdAttack, cmdBattleStance, cmdPreviewAttack, createLocalBackend, setBackend, worldBattle, worldFights, worldFleets } from '../src/lib/rpc'
import { fightCountRadiusPx } from '../src/chart/fightRings'
import { parseFightLog } from '../src/live/fightLines'

// ═══════════════════════════════════════════════════════════════════════════════
// AN ARMADA FIGHTS AS ONE, THE SEAM (0395, docs/ARMADA.md section 7, owner row 323): the real doors, through the
// client's one RPC layer, on the built world. Proof 69 proves the server's rules under any dice. This proves the client
// reads what the server serves: dark, the dry run refuses and nothing is read; lit, the dry run names the armada and
// her fleets, the press opens ONE battle that every fleet of hers reads, the map's read counts each fleet (so the ring
// grows), one Flee is the stance both fleets read, and closed, each fleet's share is served and adds up.
// NOTHING HERE ASSERTS ONE OUTCOME OF A FIGHT: every built world has its own dice (0031).
// The rounds are brought due by calling the server's own closer at a later instant (the minute job's call).
// ═══════════════════════════════════════════════════════════════════════════════

let db: LocalDb
let fleet: string
let sister: string
let target: string
let battle: string

const SISTER = 'Guarda da Costa Dourada.'
const ARMADA = 'Armada Real do Mar Largo'

const light = (keys: string[], on: boolean) =>
  db.callAs(`with lit as (update public.world_config set value = $2::jsonb where key = any($1::text[]) returning 1) select count(*)::int as result from lit`, [keys, on ? 'true' : 'false'])
// the job's call, as if `secs` seconds of the battle had passed
const tickAt = (secs: number) =>
  db.callAs<boolean>(`select public.battle_resolve(b.id, b.started_at + make_interval(secs => $2)) as result from public.battles b where b.id = $1`, [battle, secs])

test.beforeAll(async () => {
  test.setTimeout(360_000)
  db = await openLocalDb({ loadChain, loadImage: builtWorldImage, dataDir: 'memory://', log: () => {} })
  setBackend(createLocalBackend(db))
  await db.callAs(`select cmd.found_house('Armada Battle Spec', 'PRT') as result`)
  await db.callAs(`with t as (update public.port_treasury set ducats = 50000000, reserve = 0 returning 1) select count(*)::int as result from t`)
  await light(['city_treasury_enabled', 'convoys_enabled'], true)
  // the attack's reach is 0327's gate and not what is read here: her armada lies in her own port and the ship is at sea off another
  await db.callAs(`with k as (update public.world_config set value = '100000'::jsonb where key = 'attack_reach_nm' returning 1) select count(*)::int as result from k`)
  const realm = await db.callAs<string>(`select g.nation_id as result from public.great_powers g join public.nations n on n.id = g.nation_id where n.code <> 'PRT' order by n.code limit 1`)
  for (let i = 0; i < 3; i++) await db.callAs(`select public.tick_cargo_ships(now(), $1::uuid) is null as result`, [realm])
  target = await db.callAs<string>(`select c.fleet_id as result from public.cargo_ships c where c.nation_id = $1 and c.ord = 1`, [realm])
  await db.callAs(
    `select public.convoy_book('LOADED', c.fleet_id, c.player_id, c.home_port_id, 100000) is null, public.cargo_ship_step(c.fleet_id, now()) as result from public.cargo_ships c where c.fleet_id = $1`,
    [target],
  )
  const fleets = await worldFleets()
  expect(fleets.ok).toBe(true)
  if (!fleets.ok) return
  fleet = fleets.value[0].id
  // her fleet becomes a warship with an empty hold, and a second fleet of hers is made beside her in the same port (the
  // hands every fleet is made by: public.form_fleet, public.commission_ship), a lesser warship
  sister = await db.callAs<string>(
    `with g as (update public.ships set class_id = (select c.id from public.ship_classes c order by c.attack desc, c.code limit 1), cargo = '{}'::jsonb where fleet_id = $1 returning 1),
          f as (select public.form_fleet(x.player_id, $2, x.port_id) as id, x.player_id from public.fleets x where x.id = $1),
          s as (select public.commission_ship(f.player_id, f.id, (select c.code from public.ship_classes c where c.attack > 0 order by c.attack desc, c.code offset 1 limit 1), 'Guarda', true, true) as ship, f.id from f)
     select s.id as result from s, (select count(*) from g) n`,
    [fleet, SISTER],
  )
  expect(sister).toBeTruthy()
})

test.afterAll(async () => {
  clearBackend()
  await db?.close()
})

test('the armada is formed by her own door; dark, the dry run refuses and neither fleet reads a battle', async () => {
  // the shipped world has attacks LIT since 0375: this test is the other arm, the owner's switch off
  await light(['attack_enabled'], false)
  const formed = await cmdArmadaForm([fleet, sister], ARMADA)
  expect(formed.ok, JSON.stringify(formed)).toBe(true)
  const dry = await cmdPreviewAttack(fleet, target)
  expect(dry.ok).toBe(false)
  if (!dry.ok) expect(dry.refusal.code).toBe('E_NOT_IN_USE')
  for (const f of [fleet, sister]) {
    const read = await worldBattle(f)
    expect(read.ok, JSON.stringify(read)).toBe(true)
    if (read.ok) expect(read.value).toEqual({ on: false })
  }
  expect(await db.callAs<number>(`select (select count(*) from public.battles)::int + (select count(*) from public.battle_sides)::int as result`)).toBe(0)
})

test('lit: the dry run names the armada and her fleets and leaves no trace; a sister with cargo refuses it under her own name', async () => {
  await light(['attack_enabled'], true)
  const dry = await cmdPreviewAttack(fleet, target)
  expect(dry.ok, JSON.stringify(dry)).toBe(true)
  if (!dry.ok) return
  expect(dry.value.armada?.name).toBe(ARMADA)
  expect(dry.value.armada?.fleets.length).toBe(2)
  expect(dry.value.armada?.fleets[1]).toBe(SISTER)
  expect(dry.value.armada?.ships).toBe(2)
  expect(['weaker', 'even', 'stronger', 'far_stronger']).toContain(dry.value.word)
  expect(await db.callAs<number>(`select (select count(*) from public.battles)::int + (select count(*) from public.battle_sides)::int as result`)).toBe(0)
  // by her sister's press it is the same armada, the sister first
  const other = await cmdPreviewAttack(sister, target)
  expect(other.ok && other.value.armada?.fleets[0]).toBe(SISTER)
  expect(other.ok && other.value.word).toBe(dry.value.word)
  // one tun in her sister's hold: the whole attack is refused, in words that name the sister
  const good = await db.callAs<string>(`select g.code as result from public.goods g where g.bulk = 1 order by g.code limit 1`)
  await db.callAs(`with u as (update public.ships set cargo = jsonb_build_object($2::text, 1) where fleet_id = $1 returning 1) select count(*)::int as result from u`, [sister, good])
  const laden = await cmdPreviewAttack(fleet, target)
  expect(laden.ok).toBe(false)
  if (!laden.ok) {
    expect(laden.refusal.code).toBe('E_HOLD_NOT_EMPTY')
    expect(laden.refusal.sentence).toContain(SISTER)
  }
  const press = await cmdAttack(fleet, target, null)
  expect(!press.ok && press.refusal.code).toBe('E_HOLD_NOT_EMPTY')
  await db.callAs(`with u as (update public.ships set cargo = '{}'::jsonb where fleet_id = $1 returning 1) select count(*)::int as result from u`, [sister])
  expect(await db.callAs<number>(`select count(*)::int as result from public.battles`)).toBe(0)
})

test('the press opens ONE battle: both fleets read it with her fleets named, the map counts three fleets, and one Flee is the stance of both', async () => {
  const hit = await cmdAttack(fleet, target, null)
  expect(hit.ok, JSON.stringify(hit)).toBe(true)
  if (!hit.ok) return
  battle = hit.value.battle_id as string
  expect(hit.value.armada?.name).toBe(ARMADA)
  const [mine, hers] = [await worldBattle(fleet), await worldBattle(sister)]
  expect(mine.ok && hers.ok, JSON.stringify([mine, hers])).toBe(true)
  if (!mine.ok || !hers.ok) return
  for (const b of [mine.value, hers.value]) {
    expect(b.on).toBe(true)
    expect(b.battle).toBe(battle)
    expect(b.status).toBe('FIGHTING')
    expect(b.armada).toBe(ARMADA)
    expect(b.lead).toBe(fleet)
    expect(b.stance).toBe('FIGHT')
    expect(b.may).toEqual(['FIGHT', 'FLEE'])
    expect(b.word).toBe(hit.value.word)
    expect(b.fleets?.map((f) => [f.id, f.lead, f.ships])).toEqual([[fleet, true, 1], [sister, false, 1]])
    expect(b.fleets?.[1].name).toBe(SISTER)
    expect(b.shares).toBeUndefined()
    // the log is the one FightLog's: her two hulls under their two fleets
    const log = parseFightLog(b.log, { open: true })
    expect(log, JSON.stringify(b.log)).not.toBeNull()
    expect(log?.you.length).toBe(2)
    expect(log?.fleets?.map((f) => f.ships)).toEqual([1, 1])
    expect(log?.fleets?.[1].name).toBe(SISTER)
  }
  // both of her fleets are held for it
  const fleets = await worldFleets()
  expect(fleets.ok && fleets.value.filter((f) => f.status === 'IN_BATTLE').map((f) => f.id).sort()).toEqual([fleet, sister].sort())
  // THE MAP'S READ: every fleet that is there is counted, so the ring is the size of three fleets, not two
  const map = await worldFights()
  expect(map.ok, JSON.stringify(map)).toBe(true)
  if (!map.ok) return
  const card = map.value.fights.find((f) => f.id === battle)
  expect(card, JSON.stringify(map.value)).toBeTruthy()
  if (!card) return
  expect(card.size).toBe(3)
  expect(card.fleets).toBe(3)
  expect(card.mine).toBe(fleet)
  expect(card.sides.filter((s) => s.side === 'ATTACKER').map((s) => [s.fleet, s.how, s.here])).toEqual([[fleet, 'OPENED', true], [sister, 'ARMADA', true]])
  expect(fightCountRadiusPx(card.size as number)).toBeGreaterThan(fightCountRadiusPx(2))
  // ONE STANCE FOR THE SIDE: Flee, pressed once, is what both fleets' cards read, and it is one row
  const flee = await cmdBattleStance(battle, 'FLEE')
  expect(flee.ok, JSON.stringify(flee)).toBe(true)
  const [a, b] = [await worldBattle(fleet), await worldBattle(sister)]
  expect(a.ok && a.value.stance).toBe('FLEE')
  expect(b.ok && b.value.stance).toBe('FLEE')
  expect(await db.callAs<number>(`select count(*)::int as result from public.battle_stances where battle_id = $1`, [battle])).toBe(1)
  // and Fight again, for all of them
  const fight = await cmdBattleStance(battle, 'FIGHT')
  expect(fight.ok).toBe(true)
  const again = await worldBattle(sister)
  expect(again.ok && again.value.stance).toBe('FIGHT')
})

test('closed: both fleets are free, each fleet has her share, the shares add up to the loot and the hands lost, and the log still names her fleets', async () => {
  await tickAt(3600)
  expect(await tickAt(3600)).toBe(false)
  const [mine, hers] = [await worldBattle(fleet), await worldBattle(sister)]
  expect(mine.ok && hers.ok).toBe(true)
  if (!mine.ok || !hers.ok) return
  const done = mine.value
  expect(['RESOLVED', 'BROKEN_OFF']).toContain(done.status)
  expect(hers.value.status).toBe(done.status)
  expect(hers.value.shares).toEqual(done.shares)
  expect(done.shares?.map((s) => s.fleet)).toEqual([fleet, sister])
  expect(done.shares?.[1].name).toBe(SISTER)
  expect(done.shares?.reduce((n, s) => n + s.loot, 0)).toBe(done.loot)
  expect(done.shares?.reduce((n, s) => n + s.crew_lost, 0)).toBe(done.crew_lost)
  for (const s of done.shares ?? []) {
    expect(s.loot).toBeGreaterThanOrEqual(0)
    expect(s.hull_lost).toBeGreaterThanOrEqual(0)
  }
  const log = parseFightLog(done.log)
  expect(log, JSON.stringify(done.log)).not.toBeNull()
  expect(log?.fleets?.length).toBe(2)
  // one report in her History, with the shares
  expect(await db.callAs<number>(`select count(*)::int as result from public.events e where e.kind = 'BATTLE_REPORT' and e.payload ->> 'battle_id' = $1 and e.payload ? 'shares'`, [battle])).toBe(1)
  const fleets = await worldFleets()
  expect(fleets.ok && fleets.value.filter((f) => f.status === 'IN_BATTLE').length).toBe(0)
  // the navy's line never counts her own second fleet as a navy that came
  expect(done.navy).toBe('No navy came.')
})
