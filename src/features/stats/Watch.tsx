import { SectionFold, StatCell, deltaTone } from '../../components/ui'
import { formatDucats, formatDucatsDelta, formatInt, formatPct } from '../../lib/format'
import { useT } from '../../lib/i18n'
import type { StatsWatch } from '../../lib/rpc'

// THE ECONOMY WATCH (0229, docs/CLOSED_ECONOMY.md §7; owner row 212: "lets try this model and see the stats
// after few days"). The figures the closed economy is judged by, served by world.stats_now() as `watch` and
// drawn as they come: new money at the last count, the world total's move over 24 h, harbours under their
// reserve and under the thin line, broke merchants, capital gifts, and the price swing (median / p90 of a
// 10-minute step over the last hour). Presentation only — every figure is the server's. A figure the count
// did not carry (a count made before 0229) reads "—".

const dash = '—'

export function WatchSection({ watch }: { watch: StatsWatch | null | undefined }) {
  const t = useT()
  if (!watch) return null
  const count = (n: number | undefined) => (n === undefined ? { text: dash } : { value: n, format: formatInt })
  const swing =
    watch.swing_p50 === undefined || watch.swing_p50 === null || watch.swing_p90 === undefined || watch.swing_p90 === null
      ? dash
      : `${formatPct(watch.swing_p50, 1)} / ${formatPct(watch.swing_p90, 1)}`
  return (
    // THE WATCH IS A CONSULT, SO IT IS ONE LINE (2026-10-31, the sheet law): the closed line carries
    // new money at the last count; the seven figures are one press away.
    <SectionFold heading={t('watch.heading')} summary={watch.new_slot === undefined ? dash : formatDucatsDelta(watch.new_slot)} data-testid="stats-watch">
      <div className="grid grid-cols-2 gap-x-4 gap-y-3 lg:grid-cols-4">
        <StatCell label={t('watch.newMoney')} value={watch.new_slot} format={formatDucatsDelta} size="body" tone={watch.new_slot > 0 ? 'success' : 'ink'} />
        {watch.total_delta_day === null ? (
          <StatCell label={t('watch.totalDay')} text={dash} size="body" />
        ) : (
          <StatCell label={t('watch.totalDay')} value={watch.total_delta_day} format={formatDucatsDelta} size="body" tone={deltaTone(watch.total_delta_day)} />
        )}
        <StatCell label={t('watch.underReserve')} {...count(watch.under_reserve)} size="body" />
        <StatCell label={t('watch.underThin', { n: formatInt(watch.thin ?? 10_000) })} {...count(watch.under_thin)} size="body" />
        <StatCell label={t('watch.broke')} {...count(watch.broke)} size="body" />
        {watch.gifts_ducats === undefined ? (
          <StatCell label={t('watch.gifts')} text={dash} size="body" />
        ) : (
          <StatCell
            label={t('watch.gifts')}
            text={`${formatInt(watch.gifts ?? 0)} · ${formatDucats(watch.gifts_ducats)}`}
            size="body"
            data-testid="stats-watch-gifts"
          />
        )}
        <StatCell label={t('watch.swing')} text={swing} size="body" />
      </div>
    </SectionFold>
  )
}
