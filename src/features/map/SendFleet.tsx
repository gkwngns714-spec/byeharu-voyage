import { useState, type ReactNode } from 'react'
import { Button, Hint, Row, SheetSection, Tray, TrayTitle, type TrayDetent } from '../../components/ui'
import { PortFlag } from '../../live/PortFlag'
import { formatVoyageDays } from '../../lib/format'
import { CHART_CHROME, GoToLink } from '../../chart'
import { CityTabs } from './CityTabs'
import { useCityTab } from './cityTab'
import { SendFleetRow } from './SendFleetRow'
import { canGo, type SailDest } from './sendRules'
import { useSendFleet } from './useSendFleet'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE CITY PANEL — a tapped place: its three tabs, and the map's one act, as a panel at the right.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// docs/UI_DIRECTION.md §6, MAP, grown on 2026-10-13 by the owner's two sentences — *"when i press
// city … i want there to be a list, showing the total level, and its current time till the resting
// finishes"* and *"the pop-up page when clicking a ship or a city is not good in terms of
// friendliness and style"* — and on 2026-10-15 by a third:
//
//   *"when i click on a city, i don't want to see stupid useless info. Rather, i want there to be
//    tab, such as market, port, inn."*
//
//     Lisbon                                         [Send fleet]
//     Portugal · 27 merchants · 2 in port
//     [  Market  |   Port   |   Inn   ]
//       Market: the price table (PortPrices) — a press slides the price history out beside
//       Port:   In port · Incoming, yours and the merchants' (CityHarbour)
//       Inn:    the captains here this quarter hour; crew and supplies for a fleet alongside
//     [            Send Gaivota · keep 15 days            ]
//
// A HARBOUR'S BODY IS `CityTabs` (CityTabs.tsx says what each tab composes). A point of OPEN SEA
// has no tabs: it is only somewhere to send a fleet.
//
// THE SEND IS NOT LOST. The owner's flow, step for step (useSendFleet.ts quotes it): tap a place →
// the panel opens with the place's name, one line, and `Send fleet` → press it and her fleets are
// listed with the passage's verdict on each row — at the top of the PORT tab, which the press
// turns to → press one, the keep control unfolds under it → the one pinned button sends her.
// `Send fleet` stands in the title on every tab. Nothing navigates; the chart is still the ground.
//
// THE RULES (useSendFleet.ts carries them): this file composes nothing, judges nothing, and owns
// no grammar. It is the markup of a decision made elsewhere.
//
// `CHART_CHROME` for the two reasons every piece of chrome on this chart carries it: a press here
// never pans, and the label planner keeps a harbour's name from under it.
export function SendFleet({
  dest,
  line,
  harbour,
  onClose,
}: {
  dest: SailDest
  /** The one line under the name — `Portugal · 27 merchants · 2 in port`, `Open sea`. */
  line: ReactNode
  /** The Port tab's ships — in port and incoming (CityHarbour), built by MapScreen, which holds
   *  the harbour's read. Unused at sea. */
  harbour: ReactNode
  onClose: () => void
}) {
  const [detent, setDetent] = useState<TrayDetent>('peek')
  const open = detent !== 'peek'
  const flow = useSendFleet(dest, open)
  const { fleets } = flow
  const turnTo = useCityTab((s) => s.turnTo)

  const picked = fleets.find((f) => f.id === flow.picked) ?? null
  const sendable = picked !== null && canGo(flow.standingOf(picked)) && flow.presets !== null
  // The dead end is named only when the player ARRIVED at it — not in the frame after their own
  // send emptied the list, when her row already says she is under way.
  const nowhere = fleets.length > 0 && !fleets.some((f) => canGo(flow.standingOf(f))) && flow.act?.state !== 'sent'
  const busy = picked !== null && flow.act?.state === 'busy' && flow.act.fleetId === picked.id

  // HER FLEETS, each with the passage's verdict — once `Send fleet` is pressed: at the top of the
  // Port tab for a city, alone for a point of open sea.
  const sendSection = open && (
    <SheetSection heading="Your fleets" data-testid="map-send-fleets">
      {/* WHY THE TRACK WILL NOT TOUCH THE QUAY (0076): the marker leaves the triangle for a point
          up to 67.7 nm out, and a player who was not told reads that as a bug. Said only where a
          passage is being chosen — above the tabs it was the first line of every city (2026-10-15,
          "stupid useless info"). The wording is domain/passage's. */}
      {flow.roads && <Hint data-testid="map-send-roads">{flow.roads}</Hint>}
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
  )

  return (
    <Tray
      mode="side"
      detent={detent}
      onDetentChange={(next) => (next === 'closed' ? onClose() : setDetent(next))}
      title={
        <TrayTitle
          name={
            // 2026-10-18 (the owner): the flag of the nation that holds the city, beside its name.
            <span className="inline-flex max-w-full items-center gap-1.5">
              {dest.kind === 'port' && <PortFlag code={dest.code} size="title" />}
              <GoToLink to={dest.kind === 'port' ? { kind: 'port', code: dest.code } : { kind: 'point', at: dest.at }}>
                {flow.destName}
              </GoToLink>
            </span>
          }
          line={line}
          testId="map-place-name"
          trailing={
            !open && (
              <Button
                variant="primary"
                size="sm"
                onClick={() => {
                  turnTo('port')
                  setDetent('half')
                }}
                data-testid="map-send-fleet"
              >
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
      {dest.kind === 'port' ? (
        <CityTabs
          portCode={dest.code}
          harbour={
            <>
              {sendSection}
              {harbour}
            </>
          }
        />
      ) : (
        sendSection
      )}
    </Tray>
  )
}
