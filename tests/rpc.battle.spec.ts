import { test, expect } from '@playwright/test'
import { openLocalDb, type LocalDb } from '../src/lib/db/localDb'
import { loadChain } from '../src/lib/db/chainSource.node.mjs'
import { builtWorldImage } from './builtWorld.fixture'
import { clearBackend, cmdAttack, cmdBattleStance, createLocalBackend, setBackend, worldBattle, worldFleets } from '../src/lib/rpc'
import { fightRows, parseFightLog } from '../src/live/fightLines'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A BATTLE ROUND BY ROUND, THE SEAM (0357, docs/COMBAT_LOG.md 3.3, 3.4): the two real doors, through the client's one
// RPC layer, on the built world. Proof 60 proves the server's rules. This proves the client reads what the server
// serves: dark, the read says nothing and the stance door refuses; lit, the press opens a battle the card can read,
// Flee is kept from the next round, the log grows a round at a time in the shape the one FightLog parses, nothing is
// told before its round, and a battle that is over refuses a stance in words.
// The rounds are brought due by calling the server's own closer at a later instant (the minute job's call): a spec
// cannot wait a minute a round.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

let db: LocalDb
let fleet: string
let target: string
let battle: string

const light = (keys: string[], on: boolean) =>
  db.callAs(`with lit as (update public.world_config set value = $2::jsonb where key = any($1::text[]) returning 1) select count(*)::int as result from lit`, [keys, on ? 'true' : 'false'])
// the job's call, as if `secs` seconds of the battle had passed
const tickAt = (secs: number) =>
  db.callAs<boolean>(`select public.battle_resolve(b.id, b.started_at + make_interval(secs => $2)) as result from public.battles b where b.id = $1`, [battle, secs])

test.beforeAll(async () => {
  test.setTimeout(360_000)
  db = await openLocalDb({ loadChain, loadImage: builtWorldImage, dataDir: 'memory://', log: () => {} })
  setBackend(createLocalBackend(db))
  // SPEC_WORLD_SECRET gives this throwaway world another secret (scripts/ops/harness/attacks/dice.mjs runs it under many): no test below assumes how a roll falls
  if (process.env.SPEC_WORLD_SECRET) {
    await db.callAs(`with u as (update public.world_config set value = to_jsonb($1::text) where key = 'world_secret' returning 1) select count(*)::int as result from u`, [process.env.SPEC_WORLD_SECRET])
  }
  await db.callAs(`select cmd.found_house('Battle Spec', 'PRT') as result`)
  await db.callAs(`with t as (update public.port_treasury set ducats = 50000000, reserve = 0 returning 1) select count(*)::int as result from t`)
  await light(['city_treasury_enabled', 'convoys_enabled'], true)
  // rpc.attack.spec's scene: a cargo ship of another country at sea with funds, and the company's fleet at anchor on her point
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
  await db.callAs(
    `with p as (select * from voyage.fleet_point($2, now())),
          g as (update public.ships set class_id = (select c.id from public.ship_classes c order by c.attack desc, c.code limit 1), cargo = '{}'::jsonb where fleet_id = $1 returning 1),
          f as (update public.fleets x set status = 'ANCHORED', port_id = null, lat = p.lat, lon = p.lon from p where x.id = $1 returning 1)
     select (select count(*)::int from f) + (select count(*)::int from g) as result`,
    [fleet, target],
  )
})

test.afterAll(async () => {
  clearBackend()
  await db?.close()
})

test('dark: the read says nothing, the stance door refuses, and nothing is written', async () => {
  const read = await worldBattle(fleet)
  expect(read.ok, JSON.stringify(read)).toBe(true)
  if (read.ok) expect(read.value).toEqual({ on: false })
  const press = await cmdBattleStance('00000000-0000-4000-8000-000000000357', 'FLEE')
  expect(press.ok).toBe(false)
  if (!press.ok) expect(press.refusal.code).toBe('E_NOT_IN_USE')
  expect(await db.callAs<number>(`select (select count(*) from public.battle_stances)::int + (select count(*) from public.battle_rounds)::int as result`)).toBe(0)
})

test('lit: the press opens a battle the card can read, before its first round', async () => {
  await light(['attack_enabled'], true)
  const hit = await cmdAttack(fleet, target, null)
  expect(hit.ok, JSON.stringify(hit)).toBe(true)
  if (!hit.ok) return
  battle = hit.value.battle_id as string
  const read = await worldBattle(fleet)
  expect(read.ok, JSON.stringify(read)).toBe(true)
  if (!read.ok) return
  const b = read.value
  expect(b.on).toBe(true)
  expect(b.battle).toBe(battle)
  expect(b.status).toBe('FIGHTING')
  expect(b.side).toBe('ATTACKER')
  expect(b.stance).toBe('FIGHT')
  expect(b.may).toEqual(['FIGHT', 'FLEE'])
  expect(b.word).toBe(hit.value.word)
  expect(b.rounds_done).toBe(0)
  expect(b.round_seconds).toBe(60)
  expect(b.next_range).toBe('LONG')
  expect(Date.parse(b.next_at as string) - Date.parse(b.started_at as string)).toBe(60_000)
  expect(Date.parse(b.resolves_at as string) - Date.parse(b.started_at as string)).toBe(60_000 * ((b.rounds as number) + 1))
  // the log: from her deck, open, no round yet; a reader that expects a finished fight does not take it
  const log = parseFightLog(b.log, { open: true })
  expect(log, JSON.stringify(b.log)).not.toBeNull()
  expect(log?.attacker).toBe(true)
  expect(log?.end).toBe('OPEN')
  expect(log?.rounds).toEqual([])
  expect(parseFightLog(b.log)).toBeNull()
  // the target's side reads nothing of it through her attacker's door
  const theirs = await worldBattle(target)
  expect(theirs.ok && theirs.value.on).toBe(false)
})

test('the stance door: a bad word and a Pay are refused in words, Flee is kept from the next round, and the same stance writes nothing', async () => {
  for (const [word, code] of [['RUN', 'E_BAD_STANCE'], ['PAY', 'E_BAD_STANCE']] as const) {
    const r = await cmdBattleStance(battle, word as never)
    expect(r.ok).toBe(false)
    if (!r.ok) expect(r.refusal.code).toBe(code)
  }
  const none = await cmdBattleStance('00000000-0000-4000-8000-000000000357', 'FLEE')
  expect(!none.ok && none.refusal.code).toBe('E_NO_BATTLE')
  const flee = await cmdBattleStance(battle, 'FLEE')
  expect(flee.ok, JSON.stringify(flee)).toBe(true)
  if (!flee.ok) return
  expect(flee.value.stance).toBe('FLEE')
  expect(flee.value.round_next).toBe(1)
  const again = await cmdBattleStance(battle, 'FLEE')
  expect(again.ok).toBe(true)
  expect(await db.callAs<number>(`select count(*)::int as result from public.battle_stances where battle_id = $1`, [battle])).toBe(1)
  const read = await worldBattle(fleet)
  expect(read.ok && read.value.stance).toBe('FLEE')
})

test('the log grows a round at a time, each round she ran says so, and nothing is told before its round; closed, the result reads and a stance is refused', async () => {
  // round 1 falls due
  await tickAt(60)
  const one = await worldBattle(fleet)
  expect(one.ok, JSON.stringify(one)).toBe(true)
  if (!one.ok) return
  const first = parseFightLog(one.value.log, { open: one.value.status === 'FIGHTING' })
  expect(first, JSON.stringify(one.value.log)).not.toBeNull()
  if (!first) return
  expect(first.rounds.length).toBeLessThanOrEqual(1)
  if (one.value.status === 'FIGHTING') {
    expect(one.value.rounds_done).toBe(1)
    expect(first.end).toBe('OPEN')
    expect(first.board).toBeNull()
    expect(fightRows(first)[0].you.kind).toBe('run')
    expect(fightRows(first)[0].slipPct).not.toBeNull()
    expect('outcome' in one.value).toBe(false)
  }
  // the rest of the clock, in one late call: it closes once
  await tickAt(3600)
  expect(await tickAt(3600)).toBe(false)
  const done = await worldBattle(fleet)
  expect(done.ok, JSON.stringify(done)).toBe(true)
  if (!done.ok) return
  expect(['RESOLVED', 'BROKEN_OFF']).toContain(done.value.status)
  expect(done.value.next_at ?? null).toBeNull()
  const log = parseFightLog(done.value.log)
  expect(log, JSON.stringify(done.value.log)).not.toBeNull()
  if (!log) return
  expect(log.attacker).toBe(true)
  expect(['A_NONE', 'A_LOST', 'FLED', 'A_BROKE', 'A_THROWN', 'A_TERMS', 'A_TOOK']).toContain(log.end)
  if (done.value.status === 'BROKEN_OFF') expect(log.end).toBe('FLED')
  // the first round of the finished log is the round the open log showed: a later round never rewrites an earlier one
  if (first.rounds.length === 1) expect(log.rounds[0]).toEqual(first.rounds[0])
  // every round she ran fired nothing
  for (const r of fightRows(log)) expect(r.you.kind).toBe('run')
  expect(await db.callAs<number>(`select count(*)::int as result from public.battle_rounds where battle_id = $1`, [battle])).toBe(log.rounds.length)
  const late = await cmdBattleStance(battle, 'FIGHT')
  expect(late.ok).toBe(false)
  if (!late.ok) expect(late.refusal.code).toBe('E_BATTLE_OVER')
  // her fleet is free again
  const fleets = await worldFleets()
  expect(fleets.ok && fleets.value.find((f) => f.id === fleet)?.status).not.toBe('IN_BATTLE')
})
