import type { IconName } from '../components/ui'

// THE TAB TABLE — pure data + policy (no React), so the navigation contract can be pinned by a
// spec instead of read out of JSX. NavBar renders EXACTLY this list; there is no second table.
//
// ── THE EIGHT DESTINATIONS, and why each is its own tab ─────────────────────────────────────────
//   Command  compose orders. THE ONLY PLACE AN ORDER IS GIVEN. Sail, load, unload, sell, buy.
//   Fleets   what you own and where it is: ships, crew, hold, condition.
//   Port     the harbour you are in — its services, its dues, its news.
//   Market   prices here, prices remembered elsewhere, spreads.
//   Map      WHERE THINGS ARE. Read-only, always (see MapScreen).
//   Ledger   the running record: voyages, trades, profit and loss.
//   Rank     standings among captains.
//   Profile  account, session, preferences.
//
// ── EIGHT ON A PHONE ────────────────────────────────────────────────────────────────────────────
// Eight cells in one row at 320px is 40px each, under the 44px touch floor. So the bar is TWO ROWS
// of four on a phone and one row of eight from `sm` up: 320 ÷ 4 = 80px per cell, comfortably over
// the floor, at a cost of one extra 44px band of chrome.
//
// THAT IS ARITHMETIC, NOT A MEASUREMENT — nothing here has been rendered and measured yet. byeharu
// carried a paragraph claiming five tabs was the ceiling; when someone finally rendered it, six fit
// and the paragraph had been wrong for months. So: the first UI proof this repo grows should render
// THIS table through NavBar at 320px and assert per cell — width ≥ 44, height ≥ 44, label
// scrollWidth ≤ clientWidth, and no horizontal page scroll. Until that proof exists, treat the
// numbers above as an estimate that has not been checked.

export interface NavTab {
  to: string
  label: string
  icon: IconName
}

const ALL_TABS: readonly (NavTab & { enabled: boolean })[] = [
  { to: '/command', label: 'Command', icon: 'compass', enabled: true },
  { to: '/fleets', label: 'Fleets', icon: 'ship', enabled: true },
  { to: '/port', label: 'Port', icon: 'anchor', enabled: true },
  { to: '/market', label: 'Market', icon: 'scales', enabled: true },
  { to: '/map', label: 'Map', icon: 'chart', enabled: true },
  { to: '/ledger', label: 'Ledger', icon: 'ledger', enabled: true },
  { to: '/rank', label: 'Rank', icon: 'wreath', enabled: true },
  { to: '/profile', label: 'Profile', icon: 'profile', enabled: true },
]

/** The tabs NavBar renders, in order. `enabled: false` drops a destination entirely — DARK-FIRST:
 *  a tab may never lead to a screen that has nothing behind it yet. */
export const NAV_TABS: readonly NavTab[] = ALL_TABS.filter((t) => t.enabled).map(
  ({ to, label, icon }) => ({ to, label, icon }),
)

/** The landing destination. Orders are the point of the game, so the app opens on Command. */
export const HOME_TAB = '/command'

/** The nav grid classes for a tab count. STATIC literals only — Tailwind scans source text, so a
 *  computed class name (`sm:grid-cols-${n}`) would be tree-shaken out of the stylesheet and the bar
 *  would silently collapse. Mobile is always four across; the desktop row carries them all. */
export function navGridClass(count: number): string {
  const DESKTOP: Record<number, string> = {
    4: 'sm:grid-cols-4',
    5: 'sm:grid-cols-5',
    6: 'sm:grid-cols-6',
    7: 'sm:grid-cols-7',
    8: 'sm:grid-cols-8',
  }
  return `grid-cols-4 ${DESKTOP[count] ?? 'sm:grid-cols-8'}`
}
