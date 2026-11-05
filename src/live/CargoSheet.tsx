import { useState, type ReactNode } from 'react'
import { Clip, Figure, IconDisc, Row, SheetSection, ShipTile, Skeleton, Tile, TileField, Tray, TrayTitle, type TrayDetent } from '../components/ui'
import { CHART_CHROME, GoToLink } from '../chart'
import { formatDucats } from '../lib/format'
import { hullFraction } from '../domain/fleet'
import type { CargoShipCard } from '../lib/rpc'
import { portNameOf, useWorld } from './worldStore'
import { CargoHull } from './CargoHull'
import { HullCountry } from './HullCountry'
import { useT } from '../lib/i18n'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE CARGO SHIP SHEET — one crown's cargo ship, READ-ONLY (0310, docs/CITY_CONVOYS.md section 2)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// What ./MerchantSheet.tsx is for a merchant, and only the part she has: no company, no earnings, no
// captains, no skills. MAP opens it on a tapped hull; the card is read by the caller
// (`useCargoShipCard`) because MAP asks for one card at a time. Every figure is served.

export function CargoSheet({
  card,
  line,
  onClose,
  mode,
}: {
  /** Null while the first read is out. */
  card: CargoShipCard | null
  /** The one line under her name at peek: where she is, as a merchant's. */
  line: ReactNode
  onClose: () => void
  mode?: 'docked' | 'side'
}) {
  const t = useT()
  const [detent, setDetent] = useState<TrayDetent>('peek')
  return (
    <Tray
      mode={mode}
      detent={detent}
      onDetentChange={(next) => (next === 'closed' ? onClose() : setDetent(next))}
      title={
        <TrayTitle
          name={
            card ? (
              <span className="inline-flex max-w-full items-center gap-1.5" data-testid="cargo-sheet-flag">
                <HullCountry nation={card.nation_code} compact size="title" />
                <Clip>{card.fleet.name}</Clip>
              </span>
            ) : (
              '…'
            )
          }
          line={
            <>
              {t('map.cargoShip')}
              {line ? <> · {line}</> : null}
            </>
          }
          testId="cargo-sheet-name"
        />
      }
      data-testid="cargo-sheet"
      {...CHART_CHROME}
    >
      {card ? <CargoBody card={card} /> : <Skeleton className="mt-2 h-28 w-full" />}
    </Tray>
  )
}

function CargoBody({ card }: { card: CargoShipCard }) {
  const t = useT()
  const portByCode = useWorld((s) => s.portByCode)
  const bound = card.to ?? card.fleet.port ?? card.home
  const more = card.stops_left - card.next.length
  return (
    <div data-testid="cargo-sheet-body">
      <TileField className="mt-2">
        <Tile name={t('map.funds')} figure={<Figure size="figure" value={formatDucats(card.funds)} />} data-testid="cargo-funds" />
      </TileField>
      <SheetSection surface>
        <Row
          mark={<IconDisc name="compass" />}
          label={t('map.shipment')}
          value={<GoToLink to={{ kind: 'port', code: bound }}>{portNameOf(portByCode, bound)}</GoToLink>}
          hairline={card.next.length > 0}
          data-testid="cargo-bound"
        />
        {card.next.length > 0 && (
          <Row
            mark={<IconDisc name="history" />}
            label={
              <span className="block min-w-0">
                <span className="block">{t('map.nextCities')}</span>
                <span className="block break-words text-t-caption text-ink-faint">
                  {card.next.map((code, i) => (
                    <span key={code}>
                      {i > 0 && ' → '}
                      <GoToLink to={{ kind: 'port', code }}>{portNameOf(portByCode, code)}</GoToLink>
                    </span>
                  ))}
                  {more > 0 ? ` +${more}` : ''}
                </span>
              </span>
            }
            hairline={false}
            data-testid="cargo-next"
          />
        )}
      </SheetSection>
      <SheetSection heading={t('port.ships')}>
        <div className="flex flex-col gap-2">
          {card.ships.map((s) => (
            <ShipTile
              key={s.name}
              name={s.name}
              className={t('map.cargoShip')}
              flagship={s.is_flagship}
              hull={<CargoHull size={32} />}
              hullPct={hullFraction(s)}
              crew={s.crew}
              crewMax={s.crew_max}
              // She sails with no crew by design (0308), so she is never shown short of hands.
              crewRequired={0}
              speedKn={s.speed}
              holdUsed={s.cargo_tuns}
              holdTotal={s.hold}
              testId="cargo-ship-tile"
            />
          ))}
        </div>
      </SheetSection>
    </div>
  )
}
