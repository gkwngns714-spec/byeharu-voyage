import { useEffect, useLayoutEffect, useRef, type CSSProperties, type ReactNode } from 'react'
import { gameSunInstantMs } from '../lib/format'
import { serverNow } from '../lib/serverClock'
import { CHART_HEIGHT, CHART_WIDTH } from '../lib/geo'
import { subsolarPoint } from './sun'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE DAYLIGHT SHEET — the day picture, seen through the Sun's raster (./useSunlight.ts). ONE
// definition of how the raster becomes a mask, used by the two sheets that paint a day picture:
// the day SEA (ChartCanvas, over the view) and the day COAST (ChartCanvas's CoastSheet, over the
// paper).
//
// ── §7B ────────────────────────────────────────────────────────────────────────────────────────
// WHAT IT IS   one concept: WHERE THE SUN IS UP ON THE GLASS — the raster as a CSS `mask-image`
//              on an HTML sheet, tiled once per turn of the world, slid to the Sun's longitude on
//              every animation frame (owner, 2026-10-15: "right now the light zone moves rigid.
//              make it soft" — and kept soft at the owner's insistence when it was reverted).
// WHERE        src/chart, beside the sun it reads (./sun.ts holds every formula; this holds none).
// SECOND CALLER  the sea and the coast; both pass the chart-unit ORIGIN of the sheet they cover
//              and the chart units per CSS pixel, and nothing else.
// WRONG SHAPE  an SVG `<mask>` whose content moves every frame. That was this concept until
//              2026-10-17, and it is why panning stuttered: a mask's content changing invalidates
//              the PAINT of everything drawn through it, so every animation frame re-recorded the
//              whole day coast on the main thread — measured on the production build at 1280×844,
//              a 5 s drag ran at 31 fps median with 41 long tasks up to 68 ms; the same drag with
//              the mask held still ran at 60 fps with none.
//
// ── WHY A CSS MASK OVER A LAYER IS CHEAP ───────────────────────────────────────────────────────
// The day picture sits in its own compositor layer (`will-change: transform` on the inner div),
// and the mask is on its parent. Moving `mask-position` re-paints the MASK — one stretched
// 360 × 180 image — and never the picture under it, which the compositor keeps as it is. The
// raster is in the image's ALPHA channel (useSunlight.ts) and `mask-mode: alpha` reads it
// linearly, so the twilight the almanac computed is the twilight the picture shows; the browser
// filters the 1°-per-pixel image bilinearly on the way up, which is the soft terminator.
//
// THE GEOMETRY. x IS longitude on this chart (lib/geo `project`), and the raster is drawn with the
// Sun over longitude 0, so its tile's left edge belongs at chart x = −180 + (the Sun's longitude),
// repeated every CHART_WIDTH units (the copies of the sheet, wherever they are). Its top edge is
// chart y = −90 and it does not repeat vertically: past the poles there is no day.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/** The chart-unit point a sheet's top-left CSS pixel shows, and its chart units per CSS pixel. */
interface SheetFrame {
  readonly x: number
  readonly y: number
  readonly unitsPerPx: number
}

/** The mask's position, in CSS pixels, for a sheet frame and the Sun's longitude. The x offset is
 *  folded into one tile (−tile, 0] — the mask repeats along x, so any whole turn is the same. */
function maskPosition(frame: SheetFrame, sunLon: number): string {
  const tile = CHART_WIDTH / frame.unitsPerPx
  const raw = (-CHART_WIDTH / 2 + sunLon - frame.x) / frame.unitsPerPx
  const x = (((raw % tile) + tile) % tile) - tile
  const y = (-CHART_HEIGHT / 2 - frame.y) / frame.unitsPerPx
  return `${x.toFixed(2)}px ${y.toFixed(2)}px`
}

/** Both spellings: Chromium and current Safari read `mask-position`, older WebKit only its prefix. */
function place(el: HTMLElement, at: string): void {
  el.style.setProperty('mask-position', at)
  el.style.setProperty('-webkit-mask-position', at)
}

function sunLonNow(): number {
  return subsolarPoint(gameSunInstantMs(serverNow())).lon
}

export function DaylightSheet({
  rasterUrl,
  x,
  y,
  unitsPerPx,
  className,
  style,
  children,
}: {
  rasterUrl: string
  /** The chart-unit point at the sheet's top-left corner. */
  x: number
  y: number
  /** Chart units per CSS pixel on this sheet. */
  unitsPerPx: number
  className?: string
  style?: CSSProperties
  /** The day picture. */
  children: ReactNode
}) {
  const ref = useRef<HTMLDivElement>(null)
  const frame = useRef<SheetFrame>({ x, y, unitsPerPx })

  // A NEW FRAME (a pan, a zoom) is placed before the browser paints it, so the mask never lags the
  // picture by a frame.
  useLayoutEffect(() => {
    frame.current = { x, y, unitsPerPx }
    const el = ref.current
    if (el && unitsPerPx > 0) place(el, maskPosition(frame.current, sunLonNow()))
  }, [x, y, unitsPerPx])

  // THE SUN'S GLIDE — one style write per animation frame, no React render.
  useEffect(() => {
    let id = 0
    const step = () => {
      const el = ref.current
      if (el && frame.current.unitsPerPx > 0) place(el, maskPosition(frame.current, sunLonNow()))
      id = requestAnimationFrame(step)
    }
    id = requestAnimationFrame(step)
    return () => cancelAnimationFrame(id)
  }, [])

  const size = unitsPerPx > 0 ? `${CHART_WIDTH / unitsPerPx}px ${CHART_HEIGHT / unitsPerPx}px` : '0 0'
  const mask: CSSProperties = {
    maskImage: `url("${rasterUrl}")`,
    maskMode: 'alpha',
    maskRepeat: 'repeat-x',
    maskSize: size,
    WebkitMaskImage: `url("${rasterUrl}")`,
    WebkitMaskRepeat: 'repeat-x',
    WebkitMaskSize: size,
  }
  return (
    <div
      ref={ref}
      className={className}
      style={{ ...style, ...mask, pointerEvents: 'none' }}
      data-testid="map-daylight-mask"
    >
      <div className="h-full w-full will-change-transform">{children}</div>
    </div>
  )
}
