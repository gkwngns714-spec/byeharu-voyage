import type { ReactNode } from 'react'
import { Button, Note, Segmented, Skeleton } from '../../components/ui'
import { alongsideAt } from '../../domain/fleet'
import { useCommandDraft } from '../../domain/order'
import { usePortMarket } from '../../live/usePortMarket'
import { useWorld } from '../../live/worldStore'
import type { FleetView, SnapshotPort } from '../../lib/rpc'
import { PortInn } from '../../live/PortInn'
import { PortPrices } from '../../live/PortPrices'
import { CITY_TABS, useCityTab } from './cityTab'
import { CityTownHall } from './CityTownHall'
import { TowNote } from '../../live/TowNote'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE CITY PANEL'S FOUR TABS — Market | Port | Inn | Town Hall
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, 2026-10-15:
//
//   *"when i click on a city, i don't want to see stupid useless info. Rather, i want there to be
//    tab, such as market, port, inn. by clicking market it should show what it sells, the price
//    table, and so on. by clicking on part [port] it should show incomming ships, resting ships.
//    by clicking inn i should see captains … and inn should be a place where we can hire crew and
//    buy provisions."*
//
// NOTHING HERE IS NEW GAME. Each tab is a face PORT already draws, composed by a second caller:
//
//   Market  `PortPrices` — the read-only ledger (`world.market` through `usePortMarket`): every
//           good with its buy and sell price and where today's price stands in its range; a
//           press slides out `PriceTray` (the price history, the range, the stock). Trading
//           itself stays on PORT's quay, where the basket and the trade tray live.
//   Port    `CityHarbour` — in port and incoming, yours and the merchants' (MapScreen hands the
//           rows down; the harbour's read is MapScreen's, because it also feeds the title line).
//   Inn     `PortInn` — the captains in the room this quarter hour (`world.inn`, 0119), and, for
//           a fleet of yours lying here, the crew stepper (HIRE/DISMISS) and supplies
//           (PROVISION), both through `useStepOrder`'s dry run and one button.
//   Town Hall `CityTownHall` (0123) — the city's purse, its works, Invest (`cmd.preview_invest` →
//           `cmd.invest`, docked here only), and the investors by name (`world.town_hall`).
//
// Every second-level tray these faces open stands `side-next`, beside the panel — the pattern a
// ship opened from a fleet panel already uses (src/live/ShipPanel.tsx).
//
// WHICH FLEET ACTS: `alongsideAt` (src/domain/fleet/where.ts), the same rule PORT asks.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const NO_FLEETS: readonly FleetView[] = []

export function CityTabs({ portCode, harbour }: { portCode: string; harbour: ReactNode }) {
  const tab = useCityTab((s) => s.tab)
  const turnTo = useCityTab((s) => s.turnTo)
  const port = useWorld((s) => s.portByCode[portCode]) as SnapshotPort | undefined
  const fleets = useWorld((s) => s.fleets) ?? NO_FLEETS
  const draftFleetId = useCommandDraft((s) => s.fleetId)
  const { docked, acting } = alongsideAt(fleets, portCode, draftFleetId)

  return (
    <div data-testid="map-city-tabs">
      {/* 0152: a wreck of yours lying here, and its tow — whichever tab is up (src/live/TowNote.tsx). */}
      <TowNote docked={docked} />
      <Segmented label="City" segments={CITY_TABS} value={tab} onChange={turnTo} fill className="sticky top-0 z-10 mb-1" />
      <div role="tabpanel" data-testid={`map-city-${tab}`}>
        {tab === 'port' && harbour}
        {tab === 'market' && port && <CityMarket port={port} reader={acting} />}
        {tab === 'inn' && port && <PortInn port={port} alongside={docked[0] ?? null} trayMode="side-next" />}
        {tab === 'townhall' && port && <CityTownHall port={port} trayMode="side-next" />}
      </div>
    </div>
  )
}

/** The market read for one harbour, and the ledger once it lands — PORT's own loading and
 *  refusal states, for a city that keeps a book. */
function CityMarket({ port, reader }: { port: SnapshotPort; reader: FleetView | null }) {
  const quay = usePortMarket(port.kind === 'HARBOUR' ? port.id : null)
  if (port.kind !== 'HARBOUR') return <Note tone="neutral">No market here.</Note>
  if (quay.market === undefined) {
    return quay.refusal !== null ? (
      <Note
        tone="danger"
        code={quay.refusal.code}
        action={
          <Button size="sm" onClick={quay.retry}>
            Try again
          </Button>
        }
      >
        {quay.refusal.sentence}
      </Note>
    ) : (
      <Skeleton className="mt-3 h-28 w-full" />
    )
  }
  return <PortPrices goods={quay.market.goods} port={port} reader={reader} trayMode="side-next" />
}
