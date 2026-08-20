import type { HTMLAttributes, ReactNode } from 'react'
import { ExplainDot, ExplainPanel } from './Explain'
import { useExplainDisclosure } from './explainState'

// Design-system Card/Panel: the ONE panel treatment. `tone` gives a panel its subtle identity
// tint WITHOUT per-screen palettes. Rendered as <section>; spreads rest props so data-testid and
// aria-* pass through untouched.
//
// MATERIAL, changed 2026-08-20 (docs/UI_DIRECTION.md). A panel used to be a flat surface box with
// a 12px radius — a web card. It is now made of something: a warm panel body, a chamfered corner
// instead of a radius, and — when it carries a `head` — a browner header bar parted from the body
// by a gold hairline. That treatment was read off reference captures, where it is the single most
// repeated shape on screen.
//
// THE `head` SLOT EXISTS SO THERE IS STILL ONE PANEL. The reference header is FULL-BLEED: it runs
// to the panel's edges while the body stays padded. A caller cannot produce that from inside the
// padding without negative margins, so the panel owns the bar and the caller passes its contents
// (normally a <CardHeader>). Without `head`, a Card is exactly what it always was — every existing
// caller keeps working and simply inherits the new material.

export type CardTone = 'default' | 'accent' | 'success' | 'warning' | 'danger'

const TONE: Record<CardTone, string> = {
  default: 'border-edge bg-panel',
  accent: 'border-accent/25 bg-panel',
  success: 'border-success/25 bg-panel',
  warning: 'border-warning/25 bg-panel',
  danger: 'border-danger/25 bg-panel',
}

export function Card({
  tone = 'default',
  head,
  foot,
  className = '',
  children,
  ...rest
}: HTMLAttributes<HTMLElement> & {
  tone?: CardTone
  /** Full-bleed header bar contents — normally a <CardHeader>. Omit for a plain padded panel. */
  head?: ReactNode
  /** Full-bleed footer bar contents — the reference's pinned meter ("hold 276/457"). */
  foot?: ReactNode
}) {
  const framed = head !== undefined || foot !== undefined
  return (
    <section
      className={`bv-cut border ${TONE[tone]} shadow-card ${framed ? '' : 'p-4 sm:p-5'} ${className}`}
      {...rest}
    >
      {head !== undefined && <div className="bv-panel-head px-4 py-2.5 sm:px-5">{head}</div>}
      {framed ? <div className="p-4 sm:p-5">{children}</div> : children}
      {foot !== undefined && (
        <div className="border-t border-rule bg-panel-2 px-4 py-2 sm:px-5">{foot}</div>
      )}
    </section>
  )
}

/** Card title row: title (+ optional subtitle) on the left, an aside (badge/action/meta) on the
 *  right. `eyebrow` is the mono micro-designator PageHeader also carries — one idiom, defined once.
 *
 *  `flex-wrap` IS LOAD-BEARING: the aside is `shrink-0` (a badge that truncates says nothing), so
 *  without wrapping the row's MINIMUM width is title + gap + aside — a number made of GLYPHS, which
 *  differs per platform and can push a 320px page sideways. Wrapping makes the minimum the WIDER OF
 *  THE TWO instead of their sum. It is a no-op whenever they fit.
 *
 *  `subtitle` IS NOT PRINTED. It is the panel's standing explanation — what this card is, what its
 *  rows mean, what it deliberately does not show — and it goes behind the ⓘ beside the title
 *  (Explain.tsx). A card that must SAY something current says it in its body, where it can be
 *  read; a card that merely wants to introduce itself does it on demand.
 *
 *  ONE EXCEPTION, and it is the caller's to make: a line that discloses a tap affordance the
 *  player cannot otherwise discover ("Tap a fleet to command it.") is not an explanation, it is
 *  the control's own label. Those keep `subtitle` and stay printed. */
export function CardHeader({
  eyebrow,
  title,
  subtitle,
  explain,
  aside,
  flush = false,
  className = '',
}: {
  eyebrow?: ReactNode
  title: ReactNode
  /** Printed under the title. Live data about the card's subject, or the disclosure of a tap
   *  affordance the player could not otherwise find. */
  subtitle?: ReactNode
  /** The card's standing explanation — what its rows mean, what it deliberately does not show.
   *  Behind the ⓘ; never a live figure. */
  explain?: ReactNode
  aside?: ReactNode
  /** Set when this header IS the panel's header bar (passed as Card's `head`). The bar owns the
   *  spacing, so the header must not add a bottom margin inside it. */
  flush?: boolean
  className?: string
}) {
  const disclosure = useExplainDisclosure()
  return (
    <div
      className={`flex flex-wrap items-start justify-between gap-3 ${flush ? '' : 'mb-4'} ${className}`}
    >
      <div className="min-w-0">
        {eyebrow && (
          <p className="mb-0.5 font-mono text-xs uppercase tracking-wider text-ink-faint">{eyebrow}</p>
        )}
        <h2 className="font-serif text-lg font-semibold text-ink">
          {title}
          {explain && (
            <ExplainDot
              {...disclosure}
              label={typeof title === 'string' ? title : undefined}
              className="ml-1.5"
            />
          )}
        </h2>
        {subtitle && <p className="mt-0.5 text-sm text-ink-muted">{subtitle}</p>}
        {explain && <ExplainPanel {...disclosure}>{explain}</ExplainPanel>}
      </div>
      {aside && <div className="shrink-0">{aside}</div>}
    </div>
  )
}
