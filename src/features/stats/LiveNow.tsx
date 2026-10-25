import { Dot, SheetSection, StatCell } from '../../components/ui'
import { formatDucats, formatInt } from '../../lib/format'
import { useT } from '../../lib/i18n'
import type { StatsNow } from '../../lib/rpc'
import { useWorld } from '../../live/worldStore'

// RIGHT NOW — the figures on this tab that move while you watch, on every face.
//
// THE OWNER (row 200, 2026-10-25): *"i want to be updated every second"*. Three of the four cells are the
// server's live counters (world.stats_now, asked each second by statsLive.ts): all the money in the world,
// the fleets at sea — players' and merchants' — and the trades since the last count. The fourth is your
// own money, out of the store the shell already polls. Each figure counts to its new value (Counter), which
// is the moving number request 188 asks for. Before 0224 this band carried your fleets and cargo from the
// store alone, because nothing of the WORLD could honestly move faster than the fifteen-minute rollup;
// now it can, and the world's figures are what a Stats tab is for.

export function LiveNow({ live }: { live: StatsNow | null }) {
  const t = useT()
  // Selected as a primitive, one selector (worldStore's rule).
  const ducats = useWorld((s) => s.ducats)

  return (
    <SheetSection
      heading={
        <span className="flex items-center gap-2">
          <Dot tone="success" label={t('stats.live')} />
          {t('stats.rightNow')}
        </span>
      }
      data-testid="stats-live"
    >
      <div className="grid grid-cols-2 gap-x-4 gap-y-3 lg:grid-cols-4">
        <StatCell
          label={t('stats.purse')}
          value={ducats ?? 0}
          format={formatDucats}
          tone="accent"
          text={ducats === null ? '—' : undefined}
          data-testid="stats-live-purse"
        />
        <StatCell
          label={t('stats.money')}
          value={live?.total ?? 0}
          format={formatDucats}
          text={live === null ? '—' : undefined}
          data-testid="stats-live-world"
        />
        <StatCell label={t('stats.fleetsAtSea')} value={live?.at_sea ?? 0} format={formatInt} text={live === null ? '—' : undefined} />
        <StatCell
          label={t('stats.tradesSince')}
          value={live?.since_count.trades ?? 0}
          format={formatInt}
          text={live === null ? '—' : undefined}
          data-testid="stats-live-trades"
        />
      </div>
    </SheetSection>
  )
}
