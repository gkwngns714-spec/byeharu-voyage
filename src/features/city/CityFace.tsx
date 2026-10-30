import { Button, Note, Sheet, Skeleton } from '../../components/ui'
import { buildingTier, hasBuilding } from '../../domain/port'
import { CityInfo } from '../../live/CityInfo'
import { CityTownHall } from '../../live/CityTownHall'
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

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A BUILDING'S FACE, FULL SCREEN (the City page, 2026-10-30).
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// Every face here is an EXISTING one, composed — nothing is rewritten and nothing is a second
// authority (docs/NO_SPAGHETTI.md): the city hall is CityTownHall + CityInfo, the market is the
// quay's own Trade face (PortTrade) or, for a city no fleet of yours lies at, its read-only
// ledger (PortPrices), the storage is PortStorage, the port is the yard and the shipwright, the
// inn is PortInn, and the Forge is PortForge (0281: raw goods + recipes -> a crafted trade good).
//
// THE PAGE SCROLLS, THE GLASS DOES NOT. A face is a `Sheet` inside a fixed, full-viewport layer:
// the document never scrolls (the City page's own rule), while a long list — the market's goods —
// is read inside the sheet, exactly as it is on every other screen.

export type CityBuilding = 'hall' | 'market' | 'storage' | 'forge' | 'port' | 'inn'

/** One word per building, and the word's key beside it — never derived from the id. */
const BUILDING_LABEL: Record<CityBuilding, TKey> = {
  hall: 'city.cityHall',
  market: 'city.market',
  storage: 'city.storage',
  forge: 'city.forge',
  port: 'city.port',
  inn: 'city.inn',
}

export function CityFace({
  building,
  port,
  fleet,
  onClose,
}: {
  building: CityBuilding
  port: SnapshotPort
  /** A fleet of yours lying HERE (the city's acting fleet), or null — read-only city. */
  fleet: FleetView | null
  onClose: () => void
}) {
  const t = useT()
  const label = t(BUILDING_LABEL[building])
  return (
    <div className="fixed inset-0 z-40 bg-bg" data-testid="city-face" data-building={building}>
      <Sheet
        title={label}
        trailing={
          <Button variant="quiet" size="sm" onClick={onClose} data-testid="city-face-back">
            {t('common.back')}
          </Button>
        }
      >
        {building === 'hall' && (
          <>
            <CityInfo port={port} />
            <div className="mt-6" data-testid="city-hall-treasury">
              <CityTownHall port={port} />
            </div>
          </>
        )}
        {building === 'market' && <MarketFace port={port} fleet={fleet} />}
        {building === 'storage' && <StorageFace port={port} fleet={fleet} />}
        {building === 'forge' && <ForgeFace port={port} fleet={fleet} />}
        {building === 'port' && <PortFace port={port} fleet={fleet} />}
        {building === 'inn' && <InnFace port={port} fleet={fleet} />}
      </Sheet>
    </div>
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
