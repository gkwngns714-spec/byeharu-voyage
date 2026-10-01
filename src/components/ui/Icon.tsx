import type { SVGAttributes } from 'react'
import { ICON_PATHS, type IconName } from './icons'

// Design-system Icon: the ONE inline-SVG line-icon set (glyph data in ./icons.ts). Strokes with
// `currentColor`, so color always comes from token text utilities on the parent or via className
// (text-accent, text-ink-muted, …) — never per-icon palettes. Decorative by default (aria-hidden);
// spread an explicit aria-label + aria-hidden={false} when an icon is meaning-bearing.

export function Icon({
  name,
  size = 20,
  className = '',
  ...rest
}: Omit<SVGAttributes<SVGSVGElement>, 'name'> & { name: IconName; size?: number }) {
  return (
    <svg
      viewBox="0 0 24 24"
      width={size}
      height={size}
      fill="none"
      stroke="currentColor"
      strokeWidth={1.5}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      className={className}
      {...rest}
    >
      {ICON_PATHS[name].map((d) => (
        <path key={d} d={d} />
      ))}
    </svg>
  )
}

/** The meanings a disc may carry, plus the quiet default — the same names `Figure` speaks. */
export type IconDiscTone = 'muted' | 'accent' | 'success' | 'warning' | 'danger' | 'info'

const DISC_TONE: Record<IconDiscTone, string> = {
  muted: 'text-ink-muted',
  accent: 'text-accent',
  success: 'text-success',
  warning: 'text-warning',
  danger: 'text-danger',
  info: 'text-info',
}

/**
 * A ROW'S MARK AS A DISC — an `Icon` seated on a 32px `surface-2` circle (2026-10-01, owner: "it
 * is like a text game"). History, Fleets and Command led every line with a bare clock, a 10px dot
 * or nothing, so the eye had no anchor and every row was a sentence. The disc is the anchor: the
 * same stroke set, on the inset tone §4.4 gives a chip at rest, coloured only by a meaning the
 * caller already holds (a fleet's status tone — never decoration). 32px sits inside the 52px row,
 * so a row that gains one grows by nothing. ONE recipe, here, so no screen hand-rolls a circle.
 */
export function IconDisc({
  name,
  tone = 'muted',
  label,
}: {
  name: IconName
  tone?: IconDiscTone
  /** Set when the disc carries meaning on its own (a status); otherwise it is decoration. */
  label?: string
}) {
  return (
    <span
      className={`flex h-8 w-8 shrink-0 items-center justify-center rounded-chip bg-surface-2 ${DISC_TONE[tone]}`}
      role={label === undefined ? undefined : 'img'}
      aria-label={label}
    >
      <Icon name={name} size={18} />
    </span>
  )
}
