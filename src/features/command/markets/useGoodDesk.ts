import { useMemo } from 'react'
import { fleetCargoByCode } from '../../../domain/fleet'
import { useGoodBoard, usePriceOutlook } from '../../../live/useDesk'
import { usePortHistory } from '../../../live/usePortHistory'
import { useWorld } from '../../../live/worldStore'
import type { BoardBuyRow, BoardSellRow, FleetView, SnapshotGood } from '../../../lib/rpc'
import { useDeskGood } from '../../../store/deskGood'

// ONE GOOD ON THE DESK, READ ONCE (docs/COMMAND_DESK.md §3.3, §3.9). Both halves of the good's page
// stand on the same reads: the CHART (the centre pane on a wide glass, the top of the tray on a phone)
// and the TICKET (the right pane / under the chart). So the reads are asked here, once, and handed to
// both. Nothing is computed: the board is world.good_board's, the record world.price_history's, the
// estimate world.price_outlook's.
//
// THE FOCUS — which city the chart follows: the city tapped (useDeskGood), else the docked city when
// it sells the good, else the cheapest seller, else the dearest buyer.

export function useGoodDesk(fleet: FleetView, good: SnapshotGood) {
  const portByCode = useWorld((s) => s.portByCode)
  const focusCode = useDeskGood((s) => s.focus)
  const setFocus = useDeskGood((s) => s.setFocus)

  const board = useGoodBoard(good.id, fleet.id, fleet.version, null)
  const b = board.view
  const docked = fleet.status === 'DOCKED' ? fleet.port : null
  const aboard = fleetCargoByCode(fleet)[good.code] ?? 0

  const focus =
    focusCode ?? (b ? (b.buy.find((r) => r.here)?.port ?? b.buy[0]?.port ?? b.sell[0]?.port ?? null) : docked)
  const focusPort = focus ? (portByCode[focus] ?? null) : null
  const history = usePortHistory(focusPort?.id ?? '', focusPort ? good.code : null)
  const outlook = usePriceOutlook(focusPort?.id ?? null, good.id, 'mid', 24)

  const focusRow: BoardBuyRow | BoardSellRow | null =
    (b && focus && (b.buy.find((r) => r.port === focus) ?? b.sell.find((r) => r.port === focus))) || null

  // The chart's cities: every seller, then the city tapped when it only buys.
  const chips = useMemo(() => {
    const codes = (b?.buy ?? []).map((r) => r.port)
    for (const r of (b?.sell ?? []).filter((x) => x.quoted).slice(0, 3)) if (!codes.includes(r.port)) codes.push(r.port)
    if (focus && !codes.includes(focus)) codes.push(focus)
    return codes
  }, [b, focus])

  return { board, b, docked, aboard, focus, focusPort, setFocus, history, outlook, focusRow, chips }
}

export type GoodDesk = ReturnType<typeof useGoodDesk>
