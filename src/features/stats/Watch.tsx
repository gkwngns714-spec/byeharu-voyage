import { Card, Skeleton, StatCell, deltaTone } from '../../components/ui'
import { formatDucats, formatDucatsDelta, formatInt, formatPct } from '../../lib/format'
import { useT } from '../../lib/i18n'
import type { StatsNow } from '../../lib/rpc'

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
//
// THE CARD HOLDS ITS PLACE (2026-11-12; the owner's law: nothing re-flows under the player). Its figures ride the live read
// (world.stats_now), which lands after the face's own (one queue), and the card used to draw NOTHING until then: when it
// landed, 345 px of card pushed the world's chart down a phone (tests/news.dotSize.spec.ts caught "y 255 → y 611" once) and
// across a column at 1,280. So the lines stand in ONE BOX of the seven lines' height, before the read and after it: while
// the read is out the box holds seven placeholder lines (`Skeleton`, the one loading placeholder), and a line the server did
// not serve leaves its room at the foot of the box. Neither the landing nor a figure coming or going (the swing, hour by
// hour) moves what is under the card. `data-watch-loaded` says which of the two is drawn. tests/stats.watchHold.spec.ts.

const LINES = 7
/** The lines' one box: seven statement lines tall (a line is `min-h-row`), served or not. */
const LINES_BOX = 'min-h-[calc(var(--spacing-row)*7)]'

export function WatchCard({ live }: { live: StatsNow | null }) {
  const t = useT()
  if (live === null) {
    return (
      <Card title={t('watch.heading')} data-testid="stats-watch">
        <div className={LINES_BOX} data-watch-loaded="false">
          {Array.from({ length: LINES }, (_, i) => (
            <div key={i} className="flex min-h-row items-center py-1">
              <Skeleton className="h-6 w-full" />
            </div>
          ))}
        </div>
      </Card>
    )
  }
  // a world not counted yet has no watch (0229): there is no card, as before
  const watch = live.watch
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
      <div className={LINES_BOX} data-watch-loaded="true">
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
      </div>
    </Card>
  )
}
