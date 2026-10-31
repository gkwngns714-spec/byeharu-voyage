import { Figure, Row } from '../components/ui'
import type { CityInvestor } from '../lib/rpc'
import { formatDucats } from '../lib/format'
import { useT } from '../lib/i18n'

// ONE GIVER ON A CITY'S BOARD (0275/0278) — the Town Hall's investor row. It lived inside
// CityTownHall.tsx until 2026-10-31, when the City page's in-place Town Hall panel gained a
// tappable Investors drawer that must list the SAME served board (owner: "investors - tappable
// where when tapped, a list slides to the right"). One recipe, two callers — never a second copy.
export function InvestorRow({ investor }: { investor: CityInvestor }) {
  const t = useT()
  return (
    <Row
      label={
        <span>
          {investor.name}
          <span className="block text-t-caption text-ink-muted">
            {`${investor.merchant ? `${t('town.merchantWord')} · ` : ''}${t('town.invested')} ${formatDucats(investor.invested)} · ${t('town.donated')} ${formatDucats(investor.donated)}`}
          </span>
        </span>
      }
      value={<Figure value={formatDucats(investor.total)} />}
      data-testid="townhall-investor"
    />
  )
}
