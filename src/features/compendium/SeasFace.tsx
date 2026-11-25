import { useMemo, type ReactNode } from 'react'
import { ListPanel, Row, seaName, seaWallAsks } from '../../components/ui'
import { formatInt } from '../../lib/format'
import { useLocale, useT } from '../../lib/i18n'
import { fold, foldedMatch } from '../../lib/text'
import { useShutSeas } from '../../live/useFleetNav'
import { useSeaRows } from '../../live/useSeas'
import { useWorld } from '../../live/worldStore'
import { NoAnswer } from './NoAnswer'

// THE SEAS — every sea by name, with its harbours (world.sea_conditions' zones). The owner switched the sea limits off on
// 2026-11-23 ("remove sea limits entirely"; docs/design/hq-command-2026-11-23.md): every sea is open to every fleet, so the face
// draws no title, no waves and no closed list. 0514: while the seas bite again, each sea says what it asks, and a sea closed to the first
// fleet says what she is short of (the server's figures; nothing is compared here).

export function SeasFace({ query, search }: { query: string; search: ReactNode }) {
  const t = useT()
  const locale = useLocale()
  const seas = useSeaRows()
  const shut = useShutSeas()
  const firstFleet = useWorld((s) => s.fleets[0]?.id ?? null)
  const walls = shut.of(firstFleet)

  const rows = useMemo(() => {
    const needle = fold(query.trim())
    return seas.rows.filter((r) => foldedMatch(needle, r.zone.name, seaName(locale, { zoneName: r.zone.name }), r.zone.code))
  }, [seas.rows, query, locale])

  return (
    <ListPanel look="card" columns="fit" title={t('seas.seas')} count={formatInt(rows.length)} trailing={search} data-testid="seas-open">
      {rows.length === 0 ? (
        <NoAnswer />
      ) : (
        rows.map((r) => (
          <Row
            key={r.zone.code}
            label={seaName(locale, { zoneName: r.zone.name })}
            value={
              r.zone.harbours !== undefined ? (
                <span className="whitespace-nowrap text-t-caption text-ink-muted">{t('seas.harbours', { n: formatInt(r.zone.harbours), count: r.zone.harbours })}</span>
              ) : undefined
            }
            hairline={false}
            wholeName
            data-testid="sea-row"
            data-sea={r.zone.code}
            data-open={shut.bite ? (walls[r.zone.code] ? 'no' : 'yes') : undefined}
          >
            {shut.bite && (
              <span className="block text-t-caption text-ink-faint" data-testid="sea-row-asks">
                {t('seas.asks', { level: formatInt(r.zone.title_min), waves: formatInt(r.zone.wave_min) })}
              </span>
            )}
            {walls[r.zone.code] && (
              <span className="block text-t-caption text-ink-muted" data-testid="sea-row-why">
                {t('seas.closed')} {seaWallAsks(locale, walls[r.zone.code])}
              </span>
            )}
          </Row>
        ))
      )}
    </ListPanel>
  )
}
