import type { HTMLAttributes, ReactNode } from 'react'
import { Explain } from './Explain'

// Design-system label/value stat row (render inside a <dl>). THE one chrome for the
// "Label · value" detail idiom. The VALUE is mono by default: it is nearly always a number, and a
// column of numbers that does not line up cannot be read at a glance. Pass `plain` when the value
// is prose. Spreads rest props so data-testid / aria-* pass through untouched.
//
// `hint` is a STANDING EXPLANATION and is therefore not printed — it lives behind the ⓘ (see
// Explain.tsx). It used to run inline after the value, which broke the one thing this row exists
// for: a column of right-aligned figures cannot line up when half of them trail a sentence.
//
// THE DOT AND ITS PANEL BOTH LIVE IN THE <dt>, not the <dd>, for two reasons. The panel is prose
// and must flow LEFT-aligned and wide, which the right-aligned value cell cannot give it; and a
// <dl> may only contain dt/dd groups, so a third box beside them would not be conforming markup.
// `flex-1 min-w-0` gives the label side every pixel the value does not need, so the panel opens
// nearly full width and wraps instead of pushing the row sideways.

export function StatRow({
  label,
  value,
  hint,
  plain = false,
  className = '',
  ...rest
}: Omit<HTMLAttributes<HTMLDivElement>, 'children'> & {
  label: ReactNode
  value: ReactNode
  /** The rule, units or provenance behind the figure. Behind the dot; never a live figure. */
  hint?: ReactNode
  plain?: boolean
}) {
  return (
    <div className={`flex items-baseline justify-between gap-3 text-sm ${className}`} {...rest}>
      <dt className="min-w-0 flex-1 text-ink-faint">
        {label}
        {hint && (
          <Explain label={typeof label === 'string' ? label : undefined} dotClassName="ml-0.5">
            {hint}
          </Explain>
        )}
      </dt>
      {/* No `shrink-0` here: a `plain` value is prose ("12 at the urgent rate") and must still be
          allowed to wrap on a 390px phone rather than widen the row. */}
      <dd className={`text-right text-ink ${plain ? '' : 'font-mono'}`}>{value}</dd>
    </div>
  )
}
