import { useState } from 'react'
import { Button, DetailPage, Field, Note, Row } from '../../components/ui'
import { cmdMoveShip } from '../../lib/rpc'
import type { FleetView, Refusal, ShipMoves } from '../../lib/rpc'
import { useWorld } from '../../live/worldStore'
import { useT } from '../../lib/i18n'

// A SHIP CHANGES FLEETS (0321, docs/FLEETS_AND_SLOTS.md section 2.4). The server says where she may go (`world.ship_moves`) and judges the press (`cmd.move_ship`);
// nothing here decides. Dark, the read answers {on: false} and nothing is drawn. A fleet in another port is not shown, not greyed. The choice stands on a pop-up page,
// so a press moves nothing on the page behind it (the owner's press law).

type Ship = Pick<FleetView['ships'][number], 'id' | 'name'>

export function MoveShip({ moves, ship }: { moves: ShipMoves | null; ship: Ship }) {
  const t = useT()
  const [open, setOpen] = useState(false)
  if (!moves?.on || (moves.targets.length === 0 && !moves.can_new)) return null
  return (
    <>
      <Button size="sm" variant="secondary" onClick={() => setOpen(true)} data-testid="ship-move">
        {t('fleets.move')}
      </Button>
      {open && <MovePage moves={moves} ship={ship} onClose={() => setOpen(false)} />}
    </>
  )
}

function MovePage({ moves, ship, onClose }: { moves: Extract<ShipMoves, { on: true }>; ship: Ship; onClose: () => void }) {
  const t = useT()
  const refresh = useWorld((s) => s.refresh)
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
      {moves.targets.map((f) => (
        <Row key={f.id} label={f.empty ? t('fleets.moveEmpty', { name: f.name }) : f.name} chevron onClick={() => go(f.id, null)} data-testid="ship-move-target" />
      ))}
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
