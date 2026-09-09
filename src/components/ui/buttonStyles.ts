// Design-system Button classes — PURE (no React), in their own module so that:
//   · react-refresh keeps Button.tsx component-only (a file that exports both a component and a
//     helper breaks Fast Refresh — the same reason screenLayout.ts sits beside Screen.tsx), and
//   · a router <Link> or an <a> can wear the exact button skin without a wrapper component.
// Tokens only (see src/index.css @theme). Every size clears the 44px touch floor except `sm`,
// which is for in-row secondary actions.

export type ButtonVariant =
  | 'primary'
  | 'secondary'
  | 'ghost'
  | 'danger'
  | 'warning'
  | 'success'
  | 'chip'
  | 'chip-on'
  | 'chip-soft'
export type ButtonSize = 'sm' | 'md' | 'icon'

const VARIANT: Record<ButtonVariant, string> = {
  // PRIMARY WAS BRASS — a lit metal plate with a rim, because the 2026-08-20 material said a flat
  // swatch beside a chamfered panel reads as a web form. The 2026-09-09 audit said the material is
  // what reads as old, so `.bv-brass` (src/index.css) is now a flat accent fill and survives only
  // as the name this one call site still says. Step 2 replaces this variant with the `Button`
  // primitive and the name goes with it.
  primary: 'bv-brass text-app font-medium',
  secondary: 'border border-edge bg-surface-2 text-ink hover:border-ink-faint/60',
  ghost: 'text-ink-muted hover:bg-surface-2 hover:text-ink',
  danger: 'bg-danger text-app font-medium hover:bg-danger-hover',
  warning: 'bg-warning text-app font-medium hover:bg-warning-hover',
  success: 'bg-success text-app font-medium hover:bg-success-hover',

  // THE CHIP — a selectable token in a set (a verb, a fleet, a filter, a port). It was the design
  // system's missing primitive: an audit on 2026-08-20 found TWELVE hand-written copies of these
  // two recipes across Command, Market and Fleets, drifting in border colour and hover between
  // copies. Two variants rather than one boolean prop, because buttonClasses is a pure string
  // function and every caller already knows which state it is drawing.
  chip: 'border border-edge bg-surface-2 text-ink hover:border-accent/60',
  'chip-on': 'border border-accent bg-accent text-app font-medium',

  // THE SELECTED ROW, as opposed to the selected CHIP. `chip-on` fills solid brass and puts dark
  // text on it, which is right for a word in a set and wrong for a full-width row that CARRIES
  // things — a picker row holds a badge, a %NBR pill and a stock meter, and a solid fill swallows
  // all three. This is the soft tint TabRow already uses for a selected face (TabRow.tsx:60),
  // named once so a row and a tab cannot drift apart.
  //
  // It pairs with `chip` for its OFF arm, so one control is drawn by one recipe in both states —
  // which is what the command section could not do while this variant did not exist.
  'chip-soft': 'border border-accent bg-accent-soft text-ink',
}

const SIZE: Record<ButtonSize, string> = {
  sm: 'px-3 py-1 text-xs',
  md: 'min-h-11 px-4 py-2 text-sm',
  icon: 'h-11 w-11 p-0 text-base',
}

export function buttonClasses(variant: ButtonVariant = 'secondary', size: ButtonSize = 'md', extra = ''): string {
  return [
    'inline-flex items-center justify-center gap-2 rounded-md transition',
    'disabled:cursor-not-allowed disabled:opacity-45',
    VARIANT[variant],
    SIZE[size],
    extra,
  ]
    .filter(Boolean)
    .join(' ')
}
