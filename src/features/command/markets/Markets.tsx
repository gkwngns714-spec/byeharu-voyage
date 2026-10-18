import { useMemo } from 'react'
import { Chip, Field, Note, Segmented, Skeleton, categoryLabel } from '../../../components/ui'
import { usePortMarket } from '../../../live/usePortMarket'
import { useWatchlist } from '../../../live/useDesk'
import { portNameOf, useWorld } from '../../../live/worldStore'
import { fold, foldedMatch } from '../../../lib/text'
import type { FleetView, SnapshotGood, WatchGood } from '../../../lib/rpc'
import { useDeskGood } from '../../../store/deskGood'
import { DESK_SORTS, useDeskView, type DeskFilter, type DeskSort } from '../deskView'
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

export function Markets({ fleet }: { fleet: FleetView }) {
  const snapshot = useWorld((s) => s.snapshot)
  const portByCode = useWorld((s) => s.portByCode)
  const { filter, sort, search, setFilter, setSort, setSearch } = useDeskView()
  const openGood = useDeskGood((s) => s.open)
  const openCode = useDeskGood((s) => s.code)
  const list = useWatchlist(fleet.id, fleet.version)

  const docked = fleet.status === 'DOCKED' && fleet.port ? (portByCode[fleet.port] ?? null) : null
  const quay = usePortMarket(filter === 'here' && docked ? docked.id : null)

  const byCode = useMemo(() => {
    const m: Record<string, WatchGood> = {}
    for (const g of list.view?.goods ?? []) m[g.code] = g
    return m
  }, [list.view])

  const categories = useMemo(() => [...new Set((snapshot?.goods ?? []).map((g) => g.category))].sort(), [snapshot])

  const rows = useMemo(() => {
    const goods: readonly SnapshotGood[] = snapshot?.goods ?? []
    const q = fold(search.trim())
    const offered =
      filter === 'here' ? new Set((quay.market?.goods ?? []).filter((g) => g.offered).map((g) => g.code)) : null
    const kept = goods.filter((g) => {
      if (!foldedMatch(q, g.name, g.code, g.category)) return false
      if (filter === 'on_board') return (byCode[g.code]?.on_board ?? 0) > 0
      if (filter === 'here') return offered?.has(g.code) ?? false
      if (filter.startsWith('cat:')) return g.category === filter.slice(4)
      return true
    })
    const price = (g: SnapshotGood) => byCode[g.code]?.best?.mid ?? Number.POSITIVE_INFINITY
    const change = (g: SnapshotGood) => byCode[g.code]?.change_pct ?? Number.NEGATIVE_INFINITY
    return [...kept].sort((a, b) =>
      sort === 'price'
        ? price(a) - price(b) || a.name.localeCompare(b.name)
        : sort === 'change'
          ? change(b) - change(a) || a.name.localeCompare(b.name)
          : a.name.localeCompare(b.name),
    )
  }, [snapshot, search, filter, sort, byCode, quay.market])

  const chips: { id: DeskFilter; label: string }[] = [
    { id: 'all', label: 'All' },
    ...(docked ? [{ id: 'here' as DeskFilter, label: 'Here' }] : []),
    { id: 'on_board', label: 'On board' },
    ...categories.map((c) => {
      const word = categoryLabel(c)
      return {
        id: `cat:${c}` as DeskFilter,
        label: word.charAt(0).toUpperCase() + word.slice(1),
      }
    }),
  ]

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
      <div className="-mx-gutter mt-2 flex gap-2 overflow-x-auto px-gutter pb-1" role="group" aria-label="Filter goods">
        {chips.map((c) => (
          <Chip key={c.id} on={filter === c.id} onClick={() => setFilter(c.id)} className="shrink-0 whitespace-nowrap">
            {c.label}
          </Chip>
        ))}
      </div>

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
              on={openCode === g.code}
              onOpen={() => openGood(g.code)}
              portName={(c) => portNameOf(portByCode, c)}
            />
          ))
        )}
      </div>
    </div>
  )
}
