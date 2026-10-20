import { Row, SheetSection } from '../../../components/ui'
import { GoToLink } from '../../../chart'
import { formatDucats } from '../../../lib/format'
import { worldInsurance } from '../../../lib/rpc'
import type { InsuranceView } from '../../../lib/rpc'
import { portNameOf, useWorld } from '../../../live/worldStore'
import { useServedRead } from '../../../live/useServedRead'

// INSURANCE ON THE PLANS FACE (0213) — the caller's insured voyages under way, and the last ones the
// insurance paid on, as `world.insurance()` serves them. One read on the world's beat while the face is
// up; nothing is added up here. The section stands only when there is something to say: an empty
// insurance book prints no heading (the owner's map-UX law: a clean desk, minimal words).
//
//   Insurance
//   Gaivota → Funchal            12 🪙
//     cargo worth 2,000 🪙 · insured at Lisbon
//   Gaivota · Lisbon paid 1,800 🪙   (lost 2,000 🪙)
export function InsuredVoyages() {
  const portByCode = useWorld((s) => s.portByCode)
  const read = useServedRead<InsuranceView>('insurance', worldInsurance)
  const v = read.view
  if (!v || (v.active.length === 0 && v.paid.length === 0)) return null
  const name = (c: string) => portNameOf(portByCode, c)
  return (
    <SheetSection heading="Insurance" surface data-testid="desk-insurance">
      {v.active.map((a) => (
        <Row
          key={a.voyage_id}
          label={
            <span>
              {a.fleet}
              {a.to ? (
                <>
                  {' → '}
                  <GoToLink to={{ kind: 'port', code: a.to }}>{name(a.to)}</GoToLink>
                </>
              ) : null}
            </span>
          }
          value={formatDucats(a.price)}
          data-testid="desk-insurance-active"
        >
          <span className="block text-t-caption text-ink-faint">
            {`cargo worth ${formatDucats(a.value)} · insured at `}
            <GoToLink to={{ kind: 'port', code: a.port }}>{name(a.port)}</GoToLink>
          </span>
        </Row>
      ))}
      {v.paid.map((p) => (
        <Row
          key={`paid:${p.voyage_id}`}
          tone="muted"
          label={`${p.fleet} · ${name(p.port)} paid ${formatDucats(p.paid)}`}
          value={`lost ${formatDucats(p.lost_value)}`}
          data-testid="desk-insurance-paid"
        >
          {p.short > 0 && (
            <span className="block text-t-caption text-ink-faint">{`${formatDucats(p.short)} more was owed; the city could not pay it`}</span>
          )}
        </Row>
      ))}
    </SheetSection>
  )
}
