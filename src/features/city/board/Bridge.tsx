import { Countdown, Figure, Icon, NeedChip } from '../../../components/ui'
import { useShellState } from '../../../app/shellState'
import { formatDucats, formatDucatsDelta, formatInt } from '../../../lib/format'
import { properName, useT } from '../../../lib/i18n'
import { ShipPicture } from '../../../live/ShipPicture'
import { FLEET_JOB_TONE, FLEET_JOB_WORD } from './jobMarks'
import type { Board, FleetJob } from './useBoard'

// THE BRIDGE (docs/design/hq-command-2026-11-23.md): the whole state at a glance, as marks. Coin and today's coin per hour; each fleet a
// ship in the tone of her job (blue at sea, gold idle, red stuck); what finishes next, with its clock; and a pirate mark when one is near
// her routes. Each mark's word is its accessible name.

export function Bridge({ board }: { board: Board }) {
  const t = useT()
  const { nowMs } = useShellState()
  const count = (jobs: FleetJob[]) => board.fleets.filter((f) => jobs.includes(f.job)).length
  const next = board.next
  const nextWord = next
    ? next.what === 'shipReady'
      ? t('hq.shipReady', { ship: properName('hull', next.name, next.name) })
      : next.what === 'training'
        ? t('hq.training', { skill: next.name })
        : t(next.what === 'arrives' ? 'hq.arrives' : 'hq.nextLap', { fleet: next.name })
    : null

  return (
    <section aria-label={t('hq.bridge')} className="grid grid-cols-2 gap-3 md:grid-cols-4" data-testid="hq-bridge">
      <div className="flex min-w-0 flex-col gap-1 rounded-tile bg-surface p-3" data-testid="hq-bridge-purse">
        <span className="flex items-center" role="img" aria-label={`${t('hq.purse')} ${board.purse === null ? '—' : formatDucats(board.purse)}`}>
          <Figure value={board.purse === null ? '—' : formatDucats(board.purse)} size="figure" />
        </span>
        <span
          className={`text-t-caption tabular-nums ${board.perHour !== null && board.perHour < 0 ? 'text-danger' : 'text-success'}`}
          title={t(board.served ? 'hq.rateDay' : 'hq.rateToday')}
          data-testid="hq-bridge-rate"
          data-span={board.served ? '24h' : 'today'}
        >
          {board.perHour === null ? '—' : t('hq.perHour', { n: formatDucatsDelta(board.perHour) })}
        </span>
      </div>

      <div className="flex min-w-0 flex-col gap-1.5 rounded-tile bg-surface p-3" data-testid="hq-bridge-fleets">
        <span className="flex flex-wrap gap-1">
          {board.fleets.map((f) => (
            <ShipPicture key={f.fleet.id} code={f.fleet.ships[0]?.class_code} tone={FLEET_JOB_TONE[f.job]} size="mark" label={`${f.fleet.name} · ${t(FLEET_JOB_WORD[f.job])}`} />
          ))}
        </span>
        <span className="flex flex-wrap gap-1.5">
          <NeedChip icon="sailing" tone="info" label={t('hq.atSea')}>
            {formatInt(count(['trip', 'route']))}
          </NeedChip>
          <NeedChip icon="anchor" label={t('hq.inPort')}>
            {formatInt(count(['busy']))}
          </NeedChip>
          <NeedChip icon="ship" tone="accent" label={t('hq.idle')}>
            {formatInt(count(['idle']))}
          </NeedChip>
        </span>
      </div>

      <div className="flex min-w-0 flex-col gap-1 rounded-tile bg-surface p-3" data-testid="hq-bridge-next">
        <span className="flex items-center gap-1.5 text-t-caption text-ink-muted">
          <Icon name="history" size={16} aria-hidden />
          {t('hq.next')}
        </span>
        {next && nextWord ? (
          <>
            <span className="break-words text-t-label text-ink">{nextWord}</span>
            <span className="text-t-body tabular-nums text-info">
              <Countdown untilMs={next.atMs} nowMs={nowMs} />
            </span>
          </>
        ) : (
          <span className="text-t-label text-ink-faint">{t('hq.nothingNext')}</span>
        )}
      </div>

      <div className="flex min-w-0 flex-col gap-1 rounded-tile bg-surface p-3" data-testid="hq-bridge-threat" data-threats={board.threats}>
        <span className={`flex items-center gap-1.5 ${board.threats > 0 ? 'text-danger' : 'text-ink-faint'}`}>
          <Icon name={board.threats > 0 ? 'target' : 'shield'} size={18} aria-label={board.threats > 0 ? t('hq.threat') : t('hq.noRisk')} role="img" />
          <Figure value={formatInt(board.threats)} tone={board.threats > 0 ? 'danger' : 'faint'} />
        </span>
        <span className="text-t-caption text-ink-muted">{board.threats > 0 ? t('hq.threat') : t('hq.noRisk')}</span>
      </div>
    </section>
  )
}
