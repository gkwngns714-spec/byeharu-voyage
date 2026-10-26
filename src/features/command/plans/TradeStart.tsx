import { Chip, ChipRow, Col, Hint, Icon, Row, goodIcon } from '../../../components/ui'
import { fleetCargoByCode } from '../../../domain/fleet'
import { useWorld } from '../../../live/worldStore'
import { formatUnits } from '../../../lib/format'
import type { FleetView, SnapshotGood } from '../../../lib/rpc'
import { useDeskPlan, type PlanDraft } from './planDraft'
import { useT } from '../../../lib/i18n'

// START — the two ways into a trade (docs/COMMAND_REDESIGN.md §2; "Go to" is R5):
//
//   Cargo  what is on board (`fleetCargoByCode`, the fleet's own cargo) → a good pressed opens the TRIP draft
//          (planDraft.ts) with no sell city yet; the sell list under this answers "where", the card has the days
//          and the supplies, Go queues the trip
//   Here   THE PORT'S MARKET (owner row 210, 2026-10-26): the chips only stand here; the market itself — cargo,
//          buy price, sell price, Buy / Sell at once — is the centre pane (HereMarket.tsx). No trip, no days.
//
// Which start is up is the page's (Trade.tsx), so the centre can follow it. Every figure is served. Labels are
// 1–2 words (owner row 202). Each good is a `Row` with its figure in a `Col` (owner rows 196–201).

export type TradeStartKind = 'hold' | 'here'

export function TradeStart({
  fleet,
  plan,
  start,
  onStart,
}: {
  fleet: FleetView
  plan: PlanDraft | null
  start: TradeStartKind
  onStart: (start: TradeStartKind) => void
}) {
  const t = useT()
  const goodByCode = useWorld((s) => s.goodByCode)
  const open = useDeskPlan((s) => s.open)
  const docked = fleet.status === 'DOCKED' ? fleet.port : null
  const cargo = fleetCargoByCode(fleet)

  const pick = (good: SnapshotGood) =>
    open({ good: good.code, buyAt: null, sellAt: null, units: null, max: null, min: null, insure: false })

  const holdRows = Object.entries(cargo)
    .filter(([, units]) => units > 0)
    .map(([code, units]) => ({ good: goodByCode[code] ?? null, units }))
    .filter((r): r is { good: SnapshotGood; units: number } => r.good !== null)
    .sort((a, b) => a.good.name.localeCompare(b.good.name))
  const on = (code: string) => plan !== null && plan.good === code && plan.buyAt === null

  return (
    <div data-testid="trade-start">
      <ChipRow label={t('desk.start')}>
        <Chip on={start === 'hold'} onClick={() => onStart('hold')} className="shrink-0 whitespace-nowrap" data-testid="trade-start-hold">
          {t('desk.hold')}
        </Chip>
        <Chip on={start === 'here'} onClick={() => onStart('here')} className="shrink-0 whitespace-nowrap" data-testid="trade-start-here">
          {docked ? t('desk.here') : t('desk.nextPort')}
        </Chip>
      </ChipRow>
      {start === 'hold' && (
        <div className="mt-2" data-testid="trade-goods">
          {holdRows.length === 0 ? (
            <Hint>{t('desk.holdEmpty')}</Hint>
          ) : (
            holdRows.map((r, i) => (
              <GoodRow
                key={r.good.code}
                good={r.good}
                figure={t('desk.aboard', { units: formatUnits(r.units) })}
                on={on(r.good.code)}
                last={i === holdRows.length - 1}
                onPick={() => pick(r.good)}
              />
            ))
          )}
        </div>
      )}
    </div>
  )
}

/** One good to start from: the mark, the name, one served figure. The whole row is the press. */
function GoodRow({ good, figure, on, last, onPick }: { good: SnapshotGood; figure: string; on: boolean; last: boolean; onPick: () => void }) {
  return (
    <Row
      mark={<Icon name={goodIcon(good.code, good.category)} size={20} className="text-ink-muted" />}
      label={good.name}
      value={<Col w="lg">{figure}</Col>}
      tone={on ? 'accent' : 'default'}
      hairline={!last}
      onClick={onPick}
      aria-pressed={on}
      data-testid="trade-good"
      data-good={good.code}
    />
  )
}
