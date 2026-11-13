import { FactsLine } from '../../components/ui'
import { formatDucats, formatInt, formatKnots, formatOfTotal } from '../../lib/format'
import type { FleetView } from '../../lib/rpc'
import { useT } from '../../lib/i18n'

// THE FLEET'S TOTALS, ONE LINE (0354, docs/FLEETS_AND_SLOTS.md section 2.5; owner row 180: "show stats of individual ship and also as a fleet").
// Every figure is SERVED (`totals`, public.fleet_totals: the sums of the very ship reads drawn under it, the wage authority's day, the slowest ship). Nothing is added up here.
// The line wraps and cuts no name: the slowest ship and a ship short of hands are printed whole. A server before 0354 serves no `totals` and nothing is drawn.

export function FleetTotals({ fleet }: { fleet: FleetView }) {
  const t = useT()
  const s = fleet.totals
  if (!s || s.ships === 0) return null
  return (
    <FactsLine className="mb-1" data-testid="fleet-totals">
      <span data-testid="fleet-total-attack">
        {t('fleets.attack')} <span className="tabular-nums text-ink">{formatInt(s.attack)}</span>
      </span>
      <span data-testid="fleet-total-hull">
        {t('fleets.hullSum')} <span className="tabular-nums text-ink">{formatOfTotal(s.hull, s.hull_max)}</span>
      </span>
      <span data-testid="fleet-total-crew">
        {t('fleets.crew')} <span className="tabular-nums text-ink">{formatOfTotal(s.crew, s.crew_max)}</span>
      </span>
      <span data-testid="fleet-total-wages">
        {t('fleets.wages')} <span className="tabular-nums text-ink">{t('fleets.perDay', { amount: formatDucats(Math.round(s.wages_day)) })}</span>
      </span>
      {/* 0215: the fleet's wave resistance, the average of her ships' (public.fleet_wave): what a sea asks of her */}
      {fleet.wave != null && (
        <span data-testid="fleet-total-wave">
          {t('desk.waveResistance')} <span className="tabular-nums text-ink">{formatInt(fleet.wave)}</span>
        </span>
      )}
      {s.slowest && (
        <span className="break-words" data-testid="fleet-total-slowest">
          {t('fleets.slowest')} <span className="text-ink">{s.slowest.name}</span> <span className="tabular-nums">{formatKnots(s.slowest.speed)}</span>
        </span>
      )}
      {s.short_crew.length > 0 && (
        <span className="break-words text-warning" data-testid="fleet-total-short">
          {t('fleets.shortCrew')} {s.short_crew.join(', ')}
        </span>
      )}
    </FactsLine>
  )
}
