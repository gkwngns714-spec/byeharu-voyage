import { useCallback, useLayoutEffect, useRef, useState, type MouseEvent, type ReactNode } from 'react'
import { useDismiss } from './useDismiss'

// A NAME THAT MAY BE CUT — and the only thing in this game that may be (2026-10-25, owner row 201:
// "some sentences such as 'the longests stretch a...', can't read, and cant find a way to read long
// sentences that are cut in this game").
//
// THE RULE, absolute:
//   * A SENTENCE — any multi-word explanatory text, a fact line, a caption, a refusal — is NEVER cut.
//     It wraps onto further lines inside its cell (`break-words`). There is no `truncate`, no
//     `line-clamp` and no `overflow-hidden whitespace-nowrap` on a sentence anywhere in src/.
//   * A short NAME in a fixed column (a ship, a captain, a good on a tile) may be cut with `…`, and
//     then ONLY through this component, which carries the full text two ways:
//       - a `title`, so a desktop hover reads it;
//       - a press, on a glass with no hover, opens the full name IN PLACE as a layer over the cell —
//         it takes no room, so nothing else on the page moves (docs: don't restructure on press).
//         A second press, a press elsewhere or Escape closes it. A name that is NOT cut lets the
//         press through to whatever the row does.
// tests/align.spec.ts (CUT) fails on any element whose text is cut and carries no full text.

export function Clip({
  children,
  className = '',
  'data-testid': testId,
}: {
  children: ReactNode
  className?: string
  'data-testid'?: string
}) {
  const [open, setOpen] = useState(false)
  const box = useRef<HTMLSpanElement>(null)
  const line = useRef<HTMLSpanElement>(null)
  const close = useCallback(() => setOpen(false), [])
  useDismiss(open, box, close)
  // the title is the full text read off what was drawn, so a name composed of parts has one; set on
  // the element after each paint rather than kept in state, which would draw everything twice
  useLayoutEffect(() => {
    const el = line.current
    if (el) el.title = el.textContent?.trim() ?? ''
  })

  const onClick = (e: MouseEvent<HTMLSpanElement>) => {
    const el = line.current
    if (!el) return
    const cut = el.scrollWidth > el.clientWidth + 1
    if (!open && (!cut || !window.matchMedia('(hover: none)').matches)) return
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
