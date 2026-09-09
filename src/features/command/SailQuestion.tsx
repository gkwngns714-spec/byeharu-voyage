import { useEffect, useMemo, useState } from 'react'
import { Button, Field, Figure, Icon, Tile, TileField, Tray, type TrayDetent } from '../../components/ui'
import { SmallChart } from '../../chart'
import { OrderCheck, type CheckState } from './orderCheck'
import { fleetPortCode } from '../../domain/fleet'
import { fold, foldedMatch } from '../../lib/text'
import { formatInt } from '../../lib/format'
import { useWorld } from '../../live/worldStore'
import type { FleetView, SnapshotPort, WorldSnapshot } from '../../lib/rpc'

// SAIL — the world is the question. §6: "the chart takes the top 40% of the sheet (it is the
// question), harbour tiles below (name + nm), tap → tray."
//
// The chart is the Map tab's, drawn by the same modules (src/chart) — a chart copied across the
// screen boundary is the silent copy §2 forbids. It rings where she lies and the harbour this order
// would send her to; choosing still happens in the tiles, in words. The harbours are ordered by the
// server's sailed distance (`world.reach`, 0039) — never a straight line — and a dash means the
// reach read has not landed, never an invented figure. The tap opens the tray under nothing: the
// tray is `fixed`, so the chart and the tiles hold still.

export function SailQuestion({
  fleet,
  snapshot,
  dest,
  onPick,
  check,
  issuing,
  onIssue,
}: {
  fleet: FleetView
  snapshot: WorldSnapshot
  /** The chosen destination CODE (draft `dest`), or undefined while the list is open. */
  dest: string | undefined
  onPick: (code: string | null) => void
  check: CheckState
  issuing: boolean
  onIssue: () => void
}) {
  const [filter, setFilter] = useState('')
  const portByCode = useWorld((s) => s.portByCode)
  const reaches = useWorld((s) => s.reaches)
  const loadReach = useWorld((s) => s.loadReach)

  const origin = fleetPortCode(fleet)
  const originPortId = origin ? (portByCode[origin]?.id ?? null) : null
  useEffect(() => {
    if (originPortId) void loadReach(originPortId)
  }, [originPortId, loadReach])
  const reach = originPortId ? (reaches[originPortId]?.reaches ?? null) : null

  const rows = useMemo(() => {
    const q = fold(filter.trim())
    return snapshot.ports
      .filter((p) => p.code !== origin)
      .filter((p) => foldedMatch(q, p.name, p.code, p.country))
      .map((p) => ({ port: p, nm: reach ? (reach[p.code] ?? null) : null }))
      .sort(
        (a, b) =>
          Number(b.nm !== null) - Number(a.nm !== null) ||
          (a.nm ?? 0) - (b.nm ?? 0) ||
          a.port.region.localeCompare(b.port.region) ||
          a.port.name.localeCompare(b.port.name),
      )
      .slice(0, 24)
  }, [snapshot.ports, origin, reach, filter])

  const chosen = dest ? snapshot.ports.find((p) => p.code === dest) : undefined
  const refused = check.status === 'refused' || check.status === 'checking'

  return (
    <>
      <div className="aspect-[3/2] w-full overflow-hidden rounded-tile" data-testid="sail-chart">
        <SmallChart
          ports={snapshot.ports}
          fleets={[fleet]}
          considering={dest ? [dest] : []}
          highlight={dest ?? null}
          ariaLabel={`Chart showing where ${fleet.name} lies and where this order would send her`}
          className="h-full w-full"
        />
      </div>

      <Field
        value={filter}
        onChange={(e) => setFilter(e.target.value)}
        onClear={() => setFilter('')}
        aria-label="Filter harbours"
        placeholder="Filter harbours"
        spellCheck={false}
        autoCorrect="off"
        className="mt-3"
      />

      <TileField className="mt-3">
        {rows.map(({ port, nm }) => (
          <Tile
            key={port.code}
            name={port.name}
            meta={`${port.country}${hasIce(port) ? ' · ice' : ''}`}
            state={dest === port.code ? 'selected' : 'rest'}
            tap="whole"
            onClick={() => onPick(port.code)}
            figure={nm === null ? <Figure value="—" tone="faint" /> : <Figure value={formatInt(Math.round(nm))} unit="nm" />}
          />
        ))}
      </TileField>

      {chosen && (
        <SailTray
          name={chosen.name}
          endurance={fleet.endurance_days}
          check={check}
          timeCompression={snapshot.config.time_compression}
          disabled={issuing || refused}
          issuing={issuing}
          onIssue={onIssue}
          onClose={() => onPick(null)}
        />
      )}
    </>
  )
}

function hasIce(port: SnapshotPort): boolean {
  return port.is_ice_closed
}

function SailTray({
  name,
  endurance,
  check,
  timeCompression,
  disabled,
  issuing,
  onIssue,
  onClose,
}: {
  name: string
  endurance: number
  check: CheckState
  timeCompression: number
  disabled: boolean
  issuing: boolean
  onIssue: () => void
  onClose: () => void
}) {
  const [detent, setDetent] = useState<TrayDetent>('half')
  return (
    <Tray
      detent={detent}
      onDetentChange={(next) => (next === 'closed' ? onClose() : setDetent(next))}
      title={`Sail to ${name}`}
      data-testid="sail-tray"
      action={
        <Button
          variant="primary"
          className="w-full"
          disabled={disabled}
          busy={issuing}
          busyLabel="Issuing…"
          onClick={onIssue}
          data-testid="sail-send"
        >
          Sail to {name}
        </Button>
      }
    >
      <OrderCheck check={check} timeCompression={timeCompression} />
      <p className="flex items-center gap-2 py-2 text-t-label text-ink-muted">
        <Icon name="cask" size={18} className="shrink-0 text-ink-faint" />
        She carries {endurance.toFixed(1)} days of stores.
      </p>
    </Tray>
  )
}
