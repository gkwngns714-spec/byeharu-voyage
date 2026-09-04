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
// 0076 ADDED A FOURTH MARK, and it is written here rather than left to be discovered: THE
// ROADSTEAD, the one point of open water a port is reached from (OWNER_REQUESTS row 72, "create a
// point there"). It earns its place on the sheet under the same test the three above pass — it is
// a thing you understand without being told, because it is drawn at the far end of a dotted line
// out of the harbour it belongs to, and because after 0076 the track of a real voyage STARTS and
// ENDS there. A chart that showed a ship leaving from a point it never marked would be the thing
// needing explanation. It is FURNITURE, not a glyph in §E.5's sense: faint ink like the coastline,
// never brass, and it says nothing about whether a fleet of yours is anywhere near it.
//
// SIZES ARE IN CSS PIXELS AND STAY THERE. The layers multiply each by `unitsPerPx`, so a glyph is
// the same size on screen at every zoom — the paper scales, the marks on it do not. The floor is
// legibility on a 390 px phone, which is what these numbers were chosen against:
//   · loud port  10 px across, 9 px tall            · fleet dot 8.8 px across, in a 16 px halo
//   · quiet port 7.2 px across                      · labels 10.5 px mono
//     (both are the TIER-3 size; `portMarkScale` runs them from 0.60× to 1.40× — 4.3 px to 10.1 px
//      across for a quiet mark — and `portStrokeWidth` runs the line from 0.70 px to 1.58 px)
//   · the reach a tap has for a glyph is `hitRadius`, DERIVED below rather than typed
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/**
 * THE TOUCH FLOOR, in CSS pixels — the smallest a target may be for a finger.
 *
 * 44 is WCAG 2.5.5 (Target Size, AAA) and Apple's HIG; Android/Material asks 48. It is the
 * EDGE-TO-EDGE size of a target, so half of it — 22 px — is how far from the point they aimed at
 * a finger may still land. The design system already builds every control to the same floor
 * (`buttonStyles.ts`'s `min-h-11` / `h-11 w-11`); this is the same fact for a thing drawn on a
 * chart, where there is no element to give a minimum height to.
 */
export const TOUCH_TARGET_PX = 44

/** The loud (in-use) port triangle's half-width at tier 3, in CSS pixels. Named out of the table
 *  below because the reach a tap has is DERIVED from it and an object cannot read itself. */
const LOUD_PORT_HALF_WIDTH_PX = 5

/** Where a name starts, measured from the mark it belongs to. Named for the same reason. */
const LABEL_GAP_X_PX = 9

/** Glyph metrics in CSS pixels. */
export const GLYPH = {
  quietPortHalfWidth: 3.6,
  quietPortHeight: 6.4,
  loudPortHalfWidth: LOUD_PORT_HALF_WIDTH_PX,
  loudPortHeight: 9,
  destinationRingRadius: 11,
  fleetDotRadius: 4.4,
  fleetHaloRadius: 8,
  /**
   * 0076 — THE ROADSTEAD MARK: a small HOLLOW circle on the one point of open water a port is
   * reached from, at the far end of its dotted helper line (./RoadsteadsLayer.tsx).
   *
   * 2.6 px is the quiet harbour mark's 3.6 px half-width less its stroke, so at the tier the two
   * ramps are centred on the roads read as SMALLER than the port they belong to (5.2 px across
   * against 7.2). It has to be none of the three round things already on this sheet, and radius is
   * the channel it uses: the destination ring is r 11 dashed brass, the fleet dot r 4.4 FILLED
   * brass and haloed, and this is the smallest, hollow, in ink rather than brass — because a
   * roadstead is true of every harbour whether a fleet of yours uses it or not.
   */
  roadsteadRadius: 2.6,
  /**
   * 0076 — HOW SEPARATED THE ROADS MUST LOOK BEFORE THEY ARE DRAWN, in CSS pixels.
   *
   * 6 px is `2 × loudPortHalfWidth × portMarkScale(1)` — the full width of the SMALLEST mark this
   * chart draws in its loud weight. A helper line shorter than a port mark is not a helper, it is
   * a smudge on the mark it leaves, so below this the pair is not drawn at all.
   *
   * IT IS A RULE ABOUT THE PICTURE, AND IT IS IN PIXELS BECAUSE THE PICTURE IS. On this
   * equirectangular sheet a degree is the same length everywhere, so the same nautical mile buys
   * more line the further from the equator a harbour lies: at the opening frame (12° across a
   * 390 px phone) 6 px is 0.185°, which is 11.1 nm at the equator and under 6 nm in the Baltic.
   * Measured on this world (tests/map.roadsteads.spec.ts): of the 159 harbours with roads off the
   * quay, NONE draws with the whole world in one frame, 132 draw at the opening frame, and all 159
   * draw at the tightest zoom. Zoom is the precision control it already was (see `hitRadius`).
   */
  roadsteadMinPx: 6,
  /**
   * HOW FAR FROM A GLYPH A TAP STILL MEANS THAT GLYPH — 38 px, and every term is measured.
   *
   * ── WHAT IT WAS, AND THE DEFECT IT SHIPPED (measured 2026-08-25) ────────────────────────────
   * It was `22` with the comment *"half the touch target: 22 px radius = a 44 px tappable
   * circle"*. That arithmetic treats the MARK'S CENTRE as the thing the player aims at, and on
   * the running app it is not. Driven in a real browser at 1389×900, on the seeded world:
   *
   *     Cadiz  mark centre x=959.6   ·  its name "Cadiz" runs x=968.6 … 1000.1
   *     → the centre of the word is 24.8 px from the mark, and a tap there returned
   *       OPEN SEA 36.4°N 6.4°W — a plausible-looking panel for a different act.
   *     Walked outwards from the mark: 18 px selected Cadiz, 22 px was open sea.
   *
   * The harbour a player sees is the mark AND its name. Under the old number the NAME — much the
   * larger half of it, and the half you read — lay entirely outside the harbour's own target,
   * and missing it was silent: you got a free-coordinate destination beside the port instead of
   * a refusal or a miss. `docs/OWNER_REQUESTS.md:102`: *"A button that landed on the wrong port
   * would be worse than no button."* This is that, one step quieter.
   *
   * ── THE DERIVATION ──────────────────────────────────────────────────────────────────────────
   *     labelGapX                  9 px   where the name starts, measured from the mark
   *   + TOUCH_TARGET_PX / 2       22 px   how far a finger lands from the point it aimed at
   *   + the largest mark's half-extent    the mark has a BODY: loudPortHalfWidth × portMarkScale(5)
   *                               7 px    = 5 × 1.4, and the DOM measured that mark 14.00 px wide
   *   ────────────────────────────────
   *                               38 px
   *
   * Checked against the names the running app actually drew (their own centres, from the mark):
   * Cadiz 24.8, Porto 24.8, Lisbon 27.9, Malaga 27.9, Sevilla 31.0 — every one inside 38 with
   * room to spare, so **a tap on a harbour's name selects that harbour**.
   *
   * ── WHAT IT DOES NOT FIX, STATED RATHER THAN HALF-BUILT ─────────────────────────────────────
   * A long name has a tail outside the reach: `Strait of Gibraltar` measured 119.6 px wide, so
   * its far end is 129 px from the mark. The honest fix for that is not a bigger radius — it is
   * hit-testing the label's own BOX, which needs the label PLAN (./labels.ts, planned inside
   * ChartCanvas against the selection and the chrome). Recomputing that plan at tap time would be
   * a second author of where a name is, and the two could disagree about which names were even
   * printed. It stays one authority and one radius until the plan is lifted for both.
   *
   * ── WHAT IT COSTS, AND WHY THAT IS THE RIGHT TRADE ──────────────────────────────────────────
   * Free-sea pinpointing (0039) is unchanged everywhere that is not near a drawn harbour, and
   * near one it is a zoom away: the reach is 38 CSS px at EVERY zoom, so it covers 70 nm on the
   * opening frame and 9 nm four steps in. Zoom is the precision control it always was. Nothing
   * here can pick the WRONG harbour — nearest still wins (./hitTest.ts).
   */
  // `portMarkScale` is a hoisted function declaration below, so the ramp has ONE author and this
  // term reads it rather than restating `0.4 + 0.2 × 5`.
  hitRadius: LABEL_GAP_X_PX + TOUCH_TARGET_PX / 2 + LOUD_PORT_HALF_WIDTH_PX * portMarkScale(5),
  labelSize: 10.5,
  labelGapX: LABEL_GAP_X_PX,
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

/**
 * A lozenge (diamond) centred on (x, y) — the SEA-PLACE mark (0036). A different SHAPE, not a
 * different weight or ink: the triangle already means "a town with a quay", and both of the other
 * channels are spoken for (weight = a fleet of yours is using it, ink was rejected for the small
 * ports — see portStrokeWidth's header). Symmetric about the coordinate because a bank or a strait
 * IS the coordinate — there is no town above the waterline for the mark to sit under. Sized off
 * the same ramps as the triangle, so the two families rank together at every zoom.
 */
export function lozengePath(x: number, y: number, halfWidth: number, height: number): string {
  const half = height * 0.5
  return `M${x} ${y - half}L${x + halfWidth} ${y}L${x} ${y + half}L${x - halfWidth} ${y}Z`
}
