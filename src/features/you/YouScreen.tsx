import { Card, CardMark, Clip, Icon, ListPanel, MasteryRing, PageSplit, PlateDisc, Ring, Row, Sheet, goodIcon, masteredTone } from '../../components/ui'
import { useMasteryLevels } from '../../live/goodsMastery'
import { formatInt } from '../../lib/format'
import type { PlayerHouse } from '../../lib/rpc'
import { useWorld } from '../../live/worldStore'
import { WorldFailed, WorldLoading } from '../../live/WorldGate'
import { CaptainRows, CaptainTray } from '../../live/YourCaptains'
import { useYourCaptains } from '../../live/useYourCaptains'
import { tabHref, tabWord } from '../../app/navTabs'
import { properName, useLocale, useT } from '../../lib/i18n'
import { Link, useNavigate } from 'react-router-dom'
import type { ReactNode } from 'react'
import { companyRoom, useHouseRoom } from '../../live/houseRoom'
import { YouLevelsDoor } from './Levels'
import { LogbookDoor } from './Logbook'
import { useLevels } from './useLevels'
import { HullCountry } from '../../live/HullCountry'
import { seasOpened } from '../../live/levelWords'

// YOU — the owner, row 181 (2026-10-20): *"Create a tab for personal info, such as my level, my
// ships, captains, achievements, levels etc."*
//
// THREE SECTIONS, AND EVERY ONE OF THEM ALREADY EXISTED SOMEWHERE ELSE. Nothing here is read that
// was not read before and nothing is computed: the world read brings the house (with its three
// level tracks) and the fleets (with their hulls), and the captains are the ONE captains face
// (src/live/YourCaptains.tsx, `world.captains`). This tab is composition, which is why it sits in
// the Cabin: it consults, and it commands nothing (navTabs.ts says what that group is for).
//
//   Levels         MOVED HERE FROM PROFILE, not copied: §6 put them there because there was no personal tab, and
//                  the owner has now asked for one by name. Two screens drawing one ladder is two answers to "what
//                  level am I". 2026-11-16: the Trade desk's Levels face moved here too, for the same reason
//                  (Levels.tsx says how). 2026-11-23 (roadmap slice 10) the levels got a page of their own (`/levels`);
//                  You keeps the title on its plate and a door: every level as a ring.
//   Your ships     NO LIST HERE (2026-11-24, docs/design/simplify-2026-11-24.md S7): the hulls are listed once, on the Fleets tab (her level
//                  stands on her ship row there). This page keeps ONE figure, the room line (fleets and ships of what she may have), which is
//                  also the door to Fleets.
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
// the Stats faces stand their figures over their panel — and the Captains are the panel's body (from
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
  // 0160: the one captains face — her grade, the traits she uses, the cabin she sits in. ONE read and ONE open captain; her rows
  // stand in the panel below and her tray beside it.
  const face = useYourCaptains()

  return (
    // THE PAGE (2026-11-05, owner row 267): MAIN the ships and the captains as two card lists, SIDE (the tray's column) the levels. The page
    // scrolls; nothing inside it does. On a phone the side stands AFTER the lists, so the first ship is on the first glass.
    <Sheet title={title} layout="page" data-testid="you">
      {/* THE HOUSE'S PLATE (visual slice 9): her flag and name, her title and her Reputation as rings, the room line at its foot */}
      {player !== null && <HousePlate player={player} />}
      <PageSplit
        data-testid="you-page"
        stickySide
        main={
          <>
            {player === null && <RoomLine />}
            <ListPanel
              look="card"
              columns="fit"
              icon="crew"
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
            // slice 10: the levels have their own page (`/levels`); You keeps its door, every level as a ring (Levels.tsx).
            // 0478: and the logbook's door (`/logbook`), drawn only while the server serves it on (Logbook.tsx)
            <>
              <YouLevelsDoor />
              <LogbookDoor />
            </>
          )
        }
      />
      <AccountRow />
      <CaptainTray face={face} />
    </Sheet>
  )
}

/** THE ACCOUNT, ONE ROW AT THE PAGE'S FOOT (2026-11-23, the visual overhaul's slice 2, roadmap X4): the Profile left the Menu, and the
 *  language and the sign-in are reached from here. The row reads the language in its own script and opens `/profile` (the Account
 *  page), a real anchor whose plain click routes in place. Its word is the tab table's (`tabWord`), one authority with that page's title. */
function AccountRow() {
  const t = useT()
  const locale = useLocale()
  const navigate = useNavigate()
  return (
    <Card compact data-testid="you-account">
      <Row
        mark={<CardMark icon="cog" />}
        label={tabWord(locale, '/profile')}
        value={<span className="text-t-caption text-ink-muted">{t(locale === 'ko' ? 'common.korean' : 'common.english')}</span>}
        chevron
        hairline={false}
        href={tabHref('/profile')}
        onClick={(e) => {
          e.preventDefault()
          navigate('/profile')
        }}
        data-testid="you-account-row"
      />
    </Card>
  )
}

/** THE ROOM THE COMPANY HAS, ONE LINE (F5, 2026-11-11; docs/FLEETS_AND_SLOTS.md 2.7): fleets she has of the fleets she may have, ships of the ships she may have, as
 *  `world.house_room` serves them (the caps the server enforces now, lit or dark). The line is the link to Fleets, where the room is used and opened. */
function RoomLine({ className = 'mb-4' }: { className?: string }) {
  const t = useT()
  const room = companyRoom(useHouseRoom())
  if (!room) return null
  return (
    <Link to="/fleets" className={`${className} flex min-h-11 flex-wrap items-center gap-x-2 rounded-control text-t-body text-ink hover:text-accent`} data-testid="you-room">
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

/** THE HOUSE'S PLATE (2026-11-23, the visual overhaul's slice 9; RuneScape's and Melvor's character header): the company's flag
 *  on a disc and its name whole, then its two house figures as rings, the title and the Reputation, and the room line at its foot.
 *  Nothing here is read twice: the title is the levels read's (moved from the levels card, which no longer says it), the
 *  Reputation the house read's (moved from its own card), the room `world.house_room`'s. */
function HousePlate({ player }: { player: PlayerHouse }) {
  return (
    <Card className="mb-4" data-testid="you-plate">
      <div className="flex flex-wrap items-center gap-x-6 gap-y-3">
        <div className="flex min-w-0 flex-[1_1_14rem] items-center gap-3">
          {player.nation && (
            <PlateDisc data-testid="you-plate-flag">
              <HullCountry nation={player.nation} compact size="title" />
            </PlateDisc>
          )}
          <div className="flex min-w-0 flex-col gap-1">
            {/* the name whole (names.whole): it wraps, never clips */}
            <h2 className="min-w-0 text-t-card text-ink">
              <Clip data-testid="you-plate-name">{player.company_name}</Clip>
            </h2>
            <Specialty />
          </div>
        </div>
        <div className="grid min-w-0 flex-[1_1_18rem] grid-cols-2 gap-3">
          <HouseTitle />
          <Reputation player={player} />
        </div>
      </div>
      <TitleNext />
      <div className="mt-2 border-t border-edge pt-1">
        <RoomLine className="" />
      </div>
    </Card>
  )
}

/** HER SPECIALTY (0479, roadmap slice 11, goods mastery: "a trader gets a specialty"): her highest good on its ladder, as the good's mark
 *  in its level ring and its name, gold at the top. The served specialty (world.goods_mastery); dark, or before her first sale, nothing. */
function Specialty() {
  const t = useT()
  const levels = useMasteryLevels()
  const goodByCode = useWorld((s) => s.goodByCode)
  const s = levels.specialty
  if (!s) return null
  const name = goodByCode[s.good]?.name ?? s.good
  return (
    <span className="flex min-w-0 items-center gap-1.5" data-testid="you-specialty" data-good={s.good} data-level={s.level}>
      <MasteryRing level={s.level} top={levels.top} size={28} label={t('mastery.ring', { good: name, n: s.level, top: levels.top })}>
        <Icon name={goodIcon(s.good, s.kind)} size={14} className="text-accent" />
      </MasteryRing>
      <span className="min-w-0 break-words text-t-caption">
        <span className="text-ink-muted">{t('mastery.specialty')}</span> <span className={masteredTone(s.level >= levels.top, 'text-ink')}>{name}</span>
      </span>
    </span>
  )
}

/** A house figure: its mark in a ring, and under it the figure and one quiet word, centred. STACKED, not side by side: beside a 44-px
 *  ring a two-line figure's first line sits off the ring's middle (the align law's LINE), and on a 320-px phone half the plate left the
 *  title's name too narrow to stand whole ("Apprentice" broke inside the word). The caller's box is `HOUSE_FIGURE`. */
function RingFigure({
  ring,
  figure,
  word,
}: {
  ring: ReactNode
  figure: ReactNode
  word: ReactNode
}) {
  return (
    <>
      {ring}
      <span className="min-w-0 max-w-full">
        {figure}
        <span className="block break-words text-t-caption text-ink-muted">{word}</span>
      </span>
    </>
  )
}

/** THE TITLE (0215; moved here from the levels card, slice 9): her title's name and level in a ring that fills toward the next
 *  title, by the lower of her Trading and Exploration levels against the level it asks (the served figures; nothing summed). */
/** The box of one house figure: the ring over its words (RingFigure says why). */
const HOUSE_FIGURE = 'flex min-w-0 flex-col items-center gap-1 text-center'

function HouseTitle() {
  const t = useT()
  const v = useLevels().view
  if (!v || !v.company) return <span />
  const name = v.title.name ? properName('title', v.title.name, v.title.name) : t('command.lvTitle')
  const next = v.title.next
  const pct = next ? (Math.min(v.tracks.trading.level, v.tracks.exploration.level) / next.level) * 100 : 100
  return (
    <div className={HOUSE_FIGURE} data-testid="levels-title" data-level={v.title.level}>
      <RingFigure
        ring={
          <Ring pct={pct} size={44} label={`${t('command.lvTitle')} · ${name} · ${t('command.lvLevel', { n: v.title.level })}`}>
            <span className="text-accent">
              <Icon name="coronet" size={22} />
            </span>
          </Ring>
        }
        figure={<span className="block break-words text-t-body font-semibold text-ink">{name}</span>}
        word={t('command.lvLevel', { n: v.title.level })}
      />
    </div>
  )
}

/** The next title, as the title ring's target: its name and the two levels it asks, and what it opens while sea limits are on. */
function TitleNext() {
  const t = useT()
  const locale = useLocale()
  const v = useLevels().view
  if (!v || !v.company) return null
  const next = v.title.next
  return (
    <span className="mt-2 block text-t-caption text-ink-faint" data-testid="levels-title-next">
      {next
        ? t('command.lvTitleNext', {
            name: properName('title', next.name, next.name),
            tracks: t('command.goalTracks', { a: v.tracks.trading.level, b: v.tracks.exploration.level, n: next.level }),
          })
        : t('command.lvTitleTop')}
      {/* what the title opens, only while sea limits are on (2026-11-23, finding 14) */}
      {next && v.title.seas_bite && next.opens.length > 0 && (
        <span className="block text-ink-muted" data-testid="levels-opens">
          {t('command.lvOpens', { what: seasOpened(locale, next.opens) })}
        </span>
      )}
    </span>
  )
}

/** REPUTATION (0352, owner row 317): the served balance, and what today's capped earnings stand at against the day's cap
 *  (`public.reputation_card`), the cap drawn as the ring round the laurel. Nothing is computed here. A server before 0352
 *  serves none, and the figure is not drawn. */
function Reputation({ player }: { player: PlayerHouse }) {
  const t = useT()
  const rep = player.reputation
  if (!rep) return null
  const today = t('shell.repToday', { a: formatInt(rep.today), b: formatInt(rep.cap) })
  return (
    <div className={HOUSE_FIGURE} data-testid="you-reputation">
      <RingFigure
        ring={
          <Ring pct={rep.cap > 0 ? (rep.today / rep.cap) * 100 : 0} size={44} label={`${t('shell.reputation')} · ${today}`} data-testid="you-reputation-ring">
            <span className="text-accent">
              <Icon name="laurel" size={22} />
            </span>
          </Ring>
        }
        figure={
          <span className="flex flex-wrap items-baseline justify-center gap-x-1.5" data-testid="you-reputation-balance" data-value={rep.balance}>
            <span className="text-t-title tabular-nums text-ink">{formatInt(rep.balance)}</span>
            <span className="text-t-caption text-ink-muted">{t('shell.reputation')}</span>
          </span>
        }
        word={<span data-testid="you-reputation-today">{today}</span>}
      />
    </div>
  )
}
