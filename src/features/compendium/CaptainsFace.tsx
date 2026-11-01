import { useMemo, useState, type ReactNode } from 'react'
import {
  FactsLine,
  FilterBar,
  Figure,
  Hint,
  Icon,
  ListPanel,
  Note,
  Row,
  Skeleton,
  Tray,
  type TrayDetent,
} from '../../components/ui'
import { COIN, formatInt, formatPctPoints } from '../../lib/format'
import type { Officer } from '../../lib/rpc'
import { fold, foldedMatch } from '../../lib/text'
import { nationNameOf, portNameOf, useWorld } from '../../live/worldStore'
import { NoAnswer } from './NoAnswer'
import { useT, t as tNow } from '../../lib/i18n'

// THE CAPTAINS FACE — every captain in the world, signed or not, ON THE GLASS (the unfold slice, 2026-11-02).
// Each is found in an Inn and hired there (PORT's Inn); nothing here hires anyone.
//
// GRADE, JOB AND VALUE ON THE ROW, AND NOTHING ELSE (docs/UI_DIRECTION.md §6). A bonus nothing
// reads is still shown — hiding it would sell a bonus that does nothing — but as a MUTED row,
// with the reason in the tray rather than as a line of fine print printed a hundred times down the
// face. The traits, the languages, the blurb, the wage, the port and the flag are the tray's.
//
// THE CARD IS THE SERVER'S (0156, K4): grade, job, focus, the traits she knows with their lines,
// and the "Speaks …" sentence come from world.captain_card through world.officers. The three
// filters — Grade, Role, Job — are pickers of the values the SERVED captains carry, plus "All":
// nothing is offered that no captain has, and every label is a served word.

const ALL = 'all'
type Filters = { grade: string; focus: string; job: string }
const NO_FILTER: Filters = { grade: ALL, focus: ALL, job: ALL }
const EMPTY: readonly Officer[] = []

interface Option {
  id: string
  label: string
}

/** The distinct served values of one key, behind "All", in the served order of first appearance
 *  unless an order is given. */
function optionsOf(
  all: string,
  officers: readonly Officer[],
  key: (o: Officer) => string | undefined,
  label: (o: Officer) => string | undefined,
  order?: (a: string, b: string) => number,
): Option[] {
  const firstOf = new Map<string, Officer>()
  for (const o of officers) {
    const v = key(o)
    if (v !== undefined && !firstOf.has(v)) firstOf.set(v, o)
  }
  const ids = [...firstOf.keys()]
  if (order) ids.sort(order)
  return [{ id: ALL, label: all }, ...ids.map((v) => ({ id: v, label: label(firstOf.get(v)!) ?? v }))]
}

const gradeOrd = (officers: readonly Officer[], grade: string) => officers.find((o) => o.grade === grade)?.grade_ord ?? 0

export function CaptainsFace({ query, search, answered }: { query: string; search: ReactNode; answered: boolean }) {
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
      grade: optionsOf(tNow('codex.grade'), all, (o) => o.grade, (o) => o.grade, (a, b) => gradeOrd(all, b) - gradeOrd(all, a)),
      focus: optionsOf(tNow('codex.role'), all, (o) => o.focus, (o) => o.focus_word),
      job: optionsOf(tNow('codex.job'), all, (o) => o.job, (o) => o.job_word),
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
    return (
      <ListPanel title={t('codex.captains')} data-testid="codex-list">
        {answered ? (
          <Note tone="warning" className="my-1">{t('codex.captainsFailed')}</Note>
        ) : (
          <div className="space-y-2 py-1">
            <Skeleton className="h-12 w-full" />
            <Skeleton className="h-12 w-full" />
          </div>
        )}
      </ListPanel>
    )
  }

  const picks = (['grade', 'focus', 'job'] as const)
    .filter((k) => facets[k].length > 2)
    .map((k) => ({
      id: k,
      label: t(({ grade: 'codex.grade', focus: 'codex.role', job: 'codex.job' } as const)[k]),
      options: facets[k],
      value: filters[k],
      onChange: (v: string) => setFilters((f) => ({ ...f, [k]: v })),
    }))

  return (
    <>
      <ListPanel
        title={t('codex.countCaptains', { n: formatInt(rows.length), count: rows.length })}
        trailing={search}
        controls={picks.length > 0 ? <FilterBar compact data-testid="captain-filters" picks={picks} /> : undefined}
        data-testid="codex-list"
      >
        {rows.length === 0 ? (
          <NoAnswer />
        ) : (
          rows.map((o) => (
            // THE ROW is a captain as the Inn prints her. SIGNED is a fact about the world, not an offer: whose
            // company holds her is read from the roster and only read; a bonus nothing reads is MUTED.
            <Row
              key={o.code}
              mark={<Icon name="crew" size={20} />}
              label={o.name}
              value={<Figure value={`+${formatPctPoints(o.bonus_pct)}`} tone={o.takes_effect ? 'success' : 'faint'} />}
              tone={o.takes_effect ? 'default' : 'muted'}
              chevron
              onClick={() => {
                setDetent('half')
                setOpen(o)
              }}
              data-testid="officer-tile"
            >
              <FactsLine>
                {[
                  o.grade ?? null,
                  o.job_word ?? o.specialty.toLowerCase(),
                  o.hired ? t('ui.signed') : null,
                  o.level != null ? t('ui.level', { n: o.level }) : null,
                  o.port ? portNameOf(portByCode, o.port) : null,
                ]
                  .filter(Boolean)
                  .map((part, i) => (
                    <span key={i}>{part}</span>
                  ))}
              </FactsLine>
            </Row>
          ))
        )}
      </ListPanel>

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
