import { useState } from 'react'
import { PageSplit, Sheet } from '../../components/ui'
import { tabWord } from '../../app/navTabs'
import { useLocale } from '../../lib/i18n'
import { useWorld } from '../../live/worldStore'
import { WorldFailed, WorldLoading } from '../../live/WorldGate'
import { LEVELS_ROUTE, LevelsCard, LevelsSide, LevelsTray } from './Levels'
import { Studies } from './Studies'

// THE LEVELS PAGE (roadmap 2026-11-23, slice 10: "One Skills page, with loud level-ups"; RS3's skills page, Melvor's skill list).
// MAIN every level, Sea and Land, as a tile: its level, the bar to the next, what the next level opens, and "fastest way", one press
// to the act that raises it (live/LevelTiles.tsx). SIDE the Academy's studies from Trading 5 (X6), seamanship and the countries.
// A pressed tile opens its tray (the experience table, what raises it, what levels give). Lit under You in the nav (navTabs.ts):
// You's levels card is its door. Composition only: the one levels read and the Academy's book, nothing worked out.

export function LevelsScreen() {
  const title = tabWord(useLocale(), LEVELS_ROUTE)
  const phase = useWorld((s) => s.phase)
  const fatal = useWorld((s) => s.fatal)
  const [picked, setPicked] = useState<string | null>(null)
  if (phase === 'failed') return <WorldFailed title={title} refusal={fatal} />
  if (phase !== 'ready') return <WorldLoading title={title} />
  return (
    <Sheet title={title} layout="page" data-testid="skills">
      <PageSplit
        data-testid="skills-page"
        stickySide
        main={<LevelsCard picked={picked} onPick={setPicked} />}
        side={
          <>
            <Studies />
            <LevelsSide />
          </>
        }
      />
      <LevelsTray picked={picked} onClose={() => setPicked(null)} />
    </Sheet>
  )
}
