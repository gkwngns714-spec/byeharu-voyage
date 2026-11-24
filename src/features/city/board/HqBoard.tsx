import { useState } from 'react'
import { Chip, Empty, Icon, SheetSection } from '../../../components/ui'
import { MOVE_KINDS, type MoveKind } from '../../../domain/hq'
import { formatInt } from '../../../lib/format'
import { useT, type TKey } from '../../../lib/i18n'
import { KIND_ICON } from './jobMarks'
import { MoveCard } from './MoveCard'
import type { Board } from './useBoard'
import { useMovePress } from './useMovePress'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// HQ'S BEST MOVES (owner, 2026-11-23: *"i want this game to be strategical game, where all the work (activities) are done in
// HQ - words with graphics. choosing best options available, finding best options."* — docs/design/hq-command-2026-11-23.md;
// docs/design/hq-corp-2026-11-24.md C1)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// Every move open now as a card, in the server's order (world.hq_board, 0480): the top few, More for the rest; icon chips to filter.
// While the board's switch is dark: one line, "Board off" (the client ranks nothing of its own).
//   0483 lit (contracts_enabled): courier contracts are served cards; their chip shows when one is served
//   0484 lit (nation_race_enabled): a trade or request card in a contested city marks what it adds for her country; the Influence
//        filter shows only those cards
//   0485 lit (ship_roles_enabled): the role card (the best role for her new hull) and the yard's card naming the next hull's role
//
// THIS IS ONE AREA OF HQ, NOT THE PAGE (the join, 2026-11-24): the page's order is corp/HqCompany.tsx's, which reads the board ONCE
// (useBoard) and hands it here. The Rank strip, While away, the sea choices and the country race are its other areas. The Fleets
// section this file drew is deleted: every fleet is a row of the one worker list (corp/WorkerList.tsx), and her standing job is set
// in the one Assign sheet, not by chips on a second row.

/** How many moves stand before More. */
export const TOP_MOVES = 5

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

export function HqBoard({ board }: { board: Board }) {
  const t = useT()
  const press = useMovePress()
  const [filter, setFilter] = useState<Filter>('all')
  const [more, setMore] = useState(false)
  const raced = (m: (typeof board.moves)[number]) => m.data.kind === 'served' && (m.data.move.race?.points ?? 0) > 0
  const shown = board.moves.filter((m) => filter === 'all' || (filter === 'race' ? raced(m) : m.kind === filter))
  const list = more ? shown : shown.slice(0, TOP_MOVES)

  return (
    <div data-testid="hq-board" data-source={board.source ?? undefined}>
      <SheetSection heading={t('hq.moves')} trailing={<span className="text-t-caption tabular-nums text-ink-faint">{formatInt(shown.length)}</span>}>
        {/* dark: no card to filter, so no chips */}
        {board.source !== 'off' && (
          <div className="mb-3 flex flex-wrap gap-2" role="group" aria-label={t('hq.filter')} data-testid="hq-filters">
            {(
              [
                'all',
                ...(board.moves.some(raced) ? (['race'] as const) : []),
                ...MOVE_KINDS.filter((k) => (k !== 'contract' && k !== 'role') || board.moves.some((m) => m.kind === k)),
              ] as Filter[]
            ).map((f) => (
              <Chip key={f} on={filter === f} onClick={() => setFilter(f)} data-testid={`hq-filter-${f}`}>
                <span className="inline-flex items-center gap-1">
                  {f !== 'all' && <Icon name={f === 'race' ? 'banner' : KIND_ICON[f]} size={16} aria-hidden />}
                  {t(FILTER_WORD[f])}
                </span>
              </Chip>
            ))}
          </div>
        )}
        {board.source === 'off' ? (
          <p className="text-t-label text-ink-muted" data-testid="hq-board-off">
            {t('hq.boardOff')}
          </p>
        ) : list.length === 0 ? (
          <Empty icon="compass">{t('hq.none')}</Empty>
        ) : (
          <ol className="grid grid-cols-1 gap-2 lg:grid-cols-2" data-testid="hq-moves">
            {list.map((m) => (
              <li key={m.id} className="min-w-0">
                <MoveCard move={m} onPress={press} />
              </li>
            ))}
          </ol>
        )}
        {shown.length > TOP_MOVES && (
          <button type="button" onClick={() => setMore((v) => !v)} className="mt-2 min-h-11 text-t-label text-accent" data-testid="hq-moves-more">
            {more ? t('hq.less') : t('hq.more')}
          </button>
        )}
      </SheetSection>
    </div>
  )
}
