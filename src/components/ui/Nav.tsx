import type { MouseEvent as ReactMouseEvent, ReactNode } from 'react'
import { Icon } from './Icon'
import type { IconName } from './icons'
import { useT } from '../../lib/i18n'

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

// ── ON A WIDE GLASS IT IS A RAIL (2026-11-11, the remaster's S9; S4 had only centred the band) ─────────
// The playtest at 1280: five cells along a 1,280-px footer read as a footer, not a control. From `lg`
// (WIDE_QUERY) the same cells stand in a column down the window's left edge: each 64 px tall across the
// rail's width, the lit one on a soft gold plate, the GROUP (the Menu) at the rail's foot, where its tray
// opens beside it. Where the rail stands and how wide it is is the shell's (screenLayout.ts THE SHELL,
// src/app/ShellFrame.tsx); this primitive only draws the column. Below `lg` the bar is exactly as it was.
// Driven only by `items`, so it holds whatever cells the shell passes. A window too short for the column (seven
// 64-px cells want about 500 px) scrolls the rail itself, so no cell and never the Menu is cut off.

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
  const t = useT()
  return (
    <nav
      aria-label={t('ui.tabs')}
      className={`flex shrink-0 items-stretch border-t border-edge bg-surface lg:h-full lg:flex-col lg:gap-1 lg:overflow-y-auto lg:border-r lg:border-t-0 lg:px-2 lg:py-3 ${className}`}
      {...rest}
    >
      {items.map((item) => {
        const on = item.id === current
        const isOpen = item.href === undefined && openGroup === item.id
        const cell = [
          'flex min-h-14 min-w-0 flex-1 flex-col items-center justify-center gap-0.5 px-0.5 lg:min-h-16 lg:flex-none lg:gap-1 lg:rounded-tile lg:px-1 lg:transition-colors',
          on ? 'text-accent lg:bg-accent-soft' : 'text-ink-faint hover:text-ink lg:hover:bg-surface-2',
          // the group stands at the rail's foot, beside where its tray opens
          item.href === undefined ? 'lg:mt-auto' : '',
          isOpen ? 'text-ink lg:bg-surface-2' : '',
        ].join(' ')
        // THE MARK LEADS (2026-11-23, docs/design/visual-overhaul-2026-11-23.md, slice 1): the glyph stands on a pill that is
        // the lit cell's whole signal on a phone (the gold wash under a gold mark, the way a game's bar marks where you are),
        // and the word under it is a caption. On the rail the cell's own plate is the signal, so the pill stays clear there.
        // The pill is at most 48 px and never wider than its cell (seven cells at 320 px are 45 px each).
        const mark = (
          <span
            data-nav-mark=""
            className={`flex h-7 w-full max-w-12 items-center justify-center rounded-chip transition-colors ${
              on ? 'bg-accent-soft lg:bg-transparent' : isOpen ? 'bg-surface-2 lg:bg-transparent' : ''
            }`}
          >
            <Icon name={item.icon} size={22} strokeWidth={on ? 2 : 1.75} />
          </span>
        )
        const label = (
          <span data-testid={`nav-label-${item.id}`} className={`text-t-caption ${on ? 'font-semibold' : ''}`}>
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
              {mark}
              {label}
            </a>
          )
        }
        // A GROUP opens a tray instead of going anywhere: a `<button>` with `aria-expanded`. Its glyph is the four-tile `menu`
        // (navTabs.ts GROUPS) and does not turn; the pill under it is the open state. A press changes nothing about the bar's geometry.
        return (
          <button
            key={item.id}
            type="button"
            data-testid={`nav-cell-${item.id}`}
            aria-expanded={isOpen}
            onClick={() => onGroup?.(item.id)}
            className={cell}
          >
            {mark}
            {label}
          </button>
        )
      })}
    </nav>
  )
}

/**
 * A PLACE IN THE MENU: its glyph on a disc over its one-word name, as a tile (2026-11-23, docs/design/visual-overhaul-2026-11-23.md,
 * slice 1). The Menu was a list of rows, each a small line glyph and a word beside a chevron, which read as a settings page; the tiles
 * stand three to a line, the way a game lays out its screens. The place you are on wears the gold wash. A real `<a href>` (the router
 * answers a plain click through `onClick`), at least 88 px tall, so every tile is far over the 44-px reach floor.
 */
export function MenuTile({
  href,
  icon,
  label,
  here,
  onClick,
}: {
  href: string
  icon: IconName
  label: ReactNode
  here: boolean
  onClick: (e: ReactMouseEvent<HTMLAnchorElement>) => void
}) {
  return (
    <a
      href={href}
      onClick={onClick}
      aria-current={here ? 'page' : undefined}
      data-menu-tile=""
      className={`flex min-h-22 min-w-0 flex-col items-center justify-center gap-1.5 rounded-tile border px-1 py-2 transition-colors ${
        here ? 'border-accent/40 bg-accent-soft text-accent' : 'border-edge bg-surface-2 text-ink hover:border-accent/30'
      }`}
    >
      <span className={`flex h-10 w-10 items-center justify-center rounded-chip ${here ? 'bg-accent-soft' : 'bg-surface text-accent'}`}>
        <Icon name={icon} size={22} strokeWidth={1.75} />
      </span>
      <span className="max-w-full text-center text-t-caption font-medium">{label}</span>
    </a>
  )
}
