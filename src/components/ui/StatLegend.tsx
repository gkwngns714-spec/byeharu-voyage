import type { ReactNode } from 'react'

// Design-system STAT LEGEND — a list of "TERM (unit) — what it decides" lines, for the inside of
// an Explain panel. The design system draws the list and knows nothing about ships: WHAT the terms
// are arrives as a parameter (src/domain/fleet's `shipStatItems` is the first supplier), which is
// the layer rule — machinery never imports the game (tests/sections.spec.ts).
//
// WHY A PRIMITIVE AND NOT A MAP LOOP IN EACH SCREEN (§7B, asked before it was built): three
// screens print ship-stat columns today — COMPENDIUM's ships face, FLEETS' ships table, PORT's
// Alongside table — so the second and third caller exist on day one, and three hand-written loops
// over one table is how the chip recipe reached twelve copies. The words have one authority
// (domain/fleet/statGloss.ts); this is the one chrome that renders them.
//
// SPANS, NOT DIVS: this renders inside ExplainPanel, which is itself a <span> so it can open
// inside a <p>, an <h3> or a <dd>. A <div> here would be silently reparented (Explain.tsx says
// why); `block` gives each line its box without breaking phrasing content.

export interface StatLegendItem {
  /** The column's own one-word name. */
  term: string
  /** What the figure is counted in — null/undefined for a plain count or rating. */
  unit?: string | null
  /** One line: what the figure decides. */
  line: ReactNode
}

export function StatLegend({
  items,
  className = '',
}: {
  items: readonly StatLegendItem[]
  className?: string
}) {
  return (
    <span className={`block space-y-1 ${className}`}>
      {items.map((i) => (
        <span key={i.term} className="block">
          <span className="font-mono uppercase tracking-wider text-ink-muted">{i.term}</span>
          {i.unit ? <span className="text-ink-muted">, in {i.unit}</span> : null}
          {' — '}
          {i.line}
        </span>
      ))}
    </span>
  )
}
