import type { ReactNode } from 'react'

/** THE CITY PANEL — the ONE owner of the right-hand card: the Town Hall's panel and every building
 *  face stand on this shell (owner, 2026-10-31: a press changes only the plan's place and the right
 *  side). The card fills its column; its content scrolls INSIDE itself when a list is long, so the
 *  page never does. Rows pinned under the scroll (the Investors row and its drawer) go in `footer`. */
export function CityPanel({
  testId,
  scrollTestId,
  building,
  footer,
  contentClassName = '',
  children,
}: {
  testId: string
  /** The inner scroll region's testid, for the specs that measure it (the hall's no-scroll law). */
  scrollTestId?: string
  /** The open building's id, read by the specs (`data-building`). */
  building?: string
  footer?: ReactNode
  /** Extra classes for the scrolling body — the hall packs its padding on the narrowest glass
   *  (≤ 360 px), where every pixel of the 320×568 panel is spoken for. */
  contentClassName?: string
  children: ReactNode
}) {
  return (
    <section
      data-testid={testId}
      data-building={building}
      className="flex min-h-0 flex-1 flex-col overflow-hidden rounded-tile bg-surface"
    >
      <div
        data-testid={scrollTestId}
        // A QUERY CONTAINER (index.css, `narrow:`): on a phone this panel is half the glass, 139 px of room at 390 and 104 at 320, and
        // every row, summary row, act cell and face in it asks THIS width — not the screen's — how to stand.
        className={`@container bv-scroll min-h-0 min-w-0 flex-1 overflow-y-auto overflow-x-hidden px-gutter py-2 ${contentClassName}`}
      >
        {children}
      </div>
      {footer}
    </section>
  )
}
