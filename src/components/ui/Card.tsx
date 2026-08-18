import type { HTMLAttributes, ReactNode } from 'react'

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
 *  THE TWO instead of their sum. It is a no-op whenever they fit. */
export function CardHeader({
  eyebrow,
  title,
  subtitle,
  aside,
  className = '',
}: {
  eyebrow?: ReactNode
  title: ReactNode
  subtitle?: ReactNode
  aside?: ReactNode
  className?: string
}) {
  return (
    <div className={`mb-4 flex flex-wrap items-start justify-between gap-3 ${className}`}>
      <div>
        {eyebrow && (
          <p className="mb-0.5 font-mono text-xs uppercase tracking-wider text-ink-faint">{eyebrow}</p>
        )}
        <h2 className="font-serif text-lg font-semibold text-ink">{title}</h2>
        {subtitle && <p className="mt-0.5 text-sm text-ink-muted">{subtitle}</p>}
      </div>
      {aside && <div className="shrink-0">{aside}</div>}
    </div>
  )
}
