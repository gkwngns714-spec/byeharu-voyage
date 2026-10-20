import { formatRealDuration, instantMs } from '../lib/format'
import type { MerchantDoing, PortMerchant } from '../lib/rpc'
import { t, wordTable } from '../lib/i18n'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE WORDS A HARBOUR USES FOR A MERCHANT — spelled once, read by PORT's section and the MAP's
// city tray (0104's six words; 0113's level; the rest countdown of 2026-10-13)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// `doing` is DERIVED BY THE SERVER (`public.merchant_doing_at`, 0104) from her route's stops and
// cursor, its hold and its pause, and from where her fleet is. This file spells each word and
// nothing else: a second copy of the rule here is how two readings of the same thing come to
// disagree (docs/NO_SPAGHETTI.md §1). They lived in features/port/MerchantsHere.tsx until the MAP's
// city tray needed the same six (owner, 2026-10-13: *"i want there to be a list"*), which is the
// moment a screen's private table becomes a shared one.
//
// Six, one each, every one a NAME a person would use (docs/WORDS.md laws 1 and 3). The owner's own
// three — started, resting, ending — are kept as the states they describe; `laid up` is WORDS.md's
// standing row for a merchant that cannot sail on, and `away` is the plain word for "her loop
// calls here and she is somewhere else on it".
export const DOING_WORD: Readonly<Record<MerchantDoing, string>> = wordTable({
  laid_up: 'town.m_laid_up',
  resting: 'town.m_resting',
  starting: 'town.m_starting',
  ending: 'town.m_ending',
  passing: 'town.m_passing',
  away: 'town.m_away',
})

/** The instant her rest ends, in ms — `next_lap_at`, the hold 0101 wrote — or null when she is
 *  not held (or the hold is a byte the server did not spell as a time). A LAID-UP merchant's hold
 *  is not a promise: a pause outranks a hold (0104), so hers is never printed as a countdown. */
export function restEndsAt(m: Pick<PortMerchant, 'doing' | 'next_lap_at'>): number | null {
  return m.doing === 'laid_up' ? null : instantMs(m.next_lap_at)
}

/**
 * HOW LONG UNTIL HER REST ENDS, as the list prints it: `2 h 14 min`, `4.7 min` — the one real-span
 * spelling src/lib/format already owns — and `ends soon` inside the last minute, because a figure
 * that reads `12 s` on a list that re-asks the server every few seconds is a stopwatch, not news.
 * A passed instant is `ends soon` too: the server flips her on its next tick and the next read says
 * so; counting up would be the client inventing a state.
 */
export function restLeft(endsAtMs: number, nowMs: number): string {
  const left = endsAtMs - nowMs
  return left < 60_000 ? t('town.endsSoon') : formatRealDuration(left)
}

/** Her level as the read serves it (0113): the company's four skills summed. A server that has not
 *  applied 0113 sends no key at all, and a list prints that absence rather than a nought. */
export function levelOf(m: PortMerchant): number | null {
  const level: unknown = m.level
  return typeof level === 'number' && Number.isFinite(level) ? level : null
}
