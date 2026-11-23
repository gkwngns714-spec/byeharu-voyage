import { create } from 'zustand'
import {
  cmdCancelContract,
  cmdFailContract,
  cmdPostContract,
  worldCourierContracts,
  type CourierContractsView,
  type Refusal,
  type RpcResult,
} from '../lib/rpc'
import { useServedRead, type ServedRead } from './useServedRead'
import { useWorld } from './worldStore'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// COURIER CONTRACTS (0483, docs/design/roadmap-2026-11-23.md slice 14) — world.courier_contracts(): the contracts she posted and those she
// carries. ONE READ, asked when the Requests face opens, when one of her fleets acts (a new version) and after a press here; never on the
// beat. Dark it answers {on: false} after one knob read, kept a minute. Taking and delivering are HQ's board cards (servedPress.ts); the
// three doors here (post, cancel, give up) re-ask the read, and a refusal stands where it was pressed.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const DARK_MS = 60_000
const LIT_MS = 60_000

interface ContractEdits {
  edits: number
  pending: string | null
  refused: Record<string, Refusal>
  start: (key: string) => void
  done: (key: string, refusal: Refusal | null) => void
}

export const useContractEdits = create<ContractEdits>()((set) => ({
  edits: 0,
  pending: null,
  refused: {},
  start: (key) => set({ pending: key }),
  done: (key, refusal) =>
    set((s) => {
      const refused = { ...s.refused }
      if (refusal) refused[key] = refusal
      else delete refused[key]
      return { pending: null, refused, edits: refusal ? s.edits : s.edits + 1 }
    }),
}))

async function press<T>(key: string, r: () => Promise<RpcResult<T>>): Promise<boolean> {
  const s = useContractEdits.getState()
  if (s.pending !== null) return false
  s.start(key)
  const done = await r()
  useContractEdits.getState().done(key, done.ok ? null : done.refusal)
  if (done.ok) await useWorld.getState().refresh()
  return done.ok
}

/** Post a contract from her Storage at `from` (ids). Its refusal stands under the key 'post'. */
export function postContract(a: { from: string; to: string; good: string; qty: number; reward: number; collateral: number; hours: number }): Promise<boolean> {
  return press('post', () => cmdPostContract(a.from, a.to, a.good, a.qty, a.reward, a.collateral, a.hours))
}

/** Take her own untaken contract down. */
export function cancelContract(id: string): Promise<boolean> {
  return press(id, () => cmdCancelContract(id))
}

/** Give up a contract she carries. */
export function failContract(id: string): Promise<boolean> {
  return press(id, () => cmdFailContract(id))
}

/** The read, lit for her company; else null (dark, signed out, a merchant, unread). */
export function litContracts(v: CourierContractsView | null): Extract<CourierContractsView, { company: true }> | null {
  return v && v.on && v.company ? v : null
}

export function useCourierContracts(): ServedRead<CourierContractsView> {
  const company = useWorld((s) => s.player?.id ?? null)
  const fleets = useWorld((s) => s.fleets)
  const edits = useContractEdits((s) => s.edits)
  const question = company === null ? null : `${company}:${edits}:${fleets.map((f) => `${f.id}.${f.version}`).join(',')}`
  return useServedRead<CourierContractsView>(company, () => worldCourierContracts(), {
    question,
    trigger: 0,
    name: 'courier_contracts',
    freshMs: (v: CourierContractsView) => (v.on && v.company ? LIT_MS : DARK_MS),
  })
}
