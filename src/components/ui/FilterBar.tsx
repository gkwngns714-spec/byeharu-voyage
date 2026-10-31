import type { ReactNode } from 'react'
import { TileChoice, TileGrid } from './TileGrid'
import type { ChoiceColumns } from './tileStyles'

// THE FILTER BAR — one way to narrow and order a list: an ORDERED GRID of equal choice cells (one on at a
// time, "All" first; plus any on/off toggles after it), then a line of pickers (a country, a kind) and the
// sort. Written once here for every Stats face (owner row 228: "create filter for all parts in stats") and
// for any list that wants the same. The grid is the owner's 2026-10-31 rule (*"make it into square and
// allign properly orderly. this applies to all the places throughout the game."*): fixed columns, equal
// cells, never a ragged row of shrink-wrapped pills.
//
// IT DECIDES NOTHING. The caller owns the options, the choice and what a choice means; the choice is remembered per
// list by `useFilterChoice` (./filterState.ts). The grid and the pickers wrap onto fixed column lines, so the page
// never scrolls sideways.

export interface FilterOption<T extends string = string> {
  id: T
  label: ReactNode
}

export interface FilterChips<T extends string = string> {
  /** Names the group for assistive tech ("Area"). */
  label: string
  options: readonly FilterOption<T>[]
  value: T
  onChange: (id: T) => void
  /** Fixed columns of equal cells; default four (the owner's ordered grid, 2026-10-31). */
  columns?: ChoiceColumns
}

export interface FilterToggle {
  id: string
  label: ReactNode
  on: boolean
  onChange: (on: boolean) => void
}

export interface FilterPick<T extends string = string> {
  id: string
  /** Shown before the picker, and its accessible name ("Country", "Sort"). */
  label: string
  options: readonly { id: T; label: string }[]
  value: T
  onChange: (id: T) => void
}

export function FilterBar({
  chips,
  toggles = [],
  picks = [],
  sort,
  className = '',
  ...rest
}: {
  chips?: FilterChips<string>
  toggles?: readonly FilterToggle[]
  /** Filters with too many choices for chips (a country). */
  picks?: readonly FilterPick<string>[]
  sort?: FilterPick<string>
  className?: string
} & { 'data-testid'?: string }) {
  const lines = [...picks, ...(sort ? [sort] : [])]
  return (
    <div className={`flex min-w-0 flex-col gap-2 ${className}`} data-testid={rest['data-testid'] ?? 'filter-bar'}>
      {(chips !== undefined || toggles.length > 0) && (
        // ONE ORDERED GRID, NEVER A RAGGED CHIP ROW (owner, 2026-10-31). A filter set is a table of
        // equal cells on fixed column lines; the count is the set's, and the cells keep the 44-px floor.
        <TileGrid label={chips?.label} columns={chips?.columns ?? 4} className="pb-1">
          {chips?.options.map((o) => (
            <TileChoice key={o.id} on={o.id === chips.value} onClick={() => chips.onChange(o.id)} data-testid={`filter-chip-${o.id}`}>
              {o.label}
            </TileChoice>
          ))}
          {toggles.map((t) => (
            <TileChoice key={t.id} on={t.on} onClick={() => t.onChange(!t.on)} data-testid={`filter-toggle-${t.id}`}>
              {t.label}
            </TileChoice>
          ))}
        </TileGrid>
      )}
      {lines.length > 0 && (
        // a TOOLBAR, not a list: its pickers stand side by side and are not rows of one column (tests/align.spec.ts
        // skips a toolbar as it skips a tab list)
        <div role="toolbar" aria-label={lines.map((p) => p.label).join(', ')} className="flex min-w-0 flex-wrap items-center gap-2">
          {lines.map((p) => (
            <label key={p.id} className="flex min-w-0 max-w-full items-center gap-2 text-t-caption text-ink-faint">
              <span className="shrink-0">{p.label}</span>
              <select
                value={p.value}
                onChange={(e) => p.onChange(e.target.value)}
                className="min-h-11 min-w-0 max-w-full rounded-control bg-surface-2 px-3 text-t-caption text-ink"
                data-testid={`filter-pick-${p.id}`}
              >
                {p.options.map((o) => (
                  <option key={o.id} value={o.id}>
                    {o.label}
                  </option>
                ))}
              </select>
            </label>
          ))}
        </div>
      )}
    </div>
  )
}
