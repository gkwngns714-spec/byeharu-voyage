import type { ReactNode } from 'react'
import { Card } from '../../components/ui'

/** THE CITY PANEL — the ONE owner of the side column's card: the Town Hall's panel and every building face stand on this shell (owner,
 *  2026-10-31: a press changes only the plan's place and the right side). It is a page `Card` (2026-11-04, owner row 267: the HQ takes the
 *  page pattern, docs/dev-log/2026-11-04-hq-design.md): its title is the place's word, its content stands at the card's own height and the PAGE
 *  scrolls — no list scrolls inside it any more. Rows pinned under the content (the Investors row and its drawer) go in `footer`. */
export function CityPanel({
  testId,
  scrollTestId,
  building,
  title,
  footer,
  contentClassName = '',
  children,
}: {
  testId: string
  /** The content region's testid, for the specs that measure it. */
  scrollTestId?: string
  /** The open building's id, read by the specs (`data-building`). */
  building?: string
  /** The place's own word, the card's title. */
  title?: ReactNode
  footer?: ReactNode
  /** Extra classes for the content region. */
  contentClassName?: string
  children: ReactNode
}) {
  return (
    <Card title={title} data-testid={testId} data-building={building}>
      <div
        data-testid={scrollTestId}
        // A QUERY CONTAINER (index.css, `narrow:`): every row, summary row, act cell and face in it asks THIS width — the side column's — how to stand.
        className={`@container min-w-0 ${contentClassName}`}
      >
        {children}
      </div>
      {footer}
    </Card>
  )
}
