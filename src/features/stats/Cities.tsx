import { useEffect, useState } from 'react'
import { Bar, FactsLine, Figure, Flag, Hint, Note, Row, SheetSection, Skeleton, StatCell } from '../../components/ui'
import { formatDucats, formatDucatsDelta, formatInt } from '../../lib/format'
import { useT } from '../../lib/i18n'
import { worldStatsCities, type StatsCities, type StatsCityRow } from '../../lib/rpc'
import { useServedRead } from '../../live/useServedRead'
import { nationNameOf, useWorld } from '../../live/worldStore'
import { CityDetail } from './CityDetail'
import type { FaceProps } from './StatsScreen'
import { portName, sharePct } from './statsFaces'
import { servedNow } from './statsPulse'

// CITIES — every harbour, at YOUR tier there. The owner, 2026-10-20: *"a statistic info of a city is added
// only when you invest certain amount."* The server (public.stats_city_tier) decides the tier from your
// stake in that city and sends figures only for the tier you hold; this face draws a LOCK where none came,
// and the stake that opens the next tier. It has nothing to hide, because it never received it.
//   tier 0  name, flag, a bar of how far your stake has got, "Invest N 🪙 more"
//   tier 1  purse, income and spending, taxes, what it buys and sells most
//   tier 2  every good: price and its move, stock against normal, bought and sold
//
// THE BAR ON A LOCKED ROW is the one new thing here (2026-10-20, request 188): a lock that says only
// "invest 20,000" is a wall, and a lock that shows you are two thirds of the way there is a game.

export function CitiesFace({ beat, onServed }: FaceProps) {
  const t = useT()
  const read = useServedRead<StatsCities>('stats:cities', () => worldStatsCities(), { trigger: beat })
  const v = read.view
  useEffect(() => onServed(servedNow(v)), [v, onServed])
  const [open, setOpen] = useState<string | null>(null)
  const nationByCode = useWorld((s) => s.nationByCode)

  if (read.loading && !v) return <Skeleton className="h-64 w-full" data-testid="stats-waiting" />
  if (!v) return <Note tone="danger">{t('stats.citiesFailed')}</Note>

  const unlocked = v.cities.filter((c) => c.tier > 0)
  const locked = v.cities.filter((c) => c.tier === 0)
  const stake = v.cities.reduce((n, c) => n + c.paid, 0)
  const flag = (c: StatsCityRow) =>
    c.nation === null ? undefined : <Flag code={c.nation} name={nationNameOf(nationByCode, c.nation)} size="body" />

  return (
    <div data-testid="stats-cities">
      <SheetSection heading={t('stats.readable')}>
        <div className="grid grid-cols-2 gap-x-4 gap-y-3 lg:grid-cols-4">
          <StatCell label={t('stats.citiesOpen')} value={unlocked.length} format={formatInt} size="body" tone="accent" />
          <StatCell label={t('stats.stillLocked')} value={locked.length} format={formatInt} size="body" />
          <StatCell label={t('stats.yourStake')} value={stake} format={formatDucats} size="body" />
          <StatCell label={t('stats.opensCity')} text={formatDucats(v.tier1)} size="body" />
        </div>
        <Hint className="mt-2">
          {t('stats.unlockHint', { one: formatDucats(v.tier1), two: formatDucats(v.tier2) })}
        </Hint>
      </SheetSection>

      {open !== null && <CityDetail portId={open} beat={beat} onClose={() => setOpen(null)} />}

      {unlocked.length > 0 && (
        <SheetSection heading={t('stats.yourCities', { n: formatInt(unlocked.length) })} surface data-testid="stats-cities-open">
          {unlocked.map((c, i) => (
            <Row
              key={c.id}
              mark={flag(c)}
              label={portName(c.name)}
              value={<Figure value={formatDucats(c.purse ?? 0)} />}
              chevron
              tone={open === c.id ? 'accent' : 'default'}
              onClick={() => setOpen(c.id)}
              hairline={i < unlocked.length - 1}
              data-testid="stats-city-open"
            >
              <FactsLine>
                <span>{c.tier === 2 ? t('stats.fullDetail') : t('stats.overviewWord')}</span>
                <span>{t('stats.inFigure', { amount: formatDucatsDelta(c.income_1d ?? 0) })}</span>
                <span>{t('stats.outFigure', { amount: formatDucatsDelta(-(c.spending_1d ?? 0)) })}</span>
                <span>{t('stats.taxesFigure', { amount: formatDucats(c.taxes_1d ?? 0) })}</span>
              </FactsLine>
              {c.tier === 1 && c.need !== null && (
                <>
                  {/* the sentence on its own line, never in the bar's figure slot: at 390px a
                      sentence that cannot shrink is what pushes a sheet sideways */}
                  <span className="block text-t-caption text-ink-faint">{t('stats.moreOpens', { amount: formatDucats(c.need) })}</span>
                  <Bar
                    pct={sharePct(c.paid, v.tier2)}
                    tone="accent"
                    label={t('stats.stakeFull', { name: portName(c.name) })}
                    className="mt-1"
                  />
                </>
              )}
            </Row>
          ))}
        </SheetSection>
      )}

      <SheetSection heading={t('stats.lockedHeading', { n: formatInt(locked.length) })} surface data-testid="stats-cities-locked">
        {locked.length === 0 ? (
          <Row label={t('stats.allOpen')} tone="muted" hairline={false} />
        ) : (
          locked.map((c, i) => (
            <Row
              key={c.id}
              mark={flag(c)}
              label={portName(c.name)}
              value={<span className="text-t-caption text-ink-faint">{t('stats.locked')}</span>}
              chevron
              tone={open === c.id ? 'accent' : 'default'}
              onClick={() => setOpen(c.id)}
              hairline={i < locked.length - 1}
              data-testid="stats-city-locked"
            >
              <span className="block text-t-caption text-ink-faint">{t('stats.investShort', { amount: formatDucats(c.need ?? v.tier1) })}</span>
              <Bar
                pct={sharePct(c.paid, v.tier1)}
                tone="neutral"
                label={t('stats.stakeOpen', { name: portName(c.name) })}
                className="mt-1"
              />
            </Row>
          ))
        )}
      </SheetSection>
    </div>
  )
}
