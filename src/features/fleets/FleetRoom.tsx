import { Button, Card, Note, Row } from '../../components/ui'
import { formatInt, formatOfTotal } from '../../lib/format'
import type { RoomLadder } from '../../lib/rpc'
import { lockedSteps, roomStepWord, useBuyRoom, useHouseRoom } from '../../live/houseRoom'
import { useT } from '../../lib/i18n'

// THE ROOM A COMPANY HAS, AND HOW MORE OPENS (0354, docs/FLEETS_AND_SLOTS.md section 2.2; owner row 180: "unlock slots by purchasing with gold, and some with levels").
// Every row is the server's (`world.house_room`): how many fleets and how many ships a fleet, and each step: a level of a track, or a price, open or locked.
// WHILE FLEET ROOM IS NOT LIT (`on` false) the card says so in plain words and draws NO button: a press would only be refused. Lit, the one price a press would buy carries Buy,
// and only when the purse covers it. Nothing here decides a price, a level or whether she can pay. The read, the press and the step's words are houseRoom.ts's, shared with
// the fleet's locked tiles and the New fleet page (F5).
//
// TWO LINES A KIND, NOT THE LADDER (2026-11-22 second play-test: the card was a list of every rung, "Trading level 1 / 3", "Trading level 1 / 6",
// "Price 60,000", "Price 1,000,000", and read as raw data). Each kind is what she has against what she may have and the most there is ("1 / 2 · max 6"), then
// the NEXT place only: the level that opens it or the price that buys it (`lockedSteps`, the same reading the locked tiles and New fleet use), with Buy on the price.

export function FleetRoom() {
  const t = useT()
  const room = useHouseRoom()
  if (!room || !room.company) return null
  return (
    <Card icon="anchor" title={t('fleets.room')} className="mt-4" data-testid="fleet-room">
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
  const { levels, prices } = lockedSteps(ladder)
  const level = levels[0]
  const price = prices[0]
  const levelWord = level ? roomStepWord(t, level, ladder.level) : null
  const priceWord = price ? roomStepWord(t, price) : null

  return (
    <div className="mt-3" data-testid={`fleet-room-${kind.toLowerCase()}`}>
      <Row
        label={label}
        value={`${formatOfTotal(ladder.used, ladder.have)} · ${t('fleets.roomTop', { n: formatInt(ladder.top) })}`}
        hairline={false}
        data-testid="fleet-room-have"
      />
      {(levelWord || priceWord) && (
        <div className="mt-1 flex flex-wrap items-center justify-between gap-x-3 gap-y-1 text-t-caption text-ink-muted" data-testid="fleet-room-next">
          {/* one text: "Next:" and its step wrap as one line of words (two nodes read as one standing on the other) */}
          <span className="tabular-nums">
            {`${t('fleets.roomNext')} ${levelWord && priceWord ? t('fleets.roomEither', { a: levelWord, b: priceWord }) : (levelWord ?? priceWord)}`}
          </span>
          {on && price?.next && price.can_pay && (
            <Button variant="secondary" busy={busy} onClick={buy} data-testid="fleet-room-buy">
              {t('fleets.roomBuy')}
            </Button>
          )}
        </div>
      )}
      {refusal && (
        <Note tone="danger" code={refusal.code} figures={refusal.figures}>
          {refusal.sentence}
        </Note>
      )}
    </div>
  )
}
