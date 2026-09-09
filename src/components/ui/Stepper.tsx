import type { ReactNode } from 'react'
import { Chip } from './Chip'
import { Figure } from './Figure'
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

export function Stepper({
  value,
  onChange,
  max,
  cap,
  min = 0,
  step = 1,
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
  step?: number
  unit?: ReactNode
  /** Chips over the slider — `max`, a keep-level, a common quantity. Optional. */
  presets?: readonly { label: ReactNode; value: number }[]
  /** Names the quantity for assistive tech ("tuns of aniseed"). */
  label: string
  className?: string
} & { 'data-testid'?: string }) {
  const ceiling = Math.min(cap ?? max, max)
  // A floor above the ceiling is a caller's arithmetic gone wrong, not a control's: the floor
  // yields, so the control can never demand more than may be taken.
  const floor = Math.max(0, Math.min(min, ceiling))
  const clamp = (n: number) => Math.max(floor, Math.min(ceiling, n))
  const tickPct = max > 0 ? (ceiling / max) * 100 : 100

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
        <div className="min-w-0 flex-1 text-center">
          <Figure value={value.toLocaleString()} unit={unit} size="figure" />
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
        <span aria-hidden="true" className="absolute h-1 w-full rounded-chip bg-surface-2" />
        <span
          aria-hidden="true"
          style={{ width: `${max > 0 ? (value / max) * 100 : 0}%` }}
          className="absolute h-1 rounded-chip bg-accent"
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
          type="range"
          aria-label={label}
          min={0}
          max={max}
          step={step}
          value={value}
          onChange={(e) => onChange(clamp(Number(e.target.value)))}
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
