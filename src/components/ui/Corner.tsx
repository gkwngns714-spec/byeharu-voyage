import { useState, type ReactNode } from 'react'
import { Icon } from './Icon'

// THE CORNER — chrome that floats over the world, and never in the middle of it.
//
// The owner's map rules (docs/OWNER_REQUESTS.md, and the map-UX principles the audit restates in
// §4): a clean map, controls in the CORNERS and never the centre, foldable and dismissible. This
// is that shape as a primitive, and it replaces `OverlayPanel` + `overlayLayout.ts`'s five
// spellings + `MapPanel`'s absolutely-positioned close button laid over a `Collapsible`'s header.
//
// TWO PER SCREEN, MAXIMUM. Not enforced in code — a count in a component is a lint that lies the
// day a screen has a reason — but stated here because it is the whole point: the map's chrome is a
// fleet pill in one corner and the zoom controls in the other, and a third would be a toolbar.
//
// THE GLASS IS THE SECOND OF §4.3's TWO ELEVATIONS: a 70%-alpha `surface` with a 16px backdrop
// blur and `--shadow-float` casting DOWN, as against the docked `Tray`, which casts UP from the
// bottom edge. There is no third elevation and no card shadow — `--shadow-card` is `none` in the
// token layer precisely so that thirty-three drop-shadowed boxes cannot come back.
//
// IT FOLDS RATHER THAN CLOSING. A corner panel that can be dismissed outright is a control the
// player can lose; folded, it is a 44px header that says what is inside it and opens on a tap.

export type CornerSlot = 'top-left' | 'top-right' | 'bottom-left' | 'bottom-right'

const SLOT: Record<CornerSlot, string> = {
  'top-left': 'left-3 top-3',
  'top-right': 'right-3 top-3',
  'bottom-left': 'bottom-3 left-3',
  'bottom-right': 'bottom-3 right-3',
}

export function Corner({
  slot,
  label,
  mark,
  defaultOpen = false,
  children,
  className = '',
  ...rest
}: {
  slot: CornerSlot
  /** What is inside, in two words. It is the folded state's whole face. */
  label: ReactNode
  /** An `Icon` or a `Figure` that stands for the panel when it is folded. */
  mark?: ReactNode
  defaultOpen?: boolean
  /** Omit for a panel that is only ever its own header — the map's `⛵ 1` pill. */
  children?: ReactNode
  className?: string
} & { 'data-testid'?: string }) {
  const [open, setOpen] = useState(defaultOpen)
  const foldable = children !== undefined

  return (
    <div
      className={[
        'absolute z-30 max-w-[70%] overflow-hidden rounded-tile bg-surface/70 shadow-float backdrop-blur-lg',
        SLOT[slot],
        className,
      ].join(' ')}
      {...rest}
    >
      <button
        type="button"
        aria-expanded={foldable ? open : undefined}
        onClick={() => foldable && setOpen((v) => !v)}
        className="flex h-11 w-full items-center gap-2 px-3 text-left text-t-caption text-ink-muted"
      >
        {mark}
        <span className="min-w-0 flex-1 truncate">{label}</span>
        {foldable && (
          <Icon
            name="chevron"
            size={16}
            className={`shrink-0 text-ink-faint transition-transform ${open ? '-rotate-90' : 'rotate-90'}`}
          />
        )}
      </button>
      {foldable && open && <div className="max-h-64 overflow-y-auto px-3 pb-3">{children}</div>}
    </div>
  )
}
