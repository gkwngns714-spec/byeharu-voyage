import { useEffect, useMemo, useState } from 'react'
import type { LatLon } from '../lib/geo'
import {
  DAYLIGHT_RASTER_HEIGHT,
  DAYLIGHT_RASTER_WIDTH,
  daylightRaster,
  SUN_REFRESH_MS,
  subsolarPoint,
  type SubsolarPoint,
} from './sun'
import { gameSunInstantMs } from '../lib/format'
import { serverNow } from '../lib/serverClock'

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
// WRONG SHAPE  a second clock. The Sun stands at the GAME CLOCK's hour (owner, 2026-10-15: the
//              sunlight "should match the speed of the game speed"), read through the one
//              authority `gameSunInstantMs`, so it turns 360° per game day — ½° a real second at
//              120× (GAME_CLOCK_RATE). One timer (SUN_REFRESH_MS), one raster per step, never per frame.
//
// THE IMAGE is a 360 × 180 greyscale PNG — one pixel per degree, the raster's own bytes — handed
// to a CSS `mask-image` tiled once per turn of the world over each day sheet (ChartCanvas,
// `DaylightSheet`). The browser filters it bilinearly on the way up, which is a smooth terminator
// at every zoom; the cost per frame is one re-painted mask over composited pictures, and the cost
// per declination step is 4 ms of sines and one `toDataURL`.

export interface Sunlight {
  /** Where the Sun is overhead, now. */
  readonly sun: SubsolarPoint
  /** The daylight raster as a data URL, drawn with the Sun over longitude 0 — `DaylightSheet`
   *  slides it to the Sun's longitude every frame. Null where there is no canvas. */
  readonly rasterUrl: string | null
  /** The REAL instant the raster was drawn at (the Sun is at `gameSunInstantMs` of it). */
  readonly atMs: number
}

/** Draw the raster into a PNG data URL. Null where there is no canvas (a non-browser render). */
function rasterToUrl(sun: LatLon): string | null {
  if (typeof document === 'undefined') return null
  const canvas = document.createElement('canvas')
  canvas.width = DAYLIGHT_RASTER_WIDTH
  canvas.height = DAYLIGHT_RASTER_HEIGHT
  const ctx = canvas.getContext('2d')
  if (!ctx) return null
  const bytes = daylightRaster(sun)
  const image = ctx.createImageData(DAYLIGHT_RASTER_WIDTH, DAYLIGHT_RASTER_HEIGHT)
  // INTO THE ALPHA CHANNEL: the mask reads alpha linearly (./DaylightSheet.tsx says why not
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

/** The raster is drawn with the Sun over longitude 0 and SLID to where it stands, every frame,
 *  by `DaylightSheet` (owner, 2026-10-15: the light zone moved rigid — "make it soft"). Only the
 *  declination changes the picture itself, so it is re-drawn when that moves a hundredth of a
 *  degree, never on the Sun's longitude. */
const RASTER_LAT_STEP = 0.01

function sunNow(): { sun: SubsolarPoint; atMs: number } {
  const atMs = serverNow()
  // THE GAME CLOCK'S HOUR (lib/format gameSunInstantMs): day and night turn at game speed.
  return { sun: subsolarPoint(gameSunInstantMs(atMs)), atMs }
}

export function useSunlight(): Sunlight {
  const [now, setNow] = useState(sunNow)
  useEffect(() => {
    const id = window.setInterval(() => setNow(sunNow()), SUN_REFRESH_MS)
    return () => window.clearInterval(id)
  }, [])
  const rasterLat = Math.round(now.sun.lat / RASTER_LAT_STEP) * RASTER_LAT_STEP
  const rasterUrl = useMemo(() => rasterToUrl({ lat: rasterLat, lon: 0 }), [rasterLat])
  return { sun: now.sun, rasterUrl, atMs: now.atMs }
}
