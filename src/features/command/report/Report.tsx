import { useState } from 'react'
import { DetailPage, Figure, Note, Row, ScrollPane, Segmented, SignedBars, Skeleton, SummaryRow } from '../../../components/ui'
import { useServedRead } from '../../../live/useServedRead'
import { formatDucatsDelta } from '../../../lib/format'
import { worldReport, type Report as ReportView, type ReportLine, type ReportPlace, type ReportSection } from '../../../lib/rpc'
import { t as tNow, useT, type TKey } from '../../../lib/i18n'
import type { DeskLayout } from '../DeskFrame'

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
type Open = { kind: 'section'; id: ReportSection['id'] } | { kind: 'place'; index: number } | null

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

const KIND_KEYS: Record<string, TKey> = {
  SELL: 'desk.kindSell',
  BUY: 'desk.kindBuy',
  TAX: 'desk.kindTax',
  PORT_FEE: 'desk.kindPortFee',
  WAGES: 'desk.kindWages',
  HIRE: 'desk.kindHire',
  PROVISION: 'desk.kindProvision',
  REPAIR: 'desk.kindRepair',
  INSURANCE: 'desk.kindInsurance',
  INSURANCE_PAID: 'desk.kindInsurancePaid',
  SHARE: 'desk.kindShare',
  DIVIDEND: 'desk.kindDividend',
  DONATION: 'desk.kindDonation',
  BUILD: 'desk.kindBuild',
  TUITION: 'desk.kindTuition',
  TOW: 'desk.kindTow',
}

const hint = () => tNow('desk.reportHint')

const tone = (n: number): 'success' | 'danger' | 'muted' => (n > 0 ? 'success' : n < 0 ? 'danger' : 'muted')

export function Report({ layout }: { layout: DeskLayout }) {
  const t = useT()
  const [span, setSpan] = useState<Span>('week')
  const [open, setOpen] = useState<Open>(null)
  const read = useServedRead<ReportView>(`report:${span}`, () => worldReport(span))
  const r = read.view

  if (read.loading && !r) {
    return layout({
      testid: 'desk-report',
      sideHint: hint(),
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
    return layout({ testid: 'desk-report', sideHint: hint(), list: <Note tone="danger">{t('desk.reportFailed')}</Note>, main: null })
  }

  const nothing = r.sections.every((s) => s.lines.length === 0) && r.places.length === 0
  // a known kind is the dictionary's word; an unlisted one keeps the server's own-name fallback.
  const lineWord = (l: ReportLine) => {
    const key = KIND_KEYS[l.kind]
    return key ? t(key) : l.word
  }
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
  const placeTitle = (p: ReportPlace) =>
    p.kind === 'port'
      ? (p.name ?? p.code ?? t('desk.byPlace'))
      : p.kind === 'voyage'
        ? `${t('desk.voyageWord')} ${p.from ?? '—'}→${p.to ?? '—'}${p.day === null ? '' : ` d${p.day}`}`
        : t('desk.earlier')

  const section = (s: ReportSection) => (
    <SummaryRow
      key={s.id}
      title={t(SECTION_KEYS[s.id])}
      figure={<Figure value={formatDucatsDelta(s.ducats)} tone={tone(s.ducats)} />}
      word={t('common.open')}
      onClick={() => setOpen({ kind: 'section', id: s.id })}
      data-testid={`report-section-${s.id}`}
    />
  )
  const place = (p: ReportPlace, i: number) => (
    <SummaryRow
      key={`${p.kind}-${i}`}
      title={placeTitle(p)}
      figure={<Figure value={formatDucatsDelta(p.ducats)} tone={tone(p.ducats)} />}
      word={t('common.open')}
      onClick={() => setOpen({ kind: 'place', index: i })}
      data-testid={`report-place-${p.kind}-${i}`}
    />
  )

  const openSection = open?.kind === 'section' ? (r.sections.find((s) => s.id === open.id) ?? null) : null
  const openPlaceIndex = open?.kind === 'place' ? open.index : -1
  const openPlace = openPlaceIndex >= 0 ? (r.places[openPlaceIndex] ?? null) : null

  return layout({
    testid: 'desk-report',
    sideHint: hint(),
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
        <h3 className="mb-1 mt-3 text-t-caption font-semibold text-ink-faint">{t('desk.bySection')}</h3>
        <ScrollPane className="max-h-[13rem] lg:max-h-none" data-testid="report-sections">
          <div className="flex flex-col gap-1.5">{r.sections.map(section)}</div>
        </ScrollPane>
      </>
    ),
    main: (
      <>
        <h3 className="mb-1 text-t-caption font-semibold text-ink-faint">{t('desk.byPlace')}</h3>
        <ScrollPane className="max-h-[10rem] lg:max-h-none" data-testid="report-places">
          {nothing ? (
            <Note tone="neutral">{t('desk.reportNothing')}</Note>
          ) : (
            <div className="flex flex-col gap-1.5">{r.places.map(place)}</div>
          )}
        </ScrollPane>
        {r.days.length > 0 && (
          <SignedBars
            bars={r.days.map((d) => ({ id: String(d.game_day), value: d.net }))}
            label={t('desk.reportByDay')}
            className="mt-3"
            data-testid="report-bars"
          />
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
