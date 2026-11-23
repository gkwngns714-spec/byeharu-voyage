import { create } from 'zustand'
import { cmdSetShipRole, worldShipRoles, type Refusal, type ShipRole, type ShipRolesView } from '../lib/rpc'
import { useServedRead, type ServedRead } from './useServedRead'
import { useWorld } from './worldStore'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A HULL'S ROLE (0485, docs/design/roadmap-2026-11-23.md slice 17) — world.ship_roles(): her hulls' roles, the slots her third to fifth
// hulls open, the best role for a new hull, the role the next hull should fill, and the ladder (ships, routes, captains). ONE READ, shared
// by HQ's fleet rows and the goal card (one key in the cache): asked when either opens, when one of her fleets acts (a new version) and
// after a press here; never on the beat. Dark it answers {on: false} after one knob read, kept a minute.
// The one door (cmd.set_ship_role) goes through this file, so a press re-asks the read and its refusal stands where it was pressed.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const DARK_MS = 60_000
const LIT_MS = 120_000

interface RoleEdits {
  /** Moves on every committed press, so the read is asked again. */
  edits: number
  /** The hull whose press is on the wire. */
  pending: string | null
  /** The server's refusal, by hull (or by the board card's id). */
  refused: Record<string, Refusal>
  start: (key: string) => void
  done: (key: string, refusal: Refusal | null) => void
}

export const useRoleEdits = create<RoleEdits>()((set) => ({
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

/** Give her hull a role, or take it off (null). `key`: where its refusal stands (default the hull's chips). Null when it committed; else
 *  the server's refusal. */
export async function setShipRole(shipId: string, role: ShipRole | null, key: string = shipId): Promise<Refusal | null> {
  const s = useRoleEdits.getState()
  if (s.pending !== null) return null
  s.start(key)
  const done = await cmdSetShipRole(shipId, role)
  const refusal = done.ok ? null : done.refusal
  useRoleEdits.getState().done(key, refusal)
  if (done.ok) await useWorld.getState().refresh()
  return refusal
}

/** The read, lit for her company; else null (dark, signed out, a merchant, unread). */
export function litRoles(v: ShipRolesView | null): Extract<ShipRolesView, { company: true }> | null {
  return v && v.on && v.company ? v : null
}

export function useShipRoles(): ServedRead<ShipRolesView> {
  const company = useWorld((s) => s.player?.id ?? null)
  const fleets = useWorld((s) => s.fleets)
  const edits = useRoleEdits((s) => s.edits)
  const question = company === null ? null : `${company}:${edits}:${fleets.map((f) => `${f.id}.${f.version}`).join(',')}`
  return useServedRead<ShipRolesView>(company, () => worldShipRoles(), {
    question,
    trigger: 0,
    name: 'ship_roles',
    freshMs: (v: ShipRolesView) => (v.on && v.company ? LIT_MS : DARK_MS),
  })
}
