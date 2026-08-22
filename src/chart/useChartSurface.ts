import {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
  type PointerEvent as ReactPointerEvent,
  type RefObject,
} from 'react'
import { project, type GeoBounds, type LatLon, type Point, type ViewBox } from '../lib/geo'
import {
  clampView,
  fitView,
  panBy,
  unitsPerPixel,
  viewBoxOf,
  zoomAt,
  ZOOM_STEP,
  type ChartView,
} from './chartView'
import { useElementSize } from './useElementSize'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE CHART SURFACE — the element's size, the view, and the ONLY three gestures the map
// understands: drag to pan, wheel or pinch to zoom, and the +/−/all controls.
//
// DESIGN §E.5 allows exactly this and no more. There is no drag-to-target, no long-press, no
// context menu, no click-to-sail. A TAP is handled outside this hook and does one thing: it
// selects, which changes what the corner panel READS, and nothing else.
//
// ── THE VIEW IS DERIVED, NOT SYNCHRONISED ──────────────────────────────────────────────────────
// State holds only the view the player DELIBERATELY moved to. Everything else — the opening frame,
// and re-fitting when the phone rotates — is computed during render from the measured box. So
// there is no effect writing state back into the component, no first frame with the wrong view,
// and no way for the two to disagree. `fitView` and `clampView` are pure (./chartView.ts).
//
// The element ref is OWNED BY THE CALLER and passed in rather than created here and handed back:
// a ref returned inside a result object makes every later read of that object look, to the
// react-hooks rules, like touching a ref during render. The caller holds the ref, the hook holds
// the behaviour.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/** How far a pointer may travel and still count as a tap rather than a drag. Below the usual 10 px
 *  slop because this surface has no other gesture for it to be confused with. */
const TAP_SLOP_PX = 5

/**
 * Chrome that sits INSIDE the chart box but is not the chart: the two corner panels and the view
 * controls. Anything under this attribute is invisible to every gesture here.
 *
 * THE BUG THIS PREVENTS. The panels are absolutely positioned children of the gesture surface, so
 * a press on a fleet row is also a press on the chart: it would start a pan, and lifting would
 * count as a tap and hit-test whatever port happens to lie under the panel. One guard, checked in
 * all three pointer handlers and in the wheel listener, is the whole fix — as against
 * stopPropagation sprinkled over every panel, which is the same rule written five times and is one
 * forgotten call away from the bug coming back.
 */
const CHROME_ATTR = 'data-chart-chrome'

/** Marks an element as chrome. Spread onto a panel root: `<div {...CHART_CHROME}>`. */
export const CHART_CHROME = { [CHROME_ATTR]: '' } as const

function isChrome(target: EventTarget | null): boolean {
  return target instanceof Element && target.closest(`[${CHROME_ATTR}]`) !== null
}

export interface ChartSurface {
  /** Measured CSS pixels. Zero until the first layout. */
  readonly width: number
  readonly height: number
  /** Null until the surface has been measured. */
  readonly view: ChartView | null
  /** The SVG viewBox for the current view, or null. */
  readonly viewBox: ViewBox | null
  /** Chart units per CSS pixel — multiply by this to keep a glyph a constant size on screen. */
  readonly unitsPerPx: number
  readonly zoomIn: () => void
  readonly zoomOut: () => void
  /** Back to the opening frame. */
  readonly fit: () => void
  /** Put a place in the middle of the glass, at the current zoom. A VIEW change and nothing else —
   *  it is how the fleet list reaches a fleet the opening frame does not happen to contain. */
  readonly centreOn: (at: LatLon) => void
  readonly handlers: {
    onPointerDown: (e: ReactPointerEvent<HTMLDivElement>) => void
    onPointerMove: (e: ReactPointerEvent<HTMLDivElement>) => void
    onPointerUp: (e: ReactPointerEvent<HTMLDivElement>) => void
    onPointerCancel: (e: ReactPointerEvent<HTMLDivElement>) => void
  }
}

export function useChartSurface(
  ref: RefObject<HTMLDivElement | null>,
  /** The opening frame, as a function of the surface's aspect ratio — the same port set is a good
   *  frame on a laptop and a bad one on a phone, so this is asked, not stored (see openingBounds).
   *  Must be stable: wrap it in useCallback. */
  frameBounds: (aspect: number) => GeoBounds,
  /**
   * Called when a pointer goes down and up WITHOUT panning. A drag that ends over a glyph is a pan,
   * never a tap. It is handed three things, and they are the complete answer to "what did they
   * tap":
   *   `at`          where the finger landed, in chart units
   *   `unitsPerPx`  the scale at that moment, so a reach in PIXELS becomes one in chart units
   *                 without the caller holding a copy of the scale
   *   `view`        the viewBox that was on the glass, so the caller can work out what was DRAWN
   *                 at that instant. With 214 ports in the table, only the drawn ones are tappable
   *                 — and passing the box is what lets the caller apply the SAME visibility rule
   *                 the render used, without a ref into render state and without depending on this
   *                 hook's own result to build the handler it is given.
   */
  onTap?: (at: Point, unitsPerPx: number, view: ViewBox) => void,
): ChartSurface {
  // ── measure ───────────────────────────────────────────────────────────────────────────────────
  // ./useElementSize.ts, because the small chart needs the same two numbers and must not mount this
  // hook to get them (its non-passive wheel listener would eat the page scroll under a chart that
  // is embedded in a form).
  const size = useElementSize(ref)
  /** Only what the player moved to. `null` = they have not moved it, so the opening frame stands. */
  const [movedTo, setMovedTo] = useState<ChartView | null>(null)

  const pointers = useRef(new Map<number, { x: number; y: number }>())
  const travelled = useRef(0)

  const measured = size.width > 0 && size.height > 0
  const aspect = measured ? size.width / size.height : 1

  /** The view as it is right now: what the player moved to, or the opening frame — always clamped
   *  to the CURRENT aspect, so a rotation re-frames instead of stretching. */
  const view = useMemo(
    () => (measured ? clampView(movedTo ?? fitView(frameBounds(aspect), aspect), aspect) : null),
    [measured, movedTo, frameBounds, aspect],
  )

  /** What a gesture starts from. Resolving `null` here rather than through a ref keeps every
   *  handler working off the LATEST committed view, so a fast drag cannot drop motion between
   *  renders. */
  const from = useCallback(
    (previous: ChartView | null, surfaceAspect: number): ChartView =>
      previous ?? fitView(frameBounds(surfaceAspect), surfaceAspect),
    [frameBounds],
  )

  // ── wheel (and the trackpad pinch, which arrives as ctrlKey + wheel) ──────────────────────────
  // Attached natively because it must be non-passive: a chart that scrolls the page under the
  // player's finger while they zoom is unusable, and React's onWheel cannot say preventDefault.
  useEffect(() => {
    const element = ref.current
    if (!element) return
    const onWheel = (event: WheelEvent) => {
      // A wheel over a panel scrolls that panel; it does not zoom the chart underneath it.
      if (isChrome(event.target)) return
      event.preventDefault()
      const rect = element.getBoundingClientRect()
      if (rect.width <= 0 || rect.height <= 0) return
      const surfaceAspect = rect.width / rect.height
      const lineHeight = event.deltaMode === 1 ? 16 : event.deltaMode === 2 ? rect.height : 1
      const factor = Math.exp((-event.deltaY * lineHeight) / 400)
      const u = (event.clientX - rect.left) / rect.width
      const v = (event.clientY - rect.top) / rect.height
      setMovedTo((previous) => zoomAt(from(previous, surfaceAspect), surfaceAspect, factor, u, v))
    }
    element.addEventListener('wheel', onWheel, { passive: false })
    return () => element.removeEventListener('wheel', onWheel)
  }, [ref, from])

  // ── pointers: one finger pans, two pinch ──────────────────────────────────────────────────────
  const onPointerDown = useCallback((event: ReactPointerEvent<HTMLDivElement>) => {
    if (isChrome(event.target)) return
    if (pointers.current.size === 0) travelled.current = 0
    pointers.current.set(event.pointerId, { x: event.clientX, y: event.clientY })
    event.currentTarget.setPointerCapture(event.pointerId)
  }, [])

  const onPointerMove = useCallback(
    (event: ReactPointerEvent<HTMLDivElement>) => {
      if (isChrome(event.target)) return
      const previousPoint = pointers.current.get(event.pointerId)
      if (!previousPoint) return
      const element = ref.current
      if (!element) return
      const rect = element.getBoundingClientRect()
      if (rect.width <= 0 || rect.height <= 0) return

      const nextPoint = { x: event.clientX, y: event.clientY }
      const others = [...pointers.current.entries()].filter(([id]) => id !== event.pointerId)
      pointers.current.set(event.pointerId, nextPoint)

      const surfaceAspect = rect.width / rect.height
      travelled.current += Math.hypot(nextPoint.x - previousPoint.x, nextPoint.y - previousPoint.y)

      if (others.length === 0) {
        setMovedTo((previous) => {
          const base = from(previous, surfaceAspect)
          const perPixel = unitsPerPixel(base, rect.width)
          return panBy(
            base,
            surfaceAspect,
            (nextPoint.x - previousPoint.x) * perPixel,
            (nextPoint.y - previousPoint.y) * perPixel,
          )
        })
        return
      }

      // Pinch: hold the other finger still and read the change in separation about the midpoint.
      const other = others[0][1]
      const before = Math.hypot(previousPoint.x - other.x, previousPoint.y - other.y)
      const after = Math.hypot(nextPoint.x - other.x, nextPoint.y - other.y)
      if (!(before > 0) || !(after > 0)) return
      const midBefore = { x: (previousPoint.x + other.x) / 2, y: (previousPoint.y + other.y) / 2 }
      const midAfter = { x: (nextPoint.x + other.x) / 2, y: (nextPoint.y + other.y) / 2 }

      setMovedTo((previous) => {
        const base = from(previous, surfaceAspect)
        const perPixel = unitsPerPixel(base, rect.width)
        const panned = panBy(
          base,
          surfaceAspect,
          (midAfter.x - midBefore.x) * perPixel,
          (midAfter.y - midBefore.y) * perPixel,
        )
        const u = (midAfter.x - rect.left) / rect.width
        const v = (midAfter.y - rect.top) / rect.height
        return zoomAt(panned, surfaceAspect, after / before, u, v)
      })
    },
    [ref, from],
  )

  const endPointer = useCallback(
    (event: ReactPointerEvent<HTMLDivElement>) => {
      if (isChrome(event.target)) return
      pointers.current.delete(event.pointerId)
      if (event.currentTarget.hasPointerCapture(event.pointerId)) {
        event.currentTarget.releasePointerCapture(event.pointerId)
      }
      // A TAP: the last finger lifted, and the gesture never travelled far enough to be a pan.
      // A cancelled pointer is never a tap.
      if (
        event.type !== 'pointerup' ||
        pointers.current.size > 0 ||
        travelled.current > TAP_SLOP_PX ||
        !onTap ||
        !view
      ) {
        return
      }
      const element = ref.current
      if (!element) return
      const rect = element.getBoundingClientRect()
      if (rect.width <= 0 || rect.height <= 0) return
      const box = viewBoxOf(view, rect.width / rect.height)
      onTap(
        {
          x: box.x + ((event.clientX - rect.left) / rect.width) * box.width,
          y: box.y + ((event.clientY - rect.top) / rect.height) * box.height,
        },
        unitsPerPixel(view, rect.width),
        box,
      )
    },
    [ref, onTap, view],
  )

  // ── the three controls ────────────────────────────────────────────────────────────────────────
  const zoomBy = useCallback(
    (factor: number) => setMovedTo((previous) => zoomAt(from(previous, aspect), aspect, factor, 0.5, 0.5)),
    [aspect, from],
  )
  const zoomIn = useCallback(() => zoomBy(ZOOM_STEP), [zoomBy])
  const zoomOut = useCallback(() => zoomBy(1 / ZOOM_STEP), [zoomBy])
  // "Fit" returns to the opening frame by FORGETTING the moves, not by storing a copy of it — so
  // there is only ever one definition of where the chart opens.
  const fit = useCallback(() => setMovedTo(null), [])

  const centreOn = useCallback(
    (at: LatLon) => {
      const point = project(at)
      setMovedTo((previous) =>
        clampView({ cx: point.x, cy: point.y, spanX: from(previous, aspect).spanX }, aspect),
      )
    },
    [aspect, from],
  )

  return {
    width: size.width,
    height: size.height,
    view,
    viewBox: view ? viewBoxOf(view, aspect) : null,
    unitsPerPx: view ? unitsPerPixel(view, size.width) : 1,
    zoomIn,
    zoomOut,
    fit,
    centreOn,
    handlers: {
      onPointerDown,
      onPointerMove,
      onPointerUp: endPointer,
      onPointerCancel: endPointer,
    },
  }
}
