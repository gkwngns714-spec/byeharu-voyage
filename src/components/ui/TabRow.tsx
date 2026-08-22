import type { ReactNode } from 'react'

// THE FACES OF ONE PLACE — the design system's tab strip.
//
// The reference draws a port as ONE panel with faces (기본 / 교역 / 시설 / 투자), not as four
// sibling cards stacked down a page (docs/UI_DIRECTION.md §2). The difference matters at 390px:
// four stacked cards means the fourth is 1,200px down and is never seen, while four faces means
// every one of them is one tap from the others and the panel keeps its header.
//
// IT IS A REAL TABLIST. role="tablist"/"tab" with aria-selected, so a screen reader announces
// "2 of 4" rather than reading four unlabelled buttons. The panel each tab governs carries
// role="tabpanel" at the call site — this primitive owns the strip, never the content.
//
// ── IT WRAPS. IT USED TO SCROLL, AND THAT LOST TWO FEATURES (2026-08-22) ───────────────────────
// The comment that stood here said the strip scrolls sideways "because a wrapped second row of
// tabs changes the panel's height when the selection changes, which makes the content below jump."
// That reason is not true of this control: a wrapped row's height depends on how many tabs there
// are and how wide they are, and selecting one changes neither — the ON and OFF arms below differ
// only in colour, never in weight, padding or size. The strip is the same height on every face.
//
// What WAS true is what the scroll cost. Measured in the running game at 390px: `scrollWidth` 401
// against `clientWidth` 332, with the strip rendering `QUAY CITY SERVICES ALONGSIDE O` — OFFICERS
// began at x=340 and ran off the panel, and ACADEMY was further off still. Two features that had
// just shipped could not be found, and nothing on screen said there was anywhere to scroll to: no
// arrow, no fade, no cut-off glyph. A horizontal scroll with no affordance is a feature that does
// not exist (docs/UI_DIRECTION.md's rule, and the METHOD's: "if the player cannot find a feature,
// the feature does not exist").
//
// The rejected alternatives, and why: SHORTER LABELS lose the words the faces are named by and
// only postpone the overflow — the seventh face brings it straight back; an ARROW or a FADE is a
// hint that the thing you want is somewhere you cannot see, which is a worse answer than showing
// it; A SELECT is one tap to open plus one to choose, for a control whose whole job is that every
// side of the panel is ONE tap from every other.
//
// Wrapping keeps all of that: every face is on screen, whole and pressable, at full width. Nothing
// here has a max-height and nothing scrolls, so the reach law holds — an action never lives inside
// a region that can clip it.
//
// THE SELECTED FACE IS GOLD AND SITS ON A LIT EDGE, because in the reference the selected tab is
// the one that looks connected to the panel below it. The lit edge is the tab's own bottom border,
// so on a wrapped strip it underlines the selected tab in whichever row it fell — it is not a rule
// across the whole strip, and it must not become one.

export interface TabSpec<T extends string> {
  id: T
  label: ReactNode
  /** An optional count or badge riding after the label — rows, ships, actions available. */
  hint?: ReactNode
}

export function TabRow<T extends string>({
  tabs,
  value,
  onChange,
  label,
  className = '',
}: {
  tabs: readonly TabSpec<T>[]
  value: T
  onChange: (id: T) => void
  /** Names the set for assistive tech ("Port faces"). Not painted. */
  label: string
  className?: string
}) {
  return (
    <div
      role="tablist"
      aria-label={label}
      className={`-mx-1 flex flex-wrap gap-x-1 gap-y-0.5 px-1 ${className}`}
    >
      {tabs.map((t) => {
        const on = t.id === value
        return (
          <button
            key={t.id}
            role="tab"
            type="button"
            aria-selected={on}
            onClick={() => onChange(t.id)}
            className={[
              // `shrink-0` stays and `px-3` narrows to `px-2.5`: a wrapped tab must keep its own
              // width (a squeezed tab would hyphenate a one-word label), and 4px per side across
              // six faces is most of what a second row costs. `min-h-11` is the 44px reach floor
              // and is not negotiable at any width.
              'min-h-11 shrink-0 whitespace-nowrap border-b-2 px-2.5 font-mono text-xs uppercase tracking-wider transition',
              on
                ? 'border-accent bg-accent-soft text-accent'
                : 'border-transparent text-ink-faint hover:text-ink',
            ].join(' ')}
          >
            {t.label}
            {t.hint !== undefined && (
              <span className={`ml-1.5 ${on ? 'text-accent/70' : 'text-ink-faint/70'}`}>
                {t.hint}
              </span>
            )}
          </button>
        )
      })}
    </div>
  )
}
