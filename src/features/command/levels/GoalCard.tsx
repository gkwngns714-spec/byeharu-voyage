import { useWide } from '../../../components/ui'
import { properName, useT } from '../../../lib/i18n'
import { worldLevels, type LevelsView } from '../../../lib/rpc'
import { useServedRead } from '../../../live/useServedRead'
import { useSecondShip } from '../../../live/useSecondShip'
import { useWorld } from '../../../live/worldStore'
import { formatInt } from '../../../lib/format'
import { useDeskView } from '../deskView'

// THE GOAL CARD (remaster S6): one line on the Trade face saying what to aim for: the next Title and how far along you are.
// NOT a quest: it reads the SAME served read the Levels face reads (`world.levels()`, 0325, the same cached `worldLevels` read) and
// prints its figures: the next title (`title.next`), and the two tracks' levels. The rule "a title needs Trading and Exploration at
// the title's level" is the Levels face's own sentence (command.lvTitleNext); this card shows it as progress and invents no other
// threshold. What the title opens is `title.next.opens`, worded as the Levels face words it, and only while sea limits are lit. Pressing it turns to Levels.
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
// THE PRESS LAW: a fixed height in every state (loading, shown, nothing to show), so nothing moves when the read lands or on a press.

// A control is 44 px (tests/consistency.spec.ts), so the card is 44 px. On a phone every pixel above the goods is bought, so it stands on the
// Goods face only (the City and Report faces would lose room: tests/layout.spec.ts K.1, desk.city.spec.ts); on a wide glass it stands under the
// header on every face, so the panes never move between faces (the header has no room for it at 1024 px).
// THE CARD'S LINES NEVER BREAK (2026-11-12, the owner on a phone: *"long words and sentences making new messy lines"*). It was one
// sentence, "Mate: Trading 1/2, Exploration 1/2", in a 44-px box set a second gutter in from the page's own: at 320 px the sentence
// took two lines and pushed Reputation out of the box. Now the title's name and Reputation share the first line and the two tracks
// are the second, each short enough for a 320-px glass with the longest served title; the box stands on the page's own margin.
const CARD = 'grid min-h-11 min-w-0 shrink-0 grid-cols-[minmax(0,1fr)_auto] content-center items-baseline gap-x-3 rounded-control px-3 text-left'
const PHONE = 'mb-1'
const WIDE = 'mx-3 mb-2 w-[22rem] min-[90rem]:mx-6'

export function GoalCard() {
  const t = useT()
  const wide = useWide()
  const place = wide ? WIDE : PHONE
  const turnTo = useDeskView((s) => s.turnTo)
  const read = useServedRead<LevelsView>('levels', () => worldLevels(), { name: 'worldLevels' })
  const v = read.view
  const reputation = useWorld((s) => s.player?.reputation?.balance ?? null)
  const second = useSecondShip()
  if (!v || !v.company) return <div className={`${CARD} ${place}`} data-testid="goal-card-hold" aria-hidden />

  const next = v.title.next
  // While sea limits are not on (`seas_bite` false) the title opens nothing yet, so the card promises nothing.
  const opens = next && v.title.seas_bite && next.opens.length > 0 ? t('command.lvOpens', { what: next.opens.join(', ') }) : null
  return (
    <button type="button" onClick={() => turnTo('levels')} className={`${CARD} ${place} bg-surface-2`} data-testid="goal-card">
      <span className="min-w-0 whitespace-nowrap text-t-body text-ink" data-testid="goal-title">
        {next ? properName('title', next.name, next.name) : t('command.lvTitleTop')}
      </span>
      {reputation !== null ? (
        <span className="whitespace-nowrap text-t-caption text-ink-faint" data-testid="goal-reputation" data-value={reputation}>
          {t('shell.reputation')} {formatInt(reputation)}
        </span>
      ) : (
        <span />
      )}
      {second ? (
        <span
          className="col-span-2 min-w-0 whitespace-nowrap text-t-caption text-ink-faint"
          data-testid="goal-second-ship"
          data-ready={second.ready}
          data-of={second.of}
        >
          {t('yard.secondShip', { n: formatInt(second.ready), of: formatInt(second.of) })}
        </span>
      ) : next && (
        <span className="col-span-2 min-w-0 break-words text-t-caption text-ink-faint" data-testid="goal-tracks">
          <span className="whitespace-nowrap">
            {t('command.goalTracks', { a: v.tracks.trading.level, b: v.tracks.exploration.level, n: next.level })}
          </span>
          {opens && ` · ${opens}`}
        </span>
      )}
    </button>
  )
}
