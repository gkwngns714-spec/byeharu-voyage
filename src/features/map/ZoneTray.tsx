import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Button, SheetSection, Tray, TrayTitle, seaName, type TrayDetent } from '../../components/ui'
import { CHART_CHROME } from '../../chart'
import type { SeaRow } from '../../domain/seas'
import { formatInt } from '../../lib/format'
import { useLocale, useT } from '../../lib/i18n'

// A SEA, PRESSED WHILE THE SEAS FILTER IS ON (owner, 2026-11-15: *"have option to see seas"*) — the map's tray for one sea zone:
// its name, its harbours, and the Codex's Seas face for the whole list. The sea limits are off (owner, 2026-11-23: "remove sea
// limits entirely"; docs/design/hq-command-2026-11-23.md), so the tray says nothing of a title, waves or a closed sea.

export function ZoneTray({ row, onClose }: { row: SeaRow; onClose: () => void }) {
  const t = useT()
  const locale = useLocale()
  const navigate = useNavigate()
  const [detent, setDetent] = useState<TrayDetent>('half')
  const line = row.zone.harbours !== undefined ? t('seas.harbours', { n: formatInt(row.zone.harbours), count: row.zone.harbours }) : undefined

  return (
    <Tray
      mode="side"
      detent={detent}
      onDetentChange={(next) => (next === 'closed' ? onClose() : setDetent(next))}
      title={<TrayTitle name={seaName(locale, { zoneName: row.zone.name })} line={line} testId="map-zone-name" />}
      data-testid="map-zone-tray"
      data-sea={row.zone.code}
      {...CHART_CHROME}
    >
      <SheetSection>
        <Button variant="secondary" size="sm" onClick={() => navigate('/compendium?face=seas')} data-testid="map-zone-codex">
          {t('map.allSeas')}
        </Button>
      </SheetSection>
    </Tray>
  )
}
