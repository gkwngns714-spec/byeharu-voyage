import { Bar } from '../../components/ui'
import { formatPct } from '../../lib/format'
import { useT } from '../../lib/i18n'

// THE HULL GAUGE OF A ROW ON THE FLEETS TAB: the word, the bar, the figure. A fleet's row draws her worst hull with it and a ship's row
// (FleetShips.tsx, 2026-11-14) her own, so the two rows read alike and the tone rule is written once.
// §4.4: a hull that is merely sound is NEUTRAL — green is for gain, and a whole fleet painted green spends the one colour that means
// "cheap" on a hull that is fine.
export function HullGauge({ fraction, label }: { /** 0 to 1. */ fraction: number; /** What the bar says to a reader who cannot see it. */ label: string }) {
  const t = useT()
  return (
    <span className="flex min-w-32 flex-1 items-center gap-3">
      <span className="shrink-0">{t('fleets.hull')}</span>
      <Bar
        pct={fraction * 100}
        tone={fraction < 0.4 ? 'danger' : fraction < 0.75 ? 'warning' : 'neutral'}
        label={label}
        figure={<span className="tabular-nums">{formatPct(fraction)}</span>}
        className="min-w-0 flex-1"
      />
    </span>
  )
}
