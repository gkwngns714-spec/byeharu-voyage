import { useMemo, useState } from 'react'
import {
  Figure,
  Hint,
  Note,
  Row,
  Segmented,
  Skeleton,
  OfficerTile,
  TileField,
  Tray,
  type SegmentSpec,
  type TrayDetent,
} from '../../components/ui'
import { COIN, formatInt, formatPctPoints } from '../../lib/format'
import type { Officer } from '../../lib/rpc'
import { fold, foldedMatch } from '../../lib/text'
import { nationNameOf, portNameOf, useWorld } from '../../live/worldStore'
import { NoAnswer } from './NoAnswer'
import { useT, t as tNow } from '../../lib/i18n'

// THE CAPTAINS FACE — every captain in the world, signed or not. Each is found in an Inn and hired
// there (PORT's Inn); nothing here hires anyone.
//
// GRADE, JOB AND VALUE ON THE TILE, AND NOTHING ELSE (docs/UI_DIRECTION.md §6). A bonus nothing
// reads is still shown — hiding it would sell a bonus that does nothing — but as a MUTED tile,
// with the reason in the tray rather than as a line of fine print printed a hundred times down the
// face. The traits, the languages, the blurb, the wage, the port and the flag are the tray's.
//
// THE CARD IS THE SERVER'S (0156, K4): grade, job, focus, the traits she knows with their lines,
// and the "Speaks …" sentence come from world.captain_card through world.officers. The three
// filters — Grade, Role, Job — are rows of the values the SERVED captains carry, plus "All":
// nothing is offered that no captain has, and every label is a served word.

const ALL = 'all'
type Filters = { grade: string; focus: string; job: string }
const NO_FILTER: Filters = { grade: ALL, focus: ALL, job: ALL }
const EMPTY: readonly Officer[] = []

/** The distinct served values of one key, behind "All", in the served order of first appearance
 *  unless an order is given. */
function segmentsOf(
  officers: readonly Officer[],
  key: (o: Officer) => string | undefined,
  label: (o: Officer) => string | undefined,
  order?: (a: string, b: string) => number,
): SegmentSpec<string>[] {
  const firstOf = new Map<string, Officer>()
  for (const o of officers) {
    const v = key(o)
    if (v !== undefined && !firstOf.has(v)) firstOf.set(v, o)
  }
  const ids = [...firstOf.keys()]
  if (order) ids.sort(order)
  return [{ id: ALL, label: tNow('codex.all') }, ...ids.map((v) => ({ id: v, label: label(firstOf.get(v)!) ?? v }))]
}

const gradeOrd = (officers: readonly Officer[], grade: string) => officers.find((o) => o.grade === grade)?.grade_ord ?? 0

export function CaptainsFace({ query, answered }: { query: string; answered: boolean }) {
  const t = useT()
  const roster = useWorld((s) => s.officers)
  const portByCode = useWorld((s) => s.portByCode)
  const nationByCode = useWorld((s) => s.nationByCode)
  const officers = roster?.officers ?? null
  const all = officers ?? EMPTY
  const [open, setOpen] = useState<Officer | null>(null)
  const [detent, setDetent] = useState<TrayDetent>('half')
  const [filters, setFilters] = useState<Filters>(NO_FILTER)

  const facets = useMemo(
    () => ({
      // best first, by the served ladder (`grade_ord`): a grade above S costs the server a row, not this file a letter
      grade: segmentsOf(all, (o) => o.grade, (o) => o.grade, (a, b) => gradeOrd(all, b) - gradeOrd(all, a)),
      focus: segmentsOf(all, (o) => o.focus, (o) => o.focus_word),
      job: segmentsOf(all, (o) => o.job, (o) => o.job_word),
    }),
    [all],
  )

  const rows = useMemo(() => {
    const needle = fold(query.trim())
    return all.filter(
      (o) =>
        foldedMatch(
          needle,
          o.name,
          o.job_word ?? o.specialty,
          o.port === null ? null : portNameOf(portByCode, o.port),
          o.nation === null ? null : nationNameOf(nationByCode, o.nation),
          ...(o.languages ?? []),
        ) &&
        (filters.grade === ALL || o.grade === filters.grade) &&
        (filters.focus === ALL || o.focus === filters.focus) &&
        (filters.job === ALL || o.job === filters.job),
    )
  }, [all, query, filters, portByCode, nationByCode])

  if (officers === null) {
    return answered ? (
      <Note tone="warning">{t('codex.captainsFailed')}</Note>
    ) : (
      <div className="space-y-2">
        <Skeleton className="h-28 w-full" />
        <Skeleton className="h-28 w-full" />
      </div>
    )
  }

  const filterBar = (
    <div className="mb-3 flex flex-col gap-2" data-testid="captain-filters">
      {(['grade', 'focus', 'job'] as const).map((k) =>
        facets[k].length > 2 ? (
          <Segmented
            key={k}
            label={t(({ grade: 'codex.grade', focus: 'codex.role', job: 'codex.job' } as const)[k])}
            segments={facets[k]}
            value={filters[k]}
            onChange={(v) => setFilters((f) => ({ ...f, [k]: v }))}
          />
        ) : null,
      )}
    </div>
  )

  if (rows.length === 0) {
    return (
      <>
        {filterBar}
        <NoAnswer />
      </>
    )
  }

  return (
    <>
      {filterBar}
      <TileField>
        {rows.map((o) => (
          // THE TILE is the design system's `OfficerTile` since 2026-10-08 (a merchant's sheet prints
          // the same captain). SIGNED is a fact about the world, not an offer: whose company holds
          // her is read from the roster and only read.
          <OfficerTile
            key={o.code}
            name={o.name}
            role={o.job_word ?? o.specialty.toLowerCase()}
            grade={o.grade ?? null}
            bonusPct={o.bonus_pct}
            homePort={o.port ? portNameOf(portByCode, o.port) : null}
            signed={o.hired}
            level={o.level ?? null}
            takesEffect={o.takes_effect}
            onClick={() => {
              setDetent('half')
              setOpen(o)
            }}
          />
        ))}
      </TileField>

      {open && (
        <Tray
          detent={detent}
          onDetentChange={(next) => (next === 'closed' ? setOpen(null) : setDetent(next))}
          title={open.name}
          data-testid="officer-tray"
        >
          {open.grade && <Row label={t('codex.grade')} value={open.grade} data-testid="captain-grade" />}
          <Row
            label={open.job_word ? `${open.job_word} · ${open.focus_word ?? ''}` : open.specialty.toLowerCase()}
            value={
              <Figure
                value={`+${formatPctPoints(open.bonus_pct)}`}
                tone={open.takes_effect ? 'success' : 'faint'}
              />
            }
          />
          {(open.traits ?? []).map((t) => (
            <Row
              key={t.code}
              label={t.word}
              value={<Figure value={t.lines.join(' · ')} tone={t.in_use ? 'success' : 'faint'} />}
              tone={t.in_use ? 'default' : 'muted'}
              data-testid={`captain-trait-${t.code}`}
            >
              {t.note && <Hint>{t.note}</Hint>}
            </Row>
          ))}
          {open.speaks && <Row label={open.speaks} tone="muted" data-testid="captain-speaks" />}
          {/* "signs for" is the server's own phrase (0015's refusal says it word for word). */}
          <Row label={t('codex.wage')} value={<Figure value={formatInt(open.wage)} unit={t('codex.perVoyage', { coin: COIN })} />} />
          <Row
            label={t('codex.port')}
            value={open.port === null ? t('codex.noneFixed') : portNameOf(portByCode, open.port)}
            tone={open.port === null ? 'muted' : 'default'}
          />
          {open.nation !== null && <Row label={t('codex.nation')} value={nationNameOf(nationByCode, open.nation)} />}
          {open.hired && (
            <Row label={t('codex.workingFor')} value={open.fleet ?? t('codex.nobody')} tone="accent" hairline={false} />
          )}
          <p className="pt-2 text-t-label text-ink-muted">{open.blurb}</p>
          {!open.takes_effect && (
            <Note tone="neutral" className="mt-2">
              {t('codex.noEffect')}
            </Note>
          )}
        </Tray>
      )}
    </>
  )
}
