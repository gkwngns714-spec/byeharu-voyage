// Design-system Button classes — PURE (no React), in their own module so that:
//   · react-refresh keeps Button.tsx component-only (a file that exports both a component and a
//     helper breaks Fast Refresh — the same reason screenLayout.ts sits beside Screen.tsx), and
//   · a router <Link> or an <a> can wear the exact button skin without a wrapper component.
// Tokens only (see src/index.css @theme). Every size clears the 44px touch floor except `sm`,
// which is for in-row secondary actions.

export type ButtonVariant = 'primary' | 'secondary' | 'ghost' | 'danger' | 'warning' | 'success'
export type ButtonSize = 'sm' | 'md' | 'icon'

const VARIANT: Record<ButtonVariant, string> = {
  // Filled variants put dark app-colored text on the bright token fill (~8:1 contrast).
  primary: 'bg-accent text-app font-medium hover:bg-accent-hover',
  secondary: 'border border-edge bg-surface-2 text-ink hover:border-ink-faint/60',
  ghost: 'text-ink-muted hover:bg-surface-2 hover:text-ink',
  danger: 'bg-danger text-app font-medium hover:bg-danger-hover',
  warning: 'bg-warning text-app font-medium hover:bg-warning-hover',
  success: 'bg-success text-app font-medium hover:bg-success-hover',
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
