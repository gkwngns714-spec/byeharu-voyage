import { test, expect } from '@playwright/test'
import { openLocalDb, type LocalDb } from '../src/lib/db/localDb'
import { loadChain } from '../src/lib/db/chainSource.node.mjs'
import { builtWorldImage } from './builtWorld.fixture'
import { clearBackend, cmdFoundHouse, cmdRenameCompany, createLocalBackend, setBackend, worldPlayer } from '../src/lib/rpc'
import { headline } from '../src/features/ledger/headline'
import { companyNameToSend } from '../src/features/found/companyName'

// ═════════════════════════════════════════════════
// A COMPANY TAKES A NEW NAME: THE SEAM (0503; the owner's specification of 2026-11-25, plan slice A1): the founding door and the rename
// door through the client's one RPC layer, on the built world. Proof 205 proves the server's rule. This proves the shapes the client
// types promise and what the two screens print: the rule's own sentence at the founding and at the rename, the served `rename_free`
// that words the press, and the plain refusal of a second rename. No step reads the clock; every company here is this spec's own.
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

const player = async () => {
  const r = await worldPlayer()
  if (!r.ok) throw new Error(r.refusal.sentence)
  return r.value.player
}

test('the name as it is sent: trimmed, and an accent typed as a separate mark composed', () => {
  expect(companyNameToSend('  Casa Nova  ')).toBe('Casa Nova')
  expect(companyNameToSend('Café Nova')).toBe('Café Nova')
  expect(companyNameToSend('Casa  Nova')).toBe('Casa  Nova') // two spaces are the server's to refuse, not this file's to mend
})

// A SECOND ACCOUNT, with no company: the local world seeds its own house at boot, so the founding door is asked as another signed-in
// account (the server's own identity step, cmd.assume_identity, first in the same statement), and its answer is the door's envelope.
const NEWCOMER = '00000000-0503-4000-8000-0000000003a1'
type Envelope = { ok: boolean; error_code?: string; error_message?: string; fixes?: string[]; company_name?: string }
const foundAsNewcomer = (name: string) =>
  db.callAs<Envelope>(
    `with me as materialized (select cmd.assume_identity($1::uuid) as x) select cmd.found_house($2, 'PRT') as result from me`,
    [NEWCOMER, name],
  )
const newcomerHouses = () => db.callAs<number>(`select count(*)::int as result from public.players p where p.auth_uid = $1::uuid`, [NEWCOMER])

test('founding: a bad or taken name is refused with the sentence of the rule and no company is made; a good name founds one with her free rename', async () => {
  const cases: [string, string, RegExp][] = [
    ['A*B', 'E_BAD_NAME', /No special characters/],
    ['ab', 'E_BAD_NAME', /3 to 24 characters/],
    ['Casa  Nome', 'E_BAD_NAME', /one space between words/],
    ['PORTUGAL', 'E_NAME_TAKEN', /country/],
    ['lisbon', 'E_NAME_TAKEN', /place/],
    ['Black Pepper', 'E_NAME_TAKEN', /trade good/],
    ['CASA DE AVEIRO', 'E_NAME_TAKEN', /company/], // the seeded house's name, in capitals
  ]
  for (const [name, code, sentence] of cases) {
    const r = await foundAsNewcomer(name)
    expect(r.ok, `"${name}" founded a company`).toBe(false)
    expect(r.error_code, name).toBe(code)
    expect(r.error_message ?? '', name).toMatch(sentence)
    expect(r.fixes?.length ?? 0, `${name}: a refusal carries a fix`).toBeGreaterThan(0)
    expect(await newcomerHouses(), `"${name}" left a company behind`).toBe(0)
  }
  const founded = await foundAsNewcomer(companyNameToSend('  Casa Nome Spec '))
  expect(founded).toMatchObject({ ok: true, company_name: 'Casa Nome Spec' })
  expect(await newcomerHouses()).toBe(1)
  // the client's own founding call, as the account that already keeps the seeded house: the older refusal still comes first
  const again = await cmdFoundHouse('A*B', 'PRT')
  expect(!again.ok && again.refusal.code).toBe('E_ALREADY_FOUNDED')
})

test('renaming: refused names change nothing; the first rename is free and written; the next is refused in plain words', async () => {
  const before = await player()
  if (!before) throw new Error('no company')
  for (const [name, code] of [['A*B', 'E_BAD_NAME'], ['ab', 'E_BAD_NAME'], ['Portugal', 'E_NAME_TAKEN'], ['LISBON', 'E_NAME_TAKEN'], ['black pepper', 'E_NAME_TAKEN'], ['CASA NOME SPEC', 'E_NAME_TAKEN']]) {
    const r = await cmdRenameCompany(name)
    expect(!r.ok && r.refusal.code, name).toBe(code)
    expect(!r.ok && r.refusal.sentence.length > 0, `${name}: a sentence`).toBe(true)
  }
  expect(await player()).toMatchObject({ company_name: before.company_name, renames: 0, rename_free: true, ducats: before.ducats })

  // her own name again: ok, nothing changed, nothing counted
  const same = await cmdRenameCompany(` ${before.company_name} `)
  expect(same.ok && same.value).toMatchObject({ changed: false, renames: 0, rename_free: true })

  const renamed = await cmdRenameCompany(companyNameToSend('  Casa Outra Spec '))
  expect(renamed.ok && renamed.value).toMatchObject({ from: before.company_name, to: 'Casa Outra Spec', changed: true, renames: 1, rename_free: false })
  expect(await player()).toMatchObject({ company_name: 'Casa Outra Spec', renames: 1, rename_free: false, ducats: before.ducats })

  for (const name of ['Casa Terceira Spec', before.company_name, 'A*B']) {
    const again = await cmdRenameCompany(name)
    expect(!again.ok && again.refusal.code, name).toBe('E_RENAME_PAID')
    expect(!again.ok && again.refusal.sentence, name).toBe('Your free rename is used. Another rename is not available yet.')
  }
  expect(await player()).toMatchObject({ company_name: 'Casa Outra Spec', renames: 1, rename_free: false, ducats: before.ducats })

  // the book's words
  expect(headline({ kind: 'COMPANY_RENAMED', payload: { from: 'Casa Nome Spec', to: 'Casa Outra Spec' } } as never, (code) => code)).toContain('Casa Outra Spec')
})
