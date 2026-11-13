import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Button, DetailPage, Field, IconDisc, Note, Row, SheetSection } from '../../components/ui'
import { cmdMoveShip } from '../../lib/rpc'
import type { FleetView, Refusal } from '../../lib/rpc'
import { yardHref } from '../../live/cityFaces'
import { companyRoom, lockedSteps, roomStepWord, useBuyRoom, useHouseRoom, type CompanyRoom } from '../../live/houseRoom'
import { useWorld } from '../../live/worldStore'
import { useShipMoves } from './useShipMoves'
import { useT } from '../../lib/i18n'

// A NEW FLEET, FROM THE FLEETS PAGE ITSELF (F5, 2026-11-11; owner rows 180 and 316: "create multiple fleet... assign multiple ships"). Until now the only way to a second
// fleet was inside a ship's Move pop-up. This is the same door (`cmd.move_ship` with a new name: no new server door), reached from the list: a row "New fleet" under her
// fleets, and a page on which she picks the ship that leads it, names it and presses once.
//
// ── THE PAGE SAYS THE NEXT STEP, WHATEVER STANDS IN THE WAY ────────────────────────────────────
//   · one ship in the whole company: a second ship comes from a build yard, with the press that goes there;
//   · no room for another fleet (`world.house_room`, fleets): the level that opens the next one, and the price with its Buy when the purse covers it;
//   · room and ships: every ship of a fleet of two or more that the SERVER says may found a fleet (`world.ship_moves`, `can_new`); a fleet that may not gives its reason
//     in one line (docked, no orders running).
// A fleet of one ship is not offered: moving her only ship would leave that fleet empty (the Move press on a tile still allows it).
//
// ── WHILE FLEET ROOM IS NOT LIT ────────────────────────────────────────────────────────────────
// The row is a line, not a button: "New fleet · Not open yet". A press would only be refused (E_NOT_IN_USE), so none is drawn.
//
// ── THE PRESS LAW ──────────────────────────────────────────────────────────────────────────────
// Picking a ship lights her row and nothing else: the name field and the button are on the page from the start, so no box moves. The page is a `DetailPage`, a fixed layer
// over the list, so the list behind keeps its boxes too.

export function NewFleet() {
  const t = useT()
  const room = companyRoom(useHouseRoom())
  const [open, setOpen] = useState(false)
  if (!room) return null
  if (!room.on) {
    return (
      <Row
        mark={<IconDisc name="plus" tone="muted" />}
        label={t('fleets.moveNew')}
        value={<span className="text-t-caption">{t('fleets.roomNotOpen')}</span>}
        tone="muted"
        hairline={false}
        data-testid="fleet-new-dark"
      />
    )
  }
  return (
    <>
      <Row mark={<IconDisc name="plus" tone="accent" />} label={t('fleets.moveNew')} chevron tone={open ? 'accent' : 'default'} onClick={() => setOpen(true)} hairline={false} data-testid="fleet-new" />
      {open && <NewFleetPage room={room} onClose={() => setOpen(false)} />}
    </>
  )
}

function NewFleetPage({ room, onClose }: { room: CompanyRoom; onClose: () => void }) {
  const t = useT()
  const fleets = useWorld((s) => s.fleets)
  const hulls = fleets.reduce((n, f) => n + f.ships.length, 0)
  const full = room.fleets.used >= room.fleets.have
  return (
    <DetailPage title={t('fleets.moveNew')} onClose={onClose} data-testid="fleet-new-page">
      {hulls < 2 ? <NeedShip fleets={fleets} /> : full ? <NeedRoom room={room} /> : <PickLead fleets={fleets} onDone={onClose} />}
    </DetailPage>
  )
}

/** One ship in the company: the second comes from a build yard. The press goes to the HQ of the port a fleet of hers lies in, its Port place open. */
function NeedShip({ fleets }: { fleets: readonly FleetView[] }) {
  const t = useT()
  const navigate = useNavigate()
  const port = fleets.find((f) => f.port !== null)?.port ?? null
  return (
    <Note
      tone="neutral"
      action={
        <Button variant="secondary" onClick={() => navigate(yardHref(port))} data-testid="fleet-new-yard">
          {t('town.f_building_yard')}
        </Button>
      }
      data-testid="fleet-new-need-ship"
    >
      {t('fleets.newNeedShip')}
    </Note>
  )
}

/** No room for another fleet: the next level rung, and the next price with its Buy. Both are the server's rows. */
function NeedRoom({ room }: { room: CompanyRoom }) {
  const t = useT()
  const { busy, refusal, buy } = useBuyRoom('FLEET')
  const { levels, prices } = lockedSteps(room.fleets)
  const level = levels[0]
  const price = prices[0]
  if (!level && !price) {
    return (
      <Note tone="neutral" data-testid="fleet-new-top">
        {t('fleets.newTop')}
      </Note>
    )
  }
  return (
    <div data-testid="fleet-new-need-room">
      <p className="text-t-body text-ink-muted">{t('fleets.newNeedRoom')}</p>
      {level && <Row label={roomStepWord(t, level)} hairline={price !== undefined} data-testid="fleet-new-level" />}
      {price && (
        <Row
          label={<span className="tabular-nums">{roomStepWord(t, price)}</span>}
          value={
            price.next && price.can_pay ? (
              <Button variant="primary" busy={busy} onClick={buy} data-testid="fleet-new-buy">
                {t('fleets.roomBuy')}
              </Button>
            ) : (
              <span className="text-t-caption text-ink-faint" data-testid="fleet-new-short">
                {t('fleets.roomShort')}
              </span>
            )
          }
          hairline={false}
          data-testid="fleet-new-price"
        />
      )}
      {refusal && (
        <Note tone="danger" code={refusal.code} figures={refusal.figures}>
          {refusal.sentence}
        </Note>
      )}
    </div>
  )
}

/** Pick the lead ship, name the fleet, press once. */
function PickLead({ fleets, onDone }: { fleets: readonly FleetView[]; onDone: () => void }) {
  const t = useT()
  const refresh = useWorld((s) => s.refresh)
  const [shipId, setShipId] = useState<string | null>(null)
  const [name, setName] = useState('')
  const [busy, setBusy] = useState(false)
  const [refusal, setRefusal] = useState<Refusal | null>(null)
  const from = fleets.filter((f) => f.status === 'DOCKED' && f.ships.length >= 2)

  const make = () => {
    if (busy || shipId === null) return
    setBusy(true)
    setRefusal(null)
    void (async () => {
      const r = await cmdMoveShip(shipId, null, name.trim())
      setBusy(false)
      if (r.ok) {
        await refresh()
        onDone()
      } else {
        setRefusal(r.refusal)
      }
    })()
  }

  if (from.length === 0) {
    return (
      <Note tone="neutral" data-testid="fleet-new-need-dock">
        {t('fleets.newNeedDock')}
      </Note>
    )
  }
  return (
    <div data-testid="fleet-new-pick">
      <p className="text-t-body text-ink-muted">{t('fleets.newPickFirst')}</p>
      {from.map((f) => (
        <LeadChoices key={f.id} fleet={f} picked={shipId} onPick={setShipId} />
      ))}
      <div className="mt-4">
        <Field
          icon={null}
          value={name}
          maxLength={24}
          placeholder={t('fleets.moveNewName')}
          onChange={(e) => setName(e.target.value)}
          aria-label={t('fleets.moveNewName')}
          data-testid="fleet-new-name"
        />
        <Button variant="primary" className="mt-3 w-full" busy={busy} disabled={shipId === null || name.trim().length < 3} onClick={make} data-testid="fleet-new-make">
          {t('fleets.newMake')}
        </Button>
      </div>
      {refusal && (
        <Note tone="danger" code={refusal.code} figures={refusal.figures}>
          {refusal.sentence}
        </Note>
      )}
    </div>
  )
}

/** One fleet's ships as choices, when the server says a ship of hers may found a fleet; otherwise the one line that says what she waits on. */
function LeadChoices({ fleet, picked, onPick }: { fleet: FleetView; picked: string | null; onPick: (shipId: string) => void }) {
  const t = useT()
  const moves = useShipMoves(fleet.id)
  if (moves === null) return null
  return (
    <SheetSection heading={t('fleets.moveFrom', { name: fleet.name })} data-testid="fleet-new-from">
      {moves.on && moves.can_new ? (
        fleet.ships.map((ship, i) => (
          <Row
            key={ship.id}
            mark={<IconDisc name="ship" tone={picked === ship.id ? 'accent' : 'muted'} />}
            label={ship.name}
            value={<span className="text-t-caption text-ink-muted">{ship.class}</span>}
            tone={picked === ship.id ? 'accent' : 'default'}
            onClick={() => onPick(ship.id)}
            hairline={i < fleet.ships.length - 1}
            data-testid="fleet-new-ship"
          />
        ))
      ) : (
        <Row label={t('fleets.newNeedDock')} tone="muted" hairline={false} data-testid="fleet-new-busy" />
      )}
    </SheetSection>
  )
}
