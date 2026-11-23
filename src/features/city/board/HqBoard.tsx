import { useMemo, useState } from 'react'
import { Chip, Empty, Icon, SheetSection } from '../../../components/ui'
import { MOVE_KINDS, type MoveKind } from '../../../domain/hq'
import { formatInt } from '../../../lib/format'
import { useT, type TKey } from '../../../lib/i18n'
import type { FleetJobRow, SnapshotPort } from '../../../lib/rpc'
import { litAway, useAwayReport } from '../../../live/useAwayReport'
import { JobsAway } from './JobsAway'
import { Bridge } from './Bridge'
import { FleetRows } from './FleetRows'
import { KIND_ICON } from './jobMarks'
import { MoveCard } from './MoveCard'
import { useBoard } from './useBoard'
import { useMovePress } from './useMovePress'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// HQ'S COMMAND BOARD, v1 (owner, 2026-11-23: *"i want this game to be strategical game, where all the work (activities) are done in
// HQ - words with graphics. choosing best options available, finding best options."* — docs/design/hq-command-2026-11-23.md)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
//   THE BRIDGE   coin and coin per hour · each fleet a ship in her job's tone · what finishes next · pirates near
//   BEST MOVES   every move open now as a card, ranked by domain/hq's one rule; the top few, More for the rest; icon chips to filter
//   FLEETS       one row a fleet: picture, job, today's route money, Route / Plan; an idle fleet glows and offers her best card
//   0483         lit (contracts_enabled): courier contracts are served cards (take one, deliver one); their chip shows when one is served
//   0481         lit (fleet_jobs_enabled): WHILE AWAY at the top (what each standing job did), each fleet row's job mark and setter, and a
//                trade card's Repeat (that trip as her fixed route)
//
// It stands at the top of HQ, over the city's buildings, so it is the first thing seen; every building stays one press below it.

/** How many moves stand before More. */
export const TOP_MOVES = 5

type Filter = 'all' | MoveKind
const FILTER_WORD: Record<Filter, TKey> = {
  all: 'hq.all',
  trade: 'hq.trade',
  request: 'hq.request',
  contract: 'hq.contract',
  yard: 'hq.yard',
  land: 'hq.land',
  crew: 'hq.crew',
  invest: 'hq.invest',
}

export function HqBoard({ port }: { port: SnapshotPort | null }) {
  const t = useT()
  const board = useBoard(port)
  const press = useMovePress()
  const [filter, setFilter] = useState<Filter>('all')
  const [more, setMore] = useState(false)
  // 0481: her fleets' standing jobs (world.away_report; dark: null, and nothing of them is drawn)
  const away = litAway(useAwayReport().view)
  const jobs = useMemo(() => (away ? new Map<string, FleetJobRow>(away.jobs.map((j) => [j.fleet, j])) : null), [away])
  const shown = board.moves.filter((m) => filter === 'all' || m.kind === filter)
  const list = more ? shown : shown.slice(0, TOP_MOVES)

  return (
    <div className="flex flex-col gap-6" data-testid="hq-board" data-source={board.served ? 'served' : 'client'}>
      {away && <JobsAway report={away} />}
      <Bridge board={board} />

      <SheetSection heading={t('hq.moves')} trailing={<span className="text-t-caption tabular-nums text-ink-faint">{formatInt(shown.length)}</span>}>
        <div className="mb-3 flex flex-wrap gap-2" role="group" aria-label={t('hq.filter')} data-testid="hq-filters">
          {(['all', ...MOVE_KINDS.filter((k) => k !== 'contract' || board.moves.some((m) => m.kind === 'contract'))] as Filter[]).map((f) => (
            <Chip key={f} on={filter === f} onClick={() => setFilter(f)} data-testid={`hq-filter-${f}`}>
              <span className="inline-flex items-center gap-1">
                {f !== 'all' && <Icon name={KIND_ICON[f]} size={16} aria-hidden />}
                {t(FILTER_WORD[f])}
              </span>
            </Chip>
          ))}
        </div>
        {list.length === 0 ? (
          <Empty icon="compass">{t('hq.none')}</Empty>
        ) : (
          <ol className="grid grid-cols-1 gap-2 lg:grid-cols-2" data-testid="hq-moves">
            {list.map((m) => (
              <li key={m.id} className="min-w-0">
                <MoveCard move={m} onPress={press} jobs={jobs} />
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

      <SheetSection heading={t('hq.fleets')}>
        <FleetRows fleets={board.fleets} moves={board.moves} jobs={jobs} />
      </SheetSection>
    </div>
  )
}
