import { Clip } from './Clip'
import type { ReactNode } from 'react'

// THE TRAY'S HEAD — a name, one line under it, and at most one control.
//
// ── ONE HEAD FOR EVERY TRAY THAT ANSWERS A TAP ─────────────────────────────────────────────────
// It was `features/map/MapTrayTitle.tsx`, written for the two map trays so the place tray and the
// fleet tray could not drift by a pixel; the merchant sheet (src/live) then wrote its own head
// inline — the same three things, a second time, in a file the first could not reach without a
// layer violation. The owner, 2026-10-13: *"the pop-up page when clicking a ship or a city is not
// good in terms of friendliness and style."* So the head is a primitive now, beside `Tray`, and
// the three trays compose it: the city, your fleet, a merchant.
//
// ── TWO LINES, NOT ONE ─────────────────────────────────────────────────────────────────────────
// The old head set the name and the line on ONE line (`Lisbon · Portugal · 3 ships resting`,
// truncated at 390px with a button beside it). A name is a title and the facts under it are a
// caption; on one line they are the same grey sentence. This is the three-step ladder §4.1 draws
// — `t-title` for what was tapped, `t-caption` for where or what — and it is what makes the peek
// read as a heading rather than as a row. `Tray`'s peek stop (trayDetents.ts, TRAY_PEEK) is sized
// for exactly this block: the handle row and this head, two lines, and nothing else.
//
// `min-h-9` is the 36px of a `size="sm"` button, so a head without a control stands as tall as
// one with it.
export function TrayTitle({
  name,
  line,
  trailing,
  testId,
}: {
  name: ReactNode
  /** Where, or what — `Portugal · 3 resting`, `Open sea`, `to Cadiz · 4m`. One line, never a sentence. */
  line?: ReactNode
  /** The one control the head may carry. */
  trailing?: ReactNode
  testId?: string
}) {
  return (
    <span className="flex min-h-9 items-center justify-between gap-3">
      <span className="min-w-0 flex-1">
        <Clip data-testid={testId}>
          {name}
        </Clip>
        {line !== undefined && (
          <span className="block break-words text-t-caption font-medium text-ink-muted" data-testid={testId ? `${testId}-line` : undefined}>
            {line}
          </span>
        )}
      </span>
      {trailing !== undefined && <span className="shrink-0">{trailing}</span>}
    </span>
  )
}
