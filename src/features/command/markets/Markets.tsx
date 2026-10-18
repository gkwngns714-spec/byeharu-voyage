import { ChipRow, Chip, Field, Note, Segmented, Skeleton } from '../../../components/ui'
import { portNameOf, useWorld } from '../../../live/worldStore'
import type { FleetView } from '../../../lib/rpc'
import { useDeskGood } from '../../../store/deskGood'
import { DESK_SORTS, useDeskView, type DeskSort } from '../deskView'
import { useMarketRows, type MarketRows } from './marketRows'
import { WatchRow } from './WatchRow'

// MARKETS — every good once, like a broker's watchlist (docs/COMMAND_DESK.md §3.2). The owner,
// 2026-10-17: *"seeing charts of each trade goods that i click"*.
//
// THE LIST IS world.watchlist's (one read, at the market's edge) laid over the snapshot's catalogue
// (names, marks, categories). What this face owns is chrome: the search, the filter chips, the sort.
// `Here` narrows to what the city the fleet is docked at sells (world.market's `offered`, the read the
// quay already makes); `On board` to the fleet's cargo. A press opens the good's page; nothing on the
// list moves (the row takes the wash).
//
// THE COLUMN HEAD SAYS "Market price" ONCE: the figure is the cheapest seller's mid — the chart's own
// figure. What you would pay and what you would get are on the good's page, from the quote (§3.2's
// DEFAULT, technical: the ask needs each city's spread, ~1 ms a city on prod).

export function Markets({
  fleet,
  selected = null,
  market,
}: {
  fleet: FleetView
  /** The row the wide desk shows by default, when no good is open. */
  selected?: string | null
  /** The rows, when the caller already reads them (the wide desk); otherwise read here. */
  market?: MarketRows
}) {
  return market ? (
    <MarketsList fleet={fleet} selected={selected} market={market} />
  ) : (
    <MarketsOwnRows fleet={fleet} selected={selected} />
  )
}

function MarketsOwnRows({ fleet, selected }: { fleet: FleetView; selected: string | null }) {
  const market = useMarketRows(fleet)
  return <MarketsList fleet={fleet} selected={selected} market={market} />
}

function MarketsList({ selected, market }: { fleet: FleetView; selected: string | null; market: MarketRows }) {
  const portByCode = useWorld((s) => s.portByCode)
  const { filter, sort, search, setFilter, setSort, setSearch } = useDeskView()
  const openGood = useDeskGood((s) => s.open)
  const openCode = useDeskGood((s) => s.code)
  const { list, rows, byCode, chips } = market
  // The row that takes the wash: the good open, else the one the wide desk shows by default.
  const on = openCode ?? selected

  return (
    <div data-testid="desk-markets">
      <Field
        value={search}
        onChange={(e) => setSearch(e.target.value)}
        onClear={() => setSearch('')}
        icon="search"
        aria-label="Search goods"
        placeholder="Search goods"
        spellCheck={false}
        autoCorrect="off"
      />
      {/* THE FILTERS — one scrolling row, one on at a time; a press selects and moves nothing. */}
      <ChipRow label="Filter goods" className="mt-2">
        {chips.map((c) => (
          <Chip key={c.id} on={filter === c.id} onClick={() => setFilter(c.id)} className="shrink-0 whitespace-nowrap">
            {c.label}
          </Chip>
        ))}
      </ChipRow>

      <div className="mt-3 flex items-center justify-between gap-3">
        <Segmented<DeskSort> segments={DESK_SORTS} value={sort} onChange={setSort} label="Sort goods" />
        <span className="text-t-caption text-ink-faint">Market price</span>
      </div>

      <div className="mt-2" data-testid="watch-list">
        {list.loading && !list.view ? (
          Array.from({ length: 10 }, (_, i) => <Skeleton key={i} className="my-1 h-[50px] w-full" />)
        ) : !list.view ? (
          <Note tone="danger">The market list could not be read. It is asked again at the next price move.</Note>
        ) : rows.length === 0 ? (
          <Note tone="neutral" className="mt-2">
            {filter === 'on_board' ? 'No cargo on board.' : 'No goods match.'}
          </Note>
        ) : (
          rows.map((g) => (
            <WatchRow
              key={g.code}
              good={g}
              watch={byCode[g.code]}
              on={on === g.code}
              onOpen={() => openGood(g.code)}
              portName={(c) => portNameOf(portByCode, c)}
            />
          ))
        )}
      </div>
    </div>
  )
}
