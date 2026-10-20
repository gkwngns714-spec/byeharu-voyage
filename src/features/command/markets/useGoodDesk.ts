import { useEffect, useMemo, useState } from 'react'
import { fleetCargoByCode } from '../../../domain/fleet'
import { prefetchDeskReads, useGoodBoard, usePriceOutlook, usePriceWhy } from '../../../live/useDesk'
import { usePortHistory } from '../../../live/usePortHistory'
import { useWorld } from '../../../live/worldStore'
import type { BoardBuyRow, BoardSellRow, FleetView, SnapshotGood } from '../../../lib/rpc'
import { useDeskGood } from '../../../store/deskGood'
import { citySides } from './citySides'

// ONE GOOD ON THE DESK, READ ONCE (docs/COMMAND_DESK.md §3.3, §3.9). Both halves of the good's page
// stand on the same reads: the CHART (the centre pane on a wide glass, the top of the tray on a phone)
// and the TICKET (the right pane / under the chart). So the reads are asked here, once, and handed to
// both. Nothing is computed: the board is world.good_board's, the record world.price_history's, the
// estimate world.price_outlook's, the breakdown world.price_why's (0185).
//
// THE FOCUS — which city the chart follows: the city tapped (useDeskGood), else the docked city when
// it sells the good, else the cheapest seller, else the dearest buyer.
//
// THE FOCUS IS GUESSED WHILE THE BOARD IS ON THE WIRE (2026-10-19, owner: "when pressing a different trade
// goods, it takes too long to load"): the chart's estimate and the ticket's breakdown are the focus city's,
// and the focus is the board's — so they were asked only after the board landed, one wait after another.
// Now the cities the focus is likely to be (the docked city; the watchlist's cheapest seller) are asked
// beside the board (`prefetchGoodDesk`), and when the board names one of them its reads are already in.

/** The chart's estimate (world.price_outlook): the market price, a day of slots ahead. */
export const DESK_OUTLOOK = { side: 'mid', slots: 24 } as const

// THE CHART'S WINDOW — how far back it looks, and therefore how much of the record is ASKED FOR.
//
// The owner, 2026-10-20 (request 178): *"the price is shown max 12 hours, can you make this more
// longer? Like day? Week?"* The 12 hours were not a choice the client made twice over: they were the
// whole record. `public.price_history_window()` is `greatest(48, 600 MiB / (pairs × 201 bytes))`
// (0057) and production's 132,090 (port, good) pairs put the derived figure under the floor, so the
// window is the floor — 48 slots of 900 s, exactly 12 h — and it clamps BOTH the read and the prune,
// so older rows do not exist to be read. The client was ALSO pinned at 12 h (three chips, and a
// `slots = 48` default on the one caller), and that half is what this removes: the chips go on to a
// day and a week, the ask is the slots the chosen window would fill, and the SERVER says how much of
// it there is. The day the retention law widens — or the rollup of 0214, which keeps one row per UTC
// day forever, is served per city and good — these chips draw the longer line with no client change.
export const DESK_WINDOW_HOURS = [1, 6, 12, 24, 168] as const
/** The window the page opens on: the whole record as production keeps it today. */
export const DESK_WINDOW_DEFAULT = 12

/** Ask ahead what a good page will ask: the board (with `board`), and at the cities its chart is likely to
 *  follow — the docked city, then `cheapest` (the watchlist's cheapest seller) — the estimate, the
 *  breakdown and the price record. Nothing is shown from here; the panes find the answers kept. */
export function prefetchGoodDesk({
  fleetId,
  fleetVersion,
  docked,
  goodId,
  cheapest,
  board,
}: {
  fleetId: string
  fleetVersion: number | null
  /** The port CODE she is docked at, or null. */
  docked: string | null
  goodId: string
  /** The port CODE of the cheapest seller (world.watchlist's `best`), or null. */
  cheapest: string | null
  board: boolean
}): void {
  const { portByCode, history, loadHistory } = useWorld.getState()
  const portIds = [...new Set([docked, cheapest])]
    .map((code) => (code ? portByCode[code]?.id : undefined))
    .filter((id): id is string => !!id)
  prefetchDeskReads({ goodId, board: board ? { fleetId, fleetVersion } : null, outlook: DESK_OUTLOOK, portIds })
  for (const id of portIds) if (history[id] === undefined) void loadHistory(id)
}

export function useGoodDesk(fleet: FleetView, good: SnapshotGood, cheapest: string | null = null) {
  const portByCode = useWorld((s) => s.portByCode)
  const focusCode = useDeskGood((s) => s.focus)
  const setFocus = useDeskGood((s) => s.setFocus)

  const [winHours, setWinHours] = useState<number>(DESK_WINDOW_DEFAULT)
  const board = useGoodBoard(good.id, fleet.id, fleet.version, null)
  const b = board.view
  const docked = fleet.status === 'DOCKED' ? fleet.port : null
  const aboard = fleetCargoByCode(fleet)[good.code] ?? 0

  // the likely focus cities' reads, beside the board's (the header's 2026-10-19 paragraph)
  useEffect(() => {
    prefetchGoodDesk({ fleetId: fleet.id, fleetVersion: fleet.version, docked, goodId: good.id, cheapest, board: false })
  }, [fleet.id, fleet.version, docked, good.id, cheapest])

  const focus =
    focusCode ?? (b ? (b.buy.find((r) => r.here)?.port ?? b.buy[0]?.port ?? b.sell[0]?.port ?? null) : docked)
  const focusPort = focus ? (portByCode[focus] ?? null) : null
  const outlook = usePriceOutlook(focusPort?.id ?? null, good.id, DESK_OUTLOOK.side, DESK_OUTLOOK.slots)
  // The cadence is SERVED (one knob, `drift_slot_seconds`, on both payloads), so the slots a window
  // needs are derived from it and never from a literal. Until a payload lands the ask is null, which
  // is the server's own default — the chart opens on the record it already keeps.
  const slotSeconds = outlook.view?.slot_seconds ?? null
  const wantSlots = slotSeconds && slotSeconds > 0 ? Math.ceil((winHours * 3600) / slotSeconds) : null
  const history = usePortHistory(focusPort?.id ?? '', focusPort ? good.code : null, wantSlots)
  const why = usePriceWhy(focusPort?.id ?? null, good.id)

  const focusRow: BoardBuyRow | BoardSellRow | null =
    (b && focus && (b.buy.find((r) => r.port === focus) ?? b.sell.find((r) => r.port === focus))) || null

  // BOTH SIDES, CITY BY CITY (owner request 178): the board's two lists joined by city, so a row's
  // figure never stands without the side it is. Nothing is priced here (citySides.ts).
  const sides = useMemo(() => citySides(b), [b])

  // The chart's cities: every seller, then the city tapped when it only buys.
  const chips = useMemo(() => {
    const codes = (b?.buy ?? []).map((r) => r.port)
    for (const r of (b?.sell ?? []).filter((x) => x.quoted).slice(0, 3)) if (!codes.includes(r.port)) codes.push(r.port)
    if (focus && !codes.includes(focus)) codes.push(focus)
    return codes
  }, [b, focus])

  return {
    board,
    b,
    docked,
    aboard,
    focus,
    focusPort,
    setFocus,
    history,
    outlook,
    why,
    focusRow,
    chips,
    sides,
    winHours,
    setWinHours,
  }
}

export type GoodDesk = ReturnType<typeof useGoodDesk>
