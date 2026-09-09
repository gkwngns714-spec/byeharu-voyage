import type { ReactNode } from 'react'
import { Icon } from './Icon'
import type { IconName } from './icons'

// THE TAB RAIL — six cells, one row, and the group opens a tray.
//
// The DECISION this draws is already made and already pinned: nine tabs took the bar to a 3×3 grid
// **168px tall on an 844px screen**, and the answer recorded in docs/OWNER_REQUESTS.md was to
// GROUP rather than to add rows. tests/nav.geometry.spec.ts holds it — one row, every cell over
// 44px, no label shaved, and pressing a group must not move a single cell of the bar it was
// pressed on. None of that changes here. What changes is the VOICE:
//
//   · the label was `font-mono text-[10px] uppercase tracking-wider`; it is `t-caption`, sentence
//     case (§4.1 bans uppercase and letter-spacing outright — §2 item 15 counts the label voice as
//     the strongest "2008 dashboard" signal on the screen)
//   · the icon is 22px on a 56px cell, which is §5's own number
//   · the group's panel becomes a `Tray` at `peek`, not a bespoke absolutely-positioned panel
//
// THIS PRIMITIVE IS THE RAIL AND NOTHING ELSE. It takes items and renders cells; the routing, the
// grouping table (`src/app/navTabs.ts`) and the tray's contents stay in the shell, which is where
// they were and where they belong. Step 3 repoints `src/app/NavBar.tsx` at this; step 2 does not
// touch a screen or the shell.
//
// A DESTINATION IS AN `<a>` AND A GROUP IS A `<button>`, which is not a style choice — it is how
// the geometry spec finds the groups without a second copy of the tab table to keep in step.

export interface NavItem {
  id: string
  label: ReactNode
  icon: IconName
  /** A destination. Omit for a group, which opens a tray instead of going anywhere. */
  href?: string
}

export function Nav({
  items,
  current,
  openGroup,
  onGroup,
  className = '',
  ...rest
}: {
  items: readonly NavItem[]
  /** The id of the cell that is the tab you are on. */
  current?: string
  /** The id of the group whose tray is open, if any. */
  openGroup?: string
  onGroup?: (id: string) => void
  className?: string
} & { 'data-testid'?: string }) {
  return (
    <nav
      aria-label="Tabs"
      className={`flex shrink-0 items-stretch border-t border-edge bg-surface ${className}`}
      {...rest}
    >
      {items.map((item) => {
        const on = item.id === current
        const cell = [
          'flex min-h-14 flex-1 flex-col items-center justify-center gap-0.5 px-1',
          on ? 'text-accent' : 'text-ink-faint',
        ].join(' ')
        const inside = (
          <>
            <Icon name={item.icon} size={22} />
            <span data-testid={`nav-label-${item.id}`} className="text-t-caption">
              {item.label}
            </span>
          </>
        )
        if (item.href !== undefined) {
          return (
            <a key={item.id} href={item.href} data-testid={`nav-cell-${item.id}`} className={cell}>
              {inside}
            </a>
          )
        }
        return (
          <button
            key={item.id}
            type="button"
            data-testid={`nav-cell-${item.id}`}
            aria-expanded={openGroup === item.id}
            onClick={() => onGroup?.(item.id)}
            className={cell}
          >
            {inside}
          </button>
        )
      })}
    </nav>
  )
}
