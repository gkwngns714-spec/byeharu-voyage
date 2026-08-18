// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THREE GLYPHS AND NO MORE — DESIGN §E.5, as numbers.
//
//   1. THE PORT      a triangle. Two weights, never two shapes: QUIET for a port no fleet of yours
//                    is using, LOUD (larger, filled, brass, labelled) for one that is. §E.5: "▲ a
//                    port, ▲ filled + label a fleet at anchor" — so a fleet at anchor IS the loud
//                    port plus its name, not a fourth thing drawn on top of a third. Both weights
//                    are SCALED BY `size_tier`, so Lisboa and a Curaçao roadstead read as the same
//                    shape at different weights instead of as two identical dots.
//   2. THE FLEET     a dot on the dotted track, for a fleet at sea.
//   3. THE DESTINATION  a ring around the port a fleet is bound for.
//
// Nothing else goes on this chart. No rival, no hazard zone, no wind arrow, no grid, no compass
// rose, no scale bar with tick marks — every one of those is a thing to explain, and §E.5 asks for
// a chart you understand without being told.
//
// SIZES ARE IN CSS PIXELS AND STAY THERE. The layers multiply each by `unitsPerPx`, so a glyph is
// the same size on screen at every zoom — the paper scales, the marks on it do not. The floor is
// legibility on a 390 px phone, which is what these numbers were chosen against:
//   · loud port  10 px across, 9 px tall            · fleet dot 8.8 px across, in a 16 px halo
//   · quiet port 7.2 px across                      · labels 10.5 px mono
//   · every tappable thing gets a 44 px target (2 × HIT_RADIUS), the mobile touch floor
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/** Glyph metrics in CSS pixels. */
export const GLYPH = {
  quietPortHalfWidth: 3.6,
  quietPortHeight: 6.4,
  loudPortHalfWidth: 5,
  loudPortHeight: 9,
  destinationRingRadius: 11,
  fleetDotRadius: 4.4,
  fleetHaloRadius: 8,
  /** Half the touch target: 22 px radius = a 44 px tappable circle. */
  hitRadius: 22,
  labelSize: 10.5,
  labelGapX: 9,
  labelLineHeight: 12,
  /** The halo stroke that keeps a label readable where it crosses a coastline. */
  labelHaloWidth: 3.5,
  /** Hairline weights, drawn with vector-effect: non-scaling-stroke so they never fatten on zoom. */
  coastStroke: 0.9,
  trackStroke: 1.4,
  glyphStroke: 1.2,
} as const

/**
 * HOW BIG A PORT'S MARK IS, FOR ITS SIZE — the second half of the answer to 214 harbours (the
 * first is which ones are drawn at all: PORT_TIER_BANDS in ./chartView.ts).
 *
 * `size_tier` runs 1–5 and the seeded world uses 2, 3 and 5. The scale is linear across the whole
 * range so a tier the world does not use today still lands somewhere sensible:
 *
 *   tier 1 → 0.70×   tier 2 → 0.82×   tier 3 → 0.94×   tier 4 → 1.06×   tier 5 → 1.18×
 *
 * Against the quiet mark's 7.2 px width that is 5.0 px for a small harbour and 8.5 px for a great
 * one — a difference you can see at a glance without either becoming invisible or shouting. Out-of-
 * range or missing tiers clamp rather than vanish: bad data must not silently un-draw a port.
 */
export function portMarkScale(sizeTier: number): number {
  const tier = Number.isFinite(sizeTier) ? Math.min(5, Math.max(1, sizeTier)) : 3
  return 0.7 + 0.12 * (tier - 1)
}

/**
 * A triangle centred on (x, y), apex up — the port mark. Slightly top-heavy (0.6 of the height
 * above the centre, 0.4 below) so its visual centre of mass sits on the coordinate rather than
 * above it.
 */
export function trianglePath(x: number, y: number, halfWidth: number, height: number): string {
  const up = height * 0.6
  const down = height * 0.4
  return `M${x} ${y - up}L${x + halfWidth} ${y + down}L${x - halfWidth} ${y + down}Z`
}
