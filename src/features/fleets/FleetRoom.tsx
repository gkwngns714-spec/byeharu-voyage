import type { ReactNode } from 'react'
import { Bar, Button, Card, Icon, Note } from '../../components/ui'
import { formatDucats, formatInt, formatOfTotal } from '../../lib/format'
import type { RoomLadder } from '../../lib/rpc'
import { lockedSteps, roomStepWord, useBuyRoom, useHouseRoom } from '../../live/houseRoom'
import { useT } from '../../lib/i18n'
import { ShipPicture } from '../../live/ShipPicture'

// THE ROOM A COMPANY HAS, AND HOW MORE OPENS (0354, docs/FLEETS_AND_SLOTS.md section 2.2; owner row 180: "unlock slots by purchasing with gold, and some with levels").
// Every row is the server's (`world.house_room`): how many fleets and how many ships a fleet, and each step: a level of a track, or a price, open or locked.
// WHILE FLEET ROOM IS NOT LIT (`on` false) the card says so in plain words and draws NO button: a press would only be refused. Lit, the one price a press would buy carries Buy,
// and only when the purse covers it. Nothing here decides a price, a level or whether she can pay. The read, the press and the step's words are houseRoom.ts's, shared with
// the fleet's locked tiles and the New fleet page (F5).
//
// TWO LINES A KIND, NOT THE LADDER (2026-11-22 second play-test: the card was a list of every rung, "Trading level 1 / 3", "Trading level 1 / 6",
// "Price 60,000", "Price 1,000,000", and read as raw data). Each kind is what she has against what she may have and the most there is ("1 / 2 · max 6"), then
// the NEXT place only: the level that opens it or the price that buys it (`lockedSteps`, the same reading the locked tiles and New fleet use), with Buy on the price.
//
// TWO BARS (2026-11-23, the visual overhaul's slice 5: "Room is two bars (fleets, ships each) with the next step's target on the bar"). Each kind is
// its mark, its word, a bar of one segment a place up to the most there is (lit: the places she has), and "used / have"; under it the next step as
// marks: [levels] the level that opens it, [coin] the price. "Next:", "or", "max 6" and "Price" left the glass; the bar's name says the most.

export function FleetRoom() {
  const t = useT()
  const room = useHouseRoom()
  if (!room || !room.company) return null
  return (
    <Card icon="anchor" title={t('fleets.room')} data-testid="fleet-room">
      {!room.on && (
        <Note tone="neutral" data-testid="fleet-room-dark">
          {t('fleets.roomNotOpen')}
        </Note>
      )}
      <Ladder kind="FLEET" mark={<Icon name="ship" size={20} />} label={t('fleets.roomFleets')} ladder={room.fleets} on={room.on} />
      <Ladder kind="SHIP" mark={<ShipPicture code={null} size="mark" />} label={t('fleets.roomShips')} ladder={room.ships} on={room.on} />
    </Card>
  )
}

function Ladder({ kind, mark, label, ladder, on }: { kind: 'FLEET' | 'SHIP'; mark: ReactNode; label: string; ladder: RoomLadder; on: boolean }) {
  const t = useT()
  const { busy, refusal, buy } = useBuyRoom(kind)
  const { levels, prices } = lockedSteps(ladder)
  const level = levels[0]
  const price = prices[0]
  const levelWord = level ? roomStepWord(t, level, ladder.level) : null
  const have = formatOfTotal(ladder.used, ladder.have)

  return (
    <div className="mt-4 first:mt-2" data-testid={`fleet-room-${kind.toLowerCase()}`}>
      <div className="flex min-h-8 items-center gap-3" data-testid="fleet-room-have">
        <span className="flex w-8 shrink-0 justify-center text-ink-muted">{mark}</span>
        <span className="shrink-0 text-t-label text-ink-muted">{label}</span>
        <Bar
          value={ladder.have}
          of={ladder.top}
          tone="accent"
          label={`${label} ${have} · ${t('fleets.roomTop', { n: formatInt(ladder.top) })}`}
          figure={<span className="tabular-nums text-t-body font-semibold text-ink">{have}</span>}
          className="min-w-16 flex-1"
        />
      </div>
      {(level || price) && (
        <div className="mt-1 flex flex-wrap items-center gap-x-4 gap-y-1 pl-11 text-t-caption text-ink-muted" data-testid="fleet-room-next">
          {levelWord && (
            <span className="flex items-center gap-1.5 tabular-nums">
              <Icon name="levelUp" size={16} className="shrink-0 text-accent" />
              {levelWord}
            </span>
          )}
          {price && <span className="tabular-nums" title={roomStepWord(t, price)}>{formatDucats(price.price)}</span>}
          {on && price?.next && price.can_pay && (
            <Button variant="secondary" busy={busy} onClick={buy} className="ml-auto" data-testid="fleet-room-buy">
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
