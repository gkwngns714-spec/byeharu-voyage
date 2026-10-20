import { useRef, type ReactNode } from 'react'
import { useDismiss } from './useDismiss'

// THE POPOVER — a compact panel hung under the control that opened it, on a wide glass.
//
// The `Tray` is the one answer to "unfold under the press" on a phone: fixed at the bottom edge, it
// moves nothing. On a wide glass a header control (the COMMAND desk's fleet picker, 2026-10-20)
// wants the same promise in a smaller shape: a list hung directly under the button, over the panes,
// gone on a press outside or Escape. That is this. It is `absolute` under a `relative` wrapper, so
// — like the docked tray — it is out of the flow by construction and cannot move a row (the owner's
// rule, docs/OWNER_REQUESTS.md rows 6/15/25/28/45).
//
// NO SCRIM, for the Tray's reason: the world behind is not disabled. The glass is §4.3's floating
// elevation — `surface-2` with `--shadow-float` casting down — the same step the `Corner` takes,
// and the tile radius. It is a region over the page, not a modal: `role="dialog"` with
// `aria-modal={false}`, as the Tray declares itself.
//
// WHO USES IT: a control whose list is short (a handful of fleets) and whose caller is a header,
// where a side panel would be a screen and a tray would be at the wrong edge. A list that can grow
// long, or an act with a primary button, is a Tray. On a phone the caller mounts a Tray instead
// (`useWide()` decides); this primitive does not switch by itself, so each caller says which shape
// it takes where, once.

export function Popover({
  open,
  onClose,
  trigger,
  label,
  children,
  className = '',
  ...rest
}: {
  open: boolean
  onClose: () => void
  /** The control the panel hangs under. Its press is the caller's; a press on it is never "outside". */
  trigger: ReactNode
  /** Names the panel for assistive tech ("Fleets"). Not painted. */
  label: string
  children: ReactNode
  /** The panel's own width and padding, e.g. `w-80 px-4`. */
  className?: string
} & { 'data-testid'?: string }) {
  const box = useRef<HTMLDivElement | null>(null)
  useDismiss(open, box, onClose)
  return (
    <div ref={box} className="relative inline-flex min-w-0 items-center">
      {trigger}
      {open && (
        <div
          role="dialog"
          aria-modal={false}
          aria-label={label}
          data-popover=""
          className={`absolute left-0 top-full z-40 mt-1 rounded-tile bg-surface-2 shadow-float ${className}`}
          {...rest}
        >
          {children}
        </div>
      )}
    </div>
  )
}
