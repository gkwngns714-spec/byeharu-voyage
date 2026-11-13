import { test, expect } from '@playwright/test'
import { openLocalDb, type LocalDb } from '../src/lib/db/localDb'
import { loadChain } from '../src/lib/db/chainSource.node.mjs'
import { builtWorldImage } from './builtWorld.fixture'
import { clearBackend, cmdLevelUp, createLocalBackend, setBackend, worldLedger, worldLevels, worldPlayer, RPCS } from '../src/lib/rpc'
import { headline } from '../src/features/ledger/headline'
import { getLocale, setLocale } from '../src/lib/i18n'

// ═════════════════════════════════════════════════════════════════════════════════════════════════
// A LEVEL CROSSED IS A MOMENT, THE SEAM (0356, slice R4 of docs/REPUTATION.md): the real door and the real read, through
// the client's one RPC layer, on the built world. Proof 59 proves the server's rules through the game's own doors. This
// proves the client reads what the server serves: the house read carries each track's paid mark and the gift a level; a
// level standing above its mark is paid by ONE cmd.level_up(), 10 x each level, as LEVEL_UP events the ledger serves and
// History words in English and Korean; a second ask pays nothing; and the levels themselves (world.levels, the house
// read) do not move when a mark does. PURE UNIT SPEC: no browser.
// ═════════════════════════════════════════════════════════════════════════════════════════════════

let db: LocalDb
let house: string

const one = async <T>(sql: string, params: unknown[] = []): Promise<T> =>
  (Object.values((await db.pg.query<Record<string, T>>(sql, params)).rows[0] ?? {})[0]) as T

test.beforeAll(async () => {
  test.setTimeout(360_000)
  db = await openLocalDb({ loadChain, loadImage: builtWorldImage, dataDir: 'memory://', log: () => {} })
  setBackend(createLocalBackend(db))
  await db.callAs(`select cmd.found_house('Nivel Spec', 'PRT') as result`)
  const p = await worldPlayer()
  expect(p.ok && p.value.player !== null, JSON.stringify(p)).toBe(true)
  if (p.ok && p.value.player) house = p.value.player.id
})

test.afterAll(async () => {
  clearBackend()
  await db?.close()
})

test('the catalogue: cmd.level_up takes no argument and drops no kept read', () => {
  expect(RPCS.cmdLevelUp.schema).toBe('cmd')
  expect(RPCS.cmdLevelUp.fn).toBe('level_up')
  expect(RPCS.cmdLevelUp.args).toEqual([])
  expect('mutates' in RPCS.cmdLevelUp && RPCS.cmdLevelUp.mutates, 'the door would drop every kept market read each time a level is crossed').toBeFalsy()
})

test('a new house: marks at 1, the gift served, and the door pays nothing', async () => {
  const p = await worldPlayer()
  expect(p.ok).toBe(true)
  if (!p.ok || !p.value.player) return
  expect(p.value.player.reputation?.level_marks).toEqual({ trading: 1, exploration: 1, combat: 1 })
  expect(p.value.player.reputation?.level_gift).toBe(10)
  const r = await cmdLevelUp()
  expect(r.ok, JSON.stringify(r)).toBe(true)
  if (r.ok) expect(r.value.levels).toEqual([])
  expect(await one<number>(`select count(*)::int from public.house_level_marks where player_id = $1`, [house])).toBe(0)
})

test('a level above its mark: one ask pays 20 + 30 + 40, the ledger serves three LEVEL_UP events, History words them in both languages', async () => {
  // the miles of Exploration level 4, from the knobs the level is derived by (one port reached)
  await db.pg.exec(`
    insert into public.events (player_id, kind, payload)
    select '${house}', 'VOYAGE_REPORT', jsonb_build_object('to', 'PSPEC', 'total_nm',
             greatest(public.wc_num('level_points_per_step') * 9 - public.wc_num('fame_per_port'), 0) * public.wc_num('fame_nm_per_point'))`)
  const before = await worldPlayer()
  expect(before.ok).toBe(true)
  if (!before.ok || !before.value.player) return
  expect(before.value.player.levels.exploration.level, 'the level is derived at once').toBe(4)
  expect(before.value.player.reputation?.level_marks?.exploration, 'and its mark is not moved by a read').toBe(1)
  const levelsBefore = await worldLevels()

  const r = await cmdLevelUp()
  expect(r.ok, JSON.stringify(r)).toBe(true)
  if (!r.ok) return
  expect(r.value.levels).toEqual([
    { track: 'exploration', level: 2, reputation: 20 },
    { track: 'exploration', level: 3, reputation: 30 },
    { track: 'exploration', level: 4, reputation: 40 },
  ])

  const after = await worldPlayer()
  expect(after.ok).toBe(true)
  if (!after.ok || !after.value.player) return
  expect(after.value.player.reputation?.level_marks).toEqual({ trading: 1, exploration: 4, combat: 1 })
  expect(after.value.player.reputation?.balance).toBe(90)
  expect(after.value.player.reputation?.today, 'a level gift is outside the day cap').toBe(0)
  expect(after.value.player.reputation?.recent.slice(0, 3).map((x) => `${x.kind}:${x.delta}`)).toEqual(['level:40', 'level:30', 'level:20'])
  // THE LEVELS STAY DERIVED: paying moved no level, on the house read or on the Levels page's read
  expect(after.value.player.levels).toEqual(before.value.player.levels)
  expect(await worldLevels()).toEqual(levelsBefore)

  const ledger = await worldLedger()
  expect(ledger.ok).toBe(true)
  if (!ledger.ok) return
  const ups = ledger.value.events.filter((e) => e.kind === 'LEVEL_UP')
  expect(ups.map((e) => e.payload)).toEqual(expect.arrayContaining(r.value.levels))
  expect(ups).toHaveLength(3)
  const top = ups.find((e) => e.payload.level === 4)!
  const was = getLocale()
  try {
    setLocale('en')
    expect(headline(top, (c) => c)).toBe('Exploration level 4 · +40 Reputation')
    setLocale('ko')
    expect(headline(top, (c) => c)).toBe('탐험 4레벨 · 평판 +40')
  } finally {
    setLocale(was)
  }

  const again = await cmdLevelUp()
  expect(again.ok).toBe(true)
  if (again.ok) expect(again.value.levels).toEqual([])
  expect(await one<number>(`select count(*)::int from public.events where player_id = $1 and kind = 'LEVEL_UP'`, [house])).toBe(3)
})

test('the shell asks once: a house read with a level above its mark sends ONE cmd.level_up, and later reads send none', async () => {
  // THE ONE CALLER (src/live/worldStore.ts `refresh`). Her second port and its miles: Exploration level 5 over a mark of 4.
  const { useWorld } = await import('../src/live/worldStore')
  await db.pg.exec(`
    insert into public.events (player_id, kind, payload)
    select '${house}', 'VOYAGE_REPORT', jsonb_build_object('to', 'QSPEC', 'total_nm',
             greatest(public.wc_num('level_points_per_step') * 9 - public.wc_num('fame_per_port'), 0) * public.wc_num('fame_nm_per_point'))`)
  const asks: string[] = []
  const debug = console.debug
  console.debug = (...args: unknown[]) => {
    if (args[0] === '[rpc]' && typeof args[1] === 'string' && args[1].startsWith('cmd.level_up')) asks.push(args[1])
    debug(...args)
  }
  try {
    await useWorld.getState().refresh()
    await expect.poll(() => one<number>(`select level from public.house_level_marks where player_id = $1 and track = 'exploration'`, [house]), { timeout: 30_000 }).toBe(5)
    expect(asks, 'the read that saw level 5 over mark 4 asked once').toHaveLength(1)
    // the next read (the ask's own tail calls the beat; this world has no running shell, so the spec reads) serves the mark at 5,
    // and the ledger is read again although no purse and no fleet moved: the LEVEL_UP event is in the shell's events
    await useWorld.getState().refresh()
    expect(useWorld.getState().player?.reputation?.level_marks?.exploration).toBe(5)
    expect(useWorld.getState().events.filter((e) => e.kind === 'LEVEL_UP' && e.payload.level === 5)).toHaveLength(1)
    expect(useWorld.getState().player?.reputation?.balance).toBe(140)
    await useWorld.getState().refresh()
    expect(asks, 'a read with every level at its mark asks nothing').toHaveLength(1)
  } finally {
    console.debug = debug
  }
})
