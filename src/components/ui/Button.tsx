import type { ButtonHTMLAttributes } from 'react'
import { buttonClasses, type ButtonSize, type ButtonVariant } from './buttonStyles'

// THE BUTTON — flat, four variants, two heights.
//
// docs/UI_DIRECTION.md §5: "primary (accent fill, `ink` on it), secondary (surface-2), quiet
// (text), destructive; 44 and 36; icon". That is the whole vocabulary. `.bv-brass` — the lit metal
// plate with a rim that `primary` used to wear — is already a flat accent fill after step 1, and
// step 10 deletes the name.
//
// ── THERE IS ONE BUTTON, AND THIS IS IT ────────────────────────────────────────────────────────
// A second Button component beside this one would be the twelve hand-written chip recipes all over
// again (buttonStyles.ts:31-35 counts them), so this file is REWRITTEN rather than added beside.
// What that costs, stated rather than hidden: `primary` loses its 1px rim and `secondary` loses
// its border — 2px of box each, because §4.3 says separation is a tone step and not a border —
// and the `md` label goes from 14px to `t-body`'s 16px, which is the size §4.1 gives button text.
// No screen file changes; four `size="sm"` buttons grow from 26px to 36px, which is the reach
// floor being approached rather than a redesign.
//
// ── THE SIX LEGACY VARIANT NAMES STILL RESOLVE, THROUGH THEIR OWN AUTHORITY ────────────────────
// `ghost`, `warning`, `success`, `chip`, `chip-on` and `chip-soft` are said by screens this PR
// does not touch, and three of them are ALSO said by ten direct `buttonClasses(…)` call sites that
// no component wraps (ArgPickers ×5, CommandScreen, LedgerScreen, tradePickers). If this file drew
// its own chip, the Market's sort chips (a `<Button variant="chip-on">`) and the Command pickers'
// chips (a raw `buttonClasses('chip-on')`) would be two different chips on two screens — which is
// exactly the drift the chip primitive was named to end. So a legacy variant DELEGATES to
// `buttonClasses`, unchanged and pixel-identical, and there is still only one author per look.
// Steps 3-9 move each caller onto a new name; step 10 deletes `buttonStyles.ts` and this branch.

export type ButtonTone = 'primary' | 'secondary' | 'quiet' | 'destructive'

const TONE: Record<ButtonTone, string> = {
  // The ONE interactive colour, filled. `text-bg` on it, which §4.4 measured at 9.92 : 1.
  primary: 'bg-accent text-bg hover:bg-accent-hover',
  // A tone step, not a border.
  secondary: 'bg-surface-2 text-ink',
  // Text only. It is a button because it does something, not because it looks like one.
  quiet: 'text-ink-muted hover:text-ink',
  destructive: 'bg-danger text-bg hover:bg-danger-hover',
}

const SIZE: Record<'sm' | 'md' | 'icon', string> = {
  // 36 — an in-row secondary action. Below the 44 floor on purpose and only ever beside something
  // that is on it; §4.2's rhythm, not a third size.
  sm: 'min-h-9 px-3 text-t-caption',
  md: 'min-h-11 px-4 text-t-body',
  icon: 'h-11 w-11 p-0',
}

const LEGACY = new Set<string>(['ghost', 'warning', 'success', 'chip', 'chip-on', 'chip-soft'])

export function Button({
  variant = 'secondary',
  size = 'md',
  busy = false,
  busyLabel,
  className = '',
  children,
  disabled,
  ...rest
}: ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: ButtonTone | ButtonVariant
  size?: ButtonSize
  /** Loading state: disables the button and swaps the label (the caller keeps its own phase state). */
  busy?: boolean
  busyLabel?: string
}) {
  const legacy = LEGACY.has(variant)
  const tone: ButtonTone = variant === 'danger' ? 'destructive' : (variant as ButtonTone)
  const skin = legacy
    ? buttonClasses(variant as ButtonVariant, size, className)
    : [
        'inline-flex items-center justify-center gap-2 rounded-control transition',
        'disabled:cursor-not-allowed disabled:opacity-45',
        TONE[tone],
        SIZE[size],
        className,
      ]
        .filter(Boolean)
        .join(' ')

  return (
    <button type="button" disabled={disabled || busy} className={skin} {...rest}>
      {busy ? (busyLabel ?? children) : children}
    </button>
  )
}
