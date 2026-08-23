// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THREE GLYPHS AND NO MORE — DESIGN §E.5, as numbers.
//
//   1. THE PORT      a triangle. Two weights, never two shapes: QUIET for a port no fleet of yours
//                    is using, LOUD (larger, filled, brass, labelled) for one that is. §E.5: "▲ a
//                    port, ▲ filled + label a fleet at anchor" — so a fleet at anchor IS the loud
//                    port plus its name, not a fourth thing drawn on top of a third. Both weights
//                    are ranked by `size_tier` on TWO channels — how big the mark is
//                    (`portMarkScale`) and how firm its line is (`portStrokeWidth`) — so Lisboa and
//                    a Curaçao roadstead read as the same shape at different ranks instead of as
//                    two identical dots. One column, two channels, no second idea of importance.
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
//     (both are the TIER-3 size; `portMarkScale` runs them from 0.60× to 1.40× — 4.3 px to 10.1 px
//      across for a quiet mark — and `portStrokeWidth` runs the line from 0.70 px to 1.58 px)
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

/** `size_tier` as this file uses it: 1–5, and never NaN. Out-of-range or missing tiers CLAMP rather
 *  than vanish — bad data must not silently un-draw a port. One coercion, so the size ramp and the
 *  weight ramp below can never disagree about what tier a port is. */
function tierOf(sizeTier: number): number {
  return Number.isFinite(sizeTier) ? Math.min(5, Math.max(1, sizeTier)) : 3
}

/**
 * HOW BIG A PORT'S MARK IS, FOR ITS SIZE — the second half of the answer to 214 harbours (the
 * first is which ones are drawn at all: PORT_TIER_BANDS in ./chartView.ts).
 *
 *   tier 1 → 0.60×   tier 2 → 0.80×   tier 3 → 1.00×   tier 4 → 1.20×   tier 5 → 1.40×
 *
 * Against the quiet mark's 7.2 px width: 5.8 px for a small harbour, 7.2 for a middling one, 10.1
 * for a great one. Linear across the whole range, so a tier the world does not use today still
 * lands somewhere sensible.
 *
 * WHY THE RAMP WIDENED (2026-08-23). It was `0.7 + 0.12 × (tier − 1)`, and MEASURED on the running
 * chart at 390 px that drew a tier-3 mark 6.77 px wide against a tier-5 at 8.50 px — a 1.26× step
 * between two shapes otherwise identical in weight and in colour. 214 harbours drawn 26% apart is
 * 214 things said with equal emphasis, which emphasises nothing. Across the tiers the seeded world
 * actually uses (2, 3 and 5) the step is now 1.75×: a difference you read, rather than one you
 * could measure if it occurred to you to try.
 *
 * Size is only HALF the hierarchy. `portStrokeWidth` carries the other half — two channels, one
 * column, and no new idea of what makes a port important.
 */
export function portMarkScale(sizeTier: number): number {
  return 0.4 + 0.2 * tierOf(sizeTier)
}

/**
 * HOW FIRMLY A PORT'S MARK IS DRAWN, FOR ITS SIZE — the second channel, off the same column.
 *
 *   tier 1 → 0.70 px   tier 2 → 0.92 px   tier 3 → 1.14 px   tier 4 → 1.36 px   tier 5 → 1.58 px
 *
 * A great harbour is drawn with a firmer pen than a roadstead. It compounds with the size ramp
 * instead of competing with it: from tier 2 to tier 5 the mark grows 1.75× and its line thickens
 * 1.72×, so the great ports separate at a glance while the small ones stay perfectly legible.
 *
 * WHAT WAS REJECTED, and why. The obvious second channel is INK — fainter for a smaller port. It
 * was measured and dropped: the coast is now a real body (2.09 : 1 on the sea, see src/index.css)
 * and a hollow mark faded to ~55% ink sits on that land at 1.45 : 1, so the hierarchy would have
 * been bought by making the small ports hard to see, which is the opposite of the job. FILLING the
 * great ports was rejected more firmly still: a filled mark already MEANS "a fleet of yours is here
 * or bound here" (§E.5's loud/quiet split, ./PortsLayer.tsx), and a second meaning on one channel
 * is how a chart comes to need a legend.
 *
 * In CSS pixels like every other number in this file, and drawn with `vector-effect:
 * non-scaling-stroke`, so a hairline stays a hairline at 20×.
 */
export function portStrokeWidth(sizeTier: number): number {
  return 0.7 + 0.22 * (tierOf(sizeTier) - 1)
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
