import type { HTMLAttributes, ReactNode } from 'react'
import { ExplainDot, ExplainPanel } from './Explain'
import { useExplainDisclosure } from './explainState'

// Design-system Card/Panel: the ONE panel treatment (surface + edge + radius + elevation).
// `tone` gives a panel its subtle identity tint WITHOUT per-screen palettes. Rendered as
// <section>; spreads rest props so data-testid and aria-* pass through untouched.

export type CardTone = 'default' | 'accent' | 'success' | 'warning' | 'danger'

const TONE: Record<CardTone, string> = {
  default: 'border-edge bg-surface',
  accent: 'border-accent/25 bg-surface',
  success: 'border-success/25 bg-surface',
  warning: 'border-warning/25 bg-surface',
  danger: 'border-danger/25 bg-surface',
}

export function Card({
  tone = 'default',
  className = '',
  children,
  ...rest
}: HTMLAttributes<HTMLElement> & { tone?: CardTone }) {
  return (
    <section className={`rounded-card border ${TONE[tone]} p-4 shadow-card sm:p-5 ${className}`} {...rest}>
      {children}
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
  className?: string
}) {
  const disclosure = useExplainDisclosure()
  return (
    <div className={`mb-4 flex flex-wrap items-start justify-between gap-3 ${className}`}>
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
