import { useState } from 'react'
import { Bar, DetailPage, Empty, Figure, GroupHeading, type IconName, Note, Row, ScrollPane, Segmented, SignedBars, Skeleton, SummaryRow } from '../../../components/ui'
import { useServedRead } from '../../../live/useServedRead'
import { formatDucatsDelta, formatRealDay } from '../../../lib/format'
import { worldReport, type Report as ReportView, type ReportLine, type ReportPlace, type ReportSection } from '../../../lib/rpc'
import { t as tNow, useLocale, useT, type TKey } from '../../../lib/i18n'
import { moneyKindWord } from '../../../live/moneyWords'
import type { DeskLayout } from '../deskLayout'
import { HistoryChart } from '../../../live/HistoryChart'
import { companyLines } from '../../../live/historyLines'
import { reportBars } from '../../../live/reportBars'
import { portNameOf, useWorld } from '../../../live/worldStore'

// REPORT — every earning and loss by SECTION and by POINT (0286, docs/COMMAND_REDESIGN.md §4–5;
// owner rows 192, 244: *"the profit tab on command, change it to report, saving all the earnings and
// losses by sections, points"* / *"do 2, the report"*).
//
// ONE READ: world.report(span). The ledger is the record every coin moves through; the server cuts it
// by the design's fixed sections (Trade · Crew · Supplies · Repairs · Insurance · Invest · Ships ·
// Other) and by point (port, else voyage, else Earlier last), over game days. Nothing here computes
// money: the figures are the served sums, and the bars are the served days. The client never works
// out a span or a day — Day is [today], Week is the served seven, All is every day the server kept.
//
// THE COMPACT SCREEN (owner, 2026-10-31): the span chips, the total and the bars stand; every section
// and every place is ONE summary row with its figure, and a press opens its own full-screen page
// with its lines whole (SummaryRow → DetailPage, the one mechanism). Nothing unfolds in place.

type Span = ReportView['span']
type Open = { kind: 'section'; id: ReportSection['id'] } | { kind: 'place'; index: number } | { kind: 'history' } | null

const SPANS = [
  { id: 'day' as const, get label() { return tNow('desk.spanDay') } },
  { id: 'week' as const, get label() { return tNow('desk.spanWeek') } },
  { id: 'all' as const, get label() { return tNow('desk.spanAll') } },
]

const SECTION_KEYS: Record<ReportSection['id'], TKey> = {
  trade: 'desk.secTrade',
  crew: 'desk.secCrew',
  supplies: 'desk.secSupplies',
  repairs: 'desk.secRepairs',
  insurance: 'desk.secInsurance',
  invest: 'desk.secInvest',
  ships: 'desk.secShips',
  other: 'desk.secOther',
}

/** Each section's glyph (visual pass 2, 2026-11-23): the list is found by its marks, the same ones those facts wear elsewhere. */
const SECTION_ICONS: Record<ReportSection['id'], IconName> = {
  trade: 'scales',
  crew: 'crew',
  supplies: 'cask',
  repairs: 'wrench',
  insurance: 'shield',
  invest: 'invest',
  ships: 'ship',
  other: 'coin',
}


const tone = (n: number): 'success' | 'danger' | 'muted' => (n > 0 ? 'success' : n < 0 ? 'danger' : 'muted')

export function Report({ layout }: { layout: DeskLayout }) {
  const t = useT()
  const locale = useLocale()
  const [span, setSpan] = useState<Span>('week')
  const [open, setOpen] = useState<Open>(null)
  const read = useServedRead<ReportView>(`report:${span}`, () => worldReport(span))
  const r = read.view
  const portByCode = useWorld((s) => s.portByCode)

  if (read.loading && !r) {
    return layout({
      testid: 'desk-report',
      list: (
        <>
          <Skeleton className="h-11 w-full" />
          <Skeleton className="mt-3 h-[72px] w-full" />
          <Skeleton className="mt-3 h-[120px] w-full" />
        </>
      ),
      main: <Skeleton className="h-[160px] w-full" />,
    })
  }
  if (!r) {
    return layout({ testid: 'desk-report', list: <Note tone="danger">{t('desk.reportFailed')}</Note>, main: null })
  }

  const nothing = r.sections.every((s) => s.lines.length === 0) && r.places.length === 0
  // the bars are the days that are over; today stands in the total (reportBars: owner, 2026-11-07, no right edge that goes down)
  const bars = reportBars(r.days)
  // a known kind is the one money word list's (live/moneyWords.ts); an unlisted one keeps the server's own word.
  const lineWord = (l: ReportLine) => moneyKindWord(locale, l.kind, l.word)
  const lines = (list: ReportLine[]) =>
    list.length === 0 ? (
      <Note tone="neutral">{t('desk.reportNothing')}</Note>
    ) : (
      list.map((l) => (
        <Row
          key={l.kind}
          label={<span className="text-t-body text-ink">{lineWord(l)}</span>}
          value={<Figure value={formatDucatsDelta(l.ducats)} tone={tone(l.ducats)} />}
        />
      ))
    )
  // A PLACE BY ITS NAME IN HER LANGUAGE (2026-11-22 play-test: "Lisbon", "Setubal" on a Korean Report): the store's named port by its
  // served CODE (portNameOf, the one reading of a port's name), else the served English name, else the code.
  const placeName = (code: string | null, served: string | null) => (code && portByCode[code] ? portNameOf(portByCode, code) : (served ?? code))
  const placeTitle = (p: ReportPlace) =>
    p.kind === 'port'
      ? (placeName(p.code, p.name) ?? t('desk.byPlace'))
      : p.kind === 'voyage'
        ? `${t('desk.voyageWord')} ${placeName(p.from, p.from_name) ?? '—'}→${placeName(p.to, p.to_name) ?? '—'}${p.day === null ? '' : ` ${formatRealDay(p.day)}`}`
        : t('desk.earlier')

  // EACH ROW'S SHARE AS A BAR (2026-11-23, slice 7): a section's or a place's served sum against the largest of its list, green in and red out,
  // so the list is read by its bars before its figures. Drawn from the served sums; nothing is added up here.
  const share = (d: number, all: readonly { ducats: number }[]) => {
    const most = Math.max(0, ...all.map((x) => Math.abs(x.ducats)))
    return <Bar pct={most > 0 ? (Math.abs(d) / most) * 100 : 0} tone={d > 0 ? 'success' : d < 0 ? 'danger' : 'neutral'} />
  }
  const section = (s: ReportSection) => (
    <SummaryRow
      key={s.id}
      title={t(SECTION_KEYS[s.id])}
      icon={SECTION_ICONS[s.id]}
      figure={<Figure value={formatDucatsDelta(s.ducats)} tone={tone(s.ducats)} />}
      meter={share(s.ducats, r.sections)}
      onClick={() => setOpen({ kind: 'section', id: s.id })}
      data-testid={`report-section-${s.id}`}
    />
  )
  const place = (p: ReportPlace, i: number) => (
    <SummaryRow
      key={`${p.kind}-${i}`}
      title={placeTitle(p)}
      figure={<Figure value={formatDucatsDelta(p.ducats)} tone={tone(p.ducats)} />}
      meter={share(p.ducats, r.places)}
      onClick={() => setOpen({ kind: 'place', index: i })}
      data-testid={`report-place-${p.kind}-${i}`}
    />
  )

  const openSection = open?.kind === 'section' ? (r.sections.find((s) => s.id === open.id) ?? null) : null
  const openPlaceIndex = open?.kind === 'place' ? open.index : -1
  const openPlace = openPlaceIndex >= 0 ? (r.places[openPlaceIndex] ?? null) : null

  return layout({
    testid: 'desk-report',
    list: (
      <>
        <div data-testid="report-spans">
          <Segmented<Span> segments={SPANS} value={span} onChange={setSpan} label={t('desk.reportSpans')} fill />
        </div>
        <div className="mt-3 flex min-w-0 items-baseline justify-between gap-3">
          <span className="text-t-caption text-ink-faint">{t('desk.profit')}</span>
          <span data-testid="report-total">
            <Figure value={formatDucatsDelta(r.total)} tone={tone(r.total)} size="hero" />
          </span>
        </div>
        <GroupHeading className="mt-3">{t('desk.bySection')}</GroupHeading>
        <ScrollPane className="max-h-[13rem] lg:max-h-none" data-testid="report-sections">
          <div className="flex flex-col gap-1.5">
            {r.sections.map(section)}
            {/* a door, not a card: the record by day, week and month is a page of its own, and sits in this scrolling list so the face stays one glass tall at 390 px (tests/onepage.spec.ts) */}
            <SummaryRow title={t('stats.yourHistory')} onClick={() => setOpen({ kind: 'history' })} data-testid="report-history" />
          </div>
        </ScrollPane>
      </>
    ),
    main: (
      <>
        <GroupHeading>{t('desk.byPlace')}</GroupHeading>
        <ScrollPane className="max-h-[10rem] lg:max-h-none" data-testid="report-places">
          {nothing ? (
            // no place has moved money yet: the well's one line. Not the drawn anchor of visual pass 2: its disc made the face 738 px in a
            // 715-px Sheet at 390, and this face stays one glass tall (tests/onepage.spec.ts, tests/consistency.spec.ts)
            <Empty>{t('desk.reportNothing')}</Empty>
          ) : (
            <div className="flex flex-col gap-1.5">{r.places.map(place)}</div>
          )}
        </ScrollPane>
        {bars.length > 0 && (
          <SignedBars
            bars={bars}
            label={t('desk.reportByDay')}
            className="mt-3"
            data-testid="report-bars"
          />
        )}
        {open?.kind === 'history' && (
          <DetailPage title={t('stats.yourHistory')} onClose={() => setOpen(null)} data-testid="report-history-page">
            <HistoryChart what="me" title={t('stats.yourHistory')} lines={companyLines(t)} data-testid="history-me" />
          </DetailPage>
        )}
        {openSection !== null && (
          <DetailPage
            title={t(SECTION_KEYS[openSection.id])}
            figure={<Figure value={formatDucatsDelta(openSection.ducats)} tone={tone(openSection.ducats)} />}
            onClose={() => setOpen(null)}
            data-testid={`report-section-${openSection.id}-page`}
          >
            {lines(openSection.lines)}
          </DetailPage>
        )}
        {openPlace !== null && (
          <DetailPage
            title={placeTitle(openPlace)}
            figure={<Figure value={formatDucatsDelta(openPlace.ducats)} tone={tone(openPlace.ducats)} />}
            onClose={() => setOpen(null)}
            data-testid={`report-place-${openPlace.kind}-${openPlaceIndex}-page`}
          >
            {lines(openPlace.lines)}
          </DetailPage>
        )}
      </>
    ),
  })
}
