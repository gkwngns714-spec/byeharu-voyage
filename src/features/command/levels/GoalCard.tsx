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

const CARD = 'mx-gutter mb-2 flex h-14 min-w-0 shrink-0 flex-col justify-center rounded-control px-3 text-left'

export function GoalCard() {
  const t = useT()
  const turnTo = useDeskView((s) => s.turnTo)
  const read = useServedRead<LevelsView>('levels', () => worldLevels(), { name: 'worldLevels' })
  const v = read.view
  if (!v || !v.company) return <div className={CARD} data-testid="goal-card-hold" aria-hidden />

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
    <button type="button" onClick={() => turnTo('levels')} className={`${CARD} bg-surface-2`} data-testid="goal-card">
      <span className="block break-words text-t-body text-ink">{first}</span>
      {second && <span className="block break-words text-t-caption text-ink-faint">{second}</span>}
    </button>
  )
}
