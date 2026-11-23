import { Countdown, Flag, FlagSlot, Icon, NeedChip } from '../../../components/ui'
import { useShellState } from '../../../app/shellState'
import { formatInt } from '../../../lib/format'
import { useT } from '../../../lib/i18n'
import type { NationRaceView } from '../../../lib/rpc'
import { nationNameOf, useWorld } from '../../../live/worldStore'

// THE COUNTRY RACE ON THE BRIDGE (0484, docs/design/roadmap-2026-11-23.md slice 15; owner, 2026-11-23: "words with graphics. choosing best
// options available"): her country's flag and place this week, the top countries as flags with a bar of the contested cities each leads,
// her own influence, the week's clock, her home perk on the dock fee, her title when she is a champion, and last week's winner. Marks
// first; each mark's word is its accessible name. Drawn only while the race is lit (world.nation_race, live/useNationRace.ts).

/** How many countries the bar chart shows (hers is always among them). */
const SHOWN = 4

export function RaceBridge({ race }: { race: Extract<NationRaceView, { company: true }> }) {
  const t = useT()
  const { nowMs } = useShellState()
  const nationByCode = useWorld((s) => s.nationByCode)
  const mine = race.mine.nation
  const me = race.nations.find((n) => n.nation === mine) ?? null
  const top = race.nations.slice(0, SHOWN)
  const rows = me && !top.some((n) => n.nation === me.nation) ? [...top.slice(0, SHOWN - 1), me] : top
  const most = Math.max(1, ...rows.map((n) => n.cities))
  const name = (code: string) => nationNameOf(nationByCode, code)
  const cut = Math.round(race.perk.fee_cut * 100)

  return (
    <section
      aria-label={t('hq.race')}
      className="flex min-w-0 flex-col gap-2 rounded-tile bg-surface p-3"
      data-testid="hq-race"
      data-nation={mine ?? undefined}
      data-place={me?.place ?? undefined}
    >
      <div className="flex min-w-0 flex-wrap items-center gap-x-3 gap-y-1">
        <span className="flex items-center gap-1.5 text-t-caption text-ink-muted">
          <Icon name="banner" size={16} aria-hidden />
          {t('hq.race')}
        </span>
        {mine && me && (
          <span className="flex items-center gap-1.5 text-t-label text-ink" data-testid="hq-race-place">
            <Flag code={mine} name={name(mine)} />
            {t('hq.racePlace', { n: formatInt(me.place), of: formatInt(race.nations.length) })}
          </span>
        )}
        {race.title && (
          <span data-testid="hq-race-title" className="inline-flex">
            <NeedChip icon="laurel" tone="accent" label={t('hq.champion')}>
              {t('hq.champion')}
            </NeedChip>
          </span>
        )}
      </div>

      <ol className="flex flex-col gap-1" data-testid="hq-race-nations">
        {rows.map((n) => (
          <li key={n.nation} className="grid grid-cols-[auto_minmax(0,1fr)_auto] items-center gap-2" data-nation={n.nation} data-mine={n.nation === mine || undefined}>
            <Flag code={n.nation} name={name(n.nation)} size="caption" />
            <span className="h-2 min-w-0 overflow-hidden rounded-chip bg-surface-2" aria-hidden="true">
              <span className={`block h-full rounded-chip ${n.nation === mine ? 'bg-accent' : 'bg-ink-faint'}`} style={{ width: `${(100 * n.cities) / most}%` }} />
            </span>
            <span className={`text-t-caption tabular-nums ${n.nation === mine ? 'text-accent' : 'text-ink-muted'}`} aria-label={`${name(n.nation)} · ${t('hq.raceCities', { n: formatInt(n.cities) })}`}>
              {formatInt(n.cities)}
            </span>
          </li>
        ))}
      </ol>

      <span className="flex flex-wrap gap-1.5">
        <NeedChip icon="banner" tone="success" label={t('hq.racePoints', { n: formatInt(race.mine.points) })}>
          {formatInt(race.mine.points)}
        </NeedChip>
        <NeedChip icon="history" tone="info" label={t('hq.raceEnds')}>
          <Countdown untilMs={Date.parse(race.ends_at)} nowMs={nowMs} />
        </NeedChip>
        {cut > 0 && (
          <NeedChip icon="anchor" tone="success" label={t('hq.homeFee', { n: cut })}>
            −{cut}%
          </NeedChip>
        )}
        {race.last && (
          <span className="inline-flex" data-testid="hq-race-last">
            <NeedChip icon="trophy" label={t('hq.lastWinner')}>
              {race.last.winner ? <Flag code={race.last.winner} name={name(race.last.winner)} size="caption" /> : <FlagSlot size="caption" />}
            </NeedChip>
          </span>
        )}
      </span>
    </section>
  )
}
