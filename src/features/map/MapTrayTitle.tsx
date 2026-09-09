import type { ReactNode } from 'react'

// THE TRAY'S PEEK ROW — a name, one line, and at most one control.
//
// docs/UI_DIRECTION.md §6, MAP: "peek shows name + one line; half shows Send". `Tray`'s peek is
// 96px: 52 of handle and 44 of title row. This is that 44px, for both of the map's trays, so the
// place tray and the fleet tray cannot drift by a pixel from each other: the name at `t-title`, the
// line at `t-caption` beside it, and — on a place — the `Send fleet` press at the right, which is
// the owner's step one (*"press send fleet, then it will unfold to my fleets"*). `min-h-9` is the
// 36px of that button, so the row is the same height whether or not it carries one.
export function MapTrayTitle({
  name,
  line,
  trailing,
  testId,
}: {
  name: ReactNode
  /** Where, or what — `Spain`, `Open sea`, `to Cadiz · 4m`. One line, never a sentence. */
  line?: ReactNode
  /** The one control the peek row may carry. */
  trailing?: ReactNode
  testId?: string
}) {
  return (
    <span className="flex min-h-9 items-center justify-between gap-3">
      <span className="min-w-0 truncate">
        <span data-testid={testId}>{name}</span>
        {line !== undefined && <span className="ml-2 text-t-caption text-ink-faint">{line}</span>}
      </span>
      {trailing !== undefined && <span className="shrink-0">{trailing}</span>}
    </span>
  )
}
