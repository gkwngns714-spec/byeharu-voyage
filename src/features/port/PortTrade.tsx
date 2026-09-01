import { useState } from 'react'
import { Button, GoodPicker, RefusalNote, TabRow } from '../../components/ui'
import { useBuyCapacity } from '../../live/useBuyCapacity'
import { fleetCargoByCode } from '../../domain/fleet'
import { findVerb, isComplete, orderText } from '../../domain/order'
import { buyableHere } from '../../domain/market'
import type { FleetView, MarketGood, Refusal, VerbSpec } from '../../lib/rpc'
import { useWorld } from '../../live/worldStore'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// TRADE, ON THE PORT YOU ARE STANDING IN — docs/OWNER_REQUESTS.md row 53.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner: *"since each port, city will have different market - trade goods, i want buy and sell
// on port tab, the market in port tab - where i press market, then choose to trade."*
//
// They gave the reason in the same breath and it is the whole argument: **0061 and 0062 made the
// market a fact about the PORT.** A city trades its own 4-10 goods now, so "what is on the quay"
// stopped being a global price list you visit and became part of what this harbour IS. It belongs
// on the harbour.
//
// ── THIS SCREEN USED TO SAY IT NEVER ISSUES ANYTHING ───────────────────────────────────────────
// PortScreen's header carried: *"It also keeps law 2 intact: commands live on their own tab. This
// screen never issues anything."* That sentence is retired here, and it is the same retirement the
// MAP already went through: the owner's verdict there was that a map you cannot act from is a
// picture, and `SendFleet` now completes the act on the map. A quay you cannot trade on is the
// same defect wearing a different hat. Rows 15/20/25/28/45/46/51 are all one instruction — do not
// send me to another screen — and this is that instruction applied to the market.
//
// ── WHAT IS COMPOSED, AND WHAT IS DELIBERATELY NOT BUILT ───────────────────────────────────────
// Nothing here is a second anything. Every part is the part COMMAND already uses:
//
//   `GoodPicker`      the good list, the buy/sell cells and the quantity fold that unfolds under
//                     the pressed row (row 6's shape), taking plain
//                     props. It lives in the design system (components/ui/tradePickers) so
//                     both quays reach it through the one entrance — one fold, two callers.
//   `useBuyCapacity`  the ONE reading of `world.buy_capacity()`, asked about the inspected good.
//   `buyableHere`     0061's one answer to "can this be bought at this quay" — culture AND roster.
//   `fleetCargoByCode` the fleet's own manifest, so a SELL cell can say "none aboard".
//   `orderText`       the exact line the server is sent, from the server's own verb grammar.
//   `issue`           the one door (`cmd.issue`). There is no second way an order comes into being.
//
// So this file owns NO price arithmetic, NO legality check, NO grammar and NO quantity rule. It is
// a place where the existing fold is shown, and one button that sends the line it composed.
//
// ── WHY THE BUY/SELL FACES EXIST ───────────────────────────────────────────────────────────────
// Not decoration: `GoodPicker` shapes its LIST from `intent`. A BUY list is this city's quay
// (`offered !== false`); a SELL list is what she is carrying, which under 0061 is deliberately
// wider than the roster — a hold is never stranded, so she may sell here what this city does not
// trade. Gaivota lying at Bilbao with olive oil the Basques do not deal in is exactly that case,
// and it is unreachable without choosing the face first.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

type Intent = 'buy' | 'sell'

const FACES = [
  { id: 'buy' as const, label: 'Buy' },
  { id: 'sell' as const, label: 'Sell' },
]

export function PortTrade({
  goods,
  fleet,
  verbs,
  step,
}: {
  /** `world.market(port)`'s goods for THIS harbour — the read PortScreen already makes. */
  goods: readonly MarketGood[]
  /** A fleet of yours lying here, or null. Without one there is nothing to trade with. */
  fleet: FleetView | null
  /** The server's own verb grammar. Nothing here lists verbs. */
  verbs: readonly VerbSpec[]
  /** `config.trade_step_tuns` — the stepper walks in the server's own steps. */
  step: number
}) {
  const [intent, setIntent] = useState<Intent>('buy')
  const [inspecting, setInspecting] = useState<string | null>(null)
  const [good, setGood] = useState<string | undefined>(undefined)
  const [qty, setQty] = useState<string | undefined>(undefined)
  const [sending, setSending] = useState(false)
  const [refusal, setRefusal] = useState<Refusal | null>(null)
  const [sent, setSent] = useState<string | null>(null)

  const issue = useWorld((s) => s.issue)

  // ONE reading of world.buy_capacity(), and only while BUYING — a sell has no purse ceiling.
  const capacity = useBuyCapacity(intent === 'buy' ? (fleet?.id ?? null) : null, inspecting)

  const spec = findVerb(verbs, intent === 'buy' ? 'BUY' : 'SELL')
  const aboard = fleet ? fleetCargoByCode(fleet) : undefined

  if (!fleet) {
    return (
      <p className="text-sm text-ink-muted">
        No fleet of yours lies here, so there is nothing to trade with. Send one and this quay will
        deal.
      </p>
    )
  }

  // THE LINE, exactly as the server will read it. Built by the one composer helper, from the
  // server's own grammar — never assembled by hand here.
  const args: Record<string, string> = {}
  if (good) args.good = good
  if (qty) args.qty = qty
  const ready = spec !== undefined && isComplete(spec, args)
  const line = spec && ready ? orderText(spec, args, fleet.name) : null

  const reset = () => {
    setGood(undefined)
    setQty(undefined)
    setInspecting(null)
  }

  const send = () => {
    if (!line || sending) return
    setSending(true)
    setRefusal(null)
    setSent(null)
    void (async () => {
      const okay = await issue(fleet.id, line, null)
      setSending(false)
      if (okay) {
        setSent(line)
        reset()
      } else {
        setRefusal(useWorld.getState().refusal)
      }
    })()
  }

  return (
    <div className="space-y-3" data-testid="port-trade">
      {/* CHOOSING THE FACE IS CHOOSING THE LIST — see the header. Pressing one SELECTS; it never
          re-flows what surrounds it (the owner's standing rule, said four times). */}
      <TabRow
        tabs={FACES}
        value={intent}
        label="Buy or sell"
        onChange={(next) => {
          setIntent(next)
          // A good chosen for a BUY is not a chosen SELL — the lists are different sets and
          // carrying the code across would leave a line the other list cannot show.
          reset()
        }}
      />

      <GoodPicker
        goods={goods.filter((g) => (intent === 'buy' ? buyableHere(g) : true))}
        value={good}
        aboard={aboard}
        intent={intent}
        inspecting={inspecting}
        onInspect={setInspecting}
        capacity={capacity}
        onTrade={(verb: 'BUY' | 'SELL', code: string) => {
          setIntent(verb === 'BUY' ? 'buy' : 'sell')
          setGood(code)
          setSent(null)
          setRefusal(null)
        }}
        step={step}
        qtyValue={qty}
        onPickQty={setQty}
      />

      {/* THE ONE ACT. It appears only when the order is WHOLE by the server's own grammar
          (`isComplete`), so there is never a button that would compose half a line. */}
      {line && (
        <div className="space-y-2">
          <p className="font-mono text-xs text-ink" data-testid="port-trade-line">
            &gt; {line}
          </p>
          <Button variant="primary" onClick={send} disabled={sending} data-testid="port-trade-send">
            {sending ? 'Sending…' : 'Issue this order'}
          </Button>
        </div>
      )}

      {sent && (
        <p className="font-mono text-xs text-sea" data-testid="port-trade-sent">
          sent: {sent}
        </p>
      )}

      {/* A refusal is the server's, drawn by the ONE renderer every other surface uses (0050). */}
      {refusal && <RefusalNote refusal={refusal} />}
    </div>
  )
}
