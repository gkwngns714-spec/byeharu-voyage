import { Bar, Button, Figure, Icon, Note, Row } from '../../components/ui'
import { formatDaysReal, formatPriceDelta } from '../../lib/format'
import type { FleetView, Refusal } from '../../lib/rpc'
import { sailEstimate } from '../../domain/order'
import { whereabouts, whereParts } from '../../domain/fleet'
import { GoToLink, PlaceLine } from '../../chart'
import { portNameOf, useWorld } from '../../live/worldStore'
import { SendInsurance } from './SendInsurance'
import { RaidOrder } from '../../live/RaidOrder'
import { canGo, type Fix } from './sendRules'
import type { SendFlow } from './useSendFleet'
import { useT } from '../../lib/i18n'

// ONE FLEET ON THE PLACE TRAY — her row, its verdict, and what unfolds under it when pressed.
//
// A row carries its own truth (useSendFleet.ts): her name, where she lies, and the passage's own
// figures from the dry run — or the server's refusal as a `Note`, with the fixes as real presses.
// Pressing the row picks her (and points the app-wide draft at her); under the picked row is the
// keep control.
//
// THE FINAL ANSWER, AND ONLY THAT (the owner, 2026-11-13: *"just tell me the final time, price reaching the
// destination"*): the row's figure is the whole trip's days with the real wait beside them, and under it what its
// supplies cost. A far city reached through harbours between reads the same two figures for the whole chain, with
// the harbours named on one small line (`via A, B`); they ask for no press. Both are the server's figures
// (useSendFleet.ts), added up by the one passage planner (domain/passage/chain.ts).
//
// She is never a silently dead entry: a fleet that cannot be sent says why, on her
// row, as a note instead of a press.

export function SendFleetRow({ fleet: f, flow }: { fleet: FleetView; flow: SendFlow }) {
  const t = useT()
  const portByCode = useWorld((s) => s.portByCode)
  const standing = flow.standingOf(f)
  const pressable = canGo(standing)
  const on = flow.picked === f.id
  const v = flow.verdicts[f.id]
  const acted = flow.act?.fleetId === f.id ? flow.act : null
  // At sea or not is `domain/fleet`'s one rule; the mark and the line both read it, never `f.voyage`.
  const whereAt = whereabouts(f)
  const sailing = whereAt.kind === 'sailing'
  const where = <PlaceLine parts={whereParts(whereAt, (c) => portNameOf(portByCode, c))} />

  const line = !pressable
    ? standing === 'lies'
      ? t('map.dockedHere')
      : acted?.state === 'sent'
        ? t('map.underWay', { dest: flow.destName })
        : t('map.alreadyHeading')
    : sailing
      ? t('map.atSeaTurns')
      : v === undefined
        ? <>{where} · {t('map.checkingRoute')}</>
        : where
  const plan = pressable ? flow.planOf(f) : null
  const name = (code: string | null) => (code === null ? '' : portNameOf(portByCode, code))
  // the whole trip's days: the dry run's own for one leg, the planner's sum for a chain
  const days = !pressable ? null : v?.kind === 'ok' ? sailEstimate(v.result.estimate).days : v?.kind === 'chain' ? v.plan.days : null
  const sails = pressable && (v?.kind === 'ok' || v?.kind === 'chain')
  const cost = sails && plan?.kind === 'open' ? plan.cost : null
  const via = pressable && v?.kind === 'chain' ? v.plan.stops : null
  // 0241 (owner row 230): her purse is short of this passage's stores — the SAIL still goes, and the rest is owed
  const first = !pressable ? null : v?.kind === 'ok' ? v.result : v?.kind === 'chain' ? v.first : null
  const onCredit = first ? (sailEstimate(first.estimate).onCredit ?? 0) : 0
  // NO CHAIN OPENS IT: the plain reason beside the server's sentence
  const noWay =
    pressable && v?.kind === 'refused' && plan?.kind === 'shut'
      ? plan.noStops
        ? t('map.sendNoStops')
        : plan.from !== null && plan.refusal
          ? t('map.sendLegShut', { from: name(plan.from), to: name(plan.to) })
          : null
      : null

  return (
    <div data-testid="map-send-row">
      <Row
        mark={
          <Icon name={sailing ? 'ship' : 'anchor'} size={20} className={on ? 'text-accent' : 'text-ink-faint'} />
        }
        label={<GoToLink to={{ kind: 'fleet', id: f.id, where: whereAt }}>{f.name}</GoToLink>}
        value={days !== null ? <Figure value={<span data-testid="map-send-passage">{formatDaysReal(days)}</span>} /> : undefined}
        tone={on ? 'accent' : pressable ? 'default' : 'muted'}
        hairline={!on}
        onClick={pressable ? () => flow.pick(f) : undefined}
        data-testid={pressable ? 'map-send-row-head' : 'map-send-row-still'}
      >
        <span
          className="block text-t-caption text-ink-faint"
          data-testid={pressable ? (v === undefined && f.voyage == null ? 'map-send-checking' : undefined) : 'map-send-row-note'}
        >
          {line}
        </span>
        {via !== null && (
          <span className="block text-t-caption text-ink-muted" data-testid="map-send-via" data-stops={via.join(' ')}>
            {t('map.sendVia', { stops: via.map(name).join(', ') })}
          </span>
        )}
        {cost !== null && (
          <span className="block text-t-caption text-ink-muted" data-testid="map-send-cost">
            {t('map.sendSupplies', { amount: cost > 0 ? formatPriceDelta(-cost) : formatPriceDelta(0) })}
          </span>
        )}
      </Row>

      {pressable && v?.kind === 'refused' && (
        <Refused refusal={v.refusal} fixes={flow.fixesOf(f, v.refusal)} testId="map-send-refusal" />
      )}
      {noWay !== null && (
        <span className="block pb-2 text-t-caption text-warning" data-testid="map-send-no-way">
          {noWay}
        </span>
      )}

      {onCredit > 0 && (
        <span className="block pb-1 text-t-caption text-warning" data-testid="map-send-on-credit">
          {t('map.onCredit', { amount: formatPriceDelta(-onCredit) })}
        </span>
      )}

      {on && pressable && <SendInsurance fleet={f} flow={flow} />}
      {/* 0353: her standing order when raiders close, chosen where the passage is chosen. Draws nothing while orders are dark. */}
      {on && pressable && <RaidOrder fleetId={f.id} />}

      {acted?.state === 'busy' && (
        <Note tone="neutral" data-testid="map-send-busy">
          {t('map.issuing')}
        </Note>
      )}
      {/* A SENT fleet says so on her own row (`line`, above): the world flips her to `bound` on
          the read-back that follows the send, and the row's second line is where "Under way" is
          printed. Driven 2026-09-09: a second Note under the row said the same sentence twice. */}
      {acted?.state === 'refused' && acted.refusal && (
        <Refused refusal={acted.refusal} fixes={flow.fixesOf(f, acted.refusal)} testId="map-send-issue-refusal" />
      )}
      {/* A REFUSAL THE SERVER DID NOT NAME still has to say she did not sail (row 49's silence). */}
      {acted?.state === 'refused' && !acted.refusal && (
        <Note tone="warning" data-testid="map-send-silent">
          {t('map.silent')}
        </Note>
      )}
    </div>
  )
}

/** The refusal form §5 names: the sentence, have against need as a `Bar` when the server serves
 *  figures, and the fixes as presses. The code goes to console.debug, never to the screen. */
function Refused({ refusal, fixes, testId }: { refusal: Refusal; fixes: Fix[]; testId: string }) {
  const t = useT()
  const figures = refusal.figures
  return (
    <div className="py-2">
      <Note
        tone="danger"
        code={refusal.code} figures={refusal.figures}
        data-testid={testId}
        figure={
          figures ? (
            <Bar
              pct={figures.need > 0 ? (figures.have / figures.need) * 100 : 0}
              tone="danger"
              label={t('map.haveNeed', { unit: figures.unit })}
              figure={<Figure value={`${figures.have} / ${figures.need}`} unit={figures.unit} />}
            />
          ) : undefined
        }
      >
        {refusal.sentence}
      </Note>
      {fixes.length > 0 && (
        <div className="mt-2 flex flex-wrap gap-2">
          {fixes.map((fix) => (
            <Button key={fix.label} variant="secondary" size="sm" onClick={fix.run}>
              {fix.label}
            </Button>
          ))}
        </div>
      )}
    </div>
  )
}
