import type { IconName } from '../components/ui'
import { translateMaybe, type Locale } from '../lib/i18n'

// THE TAB TABLE — pure data + policy (no React), so the navigation contract can be pinned by a
// spec instead of read out of JSX. NavBar renders EXACTLY this list; there is no second table.
//
// ── THE DESTINATIONS, and why each is its own screen — eight, and NINE since 2026-10-20 ────
//   Command  NOT A TAB (owner, 2026-10-31): the desk — her queue, the halt, cancel and clear — is
//            reached from the CITY's Market building (its face composes the trade face), never
//            from this bar. Since 2026-09-09 it composes NO verb — the owner: *"they should be
//            located accordingly at different locations"* — every verb's doorway is on the face
//            of the building whose act it is (PORT) or on the chart (SAIL). FLEETS' "Command her"
//            still points it at a hull through `domain/order`'s draft; nothing hands it a verb.
//   Fleets   what you own and where it is: ships, crew, hold, condition.
//   Port     the harbour you are in — its prices, and prices read elsewhere through its port
//            field — its services, its dues, its news. MARKET folded into it on 2026-09-11 (owner
//            row 76, docs/QUAY_LEDGER.md): the two tabs drew one ledger, one tray and one harbour
//            choice, and reading a distant market from a second tab moved PORT off her quay.
//   Map      WHERE THINGS ARE — and, since 2026-08-23, where you can act on that: tapping a harbour
//            offers `Sail here`, which is a HAND-OFF to Command, never a second composer. This line
//            read "Read-only, always"; MapScreen's header carries why that was the wrong rule.
//   Ledger   the running record: voyages, trades, profit and loss.
//   Rank     standings among captains.
//   Codex    the compendium (도감): every good, hull, officer and flag the world serves, whether
//            or not you have met it. A reference — it commands nothing.
//   You      who you have become and who sails for you: the three levels, every hull you own,
//            your captains (owner row 181, 2026-10-20). It is the figures ABOUT you; Profile is
//            the account you are signed in as, and Fleets is where a fleet is right now.
//   Profile  account, session, preferences.
//
// ── NINE DESTINATIONS, SIX CELLS (2026-08-25); EIGHT AND FIVE SINCE 2026-09-11 ─────────────────
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
//   you own (Fleets), in the harbour you are docked at (Port — its prices, and any other quay's,
//   since MARKET folded in), across the sea (Map). Every one of these is touched many times a
//   session, and `docs/UI_DIRECTION.md` §3a is explicit that depth added to a frequent act is a
//   DEFECT — the reference game's own convenience team exists to undo exactly that. So all four
//   stay ONE TAP. None is grouped.
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
// the same place — and Market was played too often to sit behind a tap anyway (it has since been
// folded into Port for a different reason: they were one screen drawn twice).
//
// MEASURED 2026-08-25, chromium against the built app (tests/nav.geometry.spec.ts prints the line
// and asserts every number in it):
//   390×844  six cells of 65×56 in a bar **56px tall**, one row. Every label's scrollWidth equals
//            its clientWidth. Page scrollWidth 390 = clientWidth. The 9-tab bar it replaces
//            measured 3 rows, cells 130×56, bar 168px — so the game gained 112px of screen.
//   320×568  six cells of 53×56 in one row, widest label 46px, none shaved — clear of both the
//            44px reach floor and the 46px COMMAND needs. This is why SIX and not seven: 320 ÷ 7 is
//            45.7px, and COMMAND would be shaved by the arithmetic alone.
// SINCE 2026-09-11 the bar draws FIVE cells (Market gone); nav.geometry.spec pins the count and
// re-measures the row on every run. 2026-10-31: still FIVE — HQ leads the bar and the COMMAND tab
// is GONE (owner: *"it is a game you dick. and i told you to remove the command tab"*): the City is
// the game's home and its Market building is the desk's door. The label is "HQ", the City rail's
// own word; the bar was HQ · Fleets · Map · Stats · Menu; since 2026-11-11 it is HQ · Trade · Fleets · Map · Menu, and since
// 2026-11-16 HQ · Trade · Fleets · Map · Office · Menu (SIX cells again). Since 2026-11-23 (the visual overhaul's slice 2) the
// Office is off the bar, its faces HQ's doors: HQ · Trade · Fleets · Map · Land · Menu (five cells while Land is dark).
//
// ── THE RAIL HAS ROOM THE BAR HAS NOT (owner, 2026-11-14: *"make you, stats on the left side like hq, trade etc."*) ──
// From `lg` the nav is a column down the window's left edge, and a column is not short of cells the way a 320-px row
// is. So You and Stats stand on the RAIL as their own cells — HQ · Trade · Fleets · Map · Office · You · Stats · Menu — and
// are NOT in the Menu there (one place per destination on a given screen). The phone's bar is unchanged: six cells,
// You and Stats inside the Menu (eight cells at 320 px is 40 px each, under what the labels need). It is one field on
// the tab (`rail`), read by `navCells(wide)`; there is still exactly one table.

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
  /** Not a subject glyph: no single place-glyph is true of every member. It was the chevron ("this opens") until 2026-11-23;
   *  it is the four-tile `menu` glyph since (docs/design/visual-overhaul-2026-11-23.md, slice 1), the mark every game's menu
   *  button wears, and the open tray says the rest. Every other icon in this table names ONE place, and no two share a glyph. */
  icon: IconName
}

/** A SWITCH THE SERVER SERVES (`world.snapshot().config`). A tab that names one is on the bar only while the world serves it true:
 *  DARK-FIRST by the world's own switch, not by a constant here (0455, the Land: `land_enabled`, the owner's to light). The rest of
 *  this table is unchanged by it, so a dark world draws exactly the cells it drew before. */
export type ServedSwitch = 'land_enabled'

/** The switches a world serves true, as the bar reads them. None: every switched tab is off the bar. */
export type LitSwitches = ReadonlySet<ServedSwitch>
const NONE_LIT: LitSwitches = new Set()

const GROUPS: Record<NavGroupId, NavGroup> = {
  cabin: { label: 'Menu', icon: 'menu' },
}

const ALL_TABS: readonly (NavTab & {
  enabled: boolean
  group?: NavGroupId
  /** ITS OWN CELL ON THE WIDE RAIL, in this order among the rail's promoted cells (after the ungrouped tabs, before
   *  the group). On the phone's bar it stays a member of its `group`. Only a grouped tab may carry it. */
  rail?: number
  /** On the bar only while the server serves this switch true (ServedSwitch). */
  served?: ServedSwitch
  /** A tab switched off (`enabled: false`) whose route still stands: the cell lit while you stand on it (`litRoute`). */
  under?: string
})[] = [
  // HQ (owner, 2026-10-31: *"i press hq, then command, then hq disappears"*). The City page is the
  // game's home and sits OUTSIDE the shell, so without a cell here the desk's screens had no way
  // back to it — a navigation dead end. One press from every screen, as its OWN cell at the head of
  // the bar. The word is the City rail's own — `city.hq`, "HQ" / "본부" — and the order matches that
  // rail: HQ · Map · Stats · Menu (Fleets sits between HQ and Map here; the City rail does not
  // carry it). Five cells: 390 ÷ 5 = 78 px, clear of the 44 px floor and the 46 px the widest
  // label needs, and nav.geometry.spec re-measures the row on every run.
  { to: '/city', label: 'HQ', icon: 'fort', enabled: true },
  // TRADE (owner remaster, 2026-11-11, S1: a new captain landed on HQ with nothing to press and the desk
  // — where you buy, pick a city and sail & sell — was six presses away). The desk IS the first screen
  // now: its own cell, one press from everywhere, and HOME_TAB. The route is still `/command` (old links,
  // FLEETS' "Command her"); the word is "Trade", the desk's own first face. Bar: HQ · Trade · Fleets · Map · Menu.
  { to: '/command', label: 'Trade', icon: 'scales', enabled: true },
  { to: '/fleets', label: 'Fleets', icon: 'ship', enabled: true },
  { to: '/map', label: 'Map', icon: 'chart', enabled: true },
  // LAND (owner, 2026-11-16: *"sending expeditions to land site (mountains), for minerals like rs3"*; docs/design/land-2026-11.md 6.7).
  // The party ashore and its skills: its OWN cell, like Map, after the sea's loop. SHIPPED DARK (0455): on the bar only while the
  // world serves `land_enabled` true, so until the owner lights it the bar is the six cells nav.geometry.spec measures. Lit, the
  // phone's bar is seven cells: 320 / 7 = 45.7 px, over the 44-px reach floor (tests/land.party.spec.ts measures it).
  { to: '/land', label: 'Land', icon: 'mountain', enabled: true, served: 'land_enabled' },
  // OFFICE (owner, 2026-11-16: *"in trade, there are city invest report and levels, which aren't that related to trade. they
  // should have separate tab like map you stats etc."*). The desk's City, Invest and Report faces, MOVED to their own tab
  // (features/command/OfficeScreen.tsx); Levels went to You, where the company's levels already stood. Its OWN cell on the bar and on the rail,
  // like Map, never a Menu member: six cells, which nav.geometry.spec measures at 320 and 390 (this file's 2026-08-25 note:
  // six cells of 53 px at 320, clear of the reach floor). The word is "Office" / "사무소": the company's office ashore; "City"
  // was the HQ page's own word and one of the faces.
  // SWITCHED OFF 2026-11-23 (the visual overhaul's slice 2, roadmap X2: docs/design/visual-overhaul-2026-11-23.md). The bar is for
  // the loop you play; the Office's three faces are the company ashore, so they stand on HQ as three doors (CityScreen's Office
  // row) and the route stays, its face picked by `?face=`. The HQ cell is lit on it (`under`). Reversible: `enabled: true`.
  { to: '/office', label: 'Office', icon: 'office', enabled: false, under: '/city' },
  // STATS (owner, 2026-10-20) moved INTO the Menu on 2026-11-11 (S1): the top bar is for the loop you play
  // (Trade · Fleets · Map); the world's figures are consulted, so they sit with the cabin. Every Stats
  // face stays reachable from here.
  { to: '/stats', label: 'Stats', icon: 'stats', enabled: true, group: 'cabin', rail: 2 },
  { to: '/ledger', label: 'History', icon: 'ledger', enabled: true, group: 'cabin' },
  { to: '/rank', label: 'Rank', icon: 'trophy', enabled: true, group: 'cabin' },
  // ROUTES (owner row 115, 2026-10-11): every lane the world sails, ranked. In the CABIN for this
  // group's own stated kind — it acts on nothing; a route is COMPOSED on Command, where its verb
  // lives, and this is where you find out what the world's lanes are worth. The word is "Routes"
  // and not a second word for the same idea: Command's fold is where you make one, this is where
  // you read them, as Port and Market turned out to be one place drawn twice. The bar draws FOUR
  // cells since PORT went under Command (2026-10-18, COMMAND_DESK D8) — a group member costs no cell.
  { to: '/routes', label: 'Routes', icon: 'route', enabled: true, group: 'cabin' },
  // "Codex", not "Compendium": both mean the 도감, and the shorter word is the one that must fit a
  // cell. The screen's own title spells it out in full.
  { to: '/compendium', label: 'Codex', icon: 'codex', enabled: true, group: 'cabin' },
  // YOU (owner row 181, 2026-10-20: *"Create a tab for personal info, such as my level, my ships,
  // captains, achievements, levels etc."*). What you have become and who sails for you: the three
  // levels, every hull you own, your captains. IN THE CABIN for this group's own stated kind — it
  // consults and commands nothing — and a group member costs the bar no cell, so the five measured
  // cells of nav.geometry.spec.ts stand. The word is "You", which is how every heading in this game
  // already addresses the player ("Your fleets", "Your week"); PROFILE stays the account beside it
  // (the papers that say who you are signed in as), and nothing is printed on both.
  { to: '/you', label: 'You', icon: 'person', enabled: true, group: 'cabin', rail: 1 },
  // LEVELS (roadmap 2026-11-23, slice 10: "One Skills page"): every level on its own page, its door the levels card on You. Not a
  // Menu row (the Menu holds its rows whole at 320 x 640, nav.geometry.spec): the route stands and the You cell is lit on it.
  { to: '/levels', label: 'Levels', icon: 'levelUp', enabled: false, group: 'cabin', under: '/you' },
  // ACCOUNT (was "Profile"), OFF THE MENU since 2026-11-23 (slice 2, roadmap X4): the language and the sign-in are an "Account" row
  // at the foot of You, which opens this route; `/profile` stays, and the You cell is lit on it. Reversible: `enabled: true`.
  { to: '/profile', label: 'Account', icon: 'cog', enabled: false, group: 'cabin', under: '/you' },
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
 *  Order follows the table, and a group takes the position of its FIRST member.
 *
 *  `wide` is the rail (from `lg`): a tab marked `rail` leaves its group and stands as its own cell, in `rail` order,
 *  just before the first group — so the group (the Menu) keeps the rail's foot. */
function buildCells(wide: boolean, lit: LitSwitches): readonly NavCell[] {
  const cells: NavCell[] = []
  const members = new Map<NavGroupId, NavTab[]>()
  const shown = ENABLED.filter((t) => t.served === undefined || lit.has(t.served))
  const promoted = wide ? shown.filter((t) => t.rail !== undefined).sort((a, b) => (a.rail ?? 0) - (b.rail ?? 0)) : []
  for (const t of shown) {
    if (promoted.includes(t)) continue
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
  const firstGroup = cells.findIndex((c) => c.kind === 'group')
  const own: NavCell[] = promoted.map((t) => ({ kind: 'tab', to: t.to, label: t.label, icon: t.icon }))
  cells.splice(firstGroup === -1 ? cells.length : firstGroup, 0, ...own)
  return cells
}

/** The PHONE BAR's cells: HQ · Trade · Fleets · Map · (Land, lit) · Menu, with You and Stats inside the Menu. */
export const NAV_CELLS: readonly NavCell[] = buildCells(false, NONE_LIT)

/** The WIDE RAIL's cells: HQ · Trade · Fleets · Map · (Land, lit) · You · Stats · Menu, the Menu without those two. */
export const NAV_RAIL_CELLS: readonly NavCell[] = buildCells(true, NONE_LIT)

/** What the nav draws on this glass: the rail's cells from `lg` (`useWide()`), the bar's below it; a switched tab (`served`) only
 *  while the world serves its switch true. With nothing lit these are NAV_CELLS / NAV_RAIL_CELLS themselves. */
export function navCells(wide: boolean, lit: LitSwitches = NONE_LIT): readonly NavCell[] {
  if (lit.size === 0) return wide ? NAV_RAIL_CELLS : NAV_CELLS
  return buildCells(wide, lit)
}

/** The landing destination: the TRADE desk (owner remaster, 2026-11-11, S1) — a player lands where the
 *  buy buttons are. The City page stays one press away on the HQ cell. */
export const HOME_TAB = '/command'

/** The URL a destination actually has in the browser. The router is mounted on
 *  `import.meta.env.BASE_URL` (App.tsx passes it as the basename, and vite.config.ts sets it to
 *  `/byeharu-voyage/` so the build serves as a GitHub Pages project site), so a bare `/command`
 *  in an `href` is a 404 waiting for the first middle-click. Spelt ONCE, here, beside the table
 *  that owns the paths — a second copy is a second answer to "where does this tab live". */
export function tabHref(to: string): string {
  return `${import.meta.env.BASE_URL.replace(/\/$/, '')}${to}`
}

/** THE BAR'S WORD for a label — the shell dictionary's `tab_<label>` entry, else the label itself.
 *  This is the ONE AUTHORITY for what a destination is called: the rail's cells and every tab
 *  screen's own Sheet title read it, so a rail word and a screen word cannot drift. They had:
 *  Rank's screen titled itself "Standings" while its cell said "Rank" (the audit, 2026-10-31). */
export function navWord(locale: Locale, label: string): string {
  return translateMaybe(locale, 'shell', `tab_${label}`) ?? label
}

/** The word of the tab whose route is `to` — what a screen inside the shell titles itself with,
 *  so its title and its lit nav cell are one word. A route outside the table falls back to its own
 *  last segment (no tab screen does that today; the command desk is not a tab and keeps its own). */
export function tabWord(locale: Locale, to: string): string {
  // A switched-off tab whose route still stands (the Office, the Account) keeps its word: its screen still titles itself.
  const tab = ALL_TABS.find((t) => t.to === to)
  return navWord(locale, tab?.label ?? to.replace(/^\//, ''))
}

/** THE ROUTE WHOSE CELL IS LIT on `pathname`: itself, or, for a switched-off tab whose route still stands, the cell it now lives
 *  under (`under`: the Office under HQ, the Account under You). */
export function litRoute(pathname: string): string {
  return ALL_TABS.find((t) => !t.enabled && t.to === pathname)?.under ?? pathname
}

/** THE SCREENS THAT READ PRICES — where the status strip carries the market countdown.
 *
 *  §6: the top bar is "a 32px status strip: purse `Figure` on the right, the market countdown on
 *  the left when on a trade screen, nothing else". A countdown to the next price move is a fact
 *  about a decision you are in the middle of; on the chart, on the standings or in the cabin it is
 *  a number with nothing to do, which is precisely what §2 counted 93 lines of.
 *
 *  The one screen that holds a market payload is Command — the desk (docs/COMMAND_DESK.md): its
 *  Markets, its City's quay, its plans. PORT was the second until 2026-10-18 (D8), when its every
 *  face moved under Command's City. The OFFICE is the second since 2026-11-16: the City face, with its
 *  quay's market, moved there from the desk, and its countdown went with it. Derived from nothing — it is a
 *  JUDGEMENT about which screens are about prices, so it is written down once rather than re-decided in the bar. */
export const TRADE_ROUTES: readonly string[] = ['/command', '/office']

/** Is this pathname one of the price screens? Takes the router's `pathname`, basename already
 *  stripped, which is what `useLocation()` serves. */
export function isTradeRoute(pathname: string): boolean {
  return TRADE_ROUTES.includes(pathname)
}
