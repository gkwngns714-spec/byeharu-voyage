import { deltaTone, Figure, Row } from '../../components/ui'
import { formatDucats, formatDucatsDelta } from '../../lib/format'
import type { ManifestReceipt } from '../../lib/rpc'

// THE TOTALS BLOCK — what a basket comes to, in five rows, spelt ONCE for its two readers.
//
// docs/QUAY_LEDGER.md §3 C (the basket: "served totals") and E (the receipt: "tax, spread, haggle
// saved, profit vs paid, net"). PR #59 printed these rows twice — once in the basket face, once in
// the receipt — and the adversarial review named it (SHOULD 4a): the day a row is renamed or one
// is added, two files would have to move together or drift. This is the one place.
//
// EVERY FIGURE IS THE SERVER'S (0083): `world.quote`'s four breakdown columns summed per line
// inside the dry run or the commit; `profit` is `cmd.do_sell`'s own against the cost basis (0081),
// null when any sold line's cost was not on record; `net` is `sold − bought`, signed, and is the
// only figure the purse moves by. Nothing here adds two served numbers together.
//
// WHAT IS SHOWN WHEN. Market tax, Port fee and Net always — they are what a basket IS. Haggle
// saved only when a bargain bit (a zero would say "you saved nothing" about a basket that never
// tried). Profit only when something was SOLD: the server answers 0 for a basket of buys, and 0 is
// not a figure a buyer earned. docs/WORDS.md: "Port fee", "Bought at", never "the port's cut" or
// "paid".

export function ManifestTotals({
  totals,
  testId,
}: {
  totals: ManifestReceipt['totals']
  /** The caller's row test id — the basket's rows and the receipt's rows are counted apart. */
  testId: string
}) {
  return (
    <>
      <Row label="Market tax" value={<Figure value={formatDucats(totals.tax)} />} data-testid={testId} />
      <Row label="Port fee" value={<Figure value={formatDucats(totals.spread)} />} data-testid={testId} />
      {totals.haggle_saved > 0 && (
        <Row label="Haggle saved" value={<Figure value={formatDucats(totals.haggle_saved)} tone="success" />} data-testid={testId} />
      )}
      {totals.sold > 0 &&
        (totals.profit !== null ? (
          <Row
            label="Profit vs bought at"
            value={<Figure value={formatDucatsDelta(totals.profit)} tone={deltaTone(totals.profit)} />}
            data-testid={testId}
          />
        ) : (
          <Row label="Profit vs bought at" tone="muted" value="unknown" data-testid={testId} />
        ))}
      <Row
        label="Net"
        value={<Figure value={formatDucatsDelta(totals.net)} size="figure" tone={deltaTone(totals.net)} />}
        hairline={false}
        data-testid={testId}
      />
    </>
  )
}
