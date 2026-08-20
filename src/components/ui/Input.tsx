import type { InputHTMLAttributes } from 'react'

// THE TEXT FIELD — the design system's missing primitive.
//
// An audit on 2026-08-20 found FOUR hand-written input recipes: the sign-in form, the register,
// the Market's port search and the Command pickers' filters. They differed in border colour, in
// focus ring, in padding and in whether they cleared the 44px touch floor — four answers to one
// question, drifting apart every time one of them was touched.
//
// `size` is not a scale, it is a JOB: `md` is a field you fill in deliberately (a password, a
// house name) and `sm` is a filter you type into while scanning a list. Both clear 44px, because
// the reach law does not care how small a control looks.
//
// It spreads the native attributes, so `type`, `required`, `minLength`, `autoComplete`,
// `inputMode` and the aria-* set all pass through untouched — a wrapper that swallowed those would
// be worse than the four copies it replaces.

export function Input({
  size = 'md',
  className = '',
  ...rest
}: Omit<InputHTMLAttributes<HTMLInputElement>, 'size'> & { size?: 'sm' | 'md' }) {
  return (
    <input
      className={[
        'min-h-11 w-full rounded-md border border-edge bg-surface-2 text-ink',
        'placeholder:text-ink-faint outline-none transition',
        'focus:border-accent focus:ring-1 focus:ring-accent/40',
        size === 'md' ? 'px-3 py-3 text-sm' : 'px-2.5 py-2 text-sm',
        className,
      ].join(' ')}
      {...rest}
    />
  )
}
