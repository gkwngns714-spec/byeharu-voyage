import type { ReactNode } from 'react'
import { Ring } from './Ring'
import { masteredTone } from './masteryStyles'

// A GOOD'S MASTERY (0479, roadmap 2026-11-23 slice 11; Melvor's mastery per item): ONE recipe for the level ring (and, in
// masteryStyles.ts, for a mastered good's name), so the logbook's slots, You's plate, the arrival card and the level-up toast draw it
// alike. Pure: the caller hands the served level and top; nothing is worked out here but the ring's share.

/** The level of a good as a ring that fills toward the top, its figure (or the caller's mark) in the middle. At the top the ring is
 *  whole and the figure gold. */
export function MasteryRing({
  level,
  top,
  size = 28,
  label,
  children,
  className = '',
  ...rest
}: {
  level: number
  top: number
  size?: number
  /** What the ring says to a screen reader: the good and its level. */
  label: string
  /** The mark in the middle; the level's figure when none. */
  children?: ReactNode
  className?: string
} & { 'data-testid'?: string; 'data-level'?: number }) {
  const at = top > 0 && level >= top
  return (
    <Ring pct={top > 0 ? (100 * level) / top : 0} size={size} track="edge" label={label} className={className} {...rest}>
      {children ?? (
        <span className={`text-t-caption leading-none tabular-nums ${masteredTone(at, 'font-semibold text-ink')}`}>{level}</span>
      )}
    </Ring>
  )
}
