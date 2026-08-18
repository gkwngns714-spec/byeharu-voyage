import type { HTMLAttributes, ReactNode } from 'react'

// Design-system label/value stat row (render inside a <dl>). THE one chrome for the
// "Label · value" detail idiom. The VALUE is mono by default: it is nearly always a number, and a
// column of numbers that does not line up cannot be read at a glance. Pass `plain` when the value
// is prose. Spreads rest props so data-testid / aria-* pass through untouched.

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
  hint?: ReactNode
  plain?: boolean
}) {
  return (
    <div className={`flex items-baseline justify-between gap-3 text-sm ${className}`} {...rest}>
      <dt className="text-ink-faint">{label}</dt>
      <dd className={`text-right text-ink ${plain ? '' : 'font-mono'}`}>
        {value}
        {hint && <span className="text-ink-faint"> {hint}</span>}
      </dd>
    </div>
  )
}
