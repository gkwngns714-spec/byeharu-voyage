import { Figure, IconDisc, KEEP_WORDS_CLASS, NeedChip, goodIcon, tileToneClass} from '../../../components/ui'
import type { Move } from '../../../domain/hq'
import { formatDucats, formatDucatsDelta, formatRealShort } from '../../../lib/format'
import { properName, useT } from '../../../lib/i18n'
import { PortFlag } from '../../../live/PortFlag'
import { portNameOf, useWorld } from '../../../live/worldStore'
import { KIND_ICON } from './jobMarks'
import type { MoveData } from './useBoard'

// ONE MOVE AS A CARD (docs/design/hq-command-2026-11-23.md): the activity's glyph on a disc, what it is (whole names, never cut), the
// headline figure (coin, and coin per hour where a time is served), and what it needs as marks: the fleet, the time, the cost, the
// pirate risk. The whole card is the one press.

export function MoveCard({ move, onPress, inline = false }: { move: Move<MoveData>; onPress: (m: MoveData) => void; inline?: boolean }) {
  const t = useT()
  const portByCode = useWorld((s) => s.portByCode)
  const goodByCode = useWorld((s) => s.goodByCode)
  const d = move.data
  const goodName = (code: string) => properName('good', code, goodByCode[code]?.name ?? code)

  const title =
    d.kind === 'trade'
      ? t('hq.tradeTo', { good: goodName(d.sale.good), port: portNameOf(portByCode, d.sale.port ?? '') })
      : d.kind === 'request'
        ? t('hq.fulfil', { good: goodName(d.request.good) })
        : d.kind === 'yard'
          ? t('hq.secondShip')
          : d.kind === 'crew'
            ? t('hq.hireCaptain')
            : t('hq.investIdle')

  const fleet = d.kind === 'trade' || d.kind === 'request' || d.kind === 'crew' ? d.fleet : null
  const headline =
    d.kind === 'yard' ? formatDucats(d.price) : d.kind === 'invest' ? formatDucats(d.idle) : move.gain !== null ? formatDucatsDelta(move.gain) : null
  const tone = d.kind === 'trade' || d.kind === 'request' ? 'success' : 'ink'

  return (
    <button
      type="button"
      onClick={() => onPress(d)}
      className={`grid w-full grid-cols-[auto_minmax(0,1fr)_auto] items-start gap-x-3 gap-y-1.5 rounded-tile p-3 text-left ${tileToneClass(inline)}`}
      data-testid="hq-move"
      data-kind={move.kind}
      data-per-hour={move.perHour === null ? '' : String(Math.round(move.perHour))}
      data-fleet={move.fleet ?? undefined}
      data-good={d.kind === 'trade' ? d.sale.good : undefined}
      data-port={d.kind === 'trade' ? (d.sale.port ?? undefined) : undefined}
    >
      <IconDisc name={KIND_ICON[move.kind]} tone="accent" />
      <span className="flex min-w-0 items-center gap-1.5 self-center">
        {d.kind === 'trade' && d.sale.port && <PortFlag code={d.sale.port} />}
        <span className={`${KEEP_WORDS_CLASS} text-t-body font-medium text-ink`} data-testid="hq-move-title">
          {title}
        </span>
      </span>
      <span className="flex flex-col items-end self-center" data-testid="hq-move-figure">
        {headline !== null && <Figure value={headline} tone={tone} />}
        {move.perHour !== null && (
          <span className="whitespace-nowrap text-t-caption tabular-nums text-success">{t('hq.perHour', { n: formatDucatsDelta(move.perHour) })}</span>
        )}
      </span>
      <span className="col-span-3 flex flex-wrap gap-1.5" data-testid="hq-move-needs">
        {fleet && (
          <NeedChip icon="ship" label={t('hq.fleets')}>
            {fleet.name}
          </NeedChip>
        )}
        {d.kind === 'trade' && (
          <NeedChip icon={goodIcon(d.sale.good, goodByCode[d.sale.good]?.category ?? '')} label={goodName(d.sale.good)}>
            {d.sale.units ?? '—'}
          </NeedChip>
        )}
        {d.kind === 'request' && (
          <NeedChip icon={goodIcon(d.request.good, goodByCode[d.request.good]?.category ?? '')} label={goodName(d.request.good)}>
            {d.units}
          </NeedChip>
        )}
        {move.seconds !== null && <NeedChip icon="history">{formatRealShort(move.seconds * 1000)}</NeedChip>}
        {d.kind === 'trade' && d.sale.cost != null && (
          <NeedChip icon="coin" label={t('hq.cost', { n: formatDucats(d.sale.cost) })}>
            {formatDucats(d.sale.cost)}
          </NeedChip>
        )}
        {d.kind === 'trade' && (
          <NeedChip icon={d.haunt ? 'target' : 'shield'} tone={d.haunt ? 'danger' : 'muted'} label={d.haunt ? t('hq.pirateHaunt') : t('hq.noRisk')} />
        )}
      </span>
    </button>
  )
}
