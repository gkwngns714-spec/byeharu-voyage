import { StatCell, StatRun } from '../../components/ui'
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
//
// FOUR PAIRS, EACH AS WIDE AS ITS FIGURE (2026-11-02, the unfold slice). It was a four-column grid of 81-px
// cells, and the world's money — nine digits and a coin, 118 px — ran over the cell beside it (`At sea` was
// drawn under `131,367,515`). The label now stands before its figure (owner row 258/260: *"label and figure
// close"*) and the pairs wrap like words: three small ones on a line, the world's money on its own — nothing
// overlaps at any width, and nothing about WHEN a figure moves changed. "Right now" is the green dot beside the
// header's "Updated" (StatsScreen.tsx): the whole band is live, and that is said once.

export function LiveNow({ live }: { live: StatsNow | null }) {
  const t = useT()
  // Selected as a primitive, one selector (worldStore's rule).
  const ducats = useWorld((s) => s.ducats)

  return (
    <section data-testid="stats-live" aria-label={t('stats.rightNow')} className="mb-1 shrink-0">
      <StatRun>
      <StatCell
        inline
        label={t('stats.purse')}
        value={ducats ?? 0}
        format={formatDucats}
        size="body"
        tone="accent"
        text={ducats === null ? '—' : undefined}
        data-testid="stats-live-purse"
      />
      <StatCell
        inline
        label={t('stats.fleetsAtSea')}
        value={live?.at_sea ?? 0}
        format={formatInt}
        size="body"
        text={live === null ? '—' : undefined}
        data-testid="stats-live-sea"
      />
      <StatCell
        inline
        label={t('stats.tradesSince')}
        value={live?.since_count.trades ?? 0}
        format={formatInt}
        size="body"
        text={live === null ? '—' : undefined}
        data-testid="stats-live-trades"
      />
      <StatCell
        inline
        label={t('stats.money')}
        value={live?.total ?? 0}
        format={formatDucats}
        size="body"
        text={live === null ? '—' : undefined}
        data-testid="stats-live-world"
      />
      </StatRun>
    </section>
  )
}
