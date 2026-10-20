import { useState } from 'react'
import { Segmented, Sheet } from '../../components/ui'
import { formatRelative } from '../../lib/format'
import { useWorld } from '../../live/worldStore'
import { WorldFailed, WorldLoading } from '../../live/WorldGate'
import { CitiesFace } from './Cities'
import { LiveNow } from './LiveNow'
import { MarketsFace } from './Markets'
import { MeFace } from './Me'
import { MerchantsFace } from './Merchants'
import { OverviewFace } from './Overview'
import { STATS_FACES, type StatsFace } from './statsFaces'
import { useStatsPulse, type StatsServed } from './statsPulse'

// STATS — the world's figures, the way a trading screen shows a market (0214; docs/dev-log/2026-10-20-stats-tab.md).
// The owner, 2026-10-20: *"a statistic tab along with command, map etc. where i can see the world economy,
// npc economy, cities, trade good stocks, and much much more - that is updated regularly."*
//
// FIVE FACES, ONE READ EACH. The server's job writes a rollup every fifteen minutes; each face asks one
// read of it and prints what it says (the sums, the words, the tiers are all the server's).
//
// TWO CADENCES, AND THEY ARE BOTH THE OWNER'S (requests 187 and 188, 2026-10-20 — *"I want stats to be
// in real time, by seconds updated"*, *"no visuals, no charts, no number moving around"*):
//   · RIGHT NOW (LiveNow.tsx) is the world's own beat — your purse, your fleets, your cargo, straight
//     out of the store the shell polls every few seconds. No new read, no new write.
//   · THE ROLLUP is re-asked once a minute AND at the edge of the next count (statsPulse.ts), so a
//     fresh count reaches the screen within seconds of the server writing it. The age beside the
//     title ticks every second, measured by the SERVER (`age_seconds`) plus the time elapsed here —
//     never by this browser's clock.
// Every headline figure WALKS to its new value (`Counter`), so a count landing is something you see.
//
// A CITY'S FIGURES ARE BOUGHT (the owner: *"a statistic info of a city is added only when you invest
// certain amount"*). The Cities face draws a lock where the server sent none; it never has the figures
// to hide, because the gate is public.stats_city_tier on the server and nothing locked leaves it.
//
// THE LOOK is the desk's (docs/COMMAND_DESK.md §5): tokens, tabular Figures, hairlines, no boxes, green–red
// only for gain–loss / up–down, one accent for what is yours; charts on their own scales, a stacked bar
// for a composition, ranked bars for "which of these is big", sparklines where a chart is too much.

export function StatsScreen() {
  const phase = useWorld((s) => s.phase)
  const fatal = useWorld((s) => s.fatal)
  if (phase === 'failed') return <WorldFailed title="Stats" refusal={fatal} />
  if (phase !== 'ready') return <WorldLoading title="Stats" />
  return <StatsBody />
}

function StatsBody() {
  const [face, setFace] = useState<StatsFace>('overview')
  const [served, setServed] = useState<StatsServed | null>(null)
  const pulse = useStatsPulse(served)

  // `formatRelative` reads only the GAP between its two instants, so (−age, 0) asks it exactly what the
  // server's `age_seconds` measured plus the seconds since, and a skewed device clock cannot age a
  // server's record.
  const updated = pulse.ageMs === null ? null : `Updated ${formatRelative(-pulse.ageMs, 0)}`

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
          setServed(null)
          setFace(id)
        }}
        label="Stats faces"
        className="mb-3 w-fit max-w-full"
      />
      <LiveNow dueMs={pulse.dueMs} />
      {face === 'overview' && <OverviewFace beat={pulse.beat} onServed={setServed} />}
      {face === 'markets' && <MarketsFace beat={pulse.beat} onServed={setServed} />}
      {face === 'cities' && <CitiesFace beat={pulse.beat} onServed={setServed} />}
      {face === 'merchants' && <MerchantsFace beat={pulse.beat} onServed={setServed} />}
      {face === 'me' && <MeFace beat={pulse.beat} onServed={setServed} />}
    </Sheet>
  )
}

/** What every face takes: the tab's beat (re-ask on the backstop and at the next count's edge) and
 *  where to report how old the answer it just drew is. */
export interface FaceProps {
  beat: number
  onServed: (served: StatsServed | null) => void
}
