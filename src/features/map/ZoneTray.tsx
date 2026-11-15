import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Button, Hint, Row, SheetSection, Tray, TrayTitle, seaName, seaWallFix, type TrayDetent } from '../../components/ui'
import { CHART_CHROME } from '../../chart'
import type { FleetSeas, SeaRow } from '../../domain/seas'
import { formatInt, NBSP } from '../../lib/format'
import { useLocale, useT } from '../../lib/i18n'
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
  const home = homeRank !== null && row.zone.title_min === homeRank
  // HAVE / NEED (2026-11-15 owner: "just tell me what i have, and what is required"): one row per ask, hers beside it,
  // in the danger ink when the server calls it short. The tray's line is the sea's harbours (and home waters).
  const short = (flag: boolean | null | undefined) => wall !== null && flag !== false
  const pair = (have: number | null | undefined, need: number) =>
    have === null || have === undefined ? formatInt(need) : `${formatInt(have)}${NBSP}/${NBSP}${formatInt(need)}`
  const line = [
    row.zone.harbours !== undefined ? t('seas.harbours', { n: formatInt(row.zone.harbours), count: row.zone.harbours }) : null,
    home ? t('seas.homeWaters') : null,
  ]
    .filter((s): s is string => s !== null)
    .join(' · ')
  const fix = wall ? seaWallFix(locale, wall) : ''

  return (
    <Tray
      mode="side"
      detent={detent}
      onDetentChange={(next) => (next === 'closed' ? onClose() : setDetent(next))}
      title={<TrayTitle name={seaName(locale, { zoneName: row.zone.name })} line={line || undefined} testId="map-zone-name" />}
      data-testid="map-zone-tray"
      data-sea={row.zone.code}
      data-open={walled ? (wall ? 'no' : 'yes') : undefined}
      {...CHART_CHROME}
    >
      <SheetSection>
        {seas.fleet && walled && (
          <Row
            label={seas.fleet.name}
            value={<span className={wall ? 'text-danger' : 'text-success'}>{wall ? t('seas.closed') : t('seas.open')}</span>}
            wholeName
            data-testid="map-zone-verdict"
          />
        )}
        <Row
          label={t('seas.title')}
          value={<span className={`tabular-nums ${short(wall?.shortTitle) ? 'text-danger' : ''}`}>{pair(title?.level, row.zone.title_min)}</span>}
          data-testid="map-zone-title"
        />
        <Row
          label={t('seas.waves')}
          value={<span className={`tabular-nums ${short(wall?.shortWave) ? 'text-danger' : ''}`}>{pair(seas.fleet?.wave, row.zone.wave_min)}</span>}
          hairline={false}
          data-testid="map-zone-waves"
        />
        {fix !== '' && <p className="pt-1 text-t-caption text-ink" data-testid="map-zone-fix">{fix}</p>}
        {!seas.bite && <Hint>{t('seas.dark')}</Hint>}
        <Hint>{t('seas.howTitle')}</Hint>
        <Hint>{t('seas.howWaves')}</Hint>
        <Button variant="secondary" size="sm" className="mt-2" onClick={() => navigate('/compendium?face=seas')} data-testid="map-zone-codex">
          {t('map.allSeas')}
        </Button>
      </SheetSection>
    </Tray>
  )
}
