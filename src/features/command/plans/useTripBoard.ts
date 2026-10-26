import { useMemo, useState } from 'react'
import { useGoodBoard } from '../../../live/useDesk'
import { useWorld } from '../../../live/worldStore'
import type { FleetView, GoodBoard } from '../../../lib/rpc'
import type { PlanDraft } from './planDraft'
import { tripRows } from './planLines'
import type { MapDrawing } from './TradeMap'
import { usePlanCourse } from './usePlanCourse'

// THE TRIP'S BOARD, READ ONCE (moved 2026-10-26 from the Trade face, owner row 218 — the Buy and Sell faces both make
// a trip, so the reading is theirs, here, once). world.good_board for the plan's good, FROM its buy city FOR the asked
// amount (0171, 0188, 0225), handed to the sell list and the card; the plan's legs, proposed once, handed to the map on
// top and the card's leg list. Every figure is served; nothing is added up here.
//
// THE UNITS THE BOARD PRICES: what the player typed, else — once a sell city is chosen — the units that fit beside the
// stores that leg asks (the row's served `supplies.units_fit`, 0225), so a BUY never fills the room the casks need.
// The first read prices the capacity; the row then names the fit and the board is asked again for it.
//
// THE LAST BOARD STANDS WHILE THE NEXT IS ASKED (a press selects; nothing above the card moves): a re-ask for other
// units would otherwise empty the sell list for a beat and the card would jump. A new good or buy city starts clean.

export function useTripBoard(fleet: FleetView, plan: PlanDraft | null) {
  const goodByCode = useWorld((s) => s.goodByCode)
  const portByCode = useWorld((s) => s.portByCode)
  const good = plan ? (goodByCode[plan.good] ?? null) : null
  const buyPort = plan?.buyAt ? (portByCode[plan.buyAt] ?? null) : null
  const [units, setUnits] = useState<number | null>(null)
  const board = useGoodBoard(good?.id ?? null, fleet.id, fleet.version, plan?.buyAt ? (plan.units ?? units) : null, buyPort?.id ?? null)
  const heldKey = `${good?.id ?? ''}:${plan?.buyAt ?? ''}`
  const [held, setHeld] = useState<{ key: string; view: GoodBoard } | null>(null)
  if (board.view && (held?.view !== board.view || held.key !== heldKey)) setHeld({ key: heldKey, view: board.view })
  const b = board.view ?? (held?.key === heldKey ? held.view : null)
  const fit = plan?.buyAt && plan.units === null && plan.sellAt ? (b?.sell.find((r) => r.port === plan.sellAt)?.supplies?.units_fit ?? null) : null
  // derive-from-the-last-render (PlanVoyage.tsx's pattern): the row's fit hands the next read its units, in place
  if (fit !== null && fit > 0 && fit !== units) setUnits(fit)
  const { buyRow, sellRow } = tripRows(b, plan ?? { buyAt: null, sellAt: null })
  const open = plan !== null && good !== null
  const legs = usePlanCourse(fleet, open ? plan : null, buyRow, sellRow)
  const ends = [plan?.buyAt ?? null, plan?.sellAt ?? null].filter((c): c is string => c !== null).join(' ')
  const drawing = useMemo<MapDrawing | null>(() => (open ? { legs, ends: ends ? ends.split(' ') : [] } : null), [open, legs, ends])
  return {
    good,
    board: b,
    loading: board.loading && !b,
    units: plan?.units ?? units,
    legs,
    drawing,
  }
}
