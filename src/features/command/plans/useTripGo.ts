import { useState } from 'react'
import { fleetCargoByCode } from '../../../domain/fleet'
import { usePress } from '../../../live/usePress'
import { portNameOf, useWorld } from '../../../live/worldStore'
import { formatPrice } from '../../../lib/format'
import { cmdArmadaSail } from '../../../lib/rpc'
import type { FleetView, GoodBoard, Refusal } from '../../../lib/rpc'
import { armadaOf, useArmadas } from '../../../live/armadas'
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
// WHAT THE TRIP COSTS AND HOW LONG IT TAKES IS THE BOARD'S ROW, WHOLE (0361; the owner, 2026-11-13: "docking - resailing
// takes time too", then "do all"). The served row's days carry the calls on the way, its supplies are her casks walked
// along the trip, its wages are what the crew will be owed, its dock fee is every call's, and its profit takes all of
// them off: the same walk the Map's Send fleet reads (world.trip_cost). Nothing is added up or asked again here.
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
  // 0367 (docs/ARMADA.md section 5): a fleet of an armada sails on the armada's order only, so her trip's one SAIL is sent as the armada's (below). Null for any other fleet.
  const armada = armadaOf(useArmadas(), fleet.id)

  const aboard = fleetCargoByCode(fleet)[plan.good] ?? 0
  const rows = tripRows(b, plan)
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
      // 0367: THE TRIP OF A FLEET IN AN ARMADA. A trip of one passage is sent in three steps: what she buys here (her own lines, run at the quay), then the ARMADA's one
      // order to the trip's city (every fleet of hers, or none), then what she sells there (her own lines, kept in her queue until she lands). A refusal at any step is
      // printed and nothing after it is sent. A trip of several passages is left to the plain path below, where the server says in its own words that she sails with her armada.
      const sails = text.lines.filter((l) => l.text.startsWith('SAIL '))
      if (armada && sails.length === 1) {
        const at = text.lines.indexOf(sails[0])
        const before = text.lines.slice(0, at)
        const after = text.lines.slice(at + 1)
        if (before.length > 0 && !(await issueLines(fleet.id, before))) {
          setRefusal(useWorld.getState().refusal)
          return
        }
        const words = sails[0].text.split(' ')
        const sent = await cmdArmadaSail(armada.id, words[1], sails[0].path ?? null, words.includes('INSURED'))
        if (!sent.ok) {
          setRefusal(sent.refusal)
          await useWorld.getState().refresh()
          return
        }
        await useWorld.getState().refresh()
        if (after.length > 0 && !(await issueLines(fleet.id, after))) {
          setRefusal(useWorld.getState().refusal)
          return
        }
        setRefusal(null)
        close()
        onQueued()
        return
      }
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
