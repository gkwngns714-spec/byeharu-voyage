import type { ReactNode } from 'react'
import { Button, Note } from '../../../components/ui'
import { openHq, useHqPlace } from '../../../app/hqPlace'
import { formatDucats } from '../../../lib/format'
import { useT } from '../../../lib/i18n'
import type { FleetView } from '../../../lib/rpc'
import { HireNow } from '../../../live/PortInn'
import { RepairNow, type RepairQuote } from '../../../live/PortShipyard'
import { useWorld } from '../../../live/worldStore'
import { WorkerRow } from './WorkerRow'
import type { ActionNames, WorkerFix, WorkerRow as Row } from './workerRows'

// THE ONE PRESS THAT MENDS A JOB (0499; the lead, 2026-11-25: "a worker row / stopped job whose code has a fix shows ONE button that
// does it in place"). Which press a code has is workerRows.ts `fixOf`'s, and nothing here reads a code:
//   repair   the yard's whole repair of her fleet, AT THE SERVER'S PRICE on the button (live/PortShipyard.tsx `RepairNow`: the
//            Shipyard's own dry run and its own issue); a refusal (a purse too small, no yard where she lies) stands as its sentence
//   hire     the hands she lacks, hired at the server's price (live/PortInn.tsx `HireNow`: the Inn's own dry run and issue); a
//            refusal (a purse too small, no hands on this quay) stands as its sentence
//   assign   the one Assign sheet, for her
//   storage  HQ's Storage (the home city's Production page), where a full shed is sold from or used
// Her job goes on by itself once the cause is gone (the server's tick): nothing here restarts it.

/** The fixes that are paid for where she lies, each quoted by its building. */
type Paid = 'repair' | 'hire'
const isPaid = (fix: WorkerFix | null): fix is Paid => fix === 'repair' || fix === 'hire'

/** The press's word: "Repair 736", "Hire crew 100", "Assign", "Storage". */
function useFixWord(): (fix: WorkerFix, cost?: number | null) => string {
  const t = useT()
  return (fix, cost) =>
    fix === 'repair'
      ? cost != null
        ? t('corp.repairFor', { n: formatDucats(cost) })
        : t('corp.repair')
      : fix === 'hire'
        ? cost != null
          ? t('corp.hireFor', { n: formatDucats(cost) })
          : t('corp.hire')
        : fix === 'assign'
          ? t('corp.assign')
          : t('corp.warehouse')
}

/** Assign and Storage: one press each, no read. */
function pressOf(fix: Exclude<WorkerFix, Paid>, worker: string): () => void {
  return fix === 'assign' ? () => openHq({ sheet: 'assign', worker }) : () => useHqPlace.getState().openStorage()
}

/** The building's quote for a paid fix: the Shipyard's or the Inn's. */
function QuoteNow({ fix, fleet, children }: { fix: Paid; fleet: FleetView; children: (quote: RepairQuote) => ReactNode }) {
  return fix === 'repair' ? <RepairNow fleet={fleet}>{children}</RepairNow> : <HireNow fleet={fleet}>{children}</HireNow>
}

/** A paid press for one fleet: the price on it, and the server's sentence when it refuses. */
function PaidButton({ fix, fleet, className }: { fix: Paid; fleet: FleetView; className?: string }) {
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

/** THE BUTTON (her sheet, While away): one, or none. `worker` is a fleet's id or the party's. */
export function WorkerFixButton({ fix, worker, className }: { fix: WorkerFix | null; worker: string; className?: string }) {
  const word = useFixWord()
  const fleet = useWorld((s) => s.fleets.find((f) => f.id === worker) ?? null)
  if (fix === null) return null
  if (isPaid(fix)) return fleet && fleet.status === 'DOCKED' ? <PaidButton fix={fix} fleet={fleet} className={className} /> : null
  return (
    <Button variant="primary" className={className} onClick={pressOf(fix, worker)} data-testid="corp-fix" data-fix={fix}>
      {word(fix)}
    </Button>
  )
}

/** HER ROW WITH A PAID FIX TO PRESS: the row is one press (WorkerRow.tsx), so the row itself is the button: its pill says "Repair 736"
 *  and the press pays it. While the price is not known, or the building refuses, the press opens her sheet, where the sentence stands. */
function PaidRow({ fix, row, fleet, names, nowMs, onPress }: { fix: Paid; row: Row; fleet: FleetView; names: ActionNames; nowMs: number; onPress: (row: Row) => void }) {
  const word = useFixWord()
  return (
    <QuoteNow fix={fix} fleet={fleet}>
      {(q) =>
        q.none ? (
          <WorkerRow row={row} names={names} nowMs={nowMs} onPress={onPress} />
        ) : (
          <WorkerRow row={row} names={names} nowMs={nowMs} pill={word(fix, q.cost)} fixCost={q.cost} onPress={q.cost !== null && !q.busy ? () => q.send() : onPress} />
        )
      }
    </QuoteNow>
  )
}

/** A worker's row, with its one fixing press when her job's code has one. */
export function FixableRow({ row, names, nowMs, onPress }: { row: Row; names: ActionNames; nowMs: number; onPress: (row: Row) => void }) {
  const word = useFixWord()
  const fix = row.fix
  const fleet = useWorld((s) => (isPaid(fix) ? (s.fleets.find((f) => f.id === row.id) ?? null) : null))
  if (isPaid(fix)) return fleet ? <PaidRow fix={fix} row={row} fleet={fleet} names={names} nowMs={nowMs} onPress={onPress} /> : <WorkerRow row={row} names={names} nowMs={nowMs} onPress={onPress} />
  if (fix !== null) return <WorkerRow row={row} names={names} nowMs={nowMs} pill={word(fix)} onPress={pressOf(fix, row.id)} />
  return <WorkerRow row={row} names={names} nowMs={nowMs} onPress={onPress} />
}
