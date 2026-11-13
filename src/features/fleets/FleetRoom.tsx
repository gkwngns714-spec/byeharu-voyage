import { Button, Card, Note, Row } from '../../components/ui'
import { formatOfTotal } from '../../lib/format'
import type { RoomLadder } from '../../lib/rpc'
import { roomStepWord, useBuyRoom, useHouseRoom } from '../../live/houseRoom'
import { useT } from '../../lib/i18n'

// THE ROOM A COMPANY HAS, AND HOW MORE OPENS (0354, docs/FLEETS_AND_SLOTS.md section 2.2; owner row 180: "unlock slots by purchasing with gold, and some with levels").
// Every row is the server's (`world.house_room`): how many fleets and how many ships a fleet, and each step: a level of a track, or a price, open or locked.
// WHILE FLEET ROOM IS NOT LIT (`on` false) the card says so in plain words and draws NO button: a press would only be refused. Lit, the one price a press would buy carries Buy,
// and only when the purse covers it. Nothing here decides a price, a level or whether she can pay. The read, the press and the step's words are houseRoom.ts's, shared with
// the fleet's locked tiles and the New fleet page (F5).

export function FleetRoom() {
  const t = useT()
  const room = useHouseRoom()
  if (!room || !room.company) return null
  return (
    <Card title={t('fleets.room')} className="mt-4" data-testid="fleet-room">
      {!room.on && (
        <Note tone="neutral" data-testid="fleet-room-dark">
          {t('fleets.roomNotOpen')}
        </Note>
      )}
      <Ladder kind="FLEET" label={t('fleets.roomFleets')} ladder={room.fleets} on={room.on} />
      <Ladder kind="SHIP" label={t('fleets.roomShips')} ladder={room.ships} on={room.on} />
    </Card>
  )
}

function Ladder({ kind, label, ladder, on }: { kind: 'FLEET' | 'SHIP'; label: string; ladder: RoomLadder; on: boolean }) {
  const t = useT()
  const { busy, refusal, buy } = useBuyRoom(kind)

  return (
    <div className="mt-3" data-testid={`fleet-room-${kind.toLowerCase()}`}>
      <Row label={label} value={formatOfTotal(ladder.used, ladder.have)} hairline={false} data-testid="fleet-room-have" />
      {/* one short line a step: the list is the whole ladder, and a company's side card is not the place for fourteen tall rows */}
      <ul className="mt-1 flex flex-col gap-1 text-t-caption">
        {ladder.steps.map((s, i) => (
          <li key={i} className={`flex flex-wrap items-center justify-between gap-x-3 ${s.open ? 'text-ink' : 'text-ink-faint'}`} data-testid="fleet-room-step">
            <span className="tabular-nums">{roomStepWord(t, s)}</span>
            {on && s.how === 'gold' && s.next && s.can_pay ? (
              <Button variant="secondary" busy={busy} onClick={buy} data-testid="fleet-room-buy">
                {t('fleets.roomBuy')}
              </Button>
            ) : (
              <span>{t(s.open ? 'fleets.roomOpen' : 'fleets.roomLocked')}</span>
            )}
          </li>
        ))}
      </ul>
      {refusal && (
        <Note tone="danger" code={refusal.code} figures={refusal.figures}>
          {refusal.sentence}
        </Note>
      )}
    </div>
  )
}
