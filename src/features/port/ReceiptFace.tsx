import { deltaTone, Figure, Row } from '../../components/ui'
import { ManifestTotals } from './ManifestTotals'
import { formatDucatsDelta, formatInt, formatUnitPrice, formatUnits } from '../../lib/format'
import { lineDelta, type ManifestReceipt } from '../../lib/rpc'

// THE RECEIPT — the settlement, after the basket has landed. docs/QUAY_LEDGER.md §3 E (owner row
// 76, slice 2): per-line settled figures, the totals block, ducats before → after, `Trading +N xp`.
// No reputation row until a reputation authority exists; nothing is faked.
//
// EVERY FIGURE IS THE RECEIPT'S OWN (0083). The lines are what `cmd.do_buy` / `cmd.do_sell`
// returned inside the one transaction; the totals are the server's sums of them (ManifestTotals,
// the same block the basket printed a moment ago); the purse before and after were READ from
// `players.ducats`; the trading points from `player_progress`. This file subtracts nothing and
// sums nothing. The ONE sign it prints — a bought line is a debit, a sold line a credit — is
// `lineDelta`, spelt at the boundary for both faces (PR #59 review SHOULD 4b).
//
// The BODY of the receipt face only: the panel, its title and its dismissal are ManifestPanel's.

export function ReceiptFace({ receipt }: { receipt: ManifestReceipt }) {
  const { lines, totals, purse, trading } = receipt
  const levelled = trading.level_after > trading.level_before
  return (
    <>
      {lines.map((l) => (
        <Row
          key={l.good}
          label={l.name}
          value={<Figure value={formatDucatsDelta(lineDelta(l))} />}
          data-testid="receipt-row"
        >
          <span className="block text-t-caption text-ink-faint">
            {`${l.side === 'sell' ? 'sold' : 'bought'} · ${formatUnits(l.qty)} · ${formatUnitPrice(l.avg_price)}`}
          </span>
        </Row>
      ))}
      <ManifestTotals totals={totals} testId="receipt-row" />
      <Row
        label="Ducats"
        value={<Figure value={`${formatInt(purse.before)} → ${formatInt(purse.after)}`} unit="d." />}
        data-testid="receipt-row"
      />
      {/* A small basket earns 0 xp, and 0 painted green would say "gain" about nothing — deltaTone
          (PR #59 review NIT 9). */}
      <Row
        label="Trading"
        value={<Figure value={`${trading.delta > 0 ? '+' : ''}${formatInt(trading.delta)}`} unit="xp" tone={deltaTone(trading.delta)} />}
        hairline={false}
        data-testid="receipt-row"
      >
        {levelled && <span className="block text-t-caption text-ink-faint">{`Trading level ${formatInt(trading.level_after)}`}</span>}
      </Row>
    </>
  )
}
