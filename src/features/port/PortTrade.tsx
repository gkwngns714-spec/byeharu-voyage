import { useMemo, useState } from 'react'
import { Field, Note, TileField, TradeTile, TradeTray, type TradePick } from '../../components/ui'
import { fleetCargoByCode } from '../../domain/fleet'
import { buyableHere } from '../../domain/market'
import { useTrade } from '../../live/useTrade'
import { fold, foldedMatch } from '../../lib/text'
import type { FleetView, MarketGood } from '../../lib/rpc'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// TRADE, ON THE QUAY YOU ARE STANDING ON — docs/OWNER_REQUESTS.md row 53, redrawn to §6.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner: *"since each port, city will have different market - trade goods, i want buy and sell
// on port tab, the market in port tab - where i press market, then choose to trade."* 0061 and 0062
// made the market a fact about the PORT, so what is on the quay belongs on the harbour.
//
// ── WHAT IS DRAWN HERE IS NOT THIS SCREEN'S ───────────────────────────────────────────────────
// §6, on this face: *"TRAY: identical to Command's buy tray (same component, same `issue`)"*. The
// tile is `TradeTile`, the tray is `TradeTray`, both the design system's; the act — the grammar,
// the door, the ceiling, the server's refusal — is `useTrade`'s. COMMAND's BUY/SELL question
// composes exactly the same three, so a good cannot look different, step differently or be issued
// differently on the two quays a player buys from. What this file owns is the FIELD — which goods
// this harbour shows — and the pick.
//
// For one day (2026-09-09) it owned more: its own TradeTray.tsx and its own price cell, written in
// step 4 before step 5 promoted the same tray into the design system. Two spellings of one tray is
// the shape the standing law forbids; the private copies are deleted and nothing of them is kept.
//
// ── WHAT §6 DELETED HERE, AND WHY EACH ONE WENT ────────────────────────────────────────────────
//   THE BUY/SELL SUB-TABS.  *"the tile has both prices; the tap zone decides"*. Two faces over one
//     list cost a tap, a piece of state and 52px, and they hid half the information: a player
//     reading the BUY face could not see what the quay pays. Both figures are on the tile now and
//     the CELL that is pressed is the intent — which is also row 6 in the owner's own words
//     (*"i want to be able to click on buy and sell itself and do trades"*).
//   THE COUNT LINE.  `10 goods traded here, by name` — the list is on the screen, and a sentence
//     counting what the eye can see is §2 item 6's whole complaint.
//   THE ORDER LINE + `Issue this order`.  §5: no screen prints the order string. The tray's own
//     button is the act, and `orderText` is composed at issue time (src/live/useTrade.ts).
//   THE FOLD, and `inRowsOf` / `useTileCols` with it. The quantity opens in a `Tray` docked to the
//     bottom edge, so nothing above the press moves — the owner's rule kept exactly, without the
//     row arithmetic that existed only to insert a box into a grid (§5).
//
// ── WHAT IT STILL DOES NOT OWN ─────────────────────────────────────────────────────────────────
// No price arithmetic, no legality check, no grammar, no quantity rule. `buyableHere` is 0061's
// one answer to "can this be bought at this quay"; `fleetCargoByCode` is the one fold of a
// manifest; `useTrade` owns the capacity read and the one door (`cmd.issue`).
// ═══════════════════════════════════════════════════════════════════════════════════════════════

export function PortTrade({
  goods,
  fleet,
  culture,
}: {
  /** `world.market(port)`'s goods for THIS harbour — the read PortScreen already makes. */
  goods: readonly MarketGood[]
  /** A fleet of yours lying here, or null. Without one there is nothing to trade with. */
  fleet: FleetView | null
  /** This port's culture — printed only where it refuses a good (§6). */
  culture: string
}) {
  if (!fleet) {
    return (
      <Note tone="neutral">
        No fleet of yours lies here, so there is nothing to trade with. Send one and this quay will
        deal.
      </Note>
    )
  }
  return <QuayField goods={goods} fleet={fleet} culture={culture} />
}

/** The field and the pick, once there is a fleet to trade with — split so the hooks below never
 *  run for a quay with nobody alongside. */
function QuayField({ goods, fleet, culture }: { goods: readonly MarketGood[]; fleet: FleetView; culture: string }) {
  const [filter, setFilter] = useState('')
  const [pick, setPick] = useState<TradePick | null>(null)
  // The quantity is this screen's (COMMAND keeps its own on the order draft); the tray owns the
  // default and materialises it through `onChange`, so no rule is spelt here.
  const [qty, setQty] = useState<number | null>(null)

  const aboard = useMemo(() => fleetCargoByCode(fleet), [fleet])
  const shown = useMemo(() => {
    const q = fold(filter.trim())
    return goods
      // WHAT IS ON THIS QUAY, PLUS WHAT SHE IS CARRYING. 0061 makes those two different sets: a
      // hold is never stranded, so she may sell here what this city does not deal in.
      .filter((g) => g.available || (aboard[g.code] ?? 0) > 0)
      .filter((g) => foldedMatch(q, g.name, g.code, g.category))
      .sort((a, b) => a.name.localeCompare(b.name))
  }, [goods, filter, aboard])

  const close = () => {
    setPick(null)
    setQty(null)
  }
  const open = (good: MarketGood, intent: 'buy' | 'sell') => {
    setQty(null)
    setPick({ good, intent })
  }

  const { capacity, step, act } = useTrade(fleet, pick?.intent ?? 'buy', pick?.good ?? null, qty, close)

  return (
    <>
      <Field
        value={filter}
        onChange={(e) => setFilter(e.target.value)}
        onClear={() => setFilter('')}
        aria-label="Filter goods"
        placeholder="Filter goods"
        spellCheck={false}
        autoCorrect="off"
      />

      {shown.length === 0 ? (
        <Note tone="neutral" className="mt-3">
          Nothing here answers to that.
        </Note>
      ) : (
        <TileField className="mt-3">
          {shown.map((g) => (
            <TradeTile
              key={g.code}
              good={g}
              aboard={aboard[g.code] ?? 0}
              canBuy={buyableHere(g)}
              selected={pick?.good.code === g.code}
              onBuy={() => open(g, 'buy')}
              onSell={() => open(g, 'sell')}
            />
          ))}
        </TileField>
      )}

      {pick && (
        <TradeTray
          pick={pick}
          aboard={aboard[pick.good.code] ?? 0}
          capacity={capacity}
          step={step}
          qty={{ value: qty, onChange: setQty }}
          act={act}
          culture={culture}
          onClose={close}
        />
      )}
    </>
  )
}
