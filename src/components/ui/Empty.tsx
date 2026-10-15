import type { ReactNode } from 'react'

// THE EMPTY WELL — "nothing here yet", said once, in the caption voice, on the quiet surface.
//
// The ship panel ("Nothing fitted.") and the trade history ("No trades are held for these laps.")
// each hand-wrote this recipe, and tests/duplication.spec.ts caught the two copies (2026-10-16).
// It lives here so a third empty list asks for it instead of writing a third copy. Spacing around
// it is the caller's: pass `className` (e.g. `mt-2`), never a second recipe.
export function Empty({
  children,
  className = '',
  ...rest
}: {
  children: ReactNode
  className?: string
} & { 'data-testid'?: string }) {
  return (
    <p className={`rounded-control bg-surface-2 px-3 py-3 text-t-caption text-ink-faint ${className}`} {...rest}>
      {children}
    </p>
  )
}
