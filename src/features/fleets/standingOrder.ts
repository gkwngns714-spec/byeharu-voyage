import { useEffect, useState } from 'react'
import { useWorld } from '../../live/worldStore'
import type { FleetView, ProvisionPreset, ProvisionPresetBook } from '../../lib/rpc'

// THE STANDING ORDER, AS ONE NUMBER — "keep her at N days of stores".
//
// ── WHAT THE SERVER HOLDS, AND WHAT THE PLAYER SEES ────────────────────────────────────────────
// 0034 keeps a BOOK: up to `max` named presets, each `days`, and every fleet points at one or none.
// The old Fleets tab drew the book as a CRUD card — a name field, a days field, a strike, a `New`
// button and "The book is empty. Not an error — a state." — and then a row of chips on each
// fleet's galley face to pick one. docs/UI_DIRECTION.md §6 cuts the card and draws the order as
// what it is to the player: `Keep 15 d [−][+]` on the fleet's stores face.
//
// So this file turns ONE NUMBER into the book operations that make it true, and nothing else in
// features/fleets knows the book has names. The rule, in order, and none of it is arithmetic:
//   1. 0 days          → lift her order (nothing, when she has none).
//   2. an order already says N days → put her under it. The book is shared across fleets on
//                        purpose (0034), so two fleets kept at 15 d are one order.
//   3. she alone sails under her order → re-day that order. It is hers and nobody else's; a fleet
//                        that is not under it does not move.
//   4. room in the book → write a new order.
//   5. an order nobody sails under → re-day and rename that one. The book recycles itself, so
//                        a player who never sees the book never fills it.
//   6. otherwise write anyway and let the server refuse E_PRESET_CAP in its own sentence — the
//                        book is genuinely full of orders other fleets are under.
// The plan is a pure function (`planKeep`) so the rule can be read without a browser; the hook
// under it runs the plan through the store's own preset verbs and nothing else.

export type KeepPlan =
  | { kind: 'lift' }
  | { kind: 'apply'; presetId: string }
  | { kind: 'adjust'; presetId: string; rename: boolean; apply: boolean }
  | { kind: 'create'; name: string }

/** "1 day", "15 days" — the one spelling of a keep level, on the button, the chips and the name. */
export const keepDays = (days: number) => `${days} ${days === 1 ? 'day' : 'days'}`

/** The name a written order gets. The player never types one now, so it says what it is. */
const orderName = (days: number) => `Keep ${keepDays(days)}`

/** The order this fleet sails under — the BOOK is the authority (the fleet points at a preset by
 *  reference on the server; the book serves that edge), so nothing here is a copy. */
export function fleetOrder(book: ProvisionPresetBook | null, fleetId: string): ProvisionPreset | null {
  return book?.presets.find((p) => p.fleets.some((f) => f.id === fleetId)) ?? null
}

/** What has to happen to the book for `fleetId` to be kept at `days`. Null when nothing does. */
export function planKeep(book: ProvisionPresetBook, fleetId: string, days: number): KeepPlan | null {
  const own = fleetOrder(book, fleetId)
  if (days <= 0) return own ? { kind: 'lift' } : null
  const exact = book.presets.find((p) => p.days === days)
  if (exact) return exact.id === own?.id ? null : { kind: 'apply', presetId: exact.id }
  if (own && own.fleets.length === 1) return { kind: 'adjust', presetId: own.id, rename: true, apply: false }
  if (book.presets.length < book.max) return { kind: 'create', name: orderName(days) }
  const orphan = book.presets.find((p) => p.fleets.length === 0)
  if (orphan) return { kind: 'adjust', presetId: orphan.id, rename: true, apply: true }
  return { kind: 'create', name: orderName(days) }
}

/**
 * The fleet's standing order, read and written. `keep(days)` runs the plan; it answers false when
 * the server refused, and the refusal itself is in the store (`refusal`) for the face to print.
 */
export function useStandingOrder(fleet: FleetView) {
  const book = useWorld((s) => s.presets)
  const loadPresets = useWorld((s) => s.loadPresets)
  const savePreset = useWorld((s) => s.savePreset)
  const applyPreset = useWorld((s) => s.applyPreset)
  const [busy, setBusy] = useState(false)

  // The server fires standing orders on arrival whether or not anyone looks, so the read is
  // display, not mechanism: one fetch when the tray opens is enough (each verb re-reads after it).
  useEffect(() => {
    void loadPresets()
  }, [loadPresets])

  const order = fleetOrder(book, fleet.id)

  const keep = async (days: number): Promise<boolean> => {
    if (!book || busy) return false
    const plan = planKeep(book, fleet.id, days)
    if (!plan) return true
    setBusy(true)
    try {
      switch (plan.kind) {
        case 'lift':
          return await applyPreset(fleet.id, null)
        case 'apply':
          return await applyPreset(fleet.id, plan.presetId)
        case 'adjust': {
          const saved = await savePreset(plan.presetId, plan.rename ? orderName(days) : null, days)
          if (!saved) return false
          return plan.apply ? await applyPreset(fleet.id, plan.presetId) : true
        }
        case 'create': {
          const saved = await savePreset(null, plan.name, days)
          if (!saved) return false
          // `savePreset` re-reads the book before it answers; the written order is in it by days.
          const written = useWorld.getState().presets?.presets.find((p) => p.days === days)
          return written ? await applyPreset(fleet.id, written.id) : false
        }
      }
    } finally {
      setBusy(false)
    }
  }

  return { book, order, busy, keep }
}
