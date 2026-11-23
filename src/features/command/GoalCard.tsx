import { useLayoutEffect, useRef, useState } from 'react'
import { Icon, Ring, useWide } from '../../components/ui'
import { properName, useLocale, useT } from '../../lib/i18n'
import { levelName, nextOpening } from '../../live/levelWords'
import { worldLevels, type LevelsView } from '../../lib/rpc'
import { useServedRead } from '../../live/useServedRead'
import { useSecondShipGoal } from '../../live/useSecondShipGoal'
import { useWorld } from '../../live/worldStore'
import { formatInt } from '../../lib/format'
import { useShellState } from '../../app/shellState'
import { useNavigate } from 'react-router-dom'
import { openOfficeCity } from './officeView'
import { useShowOnMap } from '../../live/showOnMap'

// THE GOAL CARD (remaster S6): one line on the Trade face saying what to aim for: the next Title and how far along you are.
// NOT a quest: it reads the SAME served read the You page's levels read (`world.levels()`, 0325, the same cached `worldLevels` read) and
// prints its figures: the next title (`title.next`), and the two tracks' levels. The rule "a title needs Trading and Exploration at
// the title's level" is the You page's own sentence (command.lvTitleNext); this card shows it as progress and invents no other
// threshold. What the title opens is `title.next.opens`, worded as the You page words it, and only while sea limits are lit. Pressing it opens
// the You page, where the levels are whole (since 2026-11-16, when Levels left the Trade desk for the You page).
//
// 0352: ITS SECOND LINE ALSO CARRIES HER REPUTATION (the served balance, world.player(): the store's own read, no second call). A phone's
// top bar has no room for that figure, and this is the first screen she sees.
//
// 0363 (S3 of docs/SECOND_SHIP.md): WHILE THE COMPANY HAS ONE SHIP, THE SECOND LINE IS THE SECOND SHIP ("Second ship 1 / 4"), IN PLACE OF
// THE TWO TRACKS. One line replaces the other by that one rule; no line is added (the Trade face has no pixel to spare at 390 px,
// tests/trade.flow.spec.ts T3), and the two do not fit one line at 320 px in English. The title's name stays on the first line and the
// tracks are one press away (the card opens Levels, where they are whole); they come back to the card with her second ship. The count is the
// build yard's own "Ready 1 / 4" (live/useSecondShip.ts). While no yard has been read for her the tracks stand as before.
//
// 2026-11-22 (P0, a new player can read the game): the count says what it counts, "Second ship · materials 0 / 4" (the yard's lines
// stored), and the press opens the yard where those materials are stored and the trip to fetch them is planned.
//
// 0468 (P2, each level opens something): WHILE TRADING'S UNLOCKS ARE LIT (the served Trading benefits carry a step: level_unlocks_enabled),
// the card names what her next Trading level opens ("Trading 4: Ships a fleet +1", levelWords.nextOpening over the served list): on the
// first line in place of the far title while the second line is the second ship, else after the two tracks where the seas would stand
// (the seas win when the title opens one). Dark the served list has no Trading step and the card is exactly as before.
//
// 2026-11-23 (third play-test, finding 3): WHILE THE YARD TAKES ORDERS (its served `order` key) AND NO HULL IS ON ORDER, the second line
// is her purse against the Order's price, "Second ship · 46,112 / 52,000", with a thin bar in the rest of that line: the price is the yard's
// own quote (world.hull_quote, the same cached read the yard's sheet asks; 0472 serves the newcomer's floor there). The materials count
// stays the line while ordering is dark. The press opens the yard ON that hull's sheet, where the Order is; away from the yard's city,
// the Map with that city's tray up (finding 21: it opened with nothing chosen).
//
// 2026-11-23 (finding 9): THE UNLOCK NEVER RUNS UNDER THE REPUTATION. Under 390 px it gave way to the title; at 1280 in Korean it still
// ran under "평판 226". Now it stands only where it is measured to fit beside it, at every width, else the title stands; and from `sm`
// up the figure is the top bar's (TopBar.tsx shows Reputation there), so the card's first line is the unlock's.
//
// THE PRESS LAW: a fixed height in every state (loading, shown, nothing to show), so nothing moves when the read lands or on a press.

// A control is 44 px (tests/consistency.spec.ts), so the card is 44 px. It stands on the Trade tab, under the fleet strip (phone) or under the
// header (wide: the header has no room for it at 1024 px).
// THE CARD'S LINES NEVER BREAK (2026-11-12, the owner on a phone: *"long words and sentences making new messy lines"*). It was one
// sentence, "Mate: Trading 1/2, Exploration 1/2", in a 44-px box set a second gutter in from the page's own: at 320 px the sentence
// took two lines and pushed Reputation out of the box. Now the title's name and Reputation share the first line and the two tracks
// are the second, each short enough for a 320-px glass with the longest served title; the box stands on the page's own margin.
// 2026-11-23 (the visual overhaul's slice 3): THE GOAL IS A RING. A 30-px ring at the card's head, filled by the goal's own figures (her
// purse against the Order's price; else the materials stored; else the lower track against the next title's level), around the goal's
// mark (a ship for the second ship, the coronet for a title). It stands in the card's own 44 px; the thin bar the saving line drew went
// into it, so the words are not longer than they were.
const CARD = 'grid min-h-11 min-w-0 shrink-0 grid-cols-[auto_minmax(0,1fr)_auto] content-center items-baseline gap-x-2.5 rounded-control px-3 text-left'
const PHONE = 'mb-1'
const WIDE = 'mx-3 mb-2 w-[22rem] min-[90rem]:mx-6'

export function GoalCard() {
  const t = useT()
  const locale = useLocale()
  const wide = useWide()
  const place = wide ? WIDE : PHONE
  const navigate = useNavigate()
  const showOnMap = useShowOnMap()
  const read = useServedRead<LevelsView>('levels', () => worldLevels(), { name: 'worldLevels' })
  const v = read.view
  const reputation = useWorld((s) => s.player?.reputation?.balance ?? null)
  const { nowMs } = useShellState()
  // the second ship as a goal: its line, and her purse against the Order's price while the yard takes orders (the one reading the
  // welcome card's ring also draws, live/useSecondShipGoal.ts)
  const goal = useSecondShipGoal(nowMs)
  const second = goal?.second ?? null
  const saving = goal?.saving ?? null
  // the unlock stands only where it fits beside the reputation (measured, at every width)
  const titleBox = useRef<HTMLSpanElement>(null)
  const unlockGhost = useRef<HTMLSpanElement>(null)
  const [fits, setFits] = useState(true)
  useLayoutEffect(() => {
    const box = titleBox.current
    const ghost = unlockGhost.current
    if (!box || !ghost) return
    const measure = () => setFits(ghost.scrollWidth <= box.clientWidth + 0.5)
    measure()
    const ro = new ResizeObserver(measure)
    ro.observe(box)
    return () => ro.disconnect()
  })
  if (!v || !v.company) return <div className={`${CARD} ${place}`} data-testid="goal-card-hold" aria-hidden />

  const next = v.title.next
  // While sea limits are not on (`seas_bite` false) the title opens nothing yet, so the card promises nothing.
  const opens = next && v.title.seas_bite && next.opens.length > 0 ? t('command.lvOpens', { what: next.opens.join(', ') }) : null
  // 0468: lit only (a Trading step is served): what the next Trading level opens
  const trading = v.level_skills?.skills.find((s) => s.code === 'trading')
  const lit = trading?.benefits.some((b) => b.kind === 'perk') ?? false
  const ahead = lit && trading ? nextOpening(locale, v.tracks.trading.level, trading.benefits) : null
  const unlock = ahead ? t('command.goalOpens', { track: levelName(locale, 'trading'), n: ahead.level, what: ahead.what }) : null
  // THE PRESS OPENS THE NEXT STEP (2026-11-22 second play-test): the yard where she lies; away from it the Map, where its city is
  // (Office > City opens the city she lies in, and one with no yard fell back to its Market with no word why)
  const next2 = !second ? 'you' : second.here ? 'yard' : 'map'
  const nextTitle = next ? t('command.goalNext', { name: properName('title', next.name, next.name) }) : t('command.lvTitleTop')
  const press = () => {
    if (next2 === 'yard' && second) {
      // the yard ON the hull's sheet, where the Order is (finding 3); with a hull on order, the yard itself
      navigate(openOfficeCity('building_yard', second.order ? undefined : second.hull))
    } else if (next2 === 'map' && second?.port) {
      // the yard's city, its tray up with the Sail press (finding 21)
      showOnMap(second.port, true)
    } else navigate(next2 === 'map' ? '/map' : '/you')
  }
  // THE RING'S FILL: the goal's own served figures, nothing worked out but the share
  const ringPct = saving
    ? (Math.max(0, saving.have) / saving.price) * 100
    : second
      ? (second.of > 0 ? (second.ready / second.of) * 100 : 0)
      : next
        ? (Math.min(v.tracks.trading.level, v.tracks.exploration.level) / Math.max(1, next.level)) * 100
        : 100
  const ringDone = saving ? saving.have >= saving.price : ringPct >= 100
  return (
    // THE PRESS OPENS THE NEXT STEP (P0 of docs/design/playable-2026-11-22.md): while the second line is the second ship, the step
    // is the build yard's sheet (Office > City > Build yard: the materials stored, the Order, Plan trip, Build); otherwise the levels (You).
    <button type="button" onClick={press} className={`${CARD} ${place} bg-surface-2`}
      data-testid="goal-card"
      data-next={next2}
      // her two track levels stand on the card whatever its second line says (the second ship's count hides the words; a test reads these)
      data-trading={v.tracks.trading.level}
      data-exploration={v.tracks.exploration.level}
      data-unlock-level={ahead?.level}
    >
      <span className="col-start-1 row-span-2 row-start-1 flex self-center" data-testid="goal-ring" data-pct={Math.round(Math.min(100, ringPct))} data-done={ringDone || undefined}>
        <Ring pct={ringPct} size={30} label={second ? (goal?.words ?? nextTitle) : nextTitle}>
          <Icon name={second ? 'ship' : 'coronet'} size={16} className={ringDone ? 'text-success' : 'text-accent'} />
        </Ring>
      </span>
      <span ref={titleBox} className="relative col-start-2 min-w-0 overflow-hidden whitespace-nowrap text-t-body text-ink" data-testid="goal-title">
        {/* "Next: Mate" (2026-11-22, P0): the title bare read as a promotion she had not had (the You page still said the old one) */}
        {second && unlock ? (
          // THE UNLOCK STANDS WHERE IT FITS (2026-11-23, finding 9): measured against the line's own box at every width, else the
          // title stands; the unlock stays one press away, on You. The ghost is the measure: unseen and out of the flow.
          <>
            <span ref={unlockGhost} aria-hidden className="invisible absolute left-0 top-0 whitespace-nowrap">
              {unlock}
            </span>
            {fits ? <span data-testid="goal-unlock">{unlock}</span> : nextTitle}
          </>
        ) : (
          nextTitle
        )}
      </span>
      {reputation !== null ? (
        // from `sm` up the top bar carries Reputation (TopBar.tsx), and the card's first line is the goal's
        <span className="col-start-3 whitespace-nowrap text-t-caption text-ink-faint sm:hidden" data-testid="goal-reputation" data-value={reputation}>
          {t('shell.reputation')} {formatInt(reputation)}
        </span>
      ) : (
        <span className="col-start-3" />
      )}
      {second ? (
        <span
          className="col-span-2 col-start-2 min-w-0 whitespace-nowrap text-t-caption text-ink-faint"
          data-testid="goal-second-ship"
          data-ready={second.ready}
          data-of={second.of}
          data-purse={saving?.have}
          data-price={saving?.price}
        >
          {goal?.words}
        </span>
      ) : next && (
        <span className="col-span-2 col-start-2 min-w-0 break-words text-t-caption text-ink-faint" data-testid="goal-tracks">
          <span className="whitespace-nowrap">
            {/* a met requirement reads "Trading 7 ✓", not "Trading 7/4" (2026-11-23, finding 26) */}
            {[
              v.tracks.trading.level >= next.level
                ? t('command.goalTradingMet', { a: v.tracks.trading.level })
                : t('command.goalTrading', { a: v.tracks.trading.level, n: next.level }),
              v.tracks.exploration.level >= next.level
                ? t('command.goalExplorationMet', { a: v.tracks.exploration.level })
                : t('command.goalExploration', { a: v.tracks.exploration.level, n: next.level }),
            ].join(' · ')}
          </span>
          {opens ? ` · ${opens}` : unlock && ` · ${unlock}`}
        </span>
      )}
    </button>
  )
}
