import { useNavigate } from 'react-router-dom'
import {
  Badge,
  Card,
  CardHeader,
  CollapsibleCard,
  Meter,
  Notice,
  PageHeader,
  Screen,
  SectionLabel,
  TD,
  TH,
  Table,
} from '../../components/ui'
import {
  formatDucats,
  formatInt,
  formatKnots,
  formatNm,
  formatPct,
  formatRealShort,
  formatTuns,
  formatVoyageDays,
} from '../../lib/format'
import { useWorld } from '../../fixtures/useWorld'
import type { Ship } from '../../fixtures/types'
import { useCommandDraft } from '../command/commandDraft'
import type { FleetView } from './fleetMath'
import { fleetCargo, holdFree, holdUsed, seaworthiness, shipEnduranceDays, speedOfShip } from './fleetMath'

// FLEETS — E.2's roster. THE READ-ONLY TAB.
//
// "No commands here. Every row is a READ; tapping a row copies its name into the CMD line." So
// this screen has exactly one interaction and it is a handoff: tapping a fleet writes a draft into
// the shared store and goes to Command. It never issues anything, and it never grows a button that
// does — law 2, "commands live on their own tab".
//
// Every number on this screen is DERIVED, in fleetMath.ts, from the formulas in B.3, C.4 and C.5.
// Nothing here is stored, which is why the roster cannot drift from the ships it describes.

export function FleetsScreen() {
  const model = useWorld()
  const navigate = useNavigate()
  const handOff = useCommandDraft((s) => s.handOff)

  const command = (text: string, fleetId: string) => {
    handOff(text, fleetId)
    navigate('/command')
  }

  return (
    <Screen>
      <PageHeader
        eyebrow="Assets"
        title="Fleets"
        subtitle="What you own, and the state it is in."
        actions={
          <span className="font-mono text-xs text-ink-faint">
            {model.world.fleets.length}/{model.world.player.maxFleets} fleets ·{' '}
            {model.world.ships.length}/{model.world.player.maxShips} ships
          </span>
        }
      />

      <Card>
        <CardHeader eyebrow="Roster" title="All fleets" subtitle="Tap a fleet to command it." />
        <Table>
          <thead>
            <tr>
              <TH>Name</TH>
              <TH align="num">Ships</TH>
              <TH>Status</TH>
              <TH>Where</TH>
              <TH align="num">ETA</TH>
              <TH align="num">End.</TH>
            </tr>
          </thead>
          <tbody>
            {model.fleetViews.map((view) => (
              <tr key={view.fleet.id}>
                <TD>
                  <button
                    type="button"
                    className="min-h-11 text-left font-mono text-sm text-accent underline-offset-4 hover:underline"
                    onClick={() => command(`SAIL ${view.fleet.name} TO `, view.fleet.id)}
                  >
                    {view.fleet.name}
                  </button>
                </TD>
                <TD align="num">{view.shipCount}</TD>
                <TD>
                  <Badge tone={statusTone(view)}>{view.fleet.status}</Badge>
                </TD>
                <TD>{whereText(view, model.portOf)}</TD>
                <TD align="num">
                  {view.progress ? formatRealShort(view.progress.remainingMs) : '—'}
                </TD>
                <TD align="num">{formatVoyageDays(view.enduranceDays)}</TD>
              </tr>
            ))}
          </tbody>
        </Table>
        <p className="mt-3 font-mono text-[11px] text-ink-faint">
          END. is endurance in voyage-days — the shortest-ranged hull in the fleet (C.4). One
          voyage-day is three real minutes.
        </p>
      </Card>

      {model.fleetViews.map((view) => (
        <FleetDetail key={view.fleet.id} view={view} model={model} onCommand={command} />
      ))}
    </Screen>
  )
}

function FleetDetail({
  view,
  model,
  onCommand,
}: {
  view: FleetView
  model: ReturnType<typeof useWorld>
  onCommand: (text: string, fleetId: string) => void
}) {
  const cargo = fleetCargo(view.ships)
  const cargoValue = cargo.reduce((sum, lot) => sum + lot.tuns * lot.avgCost, 0)
  const water = view.ships.reduce((n, s) => n + s.waterT, 0)
  const food = view.ships.reduce((n, s) => n + s.foodT, 0)

  return (
    <CollapsibleCard
      title={view.fleet.name}
      subtitle={
        view.flagship
          ? `flag: ${view.flagship.name} (${model.classOf(view.flagship).name})`
          : 'no flagship'
      }
      aside={<Badge tone={statusTone(view)}>{view.fleet.status}</Badge>}
      storageKey={`fleet-${view.fleet.id}`}
      defaultOpen
    >
      <div className="space-y-4">
        {view.progress && (
          <div className="space-y-1">
            <div className="flex flex-wrap items-baseline justify-between gap-2 font-mono text-xs">
              <span className="text-ink">
                {model.portOf(view.progress.fromPort).name} →{' '}
                {model.portOf(view.progress.destination).name}
              </span>
              <span className="text-ink-muted">
                {formatNm(view.progress.coveredNm)} / {formatNm(view.progress.totalNm)} ·{' '}
                {formatRealShort(view.progress.remainingMs)}
              </span>
            </div>
            <Meter pct={view.progress.fraction * 100} tone="accent" />
            <p className="font-mono text-[11px] text-ink-faint">
              {formatVoyageDays(view.progress.totalVoyageDays)} at {formatKnots(view.fleet.voyage!.speedKn)},
              frozen at departure — an ETA quoted at departure never moves (B.5).
            </p>
          </div>
        )}

        <div>
          <SectionLabel>Ships</SectionLabel>
          <Table>
            <thead>
              <tr>
                <TH>Ship</TH>
                <TH>Class</TH>
                <TH align="num">Hull</TH>
                <TH align="num">Crew</TH>
                <TH align="num">Hold</TH>
                <TH align="num">Load</TH>
                <TH align="num">Speed</TH>
              </tr>
            </thead>
            <tbody>
              {view.ships.map((ship) => (
                <ShipRow key={ship.id} ship={ship} view={view} model={model} />
              ))}
            </tbody>
          </Table>
        </div>

        <div>
          <SectionLabel>Cargo</SectionLabel>
          {cargo.length === 0 ? (
            <p className="text-sm text-ink-muted">Empty hold.</p>
          ) : (
            <Table>
              <thead>
                <tr>
                  <TH>Good</TH>
                  <TH align="num">Tuns</TH>
                  <TH align="num">Avg cost</TH>
                  <TH align="num">At cost</TH>
                </tr>
              </thead>
              <tbody>
                {cargo.map((lot) => (
                  <tr key={lot.good}>
                    <TD>
                      <button
                        type="button"
                        className="min-h-11 text-left text-sm text-accent underline-offset-4 hover:underline"
                        onClick={() => onCommand(`SELL ${model.goodOf(lot.good).name} ALL`, view.fleet.id)}
                      >
                        {model.goodOf(lot.good).name}
                      </button>
                    </TD>
                    <TD align="num">{formatTuns(lot.tuns)}</TD>
                    <TD align="num">{formatInt(lot.avgCost)} d.</TD>
                    <TD align="num">{formatDucats(lot.tuns * lot.avgCost)}</TD>
                  </tr>
                ))}
                <tr>
                  <TD className="font-mono text-xs text-ink-faint">total</TD>
                  <TD align="num">{formatTuns(cargo.reduce((n, l) => n + l.tuns, 0))}</TD>
                  <TD align="num">—</TD>
                  <TD align="num">{formatDucats(cargoValue)}</TD>
                </tr>
              </tbody>
            </Table>
          )}
        </div>

        <div>
          <SectionLabel>Stores</SectionLabel>
          <p className="font-mono text-xs text-ink-muted">
            water {formatTuns(water, 1)} · food {formatTuns(food, 1)} ·{' '}
            {formatVoyageDays(view.enduranceDays)} at present · burns{' '}
            {formatTuns(view.burn.waterT + view.burn.foodT, 2)} and {formatDucats(view.burn.wagesDucats)}{' '}
            a voyage-day for {formatInt(view.burn.crew)} hands.
          </p>
        </div>

        <Notice tone="neutral" className="text-xs">
          Officers arrive with V1 (C.6). At V0 every expertise coefficient is 1.00, so a fleet is
          exactly its hulls, its hands and what is in the hold.
        </Notice>
      </div>
    </CollapsibleCard>
  )
}

function ShipRow({
  ship,
  view,
  model,
}: {
  ship: Ship
  view: FleetView
  model: ReturnType<typeof useWorld>
}) {
  const cls = model.classOf(ship)
  const hull = ship.durability / cls.maxDurability
  const used = holdUsed(ship)
  return (
    <tr>
      <TD>
        <span className="text-sm text-ink">
          {ship.name}
          {ship.isFlagship && (
            <span aria-label="flagship" title="flagship" className="ml-1 text-accent">
              ⚑
            </span>
          )}
        </span>
      </TD>
      <TD>
        <span className="text-xs text-ink-muted">{cls.name}</span>
      </TD>
      <TD align="num">
        <span className={hull < 0.5 ? 'text-danger' : hull < 0.8 ? 'text-warning' : ''}>
          {formatPct(hull)}
        </span>
      </TD>
      <TD align="num">
        <span className={ship.crew < cls.crewRequired ? 'text-danger' : ''}>
          {formatInt(ship.crew)}/{formatInt(cls.crewMax)}
        </span>
      </TD>
      <TD align="num">{formatTuns(cls.hold)}</TD>
      <TD align="num">
        {formatTuns(used, 1)} ({formatPct(used / cls.hold)})
      </TD>
      <TD align="num" title={`seaworthiness ${seaworthiness(ship, cls).toFixed(2)} · ${formatVoyageDays(shipEnduranceDays(ship))} alone · ${formatTuns(holdFree(ship, cls), 1)} free`}>
        <span className={speedOfShip(ship, cls) <= view.speedKn + 0.001 ? 'text-warning' : ''}>
          {formatKnots(speedOfShip(ship, cls))}
        </span>
      </TD>
    </tr>
  )
}

function whereText(view: FleetView, portOf: ReturnType<typeof useWorld>['portOf']): string {
  if (view.fleet.portCode) return portOf(view.fleet.portCode).name
  if (view.progress) return `→ ${portOf(view.progress.destination).name}`
  return '—'
}

function statusTone(view: FleetView) {
  switch (view.fleet.status) {
    case 'SAILING':
      return 'accent' as const
    case 'DOCKED':
      return 'success' as const
    case 'REPAIRING':
      return 'warning' as const
    case 'ADRIFT':
    case 'UNABLE_TO_SAIL':
      return 'danger' as const
    default:
      return 'neutral' as const
  }
}
