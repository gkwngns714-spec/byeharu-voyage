// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE WALK — the city's people moving along its streets, on the page's own animation frame
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, three times (docs/OWNER_REQUESTS.md rows 241, 242, 248, 2026-10-31): *"these dots are
// population, it can stop it can go back and forth, random movements"* · *"make the dot speed 3
// times slower"* · *"does this look like a city with citizens?"*.
//
// ── WHAT WAS WRONG ─────────────────────────────────────────────────────────────────────────────
// Every moving person was a `<circle>` with an SVG `<animateMotion>` (SMIL). The drive audit of
// 2026-11-08 (docs/dev-log/2026-11-08-drive-audit.md, D1) drove the HQ in a real headless Chromium
// at 1280 and 390 on fresh loads: 0 of 36 walkers moved over 4 s, the plan's two clips 3 s apart
// were byte-identical, the svg's SMIL clock ran and nothing was paused — the scene's SMIL timeline
// was never serviced until something seeked it (`svg.setCurrentTime(...)` woke them). The spec
// that "proved" the walk read a dot right after a viewport change, when the plate re-scaled under
// it. A SMIL timeline is also paused in a hidden document and is not a thing this app can watch or
// drive, so the people now walk on the page's own clock, where nothing between them and the glass
// is a browser's SMIL scheduler.
//
// ── WHAT THIS IS ───────────────────────────────────────────────────────────────────────────────
// A pure schedule per person — time → a point on a route (`walkAt`) — and ONE requestAnimationFrame
// loop per scene (`useCityWalk`) that writes one `transform` attribute per moving circle, WALK_HZ
// times a second. The loop stops while the document is hidden and while the plan is off the glass
// (IntersectionObserver), and does not start at all under `prefers-reduced-motion: reduce` — the
// people then stand where their phase puts them, which is the still picture the plan always was.
//
// CSS `offset-path` keyframes were the other candidate; see docs/dev-log/2026-11-08-city-walkers.md
// for the measurement that chose this loop (the CSS animation is serviced every frame at 60 Hz
// whatever the walk needs, cannot be throttled, and its SVG support is the browser's, which the
// owner's Safari would have to be trusted for; this loop runs wherever `requestAnimationFrame` does).
//
// ── THE WALK ITSELF ────────────────────────────────────────────────────────────────────────────
// A person's route is a polyline sampled from the street's curve, so a step is paced by distance
// (the way animateMotion paced it), not by the curve's parameter. One traverse of the route lasts
// `lap` seconds — the ×3 slow-down the owner asked for is untouched (row 248: strollers 18-42 s,
// walkers 42-78 s). The cycle is the owner's words: walk out, stop for a while somewhere along the
// way, walk to the end, rest, walk back with another stop, rest; every stop's place and length is
// the city's own seed. `phase` is the person's own start, so the crowd is never in step.

import { useEffect, useLayoutEffect, type RefObject } from 'react'

export type Pt = { x: number; y: number }

/** A route in the plan's own units: a polyline with its cumulative lengths. */
export interface Route {
  readonly pts: readonly Pt[]
  readonly cum: readonly number[]
  readonly length: number
}

/** One leg of the cycle: walking `from` → `to` (distances along the route) over `secs`; `from === to` is standing. */
export interface Leg {
  readonly secs: number
  readonly from: number
  readonly to: number
}

export interface Walk {
  readonly route: Route
  /** Seconds for one traverse of the route — the SMIL `dur` the owner's ×3 is measured on. */
  readonly lap: number
  /** Seconds; negative = already under way at document time 0 — the SMIL `begin` that spreads the crowd. */
  readonly phase: number
  readonly legs: readonly Leg[]
  /** The cycle's length in seconds: the sum of the legs. */
  readonly period: number
}

/** How often the people are moved: 20 times a second. A walker's pace is 2-5 plan units a second —
 *  0.2-0.7 px a step at the owner's widest glass — so finer steps cost frames and buy nothing. */
export const WALK_HZ = 20

/** A route from a polyline (the street's curve, already sampled). */
export function routeOf(pts: readonly Pt[]): Route {
  const cum: number[] = [0]
  for (let i = 1; i < pts.length; i++) cum.push(cum[i - 1] + Math.hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y))
  return { pts, cum, length: cum[cum.length - 1] }
}

/** The point `s` units along the route (clamped to its ends). */
export function pointAt(route: Route, s: number): Pt {
  const { pts, cum } = route
  if (s <= 0) return pts[0]
  if (s >= route.length) return pts[pts.length - 1]
  let lo = 0
  let hi = cum.length - 1
  while (hi - lo > 1) {
    const mid = (lo + hi) >> 1
    if (cum[mid] <= s) lo = mid
    else hi = mid
  }
  const span = cum[hi] - cum[lo]
  const t = span > 0 ? (s - cum[lo]) / span : 0
  return { x: pts[lo].x + (pts[hi].x - pts[lo].x) * t, y: pts[lo].y + (pts[hi].y - pts[lo].y) * t }
}

/**
 * A person's cycle on a route. `lap` is the time for one traverse; `back` says the SMIL `dur` covered
 * there AND back (the strollers' `keyPoints 0;1;0`), so each way is half of it. `rnd(n)` is the
 * city's seeded 0..1 for the n-th draw, so the same harbour walks the same way everywhere.
 */
export function walkOf(route: Route, lap: number, phase: number, back: boolean, rnd: (n: number) => number): Walk {
  const L = route.length
  const way = back ? lap / 2 : lap
  const legs: Leg[] = []
  const walk = (from: number, to: number, secs: number) => {
    if (secs > 0) legs.push({ secs, from, to })
  }
  const stand = (at: number, secs: number) => {
    if (secs > 0) legs.push({ secs, from: at, to: at })
  }
  if (back) {
    // a stroller: a short line there and back, a breath at each end
    walk(0, L, way)
    stand(L, 0.5 + rnd(0) * 2)
    walk(L, 0, way)
    stand(0, 0.5 + rnd(1) * 2)
  } else {
    // a walker: out with one stop on the way, a rest at the end, back with another stop, a rest
    const q1 = 0.25 + rnd(0) * 0.5
    const q2 = 0.25 + rnd(2) * 0.5
    walk(0, q1 * L, way * q1)
    stand(q1 * L, 2 + rnd(1) * 5)
    walk(q1 * L, L, way * (1 - q1))
    stand(L, 1 + rnd(3) * 5)
    walk(L, q2 * L, way * (1 - q2))
    stand(q2 * L, 2 + rnd(4) * 5)
    walk(q2 * L, 0, way * q2)
    stand(0, 1 + rnd(5) * 5)
  }
  const period = legs.reduce((sum, l) => sum + l.secs, 0)
  return { route, lap, phase, legs, period }
}

/** Where a person is at document time `t` (seconds). */
export function walkAt(walk: Walk, t: number): Pt {
  const { period, legs } = walk
  let local = (t - walk.phase) % period
  if (local < 0) local += period
  for (const leg of legs) {
    if (local < leg.secs) {
      return pointAt(walk.route, leg.from + (leg.to - leg.from) * (local / leg.secs))
    }
    local -= leg.secs
  }
  return pointAt(walk.route, legs[legs.length - 1]?.to ?? 0)
}

/** The `transform` that puts a circle (no cx/cy) at a point. */
export function placeAt(p: Pt): string {
  return `translate(${p.x.toFixed(2)} ${p.y.toFixed(2)})`
}

/** True when the player has asked for less motion — or when there is no `matchMedia` to ask (the
 *  reading components/ui/Counter.tsx and chart/underway.ts take: no answer means no animation). */
function still(): boolean {
  if (typeof window === 'undefined' || typeof window.matchMedia !== 'function') return true
  return window.matchMedia('(prefers-reduced-motion: reduce)').matches
}

/** A moving circle and its walk; `at` is the transform last written, so a person standing still costs no write. */
interface Person {
  el: Element
  walk: Walk
  at: string
}

function findPeople(svg: SVGSVGElement, walks: readonly Walk[]): Person[] {
  const people: Person[] = []
  for (const el of svg.querySelectorAll('circle[data-walk]')) {
    const walk = walks[Number(el.getAttribute('data-walk'))]
    if (walk) people.push({ el, walk, at: el.getAttribute('transform') ?? '' })
  }
  return people
}

/** Put every person where document time `t` has them — one attribute per person who moved. */
function place(people: Person[], t: number): void {
  for (const p of people) {
    const next = placeAt(walkAt(p.walk, t))
    if (next === p.at) continue
    p.at = next
    p.el.setAttribute('transform', next)
  }
}

/**
 * MOVE THE PEOPLE. `walks[i]` is the person whose circle carries `data-walk="i"` under `svgRef`.
 * The circles are found once per set of walks, placed before the first paint (so React's rendered
 * phase position is never on the glass), then moved WALK_HZ times a second while the document is
 * visible and the plan is on the glass. Under reduced motion they are placed once and left.
 */
export function useCityWalk(svgRef: RefObject<SVGSVGElement | null>, walks: readonly Walk[]): void {
  useLayoutEffect(() => {
    const svg = svgRef.current
    if (!svg) return
    place(findPeople(svg, walks), performance.now() / 1000)
  }, [svgRef, walks])

  useEffect(() => {
    const svg = svgRef.current
    if (!svg || walks.length === 0) return
    const people = findPeople(svg, walks)
    let frame = 0
    let last = -Infinity
    let onGlass = true
    const step = (now: number) => {
      frame = requestAnimationFrame(step)
      if (now - last < 1000 / WALK_HZ - 1) return
      last = now
      place(people, now / 1000)
    }
    const halt = () => {
      if (frame !== 0) cancelAnimationFrame(frame)
      frame = 0
    }
    const run = () => {
      if (frame !== 0 || still() || document.visibilityState === 'hidden' || !onGlass) return
      last = -Infinity
      frame = requestAnimationFrame(step)
    }
    const onVisibility = () => (document.visibilityState === 'hidden' ? halt() : run())
    const motion = typeof window.matchMedia === 'function' ? window.matchMedia('(prefers-reduced-motion: reduce)') : null
    const onMotion = () => (still() ? halt() : run())
    const seen =
      typeof IntersectionObserver === 'function'
        ? new IntersectionObserver((entries) => {
            onGlass = entries.some((e) => e.isIntersecting)
            if (onGlass) run()
            else halt()
          })
        : null
    seen?.observe(svg)
    document.addEventListener('visibilitychange', onVisibility)
    motion?.addEventListener('change', onMotion)
    run()
    return () => {
      halt()
      seen?.disconnect()
      document.removeEventListener('visibilitychange', onVisibility)
      motion?.removeEventListener('change', onMotion)
    }
  }, [svgRef, walks])
}
