import { Figure } from './Figure'
import type { BarTone } from './Bar'

// THE STACKED BAR — one whole, cut into the parts that make it up.
//
// WHY IT IS NOT `Bar`. `Bar` answers "how full is this one thing" (a hull, a hold) in one tone, and
// its segmented form counts things you can count (pips). This answers a different question — "who
// holds the world's money", "where are the merchants' fleets" — where the parts are DIFFERENT KINDS
// and the sum is the point. Folding a second meaning into `Bar` behind a flag is what
// docs/NO_SPAGHETTI.md §5 calls a third thing; two small components, one job each.
//
// THE PARTS ARE SEPARATED BY SURFACE, NOT BY A STROKE: a 2px gap of the sheet's own colour between
// segments, which is the one mechanism the house uses everywhere else (§4.3: "separation is by tone
// step", never a border). 8px tall rather than the 4px of a plain `Bar`, because four parts in a
// 4px track read as a dotted line.
//
// A LEGEND IS ALWAYS THERE when there are two or more parts, and it carries the figures: colour
// alone may not be the only channel that says which part is which (no reader of a greyscale
// screenshot, and no colourblind player, can match a swatch to a 14 % sliver). The words wear INK
// tokens; the colour lives on the swatch beside them, never on the text.

export interface StackedPart {
  id: string
  label: string
  value: number
  tone: BarTone
}

const FILL: Record<BarTone, string> = {
  accent: 'bg-accent',
  success: 'bg-success',
  warning: 'bg-warning',
  danger: 'bg-danger',
  info: 'bg-info',
  neutral: 'bg-ink-faint',
}

export function StackedBar({
  parts,
  format,
  label,
  legend = true,
  className = '',
  ...rest
}: {
  /** The parts in reading order, each with the tone it MEANS. A part of 0 is drawn as nothing and
   *  still listed in the legend — "the cities hold none" is an answer. */
  parts: readonly StackedPart[]
  /** How a part's figure reads in the legend (lib/format owns the spelling). */
  format: (v: number) => string
  /** The whole, named for assistive tech ("money in the world, by holder"). */
  label: string
  legend?: boolean
  className?: string
} & { 'data-testid'?: string }) {
  const total = parts.reduce((n, p) => n + Math.max(0, p.value), 0)
  if (parts.length === 0 || total <= 0) return null

  return (
    <div className={className} {...rest}>
      <div className="flex h-2 gap-0.5 overflow-hidden rounded-chip" role="img" aria-label={label}>
        {parts.map((p) => (
          <span
            key={p.id}
            className={`block h-full rounded-chip ${FILL[p.tone]}`}
            style={{ width: `${(Math.max(0, p.value) / total) * 100}%` }}
          />
        ))}
      </div>
      {legend && parts.length > 1 && (
        <div className="mt-2 flex flex-wrap gap-x-4 gap-y-1">
          {parts.map((p) => (
            <span key={p.id} className="inline-flex items-center gap-2">
              <span className={`inline-block h-2 w-2 shrink-0 rounded-full ${FILL[p.tone]}`} aria-hidden="true" />
              <span className="text-t-caption text-ink-muted">{p.label}</span>
              <Figure value={format(p.value)} />
            </span>
          ))}
        </div>
      )}
    </div>
  )
}
