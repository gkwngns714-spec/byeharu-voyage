import { Dot, SheetSection } from '../../components/ui'
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
      {/* A WRAPPING FACTS LINE (owner, 2026-11-01: *"everything is folded in stats… make it
          compact showing everything possible"*): four labelled live figures at caption scale —
          the same four numbers in one block instead of a 4-cell grid. The test ids stay on the
          figures themselves. */}
      <div className="flex flex-wrap items-baseline gap-x-3 gap-y-0.5 text-t-caption text-ink-faint">
        <span className="whitespace-nowrap">
          {t('stats.purse')}{' '}
          <span className="tabular-nums text-accent" data-testid="stats-live-purse">
            {ducats === null ? '—' : formatDucats(ducats ?? 0)}
          </span>
        </span>
        <span className="whitespace-nowrap">
          {t('stats.money')}{' '}
          <span className="tabular-nums text-ink" data-testid="stats-live-world">
            {live === null ? '—' : formatDucats(live.total ?? 0)}
          </span>
        </span>
        <span className="whitespace-nowrap">
          {t('stats.fleetsAtSea')} <span className="tabular-nums text-ink">{live === null ? '—' : formatInt(live.at_sea ?? 0)}</span>
        </span>
        <span className="whitespace-nowrap">
          {t('stats.tradesSince')}{' '}
          <span className="tabular-nums text-ink" data-testid="stats-live-trades">
            {live === null ? '—' : formatInt(live.since_count.trades ?? 0)}
          </span>
        </span>
      </div>
    </SheetSection>
  )
}
