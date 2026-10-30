import { useCallback, useMemo, useState } from 'react'
import { Note, SheetSection, useWide } from '../../../components/ui'
import { fleetCargoByCode } from '../../../domain/fleet'
import { usePortMarket } from '../../../live/usePortMarket'
import { portNameOf, useWorld } from '../../../live/worldStore'
import type { FleetView } from '../../../lib/rpc'
import { useDeskGood } from '../../../store/deskGood'
import { useT } from '../../../lib/i18n'
import type { DeskLayout } from '../DeskFrame'
import { Queue } from '../Queue'
import { RouteFold } from '../RouteFold'
import { InsuredVoyages } from '../plans/InsuredVoyages'
import { useTripBoard } from '../plans/useTripBoard'
import { ShipInfo } from './ShipInfo'
import { TradeBoard, TradeBoardSkeleton } from './TradeBoard'
import { tradeRows, type TradeGoodRow } from './tradeRows'
import { TradePanel } from './TradePanel'
import { doneWords, type TradeDone } from './tradeDone'
import { TradeToast } from './TradeToast'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// TRADE — ONE DOCKED SCREEN, BOTH SIDES (owner 2026-10-30)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// *"the map on command - buy and sell - is quiet the bad feeling. i am thinking of removing the map, just have
// combined buy and sell tab with trade goods when docked, choosing a fleet."*
//
// The Buy and Sell faces (BuySell.tsx, row 218) were two faces over ONE city — picked on a mini-map — and the map
// did the city-picking. The map is gone. TRADE is the city she is docked at, and its goods stand in ONE list
// (TradeBoard.tsx), every row carrying BOTH prices — the city's ask (Buy) and its bid (Sell) side by side — and the
// panel (TradePanel.tsx) opens on whichever button is pressed. Not docked, the face says so and offers nothing:
// trade happens where she lies, nowhere else.
//
//   BOARD      the docked city's goods as cards: both prices, ▲▼ on the day, the day's line, her units aboard, and
//              a Buy and a Sell button on each (dead where there is no such side).
//   PANEL      a button pressed opens THE trade panel (TradePanel.tsx): the chart, the units, the money, ONE button.
//   ORDERS     the standing route, the queue, the insured voyages, and the ship under them.
//
// The plan system (TradeMap, PlanVoyage, useTripGo, useTripBoard) is left standing for the future route builder; only
// the cities map and its city-picking left this face.

export function Trade({ fleet, layout }: { fleet: FleetView; layout: DeskLayout }) {
  const t = useT()
  const wide = useWide()
  const cancel = useWorld((s) => s.cancel)
  const clearQueue = useWorld((s) => s.clear)
  const portByCode = useWorld((s) => s.portByCode)
  const goodByCode = useWorld((s) => s.goodByCode)
  const picked = useDeskGood((s) => s.code)
  const pickGood = useDeskGood((s) => s.pick)

  // Trade happens where she lies; anywhere else there is no city in hand.
  const docked = fleet.status === 'DOCKED' ? fleet.port : null
  const cityPort = docked ? (portByCode[docked] ?? null) : null
  const quay = usePortMarket(cityPort?.id ?? null)
  const aboard = useMemo(() => fleetCargoByCode(fleet), [fleet])

  // THE CARDS: the docked city's goods in one list, each with both sides' prices.
  const rows = useMemo<TradeGoodRow[]>(() => tradeRows(quay.market?.goods ?? [], aboard, goodByCode), [quay.market, aboard, goodByCode])

  // THE SIDE OF THE OPEN PANEL — the combined board's Buy and Sell buttons each open one; the same good pressed on
  // the side already open closes it.
  const [side, setSide] = useState<'buy' | 'sell'>('buy')
  const openSide = useCallback(
    (s: 'buy' | 'sell', code: string) => {
      if (picked === code && side === s) pickGood(null)
      else {
        setSide(s)
        pickGood(code)
      }
    },
    [picked, side, pickGood],
  )

  const pickedAny = rows.find((r) => r.code === picked) ?? null
  const price = pickedAny ? (side === 'buy' ? pickedAny.buy : pickedAny.sell) : null
  const pickedRow = pickedAny && pickedAny.goodId && price !== null ? pickedAny : null

  // THE TOAST after a trade
  const [toast, setToast] = useState<string | null>(null)
  const clearToast = useCallback(() => setToast(null), [])
  const done = (d: TradeDone) => {
    setToast(doneWords(t, d, (c) => portNameOf(portByCode, c)))
    pickGood(null)
  }

  const board = docked ? (
    quay.market === undefined ? (
      quay.refusal ? (
        <Note tone="danger">{quay.refusal.sentence}</Note>
      ) : (
        <TradeBoardSkeleton />
      )
    ) : (
      <TradeBoard
        portId={cityPort?.id ?? null}
        rows={rows}
        picked={pickedRow ? pickedRow.code : null}
        onBuy={(code) => openSide('buy', code)}
        onSell={(code) => openSide('sell', code)}
      />
    )
  ) : (
    <Note tone="neutral" data-testid="trade-not-docked">
      {t('desk.tradeNotDocked')}
    </Note>
  )

  const trip = useTripBoard(fleet, null)

  const panel =
    pickedRow && docked ? (
      <TradePanel
        key={`${docked}:${pickedRow.code}:${side}:here`}
        side={side}
        fleet={fleet}
        city={docked}
        good={{
          good_id: pickedRow.goodId as string,
          code: pickedRow.code,
          name: pickedRow.name,
          category: pickedRow.category,
          rarity: pickedRow.row?.rarity,
          price: price as number,
        }}
        market={pickedRow.row}
        docked
        trip={trip}
        mode={wide ? 'pane' : 'docked'}
        onClose={() => pickGood(null)}
        onDone={done}
      />
    ) : null

  const orders = (
    <>
      {/* the standing route above the queue (0092, COMMAND_DESK §3.5: the one thing that writes orders by itself) */}
      <RouteFold fleet={fleet} />
      <SheetSection heading={t('desk.orders')} surface data-testid="command-queue">
        <Queue fleet={fleet} onCancel={(position) => cancel(fleet.id, position)} onClear={() => clearQueue(fleet.id)} />
      </SheetSection>
      {/* 0213: the insured voyages under way and what the insurance paid — only when there are any. */}
      <InsuredVoyages />
      {/* row 233: the ship under the orders */}
      <ShipInfo fleet={fleet} />
    </>
  )

  const toastLine = <TradeToast text={toast} onGone={clearToast} />

  return layout(
    wide
      ? {
          testid: 'desk-trade',
          list: orders,
          main: (
            <>
              {board}
              {toastLine}
            </>
          ),
          side: panel ? (
            <div className="h-full min-h-0" data-testid="here-tray">
              {panel}
            </div>
          ) : (
            <p className="px-4 pt-4 text-t-caption text-ink-faint" data-testid="desk-slot-hint">
              {t('desk.pickGood')}
            </p>
          ),
        }
      : {
          testid: 'desk-trade',
          order: ['list', 'main', 'side'],
          list: board,
          main: (
            <>
              {panel}
              {toastLine}
            </>
          ),
          side: <div className="mt-6">{orders}</div>,
        },
  )
}
