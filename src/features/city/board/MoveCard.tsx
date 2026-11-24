import { Figure, IconDisc, KEEP_WORDS_CLASS, NeedChip, Note, goodIcon, tileToneClass, type NeedTone } from '../../../components/ui'
import type { Move } from '../../../domain/hq'
import { formatDucats, formatDucatsDelta, formatInt, formatRealShort } from '../../../lib/format'
import type { FleetJobParams, FleetJobRow, HqMove, HqRace, HqRisk, ShipRole, ShipRoleWhy } from '../../../lib/rpc'
import { properName, useT } from '../../../lib/i18n'
import { PortFlag } from '../../../live/PortFlag'
import { portNameOf, useWorld } from '../../../live/worldStore'
import { RepeatChip } from './JobControl'
import { KIND_ICON, ROLE_ICON, ROLE_WORD } from './jobMarks'
import { pressServed, useServedPress } from './servedPress'
import type { MoveData } from './useBoard'

// ONE MOVE AS A CARD (docs/design/hq-command-2026-11-23.md): the activity's glyph on a disc, what it is (whole names, never cut), the
// headline figure (coin, and coin per hour where the server serves one), and what it needs as marks: the fleet, the time, the cost, the
// pirate risk. The whole card is the one press.
// EVERY CARD IS A SERVED MOVE (0480; H2, docs/design/hq-corp-2026-11-24.md: the client-made cards are deleted). Its figures are the
// server's; its RISK is a mark — a shield in the tone of the waters' danger, or the pirate in the danger tone when a bounty pirate's
// home or sea is on the passage — and a refusal of its act stands under it in the server's own words (servedPress.ts), the card kept.

/** A served risk as one mark: the pirate (danger) with a bounty on the way; else a shield, its tone the waters' danger level. */
function riskMark(r: HqRisk): { icon: 'pirate' | 'shield'; tone: NeedTone } {
  if (r.bounty !== null) return { icon: 'pirate', tone: 'danger' }
  return { icon: 'shield', tone: r.danger >= 4 ? 'danger' : r.danger === 3 ? 'warning' : 'muted' }
}

/** 0484: an Influence chip's tone and word by who leads that city this week: hers green, a rival's amber (a race to win), nobody muted. */
const RACE_TONE: Record<HqRace['lead'], NeedTone> = { mine: 'success', rival: 'warning', open: 'muted' }
const RACE_WORD = { mine: 'hq.raceMine', rival: 'hq.raceRival', open: 'hq.raceOpen' } as const

/** 0485: why a role is the pick, as its chip's word. */
const WHY_WORD: Record<ShipRoleWhy, 'hq.whyRaids' | 'hq.whyJobs' | 'hq.whyRoutes'> = { raids: 'hq.whyRaids', jobs: 'hq.whyJobs', routes: 'hq.whyRoutes' }

/** 0485: what a role gives, as its chip's figure and word: the guard's weight (pirates strike only within reach ÷ it), a share in %. */
function gainOf(role: ShipRole, gain: number): { fig: string; key: 'hq.gainGuard' | 'hq.gainFast' | 'hq.gainHold'; n: number } {
  if (role === 'guard') return { fig: `÷${formatInt(gain)}`, key: 'hq.gainGuard', n: gain }
  const pct = Math.round(gain * 100)
  return { fig: `+${formatInt(pct)}%`, key: role === 'fast' ? 'hq.gainFast' : 'hq.gainHold', n: pct }
}

/** 0481: a trade card's trip as a fixed route (her fleet; buy where she lies, sell there, the passage's stops), or null: not a trade, or
 *  she sells her own cargo (no harbour to buy at). */
function repeatOf(m: HqMove): { fleet: string; params: Required<Pick<FleetJobParams, 'good' | 'buy' | 'sell'>> & FleetJobParams } | null {
  const a = m.act
  if (a.rpc !== 'cmd.issue_lines' || a.args.plan.buy_at === null) return null
  return { fleet: a.args.fleet, params: { good: a.args.plan.good, buy: a.args.plan.buy_at, sell: a.args.plan.sell_at, stops: a.args.plan.stops } }
}

export function MoveCard({
  move,
  onPress,
  inline = false,
  jobs = null,
}: {
  move: Move<MoveData>
  onPress: (m: MoveData) => void
  inline?: boolean
  /** 0481: her fleets' standing jobs, by fleet (lit); a trade card then offers Repeat. Null while dark. */
  jobs?: ReadonlyMap<string, FleetJobRow> | null
}) {
  const t = useT()
  const portByCode = useWorld((s) => s.portByCode)
  const goodByCode = useWorld((s) => s.goodByCode)
  const refusal = useServedPress((s) => s.refused[move.id] ?? null)
  const pending = useServedPress((s) => s.pending === move.id)
  const d = move.data
  const goodName = (code: string) => properName('good', code, goodByCode[code]?.name ?? code)
  // a card is a served move; no other shape is built (useBoard.ts)
  if (d.kind !== 'served') return null
  const s = d.move

  function servedTitle(m: HqMove): string {
    switch (m.kind) {
      case 'trade':
        return t('hq.tradeTo', { good: goodName(m.needs.good ?? ''), port: portNameOf(portByCode, m.needs.to ?? '') })
      case 'request':
        return t('hq.fulfil', { good: goodName(m.needs.good ?? '') })
      case 'yard':
        // 0485 (lit): past the second hull, the yard's card is the next ship's, and names her role
        return m.role ? t('hq.nextShip') : t('hq.secondShip')
      case 'role':
        return t('hq.roleOf', { role: t(ROLE_WORD[m.needs.role ?? 'guard']), ship: m.needs.ship_name ?? '' })
      case 'land':
        return t('hq.collect', { good: goodName(m.needs.good ?? '') })
      case 'crew':
        return t('hq.hireCaptain')
      case 'invest':
        return t('hq.investIdle')
      case 'contract':
        return m.act.rpc === 'cmd.deliver_contract'
          ? t('hq.deliver', { good: goodName(m.needs.good ?? '') })
          : t('hq.carry', { good: goodName(m.needs.good ?? ''), port: portNameOf(portByCode, m.needs.to ?? '') })
    }
  }

  const title = servedTitle(s)
  const fleetName = s.fleet_name ?? null
  const headline =
    s.kind === 'yard'
      ? formatDucats(s.needs.cost ?? 0)
      : s.profit !== null
        ? formatDucatsDelta(s.profit)
        : s.kind === 'crew' && s.needs.wage !== undefined
          ? formatDucats(s.needs.wage)
          : null
  const tone = move.kind === 'trade' || move.kind === 'request' || move.kind === 'contract' || (s.kind === 'invest' && s.profit !== null) ? 'success' : 'ink'
  // what is moved: the good and its units (a trade, a request, Land's goods)
  const goods: { code: string; units: number | null } | null = s.needs.good ? { code: s.needs.good, units: s.needs.units ?? null } : null
  const cost = s.kind === 'trade' || s.kind === 'invest' ? (s.needs.cost ?? null) : null
  const flag = s.kind === 'trade' || s.kind === 'contract' ? (s.needs.to ?? null) : null
  const risk = (s.kind === 'trade' || s.kind === 'contract') && s.risk ? riskMark(s.risk) : null
  // 0483: a contract to take loads at its harbour A (a chip when she lies elsewhere) and holds her collateral
  const loadAt = s.kind === 'contract' && s.act.rpc === 'cmd.take_contract' && s.needs.from && s.needs.from !== s.at ? s.needs.from : null
  const collateral = s.kind === 'contract' ? (s.needs.collateral ?? null) : null
  // 0484: what it adds for her country's weekly race (a trade or request in a contested city), in the tone of who leads there
  const race = s.race && s.race.points > 0 ? s.race : null
  const good = s.kind === 'trade' ? s.needs.good : undefined
  // 0485: a role card's role, why it is the pick and what it gives; the yard's card, the role the next hull should fill
  const roleCard = s.kind === 'role' && s.needs.role ? { role: s.needs.role, why: s.needs.why ?? null, n: s.needs.n ?? 0, gain: gainOf(s.needs.role, s.needs.gain ?? 0) } : null
  const nextRole = s.kind === 'yard' ? (s.role ?? null) : null
  const repeat = jobs ? repeatOf(s) : null
  const held = repeat ? (jobs?.get(repeat.fleet) ?? null) : null

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
        data-served="true"
        data-act={s.act.rpc}
        data-per-hour={move.perHour === null ? '' : String(Math.round(move.perHour))}
        data-fleet={move.fleet ?? undefined}
        data-good={good}
        data-port={flag ?? undefined}
        data-danger={s.risk ? String(s.risk.danger) : undefined}
        data-race={race ? race.lead : undefined}
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
          {loadAt && (
            <NeedChip icon="anchor" label={t('hq.loadAt', { port: portNameOf(portByCode, loadAt) })}>
              <span className="inline-flex items-center gap-1" data-testid="hq-move-load">
                <PortFlag code={loadAt} />
                {portNameOf(portByCode, loadAt)}
              </span>
            </NeedChip>
          )}
          {collateral !== null && collateral > 0 && (
            <span data-testid="hq-move-collateral" className="inline-flex">
              <NeedChip icon="pact" tone="warning" label={t('hq.collateral', { n: formatDucats(collateral) })}>
                {formatDucats(collateral)}
              </NeedChip>
            </span>
          )}
          {roleCard && (
            <span data-testid="hq-move-role" data-role={roleCard.role} className="inline-flex flex-wrap gap-1.5">
              <NeedChip icon={ROLE_ICON[roleCard.role]} tone="success" label={t(roleCard.gain.key, { n: roleCard.gain.n })}>
                {roleCard.gain.fig}
              </NeedChip>
              {roleCard.why && roleCard.n > 0 && <NeedChip icon="report" label={t(WHY_WORD[roleCard.why], { n: roleCard.n })}>{formatInt(roleCard.n)}</NeedChip>}
            </span>
          )}
          {nextRole && (
            <span data-testid="hq-move-next-role" data-role={nextRole} className="inline-flex">
              <NeedChip icon={ROLE_ICON[nextRole]} tone="accent" label={t('hq.roleNext', { role: t(ROLE_WORD[nextRole]) })}>
                {t(ROLE_WORD[nextRole])}
              </NeedChip>
            </span>
          )}
          {race && (
            <span data-testid="hq-move-race" data-lead={race.lead} className="inline-flex">
              <NeedChip
                icon="banner"
                tone={RACE_TONE[race.lead]}
                label={`${t('hq.influenceAdds', { n: formatInt(race.points) })} · ${t(RACE_WORD[race.lead])}`}
              >
                +{formatInt(race.points)}
              </NeedChip>
            </span>
          )}
          {s.risk && risk && (
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
      {repeat && (
        <RepeatChip
          id={move.id}
          fleet={repeat.fleet}
          params={repeat.params}
          on={held?.kind === 'fixed' && held.params.good === repeat.params.good && held.params.buy === repeat.params.buy && held.params.sell === repeat.params.sell}
          send={async () => {
            await pressServed(s, d.fleet)
            return !useServedPress.getState().refused[move.id]
          }}
        />
      )}
      {refusal && (
        <Note tone="danger" code={refusal.code} figures={refusal.figures} sea={refusal.sea} data-testid="hq-move-refusal">
          {refusal.sentence}
        </Note>
      )}
    </div>
  )
}
