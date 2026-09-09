import { useEffect, type ReactNode } from 'react'

// THE NOTE — one line, a tone, and at most one action.
//
// It replaces `Notice`, `RefusalNote`, `Badge`, the `WorldFailed` body, `RebuildNotice`'s three
// paragraphs and two buttons, and every `refusal.code — sentence` printed on a quay. §2 counted
// twenty-one status badges and a rebuild warning that ran to three paragraphs; §6 says what each
// becomes: "`RebuildNotice` becomes one `Note`: *The world was rebuilt from the first migration.*
// [OK]".
//
// ── THE CODE NEVER PRINTS ──────────────────────────────────────────────────────────────────────
// §5, on the refusal form: "the code never prints (it goes to `console.debug`)". `E_HOLD_FULL`,
// `E_UNKNOWN`, `E_REFUSED`, `row(s) across N table(s)`, `byeharu-voyage.rescue.v1`, `(DESIGN K.1)`
// — §2 item 13 lists thirteen kinds of developer vocabulary leaking onto player screens. A code is
// for a log, not a quay. So this component takes a `code` and DELIBERATELY does not render it: it
// writes it to `console.debug` once, where a developer reading a session still finds it and a
// player never does.
//
// ── ONE LINE, ONE TONE, ONE ACTION ─────────────────────────────────────────────────────────────
// The tone is the left keyline and the text colour, and nothing else: no filled panel, no icon
// badge, no border box. A `Note` that needs a paragraph is a `Tray` with a `Hint` in it, and a
// `Note` that needs two buttons is a decision, which belongs in a tray with its own primary.
//
// THE REFUSAL FORM is the same component with a `Bar` passed as `figure`: have against need, the
// two served numbers, and one fix button. That is the owner's concise-and-graphic law kept with
// the primitives instead of with a second component.

export type NoteTone = 'neutral' | 'accent' | 'success' | 'warning' | 'danger' | 'info'

const TONE: Record<NoteTone, string> = {
  neutral: 'border-edge text-ink-muted',
  accent: 'border-accent text-accent',
  success: 'border-success text-success',
  warning: 'border-warning text-warning',
  danger: 'border-danger text-danger',
  info: 'border-info text-info',
}

export function Note({
  tone = 'neutral',
  action,
  figure,
  code,
  children,
  className = '',
  ...rest
}: {
  tone?: NoteTone
  /** At most one — a `Button` in `quiet` or `secondary`. A second is a decision, not a note. */
  action?: ReactNode
  /** A `Bar` or a `Figure` the note is about: the refusal's have-against-need. */
  figure?: ReactNode
  /** The server's code. Written to console.debug, never to the screen. */
  code?: string
  children: ReactNode
  className?: string
} & { 'data-testid'?: string }) {
  // In an effect, not in the render body: a component that writes to the console while React is
  // rendering it writes twice under StrictMode and once more on every re-render, and a log that
  // fires a different number of times depending on how the tree was drawn is not a log.
  useEffect(() => {
    if (code) console.debug('[note]', code)
  }, [code])

  return (
    <div
      className={`flex min-h-row items-center gap-3 border-l-2 pl-3 ${TONE[tone]} ${className}`}
      {...rest}
    >
      <div className="min-w-0 flex-1">
        <p className="text-t-label">{children}</p>
        {figure !== undefined && <div className="mt-1">{figure}</div>}
      </div>
      {action !== undefined && <div className="shrink-0">{action}</div>}
    </div>
  )
}
