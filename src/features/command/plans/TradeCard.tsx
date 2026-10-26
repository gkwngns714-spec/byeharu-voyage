import { useState } from 'react'
import { Button, Chip, Field, Figure, Hint, Note, Row } from '../../../components/ui'
import { fleetCargoByCode } from '../../../domain/fleet'
import { taxFactorWords } from '../../../domain/port'
import { PortFlag } from '../../../live/PortFlag'
import { usePress } from '../../../live/usePress'
import { portNameOf, useWorld } from '../../../live/worldStore'
import { formatCountdown, formatPrice, formatPriceDelta, formatUnits, formatVoyageDays, instantMs } from '../../../lib/format'
import type { FleetView, GoodBoard, Refusal, SnapshotGood } from '../../../lib/rpc'
import { useDeskPlan, type PlanDraft } from './planDraft'
import type { PlanLeg } from '../../../domain/passage'
import { planLines, planRoute, tripRows } from './planLines'
import { PlanVoyage } from './PlanVoyage'
import { useT } from '../../../lib/i18n'
import { useShellState } from '../../../app/shellState'

// THE TRADE CARD — one good, one buy city or the hold, one sell city, one button (docs/COMMAND_REDESIGN.md §2):
//
//   Trade · Coffee
//   Buy       Lisbon · 95            [units]
//   Sell      Antwerp · 140
//   Days      6.2
//   Supplies  −120          ← what the SAIL will buy (public.supply_need, the rule cmd.do_sail buys by)
//   Wages     −40
//   Profit    +1,860        ← the board's own net after the supplies
//   [ Insure ]
//   [ Go ]  [ Route ]
//   the chart, the crew, the restrictions, the legs (PlanVoyage.tsx)
//
// EVERY FIGURE IS THE BOARD'S (world.good_board, asked FROM the chosen buy city FOR the asked amount): the sell
// row's price, days, wages, supplies and profit are printed as served. Nothing is added up here.
//
// GO queues the whole trip — SAIL … / BUY / SAIL … / SELL — through cmd.issue_lines (0175), all or none. When Go
// cannot run, the button says why in 1–2 words in place of its label (row 202): Pick sell · Too far · Cargo full ·
// No money · Shut. ROUTE seeds the route editor with the same two stops (planDraft.ts).
//
// A PRESS SELECTS: every row is always drawn (a dash while a figure is unknown), so choosing another city changes
// figures in place and moves nothing.

/** A figure field's text as a number, or null for empty / not a number. */
function asNumber(text: string): number | null {
  const n = Number(text.replace(/,/g, ''))
  return text.trim() === '' || !Number.isFinite(n) || n <= 0 ? null : n
}

export function TradeCard({
  fleet,
  good,
  plan,
  board: b,
  units: boardUnits,
  legs,
  onQueued,
  onRoute,
}: {
  fleet: FleetView
  good: SnapshotGood
  plan: PlanDraft
  board: GoodBoard | null
  /** The units the board was asked for: typed, else the row's `units_fit` (Trade.tsx); null = all that fit. */
  units: number | null
  /** The plan's legs (Trade.tsx proposes them once; the map on top draws them, the leg list prints them). */
  legs: readonly PlanLeg[]
  /** The plan is in the queue. */
  onQueued: () => void
  /** The route editor has its seed. */
  onRoute: () => void
}) {
  const t = useT()
  const portByCode = useWorld((s) => s.portByCode)
  const seaNav = useWorld((s) => s.seaNav)
  const ducats = useWorld((s) => s.ducats)
  const onCreditLit = useWorld((s) => s.player?.on_credit === true)
  const issueLines = useWorld((s) => s.issueLines)
  const { set, close, seedRoute } = useDeskPlan()
  const [units, setUnits] = useState(plan.units !== null ? String(plan.units) : '')
  const [refusal, setRefusal] = useState<Refusal | null>(null)
  const [noCourse, setNoCourse] = useState<string | null>(null)
  const press = usePress()
  const name = (c: string) => portNameOf(portByCode, c)

  const aboard = fleetCargoByCode(fleet)[good.code] ?? 0
  const { buyRow, sellRow, days, supplies } = tripRows(b, plan)
  const outlay = (buyRow?.cost ?? 0) + (supplies?.cost ?? 0)
  // 0241 (owner row 230): SHE SAILS ON CREDIT. While the server says credit is lit (world.player `on_credit`), the
  // supplies her purse cannot cover are owed to the city and paid from her next sale — they never stop Go. The
  // cargo itself is still bought with money she has.
  const onCredit = onCreditLit && ducats !== null && supplies ? Math.max(0, Math.min(supplies.cost, outlay - ducats)) : 0
  const mustPay = onCreditLit ? (buyRow?.cost ?? 0) : outlay

  // WHY GO CANNOT RUN, in the server's terms, read off the board (never judged here): the first that bites.
  const stop: string | null = !plan.sellAt
    ? t('desk.pickSell')
    : !sellRow || !seaNav
      ? null
      : (plan.buyAt && buyRow?.sailable === false) || sellRow.sailable === false
        ? (plan.buyAt && buyRow?.stops == null) || sellRow.stops == null
          ? t('desk.far')
          : supplies && !supplies.fits
            ? t('desk.holdFull')
            : t('desk.shut')
        : supplies && !supplies.fits
          ? t('desk.holdFull')
          : !plan.buyAt && aboard <= 0
            ? t('desk.holdEmpty')
            : ducats !== null && mustPay > ducats
              ? t('desk.noMoney')
              : null

  const go = () =>
    press.run(async () => {
      if (!seaNav || stop !== null) return
      // the BUY carries the units the board priced (typed, else the row's units_fit) — never ALL into the casks' room
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

  const tone = sellRow?.profit == null ? 'muted' : sellRow.profit >= 0 ? 'success' : 'danger'
  return (
    <section data-testid="trade-card">
      <h2 className="text-t-body font-semibold text-ink">{t('desk.planOf', { good: good.name })}</h2>
      <div className="mt-2" data-testid="plan-estimate">
        <Row
          label={t('desk.buy')}
          value={
            <Figure
              value={
                plan.buyAt ? (
                  <>
                    <PortFlag code={plan.buyAt} /> {name(plan.buyAt)}
                    {buyRow?.price_each != null ? ` · ${formatPrice(buyRow.price_each)}` : ''}
                  </>
                ) : (
                  t('desk.aboard', { units: formatUnits(aboard) })
                )
              }
            />
          }
          data-testid="trade-buy"
        />
        {plan.buyAt && (
          <Field
            icon={null}
            inputMode="numeric"
            value={units}
            onChange={(e) => setUnits(e.target.value)}
            onBlur={() => set({ units: asNumber(units) })}
            placeholder={t('desk.unitsAll')}
            aria-label={t('desk.units')}
            className="my-2"
            data-testid="plan-units"
          />
        )}
        <Row
          label={t('desk.sell')}
          value={
            <Figure
              value={
                plan.sellAt ? (
                  <>
                    <PortFlag code={plan.sellAt} /> {name(plan.sellAt)}
                    {sellRow ? ` · ${formatPrice(sellRow.price_each ?? sellRow.mid)}` : ''}
                  </>
                ) : (
                  '—'
                )
              }
            />
          }
          data-testid="trade-sell"
        />
        <Row label={t('desk.days')} value={<Figure value={days !== null ? formatVoyageDays(days) : '—'} />} data-testid="plan-days" />
        <Row
          label={t('desk.supplies')}
          value={<Figure value={supplies ? formatPriceDelta(-supplies.cost) : '—'} tone={supplies && !supplies.fits ? 'danger' : 'ink'} />}
          data-testid="plan-supplies"
        />
        {onCredit > 0 && (
          <Row
            label={t('desk.onCredit')}
            value={<Figure value={formatPriceDelta(-onCredit)} tone="warning" />}
            data-testid="plan-on-credit"
          />
        )}
        <Row label={t('desk.wages')} value={<Figure value={sellRow?.wages != null ? formatPriceDelta(-sellRow.wages) : '—'} />} data-testid="trade-wages" />
        {/* 0237 (§4c): the dock fee at the sell city and the country factor on its tax — served only while the economy is closed */}
        {sellRow?.dues && (
          <Row
            label={t('desk.dockFee')}
            value={<Figure value={`${formatPriceDelta(-sellRow.dues.fee)} · ${taxFactorWords(sellRow.dues)}`} />}
            data-testid="trade-dues"
          />
        )}
        <Row
          label={t('desk.profit')}
          value={<Figure value={sellRow?.profit != null ? formatPriceDelta(sellRow.profit) : '—'} tone={tone} size="figure" />}
          hairline={false}
          data-testid="trade-profit"
        />
      </div>

      {/* INSURE THE CARGO (0213): one press. The laden SAIL lines carry INSURED (planLines.ts); the price is the
          server's when she sails. */}
      <div className="mt-2 flex items-center gap-3">
        <Chip on={plan.insure === true} onClick={() => set({ insure: !plan.insure })} className="shrink-0 whitespace-nowrap" data-testid="plan-insure">
          {t('desk.insure')}
        </Chip>
        <Hint className="mt-0">{plan.insure ? t('desk.insuredHint') : t('desk.uninsuredHint')}</Hint>
      </div>

      <div className="mt-4 grid grid-cols-[2fr_1fr] gap-3">
        <Button variant="primary" onClick={go} busy={press.pending} busyLabel={t('desk.queueing')} disabled={stop !== null || !sellRow} data-testid="plan-queue">
          {stop ?? t('desk.go')}
        </Button>
        <Button
          variant="secondary"
          onClick={() => {
            seedRoute(planRoute(plan))
            onRoute()
          }}
          disabled={!plan.sellAt || !plan.buyAt}
          data-testid="plan-route"
        >
          {t('desk.route')}
        </Button>
      </div>
      {noCourse && (
        <Note tone="danger" className="mt-3">
          {t('desk.noWater', { port: name(noCourse) })}
        </Note>
      )}
      {/* 0237 (§4c): her port time — "Ready in 0:42"; a SAIL queued now leaves when it is up */}
      {fleet.ready_at && !fleet.voyage && <ReadyIn fleet={fleet} />}
      {refusal && (
        <Note tone="danger" className="mt-3" code={refusal.code} figures={refusal.figures}>
          {refusal.sentence}
        </Note>
      )}

      {/* THE VOYAGE (owner row 183): the crew, whether you can go there, the legs. Its chart is THE map on top of the
          Trade page (owner row 217, TradeMap.tsx). */}
      <PlanVoyage fleet={fleet} board={b} buyRow={buyRow} sellRow={sellRow} legs={legs} />
    </section>
  )
}

/** 0237: "Ready in 0:42" while she is in her port time — a live countdown to the served `ready_at`. */
function ReadyIn({ fleet }: { fleet: FleetView }) {
  const t = useT()
  const { nowMs } = useShellState()
  const at = instantMs(fleet.ready_at)
  if (at === null || at <= nowMs) return null
  return (
    <Hint className="mt-2" data-testid="trade-ready-in">
      {t('domain.readyIn', { t: formatCountdown(at - nowMs) })}
    </Hint>
  )
}
