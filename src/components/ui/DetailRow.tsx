import type { HTMLAttributes, ReactNode } from 'react'
import { Explain } from './Explain'

// Design-system LABEL/VALUE row for a value that is a SENTENCE, not a number.
//
// ── WHY THIS EXISTS BESIDE StatRow, AND WHERE THE LINE IS ───────────────────────────────────────
// StatRow's own header states its remit: "The VALUE is mono by default: it is nearly always a
// number, and a column of numbers that does not line up cannot be read at a glance." It is a
// two-column, right-aligned row, and for a figure that is exactly right.
//
// It is exactly WRONG for prose. A right-aligned sentence that wraps leaves its tail alone on the
// next line, right-aligned, reading as a fragment. Measured at 390x844:
//
//   Development │ industry 12 · commerce 17
//               │                · military 8      <- "· military 8" reads as a stray line
//   Market tax  │ 4.0% set by the Mayor, banded
//               │                           0–8%
//   Funchal     │ 211% of its neighbours — the
//               │                       sell band
//
// So the rule is not "wrap better", it is: A VALUE THAT IS A SENTENCE IS LEFT-ALIGNED AND FLOWS AS
// A BLOCK. On a phone it sits under its label; from `sm` it takes a second column, still
// left-aligned, so the ragged edge is on the right where prose is supposed to have one.
//
//   StatRow   — short, numeric, right-aligned, mono. Columns of figures that must line up.
//   DetailRow — prose, left-aligned, flows. Sentences, lists, anything with a "·" in it.
//
// Two components, one decision each, and the boundary is written down so a caller never has to
// guess. Render inside a <dl>, as with StatRow.

export function DetailRow({
  label,
  value,
  hint,
  mono = false,
  className = '',
  ...rest
}: Omit<HTMLAttributes<HTMLDivElement>, 'children'> & {
  label: ReactNode
  /** The sentence. Wraps as a block; never right-aligned. */
  value: ReactNode
  /** The standing explanation of this value — units, provenance, the rule behind it. NOT PRINTED:
   *  it goes behind the ⓘ that trails the value, and appears when the player taps it (Explain.tsx).
   *  Never put a live figure here; the row's `value` is where anything current belongs. */
  hint?: ReactNode
  /** Set when the value is prose ABOUT figures ("water 3 d./t · food 12 d./t") and the digits
   *  should still be tabular. Alignment does not change; only the face does. */
  mono?: boolean
}) {
  return (
    <div
      // grid, not flex+justify-between: the label column is a fixed measure, so every row's value
      // starts on the same x — which is the alignment a reader actually uses — and the value column
      // is `minmax(0,1fr)` so a long word wraps instead of pushing the row wide.
      className={`grid gap-x-3 gap-y-0.5 py-0.5 text-sm sm:grid-cols-[minmax(0,8.5rem)_minmax(0,1fr)] ${className}`}
      {...rest}
    >
      <dt className="text-ink-faint">{label}</dt>
      <dd className={`min-w-0 text-left text-ink ${mono ? 'font-mono text-[13px]' : ''}`}>
        {value}
        {hint && (
          <Explain label={typeof label === 'string' ? label : undefined} dotClassName="ml-1">
            {hint}
          </Explain>
        )}
      </dd>
    </div>
  )
}
