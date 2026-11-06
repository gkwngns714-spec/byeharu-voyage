import { useState, type ReactNode } from 'react'
import { Clip, IconDisc, Row, SheetSection, ShipTile, Skeleton, Tray, TrayTitle, type TrayDetent } from '../components/ui'
import { CHART_CHROME, GoToLink } from '../chart'
import { hullFraction } from '../domain/fleet'
import type { NavyShipCard } from '../lib/rpc'
import { portNameOf, useWorld } from './worldStore'
import { NavyHull } from './CargoHull'
import { AttackSection } from './AttackSection'
import { HullCountry } from './HullCountry'
import { useT } from '../lib/i18n'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE NAVY SHIP SHEET — one crown's navy ship (0331, docs/WORLD_POWERS.md Part 6). Read-only, but for Attack (0333).
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// ./CargoSheet.tsx for a warship: her country, her station, her duty, where she is bound, the stops of
// her patrol, her hull. MAP opens it on a tapped hull; the card is read by the caller (`useNavyShipCard`)
// because MAP asks for one card at a time. Every figure is served. Dark: no row is ever kind NAVY, so no
// map ever opens this.

export function NavySheet({
  card,
  line,
  onClose,
  mode,
}: {
  /** Null while the first read is out. */
  card: NavyShipCard | null
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
              <span className="inline-flex max-w-full items-center gap-1.5" data-testid="navy-sheet-flag">
                <HullCountry nation={card.nation_code} compact size="title" />
                <Clip>{card.fleet.name}</Clip>
              </span>
            ) : (
              '…'
            )
          }
          line={
            <>
              {t('map.navyShip')}
              {line ? <> · {line}</> : null}
            </>
          }
          testId="navy-sheet-name"
        />
      }
      data-testid="navy-sheet"
      {...CHART_CHROME}
    >
      {card ? <NavyBody card={card} /> : <Skeleton className="mt-2 h-28 w-full" />}
    </Tray>
  )
}

function NavyBody({ card }: { card: NavyShipCard }) {
  const t = useT()
  const portByCode = useWorld((s) => s.portByCode)
  return (
    <div data-testid="navy-sheet-body">
      <SheetSection surface>
        <Row
          mark={<IconDisc name="compass" />}
          label={t('map.station')}
          value={<GoToLink to={{ kind: 'port', code: card.station }}>{portNameOf(portByCode, card.station)}</GoToLink>}
          data-testid="navy-station"
        />
        <Row
          mark={<IconDisc name="history" />}
          label={t('map.mission')}
          value={card.laid_up ? t('map.laidUp') : t(`map.mission_${card.mission}`)}
          hairline={card.next.length > 0}
          data-testid="navy-mission"
        />
        {card.next.length > 0 && (
          <Row
            mark={<IconDisc name="compass" />}
            label={
              <span className="block min-w-0">
                <span className="block">{t('map.nextCities')}</span>
                <span className="block break-words text-t-caption text-ink-faint">
                  {card.next.map((code, i) => (
                    <span key={`${code}-${i}`}>
                      {i > 0 && ' → '}
                      <GoToLink to={{ kind: 'port', code }}>{portNameOf(portByCode, code)}</GoToLink>
                    </span>
                  ))}
                </span>
              </span>
            }
            hairline={false}
            data-testid="navy-next"
          />
        )}
      </SheetSection>
      <SheetSection heading={t('port.ships')}>
        <div className="flex flex-col gap-2">
          {card.ships.map((s) => (
            <ShipTile
              key={s.name}
              name={s.name}
              className={t('map.navyShip')}
              flagship={s.is_flagship}
              hull={<NavyHull size={32} />}
              hullPct={hullFraction(s)}
              crew={s.crew}
              crewMax={s.crew_max}
              crewRequired={s.crew_required}
              speedKn={s.speed}
              holdUsed={s.cargo_tuns}
              holdTotal={s.hold}
              testId="navy-ship-tile"
            />
          ))}
        </div>
      </SheetSection>
      <AttackSection card={card} />
    </div>
  )
}
