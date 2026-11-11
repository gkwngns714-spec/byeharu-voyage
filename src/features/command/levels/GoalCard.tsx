import { useWide } from '../../../components/ui'
import { useT } from '../../../lib/i18n'
import { worldLevels, type LevelsView } from '../../../lib/rpc'
import { useServedRead } from '../../../live/useServedRead'
import { useDeskView } from '../deskView'

// THE GOAL CARD (remaster S6): one line on the Trade face saying what to aim for: the next Title and how far along you are.
// NOT a quest: it reads the SAME served read the Levels face reads (`world.levels()`, 0325, the same cached `worldLevels` read) and
// prints its figures: the next title (`title.next`), and the two tracks' levels. The rule "a title needs Trading and Exploration at
// the title's level" is the Levels face's own sentence (command.lvTitleNext); this card shows it as progress and invents no other
// threshold. What the title opens is `title.next.opens`, worded as the Levels face words it, and only while sea limits are lit. Pressing it turns to Levels.
//
// THE PRESS LAW: a fixed height in every state (loading, shown, nothing to show), so nothing moves when the read lands or on a press.

// A control is 44 px (tests/consistency.spec.ts), so the card is 44 px. On a phone every pixel above the goods is bought, so it stands on the
// Goods face only (the City and Report faces would lose room: tests/layout.spec.ts K.1, desk.city.spec.ts); on a wide glass it stands in the
// header, which is on every face, so the panes never move.
const CARD = 'flex h-11 min-w-0 shrink-0 flex-col justify-center rounded-control px-3 text-left'
const PHONE = 'mx-gutter'
const WIDE = 'w-[22rem] min-[90rem]:w-[26rem]'

export function GoalCard() {
  const t = useT()
  const wide = useWide()
  const place = wide ? WIDE : PHONE
  const turnTo = useDeskView((s) => s.turnTo)
  const read = useServedRead<LevelsView>('levels', () => worldLevels(), { name: 'worldLevels' })
  const v = read.view
  if (!v || !v.company) return <div className={`${CARD} ${place}`} data-testid="goal-card-hold" aria-hidden />

  const next = v.title.next
  const first = next
    ? t('command.goalNext', {
        name: next.name,
        a: v.tracks.trading.level,
        b: v.tracks.exploration.level,
        n: next.level,
      })
    : t('command.lvTitleTop')
  // While sea limits are not on (`seas_bite` false) the title opens nothing yet, so the card promises nothing.
  const second = next && v.title.seas_bite && next.opens.length > 0 ? t('command.lvOpens', { what: next.opens.join(', ') }) : null
  return (
    <button type="button" onClick={() => turnTo('levels')} className={`${CARD} ${place} bg-surface-2`} data-testid="goal-card">
      <span className="block break-words text-t-body text-ink">{first}</span>
      {second && <span className="block break-words text-t-caption text-ink-faint">{second}</span>}
    </button>
  )
}
