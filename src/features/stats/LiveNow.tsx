import { Band, StatCard } from '../../components/ui'
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
// is the moving number request 188 asks for. "Right now" is the green dot beside the header's "Updated"
// (StatsScreen.tsx): the whole band is live, and that is said once.
//
// FOUR STAT CARDS (2026-11-02, owner row 267 — *"too packed"*). The unfold slice drew this band as a line of
// four label-and-figure pairs at 16 px, hugging; it is now a row of stat cards: the label at 14 px over the
// figure at 24 px, 100 px of card each, four across from 1,280 (two across below, one line each on a phone).
// Nothing about WHEN a figure moves changed. The world's money is nine digits and a coin — 185 px at 24 px —
// which fits the narrowest card (278 px at 1,280, 296 px of it inside the padding) and, on a phone, a whole line.

export function LiveNow({ live }: { live: StatsNow | null }) {
  const t = useT()
  // Selected as a primitive, one selector (worldStore's rule).
  const ducats = useWorld((s) => s.ducats)

  return (
    <Band aria-label={t('stats.rightNow')} data-testid="stats-live">
      <StatCard
        label={t('stats.purse')}
        value={ducats ?? 0}
        format={formatDucats}
        tone="accent"
        text={ducats === null ? '—' : undefined}
        data-testid="stats-live-purse"
      />
      <StatCard
        label={t('stats.fleetsAtSea')}
        value={live?.at_sea ?? 0}
        format={formatInt}
        text={live === null ? '—' : undefined}
        data-testid="stats-live-sea"
      />
      <StatCard
        label={t('stats.tradesSince')}
        value={live?.since_count.trades ?? 0}
        format={formatInt}
        text={live === null ? '—' : undefined}
        data-testid="stats-live-trades"
      />
      <StatCard
        label={t('stats.money')}
        value={live?.total ?? 0}
        format={formatDucats}
        text={live === null ? '—' : undefined}
        data-testid="stats-live-world"
      />
    </Band>
  )
}
