import { useCallback, useEffect, useMemo, useState } from 'react'
import {
  Button,
  Icon,
  Note,
  Sheet,
  Skeleton,
  TileField,
  TradeTile,
  TradeTray,
  type TradePick,
} from '../../components/ui'
import { fleetCargoByCode, fleetPortCode } from '../../domain/fleet'
import { buyableHere } from '../../domain/market'
import { useCommandDraft } from '../../domain/order'
import type { FleetView, MarketGood, PricePoint, Refusal, WorldSnapshot } from '../../lib/rpc'
import { useTrade } from '../../live/useTrade'
import { WorldFailed, WorldLoading } from '../../live/WorldGate'
import { useWorld } from '../../live/worldStore'
import { harbourCode, useHarbour } from '../../store/harbour'
import { nearbyHarbours } from './nearby'
import { PortField } from './PortField'
import { PriceRows, PriceTray } from './PriceTray'

// MARKET — read prices somewhere else. docs/UI_DIRECTION.md §6, and docs/OWNER_REQUESTS.md rows
// 64 and 70: with the neighbour index gone ("the game is to challenge players for finding the best
// prices by themselves"), this tab's one job is to show what a quay you are NOT standing on would
// pay and charge. What stays is the harbour, the grid, the range and the trend. Everything else on
// the old screen was a sentence about a figure, and most of it is measured in §2:
//   · the control card, with its SORT and FILTER chips — two rows of chrome to arrange ten tiles;
//   · "Tap a good to send it to Command." — the tile's own cells are the act now (row 6);
//   · the footer `tax 3.0% · spread 2.0% · trade 20/10 · latin culture ⓘ` — four figures already
//     inside the price printed on the cell, and a culture that only matters on the good it refuses;
//   · the "HOW TO READ IT / NEARBY says cheap HERE" card, explaining a figure 0071 deleted;
//   · 238 port chips (item 8) — the page grew to 5,566px when the picker opened. The picker is a
//     `Field` with the nearest ten under it (./PortField.tsx, ./nearby.ts).
//
// ── THE SAME TILE AS THE TWO QUAYS THAT TRADE ──────────────────────────────────────────────────
// `TradeTile` is the design system's — PORT's Trade face and COMMAND's BUY/SELL question draw it —
// so a good cannot look different on the tab you read it on and the tab you buy it on. Its cells
// are real buttons, and what a press opens depends on ONE fact: whether a fleet of yours is
// alongside the harbour being read.
//   · alongside  → the design system's `TradeTray` on `useTrade`, the identical act PORT and
//                  COMMAND issue through. Reading the quay you are on IS trading on it.
//   · elsewhere  → `PriceTray`: the trend, the range, the stock, and the passage as a figure. No
//                  order is composed here (§5: `orderText()` is called at issue time, in
//                  `useTrade`), and since 2026-09-09 no SAIL is handed anywhere from here either:
//                  a passage is ordered on the MAP, where the owner drove it (rows 45/46).
//
// ── WHAT IT READS ──────────────────────────────────────────────────────────────────────────────
// Which harbour: `src/store/harbour.ts`, the one owner PORT shares. Whose cargo: the fleet that
// would sail here — alongside if one is, else the draft's fleet, else the first — so a sell cell is
// live for what she is carrying and dead ("none aboard") for what she is not, on a distant quay
// as on her own. The prices re-ask on the world's own `readAt` beat, as before; the history and
// the reach are silent reads the store caches.

export function MarketScreen() {
  const phase = useWorld((s) => s.phase)
  const fatal = useWorld((s) => s.fatal)
  const snapshot = useWorld((s) => s.snapshot)
  const open = useWorld((s) => s.open)
  // A tab opened straight on /market still has a world to read; the store's open() is its own guard.
  useEffect(() => {
    void open()
  }, [open])

  if (phase === 'failed') return <WorldFailed eyebrow="Trade" title="Prices" refusal={fatal} />
  if (phase !== 'ready' || !snapshot) {
    return <WorldLoading eyebrow="Trade" title="Prices" subtitle="Opening the world." panels={2} />
  }
  return <PricesBody snapshot={snapshot} />
}

function PricesBody({ snapshot }: { snapshot: WorldSnapshot }) {
  const fleets = useWorld((s) => s.fleets)
  const portByCode = useWorld((s) => s.portByCode)
  const markets = useWorld((s) => s.markets)
  const loadMarket = useWorld((s) => s.loadMarket)
  const history = useWorld((s) => s.history)
  const loadHistory = useWorld((s) => s.loadHistory)
  const reaches = useWorld((s) => s.reaches)
  const loadReach = useWorld((s) => s.loadReach)
  const readAt = useWorld((s) => s.readAt)
  const draftFleetId = useCommandDraft((s) => s.fleetId)
  const picked = useHarbour((s) => s.picked)
  const choose = useHarbour((s) => s.pick)

  const [loadError, setLoadError] = useState<{ portId: string; refusal: Refusal | null } | null>(null)
  const [pick, setPick] = useState<TradePick | null>(null)

  const portCode = harbourCode(picked, fleets, snapshot.ports)
  const port = portCode ? (portByCode[portCode] ?? null) : null
  const portId = port?.kind === 'HARBOUR' ? port.id : null
  const view = portId ? markets[portId] : undefined

  const docked = port ? (fleets.find((f) => f.port === port.code) ?? null) : null
  const acting = docked ?? fleets.find((f) => f.id === draftFleetId) ?? fleets[0] ?? null
  // Where the chips are measured from, and where the passage figure is measured from.
  const anchorCode = acting ? fleetPortCode(acting) : (port?.code ?? null)
  const anchor = anchorCode ? (portByCode[anchorCode] ?? null) : null
  const reach = anchor ? reaches[anchor.id] : undefined

  const fetchMarket = useCallback(
    (id: string) => {
      void loadMarket(id).then(() => {
        const state = useWorld.getState()
        setLoadError(state.markets[id] ? null : { portId: id, refusal: state.refusal })
      })
    },
    [loadMarket],
  )
  useEffect(() => {
    if (portId && readAt !== null) fetchMarket(portId)
  }, [portId, readAt, fetchMarket])
  useEffect(() => {
    if (portId && !history[portId]) void loadHistory(portId)
  }, [portId, history, loadHistory])
  useEffect(() => {
    if (anchor) void loadReach(anchor.id)
  }, [anchor, loadReach])

  const aboard = useMemo(() => (acting ? fleetCargoByCode(acting) : {}), [acting])
  const goods = useMemo(
    () =>
      (view?.goods ?? [])
        .filter((g) => g.available || (aboard[g.code] ?? 0) > 0)
        .sort((a, b) => a.name.localeCompare(b.name)),
    [view, aboard],
  )
  const offer = useCallback(
    (query: string) => nearbyHarbours(snapshot.ports, reach, anchorCode, query),
    [snapshot.ports, reach, anchorCode],
  )
  const points = (good: MarketGood): PricePoint[] | undefined =>
    portId ? history[portId]?.goods[good.code] : undefined

  const close = () => setPick(null)
  // The sailed distance to this quay from where she lies — a figure, never a passage ordered here.
  const passage =
    acting && port && !docked && anchorCode !== port.code ? (reach?.reaches[port.code] ?? null) : null

  return (
    <Sheet
      title="Prices"
      data-testid="market"
      trailing={
        docked ? (
          <span className="flex items-center gap-2 text-t-label">
            <Icon name="ship" size={20} />
            {docked.name}
          </span>
        ) : undefined
      }
    >
      <PortField
        current={port}
        offer={offer}
        onPick={(code) => {
          setPick(null)
          choose(code)
        }}
      />

      {!port ? (
        <Note tone="warning" className="mt-3">
          The world served no ports.
        </Note>
      ) : port.kind === 'SEA_PLACE' ? (
        <Note tone="neutral" className="mt-3">
          Open water keeps no book. Name a harbour.
        </Note>
      ) : loadError && loadError.portId === portId ? (
        <Note
          tone="danger"
          code={loadError.refusal?.code}
          className="mt-3"
          action={
            <Button size="sm" onClick={() => fetchMarket(loadError.portId)}>
              Try again
            </Button>
          }
        >
          {loadError.refusal?.sentence ?? `The prices for ${port.name} did not come back.`}
        </Note>
      ) : !view ? (
        <TileField className="mt-3">
          {Array.from({ length: 4 }, (_, i) => (
            <Skeleton key={i} className="h-tile" />
          ))}
        </TileField>
      ) : goods.length === 0 ? (
        <Note tone="neutral" className="mt-3">
          Nothing is traded on this quay.
        </Note>
      ) : (
        <TileField className="mt-3">
          {goods.map((g) => (
            <TradeTile
              key={g.code}
              good={g}
              aboard={aboard[g.code] ?? 0}
              canBuy={buyableHere(g)}
              selected={pick?.good.code === g.code}
              onBuy={() => setPick({ good: g, intent: 'buy' })}
              onSell={() => setPick({ good: g, intent: 'sell' })}
            />
          ))}
        </TileField>
      )}

      {pick && port && (docked ? (
        <QuayTray
          key={`${pick.good.code}:${pick.intent}`}
          fleet={docked}
          pick={pick}
          aboard={aboard[pick.good.code] ?? 0}
          culture={port.culture}
          points={points(pick.good)}
          onClose={close}
        />
      ) : (
        <PriceTray good={pick.good} points={points(pick.good)} passage={passage} onClose={close} />
      ))}
    </Sheet>
  )
}

/** A fleet of yours is alongside the harbour being read, so a price is a trade: the design
 *  system's tray on the one act, exactly as PORT composes it, with the price rows riding inside.
 *  Keyed by the pick, so a quantity never carries over from one good to the next. */
function QuayTray({
  fleet,
  pick,
  aboard,
  culture,
  points,
  onClose,
}: {
  fleet: FleetView
  pick: TradePick
  aboard: number
  culture: string
  points: readonly PricePoint[] | undefined
  onClose: () => void
}) {
  const [qty, setQty] = useState<number | null>(null)
  const { capacity, step, act } = useTrade(fleet, pick.intent, pick.good, qty, onClose)
  return (
    <TradeTray
      pick={pick}
      aboard={aboard}
      capacity={capacity}
      step={step}
      qty={{ value: qty, onChange: setQty }}
      act={act}
      culture={culture}
      onClose={onClose}
    >
      <PriceRows good={pick.good} points={points} />
    </TradeTray>
  )
}
