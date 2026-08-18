import type { ButtonHTMLAttributes } from 'react'
import { buttonClasses, type ButtonSize, type ButtonVariant } from './buttonStyles'

// Design-system Button — the component. The classes live in ./buttonStyles.ts (pure), so this file
// exports a component and nothing else.

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
  variant?: ButtonVariant
  size?: ButtonSize
  /** Loading state: disables the button and swaps the label (the caller keeps its own phase state). */
  busy?: boolean
  busyLabel?: string
}) {
  return (
    <button type="button" disabled={disabled || busy} className={buttonClasses(variant, size, className)} {...rest}>
      {busy ? (busyLabel ?? children) : children}
    </button>
  )
}
