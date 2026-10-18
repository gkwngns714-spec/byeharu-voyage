import { useMemo } from 'react'
import { categoryLabel } from '../../../components/ui'
import { usePortMarket } from '../../../live/usePortMarket'
import { useWatchlist } from '../../../live/useDesk'
import { useWorld } from '../../../live/worldStore'
import { fold, foldedMatch } from '../../../lib/text'
import type { FleetView, SnapshotGood, WatchGood } from '../../../lib/rpc'
import { useDeskView, type DeskFilter } from '../deskView'

// THE MARKETS LIST'S ROWS — which goods stand on the watchlist, in what order (docs/COMMAND_DESK.md
// §3.2). One reading for both readers: the list itself (Markets.tsx), and the wide desk, which opens the
// list's FIRST row in its centre pane when nothing is chosen yet, so the glass is never half empty.
// world.watchlist laid over the snapshot's catalogue; the search, the filter and the sort are the
// face's chrome (deskView.ts). Nothing here prices anything.

export function useMarketRows(fleet: FleetView) {
  const snapshot = useWorld((s) => s.snapshot)
  const portByCode = useWorld((s) => s.portByCode)
  const { filter, sort, search } = useDeskView()
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

  return { list, rows, byCode, chips }
}

export type MarketRows = ReturnType<typeof useMarketRows>
