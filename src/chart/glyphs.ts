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
// ── 2026-10-11, OWNER ROW 120: "the ships, higher ships will have different graphics, such as in
//    size, two ships grouping, different graphics completely etc." ───────────────────────────────
// The fleet mark stopped being ONE hull at ONE size. `hullPath` draws the three hulls this world
// sails as three silhouettes, `GLYPH.hullHalfLength` sizes them off their burthen, and `hullGroup`
// draws a fleet of several AS several. Two channels, kept apart, neither needing a legend — see
// the block above `hullHalfLengthOf` for the whole of it, including the one zoom at which a group
// collapses back to her flagship. `shipPath` and `shipHalfLength` did not move: they are the hull
// with no class named, which is what every merchant is until `world.sea_traffic` serves one.
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

// The chart's own word for a served ship class lives with the rest of the read model; what each
// class LOOKS like is this file's, and this is the only thing it imports.
import type { HullClass } from './mapTypes'

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
  /**
   * HOW LONG EACH OF THE THREE HULLS IS DRAWN, centre to bow, in CSS px (owner row 120, 2026-10-11:
   * *"the ships, higher ships will have different graphics, such as in size, two ships grouping,
   * different graphics completely etc."*).
   *
   *   barca 5.7 (11.4 px overall) · carlat 6.5 (13.0 px) · nau 10.7 (21.4 px)
   *
   * THE MIDDLING HULL KEEPS `shipHalfLength`, so nothing already on this sheet changed weight: the
   * 13 px hull row 90 measured against the 16 px halo, the roadstead ring and the port marks is
   * still exactly the caravela latina's. The other two are that number times the CUBE ROOT of the
   * tonnage ratio, because a hull's length grows as the cube root of her burthen — which is why a
   * 400-tun carrack is not six barcas long: (60/90)^⅓ = 0.874 and (400/90)^⅓ = 1.645 against the
   * 60 / 90 / 400 tuns the shipwright rates the three at
   * (`…0003_the_real_world_and_the_water_between_it.sql:2089-2091`).
   *
   * THOSE TONNAGES ARE PROSE HERE AND NOT A TABLE, ON PURPOSE. `ship_classes.hold` is the server's
   * column and this file keeps no second copy of it (docs/NO_SPAGHETTI.md §1): these three are
   * GLYPH SIZES, like every other number in this file, and the arithmetic above is the record of
   * why they are these three and not three others. If the shipwright ever re-rates a hull the mark
   * does not silently drift — somebody moves a pin here, deliberately, and says so (§6).
   *
   * 1.88× bow to stern and ~3.1× in ink from the barca to the nau. `portMarkScale`'s header is the
   * measure that was applied: a difference you READ across a room, not one you could measure if it
   * occurred to you to try — its own ramp was widened to 1.75× for exactly that reason.
   */
  hullHalfLength: { barca: 5.7, carlat: 6.5, nau: 10.7 } as Record<HullClass, number>,
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
  /**
   * A DOT'S REACH (row 104, 2026-09-18: *"when i zoom out i see dot, when i click i see
   * coordinates. it should be the corresponding city or location"*). Half the touch floor and
   * nothing more: a dot has no name to the right of it and no mark width, so the whole reach is
   * the thumb's own. A name whose mark is within this same distance of the thumb beats any dot
   * (./hitTest.ts) — the measured Cádiz/Sanlúcar theft row 94 recorded, and the reason dots had
   * no tap at all until now.
   */
  dotHitRadius: TOUCH_TARGET_PX / 2,
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
  /** A REGION'S NAME (row 93), set on its tint while the filter is on: between a sea and an
   *  ocean, spaced like water — it is ground, and a bigger piece of ground than a sea. */
  regionNameSize: 13,
  /**
   * THE DOT (row 94, 2026-09-14: "all the ports in the game when i zoom out, it can be a dot"):
   * a harbour below this zoom's full-mark tier is drawn as a filled dot of this radius, in the
   * quiet ink, with no name. 1.6 px — the smallest thing on the sheet after the roadstead ring
   * (hollow, 2.6), so 224 of them on the globe read as a scatter of ports and not as marks.
   */
  portDotRadius: 1.6,

  /**
   * THE NIGHT CHART (owner row 125, 2026-10-12): *"when i zoom out, i want cities to be bright
   * light, in a dark map, visually beautiful. so are ships but in tiny dots… i want the color to be
   * in darker tone, size smaller, but like cities, there should be light"*.
   *
   * A HARBOUR'S LIGHT is two circles and no filter: a small bright CORE, and a HALO several times
   * its radius at low opacity, which is what makes a point read as a light rather than a dot. An
   * SVG blur filter would look better and cost a repaint of the filtered region on every drift
   * frame — `docs/MAP_ATMOSPHERE.md` §7 measured the frame budget at twelve wheel-zoom steps and
   * this chart has up to 252 harbours on it, so two circles it is.
   *
   * The CORE keeps `portDotRadius` — the dot row 94 already drew — so nothing moves position or
   * grows; what is added is the light around it.
   */
  harbourLightHaloScale: 3.4,
  /** How far a tier-5 entrepôt out-burns a tier-1 coast. The halo scales by this between them, so
   *  the great ports read first on a wide sheet and a one-quay coast is a faint spark — which is
   *  the owner's "bright light" without a legend and without a second colour. */
  harbourLightTierSpread: 0.55,

  /**
   * AN EMBER: the ship mark past `HULL_EMBER_MAX_UNITS_PER_PX`. Row 120 already collapses a
   * squadron to her flagship when the sheet gets wide; past this second, wider threshold the hull
   * SHAPE goes too and what is left is a dot with its own faint light. Smaller and dimmer than a
   * harbour on purpose: the owner's "ships… in tiny dots" and "darker tone" in one rule, so a
   * fleet never out-shouts a city on the same sheet.
   */
  emberRadius: 1.15,
  /**
   * AND THIS NUMBER IS BOUNDED BY THE ONE ABOVE IT, which is how it was found. The first cut of
   * row 125 set it to 2.6, and `tests/map.night.spec.ts` refused the file: an ember's halo came to
   * 1.15 x 2.6 = 2.99 chart units against a TIER-1 harbour's 1.6 x 3.4 x 0.45 = 2.45, so a lone
   * barca out-glowed the smallest city on the sheet — the exact inversion of *"cities… bright
   * light… so are ships but in tiny dots"*. The ordering is the owner's and it is a constraint on
   * this constant, not a matter of taste: whatever these two scales become, THE DIMMEST HARBOUR
   * MUST STILL OUT-BURN THE BRIGHTEST SHIP, and the spec holds that rather than this comment.
   */
  emberHaloScale: 1.9,
  /**
   * AN ISLET (row 92): the speck of land drawn under a harbour whose island the 110m coast file
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

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// OWNER ROW 120 — A FLEET'S MARK READS WHAT SHE IS
//
//   *"the ships, higher ships will have different graphics, such as in size, two ships grouping,
//    different graphics completely etc."*  (2026-10-11)
//
// Before this, one `shipPath` at one `shipHalfLength` stood for a fleet, whether that fleet was a
// single 60-tun barca or three 400-tun naus. Two channels answer it, and they are kept apart so
// neither can be mistaken for the other — which is `docs/MAP_ATMOSPHERE.md` §4's rule ("any new
// mark that needs a legend" was rejected) and `portStrokeWidth`'s ("a second meaning on one
// channel is how a chart comes to need a legend"):
//
//   WHAT SHE IS   the hull CLASS sets the silhouette (`hullPath`) and the size
//                 (`GLYPH.hullHalfLength`). Three shapes, not one shape scaled.
//   HOW MANY      the COUNT sets how many marks are drawn (`hullGroup`): one hull, two hulls, or
//                 a group of three for a squadron. Never a number, never a badge.
//
// NEITHER CHANNEL NEEDS TELLING. A bigger, heavier mark is a bigger ship; three hulls where there
// was one is three ships. There is nothing here a legend could add.
//
// ONE RENDERER FOR BOTH FLEETS AND MERCHANTS. ./FleetsLayer.tsx draws the merchants and your own
// fleets through these same two functions — the merchants in their nation ink with no halo, yours
// in the gold with one, which is how "yours" stayed loud before row 120 and still is. A second
// arrangement for the other list is the copy this section exists to forbid.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/**
 * HOW LONG THIS HULL IS DRAWN, centre to bow, in CSS px. A class the server did not name is the
 * class-less hull at `shipHalfLength` — the mark this chart drew before row 120, which says
 * nothing about her class because nothing is known about it (./mapTypes.ts `FleetHulls`).
 */
export function hullHalfLengthOf(cls: HullClass | null): number {
  return cls === null ? GLYPH.shipHalfLength : GLYPH.hullHalfLength[cls]
}

/**
 * ONE HULL, AS A SILHOUETTE — centred on the origin, BOW UP (−y), closed, `halfLength` px from
 * centre to bow. Placed and turned by the layer with one transform, exactly as `shipPath` is, so
 * one path serves every hull of that class at every zoom.
 *
 * THE THREE ARE DIFFERENT SHAPES AND NOT ONE SHAPE SCALED, and each one is the thing a sailor
 * would have recognised her by across a harbour:
 *
 *   barca   a coaster, DOUBLE-ENDED and slim — pointed at both ends, her beam a third of her
 *           half-length, widest forward of amidships. A spindle. No castle, because she had none.
 *   carlat  the caravela latina — slim forward and then the RAISED POOP: the after quarter steps
 *           out and ends in a wide square transom. One step, aft only.
 *   nau     the carrack — BROAD, and stepped at BOTH ends: a forecastle shoulder behind the stem
 *           and the great after-castle. Her beam is over half her half-length, so she reads heavy
 *           before her length is noticed.
 *
 * WHAT DOES MOST OF THE READING IS THE SIZE, AND THAT IS STATED RATHER THAN HOPED FOR. At 11 px a
 * barca has no room for a castle to be seen; at 21 px the nau's two are plain. So the silhouettes
 * CONFIRM a hierarchy the size already carries — the same division of labour `portMarkScale` and
 * `portStrokeWidth` make for the harbours, two channels off one column.
 *
 * NEITHER OF THE SHAPES ALREADY SPOKEN FOR IS REUSED. A triangle is a port and a lozenge is a sea
 * place (`trianglePath`, `lozengePath`): both are drawn AXIS-ALIGNED and HOLLOW, where every hull
 * here is FILLED and turned to a heading, and the barca's spindle is half the relative beam of the
 * lozenge the port ramps draw. A circle is a destination, a roadstead, an islet or a halo.
 */
export function hullPath(cls: HullClass | null, halfLength: number = hullHalfLengthOf(cls)): string {
  const l = halfLength
  // THE CLASS-LESS HULL IS `shipPath` AND NOT A FOURTH SILHOUETTE. One hull-with-no-class on this
  // chart, drawn by the function the minimap and row 90's whole measurement already use.
  if (cls === null) return shipPath(l)
  if (cls === 'barca') {
    const b = l * 0.33
    return (
      `M0 ${-l}` +
      `L${b} ${-l * 0.2}` +
      `L${b * 0.55} ${l * 0.55}` +
      `L0 ${l}` +
      `L${-b * 0.55} ${l * 0.55}` +
      `L${-b} ${-l * 0.2}Z`
    )
  }
  if (cls === 'carlat') {
    const b = l * 0.42
    return (
      `M0 ${-l}` +
      `L${b} ${-l * 0.15}` +
      `L${b * 0.95} ${l * 0.45}` +
      `L${b * 1.15} ${l * 0.55}` +
      `L${b * 1.15} ${l * 0.9}` +
      `L${-b * 1.15} ${l * 0.9}` +
      `L${-b * 1.15} ${l * 0.55}` +
      `L${-b * 0.95} ${l * 0.45}` +
      `L${-b} ${-l * 0.15}Z`
    )
  }
  const b = l * 0.52
  return (
    `M0 ${-l}` +
    `L${b * 0.55} ${-l * 0.72}` +
    `L${b * 0.74} ${-l * 0.6}` +
    `L${b} ${-l * 0.1}` +
    `L${b} ${l * 0.5}` +
    `L${b * 1.12} ${l * 0.58}` +
    `L${b * 1.12} ${l * 0.95}` +
    `L${-b * 1.12} ${l * 0.95}` +
    `L${-b * 1.12} ${l * 0.58}` +
    `L${-b} ${l * 0.5}` +
    `L${-b} ${-l * 0.1}` +
    `L${-b * 0.74} ${-l * 0.6}` +
    `L${-b * 0.55} ${-l * 0.72}Z`
  )
}

/** One hull of a fleet's mark: which class, how long, and where she sits in the group — the offset
 *  in CSS px, in the FLEET'S OWN FRAME (bow up, −y), so the layer's one `rotate` turns the whole
 *  formation onto her course. */
export interface HullMark {
  readonly cls: HullClass | null
  readonly halfLength: number
  readonly dx: number
  readonly dy: number
}

/**
 * HOW MANY HULLS A GROUP EVER DRAWS — three, and the fourth is not a mark that was forgotten.
 *
 * A fleet holds one to eight hulls (0021). Three is the most a mark can SAY without being told:
 * one, two and three are read at a glance, and past that any count has to be counted — a four-hull
 * fleet and an eight-hull fleet would be two pictures nobody could tell apart, so the mark would be
 * promising a precision it cannot deliver. So the group says ONE, TWO, or A SQUADRON, which is
 * true of every fleet of four and over, and the sheet says how many (the fleet tray, the merchant
 * card). `docs/MAP_ATMOSPHERE.md` §4: no mark that needs a legend, and no mark that needs counting.
 *
 * It is also the ink budget. The roster is about to grow tenfold — ~400 merchants on the water —
 * and three is the ceiling on what that multiplies by.
 */
export const HULL_GROUP_MAX = 3

/**
 * THE FORMATION — the flagship leading and the rest on her quarters, in units of the group's own
 * longest hull, in the fleet's own frame (bow up).
 *
 * THE FIRST PLACE IS THE ORIGIN, WHICH IS THE WHOLE REASON THIS IS SAFE. A one-hull fleet is drawn
 * at the served position to the pixel, exactly where she was drawn before row 120 — so the hit
 * test (`GLYPH.hitRadius`, ./hitTest.ts), the label anchor and the framing all go on reading one
 * position and none of them had to learn about a group.
 *
 * DETERMINISTIC, AND NOT BY HASHING ANYTHING. ./liveWorld.ts's `berthSlotOf` had to derive a
 * berth from a merchant's own id because a first cut took it from her place in the served list, and
 * hulls then moved whenever a neighbour docked. The lesson is the one applied here, and it is
 * applied by having NO free parameter at all: a fleet's arrangement is a pure function of her hull
 * list and her heading, both of which are hers. Nothing about another fleet appearing, leaving or
 * being selected can reach it, so there is no value to keep stable between reads.
 *
 * ±0.95 across and 1.35 astern leaves daylight between the two quarters at every class (a hull's
 * widest beam is 0.58 of her half-length, so the two astern are 1.90 apart on centres and 1.32
 * clear), and the keyline every hull already wears in the sea colour separates them where a turn
 * brings them together.
 */
const HULL_GROUP_PLACES: readonly { readonly ax: number; readonly ay: number }[] = [
  { ax: 0, ay: 0 },
  { ax: 0.95, ay: 1.35 },
  { ax: -0.95, ay: 1.35 },
]

/**
 * WHEN A GROUP STOPS BEING A GROUP AND BECOMES WEATHER — in chart units (degrees of longitude) per
 * CSS pixel, which is what `./FleetsLayer.tsx` is handed and, it turns out, the right measure.
 *
 * 0.115 °/px. Above it (pulled further back) a fleet draws her FLAGSHIP ALONE: the class channel
 * survives the collapse — a nau is still a big mark on the globe, which costs one mark either way
 * — and only the count channel is given up, because the count is what multiplies the ink.
 *
 * WHY A DENSITY AND NOT A SPAN. The other zoom rules on this chart are spans in degrees
 * (`LABEL_SPAN_LIMIT`, `SEA_NAME_SPAN_LIMIT`, `PORT_TIER_BANDS` in ./chartView.ts) because they
 * decide WHICH FEATURES OF THE WORLD are on the sheet, and that is a fact about the world. This
 * rule is about whether a mark's own parts are still telling them apart on the GLASS, and glyphs
 * are pixel-constant here (this file's header: "the paper scales, the marks on it do not"). A span
 * limit would therefore collapse the group on a phone and leave it drawn on a 1280 sheet showing
 * the same water at three times the room — the same picture judged two ways. Degrees per pixel is
 * the same judgement on both.
 *
 * THE NUMBER: 45° across a 390 px phone. 45° is `PORT_TIER_BANDS`' own boundary between "a sea"
 * and "the world" — the zoom at which this chart already decides it is looking at too much world
 * to draw the middling harbours — and 390 px is the narrowest glass the UI promises
 * (docs/UI_DIRECTION.md §6). So the group is drawn while the chart is looking at a coast or a sea
 * and not while it is looking at the world, and at 1280 px that same density is ~148° of span,
 * because 1280 px of glass really can hold three times the hulls.
 *
 * MEASURED, on the merchants-on world served by tests/npcOn.fixture.ts (76 merchant fleets,
 * `vite preview`, chromium, 2026-10-11), by `tests/map.hulls.spec.ts`:
 *
 *   390 px, opening frame   0.0382 °/px   13 merchant marks on the glass, 7 of them several hulls
 *   1280 px, same world     0.0116 °/px    7 marks, 5 of them several
 *   390 px, pulled to the globe             76 marks on the glass, EVERY ONE of them one hull
 *
 * That last row is the number this rule exists for: at the globe the sheet holds every merchant
 * there is, and three hulls each would be 228 marks on a 390 px phone. One each is 76, which is
 * what it was before row 120.
 *
 * THE 45 IS QUOTED, NOT OWNED — ./chartView.ts decides the tier bands and this file decides how a
 * mark is drawn. It is not imported because that would point the ink at the view, which is the
 * wrong way round for a file whose header says every number in it is a size; if the band ever
 * moves, this comment is the thread back. Named as a seam rather than tidied, the way
 * docs/NO_SPAGHETTI.md §7 asks.
 */
/**
 * PAST THIS, A FLEET IS AN EMBER AND NOT A HULL (owner row 125). Three times
 * `HULL_GROUP_MAX_UNITS_PER_PX`, which is the span where `PORT_TIER_BANDS` has already given up on
 * marks and drawn harbours as dots — so the two channels change at the same places on the zoom
 * ladder and the sheet never shows a 10 px carrack beside a 1.6 px city.
 *
 * The ladder, end to end: hull silhouettes and squadrons · flagship only · an ember.
 */
export const HULL_EMBER_MAX_UNITS_PER_PX = (45 / 390) * 3

export const HULL_GROUP_MAX_UNITS_PER_PX = 45 / 390

/**
 * THE NIGHT BAND: pulled back past this, every harbour on the glass carries its light (owner row
 * 125). Below it the chart is a working sheet — names, roads, roadsteads, a fleet's silhouette —
 * and a glow over that is a smudge across the detail somebody zoomed in to read, so NOTHING GLOWS
 * CLOSE IN and the close view is exactly what it was before row 125.
 *
 * THE LIGHT IS NOT THE DOT'S PROPERTY, which is the mistake the first cut of this row made. Row
 * 94's dot got a halo and the FULL MARK DID NOT, so at the globe the greatest ports in the world —
 * the high-tier entrepôts `PORT_TIER_BANDS` deliberately keeps drawn longest — were the only
 * harbours on the sheet not lit, and the owner's *"cities to be bright light"* came out as every
 * city but the cities. `tests/map.night.spec.ts` counted them: 35 unlit marks against 217 lights.
 * The gate is a DENSITY, applied to BOTH branches of ./PortsLayer.tsx.
 *
 * Set to `HULL_GROUP_MAX_UNITS_PER_PX` rather than to a number of its own: that is already the rung
 * where this chart stops drawing a squadron and starts drawing weather, so the sheet changes
 * character once, on one rung, instead of fading between two opinions about what "pulled back" is.
 */
export const HARBOUR_LIGHT_MIN_UNITS_PER_PX = HULL_GROUP_MAX_UNITS_PER_PX

/**
 * A FLEET'S MARK — which hulls are drawn, how big each is, and where each sits, in CSS px in her
 * own frame. THE ONE ARRANGEMENT, for your fleets and for the merchants alike.
 *
 * An EMPTY list draws one class-less hull at the origin, which is the mark this chart drew before
 * row 120: a fleet the server said nothing about hulls for is still a fleet, and she is not
 * un-drawn and not guessed at.
 */
export function hullGroup(hulls: readonly (HullClass | null)[], unitsPerPx: number): readonly HullMark[] {
  const grouped = Number.isFinite(unitsPerPx) && unitsPerPx <= HULL_GROUP_MAX_UNITS_PER_PX
  const drawn = hulls.length === 0 ? [null] : hulls.slice(0, grouped ? HULL_GROUP_MAX : 1)
  // THE GROUP IS SPACED OFF ITS LONGEST HULL, so a barca leading two naus is not run down by them.
  const unit = Math.max(...drawn.map(hullHalfLengthOf))
  return drawn.map((cls, i) => ({
    cls,
    halfLength: hullHalfLengthOf(cls),
    dx: HULL_GROUP_PLACES[i].ax * unit,
    dy: HULL_GROUP_PLACES[i].ay * unit,
  }))
}

/**
 * THE HALO ROUND A FLEET OF YOURS — ONE circle for the whole group, in her own frame, in CSS px.
 *
 * The halo is how YOURS stays loud (docs/MAP_ATMOSPHERE.md §5: the merchants have none), and it is
 * the sea-coloured ground that keeps a hull legible where she crosses the land. So it has to hold
 * the hulls that are actually drawn: one circle on the group's centre, wide enough to enclose every
 * hull in it. A SINGLE hull gives back the circle that was there before row 120 to the pixel — the
 * centre is the origin and the radius `fleetHaloRadius` — because her offset is the origin and her
 * halo is `fleetHaloRadius / shipHalfLength` of her length, which for the class-less hull is 8.
 *
 * ONE CIRCLE AND NOT THREE, decided rather than defaulted: three circles at 70% sea would compound
 * where they overlap and their three gold rings would cross, which is a cluster of bubbles and not
 * a fleet. One ring round a squadron says the thing the halo exists to say, once. The cost is
 * stated: a player's three carracks wear a ~46 px disc, the largest mark this chart draws — and
 * that is the biggest thing a house can put on the water, there are never many of them, and it is
 * hers.
 */
export function hullGroupHalo(marks: readonly HullMark[]): { readonly cx: number; readonly cy: number; readonly r: number } {
  const halo = (halfLength: number) => (halfLength * GLYPH.fleetHaloRadius) / GLYPH.shipHalfLength
  const cx = marks.reduce((s, m) => s + m.dx, 0) / marks.length
  const cy = marks.reduce((s, m) => s + m.dy, 0) / marks.length
  const r = Math.max(...marks.map((m) => Math.hypot(m.dx - cx, m.dy - cy) + halo(m.halfLength)))
  return { cx, cy, r }
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

/**
 * HOW BRIGHT THIS HARBOUR BURNS, 0..1, from its `size_tier` (owner row 125). Linear between the
 * tiers the world actually uses rather than a curve: the tiers are already an editorial judgement
 * about how big a place is, and bending them again here would be this file having an opinion about
 * geography, which is `docs/MAP_ATMOSPHERE.md`'s rule against a second authority.
 */
export function harbourLightStrength(sizeTier: number): number {
  const t = Math.max(1, Math.min(5, Number.isFinite(sizeTier) ? sizeTier : 1))
  return (t - 1) / 4
}

/** The halo radius for a harbour light, in chart units. The brightest tier gets the widest bloom;
 *  `harbourLightTierSpread` is how much of the halo is tier-dependent and how much every harbour
 *  gets for free — a tier-1 spark is still a light, just a small one. */
export function harbourLightHalo(sizeTier: number, unitsPerPx: number): number {
  const base = GLYPH.portDotRadius * GLYPH.harbourLightHaloScale
  const lit = 1 - GLYPH.harbourLightTierSpread + GLYPH.harbourLightTierSpread * harbourLightStrength(sizeTier)
  return base * lit * unitsPerPx
}
