import { useEffect, useState } from 'react'
import {
  Figure,
  Hint,
  Note,
  Row,
  Sheet,
  SheetSection,
  Skeleton,
  Tray,
  type TrayDetent,
} from '../../components/ui'
import { formatInt, formatRelative } from '../../lib/format'
import type { PlayerHouse, StandingsBoard } from '../../lib/rpc'
import { nationNameOf, useWorld } from '../../live/worldStore'
import { WorldFailed, WorldLoading } from '../../live/WorldGate'

// RANK — one list, and you are pinned to the top of it. docs/UI_DIRECTION.md §6 "RANK".
//
// ── WHAT THIS SCREEN WAS, AND WHY THREE-QUARTERS OF IT WENT ────────────────────────────────────
// §2 item 17, measured at 390px: a five-column table that sheared at `TRA…` with "Swipe the table
// for the rest." under it, then FOUR cards — the house (a purse the status strip already prints,
// and fleet/ship LIMITS with a gauge captioned "hulls the house may still own"), a five-way split
// of fame, and three level tracks of which one printed `Combat — Level 0` beside a sentence
// admitting there is no combat in the game. 1,237px, and eleven ⓘ dots. The board row already
// carries the fame; a limit is not a rank; a track that admits it is empty is not on this screen.
// The levels belong on PROFILE as bars (§6), and the house's own line is the one place its fame is
// broken down — in a tray, when it is asked for.
//
// ── THE TABLE IS ROWS ──────────────────────────────────────────────────────────────────────────
// Five columns were four facts, and four facts fit in a row: the place, the house and its flag,
// and the fame the board is sorted by. The two fames the total is made of, and the ports, are in
// the tray on YOUR row — for another house they were never a decision. With that the last reason
// for `Table/TH/TD`, `scrollTableClass` and `useClipped` on this screen is gone.
//
// ── ONE CLOCK ──────────────────────────────────────────────────────────────────────────────────
// Everything on this screen is the PHOTOGRAPH `public.standings` took (0025), and the title's
// trailing line says how old it is, measured by the server (`age_seconds`), never by this
// browser's clock. The old screen printed live figures from `world.player()` beside settled ones
// and had to explain why they disagreed; there is nothing live here now, so there is nothing to
// explain. Your own live record is PROFILE's.
//
// What the board deliberately does not carry — no purse, no cargo, no fleet, no port — has its
// reason in 0025's header and is not restated here.

export function RankScreen() {
  // FIELDS, NOT THE STORE (worldStore.ts rule 4).
  const phase = useWorld((s) => s.phase)
  const fatal = useWorld((s) => s.fatal)

  if (phase === 'failed') {
    return <WorldFailed eyebrow="Standings" title="Rank" refusal={fatal} />
  }
  if (phase !== 'ready') {
    return (
      <WorldLoading eyebrow="Standings" title="Rank" subtitle="Where you stand among the captains." panels={2} />
    )
  }
  return <RankBody />
}

function RankBody() {
  const house = useWorld((s) => s.player)
  const board = useWorld((s) => s.standings)
  const loadStandings = useWorld((s) => s.loadStandings)
  const readAt = useWorld((s) => s.readAt)

  // WHETHER THE BOARD HAS ANSWERED, which `standings === null` alone cannot say: null is both "not
  // asked yet" and "the read was refused", and without the distinction a refused read draws a
  // skeleton for ever.
  const [answered, setAnswered] = useState(false)

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

  return (
    <Sheet
      title="Standings"
      data-testid="rank"
      trailing={
        settled === null ? undefined : (
          <span className="text-t-caption text-ink-faint">{`settled ${settled}`}</span>
        )
      }
    >
      <Board board={board} answered={answered} house={house} />
    </Sheet>
  )
}

/**
 * THE BOARD (0025). Four states, and three of them are STATES rather than faults:
 *   not answered yet    skeleton rows, only until the read lands
 *   answered, no board  the read was refused — say so, do not draw an empty list
 *   houses = 0          an empty world, carrying the server's OWN `why`
 *   you = null          signed in, no house: the board is real and no line on it is yours
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
  const nationByCode = useWorld((s) => s.nationByCode)
  const [detent, setDetent] = useState<TrayDetent>('closed')

  if (!board) {
    return answered ? (
      <Note tone="warning">The board could not be read just now. It will be tried again in a moment.</Note>
    ) : (
      <div className="space-y-2">
        <Skeleton className="h-12 w-full" />
        <Skeleton className="h-12 w-full" />
        <Skeleton className="h-12 w-2/3" />
      </div>
    )
  }
  if (board.board.length === 0) {
    return (
      <Row
        label={board.why ?? 'The board came back empty with no reason given.'}
        tone="muted"
        hairline={false}
      />
    )
  }

  const you = board.you
  const yourName = house?.company_name ?? 'Your house'
  // YOUR LINE IS PINNED, so it is not drawn a second time in the list; a captain below the cut is
  // carried by `you` whether or not she placed, which is why 0025 serves it.
  const others = board.board.filter((r) => !r.is_you)
  const flag = (code: string | null) => (code === null ? null : nationNameOf(nationByCode, code))

  return (
    <>
      {you === null ? (
        <Row label="No line here is yours yet — a house takes its place once it is founded." tone="muted" />
      ) : (
        <>
          <Row
            mark={<Place position={you.position} mine />}
            label={yourName}
            value={<Figure value={formatInt(you.total_fame)} tone="accent" />}
            tone="accent"
            chevron
            onClick={() => setDetent('half')}
            data-testid="rank-you"
          >
            <Standing nation={flag(house?.nation ?? null)} tied={you.tied} />
          </Row>
          {!you.on_board && (
            <Hint className="mt-2">{`The board shows the top ${formatInt(board.board_size)}. You are below it.`}</Hint>
          )}
        </>
      )}

      <SheetSection>
        {others.map((r, i) => (
          <Row
            key={`${r.position}-${r.company_name}`}
            mark={<Place position={r.position} />}
            label={r.company_name}
            value={<Figure value={formatInt(r.total_fame)} />}
            hairline={i < others.length - 1}
          >
            <Standing nation={flag(r.nation)} tied={r.tied} />
          </Row>
        ))}
      </SheetSection>

      {you !== null && (
        <Tray detent={detent} onDetentChange={setDetent} title={yourName} data-testid="fame-tray">
          <Row label="Trade fame" value={<Figure value={formatInt(you.trade_fame)} />} />
          <Row label="Exploration fame" value={<Figure value={formatInt(you.exploration_fame)} />} />
          <Row label="Ports reached" value={<Figure value={formatInt(you.ports_reached)} />} />
          <Row label="Fame" value={<Figure value={formatInt(you.total_fame)} tone="accent" />} hairline={false} />
          <Hint className="mt-2">
            One point per 100 ducats turned over; 25 for each new port, and one per 100 sea miles.
          </Hint>
        </Tray>
      )}
    </>
  )
}

/** The place, as a right-aligned figure so the names line up whatever the number's width. */
function Place({ position, mine = false }: { position: number; mine?: boolean }) {
  return <Figure value={formatInt(position)} tone={mine ? 'accent' : 'faint'} className="w-7 justify-end" />
}

/** The second line of a row: the flag, and whether the place is shared. 0025 ranks by competition,
 *  so two houses level are BOTH second and the next is fourth — "tied" is what stops the missing
 *  number after them reading as a gap. */
function Standing({ nation, tied }: { nation: string | null; tied: boolean }) {
  const text = [nation, tied ? 'tied' : null].filter(Boolean).join(' · ')
  if (text === '') return null
  return <span className="block text-t-caption text-ink-faint">{text}</span>
}
