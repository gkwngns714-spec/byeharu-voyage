import { Bar, Card, Clip, Facts, Figure, Icon, ListPanel, PageSplit, Row, Sheet, StatCell } from '../../components/ui'
import { formatInt } from '../../lib/format'
import type { FleetView, LevelTrack, PlayerHouse } from '../../lib/rpc'
import { useWorld } from '../../live/worldStore'
import { WorldFailed, WorldLoading } from '../../live/WorldGate'
import { CaptainRows, CaptainTray } from '../../live/YourCaptains'
import { useYourCaptains } from '../../live/useYourCaptains'
import { tabWord } from '../../app/navTabs'
import { useLocale, useT } from '../../lib/i18n'
import { Link } from 'react-router-dom'
import { companyRoom, useHouseRoom } from '../../live/houseRoom'

// YOU — the owner, row 181 (2026-10-20): *"Create a tab for personal info, such as my level, my
// ships, captains, achievements, levels etc."*
//
// THREE SECTIONS, AND EVERY ONE OF THEM ALREADY EXISTED SOMEWHERE ELSE. Nothing here is read that
// was not read before and nothing is computed: the world read brings the house (with its three
// level tracks) and the fleets (with their hulls), and the captains are the ONE captains face
// (src/live/YourCaptains.tsx, `world.captains`). This tab is composition, which is why it sits in
// the Cabin: it consults, and it commands nothing (navTabs.ts says what that group is for).
//
//   Levels         the three tracks, as Bars. MOVED HERE FROM PROFILE, not copied: §6 put them
//                  there because there was no personal tab, and the owner has now asked for one by
//                  name. Two screens drawing one ladder is two answers to "what level am I".
//   Your ships     EVERY hull you own, in one list, with the fleet she sails in. FLEETS lists
//                  FLEETS — where each one is, her stores, her hold, her hull — and a hull inside
//                  it sits behind a fold, so "what do I own" had no page. This is that page: a
//                  different reading of rows already served, not a second copy of FLEETS'.
//   Your captains  the roster, MOVED from FLEETS for the reason the levels moved — the owner names
//                  captains as personal info, and one list belongs in one place.
//
// ACHIEVEMENTS ARE NOT HERE, and that is deliberate (decided by default, 2026-10-20): there are no
// achievements in this game yet — no table, no read, nothing to count. ProfileScreen's own header
// records what happened the last time a screen printed a feature that did not exist ("`Not in the
// game yet` (three bullets of unbuilt features) → deleted. A roadmap is this repository's, not the
// player's"), so this tab says nothing about them. The day they exist, they are a section here.
//
// ── ON THE GLASS (the sheets-grow slice, 2026-11-02; docs/dev-log/2026-11-02-sheets-grow.md) ───────
// The three sections stood one under the other on a `Sheet`, so a veteran with eight hulls and a few captains scrolled the PAGE
// (476 px at 390×844, 1,050 at 320×640) and a company of two left a quarter of the glass empty. The unfold laws (docs/dev-log/
// 2026-11-01-ui-unfold.md, U2) say what a screen with a list does: its FIGURES on top, the list in ONE `ListPanel` that takes
// the glass they leave and scrolls INSIDE itself. So: the levels are the figures — a strip of two tracks side by side, the way
// the Stats faces stand their figures over their panel — and Ships and Captains are the two sections of the panel's body (from
// `lg` side by side, the same blocks with more room). Nothing is dropped: every figure, every row and every test id the old
// screen drew is on this one, and the captain's tray is a sibling of the panel, never inside its scroller.

export function YouScreen() {
  // THE TITLE IS THE TAB'S OWN WORD (navTabs.tabWord) — one authority with the lit nav cell.
  const title = tabWord(useLocale(), '/you')
  // FIELDS, NOT THE STORE (worldStore.ts rule 4).
  const phase = useWorld((s) => s.phase)
  const fatal = useWorld((s) => s.fatal)
  if (phase === 'failed') return <WorldFailed title={title} refusal={fatal} />
  if (phase !== 'ready') return <WorldLoading title={title} />
  return <YouBody title={title} />
}

function YouBody({ title }: { title: string }) {
  const t = useT()
  const player = useWorld((s) => s.player)
  const fleets = useWorld((s) => s.fleets)
  // 0160: the one captains face — her grade, the traits she uses, the cabin she sits in. ONE read and ONE open captain; her rows
  // stand in the panel below and her tray beside it.
  const face = useYourCaptains()

  return (
    // THE PAGE (2026-11-05, owner row 267): MAIN the ships and the captains as two card lists, SIDE (the tray's column) the levels. The page
    // scrolls; nothing inside it does. On a phone the side stands AFTER the lists, so the first ship is on the first glass.
    <Sheet title={title} layout="page" data-testid="you">
      <PageSplit
        data-testid="you-page"
        stickySide
        main={
          <>
            <RoomLine />
            <Ships fleets={fleets} />
            <ListPanel
              look="card"
              columns="fit"
              title={t('books.captains')}
              count={face.captains.length === 0 ? undefined : <span data-testid="your-captains-count">{formatInt(face.captains.length)}</span>}
              data-testid="your-captains"
            >
              <CaptainRows face={face} />
            </ListPanel>
          </>
        }
        side={
          player === null ? (
            <Card data-testid="levels">
              <Row label={t('you.noCompany')} tone="muted" hairline={false} data-testid="you-no-company" />
            </Card>
          ) : (
            <>
              <Reputation player={player} />
              <Levels player={player} />
            </>
          )
        }
      />
      <CaptainTray face={face} />
    </Sheet>
  )
}

/** THE ROOM THE COMPANY HAS, ONE LINE (F5, 2026-11-11; docs/FLEETS_AND_SLOTS.md 2.7): fleets she has of the fleets she may have, ships of the ships she may have, as
 *  `world.house_room` serves them (the caps the server enforces now, lit or dark). The line is the link to Fleets, where the room is used and opened. */
function RoomLine() {
  const t = useT()
  const room = companyRoom(useHouseRoom())
  if (!room) return null
  return (
    <Link to="/fleets" className="mb-4 flex min-h-11 flex-wrap items-center gap-x-2 rounded-control text-t-body text-ink hover:text-accent" data-testid="you-room">
      <span className="tabular-nums">
        {t('you.room', {
          a: formatInt(room.fleets.used),
          b: formatInt(room.fleets.have),
          c: formatInt(room.hulls.used),
          d: formatInt(room.hulls.have),
        })}
      </span>
      <Icon name="chevron" size={16} className="text-ink-muted" />
    </Link>
  )
}

/** REPUTATION (0352, owner row 317): the served balance, and what today's capped earnings stand at against the day's cap
 *  (`public.reputation_card`). Nothing is computed here. A server before 0352 serves none, and the card is not drawn. */
function Reputation({ player }: { player: PlayerHouse }) {
  const t = useT()
  const rep = player.reputation
  if (!rep) return null
  return (
    <Card title={t('shell.reputation')} data-testid="you-reputation">
      <span data-testid="you-reputation-balance" data-value={rep.balance}>
        <Figure value={formatInt(rep.balance)} size="figure" />
      </span>
      <p className="mt-1 text-t-caption text-ink-muted" data-testid="you-reputation-today">
        {t('shell.repToday', { a: formatInt(rep.today), b: formatInt(rep.cap) })}
      </p>
    </Card>
  )
}

/** THE THREE TRACKS (0069), as Bars — the hand-off this tab took from Profile. They are the screen's FIGURES: one heading line and
 *  the tracks side by side under it, standing on the glass over the list panel (a Stats face's figure block, StatsBlock.tsx, is the
 *  same shape). COMBAT IS NOT A TRACK until the server says so: 0069 serves it with `playable: false` on purpose — there is no
 *  fighting at sea in this game yet (0035) — and a bar at level 1 of an unbuilt track would make it look built. The server's flag
 *  decides: the day it flips, the third bar joins the grid with no edit here. Until then the heading line says what it waits on. */
function Levels({ player }: { player: PlayerHouse }) {
  const t = useT()
  const { trading, exploration, combat } = player.levels
  return (
    <Card title={t('you.levels')} data-testid="levels">
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-1">
        <Track name={t('you.trading')} track={trading} />
        <Track name={t('you.exploration')} track={exploration} />
        {combat.playable && <Track name={t('you.combat')} track={combat} />}
      </div>
      {!combat.playable && (
        <p className="mt-4 text-t-caption text-ink-faint" data-testid="combat-waits">
          {t('you.combat')} · {t('you.noFighting')}
        </p>
      )}
    </Card>
  )
}

/** The cap of the ONE level curve, `public.level_from_points` (0069:111): floored at 1, capped at
 *  20. Mirrored here for DISPLAY ONLY, the way `TIME_COMPRESSION` mirrors a served knob in
 *  src/lib/format/time.ts — the server does not serve the cap, and a bar needs an end. When
 *  `world.snapshot().config` carries it, this constant goes and the bar reads the served value. */
const LEVEL_CAP = 20

/** One level track as §6 draws it: the name and the level hugging it, the bar of the ladder under them. A countable Bar (`of`)
 *  rather than a percentage: a level is a rung, not a proportion. */
function Track({ name, track }: { name: string; track: LevelTrack }) {
  const t = useT()
  return (
    <div className="min-w-0" data-testid="level-track">
      <StatCell look="stacked" label={name} value={track.level} format={formatInt} />
      <Bar value={track.level} of={LEVEL_CAP} label={t('you.levelOf', { name })} className="mt-1" />
    </div>
  )
}

/** EVERY HULL YOU OWN, with the fleet she sails in. The served rows, flattened — a flagship says
 *  so, because she is the one hull this game promises never to lose (DESIGN §C.6). The first section of the panel's body. */
function Ships({ fleets }: { fleets: readonly FleetView[] }) {
  const t = useT()
  const ships = fleets.flatMap((fleet) => fleet.ships.map((ship) => ({ ship, fleet })))
  return (
    <ListPanel
      look="card"
      columns="fit"
      title={t('you.ships')}
      count={
        ships.length === 0 ? undefined : (
          <span data-testid="you-ships-count">
            {t('you.shipsCount', {
              ships: formatInt(ships.length),
              fleets: formatInt(fleets.length),
              count: fleets.length,
            })}
          </span>
        )
      }
      data-testid="you-ships"
    >
      {ships.length === 0 ? (
        <Row label={t('you.noShips')} tone="muted" hairline={false} data-testid="you-no-ships" />
      ) : (
        ships.map(({ ship, fleet }, i) => (
          <Row
            key={ship.id}
            label={<Clip>{ship.name}</Clip>}
            // IN A NARROW ROW HER FLEET GOES UNDER HER NAME (owner, 2026-11-12): beside a 24-letter fleet name the ship's own name
            // stood on three lines ("Nossa / Senhora da / Estrela") in a 320-px card, and on two at 390. The row is its own query
            // container (ListPanel `columns="fit"`), so the row's width decides, never the window's.
            value={<span className="text-t-caption text-ink-muted pair:hidden">{fleet.name}</span>}
            hairline={i < ships.length - 1}
            data-testid="you-ship"
          >
            <Facts className="block text-t-caption text-ink-faint pair:hidden" items={[ship.class, ship.is_flagship ? t('you.flagship') : null]} />
            <Facts className="hidden text-t-caption text-ink-faint pair:block" items={[fleet.name, ship.class, ship.is_flagship ? t('you.flagship') : null]} />
          </Row>
        ))
      )}
    </ListPanel>
  )
}
