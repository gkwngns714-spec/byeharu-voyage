import type { KeyboardEvent, MouseEvent, ReactNode } from 'react'
import type { WherePiece } from '../domain/fleet'
import { goTo, type GoToTarget } from './goTo'
import { useT } from '../lib/i18n'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE ONE LINK TO A PLACE (./goTo.ts) — every harbour, point of water, fleet and merchant named in
// a panel is drawn through this, so they all look, press and read alike.
//
// A SPAN WITH role="link", NOT A BUTTON: most names stand inside a row that is itself a button
// (press the row to open her), and a button inside a button is not HTML. The span takes focus,
// answers Enter and Space, and stops its press at itself, so the row's own press is left alone.
// Quiet by design (owner's map rules: minimal, no new words): the name keeps its colour and gains
// a faint dotted underline that firms on hover and focus.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const LINK =
  'cursor-pointer rounded-sm underline decoration-dotted decoration-1 underline-offset-2 decoration-ink-faint/70 ' +
  'transition-colors hover:text-accent hover:decoration-solid hover:decoration-current ' +
  'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent focus-visible:decoration-solid'

export function GoToLink({
  to,
  children,
  label,
}: {
  to: GoToTarget
  children: ReactNode
  /** The accessible name, when the visible words are not enough on their own. */
  label?: string
}) {
  const t = useT()
  const go = (event: MouseEvent | KeyboardEvent) => {
    event.preventDefault()
    event.stopPropagation()
    goTo(to)
  }
  return (
    <span
      role="link"
      tabIndex={0}
      aria-label={label}
      title={t('chart.showOnChart')}
      className={LINK}
      data-testid="goto-link"
      data-goto={to.kind === 'port' ? `port:${to.code}` : to.kind === 'fleet' ? `fleet:${to.id}` : 'point'}
      onClick={go}
      // The row underneath must not see the press start either (a Row's own pointer styles).
      onPointerDown={(event) => event.stopPropagation()}
      onKeyDown={(event) => {
        if (event.key === 'Enter' || event.key === ' ') go(event)
      }}
    >
      {children}
    </span>
  )
}

/** A "where" line (`domain/fleet` `WherePiece`s) with every place in it a link. */
export function PlaceLine({ parts }: { parts: readonly WherePiece[] }) {
  return (
    <>
      {parts.map((p, i) =>
        typeof p === 'string' ? (
          p
        ) : (
          <GoToLink key={i} to={'port' in p ? { kind: 'port', code: p.port } : { kind: 'point', at: p.at }}>
            {p.text}
          </GoToLink>
        ),
      )}
    </>
  )
}
