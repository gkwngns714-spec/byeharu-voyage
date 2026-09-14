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
// ── 2026-09-13, OWNER ROW 90: "map should be much more graphic... it is too blank" ─────────────
// The three-glyph austerity above was measured out of the game the way §E.5's "no fill" was: the
// audit in docs/MAP_ATMOSPHERE.md counted THREE fills on the whole opening frame. So the sheet
// became a PICTURE, and this file stays the one authority for every mark on it:
//   · THE FLEET AT SEA IS A SHIP — `shipPath`, a hull pointing along her course heading. The dot
//     is gone; `shipHalfLength` replaces `fleetDotRadius` as the fleet mark's size (one name, one
//     number — tests/chart.ink.spec.ts moved its pin deliberately).
//   · THE COURSE ENDS IN AN ARROWHEAD — `arrowPath`, at the far end of the water ahead.
//   · A GREAT HARBOUR WEARS A RING — `greatPortRingRadius`, round a tier-`GREAT_PORT_TIER` mark, so
//     the hierarchy is SEEN at the opening frame and not only measured.
//   · THE COAST'S WEIGHT SCALES WITH ZOOM — `coastStrokeWidth(spanX)`: a hairline over the globe,
//     a firm line at a harbour approach. The COLOURS do not move (the ink spec pins them).
//   · THE SHALLOWS, THE RELIEF, THE GRATICULE AND THE SEA NAMES are furniture like the roadstead:
//     their pixel sizes are here (`shallowHaloPx`, `reliefPx`, `graticuleStroke`, `seaNameSize`,
//     `oceanNameSize`, `seaNameSpacingEm`), their inks are tokens in src/index.css, and the
//     decision of WHERE they go is data (./seaNames.ts, ./labels.ts).
// Nothing here decides; every number is a size, and every position is the server's.
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
  /**
   * THE SHIP (row 90): half the hull's length, bow to stern, in CSS pixels — 13 px overall, so
   * at arm's length on a phone it reads as a hull and not a dot, and still sits inside the 16 px
   * halo that keeps it legible over land. Replaces `fleetDotRadius` (4.4): the mark is longer
   * than the dot was wide because a hull has a heading and a dot has none.
   */
  shipHalfLength: 6.5,
  fleetHaloRadius: 8,
  /** The ring round a GREAT harbour's mark (row 90): 1.9× the loud tier-5 half-width, so it
   *  clears the triangle at every weight and is still well inside the destination ring (r 11). */
  greatPortRingRadius: 9.5,
  /** THE ARROWHEAD at the end of the water ahead: its half-width, in px. */
  arrowHalfWidth: 4,
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
  /** A GREAT harbour's name (row 90): one size up from the rest, so the marks' hierarchy reaches
   *  the names. Below `seaNameSize`'s spaced water type so a port never reads as a sea. */
  greatLabelSize: 12,
  labelGapX: LABEL_GAP_X_PX,
  labelLineHeight: 12,
  /** The halo stroke that keeps a label readable where it crosses a coastline. */
  labelHaloWidth: 3.5,
  /** Hairline weights, drawn with vector-effect: non-scaling-stroke so they never fatten on zoom.
   *  `coastStroke` is the coast's weight over the GLOBE — the floor `coastStrokeWidth` rises from. */
  coastStroke: 0.9,
  trackStroke: 1.4,
  glyphStroke: 1.2,
  /**
   * THE SHALLOWS (row 90): three bands of paler water hugging every coast, drawn as non-scaling
   * strokes of the land path UNDER the land body, widest first. In px so the band is the same
   * width at every zoom — a shore has shallows whether you are looking at the globe or a bay.
   */
  shallowHaloPx: [40, 22, 10],
  /** THE RELIEF: the inner shadow along the coast, clipped to the land. Non-scaling. */
  reliefPx: 6,
  /** THE GRATICULE: one hairline per 15° of latitude and longitude, quieter than the coast. */
  graticuleStroke: 0.7,
  graticuleStepDeg: 15,
  /** SEA NAMES: light type on the water. An ocean is set larger than a sea, and both are spaced
   *  the way a chart sets water — a cartographic convention, not UI copy (docs/MAP_ATMOSPHERE.md
   *  §6 records the one exception to docs/UI_DIRECTION.md §4.1 this is). */
  seaNameSize: 11.5,
  oceanNameSize: 14,
  seaNameSpacingEm: 0.14,
  /** A REGION'S NAME (row 92), set on its tint while the filter is on: between a sea and an
   *  ocean, spaced like water — it is ground, and a bigger piece of ground than a sea. */
  regionNameSize: 13,
  /**
   * THE DOT (row 93, 2026-09-14: "all the ports in the game when i zoom out, it can be a dot"):
   * a harbour below this zoom's full-mark tier is drawn as a filled dot of this radius, in the
   * quiet ink, with no name. 1.6 px — the smallest thing on the sheet after the roadstead ring
   * (hollow, 2.6), so 224 of them on the globe read as a scatter of ports and not as marks.
   */
  portDotRadius: 1.6,
  /**
   * AN ISLET (row 91): the speck of land drawn under a harbour whose island the 110m coast file
   * has no polygon for at all (Malta, Bermuda, the Azores… 28 of them, ./landfall.ts). A filled
   * circle in the land token with the coast's stroke, 4 px — under the quiet mark's 7.2 px width
   * and inside the great ring, so it is ground under the mark, never a mark of its own.
   */
  isletRadius: 4,
} as const

/**
 * THE COAST'S WEIGHT, FOR THIS ZOOM (row 90). Over the globe a hairline (`GLYPH.coastStroke`);
 * at the tightest zoom the chart allows, nearly twice that. Logarithmic in the span, because
 * zoom is: one press of + is the same step everywhere on the range, so the pen should thicken by
 * the same amount per press. Only the WEIGHT moves — the ink is the pinned token.
 */
export function coastStrokeWidth(spanX: number): number {
  const span = Number.isFinite(spanX) && spanX > 0 ? spanX : 360
  const t = Math.min(1, Math.max(0, (Math.log(360) - Math.log(span)) / (Math.log(360) - Math.log(1.5))))
  return GLYPH.coastStroke + 0.8 * t
}

/**
 * THE SHIP (row 90) — a hull centred on the origin with its BOW UP (−y), `halfLength` px long
 * from centre to bow. The layer places and turns it with a transform (`translate · rotate ·
 * scale`) so ONE path serves every fleet at every zoom, and the turn is the course's heading.
 * A hull and not a ship-shaped icon: at 13 px there is room for one clear silhouette, and a
 * pointed bow is what says "she is going that way" without a word.
 */
export function shipPath(halfLength: number): string {
  const l = halfLength
  const beam = l * 0.42
  return (
    `M0 ${-l}` +
    `L${beam} ${-l * 0.15}` +
    `L${beam * 0.85} ${l * 0.85}` +
    `L${-beam * 0.85} ${l * 0.85}` +
    `L${-beam} ${-l * 0.15}Z`
  )
}

/**
 * THE ARROWHEAD (row 90) — an open chevron whose TIP is the origin, pointing UP (−y), `halfWidth`
 * px each side. Placed and turned like the ship, so the water ahead ends in a point that says
 * where the passage is going. Open, not filled: it sits on the destination ring and must not
 * read as a fifth mark.
 */
export function arrowPath(halfWidth: number): string {
  const w = halfWidth
  return `M${-w} ${w * 1.4}L0 0L${w} ${w * 1.4}`
}

/** Degrees clockwise from north for the SVG `rotate()` that turns a bow-up glyph to point from
 *  `from` toward `to`, in chart units (y grows downward). Null when the two points coincide. */
export function headingDeg(from: { x: number; y: number }, to: { x: number; y: number }): number | null {
  const dx = to.x - from.x
  const dy = to.y - from.y
  if (dx === 0 && dy === 0) return null
  return (Math.atan2(dy, dx) * 180) / Math.PI + 90
}

/** `size_tier` as this file uses it: 1–5, and never NaN. Out-of-range or missing tiers CLAMP rather
 *  than vanish — bad data must not silently un-draw a port. One coercion, so the size ramp and the
 *  weight ramp below can never disagree about what tier a port is. */
function tierOf(sizeTier: number): number {
  return Number.isFinite(sizeTier) ? Math.min(5, Math.max(1, sizeTier)) : 3
}

/**
 * HOW BIG A PORT'S MARK IS, FOR ITS SIZE — the second half of the answer to 224 harbours (the
 * first is which ones wear their full mark at this zoom, and which are dots: PORT_TIER_BANDS in
 * ./chartView.ts).
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
