import { useEffect, useState } from 'react'
import { Field, Segmented, Sheet } from '../../components/ui'
import { useWorld } from '../../live/worldStore'
import { WorldFailed, WorldLoading } from '../../live/WorldGate'
import { CaptainsFace } from './CaptainsFace'
import { GoodsFace } from './GoodsFace'
import { NationsFace } from './NationsFace'
import { ShipsFace } from './ShipsFace'
import { tabWord } from '../../app/navTabs'
import { useLocale, useT } from '../../lib/i18n'

// CODEX — the 도감: every good, hull, officer and flag the world serves, ON THE GLASS (owner, 2026-11-01, row
// 260: *"everything is folded … make things unfolded, minimize scrolling"*). It was the four faces as a tile grid
// and ONE summary row (`Goods 629 · Open`) with three quarters of the screen empty under it; the 629 goods were
// behind the press. It is now the four faces over ONE list panel: the face's rows, with the search (and each
// face's own filters) in the panel's header. A press on a row opens THAT item's tray, as it always did.

const FACES = [
  { id: 'goods', label: 'codex.goods', noun: 'codex.filter_goods' },
  { id: 'ships', label: 'codex.ships', noun: 'codex.filter_ships' },
  { id: 'captains', label: 'codex.captains', noun: 'codex.filter_captains' },
  { id: 'nations', label: 'codex.nations', noun: 'codex.filter_nations' },
] as const
type FaceId = (typeof FACES)[number]['id']

export function CompendiumScreen() {
  // THE TITLE IS THE TAB'S OWN WORD (navTabs.tabWord) — one authority with the lit nav cell.
  const title = tabWord(useLocale(), '/compendium')
  const phase = useWorld((s) => s.phase)
  const fatal = useWorld((s) => s.fatal)
  if (phase === 'failed') return <WorldFailed title={title} refusal={fatal} />
  if (phase !== 'ready') return <WorldLoading title={title} />
  return <CompendiumBody title={title} />
}

function CompendiumBody({ title }: { title: string }) {
  const t = useT()
  const loadOfficers = useWorld((s) => s.loadOfficers)

  // ONCE, NOT ON EVERY BEAT (2026-10-31): the roster is a catalogue the cache keeps for the
  // session, and a hire drops it by name. The old `readAt` dependency asked it again every beat
  // while the Codex was open — the owner's "keep it even though you move from tab to tab" was
  // being paid for four times a second on this screen.
  const [rosterAnswered, setRosterAnswered] = useState(false)
  useEffect(() => {
    let alive = true
    void loadOfficers().then(() => {
      if (alive) setRosterAnswered(true)
    })
    return () => {
      alive = false
    }
  }, [loadOfficers])

  const [face, setFace] = useState<FaceId>('goods')
  const [query, setQuery] = useState('')
  const current = FACES.find((f) => f.id === face) ?? FACES[0]

  // THE SEARCH STANDS ON THE PANEL'S TITLE LINE, beside the count, so a list with a search and no filter has a
  // one-line header; each face hands it to its own panel.
  const search = (
    <Field
      className="w-40"
      value={query}
      onChange={(e) => setQuery(e.target.value)}
      onClear={() => setQuery('')}
      aria-label={t(current.noun)}
      placeholder={t('codex.search')}
      spellCheck={false}
      autoCorrect="off"
      data-testid="codex-search"
    />
  )

  return (
    <Sheet title={title} fill data-testid="codex">
      <Segmented
        label={t('codex.faces')}
        segments={FACES.map((f) => ({ id: f.id, label: t(f.label) }))}
        value={face}
        onChange={(next) => {
          // A filter belongs to the face it was typed against.
          setFace(next)
          setQuery('')
        }}
        className="mb-1 w-fit max-w-full shrink-0"
      />
      {face === 'goods' && <GoodsFace query={query} search={search} />}
      {face === 'ships' && <ShipsFace query={query} search={search} />}
      {face === 'captains' && <CaptainsFace query={query} search={search} answered={rosterAnswered} />}
      {face === 'nations' && <NationsFace query={query} search={search} />}
    </Sheet>
  )
}
