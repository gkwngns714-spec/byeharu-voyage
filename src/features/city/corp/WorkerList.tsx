import { useState } from 'react'
import { SheetSection, Skeleton } from '../../../components/ui'
import { openHq } from '../../../app/hqPlace'
import { useShellState } from '../../../app/shellState'
import { useCommandDraft } from '../../../domain/order'
import { formatInt } from '../../../lib/format'
import { useT } from '../../../lib/i18n'
import { WorkerRow } from './WorkerRow'
import { sortWorkers, useWorkers, type WorkerRow as Row } from './workerRows'

// THE ONE WORKER LIST (docs/design/hq-corp-2026-11-24.md A2, C1; slice H1; the owner, 2026-11-24: *"it is like madevor's rs3 jagex game
// idle game, but instead of doing with only 1 player, i do it with multiple"*): every worker of hers on one screen, one row each, each
// on one action with its bar; the idle ones first, with Assign.
// THE ORDER IS SET WHEN THE PAGE OPENS (idle, then stopped, then working) and never under the pointer: a worker who changes state
// keeps her place, and a new one joins at the foot. The list waits for its reads, so it is ordered once, on what is true.
// A press: an idle worker's opens the one Assign sheet; any other opens her sheet (her action, Change, Stop). While her kind of work
// is dark on this server, a fleet's press opens her own sheet (cargo, route, orders), which works today.

export function WorkerList() {
  const t = useT()
  const { nowMs } = useShellState()
  const { rows, ready, names } = useWorkers()
  const selectFleet = useCommandDraft((s) => s.selectFleet)
  const [order, setOrder] = useState<readonly string[]>([])

  // a worker not placed yet takes her place (the first time: all of them, sorted); nobody placed ever moves
  const fresh = ready ? rows.filter((r) => !order.includes(r.id)) : []
  if (fresh.length > 0) setOrder([...order, ...sortWorkers(fresh).map((r) => r.id)])
  const byId = new Map(rows.map((r) => [r.id, r]))
  const list = order.flatMap((id) => byId.get(id) ?? [])

  const press = (r: Row) => {
    if (r.kind === 'fleet') selectFleet(r.id)
    if (r.kind === 'fleet' && !r.assignable) openHq({ sheet: 'fleet', fleet: r.id })
    else if (r.state === 'idle') openHq({ sheet: 'assign', worker: r.id })
    else openHq({ sheet: 'worker', worker: r.id })
  }

  if (ready && rows.length === 0) return null
  return (
    <SheetSection heading={t('corp.workers')} trailing={ready ? <span className="text-t-caption tabular-nums text-ink-faint">{formatInt(rows.length)}</span> : undefined} data-testid="corp-workers">
      {!ready ? (
        <Skeleton className="h-[104px] w-full lg:h-[72px]" />
      ) : (
        <ul className="flex flex-col gap-2" data-testid="corp-worker-list">
          {list.map((r) => (
            <li key={r.id}>
              <WorkerRow row={r} names={names} nowMs={nowMs} onPress={press} />
            </li>
          ))}
        </ul>
      )}
    </SheetSection>
  )
}
