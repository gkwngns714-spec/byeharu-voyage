import { useState, type ReactNode } from 'react'
import { Clip, IconDisc, Row, SheetSection, ShipTile, Skeleton, Tray, TrayTitle, type TrayDetent } from '../components/ui'
import { CHART_CHROME, GoToLink } from '../chart'
import { hullFraction } from '../domain/fleet'
import type { PirateShipCard } from '../lib/rpc'
import { portNameOf, useWorld } from './worldStore'
import { PirateHull } from './CargoHull'
import { AttackSection } from './AttackSection'
import { HullCountry } from './HullCountry'
import { useLocale, useT } from '../lib/i18n'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE PIRATE SHIP SHEET — one ship of the Brethren (0339, docs/WORLD_POWERS.md Part 5). Read-only, but for Attack.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// ./NavySheet.tsx for a pirate: her flag, her home, whether she is out or home, the haunt she cruises, her hull.
// MAP opens it on a tapped hull; the card is read by the caller (`usePirateShipCard`) because MAP asks for one card
// at a time. Every figure is served. Dark: no row is ever kind PIRATE, so no map ever opens this.

export function PirateSheet({
  card,
  line,
  onClose,
  mode,
}: {
  /** Null while the first read is out. */
  card: PirateShipCard | null
  /** The one line under her name at peek: where she is, as a merchant's. */
  line: ReactNode
  onClose: () => void
  mode?: 'docked' | 'side'
}) {
  const t = useT()
  const locale = useLocale()
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
              <span className="inline-flex max-w-full items-center gap-1.5" data-testid="pirate-sheet-flag">
                <HullCountry nation={card.nation_code} compact size="title" />
                <Clip>{locale === 'ko' && card.name_ko ? card.name_ko : card.fleet.name}</Clip>
              </span>
            ) : (
              '…'
            )
          }
          line={
            <>
              {t('map.pirateShip')}
              {line ? <> · {line}</> : null}
            </>
          }
          testId="pirate-sheet-name"
        />
      }
      data-testid="pirate-sheet"
      {...CHART_CHROME}
    >
      {card ? <PirateBody card={card} /> : <Skeleton className="mt-2 h-28 w-full" />}
    </Tray>
  )
}

function PirateBody({ card }: { card: PirateShipCard }) {
  const t = useT()
  const portByCode = useWorld((s) => s.portByCode)
  return (
    <div data-testid="pirate-sheet-body">
      <SheetSection surface>
        <Row
          mark={<IconDisc name="compass" />}
          label={t('map.pirateHome')}
          value={<GoToLink to={{ kind: 'port', code: card.home }}>{portNameOf(portByCode, card.home)}</GoToLink>}
          wholeName
          data-testid="pirate-home"
        />
        <Row
          mark={<IconDisc name="history" />}
          label={t('map.mission')}
          value={card.laid_up ? t('map.laidUp') : t(`map.mission_${card.mission}`)}
          hairline={card.haunt !== null}
          data-testid="pirate-mission"
        />
        {card.haunt !== null && (
          <Row
            mark={<IconDisc name="compass" />}
            label={t('map.haunt')}
            value={<GoToLink to={{ kind: 'port', code: card.haunt }}>{portNameOf(portByCode, card.haunt)}</GoToLink>}
            hairline={false}
            wholeName
            data-testid="pirate-haunt"
          />
        )}
      </SheetSection>
      <SheetSection heading={t('port.ships')}>
        <div className="flex flex-col gap-2">
          {card.ships.map((s) => (
            <ShipTile
              key={s.name}
              name={s.name}
              className={t('map.pirateShip')}
              flagship={s.is_flagship}
              hull={<PirateHull size={32} />}
              hullPct={hullFraction(s)}
              crew={s.crew}
              crewMax={s.crew_max}
              crewRequired={s.crew_required}
              speedKn={s.speed}
              holdUsed={s.cargo_tuns}
              holdTotal={s.hold}
              power={s}
              testId="pirate-ship-tile"
            />
          ))}
        </div>
      </SheetSection>
      <AttackSection card={card} />
    </div>
  )
}
