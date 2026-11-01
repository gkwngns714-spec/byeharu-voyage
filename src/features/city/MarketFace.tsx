import { useMemo, useState } from 'react'
import {
  Button,
  Figure,
  Note,
  Row,
  Segmented,
  Skeleton,
  SummaryRow,
  TradeTray,
  type TradePick,
} from '../../components/ui'
import { fleetCargoByCode } from '../../domain/fleet'
import { hasBuilding } from '../../domain/port'
import { formatDucats, formatInt, formatUnitPrice } from '../../lib/format'
import { cmdRequestCancel, type FleetView, type MarketGood, type SnapshotPort } from '../../lib/rpc'
import { useT } from '../../lib/i18n'
import { linesFor, useManifest } from '../../store/manifest'
import { CityGoodTrades } from '../../live/CityGoodTrades'
import { HaggleThread } from '../../live/HaggleThread'
import { QuayLedger } from '../../live/QuayLedger'
import { useMarketPick } from '../../live/marketPick'
import { useMarketRequests } from '../../live/useMarketRequests'
import { useTrade } from '../../live/useTrade'
import { usePriceSeries } from '../../live/usePriceSeries'
import { usePortMarket } from '../../live/usePortMarket'
import { useManifestPreview } from '../../live/useManifestPreview'
import { TRADE_FACES, useTradeFace, type TradeFace } from '../../live/tradeFace'
import { useWorld } from '../../live/worldStore'
import { RequestPage } from './RequestPage'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE MARKET FACE — the chart on the left region, BUY · SELL · REQUEST in the right panel
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, 2026-10-31 (verbatim): "when pressing a market, instead of city, i would like to have a
// graph shown, that is changed when pressed a trade good. when pressing buy, a new page pops up -
// this is not good. instead, have BUY, beneath show all the trade goods neatly organized. So is
// sell - cargo good. Request i press, a page shows up, where i search trade good - press it, shows
// up chart, choose price to buy, and then the put the money in it. - the order is made, and
// merchants will come and sell it to you if the price is reasonable" — and "but this feature,
// request, should only be done in your home country- home city. get it?"
//
// SO: no pop-up page for Buy or Sell. The doors are a `Segmented`; beneath the pressed door the
// goods are listed, grouped by the SERVED category, each group the one `QuayLedger` (the board's
// one order and membership rule, never re-spelt here). A press on a good pins it for the chart
// (marketPick.ts) AND opens the trade tray as a PANE inside this panel (mode="pane" — the same
// TradeTray/useTrade every quay composes, never a screen-covering sheet: the owner's Basket
// objection, kept). With no fleet of yours here the press only pins the good — the board is read-
// only, as it was.
//
// REQUEST is drawn ONLY when the server says this port is the house's home city
// (world.requests().home). That flag is the SAME public.home_port_of() the verb enforces, so hiding
// the door is a courtesy and the server is the gate. Its face lists the caller's open requests
// (good, quantity, price, the money set aside) with the cancel that refunds the unfilled part; the
// New request row opens the page the owner described: search → press a good → its chart → price and
// quantity → the payment → Place.
//
// The BASKET stays (a summary in this panel, never an overlay): the staged lines and the served
// basket total, with one row to the board.

type Slot = { kind: 'none' } | { kind: 'basket' } | { kind: 'pick'; pick: TradePick }

export function MarketFace({ port, fleet }: { port: SnapshotPort; fleet: FleetView | null }) {
  const t = useT()
  const quay = usePortMarket(port.kind === 'HARBOUR' ? port.id : null)
  const board = useMarketRequests(port.kind === 'HARBOUR' ? port.id : null)
  const face = useTradeFace((s) => s.face)
  const turnTo = useTradeFace((s) => s.turnTo)
  const pin = useMarketPick((s) => s.pick)
  const [slot, setSlot] = useState<Slot>({ kind: 'none' })
  const [qty, setQty] = useState<number | null>(null)
  const [requestPage, setRequestPage] = useState(false)
  const [cancelling, setCancelling] = useState<string | null>(null)

  // ALL HOOKS UNCONDITIONALLY, before any early return.
  const goods = useMemo(() => quay.market?.goods ?? [], [quay.market])
  const aboard = useMemo(() => (fleet ? fleetCargoByCode(fleet) : {}), [fleet])
  const staged = useManifest((s) => (fleet ? linesFor(s, fleet.id, port.code).length : 0))
  const home = board.view?.home ?? false
  const shown: TradeFace = face === 'requests' && !home ? 'buy' : face
  const matching = useMemo(
    () => goods.filter((g) => shown !== 'sell' || (aboard[g.code] ?? 0) > 0),
    [goods, shown, aboard],
  )
  const groups = useMemo(() => {
    const m = new Map<string, MarketGood[]>()
    for (const g of matching) {
      const k = g.category ?? ''
      const arr = m.get(k)
      if (arr) arr.push(g)
      else m.set(k, [g])
    }
    return [...m.entries()].sort((a, b) => a[0].localeCompare(b[0]))
  }, [matching])

  if (!hasBuilding(port, 'market')) return <Note tone="neutral">{t('city.noMarket')}</Note>
  if (quay.market === undefined) {
    return quay.refusal !== null ? (
      <Note
        tone="danger"
        code={quay.refusal.code}
        figures={quay.refusal.figures}
        action={
          <Button onClick={quay.retry}>
            {t('common.retry')}
          </Button>
        }
      >
        {quay.refusal.sentence}
      </Note>
    ) : (
      <Skeleton className="h-28 w-full" />
    )
  }

  const openGood = (good: MarketGood, intent: 'buy' | 'sell') => {
    pin(port.id, good)
    if (!fleet) return
    setQty(null)
    setSlot({ kind: 'pick', pick: { good, intent } })
  }

  if (slot.kind === 'pick' && fleet) {
    return (
      <MarketTray
        fleet={fleet}
        port={port}
        pick={slot.pick}
        qty={qty}
        onQty={setQty}
        onClose={() => {
          setSlot({ kind: 'none' })
          setQty(null)
        }}
      />
    )
  }
  if (slot.kind === 'basket' && fleet) {
    return (
      <BasketSummary
        fleet={fleet}
        port={port}
        onClose={() => setSlot({ kind: 'none' })}
        onOpenBoard={() => setSlot({ kind: 'none' })}
      />
    )
  }

  return (
    <>
      {fleet && (
        <Row
          label={t('trade.basket')}
          value={formatInt(staged)}
          chevron
          onClick={() => setSlot({ kind: 'basket' })}
          data-testid="city-market-basket"
        />
      )}
      <Segmented<TradeFace>
        label={t('city.market')}
        segments={TRADE_FACES.filter((f) => f.id !== 'requests' || home)}
        value={shown}
        onChange={turnTo}
        className="mt-2"
      />
      {shown === 'requests' ? (
        <div className="mt-2" data-testid="city-market-requests">
          {board.view === null ? (
            <Skeleton className="h-20 w-full" />
          ) : board.view.requests.length === 0 ? (
            <Note tone="neutral">{t('city.requestNone')}</Note>
          ) : (
            board.view.requests.map((r) => (
              <div key={r.id} className="border-b border-edge py-1" data-testid={`city-open-request-${r.id}`}>
                <Row label={`${r.name} ×${formatInt(r.qty)}`} value={<Figure value={formatUnitPrice(r.unit_price)} />} />
                {/* THE LINE WRAPS (2026-11-02, the HQ-on-a-phone slice): word, sum held and Cancel are 190 px and the panel's room 139 at 390, 104 at 320 — the
                    Cancel stood 43 px past the panel's edge at 390 and 78 at 320, cut off and unpressable. Under the sum, at the right edge, when they do not fit. */}
                <div className="flex min-h-11 flex-wrap items-center gap-x-2">
                  <span className="text-t-caption text-ink-faint">{t('city.requestPay')}</span>
                  <Figure value={formatDucats(r.escrow)} />
                  <Button
                    className="ml-auto"
                    onClick={() => {
                      setCancelling(r.id)
                      void cmdRequestCancel(r.id).finally(() => setCancelling(null))
                    }}
                    disabled={cancelling === r.id}
                  >
                    {t('city.requestCancel')}
                  </Button>
                </div>
              </div>
            ))
          )}
          <SummaryRow title={t('city.requestNew')} onClick={() => setRequestPage(true)} data-testid="city-request-new" />
          {requestPage && <RequestPage port={port} goods={goods} onClose={() => setRequestPage(false)} />}
        </div>
      ) : (
        <div className="mt-2" data-testid={`city-market-${shown}`}>
          {matching.length === 0 ? (
            <Note tone="neutral">{t(shown === 'sell' ? 'trade.noCargoSell' : 'trade.noMatch')}</Note>
          ) : (
            groups.map(([category, rows]) => (
              <div key={category || 'all'}>
                {category !== '' && (
                  <div className="pt-2 text-t-caption text-ink-faint" data-testid="city-market-group">
                    {category}
                  </div>
                )}
                <QuayLedger goods={rows} aboard={aboard} pick={null} onPick={openGood} empty={null} />
              </div>
            ))
          )}
        </div>
      )}
    </>
  )
}

/** THE BASKET, IN THE PANEL — the staged lines and the served total, the hold bar, one row to the
 *  board (moved here from CityFace when the market got its own file; behaviour unchanged). */
function BasketSummary({
  fleet,
  port,
  onClose,
  onOpenBoard,
}: {
  fleet: FleetView
  port: SnapshotPort
  onClose: () => void
  onOpenBoard: () => void
}) {
  const t = useT()
  const lines = useManifest((s) => linesFor(s, fleet.id, port.code))
  const preview = useManifestPreview(fleet.id, port.code, lines)
  const totals = preview.estimate?.totals ?? null
  return (
    <div data-testid="city-basket">
      {/* THE BASKET'S SUMMARY LINE — the count and the total hug the word (owner, 2026-11-01),
          instead of being pushed to the panel's far edge. */}
      <div className="flex min-h-11 items-center gap-2 border-b border-edge">
        <span className="text-t-caption text-ink-faint">{t('trade.basket')}</span>
        <span className="shrink-0 text-t-caption tabular-nums text-ink-muted">
          {lines.length === 0 ? t('trade.basketEmpty') : formatInt(lines.length)}
        </span>
        {totals !== null && <Figure value={formatDucats(totals.net)} size="body" />}
      </div>
      <SummaryRow title={t('town.f_market')} onClick={onOpenBoard} data-testid="city-basket-board" />
      <Row label={t('common.back')} chevron onClick={onClose} hairline={false} data-testid="city-basket-back" />
    </div>
  )
}

/** THE TRAY, IN THE PANEL — the one TradeTray in pane mode, driven by the one useTrade. */
function MarketTray({
  fleet,
  port,
  pick,
  qty,
  onQty,
  onClose,
}: {
  fleet: FleetView
  port: SnapshotPort
  pick: TradePick
  qty: number | null
  onQty: (n: number) => void
  onClose: () => void
}) {
  const stageOnBasket = useManifest((s) => s.stage)
  const stage = (n: number) => {
    stageOnBasket(fleet.id, port.code, { side: pick.intent, good: pick.good.code, qty: n })
    onClose()
  }
  const trade = useTrade(fleet, pick.intent, pick.good, qty, onClose, stage)
  const history = usePriceSeries(port.id, pick.good.good_id)
  const aboard = fleetCargoByCode(fleet)
  const goodByCode = useWorld((s) => s.goodByCode)
  return (
    <TradeTray
      mode="pane"
      pick={pick}
      quay={{
        aboard: aboard[pick.good.code] ?? 0,
        bulk: goodByCode[pick.good.code]?.bulk ?? 1,
        culture: port.culture,
        history,
      }}
      trade={trade}
      qty={{ value: qty, onChange: onQty }}
      onClose={onClose}
    >
      <HaggleThread
        key={`${pick.good.code}:${pick.intent}`}
        fleetId={fleet.id}
        good={pick.good}
        side={pick.intent}
        preview={trade.act.preview}
      />
      <CityGoodTrades portId={port.id} goodId={pick.good.good_id} refresh={fleet.version} />
    </TradeTray>
  )
}
