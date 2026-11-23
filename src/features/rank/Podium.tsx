import type { ReactNode } from 'react'
import { Bar, Figure, Flag, FlagSlot, Icon, Row, type BarTone } from '../../components/ui'
import { formatInt } from '../../lib/format'
import { nationNameOf, useWorld } from '../../live/worldStore'

// THE RANK BOARDS' TWO PICTURES (2026-11-23, the visual overhaul's slice 8: docs/design/visual-overhaul-2026-11-23.md §3.8). The three
// boards (Week, Captains, Countries) read the same way: the top three stand on a PODIUM (the trophy over the first, each house's flag,
// its whole name, its figure, and a step whose height is its figure against the first's), your own line is pinned at the head of the
// list and lit, and every row is a mark, a figure and a bar — the place, the flag and the name, the figure at the right, and under them
// a bar measured against the board's first row. Nothing is ranked or summed here: the places, ties and figures are the server's, in the
// served order (rankFigures.ts says why), and a bar is only a served figure drawn against another served figure of the same list.

export interface PodiumStep {
  key: string
  /** The served place; null on a board that serves its order and no place (the countries'). */
  place: number | null
  name: string
  nation: string | null
  /** The served figure the step is measured by (its magnitude sets the height). */
  value: number
  /** How the figure reads. */
  text: string
  mine: boolean
}

/** The height of the shortest and the tallest step, px. */
const STEP_MIN = 28
const STEP_MAX = 84

/** THE PODIUM: the first three rows of a board, second · first · third across, each on a step as tall as its figure against the first's. */
export function Podium({ steps, label }: { steps: readonly PodiumStep[]; label: string }) {
  const nationByCode = useWorld((s) => s.nationByCode)
  if (steps.length === 0) return null
  const widest = Math.max(...steps.map((s) => Math.abs(s.value))) || 1
  // second · first · third: the first stands in the middle, the classic podium; a board of one or two still centres its first
  const order = steps.length === 1 ? [0] : steps.length === 2 ? [1, 0] : [1, 0, 2]
  return (
    <div
      role="list"
      aria-label={label}
      className={`col-span-full mb-3 grid items-end gap-2 px-2 sm:gap-3 ${steps.length === 1 ? 'grid-cols-1' : steps.length === 2 ? 'grid-cols-2' : 'grid-cols-3'}`}
      data-testid="rank-podium"
    >
      {order.map((i) => {
        const s = steps[i]
        const height = STEP_MIN + Math.round((Math.abs(s.value) / widest) * (STEP_MAX - STEP_MIN))
        // a step is a wash, no border: a surface has none (docs/UI_DIRECTION.md §4.3; tests/duplication.spec.ts); yours is the gold wash
        return (
          <div key={s.key} role="listitem" className="flex min-w-0 flex-col items-center gap-1 text-center" data-testid="rank-podium-step" data-place={s.place ?? undefined} data-mine={s.mine ? '' : undefined}>
            {i === 0 ? <Icon name="trophy" size={22} className={s.mine ? 'text-accent' : 'text-ink-muted'} aria-hidden="true" /> : <span className="h-[22px]" aria-hidden="true" />}
            {s.nation === null ? <FlagSlot size="title" /> : <Flag code={s.nation} name={nationNameOf(nationByCode, s.nation)} size="title" />}
            <span className={`w-full min-w-0 text-t-label [overflow-wrap:anywhere] ${s.mine ? 'font-semibold text-accent' : 'text-ink'}`} data-testid="rank-podium-name">
              {s.name}
            </span>
            <Figure value={s.text} tone={s.mine ? 'accent' : 'ink'} />
            <div
              className={`flex w-full items-start justify-center rounded-t-[10px] pt-1 ${s.mine ? 'bg-accent-soft' : 'bg-surface-2'}`}
              style={{ height }}
              aria-hidden="true"
            >
              {s.place !== null && <span className={`text-t-label font-semibold tabular-nums ${s.mine ? 'text-accent' : 'text-ink-muted'}`}>{formatInt(s.place)}</span>}
            </div>
          </div>
        )
      })}
    </div>
  )
}

/** YOUR LINE, PINNED: the first thing under the podium, a whole line of the card (no wider than a row may be). */
export function Pinned({ children }: { children: ReactNode }) {
  return (
    <div className="col-span-full mb-2 max-w-[36rem]" data-testid="rank-pinned">
      {children}
    </div>
  )
}

/** ONE LINE OF A BOARD: the place, the flag and the whole name, the figure, and under them a bar against the board's first row. */
export function BoardRow({
  place,
  name,
  nation,
  value,
  text,
  widest,
  mine,
  tone,
  caption,
  pinned = false,
  onClick,
  ...rest
}: {
  place: number | null
  name: ReactNode
  nation: string | null
  value: number
  text: string
  /** The magnitude the bar is measured against (the board's first row). */
  widest: number
  mine: boolean
  /** The bar's meaning (`accent` for yours by default; `success`/`danger` for a gain or a loss). */
  tone?: BarTone
  /** A short caption beside the bar (a country's home and won, the cities a company is mayor of). */
  caption?: ReactNode
  /** Your line at the head of the list: a gold edge as well as the gold wash. */
  pinned?: boolean
  onClick?: () => void
} & { 'data-testid'?: string }) {
  const nationByCode = useWorld((s) => s.nationByCode)
  const pct = widest > 0 ? (Math.abs(value) / widest) * 100 : 0
  return (
    <Row
      mark={place === null ? undefined : <Figure value={formatInt(place)} tone={mine ? 'accent' : 'faint'} className="w-7 justify-end" />}
      label={
        <span className="flex min-w-0 items-center gap-2">
          {nation === null ? <FlagSlot /> : <Flag code={nation} name={nationNameOf(nationByCode, nation)} />}
          <span className="min-w-0">{name}</span>
        </span>
      }
      value={<Figure value={text} tone={mine ? 'accent' : 'ink'} />}
      tone={mine ? 'accent' : 'default'}
      chevron={onClick !== undefined}
      // ONE FIGURE COLUMN (owner, 2026-11-12): a row without the chevron keeps the chevron's room
      className={`${onClick === undefined ? 'pr-8' : ''} ${pinned ? 'ring-1 ring-accent/50 ring-inset' : ''}`}
      wholeName
      hairline={false}
      onClick={onClick}
      {...rest}
    >
      {caption !== undefined && caption !== null && <span className="block text-t-caption text-ink-faint">{caption}</span>}
      <Bar pct={pct} tone={tone ?? (mine ? 'accent' : 'neutral')} className="mt-1" />
    </Row>
  )
}
