import { useMemo, useState } from 'react'
import { Bar, Field, Figure, goodIcon, Icon, Note, Tile, TileField } from '../../components/ui'
import { fleetCargoByCode } from '../../domain/fleet'
import { buyableHere } from '../../domain/market'
import { formatInt } from '../../lib/format'
import { fold, foldedMatch } from '../../lib/text'
import type { FleetView, MarketGood } from '../../lib/rpc'
import { TradeTray, type TradePick } from './TradeTray'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// TRADE, ON THE QUAY YOU ARE STANDING ON — docs/OWNER_REQUESTS.md row 53, redrawn to §6.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner: *"since each port, city will have different market - trade goods, i want buy and sell
// on port tab, the market in port tab - where i press market, then choose to trade."* 0061 and 0062
// made the market a fact about the PORT, so what is on the quay belongs on the harbour.
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
//     button is the act, and `orderText` is composed at issue time (TradeTray.tsx).
//   THE FOLD, and `inRowsOf` / `useTileCols` with it. The quantity opens in a `Tray` docked to the
//     bottom edge, so nothing above the press moves — the owner's rule kept exactly, without the
//     row arithmetic that existed only to insert a box into a grid (§5).
//
// ── WHAT IT STILL DOES NOT OWN ─────────────────────────────────────────────────────────────────
// No price arithmetic, no legality check, no grammar, no quantity rule. `buyableHere` is 0061's
// one answer to "can this be bought at this quay"; `fleetCargoByCode` is the one fold of a
// manifest; the tray owns the capacity read and the one door (`cmd.issue`).
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
  const [filter, setFilter] = useState('')
  const [pick, setPick] = useState<TradePick | null>(null)

  const aboard = useMemo(() => (fleet ? fleetCargoByCode(fleet) : {}), [fleet])
  const shown = useMemo(() => {
    const q = fold(filter.trim())
    return goods
      // WHAT IS ON THIS QUAY, PLUS WHAT SHE IS CARRYING. 0061 makes those two different sets: a
      // hold is never stranded, so she may sell here what this city does not deal in.
      .filter((g) => g.available || (aboard[g.code] ?? 0) > 0)
      .filter((g) => foldedMatch(q, g.name, g.code, g.category))
      .sort((a, b) => a.name.localeCompare(b.name))
  }, [goods, filter, aboard])

  if (!fleet) {
    return (
      <Note tone="neutral">
        No fleet of yours lies here, so there is nothing to trade with. Send one and this quay will
        deal.
      </Note>
    )
  }

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
          {shown.map((g) => {
            const carried = aboard[g.code] ?? 0
            const canBuy = buyableHere(g)
            return (
              /* THE ID IS THE ONE `tests/layout.spec.ts:355-437` MEASURES. The spec is written
                 against COMMAND, which still draws the old picker; it keeps that id so that when
                 step 5 swaps the composer onto this tile the proof travels with it — the field
                 shape, the 44px cells, the labelled figures and "none aboard" are the same four
                 assertions either way. */
              <Tile
                key={g.code}
                mark={<Icon name={goodIcon(g.code, g.category)} size={20} />}
                name={g.name}
                state={canBuy ? 'rest' : 'muted'}
                data-testid="good-pick-tile"
              >
                <span className="grid grid-cols-2 gap-1">
                  <PriceCell
                    label="buy"
                    price={g.buy}
                    onPress={() => setPick({ good: g, intent: 'buy' })}
                    dead={canBuy ? null : 'not traded here'}
                  />
                  <PriceCell
                    label="sell"
                    price={g.sell}
                    onPress={() => setPick({ good: g, intent: 'sell' })}
                    dead={carried > 0 ? null : 'none aboard'}
                  />
                </span>

                {/* HOW FAR THIS PRICE CAN TRAVEL (0071), as the bar §6 draws it: where today's
                    ask stands between the low and the high this quay can reach. */}
                <Bar
                  pct={span(g)}
                  tone="neutral"
                  label={`${g.name} price range`}
                  className="mt-1"
                />
                <span className="flex items-center justify-between text-t-caption text-ink-faint">
                  <span className="tabular-nums">{formatInt(g.range_lo)}</span>
                  <span className="tabular-nums">{formatInt(g.range_hi)}</span>
                </span>

                {/* The stock, in the six blocks the server bands it into. NEUTRAL until it is
                    nearly out: §4.4 reserves green and red for cheap-and-dear, and a full quay
                    painted green on every tile spends the one colour that means "gain" on a
                    quantity. Warning is the state a trader actually has to act on. */}
                <Bar
                  value={g.stock_band}
                  of={6}
                  tone={g.stock_band <= 1 ? 'warning' : 'neutral'}
                  label={`${g.name} in stock`}
                />
              </Tile>
            )
          })}
        </TileField>
      )}

      {pick && (
        <TradeTray pick={pick} fleet={fleet} culture={culture} onClose={() => setPick(null)} />
      )}
    </>
  )
}

/** Where today's ask stands inside the range, 0–100. A band of zero width reads as full. */
function span(g: MarketGood): number {
  const width = g.range_hi - g.range_lo
  if (!(width > 0)) return 100
  return ((g.buy - g.range_lo) / width) * 100
}

/**
 * ONE PRICE, AND THE TAP THAT MAKES IT A TRADE — the owner's row 6, kept literally: the price IS
 * the button. A dead cell says WHY on its own face ("none aboard"), because a control that goes
 * grey without a reason is the thing `tests/layout.spec.ts` was written to stop.
 */
function PriceCell({
  label,
  price,
  onPress,
  dead,
}: {
  label: 'buy' | 'sell'
  price: number
  onPress: () => void
  /** The reason this cell cannot be pressed, or null when it can. */
  dead: string | null
}) {
  return (
    <button
      type="button"
      onClick={onPress}
      disabled={dead !== null}
      className="min-h-11 rounded-control bg-surface-2 px-2 py-1 text-left disabled:opacity-45"
    >
      <span className="block text-t-caption text-ink-faint">{label}</span>
      <Figure value={formatInt(price)} />
      {dead !== null && <span className="block text-t-caption text-ink-faint">{dead}</span>}
    </button>
  )
}
