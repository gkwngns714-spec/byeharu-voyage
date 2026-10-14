import { useEffect, useState } from 'react'
import {
  DAYLIGHT_RASTER_HEIGHT,
  DAYLIGHT_RASTER_WIDTH,
  daylightRaster,
  SUN_REFRESH_MS,
  subsolarPoint,
  type SubsolarPoint,
} from './sun'

// THE SUN, ON THE REAL CLOCK — the one hook that reads `Date.now()` for the picture and turns
// `sun.ts`'s arithmetic into the two things a layer can use: the subsolar point (for the lights
// and the inks, per point) and the daylight raster as an IMAGE (for the masks the day picture is
// painted through).
//
// ── §7B ────────────────────────────────────────────────────────────────────────────────────────
// WHAT IT IS   one concept: THE SUN NOW — `sun.ts` evaluated at the real instant, refreshed on a
//              timer, with its raster encoded once for the browser.
// WHERE        src/chart, beside the arithmetic it evaluates; the DOM (a canvas) is why it is not
//              in sun.ts, which stays pure so tests/map.sun.spec.ts can run it in plain Node.
// SECOND CALLER  `ChartCanvas` is the only caller, and that is the point: both surfaces (the Map
//              tab and SAIL's small chart) draw the one picture through it, so neither can hold a
//              sun of its own. The minimap is a locator and draws no daylight — a decision, not
//              an omission (./Minimap.tsx).
// WRONG SHAPE  a second clock. The shell's `nowMs` ticks every second for countdowns and the
//              drift; the sun moves a quarter of a degree a minute and re-rasterising 64,800
//              cells on every tick would be the per-frame cost MAP_ATMOSPHERE §7 measured out of
//              this chart. One timer, one minute, one raster.
//
// THE IMAGE is a 360 × 180 greyscale PNG — one pixel per degree, the raster's own bytes — handed
// to an SVG `<mask>` as an `<image>` stretched over each copy of the sheet (ChartCanvas,
// `DaylightMask`). The browser filters it bilinearly on the way up, which is a smooth terminator
// at every zoom; the cost per frame is one textured quad on the GPU, and the cost per minute is
// 4 ms of sines and one `toDataURL`.

export interface Sunlight {
  /** Where the Sun is overhead, now. */
  readonly sun: SubsolarPoint
  /** The daylight raster as a data URL, or null before the first paint (nothing is masked, which
   *  draws the night picture alone, truthfully, for one frame). */
  readonly rasterUrl: string | null
  /** The instant the raster was drawn for, so a change can be keyed on a number. */
  readonly atMs: number
}

/** Draw the raster into a PNG data URL. Null where there is no canvas (a non-browser render). */
function rasterToUrl(sun: SubsolarPoint): string | null {
  if (typeof document === 'undefined') return null
  const canvas = document.createElement('canvas')
  canvas.width = DAYLIGHT_RASTER_WIDTH
  canvas.height = DAYLIGHT_RASTER_HEIGHT
  const ctx = canvas.getContext('2d')
  if (!ctx) return null
  const bytes = daylightRaster(sun)
  const image = ctx.createImageData(DAYLIGHT_RASTER_WIDTH, DAYLIGHT_RASTER_HEIGHT)
  // INTO THE ALPHA CHANNEL: the mask reads alpha linearly (./DaylightMask.tsx says why not
  // luminance), so a cell's daylight is exactly the cell's opacity. White underneath, so a reader
  // who opens the PNG sees a terminator and not a black square.
  for (let i = 0; i < bytes.length; i++) {
    image.data[i * 4] = 255
    image.data[i * 4 + 1] = 255
    image.data[i * 4 + 2] = 255
    image.data[i * 4 + 3] = bytes[i]
  }
  ctx.putImageData(image, 0, 0)
  return canvas.toDataURL('image/png')
}

function sunlightNow(): Sunlight {
  const atMs = Date.now()
  const sun = subsolarPoint(atMs)
  return { sun, rasterUrl: rasterToUrl(sun), atMs }
}

export function useSunlight(): Sunlight {
  const [state, setState] = useState<Sunlight>(sunlightNow)
  useEffect(() => {
    const id = window.setInterval(() => setState(sunlightNow()), SUN_REFRESH_MS)
    return () => window.clearInterval(id)
  }, [])
  return state
}
