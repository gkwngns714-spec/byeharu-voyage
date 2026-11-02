import { useState } from 'react'
import { Dot, PageGrid, Segmented, Sheet } from '../../components/ui'
import { formatKoreaTime } from '../../lib/format'
import { useLocale, useT } from '../../lib/i18n'
import { tabWord } from '../../app/navTabs'
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
// NOTHING IS BEHIND A PRESS (owner, 2026-11-01, row 260: *"everything is folded in stats this is soo wrong."*).
// Each face is its figures and charts, in cards, and ONE list: the money log, the goods, the cities, the companies,
// the best sales. A press opens ONE item's page or a chart's large view, never the list and never a figure.
//
// THE PAGE, NOT THE PACKED COLUMN (2026-11-02, owner row 267: *"it looks so wrong. The past was better. right now
// everything is on left, too packed. this was a mistake"*). The unfold slice put each face in one 75-rem column with
// 26 rem kept clear at the right and every row at its text line; the face is now a PAGE (`Sheet layout="page"`,
// screenLayout.ts "THE PAGE"): the glass's whole width on a 12-column grid, the figures in cards with room, the
// figures themselves 24 px, the page scrolling when the stack is long. This screen is the PATTERN — Card.tsx has it
// — and docs/dev-log/2026-11-02-stats-design.md the numbers it was measured to.
//
// AND EVERY READ, EVERY SECOND (0224 for the RIGHT NOW band; 0232 for every face — owner row 213: *"and why is next
// count in minutes? i told you it should be in seconds?"*). Each face's read answers NOW on the server (the count's
// quarter hours plus the minutes since; the state as it stands; each chart's last point at now()), and each face asks
// it every second while it is open (statsLive.ts, useLiveRead). There is no count to wait for and none is shown: the
// header says only when the figures are from. Every headline figure WALKS to its new value (`Counter`).
//
// EVERY CITY IS OPEN TO EVERYONE (0223; the owner, 2026-10-25, row 197: *"on cities, i want to see all the
// info without investment"* — reversing his 2026-10-20 gate). The Cities face draws what the server sends,
// which is everything; there is no lock and no tier anywhere.
//
// THE LOOK is the desk's (docs/COMMAND_DESK.md §5): tokens, tabular Figures, hairlines, no boxes, green–red
// only for gain–loss / up–down, one accent for what is yours; charts on their own scales, a stacked bar
// for a composition, ranked bars for "which of these is big", sparklines where a chart is too much.

export function StatsScreen() {
  // THE TITLE IS THE TAB'S OWN WORD (navTabs.tabWord) — one authority with the lit nav cell.
  const title = tabWord(useLocale(), '/stats')
  const phase = useWorld((s) => s.phase)
  const fatal = useWorld((s) => s.fatal)
  if (phase === 'failed') return <WorldFailed title={title} refusal={fatal} />
  if (phase !== 'ready') return <WorldLoading title={title} />
  return <StatsBody title={title} />
}

function StatsBody({ title }: { title: string }) {
  const t = useT()
  const [face, setFace] = useState<StatsFace>('overview')
  const { live, liveAtMs } = useStatsLive()
  const updated = liveAtMs === null ? null : t('stats.updated', { time: formatKoreaTime(liveAtMs) })

  // THE PAGE SCROLLS (2026-11-02, owner row 267): no `fill`, no inner scroll — a face is as tall as its cards.
  return (
    <Sheet
      title={title}
      layout="page"
      data-testid="stats"
      trailing={
        updated === null ? undefined : (
          // THE GREEN DOT IS "RIGHT NOW": the band under the tabs and every face asks again each second, and
          // the line says from when. It stood as a heading of the band, a line of its own, until the unfold slice.
          <span className="flex items-center gap-2 text-t-caption text-ink-faint">
            <Dot tone="success" label={t('stats.live')} />
            <span data-testid="stats-updated">{updated}</span>
          </span>
        )
      }
    >
      <Segmented
        segments={STATS_FACES.map((f) => ({ id: f.id, label: t(`stats.${f.id}`) }))}
        value={face}
        onChange={setFace}
        label={t('stats.facesLabel')}
        className="w-fit max-w-full"
      />
      <PageGrid className="mt-5 lg:mt-6">
        <LiveNow live={live} />
        {face === 'overview' && <OverviewFace live={live} />}
        {face === 'markets' && <MarketsFace />}
        {face === 'cities' && <CitiesFace />}
        {face === 'merchants' && <MerchantsFace />}
        {face === 'me' && <MeFace />}
      </PageGrid>
    </Sheet>
  )
}
