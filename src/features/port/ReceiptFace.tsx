import { deltaTone, Figure, Row } from '../../components/ui'
import { formatDucats, formatDucatsDelta, formatInt, formatTuns } from '../../lib/format'
import type { ManifestReceipt } from '../../lib/rpc'

// THE RECEIPT — the settlement chit, after the manifest has landed. docs/QUAY_LEDGER.md §3 E
// (owner row 76, slice 2): per-line settled figures, tax, spread, haggle saved, profit vs paid,
// net, purse before → after, `Trading +N xp`. No reputation row until a reputation authority
// exists; nothing is faked.
//
// EVERY FIGURE IS THE RECEIPT'S OWN (0083). The lines are what `cmd.do_buy` / `cmd.do_sell`
// returned inside the one transaction; the totals are the server's sums of them; the purse before
// and after were READ from `players.ducats`; the trading points from `player_progress`. This file
// subtracts nothing, sums nothing and signs nothing it was not told: a bought line is a debit, a
// sold line a credit, and `net` arrives signed.
//
// A sub-view of ManifestTray, split out so each file keeps one export and stays readable; it draws
// only the BODY of the receipt face — the tray, its title and its dismissal are the tray's.

export function ReceiptFace({ receipt }: { receipt: ManifestReceipt }) {
  const { lines, totals, purse, trading } = receipt
  const levelled = trading.level_after > trading.level_before
  return (
    <>
      {lines.map((l) => (
        <Row
          key={l.good}
          label={`${l.name} · ${formatTuns(l.qty)} ${l.side === 'sell' ? 'sold' : 'bought'}`}
          value={<Figure value={formatDucatsDelta(l.side === 'sell' ? l.total : -l.total)} />}
          data-testid="receipt-row"
        />
      ))}
      <Row label="Market tax" value={<Figure value={formatDucats(totals.tax)} />} data-testid="receipt-row" />
      <Row label="Spread" value={<Figure value={formatDucats(totals.spread)} />} data-testid="receipt-row" />
      {totals.haggle_saved > 0 && (
        <Row label="Haggle saved" value={<Figure value={formatDucats(totals.haggle_saved)} tone="success" />} data-testid="receipt-row" />
      )}
      {/* Only a manifest that SOLD something has a profit to state; the server answers 0 for a
          basket of buys, and 0 is not a figure a buyer earned. */}
      {totals.sold > 0 &&
        (totals.profit !== null ? (
          <Row
            label="Profit vs paid"
            value={<Figure value={formatDucatsDelta(totals.profit)} tone={deltaTone(totals.profit)} />}
            data-testid="receipt-row"
          />
        ) : (
          <Row label="Profit vs paid" tone="muted" value="not on record" data-testid="receipt-row" />
        ))}
      <Row
        label="Net to purse"
        value={<Figure value={formatDucatsDelta(totals.net)} size="figure" tone={deltaTone(totals.net)} />}
        data-testid="receipt-row"
      />
      <Row
        label="Purse"
        value={<Figure value={`${formatInt(purse.before)} → ${formatInt(purse.after)}`} unit="d." />}
        data-testid="receipt-row"
      />
      <Row
        label="Trading"
        value={<Figure value={`+${formatInt(trading.delta)}`} unit="xp" tone="success" />}
        hairline={false}
        data-testid="receipt-row"
      >
        {levelled && <span className="block text-t-caption text-ink-faint">{`Trading level ${trading.level_after}`}</span>}
      </Row>
    </>
  )
}
