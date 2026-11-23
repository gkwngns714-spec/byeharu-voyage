import { useMemo, type ReactNode } from 'react'
import { ListPanel, Row, seaName } from '../../components/ui'
import { formatInt } from '../../lib/format'
import { useLocale, useT } from '../../lib/i18n'
import { fold, foldedMatch } from '../../lib/text'
import { useSeaRows } from '../../live/useSeas'
import { NoAnswer } from './NoAnswer'

// THE SEAS — every sea by name, with its harbours (world.sea_conditions' zones). The owner switched the sea limits off on
// 2026-11-23 ("remove sea limits entirely"; docs/design/hq-command-2026-11-23.md): every sea is open to every fleet, so the face
// draws no title, no waves and no closed list.

export function SeasFace({ query, search }: { query: string; search: ReactNode }) {
  const t = useT()
  const locale = useLocale()
  const seas = useSeaRows()

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
          />
        ))
      )}
    </ListPanel>
  )
}
