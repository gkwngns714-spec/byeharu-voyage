import type { ReactNode } from 'react'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A BOUNDED PANE: the glass stays still and the LIST gives (owner, 2026-10-31)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// *"i hate to scroll down on things, make it so that all the info is packed on one page."*
//
// A tab's `Sheet` is one scroll surface today; when a list inside it runs long (243 goods, 245
// harbours, a feed of hundreds of events) the whole tab travels and every heading over the list
// goes with it. A bounded pane is the opposite trade: the screen's composition stands, and the
// ONE list that is genuinely longer than the glass scrolls inside its own box. The page (the
// document) never scrolls — `onepage.spec.ts` measures that — and a pane is the only place a
// scrollbar is allowed.
//
// The caller sets the bound (`max-h-…`) because the room left over belongs to the screen's
// composition, not to this primitive. `data-scroll-pane` is the one attribute a spec (or a
// reader) can use to tell "this list is allowed to scroll" from "the tab is scrolling".

export function ScrollPane({
  className = '',
  children,
  ...rest
}: {
  className?: string
  children: ReactNode
} & { 'data-testid'?: string }) {
  return (
    <div className={`bv-scroll min-h-0 overflow-y-auto ${className}`} data-scroll-pane="" {...rest}>
      {children}
    </div>
  )
}
