import type { IconName } from '../components/ui'

// THE TAB TABLE — pure data + policy (no React), so the navigation contract can be pinned by a
// spec instead of read out of JSX. NavBar renders EXACTLY this list; there is no second table.
//
// ── THE EIGHT DESTINATIONS, and why each is its own tab ─────────────────────────────────────────
//   Command  compose orders. THE ONLY PLACE AN ORDER IS COMPOSED. Sail, load, unload, sell, buy.
//            Four tabs HAND an order to it — Fleets, Port, Market and (2026-08-23) Map — and none
//            of them composes one: they name an intent, `domain/order`'s draft holds it, and this
//            tab turns it into the single line `cmd.issue()` receives.
//   Fleets   what you own and where it is: ships, crew, hold, condition.
//   Port     the harbour you are in — its services, its dues, its news.
//   Market   prices here, prices remembered elsewhere, spreads.
//   Map      WHERE THINGS ARE — and, since 2026-08-23, where you can act on that: tapping a harbour
//            offers `Sail here`, which is a HAND-OFF to Command, never a second composer. This line
//            read "Read-only, always"; MapScreen's header carries why that was the wrong rule.
//   Ledger   the running record: voyages, trades, profit and loss.
//   Rank     standings among captains.
//   Codex    the compendium (도감): every good, hull, officer and flag the world serves, whether
//            or not you have met it. A reference — it commands nothing.
//   Profile  account, session, preferences.
//
// ── NINE ON A PHONE ─────────────────────────────────────────────────────────────────────────────
// Nine cells in one row at 320px is 35px each, under the 44px touch floor. Four across — the shape
// eight tabs wore — leaves 4+4+1: a last row with ONE orphaned cell, which reads as a mistake and
// wastes a whole 56px band on a single tab. So at nine the phone bar is THREE ROWS OF THREE
// (320 ÷ 3 = 106px, 390 ÷ 3 = 130px per cell — both comfortably over the floor) and one row of
// nine from `sm` up (640 ÷ 9 = 71px at the breakpoint's worst).
//
// MEASURED 2026-08-23, chromium against the built app (the paragraph that stood here called its
// own numbers "an estimate that has not been checked"; these are rendered and read back):
//   390×844  every cell 130×56px in a 3×3 bar 169px tall; every label's scrollWidth equals its
//            clientWidth (widest: COMMAND and PROFILE at 46px, CODEX at 33px); page scrollWidth
//            390 = clientWidth. The 8-tab bar it replaced measured 4×2, cells 98×56, bar 113px.
//   1440×900 one row of nine, cells 100×56 (the bar's max-w-4xl is what caps them), no page
//            scroll. 640 ÷ 9 = 71px at the breakpoint's worst still clears the widest 46px label.

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
  // "Codex", not "Compendium": both mean the 도감, and the shorter word is the one that must fit a
  // 71px cell at the `sm` breakpoint's worst. The screen's own title spells it out in full.
  { to: '/compendium', label: 'Codex', icon: 'codex', enabled: true },
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
 *  would silently collapse. The desktop row carries them all; the phone wraps — and the phone
 *  column count is chosen so NO row is left with an orphan cell: four across divides 8 and 12
 *  cleanly, three across divides 9 (see "NINE ON A PHONE" above). A count this table does not
 *  know falls back to four across, which at worst rags the last row — it never clips a cell. */
export function navGridClass(count: number): string {
  const GRID: Record<number, string> = {
    4: 'grid-cols-4 sm:grid-cols-4',
    5: 'grid-cols-4 sm:grid-cols-5',
    6: 'grid-cols-3 sm:grid-cols-6',
    7: 'grid-cols-4 sm:grid-cols-7',
    8: 'grid-cols-4 sm:grid-cols-8',
    9: 'grid-cols-3 sm:grid-cols-9',
  }
  return GRID[count] ?? 'grid-cols-4 sm:grid-cols-8'
}
