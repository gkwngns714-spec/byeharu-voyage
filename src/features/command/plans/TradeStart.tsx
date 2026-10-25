import { useState } from 'react'
import { Chip, ChipRow, Col, Hint, Icon, Row, Skeleton, goodIcon } from '../../../components/ui'
import { fleetCargoByCode } from '../../../domain/fleet'
import { usePortMarket } from '../../../live/usePortMarket'
import { useWorld } from '../../../live/worldStore'
import { formatPrice, formatUnits } from '../../../lib/format'
import type { FleetView, SnapshotGood } from '../../../lib/rpc'
import { useDeskPlan, type PlanDraft } from './planDraft'
import { useT } from '../../../lib/i18n'

// START — the two ways into a trade (docs/COMMAND_REDESIGN.md §2; "Go to" is R5):
//
//   Cargo  what is on board (`fleetCargoByCode`, the fleet's own cargo) → the plan sells it (buyAt null)
//   Here   what this port sells (world.market's `offered` rows — the read the quay already makes; at sea, the
//          next port's) → the plan buys it here, then sells it
//
// A good pressed OPENS THE DRAFT (planDraft.ts) with no sell city yet; the sell list under this answers "where".
// Every figure is served: units aboard, the port's own price. Labels are 1–2 words (owner row 202). Each good is a
// `Row` with its figure in a `Col` (owner rows 196–201: every list lines up on the one row primitive).

export function TradeStart({ fleet, plan }: { fleet: FleetView; plan: PlanDraft | null }) {
  const t = useT()
  const goodByCode = useWorld((s) => s.goodByCode)
  const portByCode = useWorld((s) => s.portByCode)
  const open = useDeskPlan((s) => s.open)
  const docked = fleet.status === 'DOCKED' ? fleet.port : null
  const herePort = docked ?? fleet.voyage?.to ?? null
  const [start, setStart] = useState<'hold' | 'here'>(() => (plan ? (plan.buyAt === null ? 'hold' : 'here') : herePort ? 'here' : 'hold'))
  const quay = usePortMarket(start === 'here' && herePort ? (portByCode[herePort]?.id ?? null) : null)
  const cargo = fleetCargoByCode(fleet)

  const pick = (good: SnapshotGood) =>
    open({ good: good.code, buyAt: start === 'hold' ? null : herePort, sellAt: null, units: null, max: null, min: null, insure: false })

  const holdRows = Object.entries(cargo)
    .filter(([, units]) => units > 0)
    .map(([code, units]) => ({ good: goodByCode[code] ?? null, units }))
    .filter((r): r is { good: SnapshotGood; units: number } => r.good !== null)
    .sort((a, b) => a.good.name.localeCompare(b.good.name))
  const hereRows = (quay.market?.goods ?? [])
    .filter((g) => g.offered !== false)
    .map((g) => ({ good: goodByCode[g.code] ?? null, price: g.buy }))
    .filter((r): r is { good: SnapshotGood; price: number } => r.good !== null)
    .sort((a, b) => a.good.name.localeCompare(b.good.name))
  const on = (code: string) => plan !== null && plan.good === code && (plan.buyAt === null) === (start === 'hold')

  return (
    <div data-testid="trade-start">
      <ChipRow label={t('desk.start')}>
        <Chip on={start === 'hold'} onClick={() => setStart('hold')} className="shrink-0 whitespace-nowrap" data-testid="trade-start-hold">
          {t('desk.hold')}
        </Chip>
        <Chip on={start === 'here'} onClick={() => setStart('here')} className="shrink-0 whitespace-nowrap" data-testid="trade-start-here">
          {docked ? t('desk.here') : t('desk.nextPort')}
        </Chip>
      </ChipRow>
      <div className="mt-2" data-testid="trade-goods">
        {start === 'hold' ? (
          holdRows.length === 0 ? (
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
          )
        ) : !herePort ? (
          <Hint>{t('desk.hereNone')}</Hint>
        ) : quay.market === undefined ? (
          Array.from({ length: 4 }, (_, i) => <Skeleton key={i} className="my-1 h-row w-full" />)
        ) : hereRows.length === 0 ? (
          <Hint>{t('desk.hereNone')}</Hint>
        ) : (
          hereRows.map((r, i) => (
            <GoodRow key={r.good.code} good={r.good} figure={formatPrice(r.price)} on={on(r.good.code)} last={i === hereRows.length - 1} onPick={() => pick(r.good)} />
          ))
        )}
      </div>
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
