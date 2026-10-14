import type { ButtonHTMLAttributes } from 'react'

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
// ── THE LEGACY VARIANT NAMES ARE GONE ──────────────────────────────────────────────────────────
// `ghost`, `warning`, `success`, `chip`, `chip-on` and `chip-soft` once delegated to a second
// recipe module (`buttonStyles.ts`) so screens could move over one at a time. Every caller has
// moved — chips are `Chip`, selectable blocks are `Tile` — so that module and its branch are
// deleted, and this file is the only author of a button's look.

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

type ButtonSize = 'sm' | 'md' | 'icon'

const SIZE: Record<ButtonSize, string> = {
  // 36 — an in-row secondary action. Below the 44 floor on purpose and only ever beside something
  // that is on it; §4.2's rhythm, not a third size.
  sm: 'min-h-9 px-3 text-t-caption',
  md: 'min-h-11 px-4 text-t-body',
  icon: 'h-11 w-11 p-0',
}

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
  variant?: ButtonTone
  size?: ButtonSize
  /** Loading state: disables the button and swaps the label (the caller keeps its own phase state). */
  busy?: boolean
  busyLabel?: string
}) {
  const skin = [
    'inline-flex items-center justify-center gap-2 rounded-control transition',
    'disabled:cursor-not-allowed disabled:opacity-45',
    TONE[variant],
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
