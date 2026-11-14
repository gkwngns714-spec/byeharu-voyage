import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Button, Hint, Row, SheetSection, Tray, TrayTitle, seaName, seaWallAsks, seaWallFix, type TrayDetent } from '../../components/ui'
import { CHART_CHROME } from '../../chart'
import type { FleetSeas, SeaRow } from '../../domain/seas'
import { formatInt } from '../../lib/format'
import { properName, useLocale, useT } from '../../lib/i18n'
import type { SeaConditions } from '../../lib/rpc'

// A SEA, PRESSED WHILE THE SEAS FILTER IS ON (owner, 2026-11-15: *"have option to see seas, showing waves,
// requirement to pass etc."*) — the map's tray for one sea zone: what it asks, whether the fleet in hand may enter,
// and the Codex's Seas face for the whole list. Every figure is served (world.sea_conditions, 0215 + 0396): the two
// asks, her title, the fleet's waves, and the server's verdict (the wall). Nothing is compared here. While the sea
// conditions are dark no sea is called closed, as on the Codex's face.

export function ZoneTray({
  row,
  seas,
  title,
  homeRank,
  onClose,
}: {
  row: SeaRow
  seas: FleetSeas
  title: SeaConditions['title']
  /** The rank of her home waters (0396 `home_sea.title_min`), read, never compared with hers. */
  homeRank: number | null
  onClose: () => void
}) {
  const t = useT()
  const locale = useLocale()
  const navigate = useNavigate()
  const [detent, setDetent] = useState<TrayDetent>('half')
  const walled = seas.bite && seas.judged
  const wall = walled ? row.wall : null
  const asks = `${t('seas.asksTitle', { n: formatInt(row.zone.title_min) })} · ${t('seas.asksWaves', { n: formatInt(row.zone.wave_min) })}`
  const home = homeRank !== null && row.zone.title_min === homeRank

  return (
    <Tray
      mode="side"
      detent={detent}
      onDetentChange={(next) => (next === 'closed' ? onClose() : setDetent(next))}
      title={<TrayTitle name={seaName(locale, { zoneName: row.zone.name })} line={asks} testId="map-zone-name" />}
      data-testid="map-zone-tray"
      data-sea={row.zone.code}
      data-open={walled ? (wall ? 'no' : 'yes') : undefined}
      {...CHART_CHROME}
    >
      <SheetSection>
        {seas.fleet && walled && (
          <Row
            label={seas.fleet.name}
            value={<span className={wall ? 'text-warning' : 'text-accent'}>{wall ? t('seas.closed') : t('seas.open')}</span>}
            wholeName
            data-testid="map-zone-verdict"
          >
            {wall && (
              <span className="block text-t-caption text-ink-muted">
                {[seaWallAsks(locale, wall), seaWallFix(locale, wall)].filter((s) => s !== '').join(' ')}
              </span>
            )}
          </Row>
        )}
        {!seas.bite && <Hint>{t('seas.dark')}</Hint>}
        {home && <Row label={t('seas.homeWaters')} value="" hairline={false} />}
        {title && (
          <Row
            label={t('seas.yourTitle')}
            value={`${formatInt(title.level)}${title.name ? ` · ${properName('title', title.name, title.name)}` : ''}`}
          />
        )}
        {seas.fleet && <Row label={t('seas.fleetWaves')} value={seas.fleet.wave === null ? '—' : formatInt(seas.fleet.wave)} />}
        {row.zone.harbours !== undefined && (
          <Row label={t('seas.harbours', { n: formatInt(row.zone.harbours), count: row.zone.harbours })} value="" hairline={false} />
        )}
        <Hint>{t('seas.howTitle')}</Hint>
        <Hint>{t('seas.howWaves')}</Hint>
        <Button variant="secondary" size="sm" className="mt-2" onClick={() => navigate('/compendium?face=seas')} data-testid="map-zone-codex">
          {t('map.allSeas')}
        </Button>
      </SheetSection>
    </Tray>
  )
}
