import { test, expect } from '@playwright/test'
import { openLocalDb, type LocalDb } from '../src/lib/db/localDb'
import { loadChain } from '../src/lib/db/chainSource.node.mjs'
import { builtWorldImage } from './builtWorld.fixture'
import { clearBackend, createLocalBackend, setBackend, worldBattle, worldFight, worldFights } from '../src/lib/rpc'
import { fightRing } from '../src/chart/fightRings'
import { mapFightsOf } from '../src/chart/liveWorld'
import { parseFightLog, parseFightLoss } from '../src/live/fightLines'
import { RAID_LOG } from './raidWorld.fixture'

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

// ONE STORY, TOLD IN ORDER: each test stands on the one before it (the battle the second opens is the one the third and fourth read). Serial, so a failure
// skips what follows instead of failing it on a world the next worker has built anew.
test.describe.configure({ mode: 'serial' })

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
  // EVERY BUILT WORLD HAS ITS OWN DICE (0031's world_secret; docs/dev-log/2026-11-12-live-rounds.md): nothing below may hold on one world's dice only. To prove it,
  // SPEC_WORLD_SECRET gives this throwaway world another secret (scripts/ops/harness/fight-rings/dice.sh runs it under many).
  if (process.env.SPEC_WORLD_SECRET) {
    await db.callAs(`with u as (update public.world_config set value = to_jsonb($1::text) where key = 'world_secret' returning 1) select count(*)::int as result from u`, [process.env.SPEC_WORLD_SECRET])
  }
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

test('attacks dark: the map reads no fight; `on` says only whether any kind of fight is in use; a battle that is none reads nothing', async () => {
  const read = await worldFights()
  expect(read.ok, JSON.stringify(read)).toBe(true)
  if (!read.ok) return
  // the shipped world's fight at sea bites (combat_bite), so a raid can happen and the map asks at its idle pace
  expect(read.value.on).toBe(await db.callAs<boolean>(`select public.attack_on() or public.navy_hunts_on() or public.combat_bite_on() as result`))
  expect(read.value.fights).toEqual([])
  expect(read.value.keep_seconds).toBe(60)
  expect(read.value.raid_seconds).toBe(300)
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
  // WHERE EACH LIES, AS THE READ GUARANTEES IT:
  //   · the attacker lies at her anchor, and the read serves that anchor to the digit (voyage.fleet_point of a fleet at anchor is her stored lat and lon);
  //   · the ship set upon is HELD at the battle's place: the place is voyage.position at the open and her point is voyage.position now, both rounded to 4 places, and a
  //     held ship does not move, so the two agree to within one unit of that rounding each way.
  // NOT asserted: how far the anchor is from the battle's place. The anchor was laid by the ship's point in beforeAll and the battle opened later, and a cargo ship
  // under sail covers about 0.02 degrees a real second (960x): that distance is the runner's speed, not a rule (it read 0.1993 for 0.2 on CI, 2026-11-13).
  const [a, d] = card.sides.map((s) => s.at as [number, number])
  const anchor = await db.callAs<{ lat: number; lon: number }>(`select jsonb_build_object('lat', f.lat, 'lon', f.lon) as result from public.fleets f where f.id = $1`, [attacker])
  expect(a).toEqual([anchor.lat, anchor.lon])
  expect(Math.abs(d[0] - card.lat)).toBeLessThanOrEqual(0.0002)
  expect(Math.abs(d[1] - card.lon)).toBeLessThanOrEqual(0.0002)
  expect(a[0]).toBeGreaterThan(card.lat)
  // and the ring the chart draws from exactly this goes round both, at a close zoom and a wide one
  const [fight] = mapFightsOf(read.value.fights)
  for (const upp of [0.002, 0.2]) {
    const ring = fightRing(fight, upp)
    for (const p of fight.places) expect(Math.hypot(p.lon - ring.centre.x, -p.lat - ring.centre.y)).toBeLessThanOrEqual(ring.r)
    expect(ring.rPx).toBeGreaterThanOrEqual(22)
  }
  // only the keys 0364 names ride on a card and on a side
  expect(card.kind).toBe('BATTLE')
  expect(card.size).toBe(2)
  expect(Object.keys(card).sort()).toEqual(['fleets', 'id', 'kind', 'lat', 'lon', 'mine', 'next_at', 'resolves_at', 'round_seconds', 'rounds', 'rounds_done', 'ships', 'sides', 'size', 'started_at', 'status'])
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

test('her own raid: a PIRATES day that kept its log is on HER map for 300 s, with the log her History draws and what the day cost', async () => {
  // a voyage of the watcher's own fleet with one raid day 20 s ago (rows of this spec: the real day is proof 66's), carrying a real raid's log
  const fleets = await db.callAs<string>(`select f.id as result from public.fleets f join public.players p on p.id = f.player_id where p.auth_uid = $1`, [db.authUid])
  const voyage = '00000000-0364-4000-8000-0000000000c1'
  await db.callAs(
    `with v as (insert into public.voyages (id, fleet_id, player_id, path, total_nm, speed_profile, departed_at, eta, status, origin_port_id, dest_port_id)
                select $2::uuid, f.id, f.player_id, jsonb_build_array(jsonb_build_object('a', jsonb_build_array(38, -10), 'b', jsonb_build_array(38, -12), 'nm', 600,
                         'sea_id', (select s.id from public.seas s order by s.code limit 1), 'danger', 0)), 600, '[5]', now() - interval '10 minutes', now() - interval '5 seconds', 'ARRIVED', f.port_id, f.port_id
                  from public.fleets f where f.id = $1 returning id),
          e as (insert into public.voyage_events (voyage_id, day_index, kind, payload, resolved_at)
                select v.id, 1, 'PIRATES', jsonb_build_object('crew_before', 8, 'crew_lost', 2, 'cargo_lost', '{"SUGAR": 3}'::jsonb, 'fight', jsonb_build_object('log', $3::jsonb)), now() - interval '20 seconds' from v returning 1)
     select count(*)::int as result from e`,
    [fleets, voyage, JSON.stringify({ ...RAID_LOG, foe: { ...RAID_LOG.foe, k: 4.2 } })],
  )
  const read = await worldFights()
  expect(read.ok, JSON.stringify(read)).toBe(true)
  if (!read.ok) return
  const raids = read.value.fights.filter((f) => f.kind === 'RAID')
  expect(raids).toHaveLength(1)
  const raid = raids[0]
  expect(raid.id).toBe(`raid:${voyage}:1`)
  expect(raid.mine).toBe(fleets)
  expect(raid.status).toBe('RESOLVED')
  expect(raid.size).toBe(6)
  expect(raid.end).toBe('FLED')
  expect(raid.lat).toBe(38)
  expect(Date.parse(raid.until as string) - Date.parse(raid.started_at)).toBe(300_000)
  expect(raid.sides.map((s) => [s.side, s.kind, s.ships])).toEqual([['ATTACKER', 'PIRATE', 5], ['DEFENDER', 'COMPANY', 1]])
  // the log is the one shape the one FightLog parses, from her deck; and the day's cost
  const log = parseFightLog(raid.log)
  expect(log, JSON.stringify(raid.log)).not.toBeNull()
  expect(log?.attacker).toBe(false)
  expect(log?.rounds).toHaveLength(RAID_LOG.r.length)
  expect(parseFightLoss(raid.loss)).toEqual({ crewBefore: 8, crew: 2, cargo: { SUGAR: 3 }, ransom: 0 })
  // the ring: five raiders' ships and her fleet draw 46 px, on the raid's own place
  const [ring] = mapFightsOf(raids).map((f) => fightRing(f, 0.01))
  expect(ring.rPx).toBe(46)
  expect(ring.over).toBe(false)
  // the other company reads nothing of it
  const theirs = await db.callAs<number>(
    `with i as materialized (select cmd.assume_identity($1::uuid) as x)
     select (select count(*)::int from jsonb_array_elements(world.fights() -> 'fights') e where e ->> 'kind' = 'RAID') as result from i`,
    [OTHER],
  )
  expect(theirs).toBe(0)
  // 301 s after the day's instant it has left her map
  await db.callAs(`with u as (update public.voyage_events set resolved_at = now() - interval '301 seconds' where voyage_id = $1 returning 1) select count(*)::int as result from u`, [voyage])
  const gone = await worldFights()
  expect(gone.ok && gone.value.fights.filter((f) => f.kind === 'RAID')).toEqual([])
})

test('a navy fight kept by the server is on EVERY map for 300 s, with its two ships and its log cut to nine keys', async () => {
  // the keeper on a real fight (the engine's own answer) of two whole hulls written here, named after two fleets of this world: what the battle above left of
  // those fleets' own hulls is the dice's, and this test is about the read (the real pass and old-against-new are proof 66's)
  const navyHull = JSON.stringify([{ id: '00000000-0364-4000-8000-0000000000d1', name: 'Spec Galion', tier: 4, hull: 2400, maxd: 2400, crew: 140, attack: 260, accuracy: 48, reach: 40, armour: 44, sighting: 22 }])
  const pirateHull = JSON.stringify([{ id: '00000000-0364-4000-8000-0000000000d2', name: 'Spec Xebec', tier: 2, hull: 900, maxd: 900, crew: 60, attack: 120, accuracy: 50, reach: 40, armour: 15, sighting: 25 }])
  await db.callAs(
    `select public.navy_fight_keep($1::uuid, $2::uuid, $4::jsonb, $3::jsonb, public.fight_sides($1::uuid, 7, $4::jsonb, $3::jsonb, '{}'::jsonb), now() - interval '10 seconds') is null as result`,
    [attacker, target, navyHull, pirateHull],
  )
  const read = await worldFights()
  expect(read.ok, JSON.stringify(read)).toBe(true)
  if (!read.ok) return
  const navy = read.value.fights.filter((f) => f.kind === 'NAVY')
  expect(navy).toHaveLength(1)
  const card = navy[0]
  expect(card.mine).toBeNull()
  expect(card.status).toBe('RESOLVED')
  expect(card.size).toBe(2)
  expect(card.ships).toBe(2)
  expect(card.sides.map((s) => [s.fleet, s.side, s.kind])).toEqual([[attacker, 'ATTACKER', 'NAVY'], [target, 'DEFENDER', 'PIRATE']])
  expect('loss' in card).toBe(false)
  const log = parseFightLog(card.log)
  expect(log, JSON.stringify(card.log)).not.toBeNull()
  expect(log?.attacker).toBe(true)
  expect(card.end).toBe(log?.end)
  expect(Object.keys(card.log as object).every((k) => ['v', 'atk', 'first', 'foe', 'you', 'r', 'board', 'after', 'end'].includes(k))).toBe(true)
  expect(mapFightsOf(navy)[0].kind).toBe('NAVY')
  await db.callAs(`with u as (update public.navy_fight_log set at = now() - interval '301 seconds' returning 1) select count(*)::int as result from u`)
  const gone = await worldFights()
  expect(gone.ok && gone.value.fights.filter((f) => f.kind === 'NAVY')).toEqual([])
})
