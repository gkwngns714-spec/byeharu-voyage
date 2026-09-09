import type { MouseEvent as ReactMouseEvent, ReactNode } from 'react'
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
//   · the group's panel becomes a `Tray`, not a bespoke absolutely-positioned panel
//
// THIS PRIMITIVE IS THE RAIL AND NOTHING ELSE. It takes items and renders cells; the routing, the
// grouping table (`src/app/navTabs.ts`) and the tray's contents stay in the shell, which is where
// they were and where they belong. Step 3 repoints `src/app/NavBar.tsx` at this.
//
// A DESTINATION IS AN `<a>` AND A GROUP IS A `<button>`, which is not a style choice — it is how
// the geometry spec finds the groups without a second copy of the tab table to keep in step.
//
// ── THE ANCHOR IS REAL, AND THE ROUTER STILL GETS THE CLICK (step 3) ────────────────────────────
// The cell has to BE an `<a href>`: the geometry spec reads the element type, assistive technology
// reads it as a link, and a middle-click or a long-press must be able to open a tab. But this app
// is a `BrowserRouter` over a database that lives in the browser — letting the anchor navigate for
// real re-downloads the bundle and re-opens PGlite on every single tab press. So the rail takes
// `onNavigate` and hands it the plain left-click; the shell calls `navigate()`, and the anchor
// keeps its href for everything else. Modified clicks are deliberately NOT intercepted: those are
// the ones that mean "open this somewhere else", and the browser is right about them.

export interface NavItem {
  id: string
  label: ReactNode
  icon: IconName
  /** A destination. Omit for a group, which opens a tray instead of going anywhere. */
  href?: string
}

/** A left-click with no modifier — the one a single-page router should answer instead of the
 *  browser. Every other click (middle, ⌘, ctrl, shift, alt) means "somewhere else", and the
 *  anchor's own href is the right answer to it. */
function isPlainClick(e: ReactMouseEvent): boolean {
  return (
    !e.defaultPrevented && e.button === 0 && !e.metaKey && !e.ctrlKey && !e.shiftKey && !e.altKey
  )
}

export function Nav({
  items,
  current,
  openGroup,
  onGroup,
  onNavigate,
  className = '',
  ...rest
}: {
  items: readonly NavItem[]
  /** The id of the cell that is the tab you are on. */
  current?: string
  /** The id of the group whose tray is open, if any. */
  openGroup?: string
  onGroup?: (id: string) => void
  /** Given the item on a plain left-click, so a router can answer instead of the browser. Leave it
   *  out and the anchors navigate the ordinary way. It is handed the ITEM and not the href because
   *  a router routes on a path and the href is that path with a basename on the front of it —
   *  translating one back into the other in the caller is a second spelling of `tabHref`. */
  onNavigate?: (item: NavItem) => void
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
        const label = (
          <span data-testid={`nav-label-${item.id}`} className="text-t-caption">
            {item.label}
          </span>
        )
        if (item.href !== undefined) {
          return (
            <a
              key={item.id}
              href={item.href}
              data-testid={`nav-cell-${item.id}`}
              onClick={(e) => {
                if (onNavigate === undefined || !isPlainClick(e)) return
                e.preventDefault()
                onNavigate(item)
              }}
              className={cell}
            >
              <Icon name={item.icon} size={22} />
              {label}
            </a>
          )
        }
        // A GROUP'S GLYPH IS THE CHEVRON, and the RAIL turns it rather than the shell. navTabs.ts
        // states the rule this draws: a group cell's honest graphic is "this opens", because no
        // single subject glyph is true of all four members. So it points UP at what it will reveal
        // and DOWN once the tray is standing — the only thing a press changes about the bar, and
        // it changes nothing about the bar's geometry.
        const isOpen = openGroup === item.id
        return (
          <button
            key={item.id}
            type="button"
            data-testid={`nav-cell-${item.id}`}
            aria-expanded={isOpen}
            onClick={() => onGroup?.(item.id)}
            className={cell}
          >
            <Icon name={item.icon} size={22} className={isOpen ? 'rotate-90' : '-rotate-90'} />
            {label}
          </button>
        )
      })}
    </nav>
  )
}
