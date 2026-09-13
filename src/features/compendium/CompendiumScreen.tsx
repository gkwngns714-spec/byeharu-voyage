import { useEffect, useState } from 'react'
import { Field, Segmented, Sheet } from '../../components/ui'
import { useWorld } from '../../live/worldStore'
import { WorldFailed, WorldLoading } from '../../live/WorldGate'
import { CaptainsFace } from './CaptainsFace'
import { GoodsFace } from './GoodsFace'
import { NationsFace } from './NationsFace'
import { ShipsFace } from './ShipsFace'

// CODEX — the 도감: everything that exists in this world, catalogued, whether or not you have met
// it. The owner, 2026-08-23: "create a 도감, separate tab, showing all the trade goods, ships,
// captains that are made in this game. categorize them, make filters." Redrawn to
// docs/UI_DIRECTION.md §6 "CODEX".
//
// ── IT IS A REFERENCE. IT COMMANDS NOTHING. ────────────────────────────────────────────────────
// No buy, no hire, no sail, no hand-off. Every acting surface already exists once — orders are
// composed on COMMAND, officers sign on at their quay on PORT, hulls are a yard's business — and a
// button here would be a second one of it.
//
// ── NOTHING HERE IS COMPUTED, AND NO PRICE IS PRINTED ──────────────────────────────────────────
// Every figure is a served field read off `world.snapshot()` or `world.officers()`. A good's BASE
// is the catalogue's anchor, not a price — prices are per port and live. Nothing is averaged,
// ranked or derived (worldStore.ts rule 3).
//
// ── WHAT §6 CUT, MEASURED ──────────────────────────────────────────────────────────────────────
// The goods face stood 39,365px tall at 390px. Behind the title's dot sat a 90-word paragraph; under
// the tabs sat TWO chip strips scrolling sideways (17 kinds × 4 rarities) with "Swipe for the
// rest." under them, then `523 of 523 goods`, then a tile per good carrying FOUR figures of which
// two — `SPOILS —` and `REFUSED BY —` — printed an em-dash on most of 523 goods. A dash is a figure
// that is not there. Ship tiles printed `build 40 h` and `cost 2,400 d.` for hulls no order can
// commission (domain/fleet/statGloss.ts says so); captain tiles printed "no rule reads this
// specialty yet — the bonus changes nothing" as a line of fine print on the tile.
//
// What stands now: ONE filter field, which answers to a name, a kind and a rarity word alike — so
// "spices" and "rare" filter as the chip strips did, without the strips — and ONE `Segmented` of
// four faces. The kind is a heading over its group. A tile shows the mark, the name, the rarity
// and ONE figure; everything else is in a tray, and a fact that is absent is simply not a row.
//
// ── THE FOUR FACES ─────────────────────────────────────────────────────────────────────────────
// Goods, ships and captains are the owner's. Nations ride along because they are the fourth noun
// every other page speaks in codes, and 0028 serves the catalogue so a code can become a name.
// Ports are deliberately NOT a face: MAP draws them all and MARKET lists them.

const FACES = [
  { id: 'goods', label: 'Goods', noun: 'goods' },
  { id: 'ships', label: 'Ships', noun: 'ship classes' },
  { id: 'captains', label: 'Captains', noun: 'captains' },
  { id: 'nations', label: 'Nations', noun: 'nations' },
] as const
type FaceId = (typeof FACES)[number]['id']

export function CompendiumScreen() {
  // FIELDS, NOT THE STORE (worldStore.ts rule 4).
  const phase = useWorld((s) => s.phase)
  const fatal = useWorld((s) => s.fatal)

  if (phase === 'failed') {
    return <WorldFailed eyebrow="Reference" title="Codex" refusal={fatal} />
  }
  if (phase !== 'ready') {
    return (
      <WorldLoading eyebrow="Reference" title="Codex" subtitle="Everything in the game." panels={2} />
    )
  }
  return <CompendiumBody />
}

function CompendiumBody() {
  const loadOfficers = useWorld((s) => s.loadOfficers)
  const readAt = useWorld((s) => s.readAt)

  // WHETHER THE ROSTER HAS ANSWERED, which `officers === null` alone cannot say: null is both "not
  // asked yet" and "the read was refused", and without the distinction a refused read draws a
  // skeleton for ever. Keyed on `readAt` so the one live thing here — who has signed, and whose
  // fleet they serve — rides the world's own thirty-second beat, and a refused read is retried
  // with no button.
  const [rosterAnswered, setRosterAnswered] = useState(false)
  useEffect(() => {
    if (readAt === null) return
    let alive = true
    void loadOfficers().then(() => {
      if (alive) setRosterAnswered(true)
    })
    return () => {
      alive = false
    }
  }, [loadOfficers, readAt])

  const [face, setFace] = useState<FaceId>('goods')
  const [query, setQuery] = useState('')
  const noun = FACES.find((f) => f.id === face)?.noun ?? 'entries'

  return (
    <Sheet title="Codex" data-testid="codex">
      <Segmented
        label="Codex faces"
        segments={FACES}
        value={face}
        onChange={(next) => {
          // A filter belongs to the face it was typed against: "pepper" carried onto the ships
          // face would show an empty catalogue for a reason typed a minute ago on another list.
          setFace(next)
          setQuery('')
        }}
      />
      <Field
        className="mt-3"
        value={query}
        onChange={(e) => setQuery(e.target.value)}
        onClear={() => setQuery('')}
        aria-label={`Filter ${noun}`}
        placeholder={`Filter ${noun}`}
        spellCheck={false}
        autoCorrect="off"
      />
      <div role="tabpanel" className="mt-3">
        {face === 'goods' && <GoodsFace query={query} />}
        {face === 'ships' && <ShipsFace query={query} />}
        {face === 'captains' && <CaptainsFace query={query} answered={rosterAnswered} />}
        {face === 'nations' && <NationsFace query={query} />}
      </div>
    </Sheet>
  )
}
