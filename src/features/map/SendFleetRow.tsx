import { Bar, Button, Figure, Icon, Note, Row } from '../../components/ui'
import { formatMiles, formatPriceDelta, formatVoyageDays } from '../../lib/format'
import type { FleetView, PreviewResult, Refusal } from '../../lib/rpc'
import { sailEstimate } from '../../domain/order'
import { whereabouts, whereParts } from '../../domain/fleet'
import { GoToLink, PlaceLine } from '../../chart'
import { portNameOf, useWorld } from '../../live/worldStore'
import { SendInsurance } from './SendInsurance'
import { canGo, type Fix } from './sendRules'
import type { SendFlow } from './useSendFleet'
import { useT } from '../../lib/i18n'

// ONE FLEET ON THE PLACE TRAY — her row, its verdict, and what unfolds under it when pressed.
//
// A row carries its own truth (useSendFleet.ts): her name, where she lies, and the passage's own
// figures from the dry run — or the server's refusal as a `Note`, with the fixes as real presses.
// Pressing the row picks her (and points the app-wide draft at her); under the picked row is the
// keep control. She is never a silently dead entry: a fleet that cannot be sent says why, on her
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
  const passage = pressable && v?.kind === 'ok' ? passageOf(v.result) : null
  // 0241 (owner row 230): her purse is short of this passage's stores — the SAIL still goes, and the rest is owed
  const onCredit = pressable && v?.kind === 'ok' ? (sailEstimate(v.result.estimate).onCredit ?? 0) : 0

  return (
    <div data-testid="map-send-row">
      <Row
        mark={
          <Icon name={sailing ? 'ship' : 'anchor'} size={20} className={on ? 'text-accent' : 'text-ink-faint'} />
        }
        label={<GoToLink to={{ kind: 'fleet', id: f.id, where: whereAt }}>{f.name}</GoToLink>}
        value={passage !== null ? <Figure value={<span data-testid="map-send-passage">{passage}</span>} /> : undefined}
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
      </Row>

      {pressable && v?.kind === 'refused' && (
        <Refused refusal={v.refusal} fixes={flow.fixesOf(f, v.refusal)} testId="map-send-refusal" />
      )}

      {onCredit > 0 && (
        <span className="block pb-1 text-t-caption text-warning" data-testid="map-send-on-credit">
          {t('map.onCredit', { amount: formatPriceDelta(-onCredit) })}
        </span>
      )}

      {on && pressable && <SendInsurance fleet={f} flow={flow} />}

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


/** The two figures a SAIL estimate carries — the SERVER's own sailed miles and voyage-days over
 *  the proposed course, read once for the whole app in `domain/order/estimate.ts`. */
function passageOf(result: PreviewResult): string | null {
  const { nm, days } = sailEstimate(result.estimate)
  if (nm === null && days === null) return null
  return [nm === null ? null : formatMiles(nm), days === null ? null : formatVoyageDays(days)]
    .filter(Boolean)
    .join(' · ')
}
