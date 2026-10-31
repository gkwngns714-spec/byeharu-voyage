import { useState, type ReactNode } from 'react'
import { Icon } from './Icon'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A SECONDARY SECTION, FOLDED — one line and its figure, closed until asked (owner, 2026-10-31)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner's two briefs meet here: *"i hate to scroll down on things, make it so that all the
// info is packed on one page"* and *"make things foldable"*. A long secondary block (the world's
// new money, the best and worst companies, a list you consult rather than play) stands as ONE
// 44-px line with its key figure; the block itself is one press away, never gone.
//
// THE PRESS LAW (rows 6/15/25/28/45). The control turns its OWN glyph and reveals its OWN body
// directly under itself. Nothing above it moves, and the control does not change height when it
// opens — the content FOLLOWS it down, which is what an unfold is. This is the same law
// `Trade.tsx`'s MapFold and `SheetSection` already keep; the fold is a section primitive rather
// than a per-screen hand-rolled toggle.
//
// CLOSED BY DEFAULT, and the summary must carry the number that makes it worth opening. A fold
// whose closed line says only its title is a door with nothing written on it.

export function SectionFold({
  heading,
  summary,
  defaultOpen = false,
  children,
  className = '',
  ...rest
}: {
  /** The section's name, in the same voice as `SheetSection`'s heading. */
  heading: ReactNode
  /** The one line that stands in the closed state — the block's key figure. */
  summary?: ReactNode
  defaultOpen?: boolean
  children: ReactNode
  className?: string
} & { 'data-testid'?: string }) {
  const [open, setOpen] = useState(defaultOpen)
  return (
    <section className={`mt-4 first:mt-2 ${className}`} data-open={open ? 'true' : 'false'} {...rest}>
      <button
        type="button"
        aria-expanded={open}
        onClick={() => setOpen((o) => !o)}
        data-testid={rest['data-testid'] === undefined ? undefined : `${rest['data-testid']}-toggle`}
        className="flex min-h-11 w-full items-center justify-between gap-3 rounded-control bg-surface-2 px-3 py-1 text-left transition hover:text-ink"
      >
        <span className="min-w-0 break-words text-t-body font-semibold text-ink">{heading}</span>
        <span className="flex shrink-0 items-center gap-2 text-t-caption tabular-nums text-ink-muted">
          {summary}
          <Icon name="chevron" size={16} className={`transition ${open ? 'rotate-90' : ''}`} />
        </span>
      </button>
      {open && <div className="mt-2">{children}</div>}
    </section>
  )
}
