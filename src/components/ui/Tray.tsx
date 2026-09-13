import { useRef, useState, type PointerEvent as ReactPointerEvent, type ReactNode } from 'react'
import { Icon } from './Icon'
import { detentHeight, nearestDetent, stepDetent, TRAY_PEEK, type TrayDetent } from './trayDetents'
import { trayDockWideClass } from './screenLayout'
import { useWide } from './useWide'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE TRAY — the load-bearing primitive of the whole direction
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// EVERY "unfold under the press" in this game becomes this: the quantity step, the passage check,
// the queue, a fleet's detail, a port's detail on the map, a captain's entry, a refusal's fixes.
// It retires `OverlayPanel`+`MapPanel` in the bottom slot, the `Explain`/`ExplainPanel` disclosure
// (long text opens a tray), the inline `GoodDetail` fold and `sailConfirm`, and — with them — the
// row arithmetic that existed only to place a fold safely: `inRowsOf`, `useTileCols`, `tileLayout`.
//
// ── THE OWNER'S RULE, WHICH THIS EXISTS TO KEEP ABSOLUTELY ─────────────────────────────────────
// Said three times, and built backwards twice (docs/OWNER_REQUESTS.md rows 6, 15, 25, 28, 45):
//
//     "when pressing sail, stop folding the sail … don't restruct anything."
//     "Pressing a control SELECTS. It never collapses, re-flows, replaces or destroys the surface
//      it was pressed on."
//
// A DOCKED TRAY KEEPS THAT BY CONSTRUCTION RATHER THAN BY CARE. It is `position: fixed`, so it is
// not in the grid's flow, so opening it cannot move a single tile — not the pressed tile, not its
// row-mate, not the tile above. The old answer (insert the fold after the whole row) needed to
// KNOW where a row ended, which is why the column count was computed in JavaScript in three
// places. This answer needs to know nothing. tests/primitives.geometry.spec.ts records every
// tile's offset, opens a tray, and requires the offsets to be identical.
//
// There is deliberately NO SCRIM. A scrim would say "the world behind is disabled", and it is not:
// the whole point of a peek is that you can tap the next good, or the next port, with the tray
// standing. It also means the tray can never intercept a gesture meant for the chart.
//
// ── `inline` IS THE OTHER ANSWER TO THE SAME RULE, AND IT IS BUILT ─────────────────────────────
// §7 states the open question honestly: the tray keeps the second half of the owner's rule
// absolutely, and changes the first half from *inline under the row* to *docked at the bottom
// edge*. The owner has not chosen. So both are here, as one component and one detent ladder:
//   · `mode="docked"` — `fixed` at the bottom edge of the glass. Nothing reflows, ever.
//   · `mode="inline"` — in flow, immediately after whatever the caller placed it after. What is
//     BELOW it moves down (that is what an unfold IS); nothing at or above it moves, which is the
//     half of the rule that was ever really at stake.
// The plan survives either answer because every screen composes `<Tray>` and passes a mode.
//
// ── DETENTS ────────────────────────────────────────────────────────────────────────────────────
// peek 96px · half 50% · full 100%, and the arithmetic is `trayDetents.ts` so it can be read and
// snapped to without a browser. The height is set in CSS units (`96px` / `50dvh` / `100dvh`) so
// the tray is correct before JavaScript measures anything and stays correct through a rotation;
// the JS mirror is used only while a finger is actually on the handle.
//
// ── CONTROLLED, WITH ONE PIECE OF STATE ────────────────────────────────────────────────────────
// `detent` and `onDetentChange`, and `closed` renders nothing. Not `open` + `detent`: two flags
// for one state is how a sheet ends up open at zero height, and this component is going to be
// mounted from nine screens.
//
// ── MOTION AND REACH ───────────────────────────────────────────────────────────────────────────
// The rise is `--duration-sheet` on `--ease-sheet` (240ms, §4.6), which `prefers-reduced-motion`
// already collapses to 0ms at the bottom of src/index.css — so there is no media query here and
// nothing to keep in step. The handle, the close button and the pinned action all clear 44px.

export type { TrayDetent } from './trayDetents'

const HEIGHT: Record<Exclude<TrayDetent, 'closed'>, string> = {
  peek: `${TRAY_PEEK}px`,
  half: '50dvh',
  full: '100dvh',
}

export function Tray({
  detent,
  onDetentChange,
  title,
  mode = 'docked',
  action,
  children,
  className = '',
  ...rest
}: {
  detent: TrayDetent
  onDetentChange: (next: TrayDetent) => void
  /** What was tapped. `t-title`, one line, never a sentence. */
  title: ReactNode
  mode?: 'docked' | 'inline'
  /** The ONE primary button, pinned to the bottom edge and never inside the scroll. */
  action?: ReactNode
  children?: ReactNode
  className?: string
} & { 'data-testid'?: string }) {
  // While a finger is on the handle the height is a number of pixels and the transition is off;
  // the rest of the time it is one of the three CSS stops above.
  const [dragHeight, setDragHeight] = useState<number | null>(null)
  const drag = useRef<{ startY: number; startHeight: number } | null>(null)
  // ON A WIDE GLASS A DOCKED TRAY IS A SIDE PANEL (screenLayout.ts, "the wide glass"): it stands
  // beside the column at full height, so the detent ladder — a bottom-edge idea — does not apply.
  // `detent` still says open or closed; the height is the panel's.
  const side = useWide() && mode === 'docked'

  if (detent === 'closed') return null

  const container = () =>
    mode === 'docked' ? window.innerHeight : document.documentElement.clientHeight

  const onPointerDown = (e: ReactPointerEvent<HTMLButtonElement>) => {
    e.currentTarget.setPointerCapture(e.pointerId)
    drag.current = { startY: e.clientY, startHeight: detentHeight(detent, container()) }
    setDragHeight(detentHeight(detent, container()))
  }
  const onPointerMove = (e: ReactPointerEvent<HTMLButtonElement>) => {
    if (!drag.current) return
    const h = drag.current.startHeight + (drag.current.startY - e.clientY)
    setDragHeight(Math.max(0, Math.min(container(), h)))
  }
  const onPointerUp = () => {
    if (!drag.current) return
    const landed = nearestDetent(dragHeight ?? drag.current.startHeight, container())
    drag.current = null
    setDragHeight(null)
    if (landed !== detent) onDetentChange(landed)
  }

  const height = side ? undefined : dragHeight !== null ? `${dragHeight}px` : HEIGHT[detent]

  return (
    <section
      role="dialog"
      aria-modal={false}
      aria-label={typeof title === 'string' ? title : undefined}
      data-tray-mode={mode}
      data-tray-detent={detent}
      style={{ height, transitionDuration: dragHeight !== null ? '0ms' : undefined }}
      className={[
        'z-40 flex flex-col overflow-hidden rounded-t-sheet bg-surface shadow-sheet',
        'transition-[height] duration-sheet ease-sheet',
        mode === 'docked' ? `fixed inset-x-0 bottom-0 ${trayDockWideClass()}` : 'relative w-full',
        className,
      ].join(' ')}
      {...rest}
    >
      {/* THE HANDLE IS THE DRAG SURFACE AND A REAL CONTROL. A grab bar that only responds to a
          pointer is unreachable from a keyboard, so it is a button: ↑ and ↓ step the detent
          ladder, which is the same ladder the drag snaps to. */}
      <div className="flex items-center gap-2 px-gutter pt-2">
        {/* A side panel has nothing to drag: the handle gives way to a spacer and the close button
            keeps its place at the right. */}
        {side ? (
          <span className="flex-1" />
        ) : (
          <button
            type="button"
            aria-label="Resize"
            onPointerDown={onPointerDown}
            onPointerMove={onPointerMove}
            onPointerUp={onPointerUp}
            onPointerCancel={onPointerUp}
            onKeyDown={(e) => {
              if (e.key === 'ArrowUp') onDetentChange(stepDetent(detent, 1))
              if (e.key === 'ArrowDown') onDetentChange(stepDetent(detent, -1))
            }}
            className="flex h-11 flex-1 cursor-grab touch-none items-center justify-center"
          >
            <span className="h-1 w-9 rounded-chip bg-ink-faint" />
          </button>
        )}
        <button
          type="button"
          aria-label="Close"
          data-testid="tray-close"
          onClick={() => onDetentChange('closed')}
          className="flex h-11 w-11 items-center justify-center rounded-control text-ink-muted"
        >
          <Icon name="close" size={20} />
        </button>
      </div>

      <h2 className="shrink-0 px-gutter pb-2 text-t-title">{title}</h2>

      {/* The one scrolling region. The action below it never enters this box, per §6's sketch:
          "the ONE primary button, always at the bottom edge, never in the scroll". */}
      <div className="min-h-0 flex-1 overflow-y-auto px-gutter pb-2">{children}</div>

      {action !== undefined && <div className="shrink-0 px-gutter pb-4 pt-2">{action}</div>}
    </section>
  )
}
