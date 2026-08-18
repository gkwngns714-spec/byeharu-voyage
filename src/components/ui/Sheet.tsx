import { useEffect, type ReactNode } from 'react'
import { Button } from './Button'
import { Icon } from './Icon'

// Design-system Sheet — the ONE dismissible overlay surface (detail of a port, a confirm step, a
// long report). A plain positioned <div> stack, never a platform modal component: byeharu's rule
// (no React Native <Modal>, keyboard bugs) carries over as "we own the overlay", and on web it
// also keeps the sheet inside our own token/stacking world.
//
// MOBILE-FIRST: it rises from the bottom edge and caps at 85dvh, so a thumb can reach its header
// and its content scrolls INSIDE it. At sm+ it centers as a dialog.
//
// Dismissal, three ways, all present: the close button, the backdrop, and Escape. A sheet that can
// only be closed by finding the right pixel is a trap on a phone.

export function Sheet({
  open,
  onClose,
  title,
  eyebrow,
  footer,
  children,
  'data-testid': testId,
}: {
  open: boolean
  onClose: () => void
  title: ReactNode
  eyebrow?: ReactNode
  /** Pinned action row — it sits OUTSIDE the scrolling body, so a control can never scroll away. */
  footer?: ReactNode
  children: ReactNode
  'data-testid'?: string
}) {
  useEffect(() => {
    if (!open) return
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [open, onClose])

  if (!open) return null

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center sm:items-center" data-testid={testId}>
      {/* Backdrop: a real button so it is keyboard-reachable and screen-reader-labelled. */}
      <button
        type="button"
        aria-label="Close"
        onClick={onClose}
        className="absolute inset-0 bg-app/70 backdrop-blur-sm"
      />
      <div
        role="dialog"
        aria-modal="true"
        className="relative flex max-h-[85dvh] w-full max-w-lg flex-col rounded-t-card border border-edge bg-surface shadow-overlay sm:rounded-card"
      >
        <header className="flex shrink-0 items-start justify-between gap-3 border-b border-edge px-4 py-3">
          <div className="min-w-0">
            {eyebrow && (
              <p className="mb-0.5 font-mono text-xs uppercase tracking-wider text-ink-faint">{eyebrow}</p>
            )}
            <h2 className="font-serif text-lg font-semibold text-ink">{title}</h2>
          </div>
          <Button variant="ghost" size="icon" aria-label="Close" onClick={onClose} className="shrink-0">
            <Icon name="close" size={18} />
          </Button>
        </header>
        <div className="min-h-0 flex-1 overflow-y-auto px-4 py-4">{children}</div>
        {footer && <div className="shrink-0 border-t border-edge px-4 py-3">{footer}</div>}
      </div>
    </div>
  )
}
