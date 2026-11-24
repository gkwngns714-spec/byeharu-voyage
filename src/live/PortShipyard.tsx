import { useState, type ReactNode } from 'react'
import { Figure, Note, Row } from '../components/ui'
import { StepQuestion } from './StepQuestion'
import { useStepOrder } from './useStepOrder'
import { worstHullFraction, wornFittings } from '../domain/fleet'
import { formatInt, formatPct } from '../lib/format'
import type { FleetView, Refusal, SnapshotPort } from '../lib/rpc'
import { useT } from '../lib/i18n'

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

/** A whole repair: the grammar's own default, said out loud so the line is the one the tray sends. */
const WHOLE: Record<string, string> = Object.freeze({ to_pct: '100' })

/** A mending press, quoted (the yard's whole repair; the Inn's hire of the hands she lacks, live/PortInn.tsx `HireNow`): the
 *  server's price for the day (null until it has answered, or when it refused), its own sentence when it refuses (a purse too small,
 *  no yard here, no hands on the quay), the one press that pays it, and `none` when nothing is to mend. */
export interface RepairQuote {
  cost: number | null
  refusal: Refusal | null
  busy: boolean
  send: () => void
  none: boolean
}

const noop = () => {}

/** THE WHOLE REPAIR AS ONE PRESS (0499; HQ's worker row, her sheet and While away, for a job that waits on E_FLAGSHIP_DISABLED): the
 *  same act as the tray's (useStepOrder: `cmd.preview` of the exact line, then `cmd.issue`), with no stepper. The Shipyard keeps
 *  the act (tests/verbHomes.spec.ts); the caller draws the press from the quote it is handed. */
export function RepairNow({ fleet, children }: { fleet: FleetView; children: (quote: RepairQuote) => ReactNode }) {
  const step = useStepOrder(fleet, 'REPAIR', true, noop, WHOLE)
  const c = step.check
  const cost = c.status === 'ok' && typeof c.result.estimate?.cost === 'number' ? c.result.estimate.cost : null
  const refusal = c.status === 'refused' ? c.refusal : null
  // "nothing aboard needs repair" (cmd.do_repair): mended since her job last spoke
  return <>{children({ cost, refusal, busy: step.issuing, send: step.send, none: refusal?.code === 'E_UNAVAILABLE' })}</>
}

export function PortShipyard({
  port,
  fleet,
}: {
  port: SnapshotPort
  /** A fleet of yours docked here, or null — a ship is repaired in port. */
  fleet: FleetView | null
}) {
  const t = useT()
  if (!fleet) {
    return <Note tone="neutral">{t('inn.noneHere')}</Note>
  }
  return <Repair port={port} fleet={fleet} />
}

/** Split so the hook never runs for a yard with nobody alongside. */
function Repair({ port, fleet }: { port: SnapshotPort; fleet: FleetView }) {
  const t = useT()
  const [open, setOpen] = useState(false)
  const step = useStepOrder(fleet, 'REPAIR', open, () => setOpen(false))
  const worst = worstHullFraction(fleet)
  const worn = wornFittings(fleet)

  return (
    <div data-testid="port-shipyard">
      {/* DAMAGE, not "Hull (worst ship)" — owner row 86. The figure is what the sea has TAKEN from
          the worst ship, printed as `1 − worst hull fraction`: a formatting of the served hull,
          not a rule. `13% damaged` is a reading; `87%` was a quiz. */}
      <Row
        label={t('inn.damage')}
        value={
          <Figure value={formatPct(1 - worst, 0)} tone={worst < 0.5 ? 'danger' : 'ink'} size="figure" />
        }
        chevron
        onClick={() => setOpen(true)}
        hairline={worn.units > 0}
        data-testid="shipyard-repair"
      />
      {/* 0158: HER WORN FITTINGS — a repair mends them with the hull, so the yard says how many there are (served
          only while gear wear bites; a whole hull with worn fittings is still a reason to press). */}
      {worn.units > 0 && (
        <Row
          label={t('ship.wornFittings')}
          value={<Figure value={formatInt(worn.units)} tone="warning" size="figure" />}
          chevron
          onClick={() => setOpen(true)}
          hairline={false}
          data-testid="shipyard-worn"
        />
      )}
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
