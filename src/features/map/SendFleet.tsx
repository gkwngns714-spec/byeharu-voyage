import { useState } from 'react'
import { Button, Hint, Row, SheetSection, Tray, TrayTitle, type TrayDetent } from '../../components/ui'
import { formatVoyageDays } from '../../lib/format'
import type { PortMerchant } from '../../lib/rpc'
import { CHART_CHROME } from '../../chart'
import { useShellState } from '../../app/shellState'
import { RestingHere } from './RestingHere'
import { SendFleetRow } from './SendFleetRow'
import { canGo, type SailDest } from './sendRules'
import { useSendFleet } from './useSendFleet'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE CITY TRAY — a tapped place: who lies in it, and the map's one act, as a tray from the bottom edge.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// docs/UI_DIRECTION.md §6, MAP, grown on 2026-10-13 by the owner's two sentences — *"when i press
// city … i want there to be a list, showing the total level, and its current time till the resting
// finishes"* and *"the pop-up page when clicking a ship or a city is not good in terms of
// friendliness and style"*:
//
//     peek:  Lisbon                                   [Send fleet]
//            Portugal · 2 resting · 1 laid up
//     half:  In port
//              [⚓] Carreira da Guiné      12        2 h 14 min
//                  Casa de Aveiro · 3 ships   level       Resting
//            Your fleets
//              [⚓] Gaivota · Lisbon · 1.9 days
//                  Keep 15 d  [−] ▔▔▔▔▔▔ [+]
//            [            Send Gaivota · keep 15 days            ]
//
// The owner's flow, step for step (useSendFleet.ts quotes it): tap a place → the tray peeks with
// the place's name, one line, and `Send fleet` → press it and the tray stands at half, her fleets
// listed with the passage's verdict on each row → press one, the keep control unfolds under it →
// the one pinned button sends her. Nothing navigates; the chart is still the ground.
//
// WHAT THE HALF STOP NOW HOLDS FIRST: the merchants lying in the city (RestingHere.tsx), because
// a resting merchant is drawn nowhere else on the chart since the same day. The harbour's own
// read serves them (MapScreen asks it when a city is tapped); a row opens the same read-only
// merchant sheet a hull on the water opens. Then her fleets, under their own heading, so a reader
// who pressed `Send fleet` finds the thing they pressed for named.
//
// THE RULES (useSendFleet.ts carries them): this file composes nothing, judges nothing, and owns
// no grammar. It is the markup of a decision made elsewhere.
//
// `CHART_CHROME` for the two reasons every piece of chrome on this chart carries it: a press here
// never pans, and the label planner keeps a harbour's name from under it.
export function SendFleet({
  dest,
  line,
  merchants,
  onOpenMerchant,
  onClose,
}: {
  dest: SailDest
  /** The one line under the name at peek — `Portugal · 2 resting`, `Open sea`. */
  line: string
  /** The merchants LYING in this city (the harbour's read, filtered by the caller); empty at sea. */
  merchants: readonly PortMerchant[]
  onOpenMerchant: (fleetId: string) => void
  onClose: () => void
}) {
  const [detent, setDetent] = useState<TrayDetent>('peek')
  const open = detent !== 'peek'
  const flow = useSendFleet(dest, open)
  const { fleets } = flow
  // THE ONE CLOCK (src/app/shellState.ts): the rest countdowns tick on it, never on a timer here.
  const { nowMs } = useShellState()

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
        <TrayTitle
          name={flow.destName}
          line={line}
          testId="map-place-name"
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

      {/* WHO LIES HERE — the list the owner asked for, soonest to sail first. In the scroll box
          whether or not the tray is open: at peek it is simply below the fold, a drag away. */}
      <RestingHere rows={merchants} nowMs={nowMs} onOpen={onOpenMerchant} />

      {open && (
        <SheetSection heading="Your fleets" data-testid="map-send-fleets">
          {fleets.length === 0 && (
            <Row tone="muted" hairline={false} label="No fleets yet — start your company to get one." data-testid="map-send-none" />
          )}

          {/* THE DEAD END, NAMED (OWNER_REQUESTS row 49: "i can't send a fleet in map"): a list in
              which nothing can be pressed says so ONCE, at the top, before the player hunts for the
              press. */}
          {nowhere && (
            <Row
              tone="muted"
              label={
                fleets.every((f) => flow.standingOf(f) === 'lies')
                  ? `Nothing to send — ${fleets.length === 1 ? 'it is' : 'they are'} already at ${flow.destName}.`
                  : `Nothing to send — every fleet is at ${flow.destName} or heading there.`
              }
              data-testid="map-send-nowhere"
            />
          )}

          {fleets.map((f) => (
            <SendFleetRow key={f.id} fleet={f} flow={flow} />
          ))}
        </SheetSection>
      )}
    </Tray>
  )
}
