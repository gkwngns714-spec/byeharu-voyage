import type { BattleState } from './timeline'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// WHERE EACH SHIP IS DRAWN (0435, docs/design/tick-combat.md 9.3 "Positions: the server sends none").
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A pure function of (side, index, the motion clock, the battle's state): the two sides sail one slow ellipse, a side
// opposite the other, so they circle each other. A side's ships spread along its arc. Three moves ride on top:
//   · RUN    from her `U RN` to its `X` she turns outward and pulls away; away, she sails off the edge and fades; caught,
//            she turns back to the circle over a few ticks.
//   · JOIN   a ship that comes up at her `J` sails in from outside over a few ticks.
//   · STRUCK drawn by the stage (heel, sink, colours down); her place is kept.
// The heading is the direction of travel (two poses a moment apart), so every turn is the motion itself, never a
// second rule. Under reduced motion the stage asks with the orbit clock held at 0: the same places, still.

export interface Pose {
  x: number
  y: number
  /** degrees, 0 = pointing right */
  heading: number
  /** 0..1: 0 = gone (escaped, or not yet come up) */
  alpha: number
}

export interface SceneSize {
  w: number
  h: number
}

/** One lap of the ellipse, in seconds: slow enough to read as manoeuvring, fast enough to be seen to move. */
const LAP_S = 56
const JOIN_TICKS = 4
const TURN_BACK_TICKS = 8
const FADE_TICKS = 6
/** how near the edge a ship's middle may come: half a hull, so she is never cut */
const EDGE = 80

const smooth = (x: number) => {
  const c = Math.min(1, Math.max(0, x))
  return c * c * (3 - 2 * c)
}

function orbit(side: number, idx: number, count: number, sec: number, size: SceneSize) {
  const cx = size.w / 2
  // THE MIDDLE OF THE CIRCLE IS A LITTLE BELOW THE STAGE'S (owner 2026-11-15: "make the graphic of fight slightly lower"):
  // 62 % down (it was 54 %), so there is clear air under the two sides' bars. The circle is no taller than the room
  // left under it (a hull's half-length from the bottom edge), so no ship is pressed flat against the edge.
  const cy = size.h * 0.62
  const rx = size.w * 0.3
  const ry = Math.max(70, Math.min(Math.max(size.h * 0.26, 110), size.h - EDGE - cy))
  const spread = Math.min(0.9, 1.8 / Math.max(1, count))
  const theta = (side === 0 ? Math.PI : 0) + (sec / LAP_S) * Math.PI * 2 + (idx - (count - 1) / 2) * spread
  const k = 1 - 0.22 * (idx % 2)
  return { x: cx + rx * k * Math.cos(theta), y: cy + ry * k * Math.sin(theta), cx, cy }
}

/** Where ship `idx` of `side` is, at the motion clock `sec` and the playback tick `tf` (fractional). No heading. */
function place(side: number, idx: number, count: number, sec: number, tf: number, msTick: number, st: BattleState, size: SceneSize) {
  const o = orbit(side, idx, count, sec, size)
  let { x, y } = o
  let alpha = 1
  const reach = Math.min(size.w, size.h) * 0.6
  const outward = (ox: number, oy: number) => {
    const dx = ox - o.cx
    const dy = oy - o.cy
    const d = Math.hypot(dx, dy) || 1
    return { dx: dx / d, dy: dy / d }
  }
  // JOIN: not there before her tick; sails in from outside after it
  const ship = st.ships[side]?.[idx]
  if (ship) {
    if (!ship.up) return { x, y, alpha: 0 }
    if (ship.upAt > 0) {
      const p = smooth((tf - ship.upAt) / JOIN_TICKS)
      const { dx, dy } = outward(x, y)
      x += dx * reach * (1 - p)
      y += dy * reach * (1 - p)
      alpha = Math.min(alpha, 0.3 + 0.7 * p)
    }
  }
  // RUN: her side turned away at runFrom
  const sd = st.sides[side]
  if (sd && sd.runFrom !== null) {
    const from = sd.runFrom
    const rollAt = sd.rollAt
    const at = orbit(side, idx, count, (from * msTick) / 1000, size)
    const { dx, dy } = outward(at.x, at.y)
    let off: number
    if (rollAt === null) off = 0.55 * smooth((tf - from) / 20)
    else {
      const reached = 0.55 * smooth((rollAt - from) / 20)
      off = sd.away ? reached + 0.9 * smooth((tf - rollAt) / FADE_TICKS) : reached * (1 - smooth((tf - rollAt) / TURN_BACK_TICKS))
      if (sd.away) alpha = Math.min(alpha, 1 - smooth((tf - rollAt) / FADE_TICKS))
    }
    x += dx * reach * off
    y += dy * reach * off
    // one that got away sails off the edge; every other ship stays on the glass, her bar and name with her
    if (sd.away && rollAt !== null && tf >= rollAt) return { x, y, alpha }
  }
  if (ship?.up && !(ship.upAt > 0 && tf < ship.upAt + JOIN_TICKS)) {
    x = Math.min(size.w - EDGE, Math.max(EDGE, x))
    y = Math.min(size.h - EDGE, Math.max(EDGE + 30, y))
  }
  return { x, y, alpha }
}

export function shipPose(side: number, idx: number, count: number, sec: number, tf: number, msTick: number, st: BattleState, size: SceneSize): Pose {
  const a = place(side, idx, count, sec, tf, msTick, st, size)
  // the heading: where she is a moment later (both clocks moved on, so a still orbit still has a direction)
  const dt = 0.25
  const b = place(side, idx, count, sec + dt, tf + (dt * 1000) / msTick, msTick, st, size)
  let heading = (Math.atan2(b.y - a.y, b.x - a.x) * 180) / Math.PI
  if (!Number.isFinite(heading) || (b.x === a.x && b.y === a.y)) heading = side === 0 ? 90 : -90
  return { x: a.x, y: a.y, heading, alpha: a.alpha }
}

/** The stage's drawing box for a glass of `w` x `h` px: a narrow glass gets a smaller box, so the ships are drawn larger. */
export function sceneSize(w: number, h: number): SceneSize {
  const sw = Math.round(Math.min(1100, Math.max(620, w * 1.6)))
  const sh = Math.round(Math.min(sw * 1.8, Math.max(sw * 0.42, (sw * h) / Math.max(1, w))))
  return { w: sw, h: sh }
}
