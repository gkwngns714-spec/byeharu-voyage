import { Row, Skeleton } from '../components/ui'
import { formatInt } from '../lib/format'
import { useT, type TKey } from '../lib/i18n'
import { useCaptainStats } from './useCaptainStats'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// HER STATS — the five lines on a captain's card (0337, docs/WORLD_POWERS.md 2.4; owner row 288: "captains should also have stats").
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// `world.captain_stats` is her SHEET, derived and stored nowhere: five stats (Gunnery, Boarding, Seamanship, Trade, Care), each her level in its track and the
// parts she adds — what her seat is worth to her ship or fleet, from the same terms the fight, the speed, the hold and the prices read. Nothing is computed
// here: the level is a number the server served, the parts are the server's own lines ("+9.5% speed"), and the five groups are the server's, in its order.
// A stat that adds nothing shows its level alone; a captain with no level (Care) shows none; a captain ashore shows her levels and no parts; a captain the
// server does not know shows nothing at all. A blank is a blank, never a 0.
//
// While the first ask is on the wire a block of the height of five rows stands in its place (the Skeleton), so the card under it does not jump when the sheet lands.

export function CaptainStats({ code }: { code: string }) {
  const t = useT()
  const { view: sheet, loading } = useCaptainStats(code)
  if (!sheet && !loading) return null
  return (
    <div data-testid="captain-stats">
      <h4 className="pb-1 pt-4 text-t-caption text-ink-faint">{t('books.stats')}</h4>
      {sheet ? (
        sheet.stats.map((s, i) => {
          const lines = s.parts.flatMap((p) => (p.line ? [p.line] : []))
          return (
            <Row
              key={s.stat}
              label={t(`books.stat_${s.stat}` as TKey)}
              value={s.level === null ? undefined : t('ship.level', { n: formatInt(s.level) })}
              hairline={i < sheet.stats.length - 1}
              data-testid={`captain-stat-${s.stat}`}
            >
              {lines.length > 0 && (
                <span className="block text-t-body" data-testid={`captain-stat-${s.stat}-parts`}>
                  {lines.join(' · ')}
                </span>
              )}
            </Row>
          )
        })
      ) : (
        <Skeleton className="mt-1 h-64 w-full" />
      )}
    </div>
  )
}
