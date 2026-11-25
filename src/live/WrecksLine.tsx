import { Icon, goodIcon } from '../components/ui'
import { formatInt } from '../lib/format'
import { useT } from '../lib/i18n'
import { litRounds, salvageOf, useRounds } from './useRounds'
import { useWorld } from './worldStore'

// WRECKS WHERE THEY ARE USED (0522, owner R5: "wrecks ... that can be gathered and be used to make, upgrade ships and gears"): what her fleets' last runs took
// from beaten pirates, over the yard's and the Forge's materials. The parts are ordinary goods in those fleets' holds: land them to use them. Dark, or none
// taken: nothing is drawn. The player's own wrecked fleet is another thing.
export function WrecksLine() {
  const t = useT()
  const fleets = useWorld((s) => s.fleets)
  const goodByCode = useWorld((s) => s.goodByCode)
  const runs = litRounds(useRounds(null, fleets.length > 0).view)?.runs ?? []
  const lines = runs.map((r) => ({ run: r, parts: salvageOf(r) })).filter((x) => x.parts.length > 0)
  if (lines.length === 0) return null
  return (
    <div className="mb-3 flex flex-col gap-1" data-testid="wrecks-line">
      <span className="text-t-caption text-ink-muted">{t('corp.wrecks')}</span>
      {lines.map(({ run, parts }) => (
        <span key={run.fleet} className="flex min-h-6 flex-wrap items-center gap-x-3 gap-y-1 text-t-caption text-ink" data-fleet={run.fleet}>
          <span className="text-ink-muted">{fleets.find((f) => f.id === run.fleet)?.name ?? ''}</span>
          {parts.map((p) => (
            <span key={p.good} className="inline-flex items-center gap-1 tabular-nums">
              <Icon name={goodIcon(p.good, goodByCode[p.good]?.category ?? '')} size={16} aria-hidden />
              {goodByCode[p.good]?.name ?? p.good} {formatInt(p.qty)}
            </span>
          ))}
        </span>
      ))}
    </div>
  )
}
