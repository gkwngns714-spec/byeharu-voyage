// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE RECEIPT, READ ONCE AT THE BOUNDARY — every numeric a number, whatever the transport did
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// `cmd.run_manifest` (0083) builds its receipt from jsonb, and a jsonb numeric can arrive as a JSON
// number or as a string depending on the transport (src/lib/json.ts records the day two screens
// read the same payload two ways). `useBuyCapacity.ts` answers that with `Number()` at its own
// boundary; a receipt has forty such fields, and forty casts scattered over a tray and a hook would
// be forty places to forget one. So the receipt is read HERE, once, and every caller of
// `cmdPreviewBasket` / `cmdTradeBasket` receives a `ManifestReceipt` whose numbers are numbers.
//
// MACHINERY. It decides nothing and sums nothing: a field the server did not send reads as 0 (a
// magnitude) or null (a basis, a profit — where null is a meaning), and that is the whole rule.

import { num, str } from '../json'
import type { ManifestReceipt, ManifestReceiptLine } from './types'

type Obj = Record<string, unknown>

const obj = (v: unknown): Obj | undefined => (v && typeof v === 'object' ? (v as Obj) : undefined)
/** A magnitude the server always sends. Absent reads as 0 rather than NaN. */
const n0 = (o: Obj | undefined, k: string): number => num(o, k) ?? 0

function readLine(raw: unknown): ManifestReceiptLine {
  const l = obj(raw)
  return {
    index: n0(l, 'index'),
    side: str(l, 'side') === 'sell' ? 'sell' : 'buy',
    good: str(l, 'good') ?? '',
    name: str(l, 'name') ?? '',
    qty: n0(l, 'qty'),
    total: n0(l, 'total'),
    avg_price: n0(l, 'avg_price'),
    mid_total: n0(l, 'mid_total'),
    tax_total: n0(l, 'tax_total'),
    spread_total: n0(l, 'spread_total'),
    haggle_saved: n0(l, 'haggle_saved'),
    concession_spent: n0(l, 'concession_spent'),
    basis: num(l, 'basis'),
    cost: num(l, 'cost'),
    profit: num(l, 'profit'),
  }
}

/** The served receipt (a preview's `estimate` or a commit's whole payload), numerics normalised. */
export function readManifestReceipt(payload: unknown): ManifestReceipt {
  const r = obj(payload)
  const totals = obj(r?.totals)
  const purse = obj(r?.purse)
  const hold = obj(r?.hold)
  const trading = obj(r?.trading)
  const version = num(r, 'version')
  return {
    ok: true,
    kind: 'manifest',
    port: str(r, 'port') ?? '',
    fleet: str(r, 'fleet') ?? '',
    game_day: n0(r, 'game_day'),
    at: str(r, 'at') ?? '',
    lines: Array.isArray(r?.lines) ? r.lines.map(readLine) : [],
    totals: {
      goods_at_mid: n0(totals, 'goods_at_mid'),
      tax: n0(totals, 'tax'),
      spread: n0(totals, 'spread'),
      haggle_saved: n0(totals, 'haggle_saved'),
      profit: num(totals, 'profit'),
      bought: n0(totals, 'bought'),
      sold: n0(totals, 'sold'),
      net: n0(totals, 'net'),
    },
    purse: { before: n0(purse, 'before'), after: n0(purse, 'after') },
    hold: {
      free_before: n0(hold, 'free_before'),
      free_after: n0(hold, 'free_after'),
      tuns_delta: n0(hold, 'tuns_delta'),
    },
    trading: {
      points_before: n0(trading, 'points_before'),
      points_after: n0(trading, 'points_after'),
      delta: n0(trading, 'delta'),
      level_before: n0(trading, 'level_before'),
      level_after: n0(trading, 'level_after'),
      turnover_after: n0(trading, 'turnover_after'),
    },
    ...(version !== null ? { version } : {}),
  }
}
