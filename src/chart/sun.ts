// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE SUN — where it stands over the Earth at a real instant, and how much light that puts on a
// point of the chart. ONE pure module; everything that shades by daylight composes it.
//
// The owner, 2026-10-14: *"i want there to be sunlight based on real science. The sunlight touching
// the earth should have colors similar to daytime earth."*
//
// ── §7B ────────────────────────────────────────────────────────────────────────────────────────
// WHAT IT IS   one concept: SOLAR POSITION — the subsolar point for a UTC instant, the sun's
//              elevation at any point of the globe, and the daylight factor (0 night … 1 day,
//              with the three twilights between) that the picture is shaded by.
// WHERE        src/chart, because the only thing in this game that cares where the sun is is the
//              picture — the server has no day/night rule and must not grow one from here (the
//              clock the world sails on is `time_compression`, a different clock entirely).
// SECOND CALLER  `useSunlight` (the hook: the real clock and the raster), `PortsLayer`,
//              `FleetsLayer`, `LabelsLayer` (the lights and the inks, per point). All of them ask
//              THIS module; none of them holds a declination or an obliquity of its own.
// WRONG SHAPE  a second "is it night" rule — a fixed terminator, a zoom-gated "night chart"
//              (which row 125's cut was, and which this retires), a shade computed from the
//              screen's colour scheme. There is one sun and it is where the almanac says it is.
//
// ── THE FORMULAE ───────────────────────────────────────────────────────────────────────────────
// NOAA's "Solar Calculator" low-precision algorithm (Meeus, Astronomical Algorithms, ch. 25, the
// low-accuracy method), stated here in full so a reader can check each line against the almanac:
//
//   T    Julian centuries since J2000.0 (2000-01-01 12:00 UTC):  T = (JD − 2451545) / 36525
//   L0   geometric mean longitude of the Sun, degrees:  280.46646 + 36000.76983 T + 0.0003032 T²
//   M    mean anomaly, degrees:                         357.52911 + 35999.05029 T − 0.0001537 T²
//   e    eccentricity of Earth's orbit:        0.016708634 − 0.000042037 T − 0.0000001267 T²
//   C    equation of centre, degrees:
//          (1.914602 − 0.004817 T − 0.000014 T²) sin M + (0.019993 − 0.000101 T) sin 2M + 0.000289 sin 3M
//   λ    true longitude = L0 + C;  apparent longitude λ' = λ − 0.00569 − 0.00478 sin Ω,
//          Ω = 125.04 − 1934.136 T (the Moon's ascending node, for nutation and aberration)
//   ε    obliquity of the ecliptic, corrected:  ε0 + 0.00256 cos Ω,
//          ε0 = 23.439291 − 0.0130042 T  (the first terms of Meeus 22.2 — the rest are < 0.0001°
//          over this game's lifetime)
//   δ    declination = asin(sin ε · sin λ')                                   → subsolar LATITUDE
//   E    equation of time, MINUTES (Meeus 28.3, with y = tan²(ε/2)):
//          4 · deg( y sin 2L0 − 2e sin M + 4e y sin M cos 2L0 − ½ y² sin 4L0 − 1.25 e² sin 2M )
//   H    the Sun's hour angle at Greenwich, degrees: 15 · (UTC hours + E/60 − 12)
//                                                                          → subsolar LONGITUDE = −H
//
// Accuracy: the declination is good to ~0.01° and the equation of time to a few seconds across
// 1900–2100, which on a chart whose own coastline is decimated at 0.2° is exact. The tests in
// tests/map.sun.spec.ts hold the equinoxes, the solstices and Greenwich noon on dated instants.
//
// ── THE SHADE ──────────────────────────────────────────────────────────────────────────────────
// The elevation at a point is the dot product on the sphere:
//   sin h = sin φ sin δ + cos φ cos δ cos(lon − lon_s)
// and `daylightOf(h)` turns it into the one number the picture uses — 1 above the horizon (the
// upper limb, refracted: −0.833°), falling through civil (−6°), nautical (−12°) and astronomical
// (−18°) twilight to 0. The bands are the almanac's; the values inside them are a picture's
// choice, stated as constants below and nowhere else.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import type { CSSProperties } from 'react'
import type { LatLon } from '../lib/geo'

const DEG = Math.PI / 180

/** Where the Sun is directly overhead. */
export interface SubsolarPoint extends LatLon {
  /** The equation of time at that instant, in minutes (apparent minus mean solar time). */
  readonly equationOfTimeMin: number
  /** The declination, which is the subsolar latitude — repeated under its almanac name. */
  readonly declinationDeg: number
}

/** The instant → Julian centuries since J2000.0. */
function julianCenturies(utcMs: number): number {
  const jd = utcMs / 86_400_000 + 2_440_587.5
  return (jd - 2_451_545) / 36_525
}

/** Wrap degrees into [−180, 180). */
function wrapDeg(d: number): number {
  const w = ((d + 180) % 360 + 360) % 360 - 180
  return w
}

/**
 * THE SUBSOLAR POINT at a UTC instant (milliseconds since the epoch, as `Date.now()` gives it) —
 * the NOAA / Meeus low-precision solar position, line for line as the header states it.
 */
export function subsolarPoint(utcMs: number): SubsolarPoint {
  const T = julianCenturies(utcMs)
  const L0 = (280.46646 + 36000.76983 * T + 0.0003032 * T * T) % 360
  const M = 357.52911 + 35999.05029 * T - 0.0001537 * T * T
  const e = 0.016708634 - 0.000042037 * T - 0.0000001267 * T * T
  const Mr = M * DEG
  const C =
    (1.914602 - 0.004817 * T - 0.000014 * T * T) * Math.sin(Mr) +
    (0.019993 - 0.000101 * T) * Math.sin(2 * Mr) +
    0.000289 * Math.sin(3 * Mr)
  const trueLon = L0 + C
  const omega = (125.04 - 1934.136 * T) * DEG
  const apparentLon = trueLon - 0.00569 - 0.00478 * Math.sin(omega)
  const obliquity0 = 23.439291 - 0.0130042 * T
  const obliquity = obliquity0 + 0.00256 * Math.cos(omega)
  const declination = Math.asin(Math.sin(obliquity * DEG) * Math.sin(apparentLon * DEG)) / DEG

  const y = Math.tan((obliquity / 2) * DEG) ** 2
  const L0r = L0 * DEG
  const eot =
    4 *
    ((y * Math.sin(2 * L0r) -
      2 * e * Math.sin(Mr) +
      4 * e * y * Math.sin(Mr) * Math.cos(2 * L0r) -
      0.5 * y * y * Math.sin(4 * L0r) -
      1.25 * e * e * Math.sin(2 * Mr)) /
      DEG)

  const utcHours = (((utcMs % 86_400_000) + 86_400_000) % 86_400_000) / 3_600_000
  const hourAngle = 15 * (utcHours + eot / 60 - 12)
  return {
    lat: declination,
    lon: wrapDeg(-hourAngle),
    equationOfTimeMin: eot,
    declinationDeg: declination,
  }
}

/** The Sun's elevation above the horizon at a point, in degrees (−90 … 90), for a subsolar point. */
export function solarElevationDeg(at: LatLon, sun: LatLon): number {
  const phi = at.lat * DEG
  const delta = sun.lat * DEG
  const dLon = (at.lon - sun.lon) * DEG
  const s = Math.sin(phi) * Math.sin(delta) + Math.cos(phi) * Math.cos(delta) * Math.cos(dLon)
  return Math.asin(Math.max(-1, Math.min(1, s))) / DEG
}

/**
 * THE TWILIGHT BANDS, in degrees of elevation, and the daylight the picture holds at each edge.
 * The elevations are the almanac's (sunrise at the refracted upper limb, then the three
 * twilights); the daylight at each is the picture's one statement of how bright a dusk is. Linear
 * between the edges — a smoothstep would be prettier at the terminator and no truer.
 */
export const TWILIGHT: readonly { readonly elevationDeg: number; readonly daylight: number }[] = [
  { elevationDeg: -0.833, daylight: 1 },
  { elevationDeg: -6, daylight: 0.62 },
  { elevationDeg: -12, daylight: 0.24 },
  { elevationDeg: -18, daylight: 0 },
]

/** How much daylight a solar elevation puts on a point: 1 by day, 0 by night, the twilights between. */
export function daylightOf(elevationDeg: number): number {
  if (!Number.isFinite(elevationDeg)) return 0
  if (elevationDeg >= TWILIGHT[0].elevationDeg) return 1
  for (let i = 1; i < TWILIGHT.length; i++) {
    const hi = TWILIGHT[i - 1]
    const lo = TWILIGHT[i]
    if (elevationDeg >= lo.elevationDeg) {
      const f = (elevationDeg - lo.elevationDeg) / (hi.elevationDeg - lo.elevationDeg)
      return lo.daylight + (hi.daylight - lo.daylight) * f
    }
  }
  return 0
}

/** The daylight at a point for a subsolar point — the two functions above, composed. */
export function daylightAt(at: LatLon, sun: LatLon): number {
  return daylightOf(solarElevationDeg(at, sun))
}

/**
 * THE ONE NUMBER A MARK CARRIES ABOUT THE SUN, as the CSS custom property its inks read:
 * `--night` = 1 − daylight, set on the mark's group (ports, hulls, roads, names), and read by the
 * `.bv-sun-*` rules in src/index.css that say what each ink becomes by day. One spelling, here,
 * so no layer can hold a second idea of what "night" is. (A `CSSProperties` type only — this file
 * stays pure and runs in plain Node.)
 */
export function nightStyle(at: LatLon, sun: LatLon): CSSProperties {
  return { '--night': (1 - daylightAt(at, sun)).toFixed(3) } as CSSProperties
}

/**
 * THE DAYLIGHT RASTER — one cell per degree, 360 × 180, row 0 the north pole, column 0 the
 * antimeridian (lon −180), each cell the daylight at its centre as a byte (0 … 255). This is what
 * the picture is masked by: `useSunlight` paints it into a 360 × 180 image once a minute and the
 * browser stretches it over the sheet with bilinear filtering, which is a smooth terminator at
 * every zoom for the price of 64,800 sines a minute and nothing per frame.
 */
export const DAYLIGHT_RASTER_WIDTH = 360
export const DAYLIGHT_RASTER_HEIGHT = 180

export function daylightRaster(sun: LatLon): Uint8ClampedArray {
  const out = new Uint8ClampedArray(DAYLIGHT_RASTER_WIDTH * DAYLIGHT_RASTER_HEIGHT)
  const sinD = Math.sin(sun.lat * DEG)
  const cosD = Math.cos(sun.lat * DEG)
  for (let row = 0; row < DAYLIGHT_RASTER_HEIGHT; row++) {
    const lat = 90 - row - 0.5
    const sinP = Math.sin(lat * DEG) * sinD
    const cosP = Math.cos(lat * DEG) * cosD
    for (let col = 0; col < DAYLIGHT_RASTER_WIDTH; col++) {
      const lon = -180 + col + 0.5
      const s = sinP + cosP * Math.cos((lon - sun.lon) * DEG)
      const h = Math.asin(Math.max(-1, Math.min(1, s))) / DEG
      out[row * DAYLIGHT_RASTER_WIDTH + col] = Math.round(daylightOf(h) * 255)
    }
  }
  return out
}

/** How often the picture re-reads the clock. The subsolar point moves a quarter of a degree a
 *  minute, which at the widest zoom on a 1440 px glass is a pixel — nothing finer is visible. */
export const SUN_REFRESH_MS = 60_000
