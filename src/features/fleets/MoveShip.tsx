import { useState } from 'react'
import { Button, DetailPage, FactsLine, Field, Note, Row, SheetSection } from '../../components/ui'
import { formatInt, formatKnots, formatOfTotal } from '../../lib/format'
import { cmdMoveShip } from '../../lib/rpc'
import type { FleetView, Refusal, ShipMoves } from '../../lib/rpc'
import { useWorld } from '../../live/worldStore'
import { FleetTotals } from './FleetTotals'
import { useT } from '../../lib/i18n'

// A SHIP CHANGES FLEETS (0321, docs/FLEETS_AND_SLOTS.md section 2.4). The server says where she may go (`world.ship_moves`) and judges the press (`cmd.move_ship`);
// nothing here decides. Dark, the read answers {on: false} and nothing is drawn. A fleet in another port is not shown, not greyed. The choice stands on a pop-up page,
// so a press moves nothing on the page behind it (the owner's press law).
//
// WHAT SHE SEES BEFORE THE PRESS (F5, 2026-11-11; docs/FLEETS_AND_SLOTS.md 2.5 asks for a before and after). No read serves what a fleet's totals WOULD be after a move
// (`public.fleet_totals` answers for a fleet as she stands; the wage and the slowest ship are the server's own rules), and this slice adds no migration. So the page shows what
// IS served and says so: the moving ship's own figures, the totals of the fleet she leaves, and under each fleet she may join that fleet's totals, all as they are now.
// Nothing is added up here.

type Ship = FleetView['ships'][number]

export function MoveShip({ moves, fleet, ship }: { moves: ShipMoves | null; fleet: FleetView; ship: Ship }) {
  const t = useT()
  const [open, setOpen] = useState(false)
  if (!moves?.on || (moves.targets.length === 0 && !moves.can_new)) return null
  return (
    <>
      <Button variant="secondary" className="flex-1" onClick={() => setOpen(true)} data-testid="ship-move">
        {t('fleets.move')}
      </Button>
      {open && <MovePage moves={moves} fleet={fleet} ship={ship} onClose={() => setOpen(false)} />}
    </>
  )
}

function MovePage({ moves, fleet, ship, onClose }: { moves: Extract<ShipMoves, { on: true }>; fleet: FleetView; ship: Ship; onClose: () => void }) {
  const t = useT()
  const refresh = useWorld((s) => s.refresh)
  const fleets = useWorld((s) => s.fleets)
  const [name, setName] = useState('')
  const [busy, setBusy] = useState(false)
  const [refusal, setRefusal] = useState<Refusal | null>(null)

  const go = (to: string | null, newName: string | null) => {
    if (busy) return
    setBusy(true)
    setRefusal(null)
    void (async () => {
      const r = await cmdMoveShip(ship.id, to, newName)
      setBusy(false)
      if (r.ok) {
        await refresh()
        onClose()
      } else {
        setRefusal(r.refusal)
      }
    })()
  }

  return (
    <DetailPage title={t('fleets.moveTo', { name: ship.name })} onClose={onClose} data-testid="ship-move-page">
      <SheetSection heading={t('fleets.moveShip')}>
        <FactsLine data-testid="ship-move-ship">
          <span>
            {t('fleets.attack')} <span className="tabular-nums text-ink">{formatInt(ship.attack)}</span>
          </span>
          <span>
            {t('fleets.hullSum')} <span className="tabular-nums text-ink">{formatOfTotal(ship.durability, ship.max_durability)}</span>
          </span>
          <span>
            {t('fleets.crew')} <span className="tabular-nums text-ink">{formatOfTotal(ship.crew, ship.crew_max)}</span>
          </span>
          <span className="tabular-nums text-ink">{formatKnots(ship.speed)}</span>
        </FactsLine>
      </SheetSection>
      <SheetSection heading={t('fleets.moveFrom', { name: fleet.name })}>
        <FleetTotals fleet={fleet} />
      </SheetSection>
      {moves.targets.length > 0 && (
        <SheetSection heading={t('fleets.moveInto')}>
          {moves.targets.map((f) => {
            const target = fleets.find((x) => x.id === f.id)
            return (
              <Row key={f.id} label={f.empty ? t('fleets.moveEmpty', { name: f.name }) : f.name} chevron onClick={() => go(f.id, null)} data-testid="ship-move-target">
                {target && <FleetTotals fleet={target} />}
              </Row>
            )
          })}
        </SheetSection>
      )}
      <p className="mt-3 text-t-caption text-ink-faint" data-testid="ship-move-now">
        {t('fleets.moveNowNote')}
      </p>
      {moves.can_new && (
        <div className="mt-4">
          <Field
            icon={null}
            value={name}
            maxLength={24}
            placeholder={t('fleets.moveNewName')}
            onChange={(e) => setName(e.target.value)}
            aria-label={t('fleets.moveNewName')}
            data-testid="ship-move-name"
          />
          <Button className="mt-3 w-full" busy={busy} disabled={name.trim().length < 3} onClick={() => go(null, name.trim())} data-testid="ship-move-new">
            {t('fleets.moveNew')}
          </Button>
        </div>
      )}
      {refusal && (
        <Note tone="danger" code={refusal.code} figures={refusal.figures}>
          {refusal.sentence}
        </Note>
      )}
    </DetailPage>
  )
}
