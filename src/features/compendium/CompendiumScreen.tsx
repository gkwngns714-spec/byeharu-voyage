import { useEffect, useState } from 'react'
import { DetailPage, Field, Segmented, Sheet, SummaryRow } from '../../components/ui'
import { formatInt } from '../../lib/format'
import { useWorld } from '../../live/worldStore'
import { WorldFailed, WorldLoading } from '../../live/WorldGate'
import { CaptainsFace } from './CaptainsFace'
import { GoodsFace } from './GoodsFace'
import { NationsFace } from './NationsFace'
import { ShipsFace } from './ShipsFace'
import { useT } from '../../lib/i18n'

// CODEX — the 도감: every good, hull, officer and flag the world serves. THE COMPACT SCREEN (owner,
// 2026-10-31): the four faces are a tile grid; the catalogue itself is one summary row with its
// count, opening a full-screen page that holds the search and the face's field whole.

const FACES = [
  { id: 'goods', label: 'codex.goods', noun: 'codex.filter_goods' },
  { id: 'ships', label: 'codex.ships', noun: 'codex.filter_ships' },
  { id: 'captains', label: 'codex.captains', noun: 'codex.filter_captains' },
  { id: 'nations', label: 'codex.nations', noun: 'codex.filter_nations' },
] as const
type FaceId = (typeof FACES)[number]['id']

export function CompendiumScreen() {
  const t = useT()
  const phase = useWorld((s) => s.phase)
  const fatal = useWorld((s) => s.fatal)
  if (phase === 'failed') return <WorldFailed title={t('codex.codex')} refusal={fatal} />
  if (phase !== 'ready') return <WorldLoading title={t('codex.codex')} />
  return <CompendiumBody />
}

function CompendiumBody() {
  const t = useT()
  const loadOfficers = useWorld((s) => s.loadOfficers)
  const snapshot = useWorld((s) => s.snapshot)
  const roster = useWorld((s) => s.officers)
  const nationByCode = useWorld((s) => s.nationByCode)

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
  const [open, setOpen] = useState(false)
  const current = FACES.find((f) => f.id === face) ?? FACES[0]
  const label = t(current.label)
  const count =
    face === 'goods'
      ? (snapshot?.goods?.length ?? 0)
      : face === 'ships'
        ? (snapshot?.ship_classes?.length ?? 0)
        : face === 'captains'
          ? (roster?.officers.length ?? 0)
          : Object.keys(nationByCode).length

  return (
    <Sheet title={t('codex.codex')} data-testid="codex">
      <Segmented
        label={t('codex.faces')}
        segments={FACES.map((f) => ({ id: f.id, label: t(f.label) }))}
        value={face}
        onChange={(next) => {
          // A filter belongs to the face it was typed against.
          setFace(next)
          setQuery('')
        }}
      />
      <SummaryRow className="mt-3" title={label} figure={formatInt(count)} word={t('common.open')} onClick={() => setOpen(true)} data-testid="codex-open" />
      {open && (
        <DetailPage title={label} figure={formatInt(count)} onClose={() => setOpen(false)} data-testid="codex-open-page">
          <Field
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            onClear={() => setQuery('')}
            aria-label={t(current.noun)}
            placeholder={t(current.noun)}
            spellCheck={false}
            autoCorrect="off"
          />
          <div role="tabpanel" className="mt-3">
            {face === 'goods' && <GoodsFace query={query} />}
            {face === 'ships' && <ShipsFace query={query} />}
            {face === 'captains' && <CaptainsFace query={query} answered={rosterAnswered} />}
            {face === 'nations' && <NationsFace query={query} />}
          </div>
        </DetailPage>
      )}
    </Sheet>
  )
}
