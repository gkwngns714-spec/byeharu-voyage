import { useMemo, useState, type ReactNode } from 'react'
import { Chip, Hint, ListPanel, Note, PageSplit, Row, seaName, seaWallAsks, seaWallFix } from '../../components/ui'
import type { SeaRow } from '../../domain/seas'
import { formatInt, formatOfTotal } from '../../lib/format'
import { properName, useLocale, useT } from '../../lib/i18n'
import { fold, foldedMatch } from '../../lib/text'
import { useFleetSeas } from '../../live/useFleetSeas'
import { useSeaConditions } from '../../live/useSeaConditions'
import { NoAnswer } from './NoAnswer'

// THE SEAS — every sea with what it asks, and whether it is open to the fleet in hand (design C3).
//
// Everything printed is served (world.sea_conditions, 0215 + 0396): the two asks, her title, the fleet's wave
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
  // HOME WATERS (0396): seas of the rank of her capital's sea never ask her title. Which seas is the server's (`home_sea`): the rank is read, never compared with hers.
  const homeRank = conditions.view?.home_sea?.title_min ?? null
  const isHome = (r: SeaRow) => homeRank !== null && r.zone.title_min === homeRank

  const rows = useMemo(() => {
    const needle = fold(query.trim())
    return seas.rows.filter((r) => foldedMatch(needle, r.zone.name, seaName(locale, { zoneName: r.zone.name }), r.zone.code))
  }, [seas.rows, query, locale])
  const walled = seas.bite && seas.judged
  const open = walled ? rows.filter((r) => r.wall === null) : rows
  const closed = walled ? rows.filter((r) => r.wall !== null) : []

  // HAVE / NEED (owner, 2026-11-15: "just tell me what i have, and what is required"): `Title 1 / 4 · Waves 12 / 30`, the ask she is
  // short of in the danger tone. Which one is short is the SERVER'S verdict (the wall's `shortTitle` / `shortWave`), never compared here;
  // hers are the wall's figures, or the face's own title and fleet waves where the sea is open.
  const fleetWave = seas.fleet?.wave ?? null
  const ask = (key: 'seas.asksTitle' | 'seas.asksWaves', have: number | null, need: number, short: boolean, which: string) => (
    <span className={short ? 'text-danger' : undefined} data-testid="sea-ask" data-ask={which} data-short={short ? 'yes' : 'no'}>
      {t(key, { n: have === null ? formatInt(need) : formatOfTotal(have, need) })}
    </span>
  )
  // An ask of 0 is no ask (it read `Waves 12 / 0`), and home waters never ask her title (0396: the row says Home waters).
  const asks = (r: SeaRow) => {
    const w = walled ? r.wall : null
    const pieces = [
      !isHome(r) && r.zone.title_min > 0 ? ask('seas.asksTitle', w?.title ?? title?.level ?? null, r.zone.title_min, w?.shortTitle === true, 'title') : null,
      r.zone.wave_min > 0 ? ask('seas.asksWaves', w?.wave ?? fleetWave, r.zone.wave_min, w?.shortWave === true, 'waves') : null,
    ].filter((p) => p !== null)
    return pieces.map((p, i) => (
      <span key={i}>
        {i > 0 && ' · '}
        {p}
      </span>
    ))
  }
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
          data-home={isHome(r) ? 'yes' : undefined}
        >
          {isHome(r) && (
            <span className="block text-t-caption text-accent" data-testid="sea-row-home">
              {t('seas.homeWaters')}
            </span>
          )}
          {r.zone.harbours !== undefined && (
            <span className="block text-t-caption text-ink-faint">{t('seas.harbours', { n: formatInt(r.zone.harbours), count: r.zone.harbours })}</span>
          )}
          {walled && r.wall && (
            <span className="block text-t-caption text-ink-muted" data-testid="sea-row-why">
              {/* the figures stand in the row's value (have / need); this line is the fix alone, or the whole ask on a world that does not say which one is short */}
              {r.wall.shortTitle === null || r.wall.shortWave === null ? seaWallAsks(locale, r.wall) : seaWallFix(locale, r.wall)}
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
      <Hint>{t('seas.how')}</Hint>
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
