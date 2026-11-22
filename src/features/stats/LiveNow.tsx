import { Icon, StatCard, StatStrip, type IconName } from '../../components/ui'
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
// four label-and-figure pairs at 16 px, hugging; it is now a strip of stat cards: the label at 14 px over the
// figure at 24 px, four across from 1,280 (302 px a card at 1,440, 278 at 1,280), two from 640, one line each on a
// phone. Nothing about WHEN a figure moves changed. The world's money is nine digits and a coin — 188 px at 24 px —
// which fits the narrowest card with its padding and, on a phone, a whole line (or drops under its label).

// THE WORLD'S MONEY IS A BUILDER'S FIGURE (2026-11-23, the visual overhaul's slice 2, roadmap X5): "Gold in play" and the funds at sea
// stand on the faces under "More" (`world`), with the Overview whose subject they are; the faces up front keep the player's three.
// THE MARKS (2026-11-23, the visual overhaul's slice 8): each figure wears the one glyph of its meaning before its word — money the coin,
// fleets at sea the ship, trades the scales — so the strip is read by its marks first (principle 1; the words stay, they are short).
const mark = (name: IconName) => <Icon name={name} size={18} className="shrink-0 text-ink-muted" aria-hidden="true" />

export function LiveNow({ live, world }: { live: StatsNow | null; world: boolean }) {
  const t = useT()
  // Selected as a primitive, one selector (worldStore's rule).
  const ducats = useWorld((s) => s.ducats)

  return (
    <StatStrip aria-label={t('stats.rightNow')} data-testid="stats-live">
      <StatCard
        mark={mark('coin')}
        label={t('stats.purse')}
        value={ducats ?? 0}
        format={formatDucats}
        tone="accent"
        text={ducats === null ? '—' : undefined}
        data-testid="stats-live-purse"
      />
      <StatCard
        mark={mark('ship')}
        label={t('stats.fleetsAtSea')}
        value={live?.at_sea ?? 0}
        format={formatInt}
        text={live === null ? '—' : undefined}
        data-testid="stats-live-sea"
      />
      <StatCard
        mark={mark('scales')}
        label={t('stats.tradesSince')}
        value={live?.since_count.trades ?? 0}
        format={formatInt}
        text={live === null ? '—' : undefined}
        data-testid="stats-live-trades"
      />
      {world && (
        <StatCard
          mark={mark('coin')}
          label={t('stats.money')}
          value={live?.total ?? 0}
          format={formatDucats}
          text={live === null ? '—' : undefined}
          data-testid="stats-live-world"
        />
      )}
      {/* 0310: a part of Set aside, served only while a cargo ship exists. */}
      {world && live?.funds_at_sea !== undefined && (
        <StatCard mark={mark('coin')} label={t('stats.fundsAtSea')} value={live.funds_at_sea} format={formatDucats} data-testid="stats-live-funds" />
      )}
    </StatStrip>
  )
}
