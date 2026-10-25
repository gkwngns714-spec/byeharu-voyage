import { useState } from 'react'
import { FactsLine, Figure, Flag, Note, Row, SheetSection, Skeleton } from '../../components/ui'
import { formatDucats, formatDucatsDelta, formatInt } from '../../lib/format'
import { useT } from '../../lib/i18n'
import { worldStatsCities, type StatsCities, type StatsCityRow } from '../../lib/rpc'
import { useServedRead } from '../../live/useServedRead'
import { nationNameOf, useWorld } from '../../live/worldStore'
import { CityDetail } from './CityDetail'
import type { FaceProps } from './StatsScreen'
import { portName } from './statsFaces'

// CITIES — every harbour, open to everyone. The owner, 2026-10-25 (docs/OWNER_REQUESTS.md row 197): *"on cities,
// i want to see all the info without investment"*. Until 0223 a city's figures were bought (0214's tier gate drew
// a lock here, the overview at one stake and every good at a higher one); 0223 removed the gate and its knobs, so
// every row carries the purse and the day's figures, and a press opens the whole city (CityDetail). Nothing here
// decides what you may see: the server serves it all. Investing in a city is still a game action, not a key.

export function CitiesFace({ beat }: FaceProps) {
  const t = useT()
  const read = useServedRead<StatsCities>('stats:cities', () => worldStatsCities(), { trigger: beat })
  const v = read.view
  const [open, setOpen] = useState<string | null>(null)
  const nationByCode = useWorld((s) => s.nationByCode)

  if (read.loading && !v) return <Skeleton className="h-64 w-full" data-testid="stats-waiting" />
  if (!v) return <Note tone="danger">{t('stats.citiesFailed')}</Note>

  const flag = (c: StatsCityRow) =>
    c.nation === null ? undefined : <Flag code={c.nation} name={nationNameOf(nationByCode, c.nation)} size="body" />

  return (
    <div data-testid="stats-cities">
      {open !== null && <CityDetail portId={open} beat={beat} onClose={() => setOpen(null)} />}

      <SheetSection heading={t('stats.citiesCount', { n: formatInt(v.cities.length) })} surface data-testid="stats-cities-open">
        {v.cities.map((c, i) => (
          <Row
            key={c.id}
            mark={flag(c)}
            label={portName(c.name)}
            value={<Figure value={formatDucats(c.purse ?? 0)} />}
            chevron
            tone={open === c.id ? 'accent' : 'default'}
            onClick={() => setOpen(c.id)}
            hairline={i < v.cities.length - 1}
            data-testid="stats-city-open"
          >
            <FactsLine>
              <span>{t('stats.inFigure', { amount: formatDucatsDelta(c.income_1d ?? 0) })}</span>
              <span>{t('stats.outFigure', { amount: formatDucatsDelta(-(c.spending_1d ?? 0)) })}</span>
              <span>{t('stats.taxesFigure', { amount: formatDucats(c.taxes_1d ?? 0) })}</span>
            </FactsLine>
          </Row>
        ))}
      </SheetSection>
    </div>
  )
}
