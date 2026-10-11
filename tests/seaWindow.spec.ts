// PURE UNIT SPEC — src/live/seaWindow.ts. No browser: this file never asks for the `page` fixture,
// so Playwright runs it as a plain Node process.
//
// What it pins: the ONE place the shape `world.sea_traffic` is handed is built (0102,
// docs/NPC_FLEET_SCALE.md slice B). The server REFUSES a malformed window `E_BAD_VIEW` rather than
// widening it, which is the right posture for a server and the wrong thing for a screen to
// discover: a chart zoomed out past the globe has a viewBox that runs off the ±180 a window may
// name, and `clampView` makes that case normal rather than exceptional. So every window comes
// through here, and what this file asserts is exactly the set of things the server would refuse —
// each one turned into either a legal window or null, which IS the whole world.

import { test, expect } from '@playwright/test'
import { sameSeaWindow, seaWindowAround, seaWindowOf, seaWindowUnion } from '../src/live/seaWindow'
import { viewBoxToBounds } from '../src/lib/geo'

test('a window is what the server accepts, or it is null', () => {
  // An ordinary view on Iberia: through unchanged, in the server's own spelling.
  expect(seaWindowOf({ minLat: 34, maxLat: 43, minLon: -14, maxLon: -4 })).toEqual({
    south: 34,
    north: 43,
    west: -14,
    east: -4,
  })

  // THE WHOLE WORLD IS NULL, not ±90/±180 — cheaper to send and the one value that is never wrong.
  expect(seaWindowOf({ minLat: -90, maxLat: 90, minLon: -180, maxLon: 180 })).toBeNull()
  // ...and so is anything within the slack of it, because the server pads by 10° anyway.
  expect(seaWindowOf({ minLat: -85, maxLat: 85, minLon: -177, maxLon: 177 })).toBeNull()

  // ZOOMED OUT PAST THE GLOBE. `clampView` centres such a view, so the box legally runs off the
  // edges of the world; the window is clamped back in, never refused and never sent as -400.
  const wide = seaWindowOf({ minLat: -120, maxLat: 120, minLon: -400, maxLon: 400 })
  expect(wide).toBeNull()
  const tall = seaWindowOf({ minLat: -200, maxLat: 200, minLon: -20, maxLon: 10 })
  expect(tall).toEqual({ south: -90, north: 90, west: -20, east: 10 })

  // DEGENERATE AND NONSENSE: null, because a window the server would refuse is never worth sending.
  expect(seaWindowOf({ minLat: 10, maxLat: 10, minLon: 0, maxLon: 5 })).toBeNull()
  expect(seaWindowOf({ minLat: 0, maxLat: 5, minLon: 3, maxLon: 3 })).toBeNull()
  expect(seaWindowOf({ minLat: NaN, maxLat: 5, minLon: 0, maxLon: 5 })).toBeNull()
  expect(seaWindowOf({ minLat: 0, maxLat: Infinity, minLon: 0, maxLon: 5 })).toBeNull()

  // UPSIDE DOWN IS RIGHTED rather than refused: `viewBoxToBounds` cannot produce it, but a caller
  // that hands over a flipped rectangle gets the rectangle it meant.
  expect(seaWindowOf({ minLat: 43, maxLat: 34, minLon: -4, maxLon: -14 })).toEqual({
    south: 34,
    north: 43,
    west: -14,
    east: -4,
  })
})

test('a chart viewBox becomes the water it is showing', () => {
  // The chart's y axis grows DOWNWARD (project: y = -lat), so a box's top edge is its north one.
  // Going through `viewBoxToBounds` here rather than restating the projection is the point: the
  // window must be the water that was DRAWN, and there is one inverse of the projection.
  const box = { x: -14, y: -43, width: 10, height: 9 }
  expect(viewBoxToBounds(box)).toEqual({ minLat: 34, maxLat: 43, minLon: -14, maxLon: -4 })
  expect(seaWindowOf(viewBoxToBounds(box))).toEqual({ south: 34, north: 43, west: -14, east: -4 })
})

test("a harbour asks for its own coast, and a degenerate ask is the world", () => {
  expect(seaWindowAround({ lat: 38.7, lon: -9.14 }, 6)).toEqual({
    south: 32.7,
    north: 44.7,
    west: -15.14,
    east: -3.14,
  })
  // At the top of the world the latitude is clamped and the window is still legal.
  expect(seaWindowAround({ lat: 88, lon: 20 }, 6)).toEqual({ south: 82, north: 90, west: 14, east: 26 })
  expect(seaWindowAround({ lat: 38.7, lon: -9.14 }, 0)).toBeNull()
  expect(seaWindowAround({ lat: NaN, lon: -9.14 }, 6)).toBeNull()
})

test('the union covers every wanter, and one wanter wanting the world wins', () => {
  const map = { south: 34, north: 43, west: -14, east: -4 }
  const port = { south: 20, north: 28, west: -24, east: -14 }
  // A SUPERSET OF BOTH — the safe direction: a merchant in one screen's window is never missing
  // because another screen was looking somewhere else.
  expect(seaWindowUnion([map, port])).toEqual({ south: 20, north: 43, west: -24, east: -4 })
  expect(seaWindowUnion([map])).toEqual(map)

  // NOBODY HAS SAID WHERE THEY ARE LOOKING, or one of them wants the world: the world.
  expect(seaWindowUnion([])).toBeNull()
  expect(seaWindowUnion([null])).toBeNull()
  expect(seaWindowUnion([map, null])).toBeNull()

  // TWO WINDOWS EITHER SIDE OF THE ANTIMERIDIAN union to most of the globe and are then the world.
  // Not clever, and stated in the file: the clever answer is two windows on the wire, and this
  // world has no harbour within 10° of ±180 for it to matter to.
  expect(seaWindowUnion([
    { south: -10, north: 10, west: 170, east: 178 },
    { south: -10, north: 10, west: -178, east: -170 },
  ])).toBeNull()
})

test('an equal window is the same window, so a pan that changes nothing writes nothing', () => {
  const a = { south: 34, north: 43, west: -14, east: -4 }
  expect(sameSeaWindow(a, { ...a })).toBe(true)
  expect(sameSeaWindow(a, { ...a, east: -4.0001 })).toBe(false)
  expect(sameSeaWindow(null, null)).toBe(true)
  expect(sameSeaWindow(a, null)).toBe(false)
  expect(sameSeaWindow(null, a)).toBe(false)
})
