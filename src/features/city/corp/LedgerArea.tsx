import { Bar, Figure, SheetSection } from '../../../components/ui'
import { openHq } from '../../../app/hqPlace'
import { formatDucatsDelta } from '../../../lib/format'
import { useT, type TKey } from '../../../lib/i18n'
import { worldReport, type Report, type ReportSection } from '../../../lib/rpc'
import { useHqBoard } from '../../../live/useHqBoard'
import { useServedRead } from '../../../live/useServedRead'
import { useRoleEdits } from '../../../live/useShipRoles'
import { useWorld } from '../../../live/worldStore'

// THE LEDGER (docs/design/hq-corp-2026-11-24.md B4, C1; slice H1): the company's net an hour and today's money by line. Two reads that
// exist, and NO CLIENT DIVISION:
//   the rate    `world.hq_board().rate.per_hour` (0480: her ledger's last 24 hours over 24, worked out by the server). Dark, or not
//               answered: no rate is drawn, never one made here.
//   the lines   `world.report('day')`: today by section (the Report's own sections and words), each a served sum, as a bar against
//               the largest of them, plus lines green and minus lines red; the day's served total heads them.
// One press: the Report's sheet (Today / Week / All, by line).
// The lines by kind an hour (Trade, Land, Wages, Tax, ...) and "Saved" arrive with 0495's `world.company_rate()`.

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

const tone = (n: number) => (n < 0 ? 'danger' : n > 0 ? 'success' : 'muted')

export function LedgerArea() {
  const t = useT()
  const company = useWorld((s) => s.player?.id ?? null)
  const fleets = useWorld((s) => s.fleets)
  // THE BOARD'S OWN QUESTION (board/useBoard.ts), so this is the read the board already asked, never a second one
  const roleEdits = useRoleEdits((s) => s.edits)
  const kept = useWorld((s) => (s.officers ? s.officers.officers.filter((o) => o.hired).length : -1))
  const hq = useHqBoard(company, `${fleets.map((f) => (f.status === 'DOCKED' ? `${f.id}.${f.version}` : f.id)).join(',')}:${roleEdits}:${kept}`).view
  const rate = hq && hq.on && hq.company ? hq.rate : null
  const report = useServedRead<Report>(company ? 'report:day' : null, () => worldReport('day')).view
  if (!rate && !report) return null
  const lines = (report?.sections ?? []).filter((s) => s.ducats !== 0)
  const top = Math.max(1, ...lines.map((s) => Math.abs(s.ducats)))
  return (
    <SheetSection
      heading={t('corp.ledger')}
      trailing={
        rate ? (
          <span data-testid="corp-ledger-rate" data-per-hour={rate.per_hour}>
            <Figure size="figure" tone={tone(rate.per_hour)} value={t('corp.perHour', { n: formatDucatsDelta(rate.per_hour) })} />
          </span>
        ) : undefined
      }
      data-testid="corp-ledger"
    >
      <button
        type="button"
        onClick={() => openHq({ sheet: 'report' })}
        className="flex min-h-11 w-full flex-col gap-2 rounded-tile bg-surface p-3 text-left transition hover:bg-surface-2"
        data-testid="corp-ledger-open"
      >
        {report && (
          <>
            <span className="flex items-baseline justify-between gap-3">
              <span className="text-t-caption text-ink-muted">{t('corp.today')}</span>
              <span data-testid="corp-ledger-today">
                <Figure tone={tone(report.total)} value={formatDucatsDelta(report.total)} />
              </span>
            </span>
            {lines.map((s) => (
              <span key={s.id} className="flex items-center gap-3" data-testid="corp-ledger-line" data-section={s.id}>
                <span className="w-20 shrink-0 text-t-caption text-ink-muted">{t(SECTION_WORD[s.id])}</span>
                <Bar className="min-w-0 flex-1" pct={(Math.abs(s.ducats) / top) * 100} tone={s.ducats < 0 ? 'danger' : 'success'} label={t(SECTION_WORD[s.id])} />
                <span className="w-24 shrink-0 text-right text-t-caption tabular-nums text-ink">{formatDucatsDelta(s.ducats)}</span>
              </span>
            ))}
          </>
        )}
        <span className="self-end text-t-label text-accent">{t('corp.report')}</span>
      </button>
    </SheetSection>
  )
}
