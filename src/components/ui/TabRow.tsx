import type { ReactNode } from 'react'

// THE FACES OF ONE PLACE — the design system's tab strip.
//
// The reference draws a port as ONE panel with faces (기본 / 교역 / 시설 / 투자), not as four
// sibling cards stacked down a page (docs/UI_DIRECTION.md §2). The difference matters at 390px:
// four stacked cards means the fourth is 1,200px down and is never seen, while four faces means
// every one of them is one tap from the others and the panel keeps its header.
//
// IT IS A REAL TABLIST. role="tablist"/"tab" with aria-selected, so a screen reader announces
// "2 of 4" rather than reading four unlabelled buttons. The panel each tab governs carries
// role="tabpanel" at the call site — this primitive owns the strip, never the content.
//
// IT SCROLLS SIDEWAYS RATHER THAN WRAPPING. A wrapped second row of tabs changes the panel's
// height when the selection changes, which makes the content below jump. Five faces at 390px is
// already tight; the strip scrolls and the page does not (the same structural rule Table follows).
//
// THE SELECTED FACE IS GOLD AND SITS ON A LIT EDGE, because in the reference the selected tab is
// the one that looks connected to the panel below it.

export interface TabSpec<T extends string> {
  id: T
  label: ReactNode
  /** An optional count or badge riding after the label — rows, ships, actions available. */
  hint?: ReactNode
}

export function TabRow<T extends string>({
  tabs,
  value,
  onChange,
  label,
  className = '',
}: {
  tabs: readonly TabSpec<T>[]
  value: T
  onChange: (id: T) => void
  /** Names the set for assistive tech ("Port faces"). Not painted. */
  label: string
  className?: string
}) {
  return (
    <div
      role="tablist"
      aria-label={label}
      className={`-mx-1 flex gap-1 overflow-x-auto px-1 ${className}`}
    >
      {tabs.map((t) => {
        const on = t.id === value
        return (
          <button
            key={t.id}
            role="tab"
            type="button"
            aria-selected={on}
            onClick={() => onChange(t.id)}
            className={[
              'min-h-11 shrink-0 whitespace-nowrap border-b-2 px-3 font-mono text-xs uppercase tracking-wider transition',
              on
                ? 'border-accent bg-accent-soft text-accent'
                : 'border-transparent text-ink-faint hover:text-ink',
            ].join(' ')}
          >
            {t.label}
            {t.hint !== undefined && (
              <span className={`ml-1.5 ${on ? 'text-accent/70' : 'text-ink-faint/70'}`}>
                {t.hint}
              </span>
            )}
          </button>
        )
      })}
    </div>
  )
}
