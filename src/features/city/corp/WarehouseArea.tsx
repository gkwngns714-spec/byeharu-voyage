import { Bar, Icon, SheetSection, Skeleton, goodIcon } from '../../../components/ui'
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
// dark and HQ standing on another city), no shed is drawn under that word: the area says "No storage".
//
// A FIXED SHAPE (2026-11-25, the owner's law: nothing on a page moves by itself). The area was drawn only when its third read had
// answered, and then pushed the Ledger and the city's plates down. It now stands from the page's first frame and is the same box
// whatever is known: the heading, and one tile of one height holding the bar over ONE line of goods. While its reads are asked the
// tile is a skeleton; with no shed it says so; with more goods than the line holds, the ones that do not fit give way whole (the
// Production sheet lists every one).

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

export function WarehouseArea({ port }: { port: SnapshotPort }) {
  const t = useT()
  const goods = useWorld((s) => s.goodByCode)
  const { home, asking: homeAsking } = useHome(port)
  const read = useStorage(home?.id ?? null, null)
  const asking = homeAsking || (home !== null && read.view === null && read.loading)
  const shed = home && read.view && read.view.tier !== null ? read.view : null
  const stored = shed ? [...shed.stored].filter((g) => g.qty > 0).sort((a, b) => (b.tuns ?? 0) - (a.tuns ?? 0)) : []
  return (
    <SheetSection
      heading={shed && home ? `${t('corp.warehouse')} · ${home.name}` : t('corp.warehouse')}
      trailing={shed ? <span className="text-t-caption tabular-nums text-ink-muted">{`${formatOfTotal(shed.used, shed.cap)} ${tonsWord(shed.cap)}`}</span> : undefined}
      data-testid="corp-warehouse"
      data-state={asking ? 'asking' : shed ? 'shed' : 'none'}
    >
      {/* one tile, one height: the bar's line (8 px) over the goods' line (24 px) */}
      <div className="flex h-16 flex-col justify-between rounded-tile bg-surface p-3">
        {asking ? (
          <Skeleton className="h-full w-full" />
        ) : !shed ? (
          <span className="flex h-full items-center text-t-caption text-ink-faint" data-testid="corp-warehouse-none">
            {t('inn.noStorage')}
          </span>
        ) : (
          <>
            <div className="flex h-2 items-center">
              <Bar pct={shed.cap > 0 ? (shed.used / shed.cap) * 100 : 0} tone="accent" label={t('corp.warehouse')} className="w-full" />
            </div>
            {/* one line: a mark that does not fit wraps under the line and is cut away whole */}
            <div className="flex h-6 flex-wrap items-center gap-x-4 gap-y-6 overflow-hidden" data-testid="corp-warehouse-goods">
              {stored.length === 0 ? (
                <span className="text-t-caption text-ink-faint">{t('corp.empty')}</span>
              ) : (
                stored.slice(0, TOP).map((g) => {
                  const name = properName('good', g.good, g.name)
                  return (
                    <span key={g.good} className="inline-flex h-6 items-center gap-1 text-t-caption tabular-nums text-ink" title={name} aria-label={`${name} ${formatInt(g.qty)}`}>
                      <Icon name={goodIcon(g.good, goods[g.good]?.category ?? '')} size={18} className="text-accent" />
                      {formatInt(g.qty)}
                    </span>
                  )
                })
              )}
            </div>
          </>
        )}
      </div>
    </SheetSection>
  )
}
