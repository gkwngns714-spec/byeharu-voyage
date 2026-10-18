import { useCallback, useEffect, useState } from 'react'
import {
  Button,
  Countdown,
  Figure,
  Hint,
  Note,
  Row,
  SheetSection,
  Skeleton,
  SkillTile,
  TileField,
  Tray,
  useReaskAtEdge,
  type TrayDetent,
} from '../components/ui'
import { useShellState } from '../app/shellState'
import { formatDucats, formatRealDuration } from '../lib/format'
import { useWorld } from './worldStore'
import type { Skill, SkillBook } from '../lib/rpc'

// THE ACADEMY → SKILLS (0016; re-made by 0131, docs/SHIPS_AND_SKILLS.md §5): the skills in their
// groups, and the training QUEUE with a timer on every entry. A skill is ENROLLED once where it is
// taught (the price), and each level then trains by time — anywhere, and while you are away.
//
// IT LIVES ON THE PORT BECAUSE THAT IS WHERE ENROLMENT HAPPENS. §3a of docs/UI_DIRECTION.md names
// "the action lives on the wrong screen" as the second trap the reference game paid for.
//
// IT DECIDES NOTHING. Every figure and every yes/no on this screen is served by world.skills():
// the level, the time the next level takes, whether it can be queued and the verb's own sentence if
// not, whether a docked fleet can enrol and which one. A press composes the request (the queue as
// served plus the served next level) and the server takes it whole or refuses it whole.
export function PortAcademy() {
  const book = useWorld((s) => s.skills)
  const loadSkills = useWorld((s) => s.loadSkills)
  const enrollSkill = useWorld((s) => s.enrollSkill)
  const setSkillQueue = useWorld((s) => s.setSkillQueue)
  const refusal = useWorld((s) => s.refusal)
  const { nowMs } = useShellState()
  const [openCode, setOpenCode] = useState<string | null>(null)
  const [detent, setDetent] = useState<TrayDetent>('half')
  const [busy, setBusy] = useState(false)

  useEffect(() => {
    if (!book) void loadSkills()
  }, [book, loadSkills])

  // A level lands the instant its finish passes — on the SERVER. At the first finish the book in
  // hand has stopped being true, so it is asked again (never advanced here).
  const reask = useCallback(() => void loadSkills(), [loadSkills])
  const firstFinish = book?.queue[0] ? Date.parse(book.queue[0].finishes_at) : null
  useReaskAtEdge(firstFinish, book ? Date.parse(book.now) : null, nowMs, reask)

  if (!book) return <Skeleton className="h-24 w-full" />

  const open = openCode ? (book.skills.find((s) => s.code === openCode) ?? null) : null
  const queueEntries = book.queue.map((q) => ({ code: q.code, level: q.level }))

  const run = (act: () => Promise<boolean>) => {
    if (busy) return
    setBusy(true)
    void act().finally(() => setBusy(false))
  }
  const enrol = (sk: Skill) => {
    if (sk.enrol_fleet) {
      const fleet = sk.enrol_fleet
      run(() => enrollSkill(sk.code, fleet))
    }
  }
  const train = (sk: Skill) => {
    if (sk.next_level !== null) {
      const level = sk.next_level
      run(() => setSkillQueue([...queueEntries, { code: sk.code, level }]))
    }
  }
  const remove = (pos: number) => run(() => setSkillQueue(queueEntries.filter((_, i) => book.queue[i].pos !== pos)))

  return (
    <div data-testid="port-academy">
      <SheetSection heading="Training" data-testid="skill-queue">
        <Hint>Trains while you are away.</Hint>
        {book.queue.length === 0 ? (
          <Row label="Nothing is training." tone="muted" hairline={false} />
        ) : (
          <>
            {book.queue.map((q, i) => (
              <Row
                key={q.pos}
                label={`${q.name} · level ${q.level}`}
                value={
                  <span className="flex items-center gap-2">
                    <Countdown untilMs={Date.parse(q.finishes_at)} nowMs={nowMs} dueText="Done" />
                    <Button variant="quiet" size="sm" busy={busy} onClick={() => remove(q.pos)} data-testid={`unqueue-${q.pos}`}>
                      Remove
                    </Button>
                  </span>
                }
                hairline={i < book.queue.length - 1}
                data-testid={`queued-${q.code}-${q.level}`}
              />
            ))}
            {book.eta && (
              <Row
                label={`All done · ${book.queue.length} / ${book.queue_max} levels`}
                value={<Countdown untilMs={Date.parse(book.eta)} nowMs={nowMs} dueText="Done" />}
                tone="muted"
                hairline={false}
              />
            )}
          </>
        )}
      </SheetSection>

      {book.groups.map((g) => (
        <GroupSection
          key={g.code}
          name={g.name}
          skills={book.skills.filter((s) => s.group === g.code)}
          book={book}
          onOpen={(code) => {
            setDetent('half')
            setOpenCode(code)
          }}
        />
      ))}

      {open && (
        <Tray
          detent={detent}
          onDetentChange={(next) => (next === 'closed' ? setOpenCode(null) : setDetent(next))}
          title={open.name}
          data-testid="school-tray"
          action={
            open.next_level === null ? undefined : !open.enrolled ? (
              <Button
                variant="primary"
                className="w-full"
                disabled={!open.can_enrol}
                busy={busy}
                busyLabel="Enrolling…"
                onClick={() => enrol(open)}
                data-testid={`enrol-${open.code}`}
              >
                {`Enrol · ${formatDucats(open.enrol_cost ?? 0)}`}
              </Button>
            ) : (
              <Button
                variant="primary"
                className="w-full"
                disabled={!open.can_queue}
                busy={busy}
                busyLabel="Adding…"
                onClick={() => train(open)}
                data-testid={`study-${open.code}`}
              >
                {`Train level ${open.next_level}`}
              </Button>
            )
          }
        >
          <Row label="Level" value={<Figure value={`${open.level}`} unit={`/ ${book.max_level}`} />} />
          {open.next_level !== null && open.train_seconds !== null && (
            <Row
              label={`Time to level ${open.next_level}`}
              value={<Figure value={formatRealDuration(open.train_seconds * 1000)} />}
            />
          )}
          {open.effect !== 'NONE' && (
            <Row
              label="Per level"
              value={<Figure value={`+${open.pct_per_level}%`} tone={open.takes_effect ? 'success' : 'faint'} />}
            />
          )}
          {open.prereqs.map((p) => (
            <Row
              key={p.code}
              label={p.choice > 0 ? `Needs one of: ${p.name}` : `Needs ${p.name}`}
              value={<Figure value={`${p.level}`} tone={p.met ? 'success' : 'faint'} />}
            />
          ))}
          <p className="pt-2 text-t-label text-ink-muted">{open.blurb}</p>
          {open.enrol_where && <Hint>{open.enrol_where}</Hint>}
          {open.next_level === null && <Note tone="neutral">Max level reached.</Note>}
          {open.enrol_refusal && (
            <Note tone="warning" code={open.enrol_refusal.code}>
              {open.enrol_refusal.sentence}
            </Note>
          )}
          {open.queue_refusal && (
            <Note tone="warning" code={open.queue_refusal.code}>
              {open.queue_refusal.sentence}
            </Note>
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

function GroupSection({
  name,
  skills,
  book,
  onOpen,
}: {
  name: string
  skills: Skill[]
  book: SkillBook
  onOpen: (code: string) => void
}) {
  if (skills.length === 0) return null
  return (
    <SheetSection heading={name} data-testid={`skill-group-${name}`}>
      <TileField>
        {skills.map((sk) => (
          <SkillTile key={sk.code} code={sk.code} name={sk.name} level={sk.level} max={book.max_level} onClick={() => onOpen(sk.code)} />
        ))}
      </TileField>
    </SheetSection>
  )
}
