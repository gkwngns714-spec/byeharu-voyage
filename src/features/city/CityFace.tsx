import { Button, Note, Skeleton } from '../../components/ui'
import { buildingTier, hasBuilding } from '../../domain/port'
import { PortForge } from '../../live/PortForge'
import { PortInn } from '../../live/PortInn'
import { PortPrices } from '../../live/PortPrices'
import { PortShipyard } from '../../live/PortShipyard'
import { PortStorage } from '../../live/PortStorage'
import { PortTrade } from '../../live/PortTrade'
import { PortYard } from '../../live/PortYard'
import { usePortMarket } from '../../live/usePortMarket'
import type { FleetView, SnapshotPort } from '../../lib/rpc'
import { useT, type TKey } from '../../lib/i18n'
import { CityPanel } from './CityPanel'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A BUILDING'S FACE, IN THE RIGHT PANEL (the City page, 2026-10-31)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, 2026-10-31: *"when pressed each building, HQ stays the same, but the the location
// where the city image is, as well as the right side should only change."* So a building no longer
// pops a page: its face composes INTO the City page's right panel, while the frame — the header,
// the six building tiles, the figures and the rail — never moves. Every face here is an EXISTING
// one, composed; nothing is rewritten and nothing is a second authority (docs/NO_SPAGHETTI.md): the
// market is the quay's own Trade face (PortTrade) or, for a city no fleet of yours lies at, its
// read-only ledger (PortPrices), the storage is PortStorage, the port is the yard and the
// shipwright, the inn is PortInn, and the Forge is PortForge (0281: raw goods + recipes -> a
// crafted trade good). THE TOWN HALL HAS NO FACE: it stands IN PLACE in the same panel
// (CityHallPanel, the default).
//
// THE PANEL SCROLLS, THE PAGE DOES NOT. A face that outgrows the panel is read inside it, exactly
// as it is on every other screen; the document itself never scrolls (the City page's own law).

export type CityBuilding = 'market' | 'storage' | 'forge' | 'port' | 'inn'

/** One word per building, and the word's key beside it — never derived from the id. */
const BUILDING_LABEL: Record<CityBuilding, TKey> = {
  market: 'city.market',
  storage: 'city.storage',
  forge: 'city.forge',
  port: 'city.port',
  inn: 'city.inn',
}

/** The building's face as the City page's right panel — the same card shape as the Town Hall's
 *  panel, its content scrolling inside itself when a list is long. */
export function CityFacePanel({
  building,
  port,
  fleet,
}: {
  building: CityBuilding
  port: SnapshotPort
  /** A fleet of yours lying HERE (the city's acting fleet), or null — read-only city. */
  fleet: FleetView | null
}) {
  const t = useT()
  return (
    <CityPanel testId="city-face-panel" building={building}>
      <h2 className="pb-1 text-t-caption text-ink-faint">{t(BUILDING_LABEL[building])}</h2>
      {building === 'market' && <MarketFace port={port} fleet={fleet} />}
      {building === 'storage' && <StorageFace port={port} fleet={fleet} />}
      {building === 'forge' && <ForgeFace port={port} fleet={fleet} />}
      {building === 'port' && <PortFace port={port} fleet={fleet} />}
      {building === 'inn' && <InnFace port={port} fleet={fleet} />}
    </CityPanel>
  )
}

/** The quay that trades, or read-only prices from a quay no fleet of yours lies at. */
function MarketFace({ port, fleet }: { port: SnapshotPort; fleet: FleetView | null }) {
  const t = useT()
  const quay = usePortMarket(port.kind === 'HARBOUR' ? port.id : null)
  if (!hasBuilding(port, 'market')) return <Note tone="neutral">{t('city.noMarket')}</Note>
  if (quay.market === undefined) {
    return quay.refusal !== null ? (
      <Note
        tone="danger"
        code={quay.refusal.code}
        figures={quay.refusal.figures}
        action={
          <Button size="sm" onClick={quay.retry}>
            {t('common.retry')}
          </Button>
        }
      >
        {quay.refusal.sentence}
      </Note>
    ) : (
      <Skeleton className="h-28 w-full" />
    )
  }
  return fleet ? (
    <PortTrade goods={quay.market.goods} fleet={fleet} port={port} />
  ) : (
    <PortPrices goods={quay.market.goods} port={port} reader={null} />
  )
}

/** The Forge: the GOODS economy's crafting face (0281) — raw goods + recipes -> a trade good. */
function ForgeFace({ port, fleet }: { port: SnapshotPort; fleet: FleetView | null }) {
  return <PortForge portId={port.id} fleet={fleet} />
}

function StorageFace({ port, fleet }: { port: SnapshotPort; fleet: FleetView | null }) {
  const t = useT()
  if (!hasBuilding(port, 'warehouse')) return <Note tone="neutral">{t('inn.noStorage')}</Note>
  return <PortStorage portId={port.id} fleet={fleet} />
}

/** The port: lay a hull down, and repair what she has taken. Two existing faces, in order. */
function PortFace({ port, fleet }: { port: SnapshotPort; fleet: FleetView | null }) {
  const t = useT()
  const yard = hasBuilding(port, 'building_yard')
  const repair = hasBuilding(port, 'shipyard')
  if (!yard && !repair) return <Note tone="neutral">{t('city.noYard')}</Note>
  return (
    <>
      {yard && <PortYard portId={port.id} fleet={fleet} tier={buildingTier(port, 'building_yard')} />}
      {repair && (
        <div className={yard ? 'mt-6' : ''}>
          <PortShipyard port={port} fleet={fleet} />
        </div>
      )}
    </>
  )
}

function InnFace({ port, fleet }: { port: SnapshotPort; fleet: FleetView | null }) {
  const t = useT()
  if (!hasBuilding(port, 'inn')) return <Note tone="neutral">{t('city.noInn')}</Note>
  return <PortInn port={port} alongside={fleet} />
}
