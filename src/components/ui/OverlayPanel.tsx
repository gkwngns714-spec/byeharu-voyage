import type { HTMLAttributes } from 'react'
import { overlayPanelClass, type OverlaySlot, type OverlayTone } from './overlayLayout'

// Design-system OverlayPanel — the ONE floating chrome over a chart/figure (legend, scale, a
// count of fleets at sea). Give it a `slot` to self-position in a corner of a `relative` box.
// Pointer-transparent by DEFAULT (`inert`), because the map is read-only and its chrome must never
// intercept a gesture; pass inert={false} only for a genuinely interactive overlay.

export function OverlayPanel({
  tone = 'default',
  slot,
  inert = true,
  className = '',
  children,
  ...rest
}: Omit<HTMLAttributes<HTMLDivElement>, 'slot'> & { tone?: OverlayTone; slot?: OverlaySlot; inert?: boolean }) {
  return (
    <div className={overlayPanelClass(tone, slot, className, inert)} {...rest}>
      {children}
    </div>
  )
}
