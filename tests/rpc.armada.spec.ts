import { test, expect } from '@playwright/test'
import { openLocalDb, type LocalDb } from '../src/lib/db/localDb'
import { loadChain } from '../src/lib/db/chainSource.node.mjs'
import { builtWorldImage } from './builtWorld.fixture'
import {
  clearBackend,
  cmdArmadaDisband,
  cmdArmadaForm,
  cmdArmadaSail,
  cmdIssue,
  cmdPreviewArmadaSail,
  createLocalBackend,
  setBackend,
  worldArmadas,
  worldFleets,
  worldLedger,
} from '../src/lib/rpc'
import { headline } from '../src/features/ledger/headline'
import { armadaTotals, fleetsOf } from '../src/live/armadas'
import { SECOND_FLEET } from './armada.fixture'

// ═════════════════════════════════════════════════
// AN ARMADA: THE SEAM (0367, docs/ARMADA.md): the real doors and the read, through the client's one RPC layer, on the built world. Proof 68 proves the server's rules (the
// raid as one side, old = new for every fleet in no armada). This proves the shapes the client types promise, and the path a player walks: form, see, dry run, send, disband.
// ═════════════════════════════════════════════════

let db: LocalDb

test.beforeAll(async () => {
  test.setTimeout(360_000)
  db = await openLocalDb({ loadChain, loadImage: builtWorldImage, dataDir: 'memory://', log: () => {} })
  setBackend(createLocalBackend(db))
})

test.afterAll(async () => {
  clearBackend()
  await db?.close()
})

async function fleets() {
  const r = await worldFleets()
  expect(r.ok).toBe(true)
  return r.ok ? r.value : []
}

async function armadas() {
  const r = await worldArmadas()
  expect(r.ok).toBe(true)
  if (!r.ok) throw new Error('no armadas read')
  return r.value
}

test('an armada is formed, read, sent on one order and disbanded', async () => {
  test.setTimeout(240_000)
  // a company of two fleets in one port: the founding fleet, and a second made here by the server's own makers (as the fixture's patch does in the browser)
  await db.callAs(`select cmd.found_house('Armada Spec', 'PRT') as result`)
  await db.callAs(`
    with me as (select public.current_player_id() as id),
         f as (select public.form_fleet(me.id, '${SECOND_FLEET}', (select x.port_id from public.fleets x where x.player_id = me.id limit 1)) as fid from me),
         s as (select public.commission_ship(me.id, f.fid, 'barca', 'Andorinha do Sul', true, true) as sid from me, f),
         c as (select public.credit(me.id, 'SPEC', 200000) as purse from me)
    select (select count(*) from s)::int + (select count(*) from c)::int as result`)
  const before = await fleets()
  expect(before.map((f) => f.name)).toContain(SECOND_FLEET)
  expect(before).toHaveLength(2)
  expect(before.every((f) => f.status === 'DOCKED' && f.port === before[0].port)).toBe(true)

  // THE READ, with none: lit, six at the most
  const none = await armadas()
  expect(none).toMatchObject({ on: true, max: 6, raid_scale: 1, armadas: [] })

  // ONE FLEET IS NO ARMADA; a name too short is the name's refusal; nothing was made
  const one = await cmdArmadaForm([before[0].id], 'Armada do Sul')
  expect(!one.ok && one.refusal.code).toBe('E_ARMADA_SIZE')
  const short = await cmdArmadaForm([before[0].id, before[1].id], 'ab')
  expect(!short.ok && short.refusal.code).toBe('E_BAD_NAME')
  expect((await armadas()).armadas).toHaveLength(0)

  // FORMED: the first fleet named leads; both read the armada's speed, the slower fleet's
  const formed = await cmdArmadaForm([before[1].id, before[0].id], 'Armada do Sul Dourado')
  expect(formed.ok).toBe(true)
  if (!formed.ok) return
  expect(formed.value).toMatchObject({ name: 'Armada do Sul Dourado', fleets: [before[1].id, before[0].id] })
  const read = await armadas()
  expect(read.armadas).toHaveLength(1)
  const armada = read.armadas[0]
  expect(armada).toMatchObject({ id: formed.value.armada_id, name: 'Armada do Sul Dourado', flagship: before[1].id, fleets: [before[1].id, before[0].id], state: 'PORT', port: before[0].port })
  const inPort = await fleets()
  expect(armada.speed_kn).toBe(Math.min(...before.map((f) => f.speed_kn)))
  expect(inPort.every((f) => f.speed_kn === armada.speed_kn)).toBe(true)
  // her totals are the sums of her fleets' served totals
  const members = fleetsOf(armada, inPort)
  expect(members.map((f) => f.id)).toEqual(armada.fleets)
  expect(armadaTotals(members)).toMatchObject({ fleets: 2, ships: 2, hull: inPort.reduce((n, f) => n + f.totals!.hull, 0), crew: inPort.reduce((n, f) => n + f.totals!.crew, 0) })

  // A FLEET OF HERS DOES NOT SAIL ALONE
  const alone = await cmdIssue(before[0].id, 'SAIL TO FNC', null, null)
  expect(!alone.ok && alone.refusal.code).toBe('E_IN_ARMADA')
  expect((await fleets()).every((f) => f.status === 'DOCKED')).toBe(true)

  // THE DRY RUN keeps nothing and says what the order will say
  const dry = await cmdPreviewArmadaSail(armada.id, 'FNC', null, false)
  expect(dry.ok).toBe(true)
  if (!dry.ok) return
  expect(dry.value.dry).toBe(true)
  expect(dry.value.voyages).toHaveLength(2)
  // new hulls leave the yard with their casks full, so a short passage may cost nothing: the figure is what the order costs, never less than nothing
  expect(dry.value.cost).toBeGreaterThanOrEqual(0)
  expect(dry.value.on_credit).toBeGreaterThanOrEqual(0)
  expect(dry.value.speed_kn).toBe(armada.speed_kn)
  expect((await fleets()).every((f) => f.status === 'DOCKED' && f.voyage == null)).toBe(true)
  const nowhere = await cmdPreviewArmadaSail(armada.id, 'XXQ', null, false)
  expect(!nowhere.ok && nowhere.refusal.code).toBe('E_NO_SUCH_PORT')

  // THE ORDER: both leave, on one schedule
  const sent = await cmdArmadaSail(armada.id, 'FNC', null, false)
  expect(sent.ok).toBe(true)
  if (!sent.ok) return
  expect(sent.value).toMatchObject({ dry: false, cost: dry.value.cost, speed_kn: dry.value.speed_kn })
  const atSea = await fleets()
  expect(atSea.every((f) => f.status === 'SAILING' && f.voyage != null)).toBe(true)
  expect(new Set(atSea.map((f) => f.voyage!.eta)).size).toBe(1)
  expect(new Set(atSea.map((f) => f.voyage!.to)).size).toBe(1)
  expect((await armadas()).armadas[0].state).toBe('SEA')

  // THE LEDGER says it in a sentence, with her fleets by name
  const ledger = await worldLedger()
  expect(ledger.ok).toBe(true)
  if (!ledger.ok) return
  const lines = ledger.value.events.map((e) => headline(e, (code) => code))
  expect(lines.some((l) => l.includes('Armada do Sul Dourado') && l.includes(SECOND_FLEET))).toBe(true)
  expect(lines.some((l) => l.includes('Armada do Sul Dourado') && l.includes('FNC'))).toBe(true)

  // DISBANDED AT SEA: no armada, and both fleets sail on
  const gone = await cmdArmadaDisband(armada.id)
  expect(gone.ok).toBe(true)
  expect((await armadas()).armadas).toHaveLength(0)
  expect((await fleets()).every((f) => f.status === 'SAILING')).toBe(true)
  const again = await cmdArmadaDisband(armada.id)
  expect(!again.ok && again.refusal.code).toBe('E_NO_SUCH_ARMADA')
})
