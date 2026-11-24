import { Bar, Figure, Icon, KEEP_WORDS_CLASS } from '../../../components/ui'
import { formatDucatsDelta, formatInt } from '../../../lib/format'
import { properName, useLocale, useT } from '../../../lib/i18n'
import { worldLevels, type LevelsView } from '../../../lib/rpc'
import { levelName, nextOpening } from '../../../live/levelWords'
import { useServedRead } from '../../../live/useServedRead'
import type { Board } from './useBoard'

// THE RANK STRIP (docs/design/hq-corp-2026-11-24.md B5 and C1, slice H2): the top of HQ. Her Rank and a bar to the next one, what
// the next level opens, and her company's NET PER HOUR, large, green or red (a flat 0 is muted).
//
//   RANK        the Title (`world.levels().title`, the one reader of public.title_level): its name, its step of the ladder, and a bar
//               to the next title (the lower of her Trading and Exploration levels against the level the next title asks: the goal
//               card's own share, GoalCard.tsx).
//   NEXT        what her next level opens, from the served `level_perks` steps (levelWords.nextOpening over Trading's and Exploration's
//               served benefits: the two levels the Rank is made of). With no step served, the next title's name.
//   PER HOUR    `hq_board.rate.per_hour` exactly as served (her ledger's last 24 hours over 24). NEVER worked out here.
//
// NOT DRAWN: her place in her home city. No read serves a company's place in a city's Influence (world.town_hall serves the countries'
// shares and her own points), and the client ranks nothing.
//
// THE STRIP HAS ONE HEIGHT. The per-hour figure, the rank line and the next line each stand in a slot of their own line's height, so
// the levels read or the board landing late moves nothing under the strip (the "/ hour" line used to grow HQ when it arrived).

type Lit = Extract<LevelsView, { company: true }>

export function Bridge({ board }: { board: Board }) {
  const t = useT()
  const locale = useLocale()
  // the levels read every levels reader shares (the goal card's, the You page's: one cached read)
  const read = useServedRead<LevelsView>('levels', () => worldLevels(), { name: 'worldLevels' })
  const v: Lit | null = read.view && read.view.company ? read.view : null
  const title = v?.title ?? null
  const next = title?.next ?? null
  const name = title?.name ? properName('title', title.name, title.name) : null
  // the bar: the lower of the two tracks against the level the next title asks; the top title is full
  const pct = v && next ? (Math.min(v.tracks.trading.level, v.tracks.exploration.level) / Math.max(1, next.level)) * 100 : 100
  const opening = v ? nextStep(locale, v) : null
  const nextWord = opening
    ? t('command.goalOpens', { track: levelName(locale, opening.track), n: opening.level, what: opening.what })
    : next
      ? t('command.goalNext', { name: properName('title', next.name, next.name) })
      : title
        ? t('command.lvTitleTop')
        : null
  const rate = board.perHour

  return (
    <section
      aria-label={t('hq.rank')}
      className="grid min-w-0 grid-cols-1 gap-x-6 gap-y-2 rounded-tile bg-surface p-3 md:grid-cols-[minmax(0,1fr)_auto] md:items-center"
      data-testid="hq-bridge"
    >
      <div className="flex min-w-0 flex-col gap-1">
        <div className="flex min-h-[1.375rem] min-w-0 items-center gap-2" data-testid="hq-rank" data-level={title?.level} data-next-level={next?.level}>
          {title && (
            <>
              <Icon name="coronet" size={18} className="shrink-0 text-accent" aria-hidden />
              <span className={`${KEEP_WORDS_CLASS} text-t-body font-medium text-ink`} data-testid="hq-rank-name">
                {name ?? t('hq.rank')}
              </span>
              <Bar pct={pct} label={t('hq.rankStep', { n: formatInt(title.level), of: formatInt(title.max) })} className="min-w-12 max-w-56 flex-1" />
              <span className="shrink-0 whitespace-nowrap text-t-caption tabular-nums text-ink-faint" aria-hidden>
                {formatInt(title.level)} / {formatInt(title.max)}
              </span>
            </>
          )}
        </div>
        <span className="min-h-[1.125rem] break-words text-t-caption text-ink-muted" data-testid="hq-rank-next" data-level={opening?.level}>
          {nextWord}
        </span>
      </div>

      {/* THE NET PER HOUR'S SLOT: the figure's own line, held whether the rate is here yet or not (nothing under the strip moves) */}
      <div className="flex h-7 min-w-0 items-center justify-center md:justify-end" data-testid="hq-bridge-rate-slot">
        {rate !== null && (
          <span className="inline-flex" title={t('hq.rateDay')} data-testid="hq-bridge-rate" data-span="24h" data-per-hour={rate}>
            <Figure value={t('hq.perHour', { n: formatDucatsDelta(rate) })} size="figure" tone={rate < 0 ? 'danger' : rate > 0 ? 'success' : 'muted'} />
          </span>
        )}
      </div>
    </section>
  )
}

/** The first level above hers that opens something, over the two tracks the Rank is made of (the lower level first; Trading on a tie).
 *  A pick among served steps: nothing is counted. */
function nextStep(locale: ReturnType<typeof useLocale>, v: Lit): { track: string; level: number; what: string } | null {
  const steps = (['trading', 'exploration'] as const).flatMap((track) => {
    const skill = v.level_skills?.skills.find((s) => s.code === track)
    const open = skill ? nextOpening(locale, v.tracks[track].level, skill.benefits) : null
    return open ? [{ track, ...open }] : []
  })
  return steps.sort((a, b) => a.level - b.level)[0] ?? null
}
