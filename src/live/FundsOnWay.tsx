import { useShellState } from '../app/shellState'
import { Figure, Row } from '../components/ui'
import { formatDucats, formatRealShort, instantMs } from '../lib/format'
import type { TownHallView } from '../lib/rpc'
import { useT } from '../lib/i18n'

/** 0310: "Funds on the way": what a cargo ship is bringing this city, and when. Served only while one is, so a hall with none draws nothing. */
export function FundsOnWay({ hall }: { hall: TownHallView }) {
  const t = useT()
  const { nowMs } = useShellState()
  const way = hall.funds_on_way
  if (!way) return null
  const eta = instantMs(way.eta)
  return (
    <Row label={t('town.fundsOnWay')} value={<Figure value={formatDucats(way.ducats)} />} data-testid="city-funds-on-way">
      <div className="text-t-caption tabular-nums text-ink-muted">
        {eta !== null ? t('town.arrivesIn', { span: formatRealShort(Math.max(0, eta - nowMs)) }) : t('town.stopsAway', { n: way.stops })}
      </div>
    </Row>
  )
}
