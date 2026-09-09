import { useEffect, useState } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'
import { Icon, Nav, Row, Tray, type NavItem, type TrayDetent } from '../components/ui'
import { NAV_CELLS, tabHref } from './navTabs'

// THE ONE navigation. Extracted from AppShell so it can be RENDERED AND MEASURED on its own at a
// phone viewport without booting the shell — a number in a comment is not a measurement, and
// `tests/nav.geometry.spec.ts` is where the bar's geometry is proved rather than asserted.
//
// ── SIX CELLS, NINE DESTINATIONS ────────────────────────────────────────────────────────────────
// The bar draws `NAV_CELLS`, not `NAV_TABS`. Four of the nine destinations are folded into ONE cell
// (see navTabs.ts for which four and why that grouping is the information architecture rather than
// an arithmetic split), because nine cells in one row at 390px is 43px each — under the reach floor
// — and the alternative the owner ruled out was a second row. Both lists come from the SAME table:
// `NAV_CELLS` is derived from it, so a tab cannot appear in the bar and in a group, or in neither.
//
// ── WHAT STEP 3 CHANGED, AND WHAT IT DID NOT ────────────────────────────────────────────────────
// docs/UI_DIRECTION.md §6: "the Nav keeps six cells; labels drop uppercase; Cabin opens a `Tray`
// of four rows." So this file is now COMPOSITION and routing and nothing else:
//   · the cell — a 22px icon over a 12px sentence-case label, no mono, no letter-spacing, no
//     `uppercase tracking-wider` — is the `Nav` primitive's, drawn once and never re-spelt here
//   · the revealed panel — which was 25 lines of hand-placed `absolute … bottom-full` markup with
//     its own border, its own surface and its own grid class — is a `Tray` of four `Row`s
// The routing, the group table and the open/shut fact stay here, which is where they belong.
//
// ── A GROUP REVEALS. IT DOES NOT REPLACE THE BAR ────────────────────────────────────────────────
// The owner's rule, said four times and built backwards twice:
//
//   "Pressing a control SELECTS. It never collapses, re-flows, replaces or destroys the surface it
//    was pressed on, and nothing docks and follows the scroll."
//
// The tray is therefore ANCHORED ABOVE THE BAR and out of flow: not one cell moves, the bar's own
// box does not change height, the screen behind is overlaid rather than pushed — and the Cabin
// cell stays pressable, so the press that opened it also shuts it. `nav.geometry.spec.ts` compares
// every cell rectangle before and after the press and requires them identical to the pixel.
//
// That is also why the tray is `mode="inline"` inside an out-of-flow wrapper rather than
// `mode="docked"`: a docked tray is `fixed` to the bottom edge of the glass, which is exactly
// where this bar already is, so it would cover the control it was opened from. Both modes keep the
// owner's rule; only one of them leaves the rail reachable underneath.

/** Four rows want the working detent, not the peek. `peek` is 96px — one row plus a reach floor —
 *  which is the right answer to "what did I just tap?" and the wrong one to "here are the four
 *  places you keep at your desk". `half` is 422px at 390×844, which holds the four 52px rows, the
 *  handle and the title with room to spare; the ladder still lets a drag take it anywhere. */
const CABIN_DETENT: TrayDetent = 'half'

export function NavBar() {
  const { pathname } = useLocation()
  const navigate = useNavigate()

  // AN OPEN TRAY BELONGS TO THE ROUTE IT WAS OPENED ON. Arriving somewhere closes it: it revealed
  // a choice and the choice was made. That is stored as a fact — which group, opened from where —
  // rather than synchronised by an effect that resets state after the route has already changed.
  // (`react-hooks/set-state-in-effect` forbids the effect spelling, and it is right to: the effect
  // renders the stale tray once, then renders again to remove it.) Pressing the member you are
  // ALREADY on does not change the pathname, so those rows close it explicitly too.
  const [opened, setOpened] = useState<{ path: string; group: string; detent: TrayDetent } | null>(
    null,
  )
  const open = opened && opened.path === pathname ? opened : null
  const openGroup = open?.group ?? null
  const closeGroup = () => setOpened(null)

  // Escape is the keyboard's tap-outside.
  useEffect(() => {
    if (!openGroup) return
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setOpened(null)
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [openGroup])

  const cell = NAV_CELLS.find((c) => c.kind === 'group' && c.id === openGroup)
  const openMembers = cell?.kind === 'group' ? cell : null

  // THE LIT CELL ANSWERS "WHERE AM I", and an open tray is not an answer to that. A group cell is
  // lit while you are STANDING ON one of its members — it keeps its own name in every state, since
  // a cell whose word changes with the route is not a name, and the screen prints its own title.
  const here = NAV_CELLS.find((c) =>
    c.kind === 'tab' ? c.to === pathname : c.members.some((m) => m.to === pathname),
  )
  const currentId = here === undefined ? undefined : here.kind === 'tab' ? here.to : here.id

  // A TAB'S CELL ID IS ITS ROUTE, which is what lets `onNavigate` hand back an item and this file
  // route on it without translating an href back into a path.
  const items: NavItem[] = NAV_CELLS.map((c) =>
    c.kind === 'tab'
      ? { id: c.to, label: c.label, icon: c.icon, href: tabHref(c.to) }
      : { id: c.id, label: c.label, icon: c.icon },
  )

  /** One spelling of "go there, and shut the tray on the way out" — for the six cells and the four
   *  rows alike. The anchors keep their real hrefs; this is only what answers a plain left-click. */
  const go = (to: string) => {
    closeGroup()
    navigate(to)
  }

  return (
    <div data-testid="app-nav" className="relative shrink-0">
      {openMembers && (
        <>
          {/* Tap anywhere else to dismiss. It sits BELOW the tray and below the bar (z-10 against
              z-20 and the tray's own z-40), so both stay pressable — a backdrop that swallowed the
              bar's own taps would be the collapse rule broken by another route. */}
          <button
            type="button"
            aria-label={`Close ${openMembers.label}`}
            onClick={closeGroup}
            tabIndex={-1}
            className="absolute inset-x-0 bottom-full z-10 h-screen cursor-default"
          />
          <div className="absolute inset-x-0 bottom-full z-20">
            <Tray
              data-testid="nav-group-panel"
              mode="inline"
              detent={open?.detent ?? CABIN_DETENT}
              onDetentChange={(next) => {
                if (next === 'closed') closeGroup()
                else setOpened({ path: pathname, group: openMembers.id, detent: next })
              }}
              title={openMembers.label}
            >
              {openMembers.members.map((m, i) => (
                <Row
                  key={m.to}
                  href={tabHref(m.to)}
                  onClick={(e) => {
                    if (e.defaultPrevented || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return
                    e.preventDefault()
                    go(m.to)
                  }}
                  mark={<Icon name={m.icon} size={20} />}
                  label={m.label}
                  chevron
                  tone={m.to === pathname ? 'accent' : 'default'}
                  hairline={i < openMembers.members.length - 1}
                />
              ))}
            </Tray>
          </div>
        </>
      )}

      {/* THE BAR. Rendered identically whether the tray is open or shut — this markup reads
          `openGroup` for the chevron's direction and for `aria-expanded`, and for nothing else. */}
      <Nav
        data-testid="nav-bar"
        items={items}
        current={currentId}
        openGroup={openGroup ?? undefined}
        onGroup={(id) =>
          setOpened(openGroup === id ? null : { path: pathname, group: id, detent: CABIN_DETENT })
        }
        onNavigate={(item) => go(item.id)}
      />
    </div>
  )
}
