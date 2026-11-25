import type { ReactNode } from 'react'
import { Button, Note } from '../components/ui'
import type { WorkerFix } from '../domain/fleet'
import type { FleetView } from '../lib/rpc'
import { HireNow } from './PortInn'
import { RepairNow, type RepairQuote } from './PortShipyard'
import { fixPressOf, isPaidFix, useFixWord, type PaidFix } from './fixPress'
import { useWorld } from './worldStore'

// THE ONE PRESS THAT MENDS A REFUSAL (0499; the lead, 2026-11-25: "a worker row / stopped job whose code has a fix shows ONE button that
// does it in place"). Which press a code has is domain/fleet `fixOf`'s, and nothing here reads a code:
//   repair   the yard's whole repair of her fleet, AT THE SERVER'S PRICE on the button (live/PortShipyard.tsx `RepairNow`: the
//            Shipyard's own dry run and its own issue); a refusal (a purse too small, no yard where she lies) stands as its sentence
//   hire     the hands she lacks, hired at the server's price (live/PortInn.tsx `HireNow`: the Inn's own dry run and issue); a
//            refusal (a purse too small, no hands on this quay) stands as its sentence
//   assign   the one Assign sheet, for her
//   storage  HQ's Storage (the home city's Production page), where a full shed is sold from or used
// Her job goes on by itself once the cause is gone (the server's tick): nothing here restarts it.
// IT LIVES IN src/live BECAUSE TWO SCREENS DRAW IT: HQ (her sheet, While away) and a fleet's queue (features/command/Queue.tsx).

/** The building's quote for a paid fix: the Shipyard's or the Inn's. */
export function QuoteNow({ fix, fleet, children }: { fix: PaidFix; fleet: FleetView; children: (quote: RepairQuote) => ReactNode }) {
  return fix === 'repair' ? <RepairNow fleet={fleet}>{children}</RepairNow> : <HireNow fleet={fleet}>{children}</HireNow>
}

/** A paid press for one fleet: the price on it, and the server's sentence when it refuses. */
function PaidButton({ fix, fleet, className }: { fix: PaidFix; fleet: FleetView; className?: string }) {
  const word = useFixWord()
  return (
    <QuoteNow fix={fix} fleet={fleet}>
      {(q) =>
        // nothing to mend any more (mended since her job last spoke): no press
        q.none ? null : (
          <>
            <Button variant="primary" className={className} busy={q.busy} disabled={q.busy || q.cost === null} onClick={q.send} data-testid="corp-fix" data-fix={fix} data-cost={q.cost ?? undefined}>
              {word(fix, q.cost)}
            </Button>
            {q.refusal && (
              <Note tone="danger" code={q.refusal.code} figures={q.refusal.figures} data-testid="corp-fix-refusal">
                {q.refusal.sentence}
              </Note>
            )}
          </>
        )
      }
    </QuoteNow>
  )
}

/** THE BUTTON: one, or none. `worker` is a fleet's id or the party's. */
export function WorkerFixButton({ fix, worker, className }: { fix: WorkerFix | null; worker: string; className?: string }) {
  const word = useFixWord()
  const fleet = useWorld((s) => s.fleets.find((f) => f.id === worker) ?? null)
  if (fix === null) return null
  if (isPaidFix(fix)) return fleet && fleet.status === 'DOCKED' ? <PaidButton fix={fix} fleet={fleet} className={className} /> : null
  return (
    <Button variant="primary" className={className} onClick={fixPressOf(fix, worker)} data-testid="corp-fix" data-fix={fix}>
      {word(fix)}
    </Button>
  )
}
