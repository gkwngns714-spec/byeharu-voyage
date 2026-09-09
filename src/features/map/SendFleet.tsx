import { useState } from 'react'
import { Button, Hint, Row, Tray, type TrayDetent } from '../../components/ui'
import { formatVoyageDays } from '../../lib/format'
import type { CommandIntent } from '../../domain/order'
import { CHART_CHROME } from '../../chart'
import { MapTrayTitle } from './MapTrayTitle'
import { SendFleetRow } from './SendFleetRow'
import { canGo, type SailDest } from './sendRules'
import { useSendFleet } from './useSendFleet'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// SEND FLEET — the map's one act, as a tray rising from the bottom edge.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// docs/UI_DIRECTION.md §6, MAP:
//
//     TRAY peek:  Cádiz · Spain · 254 nm    [Send fleet]
//     TRAY half:  Gaivota · Lisbon · 1.9 d · stores ✓
//                 Keep 15 d  [−] ▔▔▔▔▔▔ [+]
//                 [          Send Gaivota          ]
//
// The owner's flow, step for step (useSendFleet.ts quotes it): tap a place → the tray peeks with
// the place's name and `Send fleet` → press it and the tray stands at half, her fleets listed with
// the passage's verdict on each row → press one, the keep control unfolds under it → the one
// pinned button sends her. Nothing navigates; the chart is still the ground. The old panel did
// the same four steps INSIDE a corner card that grew down the glass with every unfold; a tray has
// three stops and the chart above it never moves.
//
// THE RULES (useSendFleet.ts carries them): this file composes nothing, judges nothing, and owns
// no grammar. It is the markup of a decision made elsewhere.
//
// `CHART_CHROME` for the two reasons every piece of chrome on this chart carries it: a press here
// never pans, and the label planner keeps a harbour's name from under it.
export function SendFleet({
  dest,
  line,
  onClose,
  onCompose,
}: {
  dest: SailDest
  /** The one line beside the name at peek — `Spain · Gaivota here`, `Open sea`. */
  line: string
  onClose: () => void
  /** A fix with an argument still to choose hands off to the one composer. The send never calls it. */
  onCompose: (intent: CommandIntent) => void
}) {
  const [detent, setDetent] = useState<TrayDetent>('peek')
  const open = detent !== 'peek'
  const flow = useSendFleet(dest, open, onCompose)
  const { fleets } = flow

  const picked = fleets.find((f) => f.id === flow.picked) ?? null
  const sendable = picked !== null && canGo(flow.standingOf(picked)) && flow.presets !== null
  // The dead end is named only when the player ARRIVED at it — not in the frame after their own
  // send emptied the list, when her row already says she is under way.
  const nowhere = fleets.length > 0 && !fleets.some((f) => canGo(flow.standingOf(f))) && flow.act?.state !== 'sent'
  const busy = picked !== null && flow.act?.state === 'busy' && flow.act.fleetId === picked.id

  return (
    <Tray
      detent={detent}
      onDetentChange={(next) => (next === 'closed' ? onClose() : setDetent(next))}
      title={
        <MapTrayTitle
          name={flow.destName}
          line={line}
          trailing={
            !open && (
              <Button variant="primary" size="sm" onClick={() => setDetent('half')} data-testid="map-send-fleet">
                Send fleet
              </Button>
            )
          }
        />
      }
      action={
        sendable ? (
          <Button
            variant="primary"
            className="w-full"
            busy={busy}
            busyLabel="Sending…"
            onClick={() => flow.send(picked)}
            data-testid="map-send-ratio-send"
          >
            {`Send ${picked.name} · keep ${formatVoyageDays(flow.daysOf(picked), 0)}`}
          </Button>
        ) : undefined
      }
      data-testid="map-detail-tray"
      {...CHART_CHROME}
    >
      {/* WHY THE TRACK WILL NOT TOUCH THE QUAY (0076): the marker leaves the triangle for a point
          up to 67.7 nm out, and a player who was not told reads that as a bug. The one hint this
          tray spends its budget on; the wording is domain/passage's. */}
      {flow.roads && <Hint data-testid="map-send-roads">{flow.roads}</Hint>}

      {open && fleets.length === 0 && (
        <Row tone="muted" hairline={false} label="No fleets yet — a house founds one before it can sail." data-testid="map-send-none" />
      )}

      {/* THE DEAD END, NAMED (OWNER_REQUESTS row 49: "i can't send a fleet in map"): a list in which
          nothing can be pressed says so ONCE, at the top, before the player hunts for the press. */}
      {open && nowhere && (
        <Row
          tone="muted"
          label={
            fleets.every((f) => flow.standingOf(f) === 'lies')
              ? `Nothing to send — ${fleets.length === 1 ? 'she is' : 'they are'} already at ${flow.destName}.`
              : `Nothing to send — every fleet is at ${flow.destName} or bound for it.`
          }
          data-testid="map-send-nowhere"
        />
      )}

      {open && fleets.length > 0 && (
        <div data-testid="map-send-fleets">
          {fleets.map((f) => (
            <SendFleetRow key={f.id} fleet={f} flow={flow} />
          ))}
        </div>
      )}
    </Tray>
  )
}
