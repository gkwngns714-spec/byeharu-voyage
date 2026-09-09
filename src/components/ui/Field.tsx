import type { InputHTMLAttributes, ReactNode } from 'react'
import { Icon } from './Icon'

// THE FIELD — one text input, with the leading mark and the clear the four copies never agreed on.
//
// `Input.tsx` already folded FOUR hand-written recipes in August (its header carries the count and
// the ways they had drifted). This is that primitive redrawn on the step-1 tokens and given the
// two things every caller was bolting on afterwards: a leading `Icon` (the Market's port search,
// the compendium's filter, both good pickers all draw one) and a clear button (`FilterBox` has
// one; the others do not, and a filter you cannot clear is a filter you must retype).
//
// NO BORDER. §4.3: separation is a tone step, and a field is `surface-2` inset on `surface`. The
// focus ring is the one exception — a control that has the keyboard must say so, and a ring is not
// a border because it is not there at rest.
//
// THE CLEAR BUTTON IS 44px AND SITS INSIDE THE FIELD, which is why the input carries `pr-11`: it
// is the one place in this file where a class encodes another control's size, and it is the reason
// the two are drawn together here rather than composed by nine callers.

export function Field({
  icon = 'search',
  onClear,
  className = '',
  ...rest
}: Omit<InputHTMLAttributes<HTMLInputElement>, 'size'> & {
  /** The leading mark. `null` for a field that is not a search — a house name, a password. */
  icon?: 'search' | null
  /** Given, and with a value present, draws the clear button. */
  onClear?: () => void
}) {
  const hasValue = typeof rest.value === 'string' ? rest.value.length > 0 : false
  return (
    <div className={`relative flex items-center ${className}`}>
      {icon !== null && (
        <Icon name={icon} size={20} className="pointer-events-none absolute left-3 text-ink-faint" />
      )}
      <input
        className={[
          'min-h-11 w-full rounded-control bg-surface-2 py-2 text-t-body text-ink',
          'placeholder:text-ink-faint outline-none transition',
          'focus:ring-1 focus:ring-accent',
          icon !== null ? 'pl-10' : 'pl-3',
          onClear ? 'pr-11' : 'pr-3',
        ].join(' ')}
        {...rest}
      />
      {onClear && hasValue && (
        <button
          type="button"
          aria-label="Clear"
          onClick={onClear}
          className="absolute right-0 flex h-11 w-11 items-center justify-center text-ink-faint"
        >
          <Icon name="close" size={18} />
        </button>
      )}
    </div>
  )
}

/** A read-only field that OPENS something instead of accepting text — the Market's port picker,
 *  which is a search field over 238 ports and must never again wrap them all onto the page as
 *  chips (§2 item 8: the page grew to 5,566px). Same box, same height, a chevron instead of a
 *  caret, and the list it opens is a `Tray`. */
export function FieldButton({
  icon = 'search',
  value,
  onClick,
  className = '',
  ...rest
}: {
  icon?: 'search' | null
  value: ReactNode
  onClick: () => void
  className?: string
} & { 'data-testid'?: string }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={[
        'flex min-h-11 w-full items-center gap-2 rounded-control bg-surface-2 px-3',
        'text-left text-t-body text-ink transition',
        className,
      ].join(' ')}
      {...rest}
    >
      {icon !== null && <Icon name={icon} size={20} className="shrink-0 text-ink-faint" />}
      <span className="min-w-0 flex-1 truncate">{value}</span>
      <Icon name="chevron" size={18} className="shrink-0 rotate-90 text-ink-faint" />
    </button>
  )
}
