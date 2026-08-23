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

/** A chrome rectangle in CSS pixels, measured from the surface's top-left corner. */
export interface ChromeBox {
  readonly x: number
  readonly y: number
  readonly width: number
  readonly height: number
}

/** One frozen empty list, so "no chrome" never allocates and never re-renders a consumer. */
const NO_CHROME: readonly ChromeBox[] = []

/**
 * WHERE THE CHROME IS, in the surface's own pixels — so a NAME is never printed under a button.
 *
 * THE DEFECT, measured at 390×844: `Saint-Malo` rendered as `Sain` and `Nantes` as a bare `s`,
 * because the zoom column is opaque and sat on top of them. Neither name was clipped by the
 * viewport — the label engine's edge rule had placed both entirely inside the glass, and the
 * measured count of edge-clipped labels was zero. They were painted underneath a control.
 * ./labels.ts carries the arithmetic and the rule that now refuses those placements.
 *
 * THIS IS THE DECLARATION THE GESTURES ALREADY READ. `CHART_CHROME` exists so that a press on a
 * panel does not pan the chart: it is the screen saying *this box is mine, and it is opaque*.
 * Asking that same marker where those boxes ARE composes an authority that exists rather than
 * adding a second one — as against a keep-out rectangle hand-written beside the zoom buttons, which
 * would be one more spelling of a corner `overlaySlotClass` already owns and would drift the day
 * the buttons move. Nothing here knows what the chrome IS: a zoom column, a fleet list and a detail
 * card occlude a name in exactly the same way, and all three are covered by the one rule.
 *
 * MEASURED, NOT DERIVED. The panels fold, the detail card exists only while something is selected,
 * and the fleet list opens folded below `COMPACT_WIDTH_PX`. A rectangle computed from class names
 * would be right at one width and silently wrong at the next.
 */
function useChromeBoxes(ref: RefObject<HTMLDivElement | null>): readonly ChromeBox[] {
  const [boxes, setBoxes] = useState<readonly ChromeBox[]>(NO_CHROME)

  useEffect(() => {
    const element = ref.current
    if (!element) return
    let frame = 0
    let last = ''

    const measure = () => {
      frame = 0
      const surface = element.getBoundingClientRect()
      const next: ChromeBox[] = []
      for (const node of element.querySelectorAll(`[${CHROME_ATTR}]`)) {
        const rect = node.getBoundingClientRect()
        if (rect.width <= 0 || rect.height <= 0) continue
        next.push({
          x: rect.left - surface.left,
          y: rect.top - surface.top,
          width: rect.width,
          height: rect.height,
        })
      }
      // Compared as a string, and state replaced ONLY when it really changed. The observers below
      // fire on every repaint of the chart (its labels are a subtree mutation), so without this the
      // hook would set state every frame and the chart would re-render itself for ever.
      const key = next
        .map((b) => `${b.x.toFixed(1)},${b.y.toFixed(1)},${b.width.toFixed(1)},${b.height.toFixed(1)}`)
        .join('|')
      if (key === last) return
      last = key
      setBoxes(next.length === 0 ? NO_CHROME : next)
    }

    const schedule = () => {
      if (frame === 0) frame = requestAnimationFrame(measure)
    }

    // Two observers, because chrome moves for two unrelated reasons: the SURFACE resizes (rotation,
    // a dragged window) and the CHROME changes (a panel folds, the detail card appears).
    const resize = new ResizeObserver(schedule)
    resize.observe(element)
    const mutations = new MutationObserver(schedule)
    mutations.observe(element, { childList: true, subtree: true, attributes: true })
    // The first measurement goes through the same frame as every later one, rather than being
    // taken synchronously here: a rect read during the effect body is a rect read before the
    // browser has painted, and setting state from it would be the cascading render React warns
    // about. One frame later the chart has no chrome to avoid; from the second, it has.
    schedule()

    return () => {
      if (frame !== 0) cancelAnimationFrame(frame)
      resize.disconnect()
      mutations.disconnect()
    }
  }, [ref])

  return boxes
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
  /**
   * Every opaque `CHART_CHROME` box on this surface, in CSS pixels from its top-left corner.
   *
   * PASS IT STRAIGHT TO `ChartCanvas`'s `keepOut` — that is what it is for, and it is the whole of
   * a screen's part in "a name is never printed under a button". The chart converts it to chart
   * units itself; the screen does no arithmetic and states no coordinate.
   */
  readonly chromeBoxes: readonly ChromeBox[]
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
  const chromeBoxes = useChromeBoxes(ref)
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
    chromeBoxes,
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
