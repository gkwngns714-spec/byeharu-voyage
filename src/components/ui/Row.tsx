import type { MouseEvent, ReactNode } from 'react'
import { Icon } from './Icon'

// THE ROW — 52px, and it is what a table was.
//
// ── WHAT IT REPLACES, COUNTED ──────────────────────────────────────────────────────────────────
// docs/UI_DIRECTION.md §3 rule 5 measured FIVE spellings of "label · value" in this tree —
// `StatRow`, `DetailRow`, `EntryTileLine`, the Map panel's private `Line`, and inline
// `grid grid-cols-[auto_1fr]` definition lists in two screens — plus the whole table apparatus
// that exists only so a table can survive a phone: `Table/TH/TD`, `scrollTableClass` with its
// sticky first column and painted scrollbar, `hScrollClass`, the `useClipped` ResizeObserver, and
// `TABLE_SCROLL_HINT` ("Swipe the table for the rest."). On screen the result was a column header
// that read `TRA…`.
//
// A row does not scroll sideways, so none of that machinery has anything to do. That is the whole
// argument: the tables were never carrying more than four facts, and four facts fit in a row.
//
// ── 52px, AND WHY IT IS A TOKEN ────────────────────────────────────────────────────────────────
// `--spacing-row` (src/index.css) is 3.25rem = 52px = the 44px reach floor plus the 8pt rhythm.
// It is a NAMED token rather than an arithmetic class so that a row cannot be spelled `min-h-13`
// in one file and `py-3.5` in another and drift by two pixels. tests/primitives.geometry.spec.ts
// measures it in the running build; this comment is not the guard.
//
// ── THE FOUR SLOTS, AND THE ONE THAT IS NOT ALLOWED ────────────────────────────────────────────
//   mark     a leading `Icon` or `RarityMark` — the row's identity at a glance
//   label    what it is, in `t-label`. Body copy lives here too; an empty section is ONE row of
//            `ink-3` text, which is what `EmptyState` was for
//   value    what it reads, normally a `<Figure>` — or a `<Bar>`, which is a figure you can see
//   chevron  set when the row OPENS something (a `Tray`, another sheet). Drawn, never `›`
// There is no `explain` slot and there never will be: §5 gives the caption voice to `Hint`, with a
// budget of one per section and none on a title. Eighty-one ⓘ dots is what the absence of that
// budget looks like.
//
// ── TAPPABLE IS A DIFFERENT ELEMENT, NOT A DIFFERENT SKIN ──────────────────────────────────────
// Pass `onClick` and the row renders a real `<button>` (`href` renders an `<a>`), so the whole
// 52px band is the target and a keyboard reaches it. A row that merely *looks* pressable is the
// defect this avoids by construction.
//
// THE TWO MAY BE PASSED TOGETHER, and that pairing is what a single-page router needs: the row
// stays a real `<a href>` — middle-click, long-press and assistive technology all keep working —
// while the plain left-click is handed to `onClick`, which calls `preventDefault()` and routes.
// (`Nav.tsx` carries the same pairing for the same reason. This app's database lives in the
// browser; a genuine anchor navigation re-opens PGlite.) The handler is given the event because
// there is no other way to refuse the browser's own navigation.

export type RowTone = 'default' | 'accent' | 'muted'

const TONE: Record<RowTone, string> = {
  default: 'text-ink',
  // Selected / yours. §4.4: gold means "you may act, or this is yours".
  accent: 'text-accent',
  // Absent, refused, not yet — the row is present and says so quietly.
  muted: 'text-ink-faint',
}

/** THE WRAPPING FLOW'S CLASSES, once per threshold (Tailwind reads class names as written, so each spelling is typed out). `narrow:` is a query
 *  container below 15 rem; `pair:` is one below 22 rem, for a row whose value is a pair of act cells. docs/dev-log/2026-11-02-city-phone.md. */
const FLOW = {
  narrow: {
    shell: 'narrow:relative narrow:flex narrow:flex-wrap narrow:gap-x-3',
    pad: 'narrow:pr-8',
    mark: 'narrow:shrink-0',
    label: 'narrow:ml-0 narrow:flex-[1_1_7rem] narrow:max-w-max',
    value: 'narrow:ml-0 narrow:max-w-full narrow:shrink-0 narrow:whitespace-normal',
    chevron: 'narrow:absolute narrow:right-0 narrow:top-2 narrow:ml-0',
    line2: 'narrow:ml-0 narrow:basis-full',
  },
  pair: {
    shell: 'pair:relative pair:flex pair:flex-wrap pair:gap-x-3',
    pad: 'pair:pr-8',
    mark: 'pair:shrink-0',
    label: 'pair:ml-0 pair:flex-[1_1_7rem] pair:max-w-max',
    value: 'pair:ml-0 pair:max-w-full pair:shrink-0',
    chevron: 'pair:absolute pair:right-0 pair:top-2 pair:ml-0',
    line2: 'pair:ml-0 pair:basis-full',
  },
} as const

export function Row({
  mark,
  label,
  value,
  chevron = false,
  tone = 'default',
  hairline = true,
  onClick,
  href,
  disabled = false,
  className = '',
  under = 'row',
  pair = false,
  children,
  ...rest
}: {
  mark?: ReactNode
  /** What this row is. A string, or a small stack the caller composes. */
  label: ReactNode
  /** What it reads — a `<Figure>`, a `<Bar>`, a word. Stands beside the label, never wrapped. */
  value?: ReactNode
  /** Set when pressing the row OPENS something. */
  chevron?: boolean
  tone?: RowTone
  /** The 1px `edge` parting rule under the row. Off for the last row of a group. */
  hairline?: boolean
  /** May be passed WITH `href`, in which case the row stays an anchor and this answers the click. */
  onClick?: (event: MouseEvent<HTMLElement>) => void
  href?: string
  disabled?: boolean
  className?: string
  /** A second line under the label — a `<Bar>`, a `<Hint>`. Rows grow; 52px is the FLOOR. */
  children?: ReactNode
  /** Where line 2 stands. `row` (default): under the label AND the value, so a list's bars share one
   *  track. `label`: under the label only, beside a value that is taller than one line (a pair of
   *  `ActCell`s), which then spans both lines — the row stays as tall as its value, not the sum. */
  under?: 'row' | 'label'
  /** The value is a PAIR of act cells (`ActPair`, 14.25 rem). Such a row stands beside its label from 22 rem of room and wraps under it
   *  below (`pair:`, index.css); any other row wraps below 15 rem (`narrow:`). */
  pair?: boolean
} & { 'data-testid'?: string }) {
  // THE LINE, AND THE LINE UNDER IT (2026-10-25, owner rows 196 and 198: "it is not in the same
  // line"). The row is a GRID, not a flex box. Line 1 holds the mark, the label and the value in
  // fixed tracks, and every cell's first line of text sits in ONE 24px line box (`.bv-row-line`,
  // src/index.css), so a label in `t-label`, a figure in `t-body` and a mark all centre on the same
  // y. Line 2 — `children`, the bar or the caption — spans from the label's start to the row's end,
  // so a list of ranked bars draws every bar on the same track whatever its figure reads. Before
  // this the value was centred against the label AND its bar together, half a line below the name,
  // and each bar was as long as its own row's label column: no two bars started or ended together.
  //
  // A CONTROL AS THE VALUE (a `Button`, 44px to the line's 24) is centred ON the line, hanging 10px
  // above and below it (src/index.css), so "Portugal" and "Change" read as one line rather than one
  // at the top and one centred in a taller box.
  // THE FIGURE SITS BESIDE ITS LABEL (owner, 2026-11-01: *"there are empty spaces between words and
  // numbers horizontally which is in effective. make it so that htey are closer, more compact"*).
  // Until that change the label owned a `1fr` track, so a short label pushed its figure to the far
  // right edge — the screen was mostly gap. The tracks are: mark · LABEL (content-sized) · VALUE ·
  // slack (1fr) · chevron. The slack absorbs the spare width AFTER the value, so the figure hugs the
  // label and the chevron still stands at the right edge; a list's bars (line 2) still span the full
  // width because they run to the last column.
  //
  // TWO RULES KEEP THE HUG FROM COSTING ROOM (main red on fe610dd0, 2026-11-01: the City's desk
  // face scrolled sideways, two buy/sell cells overlapped, the HQ book wrapped 24 px taller).
  //  1. A GAP BELONGS TO A CELL, NOT TO A TRACK. `gap-x-3` charges 12 px between every pair of tracks
  //     whether or not anything stands in them: five fixed tracks cost 48 px even for a row that is
  //     one lone label, so "No gifts yet." got 72 of the hall book's 120 px and wrapped to a second
  //     line. The shell has NO column gap; the cell that has a neighbour on its left carries `ml-3`
  //     (the same 12 px), so an empty mark / value / chevron slot and the slack track cost nothing.
  //  2. THE VALUE TRACK IS `max-content`, never `auto`. An `auto` track starts at its MIN-content (a
  //     buy+sell pair of two 112-px cells is 4 px wide at min-content) and shares the free space with
  //     the label's track, so the label took its whole width first and the pair was squeezed to
  //     176 px with its cells drawing over each other. `max-content` reserves the value's whole width
  //     first; the label takes what is left — as it did under the `1fr` label — and the label alone
  //     wraps.
  const columns = 'auto minmax(0, auto) max-content minmax(0, 1fr) auto'
  // every line-1 cell is PLACED, not auto-flowed: a value spanning two lines would otherwise be
  // auto-placed into the label's column
  const labelCol = 2
  const chevronCol = 5
  // the 12 px a cell keeps from the one before it (rule 1); a label and line 2 stand 12 px behind a mark
  const afterMark = mark !== undefined ? 'ml-3' : ''
  const flow = FLOW[pair ? 'pair' : 'narrow']
  // ── THE NARROW ROW: ON A PHONE'S HALF GLASS THE FIGURE MOVES UNDER ITS LABEL ─────────────────
  // (2026-11-02, docs/dev-log/2026-11-02-city-phone.md; owner: *"you know that this game is also for mobile
  // right?"*). Inside a query container narrower than 15 rem (the HQ's panel on a phone: 139 px at 390, 104 at
  // 320 — `narrow:`, index.css) the five tracks above cannot all stand: the value track is `max-content`, so a
  // figure wider than the row took the whole width and the label was squeezed to NOTHING (a good's name one letter
  // wide; "Space" in a column beside "0 / 750 tons"). The row is then a WRAPPING line instead — mark · label · value
  // standing in one flow, the chevron laid over the right edge of line 1, line 2 a full line of its own:
  //   · the LABEL never shrinks below its own text, up to 7 rem; past that it may wrap (`flex: 1 1 7rem`,
  //     `max-width: max-content`: a short label asks for exactly its words, a long one for 7 rem);
  //   · the VALUE stays whole while it can (a `Figure` is `nowrap`); when label and value do not fit one line, the
  //     value drops UNDER the label, flush with it — still ONE row, its pitch the 44-px floor or more; a value that is
  //     wider than the whole row even there ("none on board" is 111 px, a column of 104) wraps at its own spaces
  //     instead of standing past the row's edge and making the pane scroll sideways;
  //   · a gap belongs to a cell here too: the flow's `gap-x-3` is the 12 px, so every cell's `ml-3` is dropped.
  // A row that is not inside such a container — every other screen — never matches `narrow:` and is the grid above.
  const body = (
    <>
      {mark !== undefined && (
        <span className={`bv-row-line flex h-6 items-center ${flow.mark}`} style={{ gridRow: 1, gridColumn: 1 }} data-row-cell="mark">
          {mark}
        </span>
      )}
      <span
        className={`bv-row-line min-w-0 break-words text-t-label ${afterMark} ${flow.label}`}
        style={{ gridRow: 1, gridColumn: labelCol }}
        data-row-cell="label"
      >
        {label}
      </span>
      {value !== undefined && (
        <span
          className={`bv-row-line ml-3 whitespace-nowrap text-left text-t-body tabular-nums ${flow.value}`}
          style={{ gridRow: under === 'label' ? '1 / span 2' : 1, gridColumn: 3 }}
          data-row-cell="value"
        >
          {value}
        </span>
      )}
      {chevron && (
        <span
          className={`bv-row-line ml-3 flex h-6 items-center ${flow.chevron}`}
          style={{ gridRow: 1, gridColumn: chevronCol }}
          data-row-cell="chevron"
        >
          <Icon name="chevron" size={20} className="text-ink-faint" />
        </span>
      )}
      {children !== undefined && children !== null && children !== false && (
        <span
          className={`min-w-0 text-t-label ${afterMark} ${flow.line2}`}
          style={{ gridRow: 2, gridColumn: under === 'label' ? `${labelCol} / ${labelCol + 1}` : `${labelCol} / -1` }}
        >
          {children}
        </span>
      )}
    </>
  )

  const shell = [
    `grid w-full min-h-row content-center items-start py-2 text-left ${flow.shell}`,
    // the chevron is laid over the right edge in the narrow flow: its 20 px and 12 are kept clear of the line
    chevron ? flow.pad : '',
    hairline ? 'border-b border-edge' : '',
    TONE[tone],
    className,
  ]
    .filter(Boolean)
    .join(' ')
  const grid = { gridTemplateColumns: columns }

  if (href !== undefined) {
    return (
      <a href={href} onClick={onClick} className={shell} style={grid} data-row-line {...rest}>
        {body}
      </a>
    )
  }
  if (onClick !== undefined) {
    return (
      <button type="button" onClick={onClick} disabled={disabled} className={`${shell} disabled:opacity-45`} style={grid} data-row-line {...rest}>
        {body}
      </button>
    )
  }
  return (
    <div className={shell} style={grid} data-row-line {...rest}>
      {body}
    </div>
  )
}

// ── COLUMNS INSIDE THE VALUE ───────────────────────────────────────────────────────────────────
// A row that reads more than one figure (a price AND its move, a sparkline beside them) puts each in
// a `Col`: a FIXED-width, one-line, right-aligned, tabular cell. Fixed is the point — a column whose
// width is its own content starts wherever its row's digits happen to end, and a list of them is a
// ragged edge. One width scale, named here and nowhere else.
//   phone="hide"  the column stands down below the `sm` breakpoint; what it says must be said by
//                 another column or by line 2 of the row. Never a sideways scroll.
export type ColWidth = 'xs' | 'sm' | 'md' | 'lg'
const COL_W: Record<ColWidth, string> = {
  xs: 'w-10', // 40px: a short count
  sm: 'w-16', // 64px: a price, a percent change
  md: 'w-20', // 80px: a sparkline, a seven-digit figure
  lg: 'w-28', // 112px: a figure with its coin or unit
}

export function Col({
  w,
  phone,
  align = 'end',
  className = '',
  children,
}: {
  w: ColWidth
  phone?: 'hide'
  align?: 'start' | 'end'
  className?: string
  children: ReactNode
}) {
  const shown = phone === 'hide' ? 'hidden sm:flex' : 'flex'
  return (
    <span
      className={`${shown} ${COL_W[w]} shrink-0 items-center whitespace-nowrap tabular-nums ${align === 'end' ? 'justify-end text-right' : 'justify-start text-left'} ${className}`}
      data-col={w}
    >
      {children}
    </span>
  )
}

/** Several `Col`s side by side, as a row's `value`. */
export function Cols({ children }: { children: ReactNode }) {
  return <span className="flex items-center gap-3">{children}</span>
}
