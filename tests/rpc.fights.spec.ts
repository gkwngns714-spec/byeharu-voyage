import { test, expect } from '@playwright/test'
import { openLocalDb, type LocalDb } from '../src/lib/db/localDb'
import { loadChain } from '../src/lib/db/chainSource.node.mjs'
import { builtWorldImage } from './builtWorld.fixture'
import { clearBackend, createLocalBackend, setBackend, worldBattle, worldFight, worldFights } from '../src/lib/rpc'
import { fightRing } from '../src/chart/fightRings'
import { mapFightsOf } from '../src/chart/liveWorld'
import { parseFightLog } from '../src/live/fightLines'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE MAP'S TWO READS OF A BATTLE, THE SEAM (0364, owner row 321): `world.fights()` and `world.fight(battle)`, through
// the client's one RPC layer, on the built world. Proof 66 proves the server's rules. This proves the client reads
// what the server serves: dark, an empty list; lit, a battle ANOTHER company opened is on the watcher's map with its
// place, its fleets and where they lie; her log reads in the one shape `FightLog` parses and grows a round at a
// time; nothing that is the attacker's alone is served; and it leaves the map a minute after it ends.
// THE WATCHER IS THE SPEC'S OWN CAPTAIN (the client's layer speaks for her); the company that attacks is a second
// house, made and driven by the server's own functions, as rpc.battle.spec.ts's is driven by the doors.
// `attack_enabled` is lit in this throwaway world only (memory://), as rpc.battle.spec.ts lights it.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

let db: LocalDb
let target: string
let attacker: string
let battle: string
const OTHER = '00000000-0364-4000-8000-0000000000aa'

const light = (keys: string[], on: boolean) =>
  db.callAs(`with lit as (update public.world_config set value = $2::jsonb where key = any($1::text[]) returning 1) select count(*)::int as result from lit`, [keys, on ? 'true' : 'false'])
// the job's call, as if `secs` seconds of the battle had passed
const tickAt = (secs: number) =>
  db.callAs<boolean>(`select public.battle_resolve(b.id, b.started_at + make_interval(secs => $2)) as result from public.battles b where b.id = $1`, [battle, secs])

test.beforeAll(async () => {
  test.setTimeout(360_000)
  db = await openLocalDb({ loadChain, loadImage: builtWorldImage, dataDir: 'memory://', log: () => {} })
  setBackend(createLocalBackend(db))
  await db.callAs(`select cmd.found_house('Watcher Spec', 'PRT') as result`)
  await db.callAs(`with t as (update public.port_treasury set ducats = 50000000, reserve = 0 returning 1) select count(*)::int as result from t`)
  await light(['city_treasury_enabled', 'convoys_enabled'], true)
  // rpc.battle.spec's scene: a cargo ship of another country at sea with funds
  const realm = await db.callAs<string>(`select g.nation_id as result from public.great_powers g join public.nations n on n.id = g.nation_id where n.code <> 'PRT' order by n.code limit 1`)
  for (let i = 0; i < 3; i++) await db.callAs(`select public.tick_cargo_ships(now(), $1::uuid) is null as result`, [realm])
  target = await db.callAs<string>(`select c.fleet_id as result from public.cargo_ships c where c.nation_id = $1 and c.ord = 1`, [realm])
  await db.callAs(
    `select public.convoy_book('LOADED', c.fleet_id, c.player_id, c.home_port_id, 100000) is null, public.cargo_ship_step(c.fleet_id, now()) as result from public.cargo_ships c where c.fleet_id = $1`,
    [target],
  )
  // the other company: a gunned fleet at anchor a fifth of a degree north of the cargo ship
  // (two calls: a statement does not see the rows a function it calls has just written)
  const house = await db.callAs<string>(
    `select public.new_house($1::uuid, 'Casa Ronda', 'PRT', 'LIS', 'Ronda', (select c.code from public.ship_classes c order by c.attack desc, c.code limit 1), 'Ronda', null, false) as result`,
    [OTHER],
  )
  attacker = await db.callAs<string>(`select f.id as result from public.fleets f where f.player_id = $1`, [house])
  await db.callAs(
    `with p as (select * from voyage.fleet_point($2, now())),
          g as (update public.ships set cargo = '{}'::jsonb where fleet_id = $1 returning 1),
          f as (update public.fleets x set status = 'ANCHORED', port_id = null, lat = p.lat + 0.2, lon = p.lon from p where x.id = $1 returning 1)
     select (select count(*)::int from f) + (select count(*)::int from g) as result`,
    [attacker, target],
  )
})

test.afterAll(async () => {
  clearBackend()
  await db?.close()
})

test('dark: the map reads no battle and asks seldom; a battle that is none reads nothing', async () => {
  const read = await worldFights()
  expect(read.ok, JSON.stringify(read)).toBe(true)
  if (!read.ok) return
  expect(read.value.on).toBe(false)
  expect(read.value.fights).toEqual([])
  expect(read.value.keep_seconds).toBe(60)
  const none = await worldFight('00000000-0000-4000-8000-000000000364')
  expect(none.ok && none.value).toEqual({ on: false })
})

test('lit: a battle another company opened is on the watcher’s map, with its place, its fleets and where they lie', async () => {
  await light(['attack_enabled'], true)
  const empty = await worldFights()
  expect(empty.ok && empty.value.on).toBe(true)
  expect(empty.ok && empty.value.fights).toEqual([])
  battle = await db.callAs<string>(`select public.battle_open('ATTACK', $1::uuid, $2::uuid, now()) as result`, [attacker, target])
  const read = await worldFights()
  expect(read.ok, JSON.stringify(read)).toBe(true)
  if (!read.ok) return
  expect(read.value.fights).toHaveLength(1)
  const card = read.value.fights[0]
  expect(card.id).toBe(battle)
  expect(card.status).toBe('FIGHTING')
  expect(card.mine).toBeNull()
  expect(card.fleets).toBe(2)
  expect(card.ships).toBeGreaterThanOrEqual(2)
  expect(card.rounds_done).toBe(0)
  expect(card.round_seconds).toBe(60)
  expect(Date.parse(card.next_at as string) - Date.parse(card.started_at)).toBe(60_000)
  expect('end' in card).toBe(false)
  expect(card.sides.map((s) => [s.fleet, s.side, s.how, s.kind, s.here])).toEqual([
    [attacker, 'ATTACKER', 'OPENED', 'COMPANY', true],
    [target, 'DEFENDER', 'OPENED', 'CARGO_SHIP', true],
  ])
  expect(card.sides[0].name).toBe('Ronda')
  expect(card.sides[0].company).toBe('Casa Ronda')
  expect(card.sides[0].nation).toBe('PRT')
  expect(card.sides[1].company).toBeNull()
  expect(card.sides[1].nation).not.toBe('PRT')
  // where each lies: the ship set upon at the battle's place, the attacker a fifth of a degree north of it
  const [a, d] = card.sides.map((s) => s.at as [number, number])
  expect(Math.abs(d[0] - card.lat)).toBeLessThan(0.01)
  expect(Math.abs(d[1] - card.lon)).toBeLessThan(0.01)
  expect(a[0] - card.lat).toBeCloseTo(0.2, 3)
  // and the ring the chart draws from exactly this goes round both, at a close zoom and a wide one
  const [fight] = mapFightsOf(read.value.fights)
  for (const upp of [0.002, 0.2]) {
    const ring = fightRing(fight, upp)
    for (const p of fight.places) expect(Math.hypot(p.lon - ring.centre.x, -p.lat - ring.centre.y)).toBeLessThanOrEqual(ring.r)
    expect(ring.rPx).toBeGreaterThanOrEqual(22)
  }
  // only the keys 0364 names ride on a card and on a side
  expect(Object.keys(card).sort()).toEqual(['fleets', 'id', 'lat', 'lon', 'mine', 'next_at', 'resolves_at', 'round_seconds', 'rounds', 'rounds_done', 'ships', 'sides', 'started_at', 'status'])
  for (const s of card.sides) expect(Object.keys(s).sort()).toEqual(['at', 'company', 'fleet', 'here', 'how', 'kind', 'name', 'nation', 'ships', 'side'])
})

test('the watcher’s log: open and empty before the first round, nothing of the attacker’s own, and her own card is not the watcher’s to read', async () => {
  const read = await worldFight(battle)
  expect(read.ok, JSON.stringify(read)).toBe(true)
  if (!read.ok) return
  const b = read.value
  expect(b.on).toBe(true)
  expect(b.watch).toBe(true)
  expect(b.mine).toBeNull()
  expect(b.battle).toBe(battle)
  expect(b.status).toBe('FIGHTING')
  expect(b.you).toBe('Ronda')
  expect(b.rounds_done).toBe(0)
  expect(b.next_range).toBe('LONG')
  for (const k of ['stance', 'may', 'word', 'loot', 'crew_lost', 'outcome', 'navy']) expect(k in b, k).toBe(false)
  const log = parseFightLog(b.log, { open: true })
  expect(log, JSON.stringify(b.log)).not.toBeNull()
  expect(log?.attacker).toBe(true)
  expect(log?.end).toBe('OPEN')
  expect(log?.rounds).toEqual([])
  expect(Object.keys(b.log as object).every((k) => ['v', 'atk', 'first', 'foe', 'you', 'r', 'board', 'after', 'end'].includes(k))).toBe(true)
  // the attacker's own card (her stance, her loot) answers nothing to the watcher
  const hers = await worldBattle(attacker)
  expect(hers.ok && hers.value).toEqual({ on: false })
  // and for the attacker herself the same two reads say the battle is hers
  const mine = await db.callAs<{ card: string | null; read: string | null }>(
    `with i as materialized (select cmd.assume_identity($1::uuid) as x)
     select jsonb_build_object('card', world.fights() -> 'fights' -> 0 -> 'mine', 'read', world.fight($2::uuid) -> 'mine') as result from i`,
    [OTHER, battle],
  )
  expect(mine).toEqual({ card: attacker, read: attacker })
})

test('the log grows a round at a time for the watcher; over, the ring carries the ending for a minute and then leaves the map', async () => {
  await tickAt(60)
  const one = await worldFight(battle)
  expect(one.ok, JSON.stringify(one)).toBe(true)
  if (!one.ok) return
  const first = parseFightLog(one.value.log, { open: one.value.status === 'FIGHTING' })
  expect(first, JSON.stringify(one.value.log)).not.toBeNull()
  if (!first) return
  if (one.value.status === 'FIGHTING') {
    expect(one.value.rounds_done).toBe(1)
    expect(first.rounds).toHaveLength(1)
    expect(first.end).toBe('OPEN')
    expect(first.board).toBeNull()
    const cards = await worldFights()
    expect(cards.ok && cards.value.fights[0].rounds_done).toBe(1)
  }
  // the rest of the clock in one late call
  await tickAt(3600)
  const done = await worldFight(battle)
  expect(done.ok, JSON.stringify(done)).toBe(true)
  if (!done.ok) return
  expect(['RESOLVED', 'BROKEN_OFF']).toContain(done.value.status)
  expect(done.value.next_at ?? null).toBeNull()
  const log = parseFightLog(done.value.log)
  expect(log, JSON.stringify(done.value.log)).not.toBeNull()
  if (!log) return
  expect(['A_NONE', 'A_LOST', 'FLED', 'A_BROKE', 'A_THROWN', 'A_TERMS', 'A_TOOK']).toContain(log.end)
  if (first.rounds.length === 1) expect(log.rounds[0]).toEqual(first.rounds[0])
  for (const k of ['stance', 'may', 'word', 'loot', 'crew_lost', 'outcome', 'navy']) expect(k in done.value, k).toBe(false)
  // just over (its clock ends in the future of this world's now): still served, with the ending and no fleet's place
  const kept = await worldFights()
  expect(kept.ok, JSON.stringify(kept)).toBe(true)
  if (!kept.ok) return
  expect(kept.value.fights).toHaveLength(1)
  expect(kept.value.fights[0].end).toBe(log.end)
  expect(kept.value.fights[0].next_at).toBeNull()
  expect(kept.value.fights[0].sides.every((s) => !('at' in s))).toBe(true)
  expect(mapFightsOf(kept.value.fights)[0].over).toBe(true)
  // 61 s after its end it has left the map; its log still reads
  await db.callAs(`with u as (update public.battles set started_at = now() - interval '10 minutes', resolves_at = now() - interval '61 seconds' where id = $1 returning 1) select count(*)::int as result from u`, [battle])
  const gone = await worldFights()
  expect(gone.ok && gone.value.fights).toEqual([])
  const still = await worldFight(battle)
  expect(still.ok && still.value.on).toBe(true)
})
