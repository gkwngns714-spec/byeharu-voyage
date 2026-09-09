import { useState, type ReactNode } from 'react'
import { Tray } from './Tray'
import type { TrayDetent } from './trayDetents'

// THE HINT — the caption voice, on a budget, and the end of eighty-one ⓘ dots.
//
// ── WHAT WAS COUNTED ───────────────────────────────────────────────────────────────────────────
// §2 item 5: **81** `ⓘ` explain-dots across nine screens — on every page title, and on `provision`,
// `cargo`, `Order`, `Ships`, `Cargo`, `the hold`, `how fresh this is`, `Purse`, `Fleets`,
// `Founded`, `Ports`… — plus **57** `title=` tooltip attributes on a touch-first app, where a
// tooltip cannot be shown at all. "Prose is a tooltip" had become "a tooltip on every noun", and a
// dot beside a label that is already plain (`Purse`) is a tax on the eye with no answer behind it.
//
// ── THE BUDGET IS THE PRIMITIVE ────────────────────────────────────────────────────────────────
// §5: "a `t-caption` line under a label, present only where the caller passes one; long text opens
// a `Tray`. Budget: one per section, none on titles."
//
// So a hint is PRINTED, not hidden. That is the change: the old `Explain`/`ExplainDot`/
// `ExplainPanel`/`explainState` quartet made every explanation a control you had to discover and
// press, which is why there were 81 of them — a hidden thing costs no pixels, so nobody counted.
// A printed caption costs 16px and gets counted immediately, which is exactly the pressure this
// design wants. If it does not earn 16px, it is not a hint; it is the code narrating itself
// (§2 item 6 lists 93 lines of that).
//
// ── LONG TEXT OPENS A TRAY ─────────────────────────────────────────────────────────────────────
// Pass `more` and the caption grows one quiet control that opens a `Tray` at `half`. That is the
// one sanctioned home for a paragraph in this game: a surface with a title, a scroll and a close,
// rather than a disclosure that pushes the screen around when it opens.

export function Hint({
  children,
  more,
  moreTitle,
  className = '',
  ...rest
}: {
  /** The caption. One line, in the player's words. */
  children: ReactNode
  /** The paragraph, if there genuinely is one. Opens in a tray; never printed inline. */
  more?: ReactNode
  /** The tray's title — what the paragraph is about. Defaults to "About this". */
  moreTitle?: string
  className?: string
} & { 'data-testid'?: string }) {
  const [detent, setDetent] = useState<TrayDetent>('closed')
  return (
    <>
      <p className={`text-t-caption text-ink-faint ${className}`} {...rest}>
        {children}
        {more !== undefined && (
          <button
            type="button"
            onClick={() => setDetent('half')}
            className="ml-2 inline-flex min-h-11 min-w-11 items-center justify-center text-t-caption text-accent"
          >
            More
          </button>
        )}
      </p>
      {more !== undefined && (
        <Tray detent={detent} onDetentChange={setDetent} title={moreTitle ?? 'About this'}>
          <p className="text-t-label text-ink-muted">{more}</p>
        </Tray>
      )}
    </>
  )
}
