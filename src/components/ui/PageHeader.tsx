import type { ReactNode } from 'react'
import { ExplainDot, ExplainPanel } from './Explain'
import { useExplainDisclosure } from './explainState'

// Design-system page header: optional mono micro-label (eyebrow — the screen designator) over
// title + optional subtitle on the left, actions on the right. One per screen, first child of
// <Screen> — the Screen stack's space-y-4 owns the rhythm, so PageHeader carries NO bottom margin.
//
// ── TWO SLOTS UNDER THE TITLE, BECAUSE THERE WERE ALWAYS TWO THINGS THERE ───────────────────────
// `subtitle` used to carry both of these, and only one of them belongs on the screen by default:
//
//   Port   · Lisbon                          Fleets
//   Portugal · latin · North Atlantic Ocean  What you own, and the state it is in.
//   ^ LIVE: the harbour you are reading      ^ STANDING: true on every visit, forever
//
// The live line is the screen answering the question you opened it with. The standing line tells a
// first-time player something real and a returning one nothing at all, and it costs the top of a
// phone either way. So:
//
//   subtitle — PRINTED. The live subject, or a status ("Opening the world…", "The world did not
//              open."). Anything a player needs without asking.
//   explain  — FOLDED behind the ⓘ beside the title (Explain.tsx). The standing orientation line.
//
// Passing prose to `subtitle` is not an error, it is a decision — make it deliberately.

export function PageHeader({
  eyebrow,
  title,
  subtitle,
  explain,
  actions,
  className = '',
}: {
  eyebrow?: ReactNode
  title: ReactNode
  /** Printed under the title. Live subject or status — never a standing rule. */
  subtitle?: ReactNode
  /** The screen's standing orientation line. Behind the ⓘ; never a live figure. */
  explain?: ReactNode
  actions?: ReactNode
  className?: string
}) {
  const disclosure = useExplainDisclosure()
  return (
    <header className={`flex flex-wrap items-center justify-between gap-3 ${className}`}>
      <div className="min-w-0">
        {eyebrow && (
          <p className="mb-0.5 font-mono text-xs uppercase tracking-wider text-ink-faint">{eyebrow}</p>
        )}
        {/* The dot is INSIDE the heading, not beside it, so it rides the title's baseline at every
            wrap. A <button> in an <h1> is valid markup; an <h1> inside a button is not, which is
            why this header is not a Collapsible. */}
        <h1 className="font-serif text-2xl font-semibold tracking-tight text-ink">
          {title}
          {explain && (
            <ExplainDot
              {...disclosure}
              label={typeof title === 'string' ? title : undefined}
              className="ml-1.5"
            />
          )}
        </h1>
        {subtitle && <p className="mt-0.5 text-sm text-ink-muted">{subtitle}</p>}
        {explain && <ExplainPanel {...disclosure}>{explain}</ExplainPanel>}
      </div>
      {actions && <div className="flex items-center gap-2">{actions}</div>}
    </header>
  )
}
