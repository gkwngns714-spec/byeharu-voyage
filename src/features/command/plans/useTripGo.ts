import { useState } from 'react'
import { fleetCargoByCode } from '../../../domain/fleet'
import { usePress } from '../../../live/usePress'
import { useWorld } from '../../../live/worldStore'
import type { FleetView, GoodBoard, Refusal } from '../../../lib/rpc'
import { useT } from '../../../lib/i18n'
import { useDeskPlan, type PlanDraft } from './planDraft'
import { planLines, tripRows } from './planLines'

// GO — THE ONE WAY A PLANNED TRIP IS QUEUED (moved 2026-10-26 out of the trade card, owner row 229: the Buy / Sell
// panel's Sail & buy and Sail & sell press it). Two trips, one rule:
//
//   SAIL & BUY   plan.buyAt = the city pressed, no sell city:  SAIL … / BUY <good> <units|ALL>
//   SAIL & SELL  plan.sellAt = the city pressed, no buy city:  SAIL … / SELL <good> ALL
//
// The lines are planLines.ts's (the grammar's own text); cmd.issue_lines queues them all or none.
//
// WHY GO CANNOT RUN is read off the board, never judged here — the first that bites, in 1–2 words (row 202): Too far ·
// Cargo full · Shut · No cargo · No money. The trip's END row is the sell row on a sale and the buy row on a purchase.

export function useTripGo({
  fleet,
  plan,
  board: b,
  units: boardUnits,
  onQueued,
}: {
  fleet: FleetView
  plan: PlanDraft
  board: GoodBoard | null
  /** The units the board was asked for; null = all that fit. */
  units: number | null
  onQueued: () => void
}) {
  const t = useT()
  const portByCode = useWorld((s) => s.portByCode)
  const seaNav = useWorld((s) => s.seaNav)
  const ducats = useWorld((s) => s.ducats)
  const issueLines = useWorld((s) => s.issueLines)
  const close = useDeskPlan((s) => s.close)
  const [refusal, setRefusal] = useState<Refusal | null>(null)
  const [noCourse, setNoCourse] = useState<string | null>(null)
  const press = usePress()

  const aboard = fleetCargoByCode(fleet)[plan.good] ?? 0
  const rows = tripRows(b, plan)
  const { buyRow, sellRow, supplies } = rows
  const end = plan.sellAt ? sellRow : buyRow
  const outlay = (buyRow?.cost ?? 0) + (supplies?.cost ?? 0)

  const stop: string | null =
    !end || !seaNav
      ? null
      : (plan.buyAt && buyRow?.sailable === false) || end.sailable === false
        ? (plan.buyAt && buyRow?.stops == null) || end.stops == null
          ? t('desk.far')
          : supplies && !supplies.fits
            ? t('desk.holdFull')
            : t('desk.shut')
        : supplies && !supplies.fits
          ? t('desk.holdFull')
          : !plan.buyAt && aboard <= 0
            ? t('desk.holdEmpty')
            : ducats !== null && outlay > ducats
              ? t('desk.noMoney')
              : null

  const go = () =>
    press.run(async () => {
      if (!seaNav || stop !== null || !end) return
      // the BUY carries the units the board priced (asked, else ALL) — never more than it priced
      const text = planLines({ ...plan, units: boardUnits }, fleet, seaNav, portByCode, { toBuy: buyRow?.stops ?? [], toSell: sellRow?.stops ?? [] })
      if (!text.ok) {
        setNoCourse(text.noCourseTo)
        return
      }
      setNoCourse(null)
      if (await issueLines(fleet.id, text.lines)) {
        setRefusal(null)
        close()
        onQueued()
      } else {
        setRefusal(useWorld.getState().refusal)
      }
    })

  return { ...rows, end, stop, go, pending: press.pending, refusal, noCourse, ready: end !== null && stop === null }
}
