import { useLayoutEffect, useRef, useState } from 'react'
import { openHq } from '../../../app/hqPlace'
import { Chip, Icon, SheetSection, Skeleton } from '../../../components/ui'
import { MOVE_KINDS, type MoveKind } from '../../../domain/hq'
import { formatInt } from '../../../lib/format'
import { useT, type TKey } from '../../../lib/i18n'
import { KIND_ICON } from './jobMarks'
import { MoveCard } from './MoveCard'
import { useBoard, type Board } from './useBoard'
import { useMovePress } from './useMovePress'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// HQ'S BEST MOVES (owner, 2026-11-23: *"i want this game to be strategical game, where all the work (activities) are done in
// HQ - words with graphics. choosing best options available, finding best options."* — docs/design/hq-command-2026-11-23.md;
// docs/design/hq-corp-2026-11-24.md C1)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// Every move open now as a card, in the server's order (world.hq_board, 0480): the top three, More for the rest; icon chips to filter.
// While the board's switch is dark: the same three slots, empty, the first saying "Board off" (the client ranks nothing of its own).
//   0483 lit (contracts_enabled): courier contracts are served cards; their chip shows when one is served
//   0484 lit (nation_race_enabled): a trade or request card in a contested city marks what it adds for her country; the Influence
//        filter shows only those cards
//   0485 lit (ship_roles_enabled): the role card (the best role for her new hull) and the yard's card naming the next hull's role
//
// THIS IS ONE AREA OF HQ, NOT THE PAGE (the join, 2026-11-24): the page's order is corp/HqCompany.tsx's, which reads the board ONCE
// (useBoard) and hands it here. The Rank strip, While away, the sea choices and the country race are its other areas. The Fleets
// section this file drew is deleted: every fleet is a row of the one worker list (corp/WorkerList.tsx), and her standing job is set
// in the one Assign sheet, not by chips on a second row.
//
// ── A FIXED SHAPE (2026-11-25, the owner's law: nothing on a page moves by itself; the design's own `BEST MOVES [card][card][card] [More]`) ──
// The area is the same boxes before the board's read answers, after it, and whatever it says: the heading with More, ONE line of filter
// chips (the ones that fit it; More's sheet has all), and exactly THREE card slots of one height (one under another on a phone, side by side from `xl`: at 1024 three columns are too narrow for a card). A slot is a skeleton while
// the board is asked, a card when there is one, and a quiet empty box when there are fewer; the first empty box says why when there is
// none at all ("Board off", "No moves now"). So a late answer, a dark switch, a filter with one card and a board that serves seven
// today and two tomorrow all leave the Storage, the Ledger and the plates where they stood.
// The rest of the cards are one press away, in place: More opens every move, with the same filters, in a sheet over HQ (`moves`).
// A card too tall for its slot is cut at the slot's foot there (the sheet shows it whole); the slot is sized for the tallest card a
// 320-px glass draws today.

/** How many moves stand on HQ; the rest are behind More. */
export const TOP_MOVES = 3

/** One slot's height: the tallest card HQ draws (a title on two lines over two lines of chips), at every width. */
const SLOT = 'h-40'

/** 'race' (0484): the cards that add to her country's weekly race, whatever their kind. */
type Filter = 'all' | 'race' | MoveKind
const FILTER_WORD: Record<Filter, TKey> = {
  all: 'hq.all',
  race: 'hq.influence',
  trade: 'hq.trade',
  request: 'hq.request',
  contract: 'hq.contract',
  yard: 'hq.yard',
  role: 'hq.role',
  land: 'hq.land',
  crew: 'hq.crew',
  invest: 'hq.invest',
}

type Card = Board['moves'][number]
const raced = (m: Card) => m.data.kind === 'served' && (m.data.move.race?.points ?? 0) > 0
const pick = (moves: readonly Card[], filter: Filter) => moves.filter((m) => filter === 'all' || (filter === 'race' ? raced(m) : m.kind === filter))

/** The filter chips: All, then only the kinds the board has a card of (a chip that would show nothing is not drawn).
 *  `line`: on HQ they stand on ONE line of one height. A chip more or fewer, or none at all while the board is asked or dark, never
 *  changes the area's height, and nothing scrolls sideways: a chip that does not fit the line gives way WHOLE (hidden from sight and
 *  from the keyboard; the desk's From here line has the same rule), and More's sheet has every one, wrapped. */
function Filters({ board, filter, onFilter, line }: { board: Board; filter: Filter; onFilter: (f: Filter) => void; line: boolean }) {
  const t = useT()
  const chips: Filter[] =
    board.source !== 'served' ? [] : ['all', ...(board.moves.some(raced) ? (['race'] as const) : []), ...MOVE_KINDS.filter((k) => board.moves.some((m) => m.kind === k))]
  const row = useRef<HTMLDivElement>(null)
  const drawn = chips.join(' ')
  useLayoutEffect(() => {
    const el = row.current
    if (!line || !el) return
    const lay = () => {
      const cells = [...el.children].filter((c): c is HTMLElement => c instanceof HTMLElement)
      const top = cells[0]?.offsetTop ?? 0
      for (const c of cells) {
        const out = c.offsetTop > top
        c.style.visibility = out ? 'hidden' : ''
        c.toggleAttribute('data-gave-way', out)
      }
    }
    lay()
    const seen = new ResizeObserver(lay)
    seen.observe(el)
    return () => seen.disconnect()
  }, [line, drawn])
  return (
    <div
      ref={row}
      // one line, 44 px: a chip that wraps stands a whole row (gap-y-4) under the cut and is hidden
      className={line ? 'mb-2 flex h-11 flex-wrap gap-x-2 gap-y-4 overflow-hidden' : 'mb-3 flex flex-wrap gap-2'}
      role="group"
      aria-label={t('hq.filter')}
      data-testid="hq-filters"
    >
      {chips.map((f) => (
        <Chip key={f} on={filter === f} onClick={() => onFilter(f)} data-testid={`hq-filter-${f}`}>
          <span className="inline-flex items-center gap-1 whitespace-nowrap">
            {f !== 'all' && <Icon name={f === 'race' ? 'banner' : KIND_ICON[f]} size={16} aria-hidden />}
            {t(FILTER_WORD[f])}
          </span>
        </Chip>
      ))}
    </div>
  )
}

export function HqBoard({ board }: { board: Board }) {
  const t = useT()
  const press = useMovePress()
  const [filter, setFilter] = useState<Filter>('all')
  const shown = pick(board.moves, filter)
  const more = shown.length > TOP_MOVES
  // why there is no card at all, said once, in the first empty slot (nothing is said while the board is still asked)
  const none = board.source === 'off' ? { word: t('hq.boardOff'), testid: 'hq-board-off' } : { word: t('hq.none'), testid: 'hq-board-none' }

  return (
    <div data-testid="hq-board" data-source={board.source ?? undefined}>
      <SheetSection
        heading={t('hq.moves')}
        trailing={
          <span className="flex items-center gap-3">
            <span className="text-t-caption tabular-nums text-ink-faint" data-testid="hq-moves-count">
              {board.asking ? '' : formatInt(shown.length)}
            </span>
            {/* More stands always (the heading's line keeps its height); it is a press only when there are more than the three */}
            <button
              type="button"
              disabled={!more}
              onClick={() => openHq({ sheet: 'moves' })}
              className="min-h-11 min-w-11 text-t-label text-accent disabled:text-ink-faint disabled:opacity-45"
              data-testid="hq-moves-more"
            >
              {t('hq.more')}
            </button>
          </span>
        }
      >
        <Filters board={board} filter={filter} onFilter={setFilter} line />
        <ol className="grid grid-cols-1 gap-2 xl:grid-cols-3" data-testid="hq-moves" aria-busy={board.asking || undefined}>
          {Array.from({ length: TOP_MOVES }, (_, i) => {
            const m = shown[i]
            return (
              <li key={i} className={`min-w-0 overflow-hidden rounded-tile ${SLOT}`} data-testid="hq-move-slot" data-slot={board.asking ? 'asking' : m ? 'card' : 'empty'}>
                {board.asking ? (
                  <Skeleton className="h-full w-full rounded-tile" />
                ) : m ? (
                  <MoveCard key={m.id} move={m} onPress={press} slot />
                ) : (
                  <div className="flex h-full items-center justify-center rounded-tile border border-dashed border-edge text-t-label text-ink-faint">
                    {i === 0 && shown.length === 0 && <span data-testid={none.testid}>{none.word}</span>}
                  </div>
                )}
              </li>
            )
          })}
        </ol>
      </SheetSection>
    </div>
  )
}

/** EVERY MOVE, IN A SHEET OVER HQ (Best moves' More): the same served cards in the server's order, whole, with the same filters. It
 *  asks nothing new: `useBoard` is the page's own read, answered from what is kept. */
export function AllMoves() {
  const t = useT()
  const board = useBoard()
  const press = useMovePress()
  const [filter, setFilter] = useState<Filter>('all')
  const shown = pick(board.moves, filter)
  return (
    <div data-testid="hq-moves-all">
      <Filters board={board} filter={filter} onFilter={setFilter} line={false} />
      {shown.length === 0 ? (
        <p className="text-t-label text-ink-muted">{board.source === 'off' ? t('hq.boardOff') : board.asking ? ' ' : t('hq.none')}</p>
      ) : (
        <ol className="grid grid-cols-1 gap-2 lg:grid-cols-2">
          {shown.map((m) => (
            <li key={m.id} className="min-w-0">
              <MoveCard move={m} onPress={press} />
            </li>
          ))}
        </ol>
      )}
    </div>
  )
}
