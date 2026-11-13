import { Button, Note, ShipTile, Tile, TileField } from '../../components/ui'
import { formatInt } from '../../lib/format'
import type { FleetView } from '../../lib/rpc'
import { hullFraction, shipHoldUsed } from '../../domain/fleet'
import { companyRoom, lockedSteps, roomStepWord, useBuyRoom, useHouseRoom, type CompanyRoom } from '../../live/houseRoom'
import { MoveShip } from './MoveShip'
import { useShipMoves } from './useShipMoves'
import { useT } from '../../lib/i18n'
// HER HULLS, AS TILES — what an eight-column table was.
//
// The table (Ship · Class · Hull · Crew · Speed · Hold · Load · Free) was 8 facts wide in a 358px
// box, sheared at CREW, and printed "Swipe the table for the rest." under itself. A tile carries
// the same reading in the order a captain asks it: who she is, what she is, how sound (the bar),
// how many hands and how much room. Load and Free were Hold twice, so there is one hold figure.
//
// ── WHAT IS NOT DRAWN ──────────────────────────────────────────────────────────────────────────
// `GAIVOTA — FITTED / Nothing mounted. She sails as the shipwright rated her. / rig 0/1 · weapon
// 0/1 · ground-tackle 0/1 · 3 cabin(s)` — an empty state printed as a paragraph, per hull, and a
// slot count for cabins that hold nothing yet (docs/OWNER_REQUESTS.md row 68). What IS mounted is
// a fact and is printed, one caption line, only on a hull that carries something. Mounting one is
// the FIT verb on COMMAND; this face reads.

// THE TILE ITSELF is the design system's `ShipTile` since 2026-10-08 (a merchant's sheet prints the
// same hull); what is DERIVED — the hull fraction and the tuns in use — stays here, through
// domain/fleet, because the design system knows nothing above it.
//
// ── HER SEVEN PLACES (F5, 2026-11-11; owner rows 180 and 316: "assign multiple ships (total of 7)", "unlock slots by purchasing with gold, and some with levels") ──────
// After her ships stand the places she has not filled, up to the top the server serves (`world.house_room`, ships): an EMPTY place for each ship she has room for now, then a
// LOCKED place for each one still shut, saying how it opens: the level rung and the price that are next in line for it. The first locked place carries the one Buy, only
// while fleet room is lit and only when the purse covers the price (the server's `next` and `can_pay`); dark, a locked place says "Not open yet" and nothing can be pressed.
// The room is the COMPANY's, shared by every fleet, so a Buy here opens a place in all of them. Levels and bought steps add up, so the Nth locked place may open sooner than
// its own line says (a level and a price together); the tiles are read again after every step.
//
// ── TWO PRESSES ON A SHIP ──────────────────────────────────────────────────────────────────────
// Stats opens her whole sheet (live/ShipPanel, mounted by FleetsScreen over this page; closing it gives this page back). Move is MoveShip's, drawn only where the server
// offers a move. Both stand at the tile's foot, inside the tile, so every tile is one cell of the field.
export function FleetShips({ fleet, onOpenShip }: { fleet: FleetView; onOpenShip: (shipId: string) => void }) {
  const t = useT()
  const moves = useShipMoves(fleet.id)
  const room = companyRoom(useHouseRoom())
  return (
    <>
      {room && (
        <p className="mb-2 text-t-caption text-ink-muted" data-testid="fleet-places">
          {t('fleets.places', { used: formatInt(fleet.ships.length), have: formatInt(room.ships.have), top: formatInt(room.ships.top) })}
        </p>
      )}
      <TileField data-testid="fleet-tiles">
        {fleet.ships.map((ship) => (
          <ShipTile
            key={ship.id}
            name={ship.name}
            className={ship.class}
            flagship={ship.is_flagship}
            hullPct={hullFraction(ship)}
            crew={ship.crew}
            crewMax={ship.crew_max}
            crewRequired={ship.crew_required}
            speedKn={ship.speed}
            holdUsed={shipHoldUsed(ship)}
            holdTotal={ship.hold}
            fittings={ship.fittings}
            power={ship}
          >
            <span className="mt-auto flex flex-wrap gap-2 pt-1">
              <Button variant="secondary" className="flex-1" onClick={() => onOpenShip(ship.id)} data-testid="ship-stats">
                {t('fleets.shipStats')}
              </Button>
              <MoveShip moves={moves} fleet={fleet} ship={ship} />
            </span>
          </ShipTile>
        ))}
        {room && <Places room={room} ships={fleet.ships.length} />}
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
