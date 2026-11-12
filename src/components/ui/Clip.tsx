import { useCallback, useLayoutEffect, useRef, useState, type MouseEvent, type ReactNode } from 'react'
import { KEEP_WORDS_CLASS } from './tileStyles'
import { useDismiss } from './useDismiss'

// A NAME IS PRINTED WHOLE (2026-11-11, the full-names slice; the owner's rule, absolute: a NAME — a city, a good, a fleet, a
// ship, a captain, a house, a merchant, a route — is never cut with "…" in the game).
//
// THIS COMPONENT IS WHERE A NAME STANDS. Until 2026-11-11 it was the one place a name MIGHT be cut (a `truncate` line, read
// whole by a hover or a press). It is now the opposite, at the same address so that every place that already asked it for a
// name gets the rule at once:
//   * a name takes as many lines as it needs, and turns ONLY AT A SPACE (the design system's keeps-its-words rule,
//     `KEEP_WORDS_CLASS`, tileStyles.ts): its box is never narrower than its longest word, so no word is broken inside
//     itself, and a Korean name (no spaces) stays one word;
//   * it carries `data-name`, which is what tests/names.whole.spec.ts walks: no `data-name` element on any screen may be
//     clipped, in English or Korean, at 390 or 1,280 px.
//
// THE OLDER RULE STANDS BESIDE IT (2026-10-25, owner row 201): a SENTENCE is never cut either; it wraps (`break-words`).
//
// `cut` — THE ONE EXCEPTION, AND NEVER FOR A NAME: a single line of FIGURES in a bar of fixed height (the top bar's date,
// hour and price countdown on a phone) may still be cut with `…`, and then it carries its full text two ways: a `title` for
// a hover, and on a glass with no hover a press opens the whole line IN PLACE as a layer over the cell (nothing else moves;
// a second press, a press elsewhere or Escape closes it). Every `<Clip cut>` is on the allow-list of
// tests/names.whole.spec.ts with its reason; a new one fails there until it is listed.

export function Clip({
  children,
  className = '',
  cut = false,
  'data-testid': testId,
}: {
  children: ReactNode
  className?: string
  /** NOT A NAME: one line of figures that may be cut with `…` and read whole by a hover or a press. */
  cut?: boolean
  'data-testid'?: string
}) {
  if (cut) {
    return (
      <CutLine className={className} data-testid={testId}>
        {children}
      </CutLine>
    )
  }
  return (
    <span className={`block ${KEEP_WORDS_CLASS} ${className}`} data-name="" data-testid={testId}>
      {children}
    </span>
  )
}

function CutLine({ children, className, 'data-testid': testId }: { children: ReactNode; className: string; 'data-testid'?: string }) {
  const [open, setOpen] = useState(false)
  const box = useRef<HTMLSpanElement>(null)
  const line = useRef<HTMLSpanElement>(null)
  const close = useCallback(() => setOpen(false), [])
  useDismiss(open, box, close)
  // the title is the full text read off what was drawn, so a line composed of parts has one; set on
  // the element after each paint rather than kept in state, which would draw everything twice
  useLayoutEffect(() => {
    const el = line.current
    if (el) el.title = el.textContent?.trim() ?? ''
  })

  const onClick = (e: MouseEvent<HTMLSpanElement>) => {
    const el = line.current
    if (!el) return
    const isCut = el.scrollWidth > el.clientWidth + 1
    if (!open && (!isCut || !window.matchMedia('(hover: none)').matches)) return
    e.preventDefault()
    e.stopPropagation()
    setOpen((o) => !o)
  }

  return (
    <span ref={box} className={`relative block min-w-0 ${className}`} onClick={onClick}>
      <span ref={line} className="block truncate" data-testid={testId}>
        {children}
      </span>
      {open && (
        <span
          role="tooltip"
          className="absolute left-0 top-0 z-30 w-max max-w-[min(20rem,80vw)] whitespace-normal break-words rounded-control bg-surface-2 px-2 py-1 text-ink shadow-lg"
          data-testid="clip-full"
        >
          {children}
        </span>
      )}
    </span>
  )
}
