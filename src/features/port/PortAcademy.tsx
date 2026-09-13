import { useEffect, useState } from 'react'
import {
  Bar,
  Button,
  Figure,
  Note,
  Row,
  Skeleton,
  Tile,
  TileField,
  Tray,
  type TrayDetent,
} from '../../components/ui'
import { formatInt } from '../../lib/format'
import { useWorld } from '../../live/worldStore'
import type { FleetView, Skill } from '../../lib/rpc'

// THE SCHOOL — a trade is learned ashore, one level at a time (0016).
//
// IT LIVES ON THE PORT BECAUSE THAT IS WHERE IT HAPPENS. §3a of docs/UI_DIRECTION.md names "the
// action lives on the wrong screen" as the second trap the reference game spent four years paying
// for. A trade is learned at an academy, so this is not a tab of its own — it is a face of the
// harbour, and it is only offered where a school stands (PortScreen's `offeredFaces`).
//
// IT DECIDES NOTHING. Every refusal printed here is the server's own sentence and none of them is
// pre-empted by a check on this side. What the client does with a rule is REFUSE TO OFFER a face
// the port cannot host, because a face that always refuses is a wasted tap.
//
// ── `OfficersFace` STOOD IN THIS FILE AND IS DELETED ───────────────────────────────────────────
// Row 56 took the Officers face off this screen in 2026-09-01 and row 60's Inn replaced the act it
// carried (`PortInn.tsx` — `cmd.hire_officer`, which is not one of the twelve verbs). The
// component stayed on disk with no caller and two hand-drawn `bv-cut border border-edge bg-surface-2`
// skins in it — both of the entries `tests/duplication.spec.ts` carried for this file. A component
// nobody mounts is dead code the change that killed it should have taken with it
// (docs/NO_SPAGHETTI.md §5), so it goes with the skin ledger it was holding open.
export function PortAcademy({ acting }: { acting: FleetView | null }) {
  const book = useWorld((s) => s.skills)
  const loadSkills = useWorld((s) => s.loadSkills)
  const studySkill = useWorld((s) => s.studySkill)
  const refusal = useWorld((s) => s.refusal)
  const [open, setOpen] = useState<Skill | null>(null)
  const [detent, setDetent] = useState<TrayDetent>('half')
  const [busy, setBusy] = useState(false)

  useEffect(() => {
    if (!book) void loadSkills()
  }, [book, loadSkills])

  if (!book) return <Skeleton className="h-24 w-full" />

  const study = (skill: Skill) => {
    if (!acting || busy) return
    setBusy(true)
    void (async () => {
      const okay = await studySkill(skill.code, acting.id)
      setBusy(false)
      if (okay) setOpen(null)
    })()
  }

  return (
    <div data-testid="port-academy">
      {!acting && (
        <Note tone="warning" className="mb-3">
          Pick a fleet to train its captain.
        </Note>
      )}

      <TileField>
        {book.skills.map((sk) => (
          <Tile
            key={sk.code}
            name={sk.name}
            state={sk.level > 0 ? 'selected' : 'rest'}
            tap="whole"
            onClick={() => {
              setDetent('half')
              setOpen(sk)
            }}
            figure={<Figure value={`${sk.level}`} unit={`/ ${book.max_level}`} />}
            bar={
              <Bar
                value={sk.level}
                of={book.max_level}
                tone={sk.level > 0 ? 'accent' : 'neutral'}
                label={`${sk.name}, level ${sk.level} of ${book.max_level}`}
              />
            }
            data-testid={`skill-${sk.code}`}
          />
        ))}
      </TileField>

      {open && (
        <Tray
          detent={detent}
          onDetentChange={(next) => (next === 'closed' ? setOpen(null) : setDetent(next))}
          title={open.name}
          data-testid="school-tray"
          action={
            open.next_cost === null ? undefined : (
              <Button
                variant="primary"
                className="w-full"
                disabled={!acting}
                busy={busy}
                busyLabel="Training…"
                onClick={() => study(open)}
                data-testid={`study-${open.code}`}
              >
                {`Train to level ${open.level + 1} · ${formatInt(open.next_cost)} d.`}
              </Button>
            )
          }
        >
          <Row
            label="Per level"
            value={
              <Figure
                value={`+${open.pct_per_level}%`}
                tone={open.takes_effect ? 'success' : 'faint'}
              />
            }
          />
          <Row
            label="Level"
            value={<Figure value={`${open.level}`} unit={`/ ${book.max_level}`} />}
            hairline={false}
          />
          <p className="pt-2 text-t-label text-ink-muted">{open.blurb}</p>
          {open.next_cost === null && (
            <Note tone="neutral">Max level reached.</Note>
          )}
          {refusal && (
            <Note tone="danger" code={refusal.code}>
              {refusal.sentence}
            </Note>
          )}
        </Tray>
      )}
    </div>
  )
}
