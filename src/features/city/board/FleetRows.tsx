import { Button, Figure, KEEP_WORDS_CLASS } from '../../../components/ui'
import { useShellState } from '../../../app/shellState'
import { whereabouts, whereLine } from '../../../domain/fleet'
import type { Move } from '../../../domain/hq'
import { routePorts } from '../../../domain/route'
import { formatDucatsDelta } from '../../../lib/format'
import { useT } from '../../../lib/i18n'
import type { FleetJobRow, ShipRolesView } from '../../../lib/rpc'
import { ShipPicture } from '../../../live/ShipPicture'
import { portNameOf, useWorld } from '../../../live/worldStore'
import { JobControl } from './JobControl'
import { RoleControl } from './RoleControl'
import { FLEET_JOB_TONE, FLEET_JOB_WORD } from './jobMarks'
import { MoveCard } from './MoveCard'
import type { BoardFleet, MoveData } from './useBoard'
import { useFleetPress, useMovePress } from './useMovePress'

// THE FLEETS (docs/design/hq-command-2026-11-23.md): one row a fleet — her flagship's picture in the tone of her job, her whole name, the
// job (a route, a trip, idle), what her route earned today, and one press: her sheet over HQ (app/HqSheet.tsx: status, cargo, route,
// orders, map, ship), her route first on Route. AN IDLE FLEET GLOWS (the gold edge, "you may act") and offers her best card under her row.
// 0481 (lit): her standing job's mark and setter under her row (JobControl).
// 0485 (lit): each of her hulls' role chips under her row (RoleControl), one press each.

export function FleetRows({
  fleets,
  moves,
  jobs = null,
  roles = null,
}: {
  fleets: readonly BoardFleet[]
  moves: readonly Move<MoveData>[]
  /** 0481: her fleets' standing jobs, by fleet; null while dark (no job is drawn). */
  jobs?: ReadonlyMap<string, FleetJobRow> | null
  /** 0485: her hulls' roles and slots; null while dark (no role is drawn). */
  roles?: Extract<ShipRolesView, { company: true }> | null
}) {
  const t = useT()
  const { nowMs } = useShellState()
  const portByCode = useWorld((s) => s.portByCode)
  const pressMove = useMovePress()
  const pressFleet = useFleetPress()
  const name = (code: string) => portNameOf(portByCode, code)

  return (
    <ul className="flex flex-col gap-2" data-testid="hq-fleets">
      {fleets.map((b) => {
        const f = b.fleet
        const idle = b.job === 'idle'
        const best = idle ? (moves.find((m) => m.kind === 'trade' && m.fleet === f.id) ?? null) : null
        const job =
          b.job === 'route' && b.route
            ? t('hq.onRoute', { ports: routePorts(b.route, portByCode) })
            : idle && b.port
              ? t('hq.docked', { port: name(b.port) })
              : whereLine(whereabouts(f), name, nowMs)
        return (
          <li
            key={f.id}
            className={`flex flex-col gap-2 rounded-tile bg-surface p-3 ${idle ? 'ring-1 ring-inset ring-accent' : ''}`}
            data-testid="hq-fleet"
            data-fleet={f.id}
            data-job={b.job}
          >
            <div className="flex items-center gap-3">
              <ShipPicture code={f.ships[0]?.class_code} tone={FLEET_JOB_TONE[b.job]} label={t(FLEET_JOB_WORD[b.job])} />
              <div className="flex min-w-0 flex-1 flex-col">
                <span className={`${KEEP_WORDS_CLASS} text-t-body font-medium text-ink`} data-testid="hq-fleet-name">
                  {f.name}
                </span>
                <span className="break-words text-t-caption text-ink-muted" data-testid="hq-fleet-job">
                  {job}
                </span>
              </div>
              {b.day !== null && (
                <span className="flex flex-col items-end" title={t('hq.day', { n: formatDucatsDelta(b.day) })}>
                  <Figure value={formatDucatsDelta(b.day)} tone={b.day < 0 ? 'danger' : 'success'} />
                </span>
              )}
              <Button variant={idle ? 'primary' : 'secondary'} onClick={() => pressFleet(f.id, b.job === 'route' || idle)} data-testid="hq-fleet-press">
                {b.job === 'route' || idle ? t('hq.setRoute') : t('hq.plan')}
              </Button>
            </div>
            {jobs && <JobControl fleet={f.id} job={jobs.get(f.id) ?? null} />}
            {roles && <RoleControl fleet={f.id} roles={roles} />}
            {best && (
              <div data-testid="hq-fleet-best">
                <MoveCard move={best} onPress={pressMove} inline jobs={jobs} />
              </div>
            )}
          </li>
        )
      })}
    </ul>
  )
}
