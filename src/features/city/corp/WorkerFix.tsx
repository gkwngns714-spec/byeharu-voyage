import type { FleetView } from '../../../lib/rpc'
import { QuoteNow } from '../../../live/FixButton'
import { fixPressOf, isPaidFix, useFixWord, useWreckWord, type PaidFix } from '../../../live/fixPress'
import { WreckNow } from '../../../live/WreckFix'
import { useWorld } from '../../../live/worldStore'
import { WorkerRow } from './WorkerRow'
import type { ActionNames, WorkerRow as Row } from './workerRows'

// A WORKER'S ROW WITH ITS ONE FIXING PRESS (0499). The row is one press (WorkerRow.tsx), so the row itself is the button: its pill
// says "Repair 736" / "Hire crew 100" / "Assign" / "Storage" and the press does it. The button her sheet and While away draw is
// live/FixButton.tsx's; which press a code has is domain/fleet `fixOf`'s.

/** HER ROW WITH A PAID FIX TO PRESS. While the price is not known, or the building refuses, the press opens her sheet, where the
 *  sentence stands. */
function PaidRow({ fix, row, fleet, names, nowMs, onPress }: { fix: PaidFix; row: Row; fleet: FleetView; names: ActionNames; nowMs: number; onPress: (row: Row) => void }) {
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

/** A WRECK'S ROW (0497): her next press on the pill, one at a time: "Sell cargo" (opens the sell face on her), then "Tow 14,366"
 *  with "Tow to Colombo" on her line (the press tows her), then, towed, the Repair every stopped worker has. While the server has
 *  not answered, or the press would not act (a tow her purse cannot pay and nothing to sell), the row opens her sheet, where the
 *  server's sentence stands. */
function WreckRow({ row, fleet, names, nowMs, onPress }: { row: Row; fleet: FleetView; names: ActionNames; nowMs: number; onPress: (row: Row) => void }) {
  const word = useWreckWord()
  return (
    <WreckNow fleet={fleet}>
      {(step) => {
        const w = word(step)
        return <WorkerRow row={row} names={names} nowMs={nowMs} pill={w.pill} note={w.note} fixKind={step.kind} fixCost={step.fee} onPress={step.press !== null && !step.busy ? step.press : onPress} />
      }}
    </WreckNow>
  )
}

/** A worker's row, with its one fixing press when her job's code has one. */
export function FixableRow({ row, names, nowMs, onPress }: { row: Row; names: ActionNames; nowMs: number; onPress: (row: Row) => void }) {
  const word = useFixWord()
  const fix = row.fix
  const fleet = useWorld((s) => (isPaidFix(fix) || fix === 'wreck' ? (s.fleets.find((f) => f.id === row.id) ?? null) : null))
  if (fix === 'wreck') return fleet ? <WreckRow row={row} fleet={fleet} names={names} nowMs={nowMs} onPress={onPress} /> : <WorkerRow row={row} names={names} nowMs={nowMs} onPress={onPress} />
  if (isPaidFix(fix)) return fleet ? <PaidRow fix={fix} row={row} fleet={fleet} names={names} nowMs={nowMs} onPress={onPress} /> : <WorkerRow row={row} names={names} nowMs={nowMs} onPress={onPress} />
  if (fix !== null) return <WorkerRow row={row} names={names} nowMs={nowMs} pill={word(fix)} onPress={fixPressOf(fix, row.id)} />
  return <WorkerRow row={row} names={names} nowMs={nowMs} onPress={onPress} />
}
