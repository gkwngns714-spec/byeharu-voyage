import { useEffect, useState } from 'react'
import { Bar, FactsLine, Figure, Flag, Hint, Note, Row, SheetSection, Skeleton, StatCell } from '../../components/ui'
import { formatDucats, formatDucatsDelta, formatInt } from '../../lib/format'
import { worldStatsCities, type StatsCities, type StatsCityRow } from '../../lib/rpc'
import { useServedRead } from '../../live/useServedRead'
import { nationNameOf, useWorld } from '../../live/worldStore'
import { CityDetail } from './CityDetail'
import type { FaceProps } from './StatsScreen'
import { sharePct } from './statsFaces'
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
  const read = useServedRead<StatsCities>('stats:cities', () => worldStatsCities(), { trigger: beat })
  const v = read.view
  useEffect(() => onServed(servedNow(v)), [v, onServed])
  const [open, setOpen] = useState<string | null>(null)
  const nationByCode = useWorld((s) => s.nationByCode)

  if (read.loading && !v) return <Skeleton className="h-64 w-full" data-testid="stats-waiting" />
  if (!v) return <Note tone="danger">The cities' figures could not be read.</Note>

  const unlocked = v.cities.filter((c) => c.tier > 0)
  const locked = v.cities.filter((c) => c.tier === 0)
  const stake = v.cities.reduce((n, c) => n + c.paid, 0)
  const flag = (c: StatsCityRow) =>
    c.nation === null ? undefined : <Flag code={c.nation} name={nationNameOf(nationByCode, c.nation)} size="body" />

  return (
    <div data-testid="stats-cities">
      <SheetSection heading="What you can read">
        <div className="grid grid-cols-2 gap-x-4 gap-y-3 lg:grid-cols-4">
          <StatCell label="Cities open to you" value={unlocked.length} format={formatInt} size="body" tone="accent" />
          <StatCell label="Still locked" value={locked.length} format={formatInt} size="body" />
          <StatCell label="Your stake in them" value={stake} format={formatDucats} size="body" />
          <StatCell label="Opens a city" text={formatDucats(v.tier1)} size="body" />
        </div>
        <Hint className="mt-2">
          {`A city's figures are intelligence you buy by investing there: ${formatDucats(v.tier1)} opens its overview, ${formatDucats(v.tier2)} every good's detail.`}
        </Hint>
      </SheetSection>

      {open !== null && <CityDetail portId={open} beat={beat} onClose={() => setOpen(null)} />}

      {unlocked.length > 0 && (
        <SheetSection heading={`Your cities · ${formatInt(unlocked.length)}`} surface data-testid="stats-cities-open">
          {unlocked.map((c, i) => (
            <Row
              key={c.id}
              mark={flag(c)}
              label={c.name}
              value={<Figure value={formatDucats(c.purse ?? 0)} />}
              chevron
              tone={open === c.id ? 'accent' : 'default'}
              onClick={() => setOpen(c.id)}
              hairline={i < unlocked.length - 1}
              data-testid="stats-city-open"
            >
              <FactsLine>
                <span>{c.tier === 2 ? 'full detail' : 'overview'}</span>
                <span>{`in ${formatDucatsDelta(c.income_1d ?? 0)}`}</span>
                <span>{`out ${formatDucatsDelta(-(c.spending_1d ?? 0))}`}</span>
                <span>{`taxes ${formatDucats(c.taxes_1d ?? 0)}`}</span>
              </FactsLine>
              {c.tier === 1 && c.need !== null && (
                <>
                  {/* the sentence on its own line, never in the bar's figure slot: at 390px a
                      sentence that cannot shrink is what pushes a sheet sideways */}
                  <span className="block text-t-caption text-ink-faint">{`${formatDucats(c.need)} more opens every good here`}</span>
                  <Bar
                    pct={sharePct(c.paid, v.tier2)}
                    tone="accent"
                    label={`${c.name}: your stake against the full detail`}
                    className="mt-1"
                  />
                </>
              )}
            </Row>
          ))}
        </SheetSection>
      )}

      <SheetSection heading={`Locked · ${formatInt(locked.length)}`} surface data-testid="stats-cities-locked">
        {locked.length === 0 ? (
          <Row label="Every city is open to you." tone="muted" hairline={false} />
        ) : (
          locked.map((c, i) => (
            <Row
              key={c.id}
              mark={flag(c)}
              label={c.name}
              value={<span className="text-t-caption text-ink-faint">locked</span>}
              chevron
              tone={open === c.id ? 'accent' : 'default'}
              onClick={() => setOpen(c.id)}
              hairline={i < locked.length - 1}
              data-testid="stats-city-locked"
            >
              <span className="block text-t-caption text-ink-faint">{`Invest ${formatDucats(c.need ?? v.tier1)} to see this city's figures`}</span>
              <Bar
                pct={sharePct(c.paid, v.tier1)}
                tone="neutral"
                label={`${c.name}: your stake against what opens its figures`}
                className="mt-1"
              />
            </Row>
          ))
        )}
      </SheetSection>
    </div>
  )
}
