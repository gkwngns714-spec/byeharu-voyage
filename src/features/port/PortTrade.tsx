import { useMemo, useState } from 'react'
import { Field, Figure, Note, Row, TradeTray, useWide, type TradePick } from '../../components/ui'
import { FulfilTray } from './FulfilTray'
import { HaggleThread } from './HaggleThread'
import { ManifestPanel } from './ManifestPanel'
import { QuayLedger } from './QuayLedger'
import { RequestBoard } from './RequestBoard'
import { StepQuestion } from './StepQuestion'
import { TradeFaces } from './TradeFaces'
import { useTradeFace } from './tradeFace'
import { useStepOrder } from './useStepOrder'
import { fleetCargoByCode } from '../../domain/fleet'
import { useManifestPreview } from '../../live/useManifestPreview'
import { usePortHistory } from '../../live/usePortHistory'
import { useRequests } from '../../live/useRequests'
import { useWorld } from '../../live/worldStore'
import { useTrade } from '../../live/useTrade'
import { fold, foldedMatch } from '../../lib/text'
import { formatVoyageDays } from '../../lib/format'
import type { FleetView, ManifestLine, MarketGood, SnapshotPort, TradeRequest } from '../../lib/rpc'
import { linesFor, useManifest } from '../../store/manifest'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// TRADE, AT THE PORT YOU ARE DOCKED IN — the Quay Ledger's board (owner row 76), on the face
// row 53 put it on, redrawn to docs/QUAY_LEDGER.md §3 A, with the BASKET beside it (rows 76, 80).
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner: *"since each port, city will have different market - trade goods, i want buy and sell
// on port tab, the market in port tab - where i press market, then choose to trade."* 0061 and 0062
// made the market a fact about the PORT, so what is on the market belongs on the harbour, and since
// 2026-09-09 (*"Buy and sell should be in port - market"*) this is the ONLY place a good is bought
// or sold from. The two things that came with that: THE HAGGLE (`HaggleThread`, one row inside
// the tray that unfolds into the merchant's turns — on BOTH sides since slice 3, 2026-09-13) and
// RESUPPLY (the supplies row, opening the step tray).
//
// ── ONE ROW PER GOOD (2026-09-11) ──────────────────────────────────────────────────────────────
// The tile grid is gone. Row 76's approved board is a ledger (QuayLedger.tsx): a `TradeRow` per
// good — the name, the served rarity mark, `N units on board`, the tide inside the range, and the
// two price cells that are the two acts (row 6). A press opens the ONE tray — docked to the bottom
// edge on a phone, standing beside the column from `lg` — so nothing above the finger moves.
//
// ── THE BASKET, AND THE ONE STATE THAT SAYS WHICH TRAY STANDS (slice 2, 2026-09-13) ────────────
// The reference's centre is its basket: several lines staged, one total, one press. Here it is
// `ManifestPanel`, and on a wide glass it is what the right-hand slot ALWAYS shows on this face —
// empty, with lines, or as the receipt. A price press opens the trade tray IN THAT SLOT (it
// replaces the basket; closing the pick returns to it), and the tray's second act, `Add to
// basket`, stages the line here. PR #59's first cut let two docked trays mount at once (the
// review's MUST-FIX 3: three independent booleans), so which tray stands is now ONE state:
//     slot.kind = 'pick'     → TradeTray for that good, at half
//                 'supplies' → the resupply step tray
//                 'basket'   → ManifestPanel (its face is the store's: receipt · lines · empty)
//                 'none'     → nothing docked — a phone put the basket away; the lines are kept,
//                              and the next press on the board brings it back. A wide glass
//                              never shows an empty slot, so there 'none' reads as 'basket'.
// The basket is priced ONCE here (`useManifestPreview`) and the panel prints that answer.
//
// ── THE THREE FACES, AND THE REQUEST BOARD (slice 4, 2026-09-14, migration 0087) ────────────────
// docs/QUAY_LEDGER.md §3 A: `Segmented` Buy · Sell · Requests. Buy and Sell are two faces of the
// ONE ledger — every row keeps both its cells (owner row 6); Sell narrows the rows to what the
// ship carries, so a captain with cargo to move sees only that. Requests is the reference's 의뢰
// board: what this port asks for (`world.contracts`, read by `useRequests` on the world's beat),
// one row per request shaped like the ledger's, ONE cell `fulfil` carrying the premium, dead with
// its reason when the lot is not all on board. A press opens `FulfilTray` in the SAME slot —
//     slot.kind = 'request'  → FulfilTray for that request, at half
// and on success the served receipt (0083's, with the premium as its own line) is settled onto the
// basket store so the slot turns over to the RECEIPT face exactly as a landed basket does. Which
// face is up is `useTradeFace` (tradeFace.ts), shared with the read-only board.
//
// ── WHAT IS DRAWN HERE IS NOT THIS SCREEN'S ───────────────────────────────────────────────────
// The ledger is `QuayLedger`, shared with the read-only face; the row and the trays are the design
// system's; the act — the grammar, the door, the ceiling, the dry run, the server's refusal — is
// `useTrade`'s; the trend is `usePortHistory`'s; the basket's faces are `ManifestPanel`'s. What
// this file owns is the text FILTER, the pick, the quantity, the supplies row, and the slot.
//
// ── WHAT IT DOES NOT OWN ───────────────────────────────────────────────────────────────────────
// No price arithmetic, no legality check, no grammar, no quantity rule, no ledger order.
// `fleetCargoByCode` is the one fold of a cargo list; `useTrade` owns the capacity read, the dry
// run and the one door (`cmd.issue`); `issueManifest` is the basket's. A port with nobody of yours
// docked is not this file's at all — PortScreen mounts the read-only ledger (PortPrices.tsx).
// ═══════════════════════════════════════════════════════════════════════════════════════════════

type Slot =
  | { kind: 'basket' }
  | { kind: 'none' }
  | { kind: 'supplies' }
  | { kind: 'pick'; pick: TradePick }
  | { kind: 'request'; request: TradeRequest }

const BASKET: Slot = { kind: 'basket' }

export function PortTrade({
  goods,
  fleet,
  port,
}: {
  /** `world.market(port)`'s goods for THIS harbour — the read PortScreen already makes. */
  goods: readonly MarketGood[]
  /** The fleet of yours docked here — the one that trades (`docked[0]`, PortScreen). */
  fleet: FleetView
  /** This harbour — its culture, printed only where it refuses a good (§6). */
  port: SnapshotPort
}) {
  const [filter, setFilter] = useState('')
  const [slot, setSlot] = useState<Slot>(BASKET)
  // The quantity is this screen's; the tray owns the default and materialises it through
  // `onChange`, so no rule is spelt here.
  const [qty, setQty] = useState<number | null>(null)
  const wide = useWide()

  const pick = slot.kind === 'pick' ? slot.pick : null
  const history = usePortHistory(port.id, pick?.good.code ?? null)
  // A unit's bulk is a catalogue fact; the market row does not carry it, the snapshot does.
  const goodByCode = useWorld((s) => s.goodByCode)
  const aboard = useMemo(() => fleetCargoByCode(fleet), [fleet])
  // WHICH FACE — shared with the read-only board (tradeFace.ts). The request board is read on
  // the world's beat whatever face is up: a fresh board on turning to it is the reader's due.
  const face = useTradeFace((s) => s.face)
  const board = useRequests(port.id)
  // THE TEXT FILTER is this face's chrome; the ledger's own membership and order are QuayLedger's.
  // On the Sell face the same rows are narrowed to what the ship carries — a filter, not a second
  // ledger; on Requests it narrows the board by the same three words.
  const q = fold(filter.trim())
  const matching = useMemo(
    () => goods.filter((g) => foldedMatch(q, g.name, g.code, g.category) && (face !== 'sell' || (aboard[g.code] ?? 0) > 0)),
    [goods, q, face, aboard],
  )
  const requests = useMemo(
    () => (board.view ? board.view.contracts.filter((r) => foldedMatch(q, r.name, r.good, r.category)) : null),
    [board.view, q],
  )
  const settleReceipt = useManifest((s) => s.settle)

  // CLOSING ANYTHING RETURNS TO THE BASKET — the one rule, for the pick, the supplies and the
  // receipt alike.
  const toBasket = () => {
    setSlot(BASKET)
    setQty(null)
  }
  const open = (good: MarketGood, intent: 'buy' | 'sell') => {
    setQty(null)
    setSlot({ kind: 'pick', pick: { good, intent } })
  }

  // THE BASKET: this fleet's lines at this port, priced once. The stage press carries the
  // quantity the tray materialised — the same figure on the tray's button.
  const lines = useManifest((s) => linesFor(s, fleet.id, port.code))
  const stageOnBasket = useManifest((s) => s.stage)
  const preview = useManifestPreview(fleet.id, port.code, lines)
  const stage = (n: number) => {
    if (!pick || n <= 0) return
    stageOnBasket(fleet.id, port.code, { side: pick.intent, good: pick.good.code, qty: n })
    toBasket()
  }
  const edit = (line: ManifestLine) => {
    const good = goods.find((g) => g.code === line.good)
    if (!good) return
    open(good, line.side)
    setQty(line.qty)
  }

  const trade = useTrade(fleet, pick?.intent ?? 'buy', pick?.good ?? null, qty, toBasket, stage)
  const provision = useStepOrder(fleet, 'PROVISION', slot.kind === 'supplies', toBasket)

  const shown = slot.kind === 'none' && wide ? 'basket' : slot.kind

  return (
    <>
      {/* SUPPLIES — how many days it has, and the press that buys more. */}
      <Row
        label="Supplies"
        value={<Figure value={formatVoyageDays(fleet.endurance_days)} />}
        chevron
        onClick={() => {
          setQty(null)
          setSlot({ kind: 'supplies' })
        }}
        data-testid="quay-stores"
      />

      <TradeFaces />

      <Field
        value={filter}
        onChange={(e) => setFilter(e.target.value)}
        onClear={() => setFilter('')}
        aria-label="Filter goods"
        placeholder="Filter goods"
        spellCheck={false}
        autoCorrect="off"
        className="mt-3"
      />

      {face === 'requests' ? (
        <RequestBoard
          requests={requests}
          loading={board.loading}
          aboard={aboard}
          docked
          pick={slot.kind === 'request' ? slot.request.id : null}
          onPick={(request) => {
            setQty(null)
            setSlot({ kind: 'request', request })
          }}
        />
      ) : (
        <QuayLedger
          goods={matching}
          aboard={aboard}
          pick={pick}
          onPick={open}
          empty={
            <Note tone="neutral" className="mt-3">
              {face === 'sell' ? 'No cargo to sell.' : 'No goods match.'}
            </Note>
          }
        />
      )}

      {slot.kind === 'request' && (
        <FulfilTray
          fleet={fleet}
          request={slot.request}
          aboard={aboard[slot.request.good] ?? 0}
          onClose={toBasket}
          onSettled={(receipt) => {
            settleReceipt(fleet.id, port.code, receipt)
            toBasket()
          }}
        />
      )}

      {pick && (
        <TradeTray
          pick={pick}
          quay={{ aboard: aboard[pick.good.code] ?? 0, bulk: goodByCode[pick.good.code]?.bulk ?? 1, culture: port.culture, history }}
          trade={trade}
          qty={{ value: qty, onChange: setQty }}
          onClose={toBasket}
        >
          {/* Keyed per pick, so a thread never carries another good's (or the other side's) turns. */}
          <HaggleThread
            key={`${pick.good.code}:${pick.intent}`}
            fleetId={fleet.id}
            good={pick.good}
            side={pick.intent}
            preview={trade.act.preview}
          />
        </TradeTray>
      )}

      {shown === 'supplies' && (
        <StepQuestion
          fleet={fleet}
          port={port}
          step={provision}
          onClose={() => {
            toBasket()
            provision.reset()
          }}
        />
      )}

      {shown === 'basket' && (
        <ManifestPanel
          fleet={fleet}
          port={port}
          goods={goods}
          preview={preview}
          onEdit={edit}
          onBuy={(good) => open(good, 'buy')}
          onSell={(good) => open(good, 'sell')}
          onClose={() => setSlot({ kind: 'none' })}
        />
      )}
    </>
  )
}
