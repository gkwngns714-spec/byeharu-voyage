import { Sheet } from '../../components/ui'
import { tabWord } from '../../app/navTabs'
import { useLocale } from '../../lib/i18n'
import { useWorld } from '../../live/worldStore'
import { WorldFailed, WorldLoading } from '../../live/WorldGate'
import { LOGBOOK_ROUTE, LogbookBody } from './Logbook'

// THE LOGBOOK PAGE (0478, roadmap 2026-11-23 slice 9; RS3's collection log). Lit under You in the nav (navTabs.ts): You's logbook
// card is its door, drawn only while the server serves it on. Composition only: the one logbook read (Logbook.tsx).

export function LogbookScreen() {
  const title = tabWord(useLocale(), LOGBOOK_ROUTE)
  const phase = useWorld((s) => s.phase)
  const fatal = useWorld((s) => s.fatal)
  if (phase === 'failed') return <WorldFailed title={title} refusal={fatal} />
  if (phase !== 'ready') return <WorldLoading title={title} />
  return (
    <Sheet title={title} layout="page" data-testid="logbook-page">
      <LogbookBody />
    </Sheet>
  )
}
