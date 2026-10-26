// THE MONEY LOG'S SECTORS (owner 227: *"the money log, make filter by different sector, such as insurance,
// supplies, bought, repairs and so on"*). ONE map from a row's ledger/treasury `kind` to the sector it is filed
// under; a kind not listed is `other`. Bought/Sold are by the ROW's side — a company's SELL is a sale, but the
// city's side of the same move is a purchase (the same flip as the feed's c_SELL / c_BUY words).

export const SECTORS = ['bought', 'sold', 'supplies', 'wages', 'repairs', 'insurance', 'tax', 'fees', 'gifts', 'shares', 'other'] as const
export type Sector = (typeof SECTORS)[number]

const BY_KIND: Readonly<Record<string, Sector>> = {
  PROVISION: 'supplies',
  WAGES: 'wages',
  HIRE: 'wages',
  REPAIR: 'repairs',
  TOW: 'repairs',
  INSURANCE: 'insurance',
  INSURANCE_PAID: 'insurance',
  TAX: 'tax',
  CROWN_TAX: 'tax',
  PORT_FEE: 'fees',
  CAPITAL_GIFT: 'gifts',
  DONATION: 'gifts',
  GRANT: 'gifts',
  CROWN_AID: 'gifts',
  SHARE: 'shares',
  DIVIDEND: 'shares',
}

export function sectorOf(kind: string, holder: string): Sector {
  if (kind === 'BUY') return holder === 'city' ? 'sold' : 'bought'
  if (kind === 'SELL') return holder === 'city' ? 'bought' : 'sold'
  return BY_KIND[kind] ?? 'other'
}
