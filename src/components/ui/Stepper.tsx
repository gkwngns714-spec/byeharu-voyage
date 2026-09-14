import { useEffect, useRef, useState, type ReactNode } from 'react'
import { Chip } from './Chip'
import { Icon } from './Icon'

// THE STEPPER — how much, and the gauge the owner asked for by name.
//
// docs/OWNER_REQUESTS.md row 63, quoted in §7: *"make a gauge … the gauge max will be the stock"*.
// That is kept exactly and it is the reason this control has TWO ceilings rather than one:
//
//   `max`  the slider's END — what is THERE. The stock on the quay, the berths in the inn, the
//          tuns in the hold. The gauge spans the world's number, so the player can see how much of
//          it they are taking.
//   `cap`  the SERVER'S ceiling — what may be taken. The hold's room, the purse, the crew limit.
//          Drawn as a TICK on the track and used as the clamp. It is a served figure
//          (`buy_capacity`, `free_hold`) and it is never recomputed here: this game has already
//          had SEVEN answers to "how much fits in this hull" and one of them was wrong from the
//          day it was written (tests/duplication.spec.ts:17-21).
//
// A single `max` would have to be `min(stock, capacity)`, which is a rule — and a rule in a
// control is a rule in the wrong place. With both, the control draws the world and enforces the
// server, and the caller passes two served numbers and no arithmetic.
//
// `min` IS THE FLOOR, and it exists because a caller already owned one the control ignored:
// COMMAND's HIRE cannot sign on nobody and REPAIR cannot mend a hull DOWN, and StepQuestion has
// carried both floors in its `Bound.min` since it was written — while this control let `−` walk
// to "Hire 0" and "Mend to 40 %" on a hull at 60 %, leaving the server's dry run to say no. It
// defaults to 0, which the trade tray means literally (nought tuns, and the button goes dead), and
// it clamps exactly like `cap` does: the caller passes a number, never a rule.
//
// IT REPLACES `QtyPicker`, `NumberPicker`, `PricePicker` and the −/+ pairs written inline in
// `SendFleet` and the galley presets. The `−` and `+` are `Icon`s, not the text glyphs §4.5 bans.
//
// THE FIGURE IS THE SUBJECT. `t-figure`, tabular, with the unit beside it — the whole reason to
// touch this control is to read the number it is making, so nothing else on it is louder.
//
// ── THE FIGURE IS TYPED, THE THUMB IS BIG, AND ONE MEANS ONE (2026-09-14) ──────────────────────
// The owner: *"the marker when selling unit is shitty. and it only moves in like 10? wtf. i should
// be able to sell only 1. make it so that i can type the quantity, and also scroll but better than
// this."* Three things, in this control and not in any caller:
//   · THE FIGURE IS AN INPUT. Tap it, type, Enter or leave commits, clamped to the floor and the
//     ceiling; empty or nonsense reverts to the last good figure. `inputMode="numeric"` raises the
//     number pad on a phone. The slider does not move while a figure is being typed — the draft is
//     local until it commits — so the thumb cannot jitter under the finger.
//   · THE SLIDER IS ONE `<input type="range">` (keyboard and screen reader for free), dressed by
//     `.bv-range` (index.css): a thumb 28 px across, a visible track with the fill drawn under it,
//     `touch-action: pan-y` so a sideways drag moves it and an up-down drag still scrolls the tray.
//     A wheel over it steps by one (the listener is non-passive, bound here, so the page does not
//     scroll while the pointer is on the slider and only then). Arrows step by one, Home and End
//     go to the floor and the ceiling (native, then clamped), PageUp and PageDown step by the LOT —
//     the caller's round quantity (the trade's repricing step), when it passes one.
//   · THE STEP IS THE CALLER'S, and the trade trays pass 1: the server reprices every ten but takes
//     any count (TradeTray.tsx, UNIT_STEP).

export function Stepper({
  value,
  onChange,
  max,
  cap,
  min = 0,
  step = 1,
  lot,
  unit,
  presets,
  label,
  className = '',
  ...rest
}: {
  value: number
  onChange: (next: number) => void
  /** The slider's end: what is THERE (stock, berths, tuns). */
  max: number
  /** The server's ceiling: what may be TAKEN. Drawn as a tick, and the clamp. Defaults to `max`. */
  cap?: number
  /** The floor: the least that means anything (one hand to hire; a hull mended no lower than it
   *  stands). Defaults to 0. */
  min?: number
  /** What `−`, `+`, the arrows and the wheel move by. Defaults to 1. */
  step?: number
  /** A round quantity — PageUp / PageDown move by it. Defaults to `step`. */
  lot?: number
  unit?: ReactNode
  /** Chips over the slider — `max`, a keep-level, a common quantity. Optional. */
  presets?: readonly { label: ReactNode; value: number }[]
  /** Names the quantity for assistive tech ("tuns of aniseed"). Not drawn. */
  label: string
  className?: string
} & { 'data-testid'?: string }) {
  const ceiling = Math.min(cap ?? max, max)
  // A floor above the ceiling is a caller's arithmetic gone wrong, not a control's: the floor
  // yields, so the control can never demand more than may be taken.
  const floor = Math.max(0, Math.min(min, ceiling))
  const clamp = (n: number) => Math.max(floor, Math.min(ceiling, n))
  const tickPct = max > 0 ? (ceiling / max) * 100 : 100
  const leap = Math.max(step, lot ?? step)

  // THE TYPED DRAFT — digits only, local until it commits. Null means "show the value".
  const [draft, setDraft] = useState<string | null>(null)
  const commit = () => {
    if (draft === null) return
    const n = Number.parseInt(draft, 10)
    if (Number.isFinite(n)) onChange(clamp(n))
    setDraft(null)
  }

  // THE WHEEL. React binds `wheel` passively, where `preventDefault` is refused, so the listener
  // is bound here — non-passive, on the slider only. The latest value and clamp are read through
  // a ref so the listener is bound once and never goes stale.
  const rangeRef = useRef<HTMLInputElement>(null)
  const latest = useRef({ value, step, clamp, onChange })
  useEffect(() => {
    latest.current = { value, step, clamp, onChange }
  })
  useEffect(() => {
    const el = rangeRef.current
    if (!el) return
    const onWheel = (e: WheelEvent) => {
      if (e.deltaY === 0) return
      e.preventDefault()
      const { value, step, clamp, onChange } = latest.current
      onChange(clamp(value + (e.deltaY < 0 ? step : -step)))
    }
    el.addEventListener('wheel', onWheel, { passive: false })
    return () => el.removeEventListener('wheel', onWheel)
  }, [])

  return (
    <div className={`flex flex-col gap-2 ${className}`} {...rest}>
      <div className="flex items-center gap-3">
        <button
          type="button"
          aria-label="Less"
          onClick={() => onChange(clamp(value - step))}
          disabled={value <= floor}
          className="flex h-11 w-11 shrink-0 items-center justify-center rounded-control bg-surface-2 text-ink disabled:opacity-45"
        >
          <Icon name="minus" size={20} />
        </button>
        <div className="flex min-w-0 flex-1 items-baseline justify-center gap-1">
          <input
            type="text"
            inputMode="numeric"
            pattern="[0-9]*"
            aria-label={`${label}, typed`}
            value={draft ?? value.toLocaleString()}
            onFocus={(e) => {
              setDraft(String(value))
              e.currentTarget.select()
            }}
            onChange={(e) => setDraft(e.target.value.replace(/\D/g, ''))}
            onBlur={commit}
            onKeyDown={(e) => {
              if (e.key === 'Enter') {
                commit()
                e.currentTarget.blur()
              } else if (e.key === 'Escape') {
                setDraft(null)
                e.currentTarget.blur()
              }
            }}
            size={Math.max(2, (draft ?? value.toLocaleString()).length)}
            // h-11: the figure is a tap target now, and every target clears 44 px (§5,
            // tests/primitives.geometry.spec.ts).
            className="h-11 min-w-0 rounded-control bg-transparent px-1 text-center text-t-figure tabular-nums text-ink outline-none focus:bg-surface-2 focus-visible:ring-2 focus-visible:ring-accent"
            data-testid="stepper-figure"
          />
          {unit !== undefined && <span className="text-t-caption text-ink-faint">{unit}</span>}
        </div>
        <button
          type="button"
          aria-label="More"
          onClick={() => onChange(clamp(value + step))}
          disabled={value >= ceiling}
          className="flex h-11 w-11 shrink-0 items-center justify-center rounded-control bg-surface-2 text-ink disabled:opacity-45"
        >
          <Icon name="plus" size={20} />
        </button>
      </div>

      {/* THE GAUGE. The track spans `max` — the world — and the tick stands where the server stops
          you. A slider whose end IS the clamp hides the difference between "there is no more" and
          "you may not have more", and those are two different refusals. */}
      <div className="relative flex h-11 items-center">
        <span aria-hidden="true" className="absolute h-1.5 w-full rounded-chip border border-edge bg-surface-2" />
        <span
          aria-hidden="true"
          style={{ width: `${max > 0 ? (value / max) * 100 : 0}%` }}
          className="absolute h-1.5 rounded-chip bg-accent"
        />
        {tickPct < 100 && (
          <span
            aria-hidden="true"
            style={{ left: `${tickPct}%` }}
            className="pointer-events-none absolute h-3 w-0.5 rounded-chip bg-warning"
          />
        )}
        {/* The INPUT spans the whole track like the fill drawn under it does, so the thumb and
            the fill agree; the floor is the clamp on what it may hand back, as the cap is. */}
        <input
          ref={rangeRef}
          type="range"
          aria-label={label}
          min={0}
          max={max}
          step={step}
          value={value}
          onChange={(e) => onChange(clamp(Number(e.target.value)))}
          onKeyDown={(e) => {
            if (e.key === 'PageUp' || e.key === 'PageDown') {
              e.preventDefault()
              onChange(clamp(value + (e.key === 'PageUp' ? leap : -leap)))
            }
          }}
          className="bv-range relative"
        />
      </div>

      {presets !== undefined && presets.length > 0 && (
        <div className="flex flex-wrap gap-2">
          {presets.map((p, i) => (
            <Chip key={i} onClick={() => onChange(clamp(p.value))}>
              {p.label}
            </Chip>
          ))}
        </div>
      )}
    </div>
  )
}
