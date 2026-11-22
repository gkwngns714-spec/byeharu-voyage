import { useEffect, useMemo, useState } from 'react'
import {
  Card,
  Figure,
  Flag,
  FlagSlot,
  Hint,
  Icon,
  ListPanel,
  Note,
  PageSplit,
  RankBars,
  Row,
  Segmented,
  Sheet,
  Skeleton,
  StackedBar,
  StatCell,
  Tray,
  type RankRow,
  type StackedPart,
  type TrayDetent,
} from '../../components/ui'
import { BoardRow, Pinned, Podium, type PodiumStep } from './Podium'
import { formatInt, formatRelative } from '../../lib/format'
import { worldHousesWeek, type PlayerHouse, type StandingsBoard } from '../../lib/rpc'
import { HullCountry } from '../../live/HullCountry'
import { nationNameOf, useWorld } from '../../live/worldStore'
import { WorldFailed, WorldLoading } from '../../live/WorldGate'
import { CountriesBoard } from './CountriesBoard'
import { WeekBoard } from './WeekBoard'
import { BountyBoard } from './BountyBoard'
import { usePirateBounties } from '../../live/usePirateBounties'
import { useServedRead } from '../../live/useServedRead'
import { leadersOf, linesOf, type Line } from './rankFigures'
import { useLocale, useT } from '../../lib/i18n'
import { tabWord } from '../../app/navTabs'

// RANK — the board, ON THE PAGE. docs/UI_DIRECTION.md §6 "RANK".
//
// THE PAGE, NOT THE PACKED COLUMN (2026-11-03, owner row 267: *"it looks so wrong. The past was better. right now
// everything is on left, too packed. this was a mistake"*). The unfold slice (2026-11-02, row 260) put the two faces over ONE
// list panel in a 75-rem column with 26 rem kept clear at the right — your line pinned in its header, the board scrolling
// under it inside the panel. Rank is now a PAGE (`Sheet layout="page"`, screenLayout.ts "THE PAGE") on the pattern Stats set
// (docs/dev-log/2026-11-02-stats-design.md, Card.tsx) and the Codex and History followed: MAIN | SIDE from 1,024 px — MAIN
// the board as ONE list card whose rows stand in as many columns as the main holds (the place as each row's mark, so two
// columns still read as one ladder); the SIDE the tray's column, holding YOUR STANDING AS GRAPHICS (the place and the fame
// at 24 px, the two fames the total is made of as one stacked bar, the ports and the companies as lines) and the LEADERS —
// the first rows of the board as ranked bars. The page scrolls, never a list inside itself; nothing is pinned and nothing
// follows the scroll. The numbers it was measured to are in docs/dev-log/2026-11-03-rank-design.md.
//
// YOUR LINE IS PINNED AT THE HEAD OF THE LIST (2026-11-23, the visual overhaul's slice 8): under the podium of the top three, lit,
// whether you placed or stand off the board's end (0025 serves `you` off the end for exactly this), and lit again in its place when
// you placed. It is pinned in the flow, not docked: it does not follow the scroll (the page pattern pins nothing that moves; it
// stood in the panel's header and followed the scroll until 2026-11-03). Every row is the place, the flag and the whole name, the
// figure, and a bar against the first row (Podium.tsx).
//
// YOUR LINE OPENS THE FAME TRAY — the place, the country, the two fames the total is made of, the ports, the cities you are
// mayor of, the total — and it slides over the side column and moves nothing, as it always did. The other rows are read-only,
// as they were: 0025 serves the two fames and the ports on every row, but for another company they were never a decision
// (its header says what it deliberately does NOT serve — no purse, no cargo, no fleet, no port — and that is not restated
// here). A first cut of this slice made every row a button; tests/i18n.ko.spec.ts refused it, rightly — a button is the
// client's own element, and ten served company names stood in it that no data file lists. The `Line` shape and the tray's
// rows are one house's, so the tray COULD open any row; that it opens yours is a choice, not a limit of the payload.
//
// ONE CLOCK. Everything on this screen is the PHOTOGRAPH `public.standings` took (0025), and the title's trailing line says
// how old it is, measured by the server (`age_seconds`), never by this browser's clock. Your own live record is PROFILE's.

/** How many of the board's rows the Leaders board draws as bars. */
const LEADERS = 5

export function RankScreen() {
  // THE TITLE IS THE TAB'S OWN WORD (navTabs.tabWord). It read "Standings" while the rail said
  // "Rank" — two words for one screen (the audit, 2026-10-31).
  const title = tabWord(useLocale(), '/rank')
  // FIELDS, NOT THE STORE (worldStore.ts rule 4).
  const phase = useWorld((s) => s.phase)
  const fatal = useWorld((s) => s.fatal)

  if (phase === 'failed') {
    return <WorldFailed title={title} refusal={fatal} />
  }
  if (phase !== 'ready') {
    return <WorldLoading title={title} />
  }
  return <RankBody />
}

function RankBody() {
  const t = useT()
  const title = tabWord(useLocale(), '/rank')
  const house = useWorld((s) => s.player)
  const board = useWorld((s) => s.standings)
  const loadStandings = useWorld((s) => s.loadStandings)
  const readAt = useWorld((s) => s.readAt)

  // WHETHER THE BOARD HAS ANSWERED, which `standings === null` alone cannot say: null is both "not
  // asked yet" and "the read was refused", and without the distinction a refused read draws a
  // skeleton for ever.
  const [answered, setAnswered] = useState(false)
  // 0148: Captains (the board) or Countries (who holds the cities). 0467: Week (the houses' board), offered only when the server says
  // it is on (houses_board_enabled), and then the face a captain lands on until they pick another.
  // 0471: Bounties (the named pirates), offered only when the server says it is on (pirate_bounties_enabled), never the face landed on.
  const [picked, setPicked] = useState<'week' | 'captains' | 'countries' | 'bounties' | null>(null)
  const weekRead = useServedRead('houses-week', worldHousesWeek, { name: 'worldHousesWeek' })
  const week = weekRead.view
  const weekOn = week?.on === true
  // THE TABS WAIT FOR THE WEEK'S ANSWER (2026-11-23, third play-test finding 17): Rank opened on Captains and, 4 s later, Week
  // appeared in front and took the page. Until the read has answered (a view, or a refusal) the tab bar and the board are held.
  const weekKnown = week !== null || !weekRead.loading
  const bounties = usePirateBounties()
  const bountiesOn = bounties?.on === true
  const chosen = (picked === 'week' && !weekOn) || (picked === 'bounties' && !bountiesOn) ? 'captains' : picked
  const face = chosen ?? (weekOn ? 'week' : 'captains')

  // KEYED ON `readAt`: the world re-reads itself every thirty seconds and on tab focus, and the
  // board rides that same beat — a refused read is retried with no button, and a new slot's
  // photograph appears on its own.
  useEffect(() => {
    if (readAt === null) return
    let alive = true
    void loadStandings().then(() => {
      if (alive) setAnswered(true)
    })
    return () => {
      alive = false
    }
  }, [loadStandings, readAt])

  // `formatRelative` reads only the GAP between its two instants, so (−age, 0) asks it exactly
  // what `age_seconds` already measured, and a skewed device clock cannot age a server's record.
  const settled =
    board !== null && board.age_seconds !== null ? formatRelative(-board.age_seconds * 1000, 0) : null

  // THE PAGE SCROLLS (2026-11-03, owner row 267): no `fill`, no inner scroll — the board is as tall as its rows.
  return (
    <Sheet
      title={title}
      layout="page"
      data-testid="rank"
      trailing={
        // 0473: the Captains' photograph's age, on its own faces (the Week board says its own clock, the Bounties none)
        settled === null || face === 'week' || face === 'bounties' ? undefined : (
          <span className="text-t-caption text-ink-faint">{t('rank.settled', { when: settled })}</span>
        )
      }
    >
      {!weekKnown ? (
        <div data-testid="rank-hold" aria-busy>
          <Skeleton className="h-11 w-full max-w-sm" />
          <Skeleton className="mt-3 h-12 w-full" />
          <Skeleton className="mt-2 h-12 w-full" />
        </div>
      ) : (
        <>
          <Segmented
            segments={[
              ...(weekOn ? [{ id: 'week' as const, label: t('rank.weekly') }] : []),
              { id: 'captains' as const, label: t('rank.captains') },
              { id: 'countries' as const, label: t('rank.countries') },
              ...(bountiesOn ? [{ id: 'bounties' as const, label: t('bounty.tab') }] : []),
            ]}
            value={face}
            onChange={setPicked}
            label={title}
            className="w-fit max-w-full max-sm:w-full"
          />
          {face === 'bounties' ? (
            <BountyBoard read={bounties} />
          ) : face === 'week' ? (
            <WeekBoard read={week} />
          ) : face === 'captains' ? (
            <Board board={board} answered={answered} house={house} />
          ) : (
            <CountriesBoard />
          )}
        </>
      )}
    </Sheet>
  )
}

/**
 * THE BOARD (0025). Four states, and three of them are STATES rather than faults:
 *   not answered yet    skeleton rows, only until the read lands
 *   answered, no board  the read was refused — say so, do not draw an empty list
 *   houses = 0          an empty world, carrying the server's OWN `why`
 *   you = null          signed in, no company: the board is real and no line on it is yours
 */
function Board({
  board,
  answered,
  house,
}: {
  board: StandingsBoard | null
  answered: boolean
  /** YOUR name and flag, which the payload's `you` deliberately omits — `world.player()` owns them. */
  house: PlayerHouse | null
}) {
  const t = useT()
  const nationByCode = useWorld((s) => s.nationByCode)
  const [open, setOpen] = useState<Line | null>(null)
  const [detent, setDetent] = useState<TrayDetent>('closed')

  const yourName = house?.company_name ?? t('rank.yourCompany')
  const yourNation = house?.nation ?? null
  const lines = useMemo(() => (board === null ? null : linesOf(board, { name: yourName, nation: yourNation })), [board, yourName, yourNation])

  if (!board || lines === null) {
    return (
      <ListPanel look="card" title={t('rank.captains')} data-testid="rank-list">
        {answered ? (
          <Note tone="warning" className="my-1">
            {t('rank.failed')}
          </Note>
        ) : (
          <div className="space-y-2 py-1">
            <Skeleton className="h-12 w-full" />
            <Skeleton className="h-12 w-full" />
            <Skeleton className="h-12 w-2/3" />
          </div>
        )}
      </ListPanel>
    )
  }
  if (board.board.length === 0) {
    return (
      <ListPanel look="card" title={t('rank.captains')} data-testid="rank-list">
        <Row label={board.why ?? t('rank.empty')} tone="muted" hairline={false} />
      </ListPanel>
    )
  }

  const mine = lines.mine
  const flag = (code: string | null) => (code === null ? null : nationNameOf(nationByCode, code))
  const show = (line: Line) => {
    setOpen(line)
    setDetent('half')
  }
  // THE BAR'S MEASURE: the board's first row (the server's order is the ranking — a slice, never a sort)
  const widest = Math.abs(lines.rows[0]?.total_fame ?? 0)
  // 2026-11-23 (slice 8): a row is a mark, a figure and a bar — the place, the flag and the whole name, the fame, a bar against the
  // first. "tied" left the row: two houses level wear the same place, and the tray still says it. Your line in its place is lit; the
  // one press it opens is your PINNED line at the head of the list (`rank-you`).
  const row = (r: Line, pinned = false) => (
    <BoardRow
      key={`${pinned ? 'pin' : 'row'}-${r.position}-${r.name}`}
      place={r.position}
      name={r.name}
      nation={r.nation}
      value={r.total_fame}
      text={formatInt(r.total_fame)}
      widest={widest}
      mine={r.mine}
      pinned={pinned}
      caption={
        r.mayor_of.length > 0 ? <span data-testid="rank-mayor-of">{t('rank.mayorOf', { cities: r.mayor_of.join(', ') })}</span> : undefined
      }
      onClick={pinned ? () => show(r) : undefined}
      data-testid={pinned ? 'rank-you' : 'rank-row'}
    />
  )
  const podium: PodiumStep[] = leadersOf(lines.rows, 3).map((r) => ({
    key: `${r.position}-${r.name}`,
    place: r.position,
    name: r.name,
    nation: r.nation,
    value: r.total_fame,
    text: formatInt(r.total_fame),
    mine: r.mine,
  }))

  // THE TWO FAMES THE TOTAL IS MADE OF, as the parts of one bar (0014's two tracks; the server sums them)
  const split: StackedPart[] =
    mine === null
      ? []
      : [
          { id: 'trade', label: t('rank.trade'), value: mine.trade_fame, tone: 'accent' },
          { id: 'exploration', label: t('rank.exploration'), value: mine.exploration_fame, tone: 'info' },
        ]
  // the leaders' flags are pictures (their names the pictures' accessible names), not a caption line under each name
  const leaders: RankRow[] = leadersOf(lines.rows, LEADERS).map((r) => ({
    id: `${r.position}-${r.name}`,
    label: (
      <span className="flex min-w-0 items-center gap-2">
        {r.nation === null ? <FlagSlot /> : <Flag code={r.nation} name={flag(r.nation) ?? r.nation} />}
        <span className="min-w-0">{r.name}</span>
      </span>
    ),
    value: r.total_fame,
    tone: r.mine ? 'accent' : 'neutral',
  }))

  return (
    <>
      <PageSplit
        data-testid="rank-page"
        // no `sideFirst`: on a phone your standing stands AFTER the board — the screen's purpose is the board, and its first
        // row is on the first glass (the Codex's lesson, 2026-11-02)
        stickySide
        main={
          <ListPanel
            look="card"
            columns="fit"
            title={t('rank.captains')}
            count={formatInt(lines.rows.length)}
            // OFF THE BOARD'S END (0025 serves `you` whether or not you placed): the one caption of the card says the cut
            footer={mine !== null && !lines.onBoard ? <Hint>{t('rank.below', { n: formatInt(board.board_size) })}</Hint> : undefined}
            data-testid="rank-list"
          >
            <Podium steps={podium} label={t('rank.podium')} />
            {/* YOUR LINE, PINNED AT THE HEAD OF THE LIST (slice 8), whether you placed or stand off the board's end */}
            {mine !== null ? <Pinned>{row(mine, true)}</Pinned> : <Row label={t('rank.notRanked')} tone="muted" hairline={false} />}
            {lines.rows.map((r) => row(r))}
          </ListPanel>
        }
        side={
          <>
            <Card title={t('rank.standing')} data-testid="rank-standing">
              {mine === null ? (
                <Row label={t('rank.notRanked')} tone="muted" hairline={false} />
              ) : (
                <>
                  <div className="grid grid-cols-2 gap-4">
                    <StatCell look="stacked" label={t('rank.place')} value={mine.position} format={formatInt} tone="accent" data-testid="rank-place">
                      <span className="block text-t-caption text-ink-faint">{t('rank.ofN', { of: formatInt(board.houses) })}</span>
                    </StatCell>
                    <StatCell look="stacked" label={t('rank.fame')} value={mine.total_fame} format={formatInt} data-testid="rank-fame" />
                  </div>
                  {/* THE SPLIT, drawn — the bar draws itself only once there is fame to split; before that the two lines say 0 */}
                  {mine.trade_fame + mine.exploration_fame > 0 ? (
                    <StackedBar parts={split} format={formatInt} label={t('rank.fameByKind')} className="mt-5" data-testid="rank-fame-split" />
                  ) : (
                    <div className="mt-3">
                      <StatCell look="line" mark={<Icon name="coin" size={18} aria-hidden="true" />} label={t('rank.trade')} value={mine.trade_fame} format={formatInt} />
                      <StatCell look="line" mark={<Icon name="compass" size={18} aria-hidden="true" />} label={t('rank.exploration')} value={mine.exploration_fame} format={formatInt} />
                    </div>
                  )}
                  {/* the companies' count stands under the place ("of 846"); the ports reached keep their line, with the port's anchor */}
                  <div className="mt-3">
                    <StatCell look="line" mark={<Icon name="anchor" size={18} aria-hidden="true" />} label={t('rank.ports')} value={mine.ports_reached} format={formatInt} />
                  </div>
                </>
              )}
            </Card>
            <Card title={t('rank.leaders')} data-testid="rank-leaders">
              <RankBars rules={false} format={formatInt} empty={t('rank.empty')} rows={leaders} />
            </Card>
          </>
        }
      />

      {open !== null && (
        <Tray
          detent={detent}
          onDetentChange={(next) => (next === 'closed' ? setOpen(null) : setDetent(next))}
          title={open.name}
          data-testid="fame-tray"
        >
          <Row label={t('rank.place')} value={<Figure value={formatInt(open.position)} tone={open.mine ? 'accent' : 'ink'} />}>
            {open.tied && <span className="block text-t-caption text-ink-faint">{t('rank.tied')}</span>}
          </Row>
          {open.nation !== null && <Row label={t('codex.country')} value={<HullCountry nation={open.nation} />} />}
          <Row label={t('rank.trade')} value={<Figure value={formatInt(open.trade_fame)} />} />
          <Row label={t('rank.exploration')} value={<Figure value={formatInt(open.exploration_fame)} />} />
          <Row label={t('rank.ports')} value={<Figure value={formatInt(open.ports_reached)} />} />
          {open.mayor_of.length > 0 && <Row label={t('rank.mayorOf', { cities: open.mayor_of.join(', ') })} />}
          <Row label={t('rank.total')} value={<Figure value={formatInt(open.total_fame)} tone="accent" />} hairline={false} />
        </Tray>
      )}
    </>
  )
}
