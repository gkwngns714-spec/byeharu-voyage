import { useMemo, useState } from 'react'
import { fleetCargoByCode } from '../../../domain/fleet'
import { passageAsk } from '../../../domain/passage'
import { usePress } from '../../../live/usePress'
import { useHeldFleet } from '../../../live/useSailLegs'
import { useServedRead } from '../../../live/useServedRead'
import { portNameOf, useWorld } from '../../../live/worldStore'
import { formatPrice } from '../../../lib/format'
import { worldTripCost, type FleetView, type GoodBoard, type Refusal } from '../../../lib/rpc'
import { useT } from '../../../lib/i18n'
import { useDeskPlan, type PlanDraft } from './planDraft'
import { planLines, reachBoard, reachWords, tripRows } from './planLines'

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
//
// AND WHY, IN A SENTENCE (owner row 231, 2026-10-26: "i can't sell because i can't dock. and i can't move to that
// location"): a button that will not press never speaks for itself. `why` is the plain sentence under it that says
//
// THE CALLS ON THE WAY TAKE TIME (the owner, 2026-11-13: "docking - resailing takes time too"). The board's days are the
// sailing alone. A trip through harbours between also lies at each of them (0237's port time, while the economy is
// closed), so its legs are asked of world.trip_cost (0360), THE read the Map's Send fleet prices a trip by, and the real
// time of the calls it serves is added to the board's days. One leg, an open economy, or a world without that read:
// nothing is added and the days are the board's, as before.
//
// what stops it and what to do: the city does not buy the good; the board's own reach wording (planLines
// `reachWords`, the plan card's) for a city too far, shut or past her stores; nothing aboard; the money short.

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
  const goodByCode = useWorld((s) => s.goodByCode)
  const seaNav = useWorld((s) => s.seaNav)
  const ducats = useWorld((s) => s.ducats)
  const onCreditLit = useWorld((s) => s.player?.on_credit === true)
  const issueLines = useWorld((s) => s.issueLines)
  const close = useDeskPlan((s) => s.close)
  const [refusal, setRefusal] = useState<Refusal | null>(null)
  const [noCourse, setNoCourse] = useState<string | null>(null)
  const press = usePress()

  const aboard = fleetCargoByCode(fleet)[plan.good] ?? 0
  const sailing = tripRows(b, plan)
  // the trip's legs as Go will queue them, proposed while her place is unchanged (the pathfinder's work)
  const held = useHeldFleet(fleet)
  const buyStops = sailing.buyRow?.stops ?? null
  const sellStops = sailing.sellRow?.stops ?? null
  const callsKey = `${plan.buyAt ?? ''}>${(buyStops ?? []).join(',')}>${plan.sellAt ?? ''}>${(sellStops ?? []).join(',')}`
  const ask = useMemo(() => {
    if (!seaNav || !held || (buyStops ?? []).length + (sellStops ?? []).length === 0) return null
    const text = planLines(plan, held, seaNav, portByCode, { toBuy: buyStops ?? [], toSell: sellStops ?? [] })
    return text.ok && text.legs.length > 1 ? passageAsk(text.legs) : null
    // eslint-disable-next-line react-hooks/exhaustive-deps -- callsKey names the plan's cities and stops; the plan object is new every render
  }, [seaNav, held, portByCode, callsKey])
  const trip = useServedRead(ask ? fleet.id : null, () => worldTripCost(fleet.id, ask ?? []), { name: 'worldTripCost', question: ask ? callsKey : null })
  const calls = trip.view && trip.view.days !== null && trip.view.sail_days !== null ? Math.max(0, trip.view.days - trip.view.sail_days) : 0
  const rows = { ...sailing, days: sailing.days !== null ? sailing.days + calls : null }
  const { buyRow, sellRow, supplies } = rows
  const end = plan.sellAt ? sellRow : buyRow
  const outlay = (buyRow?.cost ?? 0) + (supplies?.cost ?? 0)
  // 0241 (owner row 230): SHE SAILS ON CREDIT. While the server says credit is lit (world.player `on_credit`), the
  // supplies her purse cannot cover are owed to the city and paid from her next sale — they never stop Go. The
  // cargo itself is still bought with money she has.
  const onCredit = onCreditLit && ducats !== null && supplies ? Math.max(0, Math.min(supplies.cost, outlay - ducats)) : 0
  const mustPay = onCreditLit ? (buyRow?.cost ?? 0) : outlay

  const buyCut = plan.buyAt !== null && buyRow?.sailable === false
  const kind: 'far' | 'holdFull' | 'shut' | 'holdEmpty' | 'noMoney' | null =
    !end || !seaNav
      ? null
      : buyCut || end.sailable === false
        ? (plan.buyAt && buyRow?.stops == null) || end.stops == null
          ? 'far'
          : supplies && !supplies.fits
            ? 'holdFull'
            : 'shut'
        : supplies && !supplies.fits
          ? 'holdFull'
          : !plan.buyAt && aboard <= 0
            ? 'holdEmpty'
            : ducats !== null && mustPay > ducats
              ? 'noMoney'
              : null
  const stop: string | null = kind ? t(`desk.${kind}`) : null

  const city = plan.sellAt ?? plan.buyAt
  const cityName = city ? portNameOf(portByCode, city) : ''
  const goodName = goodByCode[plan.good]?.name ?? plan.good
  // the row whose passage stops her: the way to the buy city when that is cut, else the trip's end
  const cut = buyCut && buyRow ? buyRow : end
  const why: string | null =
    !b || !seaNav || !city
      ? null
      : !end
        ? t(plan.sellAt ? 'desk.whyNoBuyer' : 'desk.whyNoSeller', { city: cityName, good: goodName })
        : kind === 'holdEmpty'
          ? t('desk.whyHoldEmpty', { good: goodName })
          : kind === 'noMoney'
            ? t('desk.whyNoMoney', { need: formatPrice(mustPay), have: formatPrice(ducats ?? 0) })
            : kind && cut
              ? `${cityName} — ${reachWords(cut, reachBoard(b))}.`
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

  return { ...rows, onCredit, end, stop, why, go, pending: press.pending, refusal, noCourse, ready: end !== null && stop === null }
}
