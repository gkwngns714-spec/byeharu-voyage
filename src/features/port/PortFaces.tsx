import { useEffect, useState } from 'react'
import {
  Badge,
  Button,
  Gauge,
  Notice,
  SectionLabel,
  Skeleton,
} from '../../components/ui'
import { formatInt } from '../../lib/format'
import { useWorld } from '../../live/worldStore'
import type { FleetView, SnapshotPort } from '../../lib/rpc'

// TWO FACES OF THE PORT — the roster (0015) and the school (0016).
//
// THEY LIVE ON THE PORT BECAUSE THAT IS WHERE THEY HAPPEN. §3a of docs/UI_DIRECTION.md names "the
// action lives on the wrong screen" as the second trap the reference game spent four years paying
// for; the most-praised patch in that whole backlog added no feature at all, it moved an action to
// the screen where the need arises. An officer signs on at a quay and a trade is learned at an
// academy, so neither of these is a tab of its own.
//
// THEY DECIDE NOTHING. Every refusal printed here is the server's own sentence — E_NOT_ENOUGH_DUCATS,
// E_SKILL_MAXED, E_NO_ACADEMY — and none of them is pre-empted by a check on this side. The one
// thing the client does with a rule is REFUSE TO OFFER a face the port cannot host (PortScreen only
// lists the Academy tab where `has_academy`), because a face that always refuses is a wasted tap.
//
// They are in their own file because PortScreen was already 576 lines, not because they are a
// section: they use the port's own data and belong to the port screen (docs/SECTIONS.md).

/** An officer whose specialty no rule reads yet must SAY so. `takes_effect` is the server's own
 *  flag (0015 wires NAVIGATOR only), and a bonus that does nothing must never look like one that
 *  works — the migration's receipt makes the same promise in the deploy log. */
function InertNote({ what }: { what: string }) {
  return (
    <p className="mt-1 text-[11px] text-warning">
      No rule reads {what} yet — this bonus changes nothing today.
    </p>
  )
}

function Refused() {
  const refusal = useWorld((s) => s.refusal)
  if (!refusal) return null
  return (
    <Notice tone="danger" className="text-xs">
      <span className="font-mono uppercase tracking-wider">{refusal.code}</span> — {refusal.sentence}
    </Notice>
  )
}

export function OfficersFace({ port, acting }: { port: SnapshotPort; acting: FleetView | null }) {
  const roster = useWorld((s) => s.officers)
  const loadOfficers = useWorld((s) => s.loadOfficers)
  const hireOfficer = useWorld((s) => s.hireOfficer)
  const postOfficer = useWorld((s) => s.postOfficer)
  const [busy, setBusy] = useState<string | null>(null)

  useEffect(() => {
    if (!roster) void loadOfficers()
  }, [roster, loadOfficers])

  if (!roster) return <Skeleton className="h-24 w-full" />

  // An officer is hired WHERE THEY LIVE. The rest of the roster is listed quietly with the port
  // that holds them, so the world reads as a place people are from rather than as a shop.
  const here = roster.officers.filter((o) => o.port === port.code)
  const elsewhere = roster.officers.filter((o) => o.port !== port.code)

  return (
    <div className="space-y-3">
      <Refused />

      <p className="text-xs text-ink-muted">
        An officer signs on where they live and serves in one fleet. No fleet may gain more than{' '}
        {formatInt(roster.bonus_cap_pct)}% from officers of one specialty.
      </p>

      {here.length === 0 ? (
        <p className="text-sm text-ink-muted">Nobody is looking for a berth in {port.name}.</p>
      ) : (
        <ul className="space-y-2">
          {here.map((o) => (
            <li key={o.code} className="bv-cut border border-edge bg-surface-2 p-3">
              <div className="flex flex-wrap items-baseline justify-between gap-2">
                <span className="font-serif text-base text-ink">{o.name}</span>
                <Badge tone={o.takes_effect ? 'accent' : 'neutral'}>{o.specialty}</Badge>
              </div>
              <p className="mt-1 text-xs text-ink-muted">{o.blurb}</p>
              <div className="mt-2 flex flex-wrap items-center gap-x-4 gap-y-1 font-mono text-xs">
                <span className={o.takes_effect ? 'text-success' : 'text-ink-faint'}>
                  +{o.bonus_pct}%
                </span>
                <span className="text-ink-muted">{formatInt(o.wage)} d.</span>
                {o.hired && <span className="text-accent">{o.fleet ?? 'ashore'}</span>}
              </div>
              {!o.takes_effect && <InertNote what={`${o.specialty.toLowerCase()}s`} />}
              <div className="mt-3">
                {o.hired ? (
                  <Button
                    size="sm"
                    variant="secondary"
                    disabled={(!acting && !o.fleet) || busy === o.code}
                    onClick={async () => {
                      setBusy(o.code)
                      await postOfficer(o.code, o.fleet ? null : (acting?.id ?? null))
                      setBusy(null)
                    }}
                  >
                    {o.fleet ? 'Send ashore' : `Post to ${acting?.name ?? 'a fleet'}`}
                  </Button>
                ) : (
                  <Button
                    size="sm"
                    variant="primary"
                    disabled={busy === o.code}
                    onClick={async () => {
                      setBusy(o.code)
                      await hireOfficer(o.code, acting?.id ?? null)
                      setBusy(null)
                    }}
                  >
                    Sign for {formatInt(o.wage)} d.
                  </Button>
                )}
              </div>
            </li>
          ))}
        </ul>
      )}

      {elsewhere.length > 0 && (
        <div>
          <SectionLabel>Serving elsewhere</SectionLabel>
          <ul className="space-y-1">
            {elsewhere.map((o) => (
              <li key={o.code} className="font-mono text-[11px] text-ink-faint">
                {o.name} · {o.specialty.toLowerCase()} · {o.port ?? 'no port'}
                {o.hired ? ' · signed' : ''}
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  )
}

export function AcademyFace({ port, acting }: { port: SnapshotPort; acting: FleetView | null }) {
  const book = useWorld((s) => s.skills)
  const loadSkills = useWorld((s) => s.loadSkills)
  const studySkill = useWorld((s) => s.studySkill)
  const [busy, setBusy] = useState<string | null>(null)

  useEffect(() => {
    if (!book) void loadSkills()
  }, [book, loadSkills])

  if (!book) return <Skeleton className="h-24 w-full" />

  return (
    <div className="space-y-3">
      <Refused />

      <p className="text-xs text-ink-muted">
        {port.name} keeps an academy. A trade is learned ashore, one level at a time, and the fleet
        you name is the one whose captain sits the course.
      </p>

      <ul className="space-y-2">
        {book.skills.map((sk) => (
          <li key={sk.code} className="bv-cut border border-edge bg-surface-2 p-3">
            <div className="flex flex-wrap items-baseline justify-between gap-2">
              <span className="font-serif text-base text-ink">{sk.name}</span>
              <span className="flex items-center gap-2">
                <Gauge
                  value={sk.level}
                  max={book.max_level}
                  segments={book.max_level}
                  tone={sk.level > 0 ? 'accent' : 'neutral'}
                  label={`${sk.name}, level ${sk.level} of ${book.max_level}`}
                />
                <span className="font-mono text-xs text-ink">
                  {sk.level}/{book.max_level}
                </span>
              </span>
            </div>
            <p className="mt-1 text-xs text-ink-muted">{sk.blurb}</p>
            <p className="mt-2 font-mono text-xs">
              <span className={sk.takes_effect ? 'text-success' : 'text-ink-faint'}>
                +{sk.pct_per_level}% per level
              </span>
            </p>
            {!sk.takes_effect && <InertNote what="this" />}
            <div className="mt-3">
              <Button
                size="sm"
                variant={sk.takes_effect ? 'primary' : 'secondary'}
                disabled={!acting || sk.next_cost === null || busy === sk.code}
                onClick={async () => {
                  if (!acting) return
                  setBusy(sk.code)
                  await studySkill(sk.code, acting.id)
                  setBusy(null)
                }}
              >
                {sk.next_cost === null
                  ? 'Taught as far as it goes'
                  : `Study to ${sk.level + 1} — ${formatInt(sk.next_cost)} d.`}
              </Button>
            </div>
          </li>
        ))}
      </ul>
    </div>
  )
}
