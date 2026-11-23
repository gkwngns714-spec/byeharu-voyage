import type { ReactNode } from 'react'
import { Icon } from './Icon'
import type { IconName } from './icons'

// THE EMPTY WELL — "nothing here yet", said once, in the caption voice, on the quiet surface.
//
// The ship panel ("Nothing fitted.") and the trade history ("No trades are held for these laps.")
// each hand-wrote this recipe, and tests/duplication.spec.ts caught the two copies (2026-10-16).
// It lives here so a third empty list asks for it instead of writing a third copy. Spacing around
// it is the caller's: pass `className` (e.g. `mt-2`), never a second recipe.
//
// A DRAWN MARK OVER ONE SHORT LINE (2026-11-23, visual pass 2: "empty-state screens that are just a sentence"). With `icon`, the well
// stands its glyph on a disc over the line, centred, so an empty card reads as a picture of what would be there (a crate for an empty
// store, a tricorne for no captains) rather than as a grey sentence. The line stays the one sentence it was; the mark adds no word.
export function Empty({
  children,
  icon,
  className = '',
  ...rest
}: {
  children: ReactNode
  /** The glyph of what would stand here (`icons.ts`): drawn on a disc over the line. Unset, the well is the line alone. */
  icon?: IconName
  className?: string
} & { 'data-testid'?: string }) {
  if (icon === undefined) {
    return (
      <p className={`rounded-control bg-surface-2 px-3 py-3 text-t-caption text-ink-faint ${className}`} {...rest}>
        {children}
      </p>
    )
  }
  return (
    <div className={`flex flex-col items-center gap-2 rounded-control bg-surface-2 px-3 py-4 text-center ${className}`} data-empty-mark={icon} {...rest}>
      <span className="flex h-11 w-11 items-center justify-center rounded-chip bg-surface text-ink-muted" aria-hidden="true">
        <Icon name={icon} size={24} strokeWidth={1.5} />
      </span>
      <p className="text-t-caption text-ink-muted">{children}</p>
    </div>
  )
}
