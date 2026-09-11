import { useMemo, useState } from 'react'
import { Field, Figure, Note, Row, TradeTray, type TradePick } from '../../components/ui'
import { HaggleRow } from './HaggleRow'
import { QuayLedger } from './QuayLedger'
import { StepQuestion } from './StepQuestion'
import { useStepOrder } from './useStepOrder'
import { fleetCargoByCode } from '../../domain/fleet'
import { usePortHistory } from '../../live/usePortHistory'
import { useTrade } from '../../live/useTrade'
import { fold, foldedMatch } from '../../lib/text'
import { formatVoyageDays } from '../../lib/format'
import type { FleetView, MarketGood, SnapshotPort } from '../../lib/rpc'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// TRADE, ON THE QUAY YOU ARE STANDING ON — the Quay Ledger's board (owner row 76), on the face
// row 53 put it on, redrawn to docs/QUAY_LEDGER.md §3 A.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner: *"since each port, city will have different market - trade goods, i want buy and sell
// on port tab, the market in port tab - where i press market, then choose to trade."* 0061 and 0062
// made the market a fact about the PORT, so what is on the quay belongs on the harbour, and since
// 2026-09-09 (*"Buy and sell should be in port - market"*) this is the ONLY place a good is bought
// or sold from. The two things that came with that: THE BARGAIN (`HaggleRow`, one row inside the
// buy tray) and THE CHANDLER (PROVISION — her stores as the first row, opening the step tray).
//
// ── ONE ROW PER GOOD (2026-09-11) ──────────────────────────────────────────────────────────────
// The tile grid is gone. Row 76's approved board is a ledger (QuayLedger.tsx): a `TradeRow` per
// good — the name, the served rarity mark, `N t aboard`, the tide inside the range, and the two
// price cells that are the two acts (row 6). The 2026-08-26 grid rule this reverses is annotated
// where it was pinned (tests/layout.spec.ts, docs/OWNER_REQUESTS.md row 34). A press opens the ONE
// tray, docked to the bottom edge, so nothing above the finger moves — the owner's rule, kept by
// construction.
//
// ── WHAT IS DRAWN HERE IS NOT THIS SCREEN'S ───────────────────────────────────────────────────
// The ledger is `QuayLedger`, shared with the read-only face; the row and the tray are the design
// system's; the act — the grammar, the door, the ceiling, the dry run, the server's refusal — is
// `useTrade`'s; the trend is `usePortHistory`'s. What this file owns is the text FILTER, the pick,
// the quantity, and the chandler's row.
//
// ── WHAT IT DOES NOT OWN ───────────────────────────────────────────────────────────────────────
// No price arithmetic, no legality check, no grammar, no quantity rule, no ledger order.
// `fleetCargoByCode` is the one fold of a manifest; `useTrade` owns the capacity read, the dry run
// and the one door (`cmd.issue`). A quay with nobody of yours alongside is not this file's at all —
// PortScreen mounts the read-only ledger (PortPrices.tsx) instead, so no hook here ever runs
// without a hull to trade with.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

export function PortTrade({
  goods,
  fleet,
  port,
}: {
  /** `world.market(port)`'s goods for THIS harbour — the read PortScreen already makes. */
  goods: readonly MarketGood[]
  /** The fleet of yours lying here — the one that trades (`docked[0]`, PortScreen). */
  fleet: FleetView
  /** This harbour — its culture, printed only where it refuses a good (§6). */
  port: SnapshotPort
}) {
  const [filter, setFilter] = useState('')
  const [pick, setPick] = useState<TradePick | null>(null)
  // The quantity is this screen's; the tray owns the default and materialises it through
  // `onChange`, so no rule is spelt here.
  const [qty, setQty] = useState<number | null>(null)
  const [stores, setStores] = useState(false)

  const history = usePortHistory(port.id, pick?.good.code ?? null)
  const aboard = useMemo(() => fleetCargoByCode(fleet), [fleet])
  // THE TEXT FILTER is this face's chrome; the ledger's own membership and order are QuayLedger's.
  const matching = useMemo(() => {
    const q = fold(filter.trim())
    return goods.filter((g) => foldedMatch(q, g.name, g.code, g.category))
  }, [goods, filter])

  const close = () => {
    setPick(null)
    setQty(null)
  }
  const open = (good: MarketGood, intent: 'buy' | 'sell') => {
    setStores(false)
    setQty(null)
    setPick({ good, intent })
  }

  const trade = useTrade(fleet, pick?.intent ?? 'buy', pick?.good ?? null, qty, close)
  const provision = useStepOrder(fleet, 'PROVISION', stores, () => setStores(false))

  return (
    <>
      {/* THE CHANDLER — her stores, and the press that fills them. One tray at a time: opening
          this closes a price tray, and a price cell closes this. */}
      <Row
        label="Stores"
        value={<Figure value={formatVoyageDays(fleet.endurance_days)} />}
        chevron
        onClick={() => {
          close()
          setStores(true)
        }}
        data-testid="quay-stores"
      />

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

      <QuayLedger
        goods={matching}
        aboard={aboard}
        pick={pick}
        onPick={open}
        empty={
          <Note tone="neutral" className="mt-3">
            Nothing here answers to that.
          </Note>
        }
      />

      {pick && (
        <TradeTray
          pick={pick}
          quay={{ aboard: aboard[pick.good.code] ?? 0, culture: port.culture, history }}
          trade={trade}
          qty={{ value: qty, onChange: setQty }}
          onClose={close}
        >
          {pick.intent === 'buy' && <HaggleRow fleetId={fleet.id} good={pick.good} />}
        </TradeTray>
      )}

      {stores && (
        <StepQuestion
          fleet={fleet}
          port={port}
          step={provision}
          onClose={() => {
            setStores(false)
            provision.reset()
          }}
        />
      )}
    </>
  )
}
