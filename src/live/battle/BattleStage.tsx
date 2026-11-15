import { useEffect, useId, useLayoutEffect, useRef, useState, type ReactNode } from 'react'
import type { TickTimeline } from '../../lib/rpc'
import { useT } from '../../lib/i18n'
import { sceneSize, shipPose, type SceneSize } from './scene'
import type { BattleEvent, BattleState } from './timeline'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE STAGE (0435, docs/design/tick-combat.md 11): our own plain SVG hulls seen from above, circling.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// TWO CLOCKS, ON PURPOSE. React draws once a TICK (600 ms): the hull bars, the brace ring, who is down, and the tick's
// effects (a flash and smoke at the gun, a tracer, a splash at a miss, the hit number rising, larger at a crit). Between
// ticks one requestAnimationFrame loop moves each ship's two transforms directly (place and heading), so a phone redraws
// nothing else 60 times a second. Each effect is a CSS animation keyed by its event, mounted for two ticks.
// REDUCED MOTION: no loop at all, the orbit held still; each tick's effects stand still for their two ticks (the
// `data-motion` rule in src/index.css), and a ship that is down is drawn down.
// SMALLER SHIPS, A WIDER SEA (owner 2026-11-16: "fighting graphics (ships), make it smaller, and fight scene more wider"):
// a hull is drawn at SHIP_SCALE (six tenths of what it was), her bar, her name and her brace ring with her; the hit numbers
// and the ability's word keep their size, so they stay readable. The wider circle is ./scene.ts.

const SIDE_TONE = ['var(--color-info)', 'var(--color-danger)'] as const
const HULL_FILL = 'color-mix(in srgb, var(--color-accent) 30%, var(--color-bg))'
const DECK_FILL = 'color-mix(in srgb, var(--color-accent) 48%, var(--color-bg))'

/** A hull's drawn size against the shape's own units: six tenths (it was 1). */
const SHIP_SCALE = 0.6
/** A hit number (and a patch's) begins this far above her middle: over her bar and her name, which sit close on a small hull. */
const NUM_UP = 80
/** How much bigger a heavier hull is drawn. */
const tierScale = (t: number) => (1.02 + Math.min(5, Math.max(1, t || 1)) * 0.08) * SHIP_SCALE

function hullTone(share: number) {
  return share > 0.5 ? 'var(--color-success)' : share > 0.25 ? 'var(--color-warning)' : 'var(--color-danger)'
}

/** Our own hull, seen from above, bow to the right: a long pointed hull, a deck, three masts with their sails. */
function ShipShape({ side, struck }: { side: number; struck: boolean }) {
  return (
    <>
      {/* the wake */}
      <path d="M -56 -12 Q -96 -10 -138 -26 Q -104 0 -138 26 Q -96 10 -56 12 Z" fill="var(--color-ink)" fillOpacity={0.12} />
      <path
        d="M -60 -13 Q -40 -19 8 -19 Q 44 -17 64 0 Q 44 17 8 19 Q -40 19 -60 13 Z"
        fill={HULL_FILL}
        stroke={SIDE_TONE[side]}
        strokeWidth={3}
      />
      <path d="M -52 -9 Q -36 -13 6 -13 Q 36 -12 50 0 Q 36 12 6 13 Q -36 13 -52 9 Z" fill={DECK_FILL} />
      {/* bowsprit */}
      <line x1={62} y1={0} x2={84} y2={0} stroke={HULL_FILL} strokeWidth={3} />
      {/* the sails across the yards, bellied forward */}
      {[-30, 0, 28].map((x, k) => (
        <path
          key={x}
          d={`M ${x - 2} ${-(30 - k * 2)} Q ${x + 9} 0 ${x - 2} ${30 - k * 2} L ${x - 6} ${30 - k * 2} Q ${x + 3} 0 ${x - 6} ${-(30 - k * 2)} Z`}
          fill="var(--color-ink)"
          fillOpacity={struck ? 0.35 : 0.92}
        />
      ))}
      {[-30, 0, 28].map((x) => (
        <circle key={`m${x}`} cx={x - 4} cy={0} r={3} fill={HULL_FILL} />
      ))}
      {/* her colours at the stern: struck, they come down */}
      {!struck && <path d="M -60 0 L -80 -6 L -76 0 L -80 6 Z" fill={SIDE_TONE[side]} />}
    </>
  )
}

export function BattleStage({
  tl,
  events,
  state,
  tick,
  clock,
  reduced,
  endWords,
}: {
  tl: TickTimeline
  events: BattleEvent[]
  state: BattleState
  tick: number
  /** the playback clock, in fractional ticks */
  clock: () => number
  reduced: boolean
  /** the end's words, drawn over the stage once it is over */
  endWords: ReactNode
}) {
  const t = useT()
  const box = useRef<HTMLDivElement>(null)
  const [size, setSize] = useState<SceneSize>({ w: 1000, h: 520 })
  const svg = useRef<SVGSVGElement>(null)
  const live = useRef({ state, size })
  const gradId = useId().replace(/:/g, '')
  const ms = tl.ms

  useLayoutEffect(() => {
    live.current = { state, size }
  })

  useLayoutEffect(() => {
    const el = box.current
    if (!el) return
    const measure = () => {
      const r = el.getBoundingClientRect()
      if (r.width > 0 && r.height > 0) {
        const next = sceneSize(r.width, r.height)
        setSize((s) => (s.w === next.w && s.h === next.h ? s : next))
      }
    }
    measure()
    const ro = new ResizeObserver(measure)
    ro.observe(el)
    return () => ro.disconnect()
  }, [])

  // THE FRAME LOOP: only the ships' two transforms, and only with motion allowed
  useEffect(() => {
    if (reduced) return
    let raf = 0
    const frame = () => {
      const tf = clock()
      const sec = (tf * ms) / 1000
      const { state: st, size: sz } = live.current
      const groups = svg.current?.querySelectorAll<SVGGElement>('g[data-ship]') ?? []
      for (const outer of groups) {
        const [s, i] = (outer.dataset.ship ?? '').split(':').map(Number)
        if (!st.ships[s]?.[i]) continue
        const p = shipPose(s, i, st.ships[s].length, sec, tf, ms, st, sz)
        outer.setAttribute('transform', `translate(${p.x.toFixed(1)} ${p.y.toFixed(1)})`)
        outer.setAttribute('opacity', p.alpha.toFixed(2))
        outer.querySelector('g[data-rot]')?.setAttribute('transform', `rotate(${p.heading.toFixed(1)})`)
      }
      raf = requestAnimationFrame(frame)
    }
    raf = requestAnimationFrame(frame)
    return () => cancelAnimationFrame(raf)
  }, [reduced, clock, ms])

  // a pose at a whole tick, for React's own draw and for the effects (held still under reduced motion)
  const poseAt = (s: number, i: number, tk: number) =>
    shipPose(s, i, state.ships[s].length, reduced ? 0 : (tk * ms) / 1000, tk, ms, state, size)

  const fx: ReactNode[] = []
  for (const ev of events) {
    if (ev.t > tick) break
    if (ev.t < tick - 1) continue
    if (ev.kind === 'shot') {
      const from = poseAt(ev.s, ev.i, ev.t)
      const to = poseAt(1 - ev.s, ev.j, ev.t)
      const jx = ((ev.id % 5) - 2) * 14
      fx.push(
        <g key={`f${ev.id}`}>
          <line className="bv-bt-fx bv-bt-trace" x1={from.x} y1={from.y} x2={to.x + jx} y2={to.y} stroke="var(--color-harbour-light)" strokeWidth={2} />
          <circle className="bv-bt-fx bv-bt-smoke" cx={from.x} cy={from.y} r={17} fill="var(--color-ink)" />
          <circle className="bv-bt-fx bv-bt-flash" cx={from.x} cy={from.y} r={10} fill="var(--color-harbour-light)" />
          {ev.dmg > 0 ? (
            <text
              className={`bv-bt-fx bv-bt-num${ev.crit ? ' bv-bt-crit' : ''}`}
              data-testid="battle-hit"
              data-crit={ev.crit ? '1' : '0'}
              x={to.x + jx}
              y={to.y - NUM_UP}
              textAnchor="middle"
              fontSize={ev.crit ? 40 : 28}
              fontWeight={ev.crit ? 800 : 700}
              fill={ev.crit ? 'var(--color-accent)' : 'var(--color-ink)'}
              stroke="var(--color-bg)"
              strokeWidth={4}
              paintOrder="stroke"
            >
              {`-${Math.round(ev.dmg)}${ev.crit ? '!' : ''}`}
            </text>
          ) : (
            <g transform={`translate(${to.x + jx * 2} ${to.y + 26}) scale(0.75)`}>
              <g className="bv-bt-fx bv-bt-splash" data-testid="battle-splash">
                <path d="M -12 0 L -6 -22 L 0 -6 L 6 -26 L 12 0 Z" fill="var(--color-ship-light)" fillOpacity={0.8} />
                <ellipse cx={0} cy={2} rx={22} ry={6} fill="none" stroke="var(--color-ship-light)" strokeWidth={2} />
              </g>
            </g>
          )}
        </g>,
      )
    } else if (ev.kind === 'patch') {
      const at = poseAt(ev.s, ev.i, ev.t)
      fx.push(
        <text key={`p${ev.id}`} className="bv-bt-fx bv-bt-num" x={at.x} y={at.y - NUM_UP} textAnchor="middle" fontSize={28} fontWeight={700} fill="var(--color-success)" stroke="var(--color-bg)" strokeWidth={4} paintOrder="stroke">
          {`+${Math.round(ev.amount)}`}
        </text>,
      )
    } else if (ev.kind === 'use') {
      const i = Math.max(0, state.ships[ev.s].findIndex((x) => x.up && !x.struck))
      const at = poseAt(ev.s, i, ev.t)
      fx.push(
        <text key={`u${ev.id}`} className="bv-bt-fx bv-bt-call" data-testid="battle-call" x={at.x} y={at.y + 56} textAnchor="middle" fontSize={24} fontWeight={700} fill="var(--color-accent)" stroke="var(--color-bg)" strokeWidth={4} paintOrder="stroke">
          {t(`battle.ab_${ev.code}` as never)}
        </text>,
      )
    }
  }

  return (
    <div ref={box} className="relative h-full w-full overflow-hidden" data-testid="battle-stage">
      <svg ref={svg} viewBox={`0 0 ${size.w} ${size.h}`} preserveAspectRatio="xMidYMid meet" className="absolute inset-0 h-full w-full" role="img" aria-label={t('battle.title')}>
        <defs>
          <radialGradient id={`sea${gradId}`} cx="50%" cy="55%" r="75%">
            <stop offset="0%" stopColor="var(--color-sea-1)" />
            <stop offset="100%" stopColor="var(--color-chart-deep)" />
          </radialGradient>
        </defs>
        <rect x={0} y={0} width={size.w} height={size.h} fill={`url(#sea${gradId})`} />
        {state.ships.map((side, s) =>
          side.map((sh, i) => {
            const p = poseAt(s, i, tick)
            const share = sh.ship.m > 0 ? Math.max(0, Math.min(1, sh.hull / sh.ship.m)) : 0
            const braced = state.sides[s].bracedUntil > tick && !sh.struck
            const key = `${s}:${i}`
            return (
              <g
                key={key}
                data-testid="battle-ship"
                data-side={s}
                data-struck={sh.struck ? '1' : '0'}
                data-ship={key}
                transform={`translate(${p.x.toFixed(1)} ${p.y.toFixed(1)})`}
                opacity={p.alpha.toFixed(2)}
              >
                <g data-rot="" transform={`rotate(${p.heading.toFixed(1)})`}>
                  <g transform={`scale(${tierScale(sh.ship.t).toFixed(2)})`}>
                    <g className={sh.struck ? 'bv-bt-sink' : undefined}>
                      <ShipShape side={s} struck={sh.struck} />
                    </g>
                  </g>
                </g>
                {braced && <circle data-testid="battle-brace" r={50} fill="none" stroke="var(--color-info)" strokeWidth={2.5} strokeDasharray="8 6" opacity={0.8} />}
                {/* her hull bar, level whatever her heading */}
                <g transform="translate(-33 -52)">
                  <rect width={66} height={8} rx={4} fill="var(--color-chart-deep)" opacity={0.85} />
                  <rect data-testid="battle-hp" data-hull={Math.round(sh.hull)} width={66 * share} height={8} rx={4} fill={hullTone(share)} />
                </g>
                {/* her name only where a side has more than one ship: a lone ship's is the side's own, above the stage */}
                {side.length > 1 && (
                  <text y={-60} textAnchor="middle" fontSize={18} fontWeight={600} fill="var(--color-ink)" stroke="var(--color-bg)" strokeWidth={4} paintOrder="stroke">
                    {sh.ship.n}
                  </text>
                )}
                {sh.struck && (
                  <text y={7} textAnchor="middle" fontSize={19} fontWeight={700} fill="var(--color-danger)" stroke="var(--color-bg)" strokeWidth={4} paintOrder="stroke">
                    {t('battle.sunk')}
                  </text>
                )}
              </g>
            )
          }),
        )}
        {fx}
      </svg>
      {state.ended && (
        <div className="pointer-events-none absolute inset-0 flex items-center justify-center" data-testid="battle-end">
          <div className="rounded-tile bg-surface/90 px-6 py-4 text-center shadow-lg">{endWords}</div>
        </div>
      )}
    </div>
  )
}
