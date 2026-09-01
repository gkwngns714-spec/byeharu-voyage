import { useEffect, useState } from 'react'
import {
  Badge,
  Card,
  CardHeader,
  EmptyState,
  Gauge,
  Notice,
  PageHeader,
  Screen,
  Skeleton,
  StatRow,
  TD,
  TH,
  Table,
  fineClass,
  scrollTableClass,
} from '../../components/ui'
import { formatDucats, formatInt, formatRealShort, formatRelative } from '../../lib/format'
import type { StandingsBoard } from '../../lib/rpc'
import { nationNameOf, useWorld } from '../../live/worldStore'
import { WorldFailed, WorldLoading } from '../../live/WorldGate'

// RANK — I.4: "the Ledger is not a UI convenience — it is the source of truth from which rank is
// computed." That sentence is the whole design of this screen, and as of 0025 the whole of it is
// drawn: `world.standings()` is the one place another house's figures cross the wire, and it
// serves a name, a nation, a standing and the fames the standing is computed from.
//
// DELETED WITH THE MIGRATION THAT ANSWERED THEM (NO_SPAGHETTI §5, "delete, don't adapt"): the
// "WHAT IS MISSING, PRECISELY" note, the four-bullet backlog headed "what a standing needs first",
// and the card that told the player no table of captains existed. The first two bullets — no
// players table a client may read, no settled standing — were answered outright by 0025; the other
// two named things 0025 REFUSED on purpose, with its reasons, which is not a backlog. A comment
// arguing with the code beneath it is worse than no comment at all.
//
// ── LIVE SELF, SETTLED FIELD, AND WHY BOTH ARE ON ONE SCREEN ───────────────────────────────────
// Two clocks run here and the screen must never blur them:
//
//   the House and Fame cards   `world.player()` — DERIVED on every call (0014), so they are true
//                              at the instant you read them.
//   the board                  `public.standings` — a PHOTOGRAPH taken once per slot, recording
//                              what `player_fame()` said then.
//
// So the board's own header prints how old the photograph is, in the player's words, rather than
// implying a figure that moves while it is read. Nothing here reconciles the two: a settled figure
// that disagrees with a live one is the board being a board, not a defect.
//
// ── FAME IS THE SERVER'S, AND THE CLIENT COUNTS NOTHING ────────────────────────────────────────
// This screen used to count voyages and turnover out of ONE PAGE of `world.events` and had to
// print how many entries it had looked at. 0014 made fame a server-side reading of the WHOLE
// record; 0025 records what that reading said. The client adds up nothing, ranks nothing and
// compares nothing — a standing computed on this side of the wire would be a second authority for
// a figure the ledger already owns.
//
// ── WHAT THE BOARD DELIBERATELY DOES NOT SAY ───────────────────────────────────────────────────
// No purse, no cargo, no fleet, no port, no ledger line, and no season. Every one of those refusals
// has its reason written where the decision was taken, in 0025's header, and is NOT restated here:
// a privacy rule with two statements of itself is a rule that can drift.

export function RankScreen() {
  // FIELDS, NOT THE STORE (worldStore.ts rule 4).
  const phase = useWorld((s) => s.phase)
  const fatal = useWorld((s) => s.fatal)

  if (phase === 'failed') {
    return <WorldFailed eyebrow="Standings" title="Rank" refusal={fatal} />
  }
  if (phase !== 'ready') {
    return (
      <WorldLoading
        eyebrow="Standings"
        title="Rank"
        subtitle="Where you stand among the captains."
        panels={3}
      />
    )
  }
  return <RankBody />
}

function RankBody() {
  // The snapshot, not `snapshot?.config` — a selector must return something stable, and reaching
  // one level deeper is free here because the snapshot object is replaced only when the world is
  // reopened (worldStore.ts rule 4, 'the one thing to watch').
  const snapshot = useWorld((s) => s.snapshot)
  const ducats = useWorld((s) => s.ducats)
  const house = useWorld((s) => s.player)
  const board = useWorld((s) => s.standings)
  const loadStandings = useWorld((s) => s.loadStandings)
  const readAt = useWorld((s) => s.readAt)
  const config = snapshot?.config

  // WHETHER THE BOARD HAS ANSWERED, which `standings === null` alone cannot say: null is both "not
  // asked yet" and "the read was refused". Without this the failed case draws a skeleton for ever,
  // which is the shape of a screen that is lying about being busy.
  const [answered, setAnswered] = useState(false)

  // KEYED ON `readAt`: the `read again` button is deleted (the owner: "read again on top left of
  // the game is useless. remove it") — the world re-reads itself every thirty seconds and on tab
  // focus, and the board rides that same beat, so a refused board read is retried with no button
  // and a new slot's photograph appears on its own. A repeat inside one slot costs two index
  // lookups, because 0025 settles at most once per slot.
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

  // SERVED, not folded — `world.player()` counts them (migration 0014:140-141). FleetsScreen was
  // folding the roster for the same two figures; both read the house now.
  const shipCount = house?.ships ?? null
  const fleetCount = house?.fleets ?? null
  const fame = house?.fame ?? null
  const levels = house?.levels ?? null

  return (
    <Screen>
      <PageHeader
        eyebrow="Standings"
        title="Rank"
        explain="Your own record, worked out fresh from your ledger every time you look. The table of captains beneath it is settled on a timer and says how old it is."
      />

      <TableOfCaptains board={board} answered={answered} houseName={house?.company_name ?? null} houseNation={house?.nation ?? null} />

      <Card
        head={
          <CardHeader
            flush
            title={house?.company_name ?? 'The house'}
            aside={
              house?.nation ? <Badge tone="neutral">{house.nation_name ?? house.nation}</Badge> : null
            }
          />
        }
      >
        <dl className="space-y-2">
          <StatRow
            label="Purse"
            value={ducats === null ? '—' : formatDucats(ducats)}
            hint="The game's own figure, checked against your ledger every time it is read."
          />
          <StatRow
            label="Fleets"
            value={`${fleetCount === null ? '—' : formatInt(fleetCount)} / ${config ? formatInt(config.fleet_max) : '—'}`}
            /* `fleet_max` was named here by its config key — provenance for a developer, and to a
               captain a word from nowhere. What they need is what the second figure MEANS. */
            hint="The second figure is the same for every house. It is a limit, not a rank, and nothing you do raises it."
          />
          <StatRow
            label="Ships"
            value={`${shipCount === null ? '—' : formatInt(shipCount)} / ${config ? formatInt(config.ship_max) : '—'}`}
          />
        </dl>

        {/* The gauge needs a COUNT; an unread house has none, and drawing a zero-length gauge
            would be inventing one. It simply does not draw. */}
        {config && shipCount !== null && (
          <div className="mt-3 flex items-center gap-3">
            <Gauge
              value={shipCount}
              max={config.ship_max}
              segments={config.ship_max}
              tone={shipCount >= config.ship_max ? 'warning' : 'accent'}
              label={`${shipCount} of ${config.ship_max} ships`}
            />
            <span className={fineClass()}>
              {shipCount >= config.ship_max ? 'every berth taken' : 'hulls the house may still own'}
            </span>
          </div>
        )}
      </Card>

      {/* THE PROVENANCE MOVED BEHIND THE DOT. "Counted from your whole ledger every time you open
          this screen — never a running total kept aside…" is a standing rule about how the figures
          are made, which is the exact thing docs/UI_DIRECTION.md §4 rule 4 folds. It was a printed
          paragraph sitting between the card's title and the five numbers it introduces.

          THIS CARD IS THE ONE PLACE FAME IS EXPLAINED. The board above prints the same three
          figures for every house and deliberately does NOT re-explain them: two spellings of "what
          is trade fame" is two authorities for the rule, and the shorter one always drifts. */}
      <Card
        head={
          <CardHeader
            flush
            title="Fame"
            explain="Counted from your whole ledger every time you open this screen — never a running total kept aside, so it cannot drift from what you actually did."
          />
        }
      >
        <dl className="space-y-2">
          <StatRow
            label="Trade fame"
            value={fame ? formatInt(fame.trade) : '—'}
            hint="One point per 100 ducats TURNED OVER on a buy or a sale. Turnover, not profit — the profit is already the purse, and scoring it twice would count one thing twice."
          />
          <StatRow
            label="Exploration fame"
            value={fame ? formatInt(fame.exploration) : '—'}
            hint="25 for each DISTINCT port you have arrived at, and one more for every 100 sea miles sailed. A port is reached once, so a route you have worn smooth stops paying for the landfall and keeps paying for the distance."
          />
          <StatRow label="Total" value={fame ? formatInt(fame.total) : '—'} />
          <StatRow label="Ports reached" value={fame ? formatInt(fame.ports_reached) : '—'} />
          <StatRow label="Turned over" value={fame ? formatDucats(fame.turnover) : '—'} />
        </dl>
      </Card>

      {/* ── THE THREE TRACKS (0069) ────────────────────────────────────────────────────────────
          The owner: *"levels - the game will have 3 kinds of levels - exploration, trading,
          combat"*.

          Fame above and levels here are the SAME count — since 0069 `player_fame` is a view of
          `player_progress` rather than a second reading of the ledger — so the two cards can never
          disagree. What a level adds is a THRESHOLD: captain promotion is what will require one.

          Combat prints its honest zero and the reason. A blank would read as "not loaded", and a
          proxy — hazards survived, say — would make an unbuilt track look built. */}
      <Card
        head={
          <CardHeader
            flush
            title="Levels"
            explain="What playing has earned, in three tracks. Recomputed from your record every time, so nothing here can be inflated and nothing was lost before it was counted."
          />
        }
      >
        <dl className="space-y-2">
          <StatRow
            label="Trading"
            value={levels ? `Level ${formatInt(levels.trading.level)}` : '—'}
            hint={
              levels
                ? `${formatInt(levels.trading.points)} points, from ${formatDucats(levels.trading.turnover)} turned over.`
                : undefined
            }
          />
          <StatRow
            label="Exploration"
            value={levels ? `Level ${formatInt(levels.exploration.level)}` : '—'}
            hint={
              levels
                ? `${formatInt(levels.exploration.points)} points, from ${formatInt(levels.exploration.ports_reached)} port(s) reached and ${formatInt(levels.exploration.nm_sailed)} nm sailed.`
                : undefined
            }
          />
          <StatRow
            label="Combat"
            value={levels ? `Level ${formatInt(levels.combat.level)}` : '—'}
            hint="There is no combat in this game yet, so this track honestly reads nothing. It is here because it is one of the three, not because it is waiting to be found."
          />
        </dl>
      </Card>
    </Screen>
  )
}

/**
 * THE TABLE OF CAPTAINS (0025).
 *
 * Four states, and three of them are STATES rather than faults — the distinction 0014 set and 0025
 * kept, because a screen that renders every absence as a failure teaches the player to distrust it:
 *
 *   not answered yet   a skeleton, and only until the read lands
 *   answered, no board the read was refused — say so, do not draw an empty table
 *   houses = 0         an empty world, carrying the server's OWN `why`
 *   you = null         signed in, no house: the board is real and no line on it is yours
 */
function TableOfCaptains({
  board,
  answered,
  houseName,
  houseNation,
}: {
  board: StandingsBoard | null
  answered: boolean
  /** YOUR name and flag, which the payload's `you` deliberately omits — you already have them, and
   *  sending them back would be a second copy of a fact `world.player()` owns. */
  houseName: string | null
  houseNation: string | null
}) {
  if (!board) {
    return (
      <Card head={<CardHeader flush title="The table of captains" />}>
        {answered ? (
          <Notice tone="warning">
            The board could not be read just now. Nothing about your own record above depends on it
            — it will be tried again in a moment.
          </Notice>
        ) : (
          <div className="space-y-2">
            <Skeleton className="h-6 w-full" />
            <Skeleton className="h-6 w-full" />
            <Skeleton className="h-6 w-2/3" />
          </div>
        )}
      </Card>
    )
  }

  // AN EMPTY WORLD IS A STATE WITH ITS REASON ATTACHED, and the reason is the server's sentence,
  // not one written here: `why` exists precisely so this screen never has to guess why the board is
  // short. The fallback below can only be reached if the payload breaks its own contract, and it
  // says that rather than dressing a fault as a state.
  if (board.board.length === 0) {
    return (
      <EmptyState
        title="The table of captains"
        body={
          board.why ??
          'The board came back empty with no reason given. That is a fault, not a quiet world.'
        }
      />
    )
  }

  // HOW OLD THE PHOTOGRAPH IS, MEASURED BY THE SERVER AND NOT BY THIS BROWSER. `formatRelative`
  // reads only the GAP between its two instants, so handing it (−age, 0) asks it exactly what
  // `age_seconds` already measured. Rebuilding a wall-clock instant against `Date.now()` would
  // have let a skewed device clock decide how stale a server's record is, and would have made the
  // line re-render into a different answer on every pass.
  const settled =
    board.age_seconds === null ? null : formatRelative(-board.age_seconds * 1000, 0)
  const you = board.you

  return (
    <Card
      head={
        <CardHeader
          flush
          title="The table of captains"
          /* PRINTED, because it is live: how old the photograph is decides how much of it to
             believe, and a player must never have to ask for that. */
          subtitle={settled === null ? undefined : `Settled ${settled}`}
          explain={`Everyone here is ranked on fame alone, and this is a photograph rather than a live count — a new one is taken every ${formatRealShort(board.slot_seconds * 1000)}. Two houses level are BOTH given the same place and the next captain takes the one after both of them, so a jump in the numbering is the tie showing, not a gap.`}
          aside={
            // "1 HOUSES" is the shape this screen already deleted once — the ungrammatical "0 of
            // the 1 entries" that used to close it. The figure is the server's; the noun is this
            // screen's, so this screen makes the noun agree with it.
            <Badge tone="neutral">
              {formatInt(board.houses)} {board.houses === 1 ? 'house' : 'houses'}
            </Badge>
          }
        />
      }
    >
      <Table scrollHint className={scrollTableClass()}>
        <thead>
          <tr>
            {/* THE PLACE RIDES IN THE HOUSE CELL, and that is the whole reason this table reads at
                390px. `scrollTableClass` pins the FIRST column so a row's identity can never be
                scrolled out of reach — and on a leaderboard the identity is the captain, not the
                two characters in front of her. A `#` column of its own would have pinned the one
                cell nobody needs to keep looking at and let the names slide away.

                FAME IS SECOND for MARKET's %NBR reason: the second column is the last one certain
                to be on screen without scrolling, and total fame is the figure the whole board is
                sorted by. The two fames it is made of, and the ports, follow it. */}
            <TH>House</TH>
            <TH align="num">Fame</TH>
            <TH align="num">Trade</TH>
            <TH align="num">Exploration</TH>
            <TH align="num">Ports</TH>
          </tr>
        </thead>
        <tbody>
          {board.board.map((row) => (
            <StandingLine
              key={`${row.position}-${row.company_name}`}
              position={row.position}
              tied={row.tied}
              name={row.company_name}
              nation={row.nation}
              tradeFame={row.trade_fame}
              explorationFame={row.exploration_fame}
              totalFame={row.total_fame}
              portsReached={row.ports_reached}
              mine={row.is_you}
            />
          ))}

          {/* OFF THE END OF THE BOARD, AND STILL ON IT. A ten-row board says nothing at all to the
              hundredth captain unless her own line is carried beside it, which is exactly why 0025
              serves `you` whether or not she placed. It is drawn by the SAME component as every
              other line — a second row renderer for one row would be the copy that drifts — with
              the name and flag composed from the house, because the payload leaves them out. */}
          {you && !you.on_board && (
            <>
              <tr>
                <td colSpan={5} className="border-b border-edge/50 px-2 pt-4 text-xs text-ink-muted">
                  The board shows the top {formatInt(board.board_size)}. You are below it:
                </td>
              </tr>
              <StandingLine
                position={you.position}
                tied={you.tied}
                name={houseName ?? 'Your house'}
                nation={houseNation}
                tradeFame={you.trade_fame}
                explorationFame={you.exploration_fame}
                totalFame={you.total_fame}
                portsReached={you.ports_reached}
                mine
              />
            </>
          )}
        </tbody>
      </Table>

      {/* A REAL WORLD REACHES THIS: signed in, book unsigned. The board is not broken and is not
          empty — it simply has no line of yours on it yet, and saying so is the difference between
          a state and a screen that looks like it failed. */}
      {you === null && (
        <Notice tone="neutral" className="mt-3 text-xs">
          No line here is yours yet — a house takes its place on the board once it has been founded.
        </Notice>
      )}
    </Card>
  )
}

/** ONE LINE OF THE BOARD, wherever it is drawn: in place, or carried below the cut for a captain
 *  who did not make the top of it. */
function StandingLine({
  position,
  tied,
  name,
  nation,
  tradeFame,
  explorationFame,
  totalFame,
  portsReached,
  mine,
}: {
  position: number
  tied: boolean
  name: string
  nation: string | null
  tradeFame: number
  explorationFame: number
  totalFame: number
  portsReached: number
  mine: boolean
}) {
  // Selected HERE rather than threaded down from the board, because the catalogue is a world
  // fact and every screen that names a nation will want the same one. A bare `useWorld()` with no
  // selector is banned — it re-renders on every read, and reading is how time passes in this game.
  const nationByCode = useWorld((s) => s.nationByCode)
  return (
    <tr>
      {/* THE ACCENT RULE IS ON THE CELL, NOT THE ROW. This first cell is the sticky one, and
          `scrollTableClass` paints its background so the scrolling columns cannot show through —
          which means a tinted <tr> would be invisible under exactly the cell that carries the
          name. A left rule and the colour of the name itself survive the pinning. */}
      <TD className={mine ? 'border-l-2 border-l-accent' : ''}>
        <span className="flex items-baseline gap-2">
          {/* `=1` is the tie, said in two characters: 0025 ranks by competition, so two houses
              level are both first and nobody is placed above an equal. The mark is on every tied
              row, which is what stops the missing number after them reading as a bug. */}
          <span className="w-7 shrink-0 text-right font-mono tabular-nums text-ink-faint">
            {tied ? '=' : ''}
            {position}
          </span>
          <span className={mine ? 'font-semibold text-accent' : 'text-ink'}>{name}</span>
          {/* THE NAME, NOT THE CODE. This row printed a bare `PRT` on the day the board shipped,
              on the one screen whose job is telling houses apart, because `world.standings` serves
              a nation the way the server stores it. The lookup table did NOT get written here —
              0028 serves `snapshot.nations` and `nationNameOf` is the one reading of it, beside
              `portNameOf`, which exists because its port-shaped twin got hand-written seven times
              before anybody counted. A code still shows if the catalogue does not know one: a code
              is at least true, where "unknown" beside a real house would hide the defect. */}
          {nation && <span className={fineClass()}>{nationNameOf(nationByCode, nation)}</span>}
          {mine && <Badge tone="accent">you</Badge>}
        </span>
      </TD>
      <TD align="num" className={mine ? 'text-accent' : ''}>
        {formatInt(totalFame)}
      </TD>
      <TD align="num">{formatInt(tradeFame)}</TD>
      <TD align="num">{formatInt(explorationFame)}</TD>
      <TD align="num">{formatInt(portsReached)}</TD>
    </tr>
  )
}
