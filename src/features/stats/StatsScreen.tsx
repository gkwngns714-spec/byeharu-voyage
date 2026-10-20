import { useState } from 'react'
import { Segmented, Sheet } from '../../components/ui'
import { formatRelative } from '../../lib/format'
import { useWorld } from '../../live/worldStore'
import { WorldFailed, WorldLoading } from '../../live/WorldGate'
import { CitiesFace } from './Cities'
import { MarketsFace } from './Markets'
import { MeFace } from './Me'
import { MerchantsFace } from './Merchants'
import { OverviewFace } from './Overview'
import { STATS_FACES, type StatsFace } from './statsFaces'
import { useStatsBeat } from './useStatsBeat'

// STATS — the world's figures, the way a trading screen shows a market (0214; docs/dev-log/2026-10-20-stats-tab.md).
// The owner, 2026-10-20: *"a statistic tab along with command, map etc. where i can see the world economy,
// npc economy, cities, trade good stocks, and much much more - that is updated regularly."*
//
// FIVE FACES, ONE READ EACH. The server's job writes a rollup every fifteen minutes; each face asks one
// read of it and prints what it says (the sums, the words, the tiers are all the server's). A face
// re-asks once a minute while it is open (useStatsBeat) and says how old its figures are, measured by the
// SERVER (`age_seconds`), never by this browser's clock — Rank's idiom.
//
// A CITY'S FIGURES ARE BOUGHT (the owner: *"a statistic info of a city is added only when you invest
// certain amount"*). The Cities face draws a lock where the server sent none; it never has the figures
// to hide, because the gate is public.stats_city_tier on the server and nothing locked leaves it.
//
// THE LOOK is the desk's (docs/COMMAND_DESK.md §5): tokens, tabular Figures, hairlines, no boxes, green–red
// only for gain–loss / up–down, one accent for what is yours; small-multiple charts on their own scales.

export function StatsScreen() {
  const phase = useWorld((s) => s.phase)
  const fatal = useWorld((s) => s.fatal)
  if (phase === 'failed') return <WorldFailed title="Stats" refusal={fatal} />
  if (phase !== 'ready') return <WorldLoading title="Stats" />
  return <StatsBody />
}

function StatsBody() {
  const [face, setFace] = useState<StatsFace>('overview')
  const [ageSeconds, setAgeSeconds] = useState<number | null>(null)
  const beat = useStatsBeat()

  // `formatRelative` reads only the GAP between its two instants, so (−age, 0) asks it exactly what the
  // server's `age_seconds` measured, and a skewed device clock cannot age a server's record.
  const updated = ageSeconds === null ? null : `Updated ${formatRelative(-ageSeconds * 1000, 0)}`

  return (
    <Sheet
      title="Stats"
      data-testid="stats"
      trailing={
        updated === null ? undefined : (
          <span className="text-t-caption text-ink-faint" data-testid="stats-updated">
            {updated}
          </span>
        )
      }
    >
      <Segmented
        segments={STATS_FACES.map((f) => ({ id: f.id, label: f.label }))}
        value={face}
        onChange={(id) => {
          setAgeSeconds(null)
          setFace(id)
        }}
        label="Stats faces"
        className="mb-3 w-fit max-w-full"
      />
      {face === 'overview' && <OverviewFace beat={beat} onAge={setAgeSeconds} />}
      {face === 'markets' && <MarketsFace beat={beat} onAge={setAgeSeconds} />}
      {face === 'cities' && <CitiesFace beat={beat} onAge={setAgeSeconds} />}
      {face === 'merchants' && <MerchantsFace beat={beat} onAge={setAgeSeconds} />}
      {face === 'me' && <MeFace beat={beat} onAge={setAgeSeconds} />}
    </Sheet>
  )
}

/** What every face takes: the tab's beat (re-ask once a minute) and where to report its figures' age. */
export interface FaceProps {
  beat: number
  onAge: (seconds: number | null) => void
}
