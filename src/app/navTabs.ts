import type { IconName } from '../components/ui'

// THE TAB TABLE — pure data + policy (no React), so the navigation contract can be pinned by a
// spec instead of read out of JSX. NavBar renders EXACTLY this list; there is no second table.
//
// ── THE NINE DESTINATIONS, and why each is its own screen ───────────────────────────────────────
//   Command  whose orders, and what she has been told: her queue, the halt, cancel and clear.
//            Since 2026-09-09 it composes NO verb — the owner: *"they should be located
//            accordingly at different locations"* — every verb's doorway is on the face of the
//            building whose act it is (PORT) or on the chart (SAIL). FLEETS' "Command her" still
//            points it at a hull through `domain/order`'s draft; nothing hands it a verb.
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
// ── NINE DESTINATIONS, SIX CELLS (2026-08-25) ───────────────────────────────────────────────────
// Nine cells in one row at 390px is 43px each — under the 44px reach floor, and under the 46px the
// widest label (COMMAND) needs. The bar therefore WRAPPED: three rows of three, MEASURED at
// 390×844 as nine cells of 130×56 in a bar **168px tall**, which is 19.9% of the screen spent on
// navigation before the game gets a pixel. `docs/OWNER_REQUESTS.md` recorded the open question —
// *"noted here in case the answer is to group tabs rather than add a row"* — and the owner's answer
// was: **group them. No second row.**
//
// THE GROUPING IS READ OFF THE INFORMATION ARCHITECTURE, not off an arithmetic split. Ask of each
// destination "what kind of thing is this?" and the nine fall into two kinds:
//
//   THE VOYAGE — the loop you are actually playing. You compose an order (Command) with the ships
//   you own (Fleets), in the harbour you are docked at (Port), against its prices (Market), across
//   the sea (Map). Every one of these is touched many times a session, and `docs/UI_DIRECTION.md`
//   §3a is explicit that depth added to a frequent act is a DEFECT — the reference game's own
//   convenience team exists to undo exactly that. So all five stay ONE TAP. None is grouped.
//
//   THE CABIN — what a captain keeps at his desk. The ledger he writes up, the standings he is
//   listed in, the compendium he looks things up in, and the papers that say who he is. The kind
//   they share is not "leftovers": **none of them acts on the world.** Ledger, Rank and Codex are
//   read-only by construction (Codex's line above already says "it commands nothing"), and Profile
//   is the account rather than the voyage. They are consulted, not played. One extra tap to reach a
//   thing you consult is the trade the frequent five are being spared.
//
// The names were checked against the owner's "one word per idea across the whole game": CABIN
// collides with nothing in the game's vocabulary. RECORDS was the obvious label and was rejected —
// `Ledger` is already defined above as "the running record", so a group called Records containing a
// tab called Ledger is two words for one idea. HARBOUR was likewise rejected as a group over
// {Port, Market}: navTabs already glosses Port as "the harbour you are in", so the two words name
// the same place — and Market is played too often to sit behind a tap anyway.
//
// MEASURED 2026-08-25, chromium against the built app (tests/nav.geometry.spec.ts prints the line
// and asserts every number in it):
//   390×844  six cells of 65×56 in a bar **56px tall**, one row. Every label's scrollWidth equals
//            its clientWidth. Page scrollWidth 390 = clientWidth. The 9-tab bar it replaces
//            measured 3 rows, cells 130×56, bar 168px — so the game gained 112px of screen.
//   320×568  six cells of 53×56 in one row, widest label 46px, none shaved — clear of both the
//            44px reach floor and the 46px COMMAND needs. This is why SIX and not seven: 320 ÷ 7 is
//            45.7px, and COMMAND would be shaved by the arithmetic alone.

export interface NavTab {
  to: string
  label: string
  icon: IconName
}

/** The groups the bar may fold tabs into. A group is a CELL that REVEALS its members; it is never
 *  a destination itself and it has no route — adding one here without adding members leaves an
 *  empty cell, which `NAV_CELLS` cannot produce because a group exists only where a tab claims it. */
export type NavGroupId = 'cabin'

interface NavGroup {
  label: string
  /** The chevron, not a subject glyph. A group cell's honest graphic is "this opens" — every other
   *  icon in this table names a place, and no single place-glyph is true of all four members (a
   *  book is not a wreath is not an account). The `Nav` primitive points it up while the tray is
   *  shut and down while it is standing. */
  icon: IconName
}

const GROUPS: Record<NavGroupId, NavGroup> = {
  cabin: { label: 'Cabin', icon: 'chevron' },
}

const ALL_TABS: readonly (NavTab & { enabled: boolean; group?: NavGroupId })[] = [
  { to: '/command', label: 'Command', icon: 'compass', enabled: true },
  { to: '/fleets', label: 'Fleets', icon: 'ship', enabled: true },
  { to: '/port', label: 'Port', icon: 'anchor', enabled: true },
  { to: '/market', label: 'Market', icon: 'scales', enabled: true },
  { to: '/map', label: 'Map', icon: 'chart', enabled: true },
  { to: '/ledger', label: 'Ledger', icon: 'ledger', enabled: true, group: 'cabin' },
  { to: '/rank', label: 'Rank', icon: 'wreath', enabled: true, group: 'cabin' },
  // "Codex", not "Compendium": both mean the 도감, and the shorter word is the one that must fit a
  // cell. The screen's own title spells it out in full.
  { to: '/compendium', label: 'Codex', icon: 'codex', enabled: true, group: 'cabin' },
  { to: '/profile', label: 'Profile', icon: 'profile', enabled: true, group: 'cabin' },
]

const ENABLED = ALL_TABS.filter((t) => t.enabled)

/** Every destination the bar can reach, FLAT and in order, grouped or not. `enabled: false` drops
 *  one entirely — DARK-FIRST: a tab may never lead to a screen that has nothing behind it yet.
 *
 *  NOT A SECOND TABLE, and not the thing the bar draws: since the grouping (2026-08-25) NavBar
 *  renders `NAV_CELLS`, and both this and that are computed from `ALL_TABS` above. This list has no
 *  caller in `src/` today — it is kept as the enumeration `docs/CORE_REUSE.md` names and as the
 *  natural reading for anyone checking App.tsx's route table against the destinations. If a caller
 *  ever wants "the tabs", it wants this; if it wants "what the bar draws", it wants NAV_CELLS. */
export const NAV_TABS: readonly NavTab[] = ENABLED.map(({ to, label, icon }) => ({ to, label, icon }))

/** What the BAR draws: either a destination, or a group that reveals several. */
export type NavCell =
  | { kind: 'tab'; label: string; icon: IconName; to: string }
  | { kind: 'group'; id: NavGroupId; label: string; icon: IconName; members: readonly NavTab[] }

/** THE BAR'S CELLS, DERIVED — never declared. A group's membership is a field on the tab, so there
 *  is exactly one table and a tab cannot be listed in the bar and in a group, listed twice, or
 *  listed nowhere. A second array naming the members is precisely the drift `docs/NO_SPAGHETTI.md`
 *  forbids, and it is unbuildable here: this list is computed from `ALL_TABS` and nothing else.
 *  Order follows the table, and a group takes the position of its FIRST member. */
export const NAV_CELLS: readonly NavCell[] = (() => {
  const cells: NavCell[] = []
  const members = new Map<NavGroupId, NavTab[]>()
  for (const t of ENABLED) {
    const tab: NavTab = { to: t.to, label: t.label, icon: t.icon }
    if (!t.group) {
      cells.push({ kind: 'tab', ...tab })
      continue
    }
    let list = members.get(t.group)
    if (!list) {
      list = []
      members.set(t.group, list)
      cells.push({ kind: 'group', id: t.group, ...GROUPS[t.group], members: list })
    }
    list.push(tab)
  }
  return cells
})()

/** The landing destination. Orders are the point of the game, so the app opens on Command. */
export const HOME_TAB = '/command'

/** The URL a destination actually has in the browser. The router is mounted on
 *  `import.meta.env.BASE_URL` (App.tsx passes it as the basename, and vite.config.ts sets it to
 *  `/byeharu-voyage/` so the build serves as a GitHub Pages project site), so a bare `/command`
 *  in an `href` is a 404 waiting for the first middle-click. Spelt ONCE, here, beside the table
 *  that owns the paths — a second copy is a second answer to "where does this tab live". */
export function tabHref(to: string): string {
  return `${import.meta.env.BASE_URL.replace(/\/$/, '')}${to}`
}

/** THE SCREENS THAT READ PRICES — where the status strip carries the market countdown.
 *
 *  §6: the top bar is "a 32px status strip: purse `Figure` on the right, the market countdown on
 *  the left when on a trade screen, nothing else". A countdown to the next price move is a fact
 *  about a decision you are in the middle of; on the chart, on the standings or in the cabin it is
 *  a number with nothing to do, which is precisely what §2 counted 93 lines of.
 *
 *  These three are the screens that hold a market payload (each calls `loadMarket`): Command
 *  composes the trade, Port shows the quay's own prices, Market reads them elsewhere. Derived
 *  from nothing — it is a JUDGEMENT about which screens are about prices, so it is written down
 *  once rather than re-decided in the bar. */
export const TRADE_ROUTES: readonly string[] = ['/command', '/port', '/market']

/** Is this pathname one of the price screens? Takes the router's `pathname`, basename already
 *  stripped, which is what `useLocation()` serves. */
export function isTradeRoute(pathname: string): boolean {
  return TRADE_ROUTES.includes(pathname)
}
