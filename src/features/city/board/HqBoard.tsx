import { useMemo, useState } from 'react'
import { Chip, Empty, Icon, SheetSection } from '../../../components/ui'
import { MOVE_KINDS, type MoveKind } from '../../../domain/hq'
import { formatInt } from '../../../lib/format'
import { useT, type TKey } from '../../../lib/i18n'
import type { FleetJobRow, SnapshotPort } from '../../../lib/rpc'
import { litAway, useAwayReport } from '../../../live/useAwayReport'
import { litRace, useNationRace } from '../../../live/useNationRace'
import { litRoles, useShipRoles } from '../../../live/useShipRoles'
import { litSea, useSeaChoices } from '../../../live/useSeaChoices'
import { FirstVoyageLine } from '../../../live/FirstVoyageLine'
import { GoalCard } from '../../../live/GoalCard'
import { JobsAway } from './JobsAway'
import { Bridge } from './Bridge'
import { FleetRows } from './FleetRows'
import { KIND_ICON } from './jobMarks'
import { MoveCard } from './MoveCard'
import { RaceBridge } from './RaceBridge'
import { SeaChoiceCard } from './SeaChoiceCard'
import { useBoard } from './useBoard'
import { useMovePress } from './useMovePress'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// HQ'S COMMAND BOARD, v1 (owner, 2026-11-23: *"i want this game to be strategical game, where all the work (activities) are done in
// HQ - words with graphics. choosing best options available, finding best options."* — docs/design/hq-command-2026-11-23.md)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
//   RANK STRIP   her Rank and a bar to the next, what the next level opens, and net coin per hour as served (Bridge.tsx; H2,
//                docs/design/hq-corp-2026-11-24.md)
//   BEST MOVES   every move open now as a card, in the server's order (world.hq_board, 0480); the top few, More for the rest; icon
//                chips to filter. While the board's switch is dark: one line, "Board off" (the client ranks nothing of its own)
//   FLEETS       one row a fleet: picture, job, today's route money, Route / Plan; an idle fleet glows and offers her best card
//   0486         lit (sea_choices_enabled): A CHOICE AT SEA first of all (a storm, a wreck or a strange sail her long trip met: the options,
//                their odds as bars, the best by expected coin, the safe default, the clock to her arrival; one press), and While away
//                says each choice's end since she last pressed OK
//   0485         lit (ship_roles_enabled): each fleet row's role chips (guard, fast, big cargo) for each of her hulls; the board's role card
//                (the best role for her new hull, one press) and the yard's card naming the role the next hull should fill
//   0484         lit (nation_race_enabled): THE COUNTRY RACE under the bridge (her country's place, the countries' cities led as bars, her
//                influence, the week's clock, the home perk, her title), and a trade or request card in a contested city marks what it adds
//                for her country (an Influence chip, in the tone of who leads there); the Influence filter shows only those cards
//   0483         lit (contracts_enabled): courier contracts are served cards (take one, deliver one); their chip shows when one is served
//   0481         lit (fleet_jobs_enabled): WHILE AWAY at the top (what each standing job did), each fleet row's job mark and setter, and a
//                trade card's Repeat (that trip as her fixed route)
//
// It stands at the top of HQ, over the city's buildings, so it is the first thing seen; every building stays one press below it.

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

/** `port` (the city in hand) is no longer read: the board is the server's, for her whole company. CityScreen.tsx still passes it. */
export function HqBoard(props: { port: SnapshotPort | null }) {
  void props
  const t = useT()
  const board = useBoard()
  const press = useMovePress()
  const [filter, setFilter] = useState<Filter>('all')
  const [more, setMore] = useState(false)
  // 0481: her fleets' standing jobs (world.away_report; dark: null, and nothing of them is drawn)
  const away = litAway(useAwayReport().view)
  const jobs = useMemo(() => (away ? new Map<string, FleetJobRow>(away.jobs.map((j) => [j.fleet, j])) : null), [away])
  // 0484: the country race (world.nation_race; dark: null, and nothing of it is drawn)
  const race = litRace(useNationRace().view)
  // 0485: her hulls' roles (world.ship_roles; dark: null, and nothing of them is drawn)
  const roles = litRoles(useShipRoles().view)
  // 0486: her choices at sea (world.sea_choices; dark: null, and nothing of them is drawn)
  const sea = litSea(useSeaChoices().view)
  const raced = (m: (typeof board.moves)[number]) => m.data.kind === 'served' && (m.data.move.race?.points ?? 0) > 0
  const shown = board.moves.filter((m) => filter === 'all' || (filter === 'race' ? raced(m) : m.kind === filter))
  const list = more ? shown : shown.slice(0, TOP_MOVES)

  return (
    <div className="flex flex-col gap-6" data-testid="hq-board" data-source={board.source ?? undefined}>
      {sea?.open.map((c) => <SeaChoiceCard key={c.id} c={c} />)}
      {away && <JobsAway report={away} sea={sea?.recent ?? []} />}
      <Bridge board={board} />
      {/* H3 (2026-11-24, simplify S3): the goal card and the starter chain's step stood over the Trade desk; they stand under the bridge */}
      <div className="flex flex-col gap-2" data-testid="hq-goal">
        <GoalCard />
        <FirstVoyageLine />
      </div>
      {race && <RaceBridge race={race} />}

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
        <FleetRows fleets={board.fleets} moves={board.moves} jobs={jobs} roles={roles} />
      </SheetSection>
    </div>
  )
}
