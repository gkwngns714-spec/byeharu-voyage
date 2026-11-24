import { Button, Note } from '../../../components/ui'
import { openHq, useHqPlace } from '../../../app/hqPlace'
import { formatDucats } from '../../../lib/format'
import { useT } from '../../../lib/i18n'
import type { FleetView } from '../../../lib/rpc'
import { RepairNow } from '../../../live/PortShipyard'
import { useWorld } from '../../../live/worldStore'
import { WorkerRow } from './WorkerRow'
import type { ActionNames, WorkerFix, WorkerRow as Row } from './workerRows'

// THE ONE PRESS THAT MENDS A JOB (0499; the lead, 2026-11-25: "a worker row / stopped job whose code has a fix shows ONE button that
// does it in place"). Which press a code has is workerRows.ts `fixOf`'s, and nothing here reads a code:
//   repair   the yard's whole repair of her fleet, AT THE SERVER'S PRICE on the button (live/PortShipyard.tsx `RepairNow`: the
//            Shipyard's own dry run and its own issue); a refusal (a purse too small, no yard where she lies) stands as its sentence
//   assign   the one Assign sheet, for her
//   storage  HQ's Storage (the home city's Production page), where a full shed is sold from or used
// Her job goes on by itself once the cause is gone (the server's tick): nothing here restarts it.

/** The press's word: "Repair 736", "Assign", "Storage". */
function useFixWord(): (fix: WorkerFix, cost?: number | null) => string {
  const t = useT()
  return (fix, cost) => (fix === 'repair' ? (cost != null ? t('corp.repairFor', { n: formatDucats(cost) }) : t('corp.repair')) : fix === 'assign' ? t('corp.assign') : t('corp.warehouse'))
}

/** Assign and Storage: one press each, no read. */
function pressOf(fix: Exclude<WorkerFix, 'repair'>, worker: string): () => void {
  return fix === 'assign' ? () => openHq({ sheet: 'assign', worker }) : () => useHqPlace.getState().openStorage()
}

/** The repair press for one fleet: the price on it, and the server's sentence when it refuses. */
function RepairButton({ fleet, className }: { fleet: FleetView; className?: string }) {
  const word = useFixWord()
  return (
    <RepairNow fleet={fleet}>
      {(r) =>
        // a hull that needs nothing (mended since her job last spoke): no press
        r.refusal?.code === 'E_UNAVAILABLE' ? null : (
          <>
            <Button variant="primary" className={className} busy={r.busy} disabled={r.busy || r.cost === null} onClick={r.send} data-testid="corp-fix" data-fix="repair" data-cost={r.cost ?? undefined}>
              {word('repair', r.cost)}
            </Button>
            {r.refusal && (
              <Note tone="danger" code={r.refusal.code} figures={r.refusal.figures} data-testid="corp-fix-refusal">
                {r.refusal.sentence}
              </Note>
            )}
          </>
        )
      }
    </RepairNow>
  )
}

/** THE BUTTON (her sheet, While away): one, or none. `worker` is a fleet's id or the party's. */
export function WorkerFixButton({ fix, worker, className }: { fix: WorkerFix | null; worker: string; className?: string }) {
  const word = useFixWord()
  const fleet = useWorld((s) => s.fleets.find((f) => f.id === worker) ?? null)
  if (fix === null) return null
  if (fix === 'repair') return fleet && fleet.status === 'DOCKED' ? <RepairButton fleet={fleet} className={className} /> : null
  return (
    <Button variant="primary" className={className} onClick={pressOf(fix, worker)} data-testid="corp-fix" data-fix={fix}>
      {word(fix)}
    </Button>
  )
}

/** HER ROW WITH A REPAIR TO PRESS: the row is one press (WorkerRow.tsx), so the row itself is the button: its pill says "Repair 736"
 *  and the press pays it. While the price is not known, or the yard refuses, the press opens her sheet, where the sentence stands. */
function RepairRow({ row, fleet, names, nowMs, onPress }: { row: Row; fleet: FleetView; names: ActionNames; nowMs: number; onPress: (row: Row) => void }) {
  const word = useFixWord()
  return (
    <RepairNow fleet={fleet}>
      {(r) =>
        r.refusal?.code === 'E_UNAVAILABLE' ? (
          <WorkerRow row={row} names={names} nowMs={nowMs} onPress={onPress} />
        ) : (
          <WorkerRow row={row} names={names} nowMs={nowMs} pill={word('repair', r.cost)} fixCost={r.cost} onPress={r.cost !== null && !r.busy ? () => r.send() : onPress} />
        )
      }
    </RepairNow>
  )
}

/** A worker's row, with its one fixing press when her job's code has one. */
export function FixableRow({ row, names, nowMs, onPress }: { row: Row; names: ActionNames; nowMs: number; onPress: (row: Row) => void }) {
  const word = useFixWord()
  const fleet = useWorld((s) => (row.fix === 'repair' ? (s.fleets.find((f) => f.id === row.id) ?? null) : null))
  if (row.fix === 'repair' && fleet) return <RepairRow row={row} fleet={fleet} names={names} nowMs={nowMs} onPress={onPress} />
  if (row.fix === 'assign' || row.fix === 'storage') return <WorkerRow row={row} names={names} nowMs={nowMs} pill={word(row.fix)} onPress={pressOf(row.fix, row.id)} />
  return <WorkerRow row={row} names={names} nowMs={nowMs} onPress={onPress} />
}
