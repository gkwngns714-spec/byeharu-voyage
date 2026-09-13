import { useState } from 'react'
import { Figure, Note, Row } from '../../components/ui'
import { StepQuestion } from './StepQuestion'
import { useStepOrder } from './useStepOrder'
import { worstHullFraction } from '../../domain/fleet'
import { formatPct } from '../../lib/format'
import type { FleetView, SnapshotPort } from '../../lib/rpc'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// REPAIR — the face of the building 0067 calls a shipyard, named for the ACT (owner row 86).
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, 2026-09-09: *"they should be located accordingly at different locations."* REPAIR's
// doorway was a tile on COMMAND's grid; the act happens in the repairing building, so this is the
// face of that building, offered only where one stands (`PORT_FACES`, read off the port's own
// rows). It is not the Build face: 0067's own words are *"the building yard … is not the
// shipyard, which repairs."*
//
// The owner, 2026-09-13: *"wtf is shipyard and hull (worst ship)? use easy words."* The tab says
// `Repair` (portView.ts — the id stays `shipyard`, it is the served kind) and the row says
// `Damage`, with the figure as what the worst ship has TAKEN. The step tray's own words for the
// verb live in StepQuestion.tsx, beside the Inn's.
//
// ONE ROW, ONE TRAY. The worst ship's damage is the figure a repair is a decision about, so it is
// the row; pressing it opens the same step tray the Inn opens for HIRE (StepQuestion.tsx), with
// the reading, the stepper and the server's own price for the day. Nothing here judges whether
// a ship can be repaired — `cmd.do_repair` does, and the dry run says so before the press.
//
// FIT and UNFIT are served (0074) and belong on this face too — a fitting goes on and comes off
// alongside, and the shipwright is who does it. They are not drawn yet because no read serves
// "the fittings this house keeps in THIS city" outside `world.workstation` (which stands only
// where a workstation does); that read is the next slice's, and it is a migration.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

export function PortShipyard({
  port,
  fleet,
}: {
  port: SnapshotPort
  /** A fleet of yours docked here, or null — a ship is repaired in port. */
  fleet: FleetView | null
}) {
  if (!fleet) {
    return <Note tone="neutral">None of your fleets are here. Ships are repaired in port.</Note>
  }
  return <Repair port={port} fleet={fleet} />
}

/** Split so the hook never runs for a yard with nobody alongside. */
function Repair({ port, fleet }: { port: SnapshotPort; fleet: FleetView }) {
  const [open, setOpen] = useState(false)
  const step = useStepOrder(fleet, 'REPAIR', open, () => setOpen(false))
  const worst = worstHullFraction(fleet)

  return (
    <div data-testid="port-shipyard">
      {/* DAMAGE, not "Hull (worst ship)" — owner row 86. The figure is what the sea has TAKEN from
          the worst ship, printed as `1 − worst hull fraction`: a formatting of the served hull,
          not a rule. `13% damaged` is a reading; `87%` was a quiz. */}
      <Row
        label="Damage"
        value={
          <Figure value={formatPct(1 - worst, 0)} unit="damaged" tone={worst < 0.5 ? 'danger' : 'ink'} size="figure" />
        }
        chevron
        onClick={() => setOpen(true)}
        hairline={false}
        data-testid="shipyard-repair"
      />
      {open && (
        <StepQuestion
          fleet={fleet}
          port={port}
          step={step}
          onClose={() => {
            setOpen(false)
            step.reset()
          }}
        />
      )}
    </div>
  )
}
