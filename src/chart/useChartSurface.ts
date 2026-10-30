import {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
  type PointerEvent as ReactPointerEvent,
  type RefObject,
} from 'react'
import { project, wrapLon, type GeoBounds, type LatLon, type Point, type ViewBox } from '../lib/geo'
import {
  approachView,
  clampView,
  fitView,
  glideShare,
  GOTO_GLIDE_MS,
  panBy,
  unitsPerPixel,
  viewArrived,
  viewBoxOf,
  zoomAt,
  ZOOM_GLIDE_MS,
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
// A TAP NOW ARRIVES WITH ITS COUNT (owner row 172, 2026-10-20), and that is not a fourth gesture:
// every tap is still delivered the instant the finger lifts, and nothing is held back to see
// whether a second one follows. The count is a FACT ABOUT THE TAP, measured here beside the drag
// slop because this is where a tap is decided — what a second press means belongs to the screen
// (MapScreen: the second press is what names a point of open water).
//
// ── ONE IMPLEMENTATION, THREE POSTURES (2026-08-23; `wheel-zoom` 2026-10-30) ────────────────────
// This hook is the only gesture implementation the game has, and it serves two kinds of surface.
// A FULL-TAB chart (the Map tab) owns every gesture on its glass: `touch-none`, and a non-passive
// wheel listener that `preventDefault`s so zooming never scrolls anything. An EMBEDDED chart
// (`SmallChart`, the command desk's map) must not own them all, and how much it cedes is the
// `scroll` option — a chart that ate every vertical drag while it sat over a scrolling form would
// be a wall the player cannot scroll past (docs/CORE_REUSE.md §1.5). The option is one hook rather
// than two implementations precisely so the pan arithmetic, the pinch, the chrome guard and the
// tap rule can never drift apart between the postures.
//
// What the embedded postures cede, and to whom (§7C: every branch here chooses between two
// ACCEPTABLE outcomes — both "the chart moves" and "the page scrolls" are products):
//   · 'wheel-zoom' (the command desk's map): the WHEEL is the chart's — a mouse wheel zooms, the
//     reader's first instinct on a map big enough to deserve it. A one-finger TOUCH drag's
//     VERTICAL axis is still the page's (`touch-pan-y`), so a thumb scrolling the form is never
//     trapped on the map. A pinch zooms; a mouse drag pans both axes.
//   · 'page-vertical' (a small embedded chart): the WHEEL is the page's. No listener is attached
//     at all, so a mouse wheel over the chart scrolls the form exactly as it does over the text
//     beside it, and zoom is the visible +/− column (`ViewControls`). A one-finger TOUCH drag's
//     VERTICAL axis is the page's (`touch-pan-y`), so the browser itself runs vertical scrolling;
//     our pan applies the HORIZONTAL component only, so the two authorities never fight over one
//     gesture — a finger down the page scrolls the page, a finger along the coast pans the chart.
//   · a PINCH is still the chart's (`pan-y` leaves multi-touch to us), and a MOUSE drag still pans
//     both axes — a mouse drag never scrolled a page, so there is nothing to cede.
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

/** WHAT MAKES TWO TAPS ONE GESTURE (owner row 172, 2026-10-20) — the second tap lands within this
 *  long of the first, and this near it. 400 ms is a little longer than a phone's own double-tap
 *  window, because nothing here is waiting on the answer: a single tap has already done its work
 *  (the caller decides what the count means), so a late second tap costs the player nothing. The
 *  reach is a thumb's width rather than the 5 px of a tap, since two deliberate taps on the same
 *  piece of water never land on the same pixel. */
const DOUBLE_TAP_MS = 400
const DOUBLE_TAP_SLOP_PX = 24

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

export interface ChartSurfaceOptions {
  /**
   * Who owns the gestures a scrolling page also wants — see the header.
   *   'chart'          (default) a full-tab surface: wheel zooms (non-passive), every drag pans.
   *   'wheel-zoom'     embedded in a scrolling form on a MOUSE: the wheel ZOOMS (the reader's first
   *                    instinct, and the command desk's map is big enough to deserve it), while a
   *                    one-finger TOUCH drag's vertical axis stays the page's — a thumb keeps
   *                    scrolling the form. A mouse drag pans both axes; a pinch zooms.
   *   'page-vertical'  embedded in a small scrolling form: the wheel AND a one-finger touch drag's
   *                    vertical axis belong to the PAGE; zoom is the caller's `ViewControls`.
   * Whichever is chosen, put the returned `touchClass` on the surface element — the posture and
   * its `touch-action` are one fact, stated here once, never hand-paired at a call site.
   */
  readonly scroll?: 'chart' | 'wheel-zoom' | 'page-vertical'
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
  /**
   * The `touch-action` class this surface's posture REQUIRES, for the caller to put on the
   * element the handlers go on. `touch-none` for a surface that owns every gesture;
   * `touch-pan-y` for one that cedes vertical scrolling to the page. Literal Tailwind classes
   * (the JIT scanner reads source text), and they live HERE because pairing them by hand at each
   * call site is how one caller ends up eating a scroll its option said it would cede.
   */
  readonly touchClass: 'touch-none' | 'touch-pan-y'
  readonly zoomIn: () => void
  readonly zoomOut: () => void
  /** Back to the opening frame. */
  readonly fit: () => void
  /** Put a place in the middle of the glass, at the current zoom. A VIEW change and nothing else —
   *  it is how the fleet list reaches a fleet the opening frame does not happen to contain. */
  readonly centreOn: (at: LatLon) => void
  /** GLIDE a place to a point of the glass (`u`, a fraction of its width; 0.5 the middle) at the
   *  span `spanFor` picks from the current one (./chartView.ts `goToSpan`, the one rule) — the zoom
   *  glide's own loop, aimed (./goTo.ts). The hand still wins. */
  readonly glideTo: (at: LatLon, spanFor: (currentSpanX: number) => number, u?: number) => void
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
   *   `presses`     how many taps in a row this one is: 1 for a tap on its own, 2 for the second
   *                 of a double tap, and so on (DOUBLE_TAP_MS / DOUBLE_TAP_SLOP_PX above). COUNTED
   *                 HERE because it is a fact about the gesture, like the drag slop beside it, and
   *                 every tap is still delivered the moment the finger lifts — nothing is held
   *                 back waiting to see whether a second one arrives. What a second press MEANS is
   *                 the caller's: on the map tab it is what shows a point of open water (owner
   *                 row 172: *"I want to just move around. Show coordinate when pressed twice."*).
   */
  onTap?: (at: Point, unitsPerPx: number, view: ViewBox, presses: number) => void,
  options?: ChartSurfaceOptions,
): ChartSurface {
  const owns = options?.scroll ?? 'chart'
  /** The page owns the wheel: a mouse wheel scrolls the form, never zooms (page-vertical only). */
  const pageOwnsWheel = owns === 'page-vertical'
  /** The page owns the vertical axis of a one-finger TOUCH drag — the browser scrolls the form
   *  (`touch-pan-y`) — on every posture but the full `chart`. A MOUSE drag pans both axes on every
   *  posture (a mouse never scrolled a page by dragging). */
  const pageOwnsVertical = owns !== 'chart'
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
  /** The last tap, for counting a double one: where it landed on the page, when, and what it was
   *  counted as. */
  const lastTap = useRef({ x: 0, y: 0, ms: 0, presses: 0 })

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

  // ── THE ZOOM GLIDE (owner, 2026-10-15: "i want zoom in and out to be smoother") ────────────────
  // A wheel notch or a +/− press no longer jumps: it adds its log-factor to what is still owed and
  // one animation frame at a time pays a share of it (time constant ZOOM_GLIDE_MS) around the
  // latest anchor. One loop, one owed amount — a second notch mid-glide just owes more. A drag, a
  // pinch, Fit or a centre-on cancels it, so the hand always wins.
  // A GO-TO (./goTo.ts) is the same loop with a destination instead of a debt: `to` is where it
  // is going and `at` where the last frame left it. A wheel notch, a drag or a pinch drops it.
  const glide = useRef({
    owed: 0,
    u: 0.5,
    v: 0.5,
    aspect: 1,
    frame: 0,
    last: 0,
    to: null as ChartView | null,
    at: null as ChartView | null,
  })
  const stopGlide = useCallback(() => {
    cancelAnimationFrame(glide.current.frame)
    glide.current.frame = 0
    glide.current.owed = 0
    glide.current.to = null
  }, [])
  const glideZoom = useCallback(
    (factor: number, u: number, v: number, surfaceAspect: number) => {
      const g = glide.current
      if (g.to) stopGlide()
      g.owed += Math.log(factor)
      g.u = u
      g.v = v
      g.aspect = surfaceAspect
      if (g.frame !== 0) return
      g.last = performance.now()
      const step = (t: number) => {
        const share = glideShare(t, g.last, ZOOM_GLIDE_MS)
        g.last = t
        const done = Math.abs(g.owed) < 0.002
        const pay = done ? g.owed : g.owed * share
        g.owed -= pay
        setMovedTo((previous) => zoomAt(from(previous, g.aspect), g.aspect, Math.exp(pay), g.u, g.v))
        g.frame = done ? 0 : requestAnimationFrame(step)
      }
      g.frame = requestAnimationFrame(step)
    },
    [from, stopGlide],
  )
  useEffect(() => stopGlide, [stopGlide])

  // The view the last render committed, for a go-to to start from (read in a handler, never in
  // render).
  const committed = useRef<ChartView | null>(null)
  const glideTo = useCallback(
    (at: LatLon, spanFor: (currentSpanX: number) => number, u = 0.5) => {
      const start = committed.current
      if (!start) return
      stopGlide()
      const g = glide.current
      const span = spanFor(start.spanX)
      const point = project(at)
      const to = clampView({ cx: point.x + (0.5 - u) * span, cy: point.y, spanX: span }, aspect)
      g.to = to
      g.at = start
      g.last = performance.now()
      const step = (t: number) => {
        if (g.to !== to || !g.at) return
        const share = glideShare(t, g.last, GOTO_GLIDE_MS)
        g.last = t
        const next = approachView(g.at, to, share)
        const done = viewArrived(next, to)
        g.at = done ? to : next
        setMovedTo(clampView(g.at, aspect))
        if (done) {
          g.to = null
          g.frame = 0
        } else g.frame = requestAnimationFrame(step)
      }
      g.frame = requestAnimationFrame(step)
    },
    [aspect, stopGlide],
  )

  // ── wheel (and the trackpad pinch, which arrives as ctrlKey + wheel) ──────────────────────────
  // Attached natively because it must be non-passive: a chart that scrolls the page under the
  // player's finger while they zoom is unusable, and React's onWheel cannot say preventDefault.
  //
  // NOT ATTACHED AT ALL when the page owns the scroll: an embedded chart that preventDefaults the
  // wheel is a dead band in the middle of a form — the player spins the wheel over it and the page
  // stands still, with the Issue button below the fold. No listener, so the wheel behaves over the
  // chart exactly as it does over the paragraph above it, and zoom is the visible +/− column.
  useEffect(() => {
    if (pageOwnsWheel) return
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
      glideZoom(factor, u, v, surfaceAspect)
    }
    element.addEventListener('wheel', onWheel, { passive: false })
    return () => element.removeEventListener('wheel', onWheel)
  }, [ref, glideZoom, pageOwnsWheel])

  // ── pointers: one finger pans, two pinch ──────────────────────────────────────────────────────
  const onPointerDown = useCallback((event: ReactPointerEvent<HTMLDivElement>) => {
    if (isChrome(event.target)) return
    stopGlide()
    if (pointers.current.size === 0) travelled.current = 0
    pointers.current.set(event.pointerId, { x: event.clientX, y: event.clientY })
    event.currentTarget.setPointerCapture(event.pointerId)
  }, [stopGlide])

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
        // WHEN THE PAGE OWNS THE VERTICAL, a one-finger TOUCH drag pans horizontally ONLY. With
        // `touch-pan-y` the browser is simultaneously deciding whether this drag is a page scroll,
        // and until it decides (and fires pointercancel) both of us receive the moves — panning
        // the chart on dy in that window would drag the sheet a few pixels and then have the
        // browser snatch the gesture, a visible stutter with two hands on one wheel. Ceding the
        // axis outright is the honest split: down the page scrolls, along the coast pans, and the
        // vertical of the chart is reached by pinch, by the buttons, or by a mouse — whose drags
        // never scrolled a page and therefore keep both axes.
        const panDy = pageOwnsVertical && event.pointerType === 'touch' ? 0 : nextPoint.y - previousPoint.y
        setMovedTo((previous) => {
          const base = from(previous, surfaceAspect)
          const perPixel = unitsPerPixel(base, rect.width)
          return panBy(base, surfaceAspect, (nextPoint.x - previousPoint.x) * perPixel, panDy * perPixel)
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
    [ref, from, pageOwnsVertical],
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
      // HOW MANY TAPS IN A ROW THIS IS (see `onTap`'s contract): the clock and the distance are
      // both the PAGE's, so a tap that pans nothing and a chart that has not moved are irrelevant
      // to it — two taps on one piece of glass are one gesture whatever the view did between them.
      const ms = performance.now()
      const near = Math.hypot(event.clientX - lastTap.current.x, event.clientY - lastTap.current.y) <= DOUBLE_TAP_SLOP_PX
      const presses = near && ms - lastTap.current.ms <= DOUBLE_TAP_MS ? lastTap.current.presses + 1 : 1
      lastTap.current = { x: event.clientX, y: event.clientY, ms, presses }
      // A TAP IS A PLACE ON THE GLOBE, so its x is a longitude in [−180, 180] whatever copy of the
      // sheet the finger landed on (2026-10-14, the continuous chart): a view panned past the
      // antimeridian hands out boxes that run to 200°, and the harbours, the fleets and the sea
      // grid all live on the one copy. `box` itself is handed on untouched — it is the window the
      // caller culls by, and `portMarks` reads it through the sheet's copies.
      onTap(
        {
          x: wrapLon(box.x + ((event.clientX - rect.left) / rect.width) * box.width),
          y: box.y + ((event.clientY - rect.top) / rect.height) * box.height,
        },
        unitsPerPixel(view, rect.width),
        box,
        presses,
      )
    },
    [ref, onTap, view],
  )

  // ── the three controls ────────────────────────────────────────────────────────────────────────
  useEffect(() => {
    committed.current = view
  }, [view])

  const zoomBy = useCallback(
    (factor: number) => glideZoom(factor, 0.5, 0.5, aspect),
    [aspect, glideZoom],
  )
  const zoomIn = useCallback(() => zoomBy(ZOOM_STEP), [zoomBy])
  const zoomOut = useCallback(() => zoomBy(1 / ZOOM_STEP), [zoomBy])
  // "Fit" returns to the opening frame by FORGETTING the moves, not by storing a copy of it — so
  // there is only ever one definition of where the chart opens.
  const fit = useCallback(() => {
    stopGlide()
    setMovedTo(null)
  }, [stopGlide])

  const centreOn = useCallback(
    (at: LatLon) => {
      stopGlide()
      const point = project(at)
      setMovedTo((previous) =>
        clampView({ cx: point.x, cy: point.y, spanX: from(previous, aspect).spanX }, aspect),
      )
    },
    [aspect, from, stopGlide],
  )

  return {
    width: size.width,
    height: size.height,
    view,
    viewBox: view ? viewBoxOf(view, aspect) : null,
    unitsPerPx: view ? unitsPerPixel(view, size.width) : 1,
    chromeBoxes,
    touchClass: pageOwnsVertical ? 'touch-pan-y' : 'touch-none',
    zoomIn,
    zoomOut,
    fit,
    centreOn,
    glideTo,
    handlers: {
      onPointerDown,
      onPointerMove,
      onPointerUp: endPointer,
      onPointerCancel: endPointer,
    },
  }
}
