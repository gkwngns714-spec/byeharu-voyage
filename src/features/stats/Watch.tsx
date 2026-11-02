import { Card, StatCell, deltaTone } from '../../components/ui'
import { formatDucats, formatDucatsDelta, formatInt, formatPct } from '../../lib/format'
import { useT } from '../../lib/i18n'
import type { StatsWatch } from '../../lib/rpc'

// THE ECONOMY WATCH (0229, docs/CLOSED_ECONOMY.md §7; owner row 212): the figures the closed
// economy is judged by.
//
// ON THE FACE, ALL SEVEN (owner, 2026-11-01, row 260: *"everything is folded in stats this is soo wrong"*; the
// brief: "the Watch figures must stay — move them, don't drop them"). They are one card of statement lines, the new
// money the first of them (not printed twice: the title carries no figure). A LINE IS A LABEL AT THE LEFT AND A
// FIGURE AT THE RIGHT (2026-11-02, owner row 267 — *"too packed"*): the pairs the unfold slice wrapped like words,
// label and figure hugging at 8 px, are 52-px lines now, 24-px figures on one edge.
//
// A FIGURE THE SERVER DID NOT SERVE IS NOT DRAWN (the consistency law, row 37's: an absence is drawn as an
// absence, never as a dash where a figure is owed). A count made before 0229 has no `under_reserve`; a world
// under a day old has no `total_delta_day`; an hour with no price step has no swing. The line is simply not
// there until the figure is — the old page drew "—" for each, which is the thing the law refuses on a screen.

export function WatchCard({ watch }: { watch: StatsWatch | null | undefined }) {
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
    <Card title={t('watch.heading')} data-testid="stats-watch">
      <StatCell look="line" label={t('watch.newMoney')} value={watch.new_slot} format={formatDucatsDelta} tone={watch.new_slot > 0 ? 'success' : 'ink'} />
      {watch.total_delta_day !== null && (
        <StatCell look="line" label={t('watch.totalDay')} value={watch.total_delta_day} format={formatDucatsDelta} tone={deltaTone(watch.total_delta_day)} />
      )}
      {underReserve !== null && <StatCell look="line" label={t('watch.underReserve')} {...underReserve} />}
      {underThin !== null && <StatCell look="line" label={t('watch.underThin', { n: formatInt(watch.thin ?? 10_000) })} {...underThin} />}
      {broke !== null && <StatCell look="line" label={t('watch.broke')} {...broke} />}
      {watch.gifts_ducats !== undefined && (
        <StatCell look="line" label={t('watch.gifts')} text={`${formatInt(watch.gifts ?? 0)} · ${formatDucats(watch.gifts_ducats)}`} data-testid="stats-watch-gifts" />
      )}
      {swing !== null && <StatCell look="line" label={t('watch.swing')} text={swing} />}
    </Card>
  )
}
