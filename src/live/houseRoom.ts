import { useState } from 'react'
import { formatDucats } from '../lib/format'
import { cmdBuyRoom, worldHouseRoom } from '../lib/rpc'
import type { HouseRoom, Refusal, RoomLadder, RoomStep } from '../lib/rpc'
import { useServedRead } from './useServedRead'
import { useWorld } from './worldStore'
import type { T, TKey } from '../lib/i18n'

// THE ROOM A COMPANY HAS, READ AND BOUGHT IN ONE PLACE (0354; the Fleets page, F5). Three faces read it: the Room card (FleetRoom), a fleet's locked tiles (FleetShips) and
// the New fleet page (NewFleet). They share this read, this press and these words, so a price, a level and "can she pay" are said one way. Every figure is the server's
// (`world.house_room`); nothing here decides one.

/** `world.house_room`, asked when a face that draws it opens and again on the world's beat. Null before the first answer. */
export function useHouseRoom(): HouseRoom | null {
  return useServedRead<HouseRoom>('house-room', () => worldHouseRoom(), { name: 'worldHouseRoom', cache: false }).view
}

/** The read, narrowed to a company's (a visitor with no company has no room to draw). */
export type CompanyRoom = Extract<HouseRoom, { company: true }>
export function companyRoom(room: HouseRoom | null): CompanyRoom | null {
  return room && room.company ? room : null
}

/** The one Buy press (`cmd.buy_room`): the server takes the price and judges; a refusal is printed by the caller. */
export function useBuyRoom(kind: 'FLEET' | 'SHIP'): { busy: boolean; refusal: Refusal | null; buy: () => void } {
  const refresh = useWorld((s) => s.refresh)
  const [busy, setBusy] = useState(false)
  const [refusal, setRefusal] = useState<Refusal | null>(null)
  const buy = () => {
    if (busy) return
    setBusy(true)
    setRefusal(null)
    void (async () => {
      const r = await cmdBuyRoom(kind)
      if (r.ok) await refresh()
      else setRefusal(r.refusal)
      setBusy(false)
    })()
  }
  return { busy, refusal, buy }
}

/** How one step opens, in the player's words: a price, or "Trading 3", or "Seamanship or Command 2". */
export function roomStepWord(t: T, s: RoomStep): string {
  if (s.how === 'gold') return formatDucats(s.price)
  const names = s.tracks.map((k) => t(`fleets.track_${k}` as TKey))
  return t('fleets.roomLevel', { track: names.length === 2 ? t('fleets.roomEither', { a: names[0], b: names[1] }) : names.join(', '), level: s.level })
}

type LevelStep = Extract<RoomStep, { how: 'level' }>
type GoldStep = Extract<RoomStep, { how: 'gold' }>

/** The steps of a ladder that are still shut, in the order they open: the level rungs and the prices. The Nth entry of each is one way the Nth locked place opens
 *  (levels and bought steps add up, so a mix opens it sooner; the list is read again after every step). */
export function lockedSteps(ladder: RoomLadder): { levels: LevelStep[]; prices: GoldStep[] } {
  return {
    levels: ladder.steps.filter((s): s is LevelStep => s.how === 'level' && !s.open),
    prices: ladder.steps.filter((s): s is GoldStep => s.how === 'gold' && !s.open),
  }
}
