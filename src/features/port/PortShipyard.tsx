import { useState } from 'react'
import { Figure, Note, Row } from '../../components/ui'
import { StepQuestion } from './StepQuestion'
import { useStepOrder } from './useStepOrder'
import { worstHullFraction } from '../../domain/fleet'
import { formatPct } from '../../lib/format'
import type { FleetView, SnapshotPort } from '../../lib/rpc'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE SHIPYARD — where a hull the sea has taken a toll on is mended (0067: "Repair a hull").
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, 2026-09-09: *"they should be located accordingly at different locations."* REPAIR's
// doorway was a tile on COMMAND's grid; the act happens in a shipyard, so this is the face of that
// building, offered only where one stands (`PORT_FACES`, read off the port's own rows). It is not
// the Yard: 0067's own words are *"the building yard … is not the shipyard, which repairs."*
//
// ONE ROW, ONE TRAY. Her worst hull is the figure a repair is a decision about, so it is the row;
// pressing it opens the same step tray the Inn opens for HIRE (StepQuestion.tsx), with the reading,
// the stepper and the server's own price for the day. Nothing here judges whether she can be
// mended — `cmd.do_repair` does, and the dry run says so before the press.
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
  /** A fleet of yours lying here, or null — a hull is mended alongside. */
  fleet: FleetView | null
}) {
  if (!fleet) {
    return <Note tone="neutral">No fleet of yours lies here, and a hull is mended alongside.</Note>
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
      <Row
        label="Worst hull"
        value={<Figure value={formatPct(worst, 0)} tone={worst < 0.5 ? 'danger' : 'ink'} size="figure" />}
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
