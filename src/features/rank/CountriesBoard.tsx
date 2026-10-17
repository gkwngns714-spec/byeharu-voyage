import { Figure, Row, SheetSection, Skeleton } from '../../components/ui'
import { formatInt } from '../../lib/format'
import { worldNationStandings } from '../../lib/rpc'
import { HullCountry } from '../../live/HullCountry'
import { useServedRead } from '../../live/useServedRead'

// RANK → COUNTRIES (0148, docs/INFLUENCE.md §5.4, OWNER O3: fame/rank for leading a city). ONE read,
// `world.nation_standings()`: every country's cities — home and won — the cities won this week, and
// its three biggest givers. Nothing is counted here; the server counts `public.port_nation`.
export function CountriesBoard() {
  const read = useServedRead('countries', worldNationStandings)
  const board = read.view
  if (!board) {
    return (
      <div className="space-y-2">
        <Skeleton className="h-12 w-full" />
        <Skeleton className="h-12 w-full" />
      </div>
    )
  }
  return (
    <SheetSection surface data-testid="rank-countries">
      {board.countries.map((c, i) => (
        <Row
          key={c.nation}
          label={<HullCountry nation={c.nation} />}
          value={<Figure value={formatInt(c.held)} />}
          hairline={i < board.countries.length - 1}
          data-testid="rank-country"
        >
          <span className="block text-t-caption text-ink-faint">
            {[
              `${formatInt(c.home)} home · ${formatInt(c.won)} won`,
              c.won_week > 0 ? `${formatInt(c.won_week)} this week` : null,
              c.top.length > 0 ? c.top.map((t) => t.name).join(', ') : null,
            ]
              .filter(Boolean)
              .join(' · ')}
          </span>
        </Row>
      ))}
    </SheetSection>
  )
}
