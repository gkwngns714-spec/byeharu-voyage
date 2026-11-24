import { Bar, Icon, SheetSection, goodIcon } from '../../../components/ui'
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

/** Her home city, or null while no served read names it. */
function useHome(port: SnapshotPort): SnapshotPort | null {
  const portByCode = useWorld((s) => s.portByCode)
  const { land } = useCorpLand()
  const here = useMarketRequests(land ? null : port.id)
  if (land) return portByCode[land.home.port] ?? null
  return here.view?.home ? port : null
}

export function WarehouseArea({ port }: { port: SnapshotPort }) {
  const t = useT()
  const goods = useWorld((s) => s.goodByCode)
  const home = useHome(port)
  const shed = useStorage(home?.id ?? null, null).view
  if (!home || !shed || shed.tier === null) return null
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
