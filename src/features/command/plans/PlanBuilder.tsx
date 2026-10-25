import { useState } from 'react'
import { ChipRow, Button, Chip, Field, Figure, Hint, Note, Row, Skeleton, Tray, type TrayDetent, type TrayMode } from '../../../components/ui'
import { fleetCargoByCode } from '../../../domain/fleet'
import { PortFlag } from '../../../live/PortFlag'
import { usePress } from '../../../live/usePress'
import { useGoodBoard } from '../../../live/useDesk'
import { portNameOf, useWorld } from '../../../live/worldStore'
import { formatClock, formatPrice, formatPriceDelta, formatUnits, formatVoyageDays } from '../../../lib/format'
import type { FleetView, Refusal, SnapshotGood } from '../../../lib/rpc'
import { useDeskPlan, type PlanDraft } from './planDraft'
import { planLines, planRoute, viaWords } from './planLines'
import { PlanVoyage } from './PlanVoyage'
import { useT } from '../../../lib/i18n'

// THE PLAN BUILDER (docs/COMMAND_DESK.md §3.5) — the owner's coffee example as one tray:
//
//   Plan · Coffee
//   Buy at   [Mocha] [Aden] …      60 units    Max 95 🪙
//   Sell at  [Lisbon] [Cádiz] …                Min 140 🪙
//   Estimate  cost 5,640 🪙 · you get 8,460 🪙 · net +1,860 🪙 · arrive 18:31
//   [ Queue it once ]   [ Make it a route ]
//
// THE ESTIMATE IS THE BOARD'S. world.good_board is asked FROM the chosen buy city FOR the chosen amount,
// and the sell city's row is printed as served: cost, what you get, net (after the profit tax and the
// wages), the arrival. Nothing is added up here. It is labelled Estimate because the real check is the
// order itself when it runs (a plan does not wait — COMMAND_DESK D6).
//
// QUEUE IT ONCE: the lines (planLines.ts) go to cmd.issue_lines (0175), all queued or none; the desk then
// turns to Plans, where they stand in the queue. MAKE IT A ROUTE: the route editor's own draft is seeded
// (planDraft.ts) and the editor opens on it on Plans.
//
// THE PASSAGE SHE CAN SAIL (0188). The board serves each city's `stops` (every leg within her captain's
// reach), `needs` (the Navigation a direct leg would need) and `sailable` (reach AND stores). The lines go
// through those stops (planLines.ts); a city she cannot reach says why and is not queued.
//
// A press selects: a chip or a figure changes the estimate in place (the old figures stand while the
// board is re-asked). The two buttons are busy only while their own press is on the wire (usePress).

/** A figure field's text as a number, or null for empty / not a number. */
function asNumber(text: string): number | null {
  const n = Number(text.replace(/,/g, ''))
  return text.trim() === '' || !Number.isFinite(n) || n <= 0 ? null : n
}

export function PlanBuilder({
  fleet,
  good,
  plan,
  onQueued,
  onRoute,
  mode = 'docked',
}: {
  /** A desk pane on a wide glass; docked on a phone. */
  mode?: TrayMode
  fleet: FleetView
  good: SnapshotGood
  plan: PlanDraft
  /** The plan is in the queue: the desk turns to Plans. */
  onQueued: () => void
  /** The route editor has its seed: the desk turns to Plans. */
  onRoute: () => void
}) {
  const t = useT()
  const portByCode = useWorld((s) => s.portByCode)
  const seaNav = useWorld((s) => s.seaNav)
  const issueLines = useWorld((s) => s.issueLines)
  const { set, close, seedRoute } = useDeskPlan()
  const [detent, setDetent] = useState<TrayDetent>('full')
  const [units, setUnits] = useState(plan.units !== null ? String(plan.units) : '')
  const [max, setMax] = useState(plan.max !== null ? String(plan.max) : '')
  const [min, setMin] = useState(plan.min !== null ? String(plan.min) : '')
  const [refusal, setRefusal] = useState<Refusal | null>(null)
  const [noCourse, setNoCourse] = useState<string | null>(null)
  const press = usePress()

  const aboard = fleetCargoByCode(fleet)[good.code] ?? 0
  const buyPort = plan.buyAt ? portByCode[plan.buyAt] ?? null : null
  const board = useGoodBoard(good.id, fleet.id, fleet.version, plan.buyAt ? plan.units : null, buyPort?.id ?? null)
  const b = board.view
  const sellRow = b && plan.sellAt ? (b.sell.find((r) => r.port === plan.sellAt) ?? null) : null
  const name = (c: string) => portNameOf(portByCode, c)

  const sellChoices = b ? b.sell.filter((r) => r.quoted || r.port === plan.sellAt).map((r) => r.port) : []
  const buyRow = b && plan.buyAt ? (b.buy.find((r) => r.port === plan.buyAt) ?? null) : null
  // the voyage the board serves: through its stops; a city beyond the captain's reach or the supplies is not planned
  // (why, in THE wording, is printed by PlanVoyage's "Can you go there?" — row 183 — not twice)
  const unreachable = [plan.buyAt ? buyRow : null, sellRow].find((r) => r && r.sailable === false) ?? null

  const queue = () =>
    press.run(async () => {
      if (!seaNav) return
      if (unreachable) return
      const text = planLines(plan, fleet, seaNav, portByCode, {
        toBuy: buyRow?.stops ?? [],
        toSell: sellRow?.stops ?? [],
        stores: b?.supplies ? { speedKn: b.fleet.speed_kn, days: b.supplies.days, margin: b.supplies.margin } : null,
      })
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

  return (
    <Tray
      detent={detent}
      onDetentChange={(next) => (next === 'closed' ? close() : setDetent(next))}
      title={t('desk.planOf', { good: good.name })}
      mode={mode}
      data-testid="plan-builder"
      action={
        <div className="grid grid-cols-2 gap-3">
          <Button
            variant="primary"
            onClick={queue}
            busy={press.pending}
            busyLabel={t('desk.queueing')}
            disabled={!plan.sellAt || !seaNav || (!plan.buyAt && aboard <= 0) || unreachable !== null}
            data-testid="plan-queue"
          >
            {t('desk.queueOnce')}
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
            {t('desk.makeRoute')}
          </Button>
        </div>
      }
    >
      <span className="block text-t-caption text-ink-faint">{t('desk.buyAt')}</span>
      <ChipRow label={t('desk.buyAt')} className="mt-1">
        {aboard > 0 && (
          <Chip on={plan.buyAt === null} onClick={() => set({ buyAt: null })} className="shrink-0 whitespace-nowrap">
            {t('desk.onBoardN', { units: formatUnits(aboard) })}
          </Chip>
        )}
        {(b?.buy ?? []).map((r) => (
          <Chip key={r.port} on={plan.buyAt === r.port} onClick={() => set({ buyAt: r.port })} className="shrink-0 whitespace-nowrap">
            <PortFlag code={r.port} />
            {name(r.port)}
          </Chip>
        ))}
      </ChipRow>
      {plan.buyAt && (
        <div className="mt-2 grid grid-cols-2 gap-3">
          <Field
            icon={null}
            inputMode="numeric"
            value={units}
            onChange={(e) => setUnits(e.target.value)}
            onBlur={() => set({ units: asNumber(units) })}
            placeholder={t('desk.unitsPh')}
            aria-label={t('desk.unitsToBuy')}
            data-testid="plan-units"
          />
          <Field
            icon={null}
            inputMode="decimal"
            value={max}
            onChange={(e) => setMax(e.target.value)}
            onBlur={() => set({ max: asNumber(max) })}
            placeholder={t('desk.maxPh')}
            aria-label={t('desk.maxLabel')}
            data-testid="plan-max"
          />
        </div>
      )}

      <span className="mt-4 block text-t-caption text-ink-faint">{t('desk.sellAt')}</span>
      <ChipRow label={t('desk.sellAt')} className="mt-1">
        {sellChoices.map((c) => (
          <Chip key={c} on={plan.sellAt === c} onClick={() => set({ sellAt: c })} className="shrink-0 whitespace-nowrap">
            <PortFlag code={c} />
            {name(c)}
          </Chip>
        ))}
      </ChipRow>
      <Field
        icon={null}
        inputMode="decimal"
        value={min}
        onChange={(e) => setMin(e.target.value)}
        onBlur={() => set({ min: asNumber(min) })}
        placeholder={t('desk.minPh')}
        aria-label={t('desk.minLabel')}
        className="mt-2"
        data-testid="plan-min"
      />

      {/* INSURE THE CARGO (0213): one press. The laden SAIL lines carry INSURED (planLines.ts); the price is
          the server's when she sails, from the cargo then on board, so no figure is guessed here. */}
      <span className="mt-4 block text-t-caption text-ink-faint">{t('desk.insurance')}</span>
      <ChipRow label={t('desk.insurance')} className="mt-1">
        <Chip
          on={plan.insure === true}
          onClick={() => set({ insure: !plan.insure })}
          className="shrink-0 whitespace-nowrap"
          data-testid="plan-insure"
        >
          {t('desk.insure')}
        </Chip>
      </ChipRow>
      <Hint>
        {plan.insure
          ? t('desk.insuredHint')
          : t('desk.uninsuredHint')}
      </Hint>

      {/* THE ESTIMATE — the board's row for the chosen cities and amount, as served */}
      <div className="mt-4 min-h-[156px]" data-testid="plan-estimate">
        <span className="block text-t-caption text-ink-faint">{t('desk.estimate')}</span>
        {!sellRow ? (
          board.loading && !b ? (
            <Skeleton className="mt-1 h-[140px] w-full" />
          ) : (
            <Hint>{t('desk.pickSell')}</Hint>
          )
        ) : !sellRow.quoted ? (
          <Hint>{t('desk.notDearest', { port: name(sellRow.port), price: formatPrice(sellRow.mid) })}</Hint>
        ) : (
          <>
            <Row label={t('desk.cost')} value={<Figure value={sellRow.cost !== null ? formatPrice(sellRow.cost) : '—'} />} />
            <Row label={t('desk.youGet')} value={<Figure value={sellRow.proceeds !== null ? formatPrice(sellRow.proceeds) : '—'} />} />
            <Row
              label={t('desk.net')}
              value={
                <Figure
                  value={sellRow.net !== null ? formatPriceDelta(sellRow.net) : '—'}
                  tone={sellRow.net === null ? 'muted' : sellRow.net >= 0 ? 'success' : 'danger'}
                  size="figure"
                />
              }
              hairline={false}
            />
            <Hint>
              {[
                b?.qty ? t('desk.forUnits', { units: formatUnits(b.qty.units) }) : null,
                sellRow.days !== null ? formatVoyageDays(sellRow.days) : null,
                sellRow.arrive_at ? t('desk.arrive', { time: formatClock(Date.parse(sellRow.arrive_at)) }) : null,
                viaWords([...(buyRow?.stops ?? []), ...(plan.buyAt ? [plan.buyAt] : []), ...(sellRow.stops ?? [])], name),
              ]
                .filter(Boolean)
                .join(' · ')}
            </Hint>
          </>
        )}
      </div>
      {/* THE VOYAGE (owner row 183): the chart of only this plan, how long, the supplies and crew it needs,
          and whether you can go there — PlanVoyage.tsx. Under the estimate, so nothing above moves. */}
      <PlanVoyage fleet={fleet} plan={plan} board={b} buyRow={buyRow} sellRow={sellRow} />
      {noCourse && (
        <Note tone="danger" className="mt-3">
          {t('desk.noWater', { port: name(noCourse) })}
        </Note>
      )}
      {refusal && (
        <Note tone="danger" className="mt-3" code={refusal.code} figures={refusal.figures}>
          {refusal.sentence}
        </Note>
      )}
    </Tray>
  )
}

