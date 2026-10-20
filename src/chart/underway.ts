// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A HULL UNDER WAY, BETWEEN ONE MODEL AND THE NEXT — the chart's own frame, nothing else's
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, OWNER_REQUESTS row 169 (2026-10-20): *"I want the ship movement to be smooth, not by
// ticks."*
//
// ── WHAT WAS TICKING ───────────────────────────────────────────────────────────────────────────
// Not the read. 0075 already drew her between reads (./drift.ts): the model is a function of the
// shell's one clock, so a hull was placed a finer fraction along her leg than the 7.5-second read
// could place her. But that clock ticks ONCE A SECOND (app/AppShell.tsx — "one second is the
// coarsest tick that still lets a 12s readout look alive"), and once a second is a TICK: she held
// still for a second and then stepped. At the live compression a step is a nautical mile and a
// half, which is a pixel at the globe and tens of pixels on a harbour approach.
//
// The fix is not a faster clock. Re-running `buildChartModel` sixty times a second is the thing
// 2026-10-12 measured and removed (*"the game looks stuck"*): every memo in ChartCanvas keyed on
// the model would miss, 252 harbours would re-render, and the labels would be re-planned, per
// frame, so that a few hundred hulls could move a pixel. So the model stays on its one-second
// beat, and THIS file moves the hulls in between — by writing one attribute per hull per frame,
// outside React, on a single animation frame shared by the whole sheet.
//
// ── WHAT IT MAY DO, WHICH IS WHAT ./drift.ts MAY DO ────────────────────────────────────────────
// Nothing here is a second mover. The point it paints is `driftedPoint`'s — the same interpolation
// of the same served leg, asked for at the frame's instant instead of the second's — read off the
// SERVER'S clock (lib/serverClock `serverNow`, the one clock this device has). Every property the
// ledger pinned on 0075 therefore still holds, including the two that matter most here: she cannot
// be drawn past the vertex the next read will hand back, and she cannot be drawn past the arrival
// instant.
//
// ── SHE CONVERGES; SHE NEVER SNAPS ────────────────────────────────────────────────────────────
// A read can disagree with where she was drawn — the pace this chart drifts her at is the server's
// remaining-miles-over-remaining-time, and the server settles against the frozen profile, so the
// two agree closely and not exactly. A jump backwards is precisely the thing this slice removes, so
// the drawn point CHASES the served one: every frame it closes `glideShare` of the gap
// (`UNDERWAY_GLIDE_MS`, ./chartView.ts). She therefore trails her served place by a fifth of a
// second of her own passage and absorbs a correction over half a second, in either direction, and
// a frame's drawn point is always a blend of two points the server would own — so the convergence
// cannot carry her past her destination either.
//
// A gap too big to be a correction is NOT eased: see `UNDERWAY_SNAP_DEG`.
//
// ── WHAT FOLLOWS HER ───────────────────────────────────────────────────────────────────────────
// Everything that is drawn AT her, so the picture cannot come apart: her hull (FleetsLayer), her
// course's split and its arrowhead (TracksLayer), and her name (LabelsLayer). Each one hands this
// file a `paint` of its own, because the string that places a hull and the string that places a
// name belong to the layers that draw them, not here. A merchant is a hull like any other and
// arrives through the same door (the owner: *"all ships including npcs"*).
//
// A tap still resolves against the MODEL's position (hitTest, shipMarks) — a fifth of a second
// behind the glass, which is a pixel against a 38-pixel reach.
//
// ── A PLAYER WHO ASKED FOR LESS MOTION GETS NONE ──────────────────────────────────────────────
// `prefers-reduced-motion: reduce` and no frame is asked for at all: the chart is then exactly the
// chart before this file — the served point, once a second. The preference is watched, so a player
// who changes it is answered without a reload.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { useEffect, useLayoutEffect, useRef } from 'react'
import { lonLerp, shortLonDelta, type LatLon } from '../lib/geo'
import { serverNow } from '../lib/serverClock'
import type { FleetOnChart } from './chartModel'
import { glideShare, UNDERWAY_GLIDE_MS } from './chartView'
import { driftedPoint } from './drift'
import type { MapVoyage } from './mapTypes'

/**
 * HOW FAR A READ MAY DISAGREE AND STILL BE A CORRECTION, in degrees — beyond it she is put where
 * the server says at once.
 *
 * A correction is a fraction of the miles she makes between two reads: ten nautical miles at the
 * live clock, a sixth of a degree. A whole degree is sixty, which is not a correction — it is a
 * different passage: she arrived and was sent on, she was re-ordered, or she has just come back
 * onto the glass after a pan and has no drawn point worth keeping. Easing across that would be a
 * hull swimming over the water for half a second with no passage under it, so the honest answer is
 * the server's point, now.
 */
export const UNDERWAY_SNAP_DEG = 1

/** The served leg a follower carries: enough to ask ./drift.ts where she is at any instant, and
 *  where the model drew her, which is what the things placed BESIDE her were placed against. */
export interface UnderwayLeg {
  readonly voyage: MapVoyage
  /** When her served position was true (`FleetOnChart.readAtMs`). */
  readonly readAtMs: number
  /** Where the model drew her (`FleetOnChart.at`) — her place on the last one-second beat. */
  readonly at: LatLon
}

/**
 * IS SHE UNDER WAY, AND WHEN WAS THAT TRUE — the one reading of a drawn fleet that this file needs,
 * taken here so the three layers that follow her cannot each decide it differently. Null for a hull
 * at a quay or at an anchor, and for a model built with no clock (`SmallChart`), which both mean the
 * same thing: she is drawn where the model drew her.
 */
export function legOf(fleet: FleetOnChart): UnderwayLeg | null {
  return fleet.voyage && fleet.readAtMs !== null
    ? { voyage: fleet.voyage, readAtMs: fleet.readAtMs, at: fleet.at }
    : null
}

/**
 * WHERE TO DRAW HER THIS FRAME — the whole of this file's arithmetic, pure.
 *
 * `drawn` is where the last frame left her (null on her first), `target` is `driftedPoint`'s answer
 * for this instant, and `share` is how much of the gap this frame closes. Longitude is blended the
 * short way round (`lonLerp`, the convention of docs/NAVIGATION_PLAN.md §7), so a correction across
 * the antimeridian closes across the seam instead of sweeping the sheet.
 */
export function underwayStep(drawn: LatLon | null, target: LatLon, share: number): LatLon {
  if (!drawn || !Number.isFinite(share)) return target
  const dLat = target.lat - drawn.lat
  const dLon = shortLonDelta(drawn.lon, target.lon)
  if (Math.hypot(dLat, dLon) > UNDERWAY_SNAP_DEG) return target
  const s = Math.min(1, Math.max(0, share))
  return { lat: drawn.lat + dLat * s, lon: lonLerp(drawn.lon, target.lon, s) }
}

/** One element on the glass that is drawn at a hull, and what it does about her moving. */
interface Follower {
  /** Whose place this element follows, by fleet id — her hull, her course and her name share one. */
  id: string
  /** Her served leg, when this element was handed it; null when it was not (her name is not). */
  leg: UnderwayLeg | null
  /** Put the element at this point; `from` is where the MODEL drew her, for an element that is
   *  placed beside her rather than on her (her name). Both null = stand at the served place the
   *  model drew it at, which is what "there is nothing under way here" looks like. */
  paint: (at: LatLon | null, from: LatLon | null) => void
  /** Already standing at its served place, so there is nothing to write. A fleet's name outlives
   *  her passage (she docks and keeps her name), and a name at rest should cost no attribute. */
  resting: boolean
}

/** WHERE SHE IS BEING DRAWN, one per fleet — shared by every element that follows her, so her hull,
 *  her course and her name cannot be at three different points on one frame. */
interface Berth {
  voyage: MapVoyage
  readAtMs: number
  /** Where the model drew her on the last beat. */
  modelAt: LatLon
  drawn: LatLon | null
  /** Was her leg handed in on this frame? A berth nothing carries any more is dropped. */
  held: boolean
}

const followers = new Set<Follower>()
const berths = new Map<string, Berth>()
let frame = 0
let last = 0

/** True when the player has asked for less motion — or when there is no `matchMedia` to ask
 *  (the same reading components/ui/Counter.tsx takes: no answer means no animation). */
function still(): boolean {
  if (typeof window === 'undefined' || typeof window.matchMedia !== 'function') return true
  return window.matchMedia('(prefers-reduced-motion: reduce)').matches
}

function step(t: number) {
  const share = glideShare(t, last, UNDERWAY_GLIDE_MS)
  last = t
  const nowMs = serverNow()

  // THE SERVED LEGS, as the elements now hold them. A new read reaches this file the same way it
  // reaches the picture — through a render — so a berth is refreshed from whatever its followers
  // carry, and the drawn point survives that refresh. That is the convergence: the next frame
  // closes part of the gap between where she was drawn and where the new read puts her.
  for (const b of berths.values()) b.held = false
  for (const f of followers) {
    if (!f.leg) continue
    const held = berths.get(f.id)
    if (held) {
      held.voyage = f.leg.voyage
      held.readAtMs = f.leg.readAtMs
      held.modelAt = f.leg.at
      held.held = true
    } else {
      berths.set(f.id, {
        voyage: f.leg.voyage,
        readAtMs: f.leg.readAtMs,
        modelAt: f.leg.at,
        drawn: null,
        held: true,
      })
    }
  }

  for (const [id, b] of berths) {
    if (!b.held) berths.delete(id)
    else b.drawn = underwayStep(b.drawn, driftedPoint(b.voyage, { nowMs, readAtMs: b.readAtMs }), share)
  }

  for (const f of followers) {
    const b = berths.get(f.id)
    if (b?.drawn) {
      f.paint(b.drawn, b.modelAt)
      f.resting = false
    } else if (!f.resting) {
      f.paint(null, null)
      f.resting = true
    }
  }

  frame = requestAnimationFrame(step)
}

function run() {
  if (frame !== 0 || followers.size === 0 || still()) return
  last = performance.now()
  frame = requestAnimationFrame(step)
}

function halt() {
  if (frame !== 0) cancelAnimationFrame(frame)
  frame = 0
  berths.clear()
}

// THE PREFERENCE, WATCHED. Turned on, the frame stops and the hulls stay where the model puts them;
// turned off, the frame starts again on the next hull drawn. Attached once, with the module, and
// never removed — there is one chart.
if (typeof window !== 'undefined' && typeof window.matchMedia === 'function') {
  window.matchMedia('(prefers-reduced-motion: reduce)').addEventListener('change', () => {
    if (still()) halt()
    else run()
  })
}

/**
 * DRAW THIS ELEMENT WHERE SHE IS, EVERY FRAME.
 *
 * `id` null means this element follows nobody — a merchant lying at an anchor, a harbour's name —
 * and nothing is registered, no frame is asked for and `paint` is never called. `leg` is her served
 * leg for the elements that were handed it (her hull and her course); her name is not, and follows
 * the berth those open. The latest `paint` and `leg` are picked up on every render without
 * re-registering, so a pan — which re-renders the sheet and changes nothing about who is sailing —
 * costs one assignment a hull.
 */
export function useUnderway(
  id: string | null,
  leg: UnderwayLeg | null,
  paint: (at: LatLon | null, from: LatLon | null) => void,
): void {
  // ONE record per element, held across renders and written only from an effect — never read during
  // render, which is what `react-hooks/refs` is right about. The first effect keeps it current; the
  // second puts it on the frame for as long as this element follows somebody.
  const held = useRef<Follower | null>(null)
  // BEFORE THE BROWSER PAINTS THE NEW MODEL, PUT HER BACK WHERE SHE IS. React has just written the
  // model's own place into the DOM — a second behind the glass — and a frame will correct it ~16 ms
  // later: that correction would be a visible twitch backwards, once a second, which is the very
  // thing this file exists to remove. So the record is brought up to date and the element is painted
  // again HERE, in the same commit. With no frame running (reduced motion) there is no berth and
  // nothing is painted, which leaves the chart exactly as React drew it.
  useLayoutEffect(() => {
    const f = held.current
    if (!f) {
      held.current = { id: id ?? '', leg, paint, resting: true }
      return
    }
    f.id = id ?? ''
    f.leg = leg
    f.paint = paint
    const b = berths.get(f.id)
    if (!b) return
    if (f.leg) {
      b.voyage = f.leg.voyage
      b.readAtMs = f.leg.readAtMs
      b.modelAt = f.leg.at
    }
    if (b.drawn) {
      f.paint(b.drawn, b.modelAt)
      f.resting = false
    }
  })
  const follows = id !== null
  useEffect(() => {
    const f = held.current
    if (!f || !follows) return
    followers.add(f)
    run()
    return () => {
      followers.delete(f)
      if (followers.size === 0) halt()
    }
  }, [follows])
}
