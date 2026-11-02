import { useMemo, useState, type ReactNode } from 'react'
import {
  ALL,
  Card,
  FactsLine,
  FilterBar,
  Figure,
  Hint,
  Icon,
  ListPanel,
  Note,
  PageSplit,
  RankBars,
  Row,
  Skeleton,
  Tray,
  type RankRow,
  type TrayDetent,
} from '../../components/ui'
import { COIN, formatInt, formatPctPoints } from '../../lib/format'
import type { Officer } from '../../lib/rpc'
import { fold, foldedMatch } from '../../lib/text'
import { nationNameOf, portNameOf, useWorld } from '../../live/worldStore'
import { optionsOf } from './codexFilters'
import { NoAnswer } from './NoAnswer'
import { useT, t as tNow } from '../../lib/i18n'

// THE CAPTAINS FACE — every captain in the world, signed or not, ON THE PAGE (2026-11-02, owner row 267; the pattern is
// Stats', docs/dev-log/2026-11-02-stats-design.md). MAIN | SIDE: MAIN is ONE list card — a row a captain, the three filters one
// line of pickers in its header, the search on its title line, the rows in as many columns as the main holds; the SIDE is the
// tray's column and holds the roster's shape AS GRAPHICS — how many captains of each grade and of each role stand among the
// rows the filters leave, as ranked bars. Each captain is found in an Inn and hired there (PORT's Inn); nothing here hires
// anyone. A press on a row opens her tray, which slides over the side column and moves nothing.
//
// GRADE, JOB AND VALUE ON THE ROW, AND NOTHING ELSE (docs/UI_DIRECTION.md §6). A bonus nothing
// reads is still shown — hiding it would sell a bonus that does nothing — but as a MUTED row,
// with the reason in the tray rather than as a line of fine print printed a hundred times down the
// face. The traits, the languages, the blurb, the wage, the port and the flag are the tray's.
//
// THE CARD IS THE SERVER'S (0156, K4): grade, job, focus, the traits she knows with their lines,
// and the "Speaks …" sentence come from world.captain_card through world.officers. The three
// filters — Grade, Role, Job — are pickers of the values the SERVED captains carry, plus "All":
// nothing is offered that no captain has, and every label is a served word. The two boards count the
// served grade and the served focus; counting is presentation, not authorship.

type Filters = { grade: string; focus: string; job: string }
const NO_FILTER: Filters = { grade: ALL, focus: ALL, job: ALL }
const EMPTY: readonly Officer[] = []

const gradeOrd = (officers: readonly Officer[], grade: string) => officers.find((o) => o.grade === grade)?.grade_ord ?? 0

/** How many of the rows carry each value of a key, best first by `order`, as ranked bars' rows. */
function countBy(rows: readonly Officer[], key: (o: Officer) => string | undefined, label: (o: Officer) => string | undefined, order: (a: string, b: string) => number): RankRow[] {
  const counts = new Map<string, { n: number; first: Officer }>()
  for (const o of rows) {
    const v = key(o)
    if (v === undefined) continue
    const got = counts.get(v)
    if (got) got.n++
    else counts.set(v, { n: 1, first: o })
  }
  return [...counts.entries()]
    .sort(([a], [b]) => order(a, b))
    .map(([v, { n, first }]) => ({ id: v, label: label(first) ?? v, value: n }))
}

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

  // best first, by the served ladder (`grade_ord`): a grade above S costs the server a row, not this file a letter
  const byGrade = useMemo(() => (a: string, b: string) => gradeOrd(all, b) - gradeOrd(all, a), [all])
  const facets = useMemo(
    () => ({
      grade: optionsOf(tNow('codex.grade'), all, (o) => o.grade, (v) => v, byGrade),
      focus: optionsOf(tNow('codex.role'), all, (o) => o.focus, (_v, o) => o.focus_word),
      job: optionsOf(tNow('codex.job'), all, (o) => o.job, (_v, o) => o.job_word),
    }),
    [all, byGrade],
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

  // THE TWO BOARDS: the rows on the face by grade (best first) and by role (the biggest count first)
  const grades = useMemo(() => countBy(rows, (o) => o.grade, (o) => o.grade, byGrade), [rows, byGrade])
  const roles = useMemo(() => {
    const counted = countBy(rows, (o) => o.focus, (o) => o.focus_word, (a, b) => a.localeCompare(b))
    return counted.sort((a, b) => b.value - a.value || String(a.label).localeCompare(String(b.label)))
  }, [rows])

  if (officers === null) {
    return (
      <ListPanel look="card" title={t('codex.captains')} data-testid="codex-list">
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
      <PageSplit
        data-testid="codex-captains"
        // no `sideFirst`: on a phone the boards stand AFTER the list — the Codex's purpose is the list, and its first rows are on the first glass
        stickySide
        main={
          <ListPanel
            look="card"
            columns="fit"
            title={t('codex.captains')}
            count={formatInt(rows.length)}
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
                  hairline={false}
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
        }
        side={
          <>
            <Card title={t('codex.byGrade')} data-testid="codex-captains-grades">
              <RankBars rules={false} format={formatInt} empty={t('codex.noMatches')} rows={grades} />
            </Card>
            <Card title={t('codex.byRole')} data-testid="codex-captains-roles">
              <RankBars rules={false} format={formatInt} empty={t('codex.noMatches')} rows={roles} />
            </Card>
          </>
        }
      />

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
          {/* A TRAIT IS ITS NAME ON LINE 1 AND ITS SENTENCE ON LINE 2 (2026-11-02). The sentence is a clause or two of prose
              ("−4.2% crew lost to pirates · −4.2 points of homesickness", 436 px) and `Row` keeps a `value` on one line, so
              as the value it shoved the tray 74 px sideways at 390 and left "Surgeon" one letter wide; on line 2 it wraps
              under its label and the row is as wide as the tray. The row's tone and the served `in_use` still colour it. */}
          {(open.traits ?? []).map((t) => (
            <Row key={t.code} label={t.word} tone={t.in_use ? 'default' : 'muted'} data-testid={`captain-trait-${t.code}`}>
              <span className={`block text-t-body ${t.in_use ? 'text-success' : ''}`}>{t.lines.join(' · ')}</span>
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
