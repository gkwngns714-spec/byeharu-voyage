import { useWide } from '../../../components/ui'
import { useT } from '../../../lib/i18n'
import { worldLevels, type LevelsView } from '../../../lib/rpc'
import { useServedRead } from '../../../live/useServedRead'
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
// THE PRESS LAW: a fixed height in every state (loading, shown, nothing to show), so nothing moves when the read lands or on a press.

// A control is 44 px (tests/consistency.spec.ts), so the card is 44 px. On a phone every pixel above the goods is bought, so it stands on the
// Goods face only (the City and Report faces would lose room: tests/layout.spec.ts K.1, desk.city.spec.ts); on a wide glass it stands under the
// header on every face, so the panes never move between faces (the header has no room for it at 1024 px).
const CARD = 'flex h-11 min-w-0 shrink-0 flex-col justify-center rounded-control px-3 text-left'
const PHONE = 'mx-gutter'
const WIDE = 'mx-3 mb-2 w-[22rem] min-[90rem]:mx-6'

export function GoalCard() {
  const t = useT()
  const wide = useWide()
  const place = wide ? WIDE : PHONE
  const turnTo = useDeskView((s) => s.turnTo)
  const read = useServedRead<LevelsView>('levels', () => worldLevels(), { name: 'worldLevels' })
  const v = read.view
  const reputation = useWorld((s) => s.player?.reputation?.balance ?? null)
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
      {(second || reputation !== null) && (
        <span className="block break-words text-t-caption text-ink-faint">
          {second}
          {second && reputation !== null && ' · '}
          {reputation !== null && (
            <span data-testid="goal-reputation" data-value={reputation}>
              {t('shell.reputation')} {formatInt(reputation)}
            </span>
          )}
        </span>
      )}
    </button>
  )
}
