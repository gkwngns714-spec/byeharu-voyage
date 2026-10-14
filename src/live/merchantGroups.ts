import type { MerchantDoing, PortMerchant } from '../lib/rpc'
import { restEndsAt } from './merchantWords'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A HARBOUR'S MERCHANTS, GROUPED BY WHAT EACH IS DOING — the ONE grouping (owner, 2026-10-14)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, 2026-10-11 (row 121): *"By clicking the city, i get to see what trading ships
// started, resting, ending etc."* — and 2026-10-13 (row 128): *"when i press city … i want there
// to be a list, showing the total level, and its current time till the resting finishes."* Then,
// 2026-10-14: *"i press a city and i see no ship info. Why did this revert back?"*
//
// WHAT WENT WRONG. The city tray listed only the merchants LYING in the city (`m.port === code`),
// and since 0116 a merchant rests two real minutes, so a harbour the server answers with
// twenty-five merchants showed none at all. Row 121 was the whole sentence — started, resting,
// ending, etc. — and the filter kept one word of it.
//
// WHAT THIS IS. The harbour's read (`world.port_merchants`, 0104) serves every merchant whose loop
// calls here, ranked by the server: laid_up 1 · resting 2 · starting 3 · ending 4 · passing 5 ·
// away 6 — "the ones who are here first, then the ones coming, then the rest". This file cuts
// that one ranked list into headed groups and changes NOTHING about it: the groups are in the
// server's rank, the rows inside a group keep the server's order, and the only sort of its own is
// the one row 128 asked for — in port, the merchant whose rest ends soonest stands first. A group
// with nobody in it is not printed (an empty label is not a state); a harbour with merchants is
// never printed as empty.
//
// WHERE IT LIVES AND WHO READS IT. `src/live`, beside the words (merchantWords.ts) and the row
// (MerchantRow.tsx), because a grouping of a harbour's merchants is a fact about the harbour's
// read and not about the screen that prints it. Today the MAP's city tray groups and PORT's
// "Merchants" section prints the same list flat; the day PORT groups too, it composes THIS and
// does not write a second table of which word goes under which heading (docs/NO_SPAGHETTI.md
// §1, §7B). The headings are docs/WORDS.md words: `in port` is the law's own row for a ship in
// port; arriving, leaving, passing and away are the plain words for the server's four.
//
// NOTHING HERE IS WORKED OUT. `doing` is the server's (public.merchant_doing_at, 0104), the rest
// instant is `next_lap_at` (0101), and a level is the server's (0113). This file only decides
// which heading a served word stands under.

export type MerchantGroupKey = 'in_port' | 'leaving' | 'arriving' | 'passing' | 'away'

export interface MerchantGroup {
  key: MerchantGroupKey
  /** The heading the list prints — a docs/WORDS.md word. */
  heading: string
  rows: PortMerchant[]
}

/**
 * THE GROUPS, in the server's rank (0104): who is here, then who is coming, then the rest. The
 * `doing` words each one holds are the server's; a word belongs to exactly one group, and the
 * table below is the only place that says which.
 */
export const MERCHANT_GROUPS: readonly { key: MerchantGroupKey; heading: string; doings: readonly MerchantDoing[] }[] = [
  // LYING HERE, and not free to sail: held for her rest (with the time it ends) or laid up.
  { key: 'in_port', heading: 'In port', doings: ['laid_up', 'resting'] },
  // AT HER HOME QUAY AND FREE TO SAIL — the lap starts here on the server's next tick.
  { key: 'leaving', heading: 'Leaving', doings: ['starting'] },
  // AT SEA, BOUND HERE as the last call of her lap.
  { key: 'arriving', heading: 'Arriving', doings: ['ending'] },
  // A CALL IN THE MIDDLE of her loop — here, or at sea bound here.
  { key: 'passing', heading: 'Passing', doings: ['passing'] },
  // HER LOOP CALLS HERE and she is somewhere else on it.
  { key: 'away', heading: 'Away', doings: ['away'] },
]

/** The group a served word stands under. Total over `MerchantDoing` by construction of the table. */
export function groupOf(doing: MerchantDoing): MerchantGroupKey {
  const g = MERCHANT_GROUPS.find((x) => x.doings.includes(doing))
  if (!g) throw new Error(`merchantGroups: no group holds the word "${doing}"`)
  return g.key
}

/**
 * Cut the harbour's ranked list into its groups. Empty groups are omitted. Inside `in_port` the
 * soonest rest-end stands first and the rows with no instant (laid up, or a hold the server did
 * not spell as a time) follow in the server's order; every other group keeps the server's order
 * exactly. A sort is a VIEW: no figure is changed by it.
 */
export function groupMerchants(rows: readonly PortMerchant[]): MerchantGroup[] {
  // Bucketed through `groupOf`, not filtered per group: a served word the table does not hold
  // is an error, never a merchant quietly left off the list (docs/NO_SPAGHETTI.md §7C).
  const by = new Map<MerchantGroupKey, PortMerchant[]>()
  for (const m of rows) {
    const key = groupOf(m.doing)
    const bucket = by.get(key)
    if (bucket) bucket.push(m)
    else by.set(key, [m])
  }
  const out: MerchantGroup[] = []
  for (const g of MERCHANT_GROUPS) {
    const mine = by.get(g.key)
    if (!mine) continue
    out.push({ key: g.key, heading: g.heading, rows: g.key === 'in_port' ? soonestFirst(mine) : mine })
  }
  return out
}

function soonestFirst(rows: readonly PortMerchant[]): PortMerchant[] {
  const withEnd = rows.map((m, i) => ({ m, i, ends: restEndsAt(m) }))
  withEnd.sort((a, b) => {
    if (a.ends !== null && b.ends !== null) return a.ends - b.ends || a.i - b.i
    if (a.ends !== null) return -1
    if (b.ends !== null) return 1
    return a.i - b.i
  })
  return withEnd.map((x) => x.m)
}

/**
 * THE CITY'S ONE LINE at the tray's peek: `27 merchants · 2 in port`, `1 merchant`, or '' when the
 * harbour concerns nobody. Counts what the server served, never a guess from where she is, and it
 * says how many there are in all BEFORE how many lie here — a city with twenty-five merchants on
 * its loops and none at its quay this minute is a busy city, not an empty one.
 */
export function merchantsSummary(rows: readonly PortMerchant[]): string {
  if (rows.length === 0) return ''
  const inPort = rows.filter((m) => groupOf(m.doing) === 'in_port').length
  const all = `${rows.length} ${rows.length === 1 ? 'merchant' : 'merchants'}`
  return inPort > 0 ? `${all} · ${inPort} in port` : all
}
