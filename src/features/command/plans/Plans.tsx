import { SheetSection } from '../../../components/ui'
import { useWorld } from '../../../live/worldStore'
import type { FleetView } from '../../../lib/rpc'
import { Queue } from '../Queue'
import { RouteFold } from '../RouteFold'

// PLANS — the fleet's route and its orders (docs/COMMAND_DESK.md §3.5), the two things COMMAND held
// before the desk, moved onto their face as they were: the standing route above the queue (0092; it
// folds in place, the queue moves down), and the queue with its ✕ and Clear (busy only while their own
// press is on the wire — Queue.tsx wears the one `usePress`). The plan builder joins this face in D4.

export function Plans({ fleet }: { fleet: FleetView }) {
  const readAt = useWorld((s) => s.readAt)
  const cancel = useWorld((s) => s.cancel)
  const clearQueue = useWorld((s) => s.clear)
  return (
    <div data-testid="desk-plans">
      <RouteFold fleet={fleet} />
      <SheetSection heading="Orders" surface data-testid="command-queue">
        <Queue
          fleet={fleet}
          readAt={readAt}
          onCancel={(seq) => cancel(fleet.id, seq)}
          onClear={() => clearQueue(fleet.id)}
        />
      </SheetSection>
    </div>
  )
}
