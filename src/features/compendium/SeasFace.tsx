import { useMemo, useState, type ReactNode } from 'react'
import { Chip, Hint, ListPanel, Note, PageSplit, Row, seaName, seaWallAsks, seaWallFix } from '../../components/ui'
import type { SeaRow } from '../../domain/seas'
import { formatInt } from '../../lib/format'
import { properName, useLocale, useT } from '../../lib/i18n'
import { fold, foldedMatch } from '../../lib/text'
import { useFleetSeas } from '../../live/useFleetSeas'
import { useSeaConditions } from '../../live/useSeaConditions'
import { NoAnswer } from './NoAnswer'

// THE SEAS — every sea with what it asks, and whether it is open to the fleet in hand (design C3).
//
// Everything printed is served (world.sea_conditions, 0215 + 0391): the two asks, her title, the fleet's wave
// resistance, and for each sea that refuses her the rule's own figures. A closed sea says what it asks that she does
// not hold and what to do, in the one wording (components/ui/seaWallWords.ts). While the sea conditions are dark the
// face lists what each sea asks and calls none closed.

export function SeasFace({ query, search }: { query: string; search: ReactNode }) {
  const t = useT()
  const locale = useLocale()
  const conditions = useSeaConditions()
  const [picked, setPicked] = useState<string | null | undefined>(undefined)
  const seas = useFleetSeas(picked)
  const fleets = conditions.view?.fleets ?? []
  const title = conditions.view?.title ?? null

  const rows = useMemo(() => {
    const needle = fold(query.trim())
    return seas.rows.filter((r) => foldedMatch(needle, r.zone.name, seaName(locale, { zoneName: r.zone.name }), r.zone.code))
  }, [seas.rows, query, locale])
  const walled = seas.bite && seas.judged
  const open = walled ? rows.filter((r) => r.wall === null) : rows
  const closed = walled ? rows.filter((r) => r.wall !== null) : []

  const asks = (r: SeaRow) => `${t('seas.asksTitle', { n: formatInt(r.zone.title_min) })} · ${t('seas.asksWaves', { n: formatInt(r.zone.wave_min) })}`
  const list = (items: SeaRow[]) =>
    items.length === 0 ? (
      <NoAnswer />
    ) : (
      items.map((r) => (
        <Row
          key={r.zone.code}
          label={seaName(locale, { zoneName: r.zone.name })}
          value={<span className="whitespace-nowrap text-t-caption text-ink-muted">{asks(r)}</span>}
          tone={r.wall && walled ? 'muted' : 'default'}
          hairline={false}
          wholeName
          data-testid="sea-row"
          data-sea={r.zone.code}
          data-open={walled ? (r.wall === null ? 'yes' : 'no') : undefined}
        >
          {r.zone.harbours !== undefined && (
            <span className="block text-t-caption text-ink-faint">{t('seas.harbours', { n: formatInt(r.zone.harbours), count: r.zone.harbours })}</span>
          )}
          {walled && r.wall && (
            <span className="block text-t-caption text-ink-muted" data-testid="sea-row-why">
              {[seaWallAsks(locale, r.wall), seaWallFix(locale, r.wall)].filter((s) => s !== '').join(' ')}
            </span>
          )}
        </Row>
      ))
    )

  const head = (
    <div className="min-w-0" data-testid="seas-head">
      <Note tone={seas.bite ? 'accent' : 'neutral'} data-testid="seas-state" data-bite={seas.bite ? 'yes' : 'no'}>
        {seas.bite ? t('seas.lit') : t('seas.dark')}
      </Note>
      {fleets.length > 1 && (
        <div className="mt-2 flex flex-wrap gap-2" role="group" aria-label={t('seas.fleet')} data-testid="seas-fleets">
          {fleets.map((f) => (
            <Chip key={f.id} on={seas.fleet?.id === f.id} onClick={() => setPicked(f.id)} className="break-words">
              {f.name}
            </Chip>
          ))}
        </div>
      )}
      {title && (
        <Row
          label={t('seas.yourTitle')}
          value={`${formatInt(title.level)}${title.name ? ` · ${properName('title', title.name, title.name)}` : ''}`}
          data-testid="seas-title"
        />
      )}
      {seas.fleet ? (
        <Row label={t('seas.fleetWaves')} value={seas.fleet.wave === null ? '—' : formatInt(seas.fleet.wave)} hairline={false} data-testid="seas-waves">
          <span className="block break-words text-t-caption text-ink-faint">{seas.fleet.name}</span>
        </Row>
      ) : (
        title && <Hint>{t('seas.noFleet')}</Hint>
      )}
      <Hint>{t('seas.howTitle')}</Hint>
      <Hint>{t('seas.howWaves')}</Hint>
    </div>
  )

  return (
    <PageSplit
      data-testid="sea-rows"
      main={
        <ListPanel
          look="card"
          columns="fit"
          title={walled ? t('seas.open') : t('seas.seas')}
          count={formatInt(open.length)}
          trailing={search}
          controls={head}
          data-testid="seas-open"
        >
          {list(open)}
        </ListPanel>
      }
      side={
        walled ? (
          <ListPanel look="card" title={t('seas.closed')} count={formatInt(closed.length)} data-testid="seas-closed">
            {list(closed)}
          </ListPanel>
        ) : null
      }
    />
  )
}
