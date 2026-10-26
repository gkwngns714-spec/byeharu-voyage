import type { ReactNode } from 'react'
import { Chip } from './Chip'
import { ChipRow } from './ChipRow'

// THE FILTER BAR — one way to narrow and order a list: a row of chips that scrolls sideways (one chip on at a time,
// "All" first; plus any on/off toggles after it), then a line of pickers (a country, a kind) and the sort. Written
// once here for every Stats face (owner row 228: "create filter for all parts in stats") and for any list that
// wants the same (the Money log may adopt it).
//
// IT DECIDES NOTHING. The caller owns the options, the choice and what a choice means; the choice is remembered per
// list by `useFilterChoice` (./filterState.ts). On a phone the chips scroll inside their own row and the pickers
// wrap, so the page never scrolls sideways.

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
        <ChipRow label={chips?.label}>
          {chips?.options.map((o) => (
            <Chip key={o.id} on={o.id === chips.value} onClick={() => chips.onChange(o.id)} className="shrink-0 whitespace-nowrap" data-testid={`filter-chip-${o.id}`}>
              {o.label}
            </Chip>
          ))}
          {toggles.map((t) => (
            <Chip key={t.id} on={t.on} onClick={() => t.onChange(!t.on)} className="shrink-0 whitespace-nowrap" data-testid={`filter-toggle-${t.id}`}>
              {t.label}
            </Chip>
          ))}
        </ChipRow>
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
