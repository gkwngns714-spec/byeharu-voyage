// THE DOT — one state, as one 8-px disc of a tone, beside a name.
//
// The fleet picker (features/command/FleetPicker.tsx, 2026-10-20) shows a fleet's one-word signal
// as a dot: green sailing, grey waiting, red stuck. The same disc stands on the picker's button and
// on every row of its list, so it is a primitive rather than a class string written twice. It is a
// MARK, like `RarityMark`: pure props, no store, no rule — the caller decides the tone from a
// domain reading (`fleetSignal`), this draws it.
//
// THE TONE IS THE MEANING (§4.4): `success` and `danger` here mean "under way" and "needs you",
// the two the owner named; `neutral` is "nothing to do". No `warning`: a third colour on a dot
// this small is a colour nobody can name.
//
// A dot that carries meaning on its own takes a `label`, so a screen reader hears the word a sighted
// player reads from the colour; without one it is decoration beside a word that already says it.

export type DotTone = 'success' | 'danger' | 'neutral'

const TONE: Record<DotTone, string> = {
  success: 'bg-success',
  danger: 'bg-danger',
  neutral: 'bg-ink-faint',
}

export function Dot({
  tone,
  label,
  className = '',
  ...rest
}: {
  tone: DotTone
  /** The word the colour stands for ("sailing", "stuck"). Set when the dot is the only place it is said. */
  label?: string
  className?: string
} & { 'data-testid'?: string }) {
  return (
    <span
      role={label ? 'img' : undefined}
      aria-label={label}
      aria-hidden={label ? undefined : true}
      title={label}
      data-tone={tone}
      className={`inline-block h-2 w-2 shrink-0 rounded-full ${TONE[tone]} ${className}`}
      {...rest}
    />
  )
}
