// The two faces of THE ONE CLOCK (app/shellState.ts) — the real time now, and the time until a
// served instant. Design-system property from the first use, because the second and third screens
// are already known: COMMAND prints the hour and counts down to the market's next move (0029),
// PORT counts down a fair's end, RANK prints a settled-age.
//
// BOTH ARE PURE DISPLAY. `nowMs` comes in as a prop from `useShellState()` — a screen passes it
// down; neither component mounts a timer of its own (two timers is two clocks disagreeing by a
// second, the exact thing shellState exists to prevent) and neither may import shellState itself
// (components/ ranks below app/ in the import order tests/sections.spec.ts enforces).
//
// NEITHER DECIDES ANYTHING. When a countdown reaches zero the truth is the SERVER's: the caller
// re-asks through useReaskAtEdge (./reaskAtEdge.ts) rather than assuming what the world did —
// see MarketClock in src/lib/rpc/types.ts for why assuming is a second authority.

import { formatClock, formatCountdown } from '../../lib/format'

/** The actual time, alive: "14:22:07". One authority for spelling it — `formatClock`. */
export function WallClock({ nowMs, className }: { nowMs: number; className?: string }) {
  return (
    <span className={className} data-testid="wall-clock">
      {formatClock(nowMs, true)}
    </span>
  )
}

/**
 * Time until a SERVED instant, live: "4:12" … "0:07" … then `dueText`.
 *
 * The remaining time is SUBTRACTION — `untilMs - nowMs` — against an instant the server served
 * (a `next_change_at`, an `ends_at`, an `eta`). It is never multiplied out of a cadence knob;
 * the served instant is the one authority for when the thing happens.
 *
 * At zero it prints `dueText` and STAYS there until the caller's re-ask replaces the payload —
 * it never goes negative and never guesses what changed.
 */
export function Countdown({
  untilMs,
  nowMs,
  dueText = 'due',
  className,
}: {
  /** The served instant, in ms (Date.parse of a served timestamptz). */
  untilMs: number
  /** THE ONE CLOCK, from useShellState() — passed down, never mounted here. */
  nowMs: number
  /** What to print once the instant has passed, while the re-ask is in flight. */
  dueText?: string
  className?: string
}) {
  const remaining = untilMs - nowMs
  return (
    <span className={className} data-testid="countdown" data-due={remaining <= 0 || undefined}>
      {remaining <= 0 ? dueText : formatCountdown(remaining)}
    </span>
  )
}
