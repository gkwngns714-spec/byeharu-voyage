import { StatCell, StatRun, deltaTone } from '../../components/ui'
import { formatDucats, formatDucatsDelta, formatInt, formatPct } from '../../lib/format'
import { useT } from '../../lib/i18n'
import type { StatsWatch } from '../../lib/rpc'
import { Block } from './StatsBlock'

// THE ECONOMY WATCH (0229, docs/CLOSED_ECONOMY.md §7; owner row 212): the figures the closed
// economy is judged by.
//
// ON THE FACE, ALL SEVEN (owner, 2026-11-01, row 260: *"everything is folded in stats this is soo wrong"*; the
// brief: "the Watch figures must stay — move them, don't drop them"). They were one summary row with the new
// money on it and the other six on a page; they are now one block of cells, the new money the first of them
// (not printed twice: the title carries no figure).
//
// A FIGURE THE SERVER DID NOT SERVE IS NOT DRAWN (the consistency law, row 37's: an absence is drawn as an
// absence, never as a dash where a figure is owed). A count made before 0229 has no `under_reserve`; a world
// under a day old has no `total_delta_day`; an hour with no price step has no swing. The cell is simply not
// there until the figure is — the old page drew "—" for each, which is the thing the law refuses on a screen.

export function WatchSection({ watch }: { watch: StatsWatch | null | undefined }) {
  const t = useT()
  if (!watch) return null
  const count = (n: number | undefined) => (n === undefined ? null : { value: n, format: formatInt })
  const underReserve = count(watch.under_reserve)
  const underThin = count(watch.under_thin)
  const broke = count(watch.broke)
  const swing =
    watch.swing_p50 === undefined || watch.swing_p50 === null || watch.swing_p90 === undefined || watch.swing_p90 === null
      ? null
      : `${formatPct(watch.swing_p50, 1)} / ${formatPct(watch.swing_p90, 1)}`
  return (
    <Block title={t('watch.heading')} data-testid="stats-watch">
      {/* PAIRS, LIKE WORDS (owner row 258/260: label and figure close): seven of them wrap into three lines. */}
      <StatRun>
        <StatCell inline label={t('watch.newMoney')} value={watch.new_slot} format={formatDucatsDelta} size="body" tone={watch.new_slot > 0 ? 'success' : 'ink'} />
        {watch.total_delta_day !== null && (
          <StatCell inline label={t('watch.totalDay')} value={watch.total_delta_day} format={formatDucatsDelta} size="body" tone={deltaTone(watch.total_delta_day)} />
        )}
        {underReserve !== null && <StatCell inline label={t('watch.underReserve')} {...underReserve} size="body" />}
        {underThin !== null && <StatCell inline label={t('watch.underThin', { n: formatInt(watch.thin ?? 10_000) })} {...underThin} size="body" />}
        {broke !== null && <StatCell inline label={t('watch.broke')} {...broke} size="body" />}
        {watch.gifts_ducats !== undefined && (
          <StatCell
            inline
            label={t('watch.gifts')}
            text={`${formatInt(watch.gifts ?? 0)} · ${formatDucats(watch.gifts_ducats)}`}
            size="body"
            data-testid="stats-watch-gifts"
          />
        )}
        {swing !== null && <StatCell inline label={t('watch.swing')} text={swing} size="body" />}
      </StatRun>
    </Block>
  )
}
