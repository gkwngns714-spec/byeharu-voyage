import { useState } from 'react'
import { Figure, Note, Row, Segmented, SheetSection, SignedBars, Skeleton } from '../../../components/ui'
import { useServedRead } from '../../../live/useServedRead'
import { useWorld, portNameOf } from '../../../live/worldStore'
import { formatDucatsDelta } from '../../../lib/format'
import { useT, type TKey } from '../../../lib/i18n'
import { worldReport, type Report as ReportRead, type ReportPlace, type ReportSpan } from '../../../lib/rpc'
import type { DeskLayout } from '../DeskFrame'

// REPORT — every earning and loss, by span, section and place (docs/COMMAND_REDESIGN.md §4, R4; owner row 192,
// 2026-10-25: *"the profit tab on command, change it to report, saving all the earnings and losses by sections,
// points, that is saved."*). Replaces the Profit face (0177's world.books, dropped by 0278).
//
// THE ONE READ IS world.report (0278): the append-only ledger summed by span ('day' | 'week' | 'all', in game
// days — the server's clock), by section (the server's kind->section mapping, §4: Trade · Crew · Supplies ·
// Repairs · Insurance · Invest · Ships · Other) and by place (the row's voyage, else its port, else "Earlier").
// The client computes NOTHING: it prints the served figures, maps a section's served id to the language's label
// (display only — the mapping itself lives in the function), and hands the days to SignedBars. A press on a span
// chip SELECTS it and the figures change in place; nothing collapses, re-flows or docks anything that follows.

const SPANS = ['day', 'week', 'all'] as const

/** The span chips' labels, keyed by the span (desk.reportSpanDay / …Week / …All). */
const SPAN_KEYS: Record<ReportSpan, 'desk.reportSpanDay' | 'desk.reportSpanWeek' | 'desk.reportSpanAll'> = {
  day: 'desk.reportSpanDay',
  week: 'desk.reportSpanWeek',
  all: 'desk.reportSpanAll',
}

/** The section labels, keyed by the SERVER'S section id (the one authority for id -> label; an id the dict
 *  does not know — a future section — prints the served word). The kind->section mapping is the server's. */
const SECTION_KEYS: Record<string, TKey> = {
  trade: 'desk.reportSecTrade',
  crew: 'desk.reportSecCrew',
  supplies: 'desk.reportSecSupplies',
  repairs: 'desk.reportSecRepairs',
  insurance: 'desk.reportSecInsurance',
  invest: 'desk.reportSecInvest',
  ships: 'desk.reportSecShips',
  other: 'desk.reportSecOther',
}

const tone = (n: number): 'success' | 'danger' | 'muted' => (n > 0 ? 'success' : n < 0 ? 'danger' : 'muted')

export function Report({ layout }: { layout: DeskLayout }) {
  const t = useT()
  const portByCode = useWorld((s) => s.portByCode)
  const [span, setSpan] = useState<ReportSpan>('day')
  // THE SUBJECT IS THE FACE, THE QUESTION THE SPAN (useServedRead's pattern): a span press re-asks
  // and the last answer STANDS, dimmed (`stale`), until the new one lands — the figures change in
  // place, nothing blanks or re-flows.
  const read = useServedRead<ReportRead>('report', () => worldReport(span), { question: span })
  const r = read.view
  const dim = read.stale ? 'opacity-60' : ''

  if (read.loading && !r) {
    return layout({
      testid: 'desk-report',
      sideHint: t('desk.reportHint'),
      list: (
        <>
          <Skeleton className="h-[72px] w-full" />
          <Skeleton className="mt-3 h-[96px] w-full" />
        </>
      ),
      main: null,
    })
  }
  if (!r) return layout({ testid: 'desk-report', list: <Note tone="danger">{t('desk.reportFailed')}</Note>, main: null })

  const sectionWord = (id: string, word: string) =>
    id in SECTION_KEYS ? t(SECTION_KEYS[id]) : word

  const placeLabel = (p: ReportPlace) =>
    p.kind === 'port'
      ? portNameOf(portByCode, p.code) ?? p.name
      : p.kind === 'voyage'
        ? `${p.from}→${p.to} · d${p.game_day}`
        : t('desk.reportEarlier')

  // The days the server zero-fills, oldest first; more periods than a phone has pixels hand the LAST
  // ones to SignedBars (its own contract — a picture, never a money figure).
  const bars = r.days.slice(-40).map((d) => ({ id: String(d.game_day), value: d.net }))

  return layout({
    testid: 'desk-report',
    sideHint: t('desk.reportHint'),
    order: ['list', 'main'],
    list: (
      <div className={dim}>
        <Segmented<ReportSpan>
          segments={SPANS.map((s) => ({ id: s, label: t(SPAN_KEYS[s]) }))}
          value={span}
          onChange={setSpan}
          label={t('desk.reportSpans')}
          fill
        />
        <div className="mt-4 grid grid-cols-2 gap-4">
          <div className="min-w-0" data-testid="report-total">
            <span className="block text-t-caption text-ink-faint">{t('desk.profit')}</span>
            <Figure value={formatDucatsDelta(r.total)} tone={tone(r.total)} size="hero" />
          </div>
        </div>

        {/* BY SECTION (design §5): each section with its kind lines, always drawn — a press never
            collapses or re-flows anything below it. */}
        <SheetSection heading={t('desk.reportSections')} surface className="mt-4" data-testid="report-sections">
          {r.sections.length === 0 ? (
            <Row label={t('desk.reportNothing')} tone="muted" hairline={false} />
          ) : (
            r.sections.map((s) => (
              <div key={s.id} data-testid="report-section" data-section={s.id}>
                <Row
                  label={<span className="font-medium">{sectionWord(s.id, s.word)}</span>}
                  value={<Figure value={formatDucatsDelta(s.ducats)} tone={tone(s.ducats)} />}
                  hairline={false}
                />
                {s.lines.map((l) => (
                  <Row
                    key={l.kind}
                    label={<span className="pl-4 text-t-caption text-ink-muted">{l.kind}</span>}
                    value={<Figure value={formatDucatsDelta(l.ducats)} tone="muted" />}
                    hairline={false}
                    data-testid="report-section-line"
                    data-kind={l.kind}
                  />
                ))}
              </div>
            ))
          )}
        </SheetSection>
      </div>
    ),
    main: (
      <div className={dim}>
        {/* BY PLACE (design §5): the port the money moved at, the voyage it belonged to, or Earlier. */}
        <SheetSection heading={t('desk.reportPlaces')} surface data-testid="report-places">
          {r.places.length === 0 ? (
            <Row label={t('desk.reportNothing')} tone="muted" hairline={false} />
          ) : (
            r.places.map((p, i) => (
              <Row
                key={`${p.kind}:${i}`}
                label={<span className="font-medium">{placeLabel(p)}</span>}
                value={<Figure value={formatDucatsDelta(p.ducats)} tone={tone(p.ducats)} />}
                hairline={i < r.places.length - 1}
                data-testid="report-place"
                data-place={p.kind}
              />
            ))
          )}
        </SheetSection>

        {/* ONE BAR A GAME DAY (design §5): up for a gain, down for a loss, the zero line their only axis. */}
        {bars.length > 0 && (
          <SignedBars bars={bars} label={t('desk.reportBars')} className="mt-4" data-testid="report-bars" />
        )}
      </div>
    ),
  })
}
