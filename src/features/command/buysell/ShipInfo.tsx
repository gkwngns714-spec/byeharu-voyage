import { useEffect } from 'react'
import { CargoBar, CargoRows, Figure, Row, SheetSection, SkillTile } from '../../../components/ui'
import { fleetCargo, fleetCrew, fleetHoldBreakdown, fleetHoldTotal, fleetHoldUsed } from '../../../domain/fleet'
import { formatFixed, formatInt, formatPrice } from '../../../lib/format'
import { useT } from '../../../lib/i18n'
import type { FleetView, SkillEffect } from '../../../lib/rpc'
import { useCrewCost } from '../../../live/useCrewCost'
import { useWorld } from '../../../live/worldStore'

// THE SHIP, UNDER THE ORDERS ON BUY (owner row 233, 2026-10-27: *"in command buy, below orders i want there to be a
// ship info - cargo. crews, provision, buying related skills?"*).
//
// NOTHING HERE IS NEW: every row is a reading the game already serves, drawn by the primitive that draws it elsewhere.
//   CARGO     FleetView.free_hold over the hulls' hold (CargoBar), the goods aboard (CargoRows) — as FLEETS draws them
//   CREW      fleetCrew (domain/fleet), the same fold the Inn and FLEETS read
//   WAGES     world.crew_cost for the crew aboard (useCrewCost) — the server's sum, never a rate times a count
//   STORES    FleetView.endurance_days; PROVISIONS the water and food tuns (fleetHoldBreakdown) — they share the hold
//   SKILLS    world.skills(): the skills whose served effect prices a purchase — SPREAD (Haggling: a cut off the port's
//             spread) and TRADE_CAP (Accounting: the daily buying cap) — that a rule reads (takes_effect). None → no row.
const BUYING: readonly SkillEffect[] = ['SPREAD', 'TRADE_CAP']

export function ShipInfo({ fleet }: { fleet: FleetView }) {
  const t = useT()
  const goodByCode = useWorld((s) => s.goodByCode)
  const book = useWorld((s) => s.skills)
  const loadSkills = useWorld((s) => s.loadSkills)
  useEffect(() => {
    if (!book) void loadSkills()
  }, [book, loadSkills])

  const crew = fleetCrew(fleet)
  const wages = useCrewCost(fleet.id, null).cost
  const hold = fleetHoldBreakdown(fleet)
  const skills = book ? book.skills.filter((s) => BUYING.includes(s.effect) && s.takes_effect) : []

  return (
    <SheetSection heading={t('desk.ship')} surface data-testid="buy-ship">
      <div className="px-4 py-3">
        <CargoBar used={fleetHoldUsed(fleet)} total={fleetHoldTotal(fleet)} free={fleet.free_hold} />
      </div>
      <CargoRows
        rows={fleetCargo(fleet).map((line) => ({
          code: line.code,
          name: goodByCode[line.code]?.name ?? line.code,
          category: goodByCode[line.code]?.category ?? '',
          qty: line.qty,
        }))}
        totalTons={hold.goodsT}
        testId="buy-ship-cargo"
      />
      <Row
        label={t('fleets.crew')}
        value={<Figure value={`${formatInt(crew.aboard)}/${formatInt(crew.max)}`} tone={crew.short > 0 ? 'danger' : 'ink'} />}
        data-testid="buy-ship-crew"
      />
      {wages !== null && (
        <Row label={t('desk.wages')} value={<Figure value={formatPrice(wages.per_day)} unit={t('desk.perDay')} />} data-testid="buy-ship-wages" />
      )}
      <Row
        label={t('desk.stores')}
        value={<Figure value={formatFixed(fleet.endurance_days, 1)} unit={t('fleets.unitDays')} />}
        data-testid="buy-ship-stores"
      />
      <Row
        label={t('desk.provisions')}
        value={<Figure value={formatFixed(hold.provisionsT, 1)} unit={t('fleets.unitTons')} />}
        hairline={skills.length > 0}
        data-testid="buy-ship-provisions"
      />
      {book && skills.length > 0 && (
        <div className="px-4 pb-3" data-testid="buy-ship-skills" aria-label={t('port.skills')}>
          <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
            {skills.map((sk) => (
              <SkillTile key={sk.code} code={sk.code} name={sk.name} level={sk.level} max={book.max_level} />
            ))}
          </div>
        </div>
      )}
    </SheetSection>
  )
}
