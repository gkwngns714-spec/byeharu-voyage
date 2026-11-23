import { Figure, IconDisc, KEEP_WORDS_CLASS, NeedChip, Note, goodIcon, tileToneClass, type NeedTone } from '../../../components/ui'
import type { Move } from '../../../domain/hq'
import { formatDucats, formatDucatsDelta, formatInt, formatRealShort } from '../../../lib/format'
import type { HqMove, HqRisk } from '../../../lib/rpc'
import { properName, useT } from '../../../lib/i18n'
import { PortFlag } from '../../../live/PortFlag'
import { portNameOf, useWorld } from '../../../live/worldStore'
import { KIND_ICON } from './jobMarks'
import { useServedPress } from './servedPress'
import type { MoveData } from './useBoard'

// ONE MOVE AS A CARD (docs/design/hq-command-2026-11-23.md): the activity's glyph on a disc, what it is (whole names, never cut), the
// headline figure (coin, and coin per hour where a time is served), and what it needs as marks: the fleet, the time, the cost, the
// pirate risk. The whole card is the one press.
// 0480 (lit): a served move draws the same card from the server's figures; its RISK is a mark — a shield in the tone of the waters'
// danger, or the pirate in the danger tone when a bounty pirate's home or sea is on the passage — and a refusal of its act stands under
// it in the server's own words (servedPress.ts), the card kept.

/** A served risk as one mark: the pirate (danger) with a bounty on the way; else a shield, its tone the waters' danger level. */
function riskMark(r: HqRisk): { icon: 'pirate' | 'shield'; tone: NeedTone } {
  if (r.bounty !== null) return { icon: 'pirate', tone: 'danger' }
  return { icon: 'shield', tone: r.danger >= 4 ? 'danger' : r.danger === 3 ? 'warning' : 'muted' }
}

export function MoveCard({ move, onPress, inline = false }: { move: Move<MoveData>; onPress: (m: MoveData) => void; inline?: boolean }) {
  const t = useT()
  const portByCode = useWorld((s) => s.portByCode)
  const goodByCode = useWorld((s) => s.goodByCode)
  const refusal = useServedPress((s) => s.refused[move.id] ?? null)
  const pending = useServedPress((s) => s.pending === move.id)
  const d = move.data
  const goodName = (code: string) => properName('good', code, goodByCode[code]?.name ?? code)
  const s: HqMove | null = d.kind === 'served' ? d.move : null

  const title = s
    ? servedTitle(s)
    : d.kind === 'trade'
      ? t('hq.tradeTo', { good: goodName(d.sale.good), port: portNameOf(portByCode, d.sale.port ?? '') })
      : d.kind === 'request'
        ? t('hq.fulfil', { good: goodName(d.request.good) })
        : d.kind === 'yard'
          ? t('hq.secondShip')
          : d.kind === 'crew'
            ? t('hq.hireCaptain')
            : t('hq.investIdle')

  function servedTitle(m: HqMove): string {
    switch (m.kind) {
      case 'trade':
        return t('hq.tradeTo', { good: goodName(m.needs.good ?? ''), port: portNameOf(portByCode, m.needs.to ?? '') })
      case 'request':
        return t('hq.fulfil', { good: goodName(m.needs.good ?? '') })
      case 'yard':
        return t('hq.secondShip')
      case 'land':
        return t('hq.collect', { good: goodName(m.needs.good ?? '') })
      case 'crew':
        return t('hq.hireCaptain')
      case 'invest':
        return t('hq.investIdle')
    }
  }

  const fleetName = s ? (s.fleet_name ?? null) : d.kind === 'trade' || d.kind === 'request' || d.kind === 'crew' ? d.fleet.name : null
  const headline = s
    ? s.kind === 'yard'
      ? formatDucats(s.needs.cost ?? 0)
      : s.profit !== null
        ? formatDucatsDelta(s.profit)
        : s.kind === 'crew' && s.needs.wage !== undefined
          ? formatDucats(s.needs.wage)
          : null
    : d.kind === 'yard'
      ? formatDucats(d.price)
      : d.kind === 'invest'
        ? formatDucats(d.idle)
        : move.gain !== null
          ? formatDucatsDelta(move.gain)
          : null
  const tone = move.kind === 'trade' || move.kind === 'request' || (s?.kind === 'invest' && s.profit !== null) ? 'success' : 'ink'
  // what is moved: the good and its units (a trade, a request, Land's goods)
  const goods: { code: string; units: number | null } | null = s
    ? s.needs.good
      ? { code: s.needs.good, units: s.needs.units ?? null }
      : null
    : d.kind === 'trade'
      ? { code: d.sale.good, units: d.sale.units ?? null }
      : d.kind === 'request'
        ? { code: d.request.good, units: d.units }
        : null
  const cost = s ? (s.kind === 'trade' || s.kind === 'invest' ? (s.needs.cost ?? null) : null) : d.kind === 'trade' ? (d.sale.cost ?? null) : null
  const flag = s ? (s.kind === 'trade' ? (s.needs.to ?? null) : null) : d.kind === 'trade' ? d.sale.port : null
  const risk = s ? (s.kind === 'trade' && s.risk ? riskMark(s.risk) : null) : null
  const good = s ? (s.kind === 'trade' ? s.needs.good : undefined) : d.kind === 'trade' ? d.sale.good : undefined

  return (
    <div className="flex min-w-0 flex-col gap-1">
      <button
        type="button"
        onClick={() => onPress(d)}
        disabled={pending}
        aria-busy={pending || undefined}
        className={`grid w-full grid-cols-[auto_minmax(0,1fr)_auto] items-start gap-x-3 gap-y-1.5 rounded-tile p-3 text-left disabled:opacity-60 ${tileToneClass(inline)}`}
        data-testid="hq-move"
        data-kind={move.kind}
        data-served={s ? 'true' : undefined}
        data-act={s ? s.act.rpc : undefined}
        data-per-hour={move.perHour === null ? '' : String(Math.round(move.perHour))}
        data-fleet={move.fleet ?? undefined}
        data-good={good}
        data-port={flag ?? undefined}
        data-danger={s?.risk ? String(s.risk.danger) : undefined}
      >
        <IconDisc name={KIND_ICON[move.kind]} tone="accent" />
        <span className="flex min-w-0 items-center gap-1.5 self-center">
          {flag && <PortFlag code={flag} />}
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
          {fleetName && (
            <NeedChip icon="ship" label={t('hq.fleets')}>
              {fleetName}
            </NeedChip>
          )}
          {goods && (
            <NeedChip icon={goodIcon(goods.code, goodByCode[goods.code]?.category ?? '')} label={goodName(goods.code)}>
              {goods.units === null ? '—' : formatInt(goods.units)}
            </NeedChip>
          )}
          {move.seconds !== null && <NeedChip icon="history">{formatRealShort(move.seconds * 1000)}</NeedChip>}
          {cost !== null && (
            <NeedChip icon="coin" label={t('hq.cost', { n: formatDucats(cost) })}>
              {formatDucats(cost)}
            </NeedChip>
          )}
          {!s && d.kind === 'trade' && (
            <NeedChip icon={d.haunt ? 'target' : 'shield'} tone={d.haunt ? 'danger' : 'muted'} label={d.haunt ? t('hq.pirateHaunt') : t('hq.noRisk')} />
          )}
          {s?.risk && risk && (
            <span data-testid="hq-move-risk" data-risk={risk.icon} className="inline-flex">
              <NeedChip
                icon={risk.icon}
                tone={risk.tone}
                label={s.risk.bounty !== null ? `${s.risk.pirate ?? t('hq.pirateHaunt')} · ${t('hq.bounty', { n: formatDucats(s.risk.bounty) })}` : t('hq.danger', { n: s.risk.danger })}
              >
                {s.risk.bounty !== null ? formatDucats(s.risk.bounty) : s.risk.danger}
              </NeedChip>
            </span>
          )}
        </span>
      </button>
      {refusal && (
        <Note tone="danger" code={refusal.code} figures={refusal.figures} sea={refusal.sea} data-testid="hq-move-refusal">
          {refusal.sentence}
        </Note>
      )}
    </div>
  )
}
