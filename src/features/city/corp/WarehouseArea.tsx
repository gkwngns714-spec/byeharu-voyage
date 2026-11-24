import { Bar, HeldRoom, Icon, SheetSection, goodIcon } from '../../../components/ui'
import { formatInt, formatOfTotal, tonsWord } from '../../../lib/format'
import { properName, useT } from '../../../lib/i18n'
import type { SnapshotPort } from '../../../lib/rpc'
import { useMarketRequests } from '../../../live/useMarketRequests'
import { useStorage } from '../../../live/useStorage'
import { useWorld } from '../../../live/worldStore'
import { useCorpLand } from './workerRows'

// THE WAREHOUSE (docs/design/hq-corp-2026-11-24.md B2, C1; slice H1): the shed at the company's HOME city, as one bar (used of its
// room, in tuns) and its goods as marks with their units. Every figure is `world.warehouse`'s (live/useStorage.ts).
// WHICH CITY IS HOME is the server's reading (public.home_port_of), read where it is served today: the Land's read names it
// (`home.port`), and a city's own requests read says whether it is home (`world.requests().home`). Where neither says so (the Land
// dark and HQ standing on another city), no warehouse is drawn rather than another city's shed under that word.

/** How many goods stand as marks. */
const TOP = 8

/** Her home city, or null while no served read names it; `asking` while the read that would name it has not answered yet. */
function useHome(port: SnapshotPort): { home: SnapshotPort | null; asking: boolean } {
  const portByCode = useWorld((s) => s.portByCode)
  const { land, loading } = useCorpLand()
  const here = useMarketRequests(land ? null : port.id)
  if (land) return { home: portByCode[land.home.port] ?? null, asking: false }
  return { home: here.view?.home ? port : null, asking: loading || (here.view === null && here.loading) }
}

type Shed = NonNullable<ReturnType<typeof useStorage>['view']>

/** The area holds the room it had last time while its reads are asked (HeldRoom.tsx): it stands over the Ledger and the city's plates,
 *  and drawn when its third read landed it pushed them down (2026-11-25). */
export function WarehouseArea({ port }: { port: SnapshotPort }) {
  const { home, asking } = useHome(port)
  const read = useStorage(home?.id ?? null, null)
  const shed = read.view
  return (
    <HeldRoom name="hq-storage" asking={asking || (home !== null && shed === null && read.loading)}>
      {home && shed && shed.tier !== null && <ShedArea home={home} shed={shed} />}
    </HeldRoom>
  )
}

function ShedArea({ home, shed }: { home: SnapshotPort; shed: Shed }) {
  const t = useT()
  const goods = useWorld((s) => s.goodByCode)
  const stored = [...shed.stored].filter((g) => g.qty > 0).sort((a, b) => (b.tuns ?? 0) - (a.tuns ?? 0))
  return (
    <SheetSection
      heading={`${t('corp.warehouse')} · ${home.name}`}
      trailing={<span className="text-t-caption tabular-nums text-ink-muted">{`${formatOfTotal(shed.used, shed.cap)} ${tonsWord(shed.cap)}`}</span>}
      data-testid="corp-warehouse"
    >
      <div className="rounded-tile bg-surface p-3">
        <Bar pct={shed.cap > 0 ? (shed.used / shed.cap) * 100 : 0} tone="accent" label={t('corp.warehouse')} />
        <div className="mt-2 flex min-h-6 flex-wrap items-center gap-x-4 gap-y-1" data-testid="corp-warehouse-goods">
          {stored.length === 0 ? (
            <span className="text-t-caption text-ink-faint">{t('corp.empty')}</span>
          ) : (
            stored.slice(0, TOP).map((g) => {
              const name = properName('good', g.good, g.name)
              return (
                <span key={g.good} className="inline-flex items-center gap-1 text-t-caption tabular-nums text-ink" title={name} aria-label={`${name} ${formatInt(g.qty)}`}>
                  <Icon name={goodIcon(g.good, goods[g.good]?.category ?? '')} size={18} className="text-accent" />
                  {formatInt(g.qty)}
                </span>
              )
            })
          )}
        </div>
      </div>
    </SheetSection>
  )
}
