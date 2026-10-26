import { useState } from 'react'
import { Segmented, Sheet } from '../../components/ui'
import { formatKoreaTime } from '../../lib/format'
import { useT } from '../../lib/i18n'
import type { StatsNow } from '../../lib/rpc'
import { useWorld } from '../../live/worldStore'
import { WorldFailed, WorldLoading } from '../../live/WorldGate'
import { CitiesFace } from './Cities'
import { LiveNow } from './LiveNow'
import { MarketsFace } from './Markets'
import { MeFace } from './Me'
import { MerchantsFace } from './Merchants'
import { OverviewFace } from './Overview'
import { STATS_FACES, type StatsFace } from './statsFaces'
import { useStatsLive } from './statsLive'

// STATS — the world's figures, the way a trading screen shows a market (0214; docs/dev-log/2026-10-20-stats-tab.md).
// The owner, 2026-10-20: *"a statistic tab along with command, map etc. where i can see the world economy,
// npc economy, cities, trade good stocks, and much much more - that is updated regularly."*
//
// FIVE FACES, ONE READ EACH. The server's job writes a rollup every fifteen minutes; each face asks one
// read of it and prints what it says (the sums, the words, the tiers are all the server's).
//
// AND ONE LIVE READ, EVERY SECOND (0224, owner row 200 — *"i want to be updated every second"*, asked three
// times). statsLive.ts asks world.stats_now() each second while this screen is open: money by holder, fleets
// at sea, the trades since the last count. The RIGHT NOW band prints it; the Overview and Merchants faces
// draw it as their headline figures and as each chart's LAST point, moving at the right edge; and the
// instant of the last count, carried on the same answer, is what re-asks a face's rollup read — no
// backstop interval, no computed edge. Every headline figure WALKS to its new value (`Counter`).
//
// EVERY CITY IS OPEN TO EVERYONE (0223; the owner, 2026-10-25, row 197: *"on cities, i want to see all the
// info without investment"* — reversing his 2026-10-20 gate). The Cities face draws what the server sends,
// which is everything; there is no lock and no tier anywhere.
//
// THE LOOK is the desk's (docs/COMMAND_DESK.md §5): tokens, tabular Figures, hairlines, no boxes, green–red
// only for gain–loss / up–down, one accent for what is yours; charts on their own scales, a stacked bar
// for a composition, ranked bars for "which of these is big", sparklines where a chart is too much.

export function StatsScreen() {
  const t = useT()
  const phase = useWorld((s) => s.phase)
  const fatal = useWorld((s) => s.fatal)
  if (phase === 'failed') return <WorldFailed title={t('stats.title')} refusal={fatal} />
  if (phase !== 'ready') return <WorldLoading title={t('stats.title')} />
  return <StatsBody />
}

function StatsBody() {
  const t = useT()
  const [face, setFace] = useState<StatsFace>('overview')
  const { live, count, liveAtMs } = useStatsLive()
  const counted = liveAtMs === null ? null : t('stats.updated', { time: formatKoreaTime(liveAtMs) })

  return (
    <Sheet
      title={t('stats.title')}
      data-testid="stats"
      trailing={
        counted === null ? undefined : (
          <span className="text-t-caption text-ink-faint" data-testid="stats-updated">
            {counted}
          </span>
        )
      }
    >
      <Segmented
        segments={STATS_FACES.map((f) => ({ id: f.id, label: t(`stats.${f.id}`) }))}
        value={face}
        onChange={setFace}
        label={t('stats.facesLabel')}
        className="mb-3 w-fit max-w-full"
      />
      <LiveNow live={live} />
      {face === 'overview' && <OverviewFace beat={count} live={live} />}
      {face === 'markets' && <MarketsFace beat={count} live={live} />}
      {face === 'cities' && <CitiesFace beat={count} live={live} />}
      {face === 'merchants' && <MerchantsFace beat={count} live={live} />}
      {face === 'me' && <MeFace beat={count} live={live} />}
    </Sheet>
  )
}

/** What every face takes: the count's beat (its rollup read re-asks when the last count moves) and the live
 *  figures of this second, for the faces that print them. */
export interface FaceProps {
  beat: number
  live: StatsNow | null
}
