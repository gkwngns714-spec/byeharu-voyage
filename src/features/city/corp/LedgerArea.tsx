import { Bar, HeldRoom, SheetSection } from '../../../components/ui'
import { openHq } from '../../../app/hqPlace'
import { formatDucatsDelta } from '../../../lib/format'
import { translateMaybe, useLocale, useT, type TKey } from '../../../lib/i18n'
import { worldReport, type HqRate, type Report, type ReportSection } from '../../../lib/rpc'
import { useServedRead } from '../../../live/useServedRead'
import { useWorld } from '../../../live/worldStore'

// THE LEDGER (docs/design/hq-corp-2026-11-24.md B4, C1; slice H1; the join, 2026-11-24): the company's money by line, as bars. NO
// CLIENT DIVISION, and NO NET HERE: HQ's one per-hour figure is the Rank strip's (board/Bridge.tsx), and this area draws what it is
// made of.
//   lines served   0493 (`world.hq_board().rate.lines`, the board's one read, handed in by HqCompany.tsx): her RUNNING lines, each
//                  its served coin an hour, as a bar against the largest of them, plus lines green and minus lines red. A purchase
//                  made once is not an hourly line (the strip's sheet lists them).
//   no lines       a server before 0493: `world.report('day')`, today by section (the Report's own sections and words), each a
//                  served sum. No total: for a young company it is the figure While away has already said.
// A lone line is not drawn (it is the net again): with no line to draw the band says "Nothing yet", on every glass; the Report's
// door stands all the same.
// One press: the Report's sheet (Today / Week / All, by line).
// "Saved" arrives with 0495's `world.company_rate()`.

const SECTION_WORD: Record<ReportSection['id'], TKey> = {
  trade: 'desk.secTrade',
  crew: 'desk.secCrew',
  supplies: 'desk.secSupplies',
  repairs: 'desk.secRepairs',
  insurance: 'desk.secInsurance',
  invest: 'desk.secInvest',
  ships: 'desk.secShips',
  other: 'desk.secOther',
}

interface Line {
  id: string
  word: string
  amount: number
}

/** `asking`: the board's first answer is still on the wire (the rate comes with it), so the area holds the room it had last time (HeldRoom.tsx). */
export function LedgerArea({ rate, asking = false }: { rate: HqRate | null; asking?: boolean }) {
  const t = useT()
  const locale = useLocale()
  // a rate line's word is the dictionary's own entry for its code (`hq.rate<Code>`, the entries RateWhy.tsx reads); a line the server
  // names later reads as Other until it has one
  const lineWord = (code: string) => translateMaybe(locale, 'hq', `rate${code.charAt(0).toUpperCase()}${code.slice(1)}`) ?? t('hq.rateOther')
  const company = useWorld((s) => s.player?.id ?? null)
  const hourly = rate?.lines ?? null
  // today's Report only while the server serves no lines (a second window beside the strip's would say the same money twice)
  const read = useServedRead<Report>(company && rate && !hourly ? 'report:day' : null, () => worldReport('day'))
  const report = read.view
  if (!hourly && !report) return <HeldRoom name="hq-ledger" asking={asking || read.loading} />
  const lines: Line[] = hourly
    ? hourly.filter((l) => !l.one_time && l.per_hour !== 0).map((l) => ({ id: l.line, word: lineWord(l.line), amount: l.per_hour }))
    : (report?.sections ?? []).filter((s) => s.ducats !== 0).map((s) => ({ id: s.id, word: t(SECTION_WORD[s.id]), amount: s.ducats }))
  // ONE LINE IS THE NET AGAIN (the strip's figure, or While away's for a company of one fleet): the lines are drawn from two up
  const drawn = lines.length > 1 ? lines : []
  const top = Math.max(1, ...lines.map((l) => Math.abs(l.amount)))
  return (
    <HeldRoom name="hq-ledger" asking={false}>
    <SheetSection
      heading={t('corp.ledger')}
      trailing={<span className="text-t-caption text-ink-muted">{t(hourly ? 'corp.hourly' : 'corp.today')}</span>}
      data-testid="corp-ledger"
      data-span={hourly ? 'hour' : 'today'}
    >
      <button
        type="button"
        onClick={() => openHq({ sheet: 'report' })}
        className="flex min-h-11 w-full flex-col gap-2 rounded-tile bg-surface p-3 text-left transition hover:bg-surface-2"
        data-testid="corp-ledger-open"
      >
        {drawn.length === 0 && <span className="text-t-caption text-ink-faint">{t('corp.noLines')}</span>}
        {drawn.map((l) => (
          <span key={l.id} className="flex items-center gap-3" data-testid="corp-ledger-line" data-line={l.id}>
            <span className="w-20 shrink-0 text-t-caption text-ink-muted">{l.word}</span>
            <Bar className="min-w-0 flex-1" pct={(Math.abs(l.amount) / top) * 100} tone={l.amount < 0 ? 'danger' : 'success'} label={l.word} />
            <span className="w-24 shrink-0 text-right text-t-caption tabular-nums text-ink">{formatDucatsDelta(l.amount)}</span>
          </span>
        ))}
        <span className="self-end text-t-label text-accent">{t('corp.report')}</span>
      </button>
    </SheetSection>
    </HeldRoom>
  )
}
