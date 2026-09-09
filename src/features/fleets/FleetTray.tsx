import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Bar, Button, Figure, Row, Segmented, Tray, type TrayDetent } from '../../components/ui'
import { formatOfTotal } from '../../lib/format'
import { portNameOf, useWorld } from '../../live/worldStore'
import { useShellState } from '../../app/shellState'
import type { FleetView } from '../../lib/rpc'
import { useCommandDraft, type CommandIntent } from '../../domain/order'
import { voyageFraction } from '../../domain/fleet'
import { FleetCargo } from './FleetCargo'
import { FleetShips } from './FleetShips'
import { FleetStores } from './FleetStores'
import { fleetBoundFor, fleetDue } from './fleetLine'
import { keepDays, useStandingOrder } from './standingOrder'

// ONE FLEET, IN A TRAY — the detail that used to be a collapsible card per fleet, open by default,
// stacked under the roster (§2 item 11). Docked to the bottom edge, so opening it moves nothing on
// the list; three faces, because a fleet has three sides and they are not routes.
//
// ── THE ONE BUTTON CHANGES WITH THE FACE ───────────────────────────────────────────────────────
// A tray has one primary action, pinned under the scroll (§6). On SHIPS it is the hand-off this
// tab has always had — "tapping a fleet copies her into the CMD line" — as a structured intent to
// COMMAND. On CARGO there is none: every row IS the act (sell it). On STORES it is the commit of
// the standing order, and it appears only when the stepper differs from what the server holds — a
// primary button that is disabled every time it is first seen is §2 item 1's complaint.

/** The three faces of one fleet. */
type FleetFace = 'ships' | 'cargo' | 'stores'

const FACES = [
  { id: 'ships', label: 'Ships' },
  { id: 'cargo', label: 'Cargo' },
  { id: 'stores', label: 'Stores' },
] as const satisfies readonly { id: FleetFace; label: string }[]

export function FleetTray({ fleet, onClose }: { fleet: FleetView; onClose: () => void }) {
  const [detent, setDetent] = useState<TrayDetent>('half')
  const [face, setFace] = useState<FleetFace>('ships')
  const portByCode = useWorld((s) => s.portByCode)
  const { nowMs } = useShellState()
  const navigate = useNavigate()
  const handOff = useCommandDraft((s) => s.handOff)
  const standing = useStandingOrder(fleet)

  // THE STEPPER'S DRAFT, seated on the served figure. Null means "what the server holds", so a
  // read that lands while the tray is open re-seats the stepper and a committed change needs no
  // effect to clear it: the draft is dropped the moment the server agrees with it.
  const served = standing.order?.days ?? 0
  const [draft, setDraft] = useState<number | null>(null)
  const days = draft ?? served

  // The draft is a structured INTENT (domain/order): the verb and the fleet, the pickers open.
  const command = (intent: CommandIntent) => {
    handOff(intent)
    navigate('/command')
  }
  const commit = () => {
    void standing.keep(days).then((ok) => {
      if (ok) setDraft(null)
    })
  }

  const fraction = voyageFraction(fleet)
  const bound = fleetBoundFor(fleet, (code) => (code ? portNameOf(portByCode, code) : null))

  const action =
    face === 'ships' ? (
      <Button variant="primary" className="w-full" onClick={() => command({ fleetId: fleet.id })}>
        Command {fleet.name}
      </Button>
    ) : face === 'stores' && draft !== null && days !== served ? (
      <Button
        variant="primary"
        className="w-full"
        busy={standing.busy}
        busyLabel="Writing…"
        onClick={commit}
        data-testid="fleet-keep"
      >
        {days === 0 ? 'Lift the order' : `Keep ${keepDays(days)}`}
      </Button>
    ) : undefined

  return (
    <Tray
      detent={detent}
      onDetentChange={(next) => (next === 'closed' ? onClose() : setDetent(next))}
      title={fleet.name}
      action={action}
      data-testid="fleet-tray"
    >
      {/* THE PASSAGE, only while there is one: where she is bound, how far along, and when. The
          ETA is the server's and the position its closed form — nothing here interpolates. */}
      {fleet.voyage && fraction !== null && (
        <Row label={`to ${bound}`} value={fleetDue(fleet, nowMs)} hairline={false} data-testid="fleet-passage">
          <Bar
            pct={fraction * 100}
            tone="info"
            label="how far along the passage"
            figure={
              <Figure value={formatOfTotal(fleet.voyage.nm_done, fleet.voyage.total_nm)} unit="nm" />
            }
            className="mt-1"
          />
        </Row>
      )}

      <Segmented
        label={`${fleet.name} faces`}
        segments={FACES}
        value={face}
        onChange={setFace}
        className="mt-1"
      />

      <div role="tabpanel" className="mt-3">
        {face === 'ships' && <FleetShips fleet={fleet} />}
        {face === 'cargo' && (
          <FleetCargo
            fleet={fleet}
            // A good travels as its CODE: the parser splits on whitespace and a display name like
            // "black pepper" would arrive as two arguments.
            onSell={(code) => command({ verb: 'SELL', fleetId: fleet.id, args: { good: code, qty: 'ALL' } })}
          />
        )}
        {face === 'stores' && (
          <FleetStores fleet={fleet} order={standing.order} book={standing.book} days={days} onDays={setDraft} />
        )}
      </div>
    </Tray>
  )
}
