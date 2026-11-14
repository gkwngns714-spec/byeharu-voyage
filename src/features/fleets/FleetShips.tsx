import { Button, CargoBar, Clip, FactsLine, IconDisc, Note, Row, Tile, TileField } from '../../components/ui'
import { formatInt } from '../../lib/format'
import type { FleetView } from '../../lib/rpc'
import { hullFraction, shipHoldFree, shipHoldUsed } from '../../domain/fleet'
import { companyRoom, lockedSteps, roomStepWord, useBuyRoom, useHouseRoom, type CompanyRoom } from '../../live/houseRoom'
import { HullGauge } from './HullGauge'
import { useT } from '../../lib/i18n'

// HER SHIPS, ONE ROW EACH — the owner, 2026-11-14: *"in fleets, when pressed a fleet, show only ships, then when i press the ship, show
// cargo and supplies."*
//
// A pressed fleet used to open ships, cargo, supplies, totals, orders and room at once, each ship a tile with eleven figures and two
// buttons. Now the fleet's page is THIS list and nothing above it: a ship is one `Row` on the pattern her fleet's own row set
// (FleetsScreen.FleetRow) — her name whole, her class beside it, and the two figures that tell ships apart at a glance: how sound the
// hull is and how full the hold is. A press opens her own page (FleetShipPage.tsx: cargo, supplies, Stats, Move).
//
// ── WHAT LEFT THE ROW, AND WHERE IT WENT ───────────────────────────────────────────────────────
// Crew, speed, power and what is mounted: her sheet (Stats, on her page) prints all of them. Stats and Move: her page. The empty and
// locked places: the fleet's More page (`FleetPlaces` below), with the rest of what belongs to the fleet as a whole.
export function FleetShips({ fleet, openShipId, onOpenShip }: { fleet: FleetView; /** Her page is up: the row reads `accent`. */ openShipId: string | null; onOpenShip: (shipId: string) => void }) {
  const t = useT()
  return (
    <div data-testid="fleet-ship-rows">
      {fleet.ships.map((ship, i) => (
        <Row
          key={ship.id}
          mark={<IconDisc name="ship" tone={ship.is_flagship ? 'accent' : 'muted'} label={ship.is_flagship ? t('ui.flagship') : undefined} />}
          /* THE NAME IS WHOLE (`Clip` without `cut` turns only at a space and never trims); her class drops under it when the two do not fit one line. */
          label={
            <span className="flex flex-wrap items-baseline justify-between gap-x-3">
              <Clip className="max-w-full text-t-body font-semibold" data-testid="fleet-ship-name">{ship.name}</Clip>
              <span className="min-w-0 max-w-full text-t-label text-ink-muted">{ship.class}</span>
            </span>
          }
          chevron
          tone={openShipId === ship.id ? 'accent' : 'default'}
          onClick={() => onOpenShip(ship.id)}
          hairline={i < fleet.ships.length - 1}
          data-testid="fleet-ship-row"
        >
          {/* the same line her fleet's row draws: the hull gauge, then the one cargo gauge of the game on its own line on a phone */}
          <FactsLine data-testid="fleet-ship-row-bars">
            <HullGauge fraction={hullFraction(ship)} label={t('ui.hullOf', { name: ship.name })} />
            <CargoBar used={shipHoldUsed(ship)} total={ship.hold} free={shipHoldFree(ship)} className="min-w-48 grow basis-full sm:basis-auto" />
          </FactsLine>
        </Row>
      ))}
    </div>
  )
}

// ── HER SEVEN PLACES (F5, 2026-11-11; owner rows 180 and 316: "assign multiple ships (total of 7)", "unlock slots by purchasing with gold, and some with levels") ──────
// The places she has not filled, up to the top the server serves (`world.house_room`, ships): an EMPTY place for each ship she has room for now, then a
// LOCKED place for each one still shut, saying how it opens: the level rung and the price that are next in line for it. The first locked place carries the one Buy, only
// while fleet room is lit and only when the purse covers the price (the server's `next` and `can_pay`); dark, a locked place says "Not open yet" and nothing can be pressed.
// The room is the COMPANY's, shared by every fleet, so a Buy here opens a place in all of them. Levels and bought steps add up, so the Nth locked place may open sooner than
// its own line says (a level and a price together); the tiles are read again after every step.
// Since 2026-11-14 they stand on the fleet's More page (FleetMore.tsx), not among her ships: a place is room, and the fleet's page is her ships only.
export function FleetPlaces({ fleet }: { fleet: FleetView }) {
  const t = useT()
  const room = companyRoom(useHouseRoom())
  if (!room) return null
  return (
    <>
      <p className="mb-2 text-t-caption text-ink-muted" data-testid="fleet-places">
        {t('fleets.places', { used: formatInt(fleet.ships.length), have: formatInt(room.ships.have), top: formatInt(room.ships.top) })}
      </p>
      <TileField data-testid="fleet-tiles">
        <Places room={room} ships={fleet.ships.length} />
      </TileField>
    </>
  )
}
/** The places after her ships: the empty ones, then the locked ones with how each opens. */
function Places({ room, ships }: { room: CompanyRoom; ships: number }) {
  const t = useT()
  const { busy, refusal, buy } = useBuyRoom('SHIP')
  const ladder = room.ships
  const empty = Math.max(0, ladder.have - ships)
  const locked = Math.max(0, ladder.top - Math.max(ladder.have, ships))
  const { levels, prices } = lockedSteps(ladder)
  return (
    <>
      {Array.from({ length: empty }, (_, i) => (
        <Tile key={`empty-${i}`} name={t('fleets.placeEmpty')} meta={t('fleets.placeEmptyLine')} className="min-h-0! border-dashed border-edge!" data-testid="fleet-place-empty" />
      ))}
      {Array.from({ length: locked }, (_, i) => {
        const level = levels[i]
        const price = prices[i]
        return (
          <Tile key={`locked-${i}`} name={t('fleets.roomLocked')} state="muted" className="min-h-0!" data-testid="fleet-place-locked">
            {room.on ? (
              <span className="flex flex-col items-start gap-1 text-t-caption" data-testid="fleet-place-how">
                {level && <span>{roomStepWord(t, level)}</span>}
                {price && <span className="tabular-nums">{roomStepWord(t, price)}</span>}
                {price?.next &&
                  (price.can_pay ? (
                    <Button variant="secondary" busy={busy} onClick={buy} data-testid="fleet-place-buy">
                      {t('fleets.roomBuy')}
                    </Button>
                  ) : (
                    <span data-testid="fleet-place-short">{t('fleets.roomShort')}</span>
                  ))}
              </span>
            ) : (
              <span className="text-t-caption" data-testid="fleet-place-dark">
                {t('fleets.roomNotOpen')}
              </span>
            )}
          </Tile>
        )
      })}
      {refusal && (
        <Note tone="danger" code={refusal.code} figures={refusal.figures} className="col-span-full">
          {refusal.sentence}
        </Note>
      )}
    </>
  )
}
