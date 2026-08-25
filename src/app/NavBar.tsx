import { useEffect, useState, type ReactNode } from 'react'
import { NavLink, useLocation } from 'react-router-dom'
import { Icon } from '../components/ui'
import { NAV_CELLS, navGridClass, type NavTab } from './navTabs'

// THE ONE navigation. Extracted from AppShell so it can be RENDERED AND MEASURED on its own at a
// phone viewport without booting the shell — a number in a comment is not a measurement, and
// `tests/nav.geometry.spec.ts` is where the bar's geometry is now proved rather than asserted.
//
// Text-first: the LABEL is the tab. The glyph is a small quiet mark above it, never the only
// signal — a word cannot be misread the way an icon can.
//
// ── SIX CELLS, NINE DESTINATIONS ────────────────────────────────────────────────────────────────
// The bar draws `NAV_CELLS`, not `NAV_TABS`. Four of the nine destinations are folded into ONE cell
// (see navTabs.ts for which four and why that grouping is the information architecture rather than
// an arithmetic split), because nine cells in one row at 390px is 43px each — under the reach floor
// — and the alternative the owner ruled out was a second row. Both lists come from the SAME table:
// `NAV_CELLS` is derived from it, so a tab cannot appear in the bar and in a group, or in neither.
//
// ── A GROUP REVEALS. IT DOES NOT REPLACE THE BAR ────────────────────────────────────────────────
// The owner's rule, said four times and built backwards twice:
//
//   "Pressing a control SELECTS. It never collapses, re-flows, replaces or destroys the surface it
//    was pressed on, and nothing docks and follows the scroll."
//
// A grouped tab rail is the easiest place in this app to break it — the obvious build swaps the
// bar's six cells for the group's four, destroying the surface the finger just landed on. So the
// members are revealed in a panel that is **absolutely positioned above the bar** and therefore
// out of flow entirely: not one cell of the bar moves, the bar's own box does not change height,
// and the screen behind is overlaid rather than pushed. The panel is anchored to the bar, which is
// fixed chrome — it is not docked to anything that scrolls. `nav.geometry.spec.ts` compares every
// cell rectangle before and after the press and requires them identical to the pixel, so building
// the collapsing version would fail the suite rather than reach the owner a third time.

/** ONE CELL, ONE LOOK. The bar's destinations and a group's revealed members are the same control
 *  drawn the same way — a second spelling of these classes is how the two would drift apart. */
function cellClass(active: boolean): string {
  return `relative flex min-h-14 flex-col items-center justify-center gap-0.5 transition ${
    active ? 'text-accent' : 'text-ink-muted hover:text-ink'
  }`
}

/** The label is its own measurable box: the fit proof reads scrollWidth vs clientWidth on THIS
 *  element. `truncate` would HIDE a clip instead of failing the proof, so it is deliberately
 *  absent — a label that does not fit must break the build, not shorten itself in silence. */
function CellFace({ label, active, children }: { label: string; active: boolean; children: ReactNode }) {
  return (
    <>
      {children}
      <span
        data-testid={`nav-label-${label.toLowerCase()}`}
        className={`whitespace-nowrap font-mono text-[10px] uppercase tracking-wider ${
          active ? 'font-medium' : ''
        }`}
      >
        {label}
      </span>
      {active && <span aria-hidden className="absolute inset-x-3 top-0 h-px bg-accent" />}
    </>
  )
}

function TabCell({ tab, onNavigate }: { tab: NavTab; onNavigate?: () => void }) {
  return (
    <NavLink
      to={tab.to}
      data-testid={`nav-${tab.label.toLowerCase()}`}
      onClick={onNavigate}
      className={({ isActive }) => cellClass(isActive)}
    >
      {({ isActive }) => (
        <CellFace label={tab.label} active={isActive}>
          <Icon name={tab.icon} size={18} />
        </CellFace>
      )}
    </NavLink>
  )
}

export function NavBar() {
  const { pathname } = useLocation()

  // AN OPEN PANEL BELONGS TO THE ROUTE IT WAS OPENED ON. Arriving somewhere closes it: it revealed
  // a choice and the choice was made. That is stored as a fact — which group, opened from where —
  // rather than synchronised by an effect that resets state after the route has already changed.
  // (`react-hooks/set-state-in-effect` forbids the effect spelling, and it is right to: the effect
  // renders the stale panel once, then renders again to remove it.) Pressing the member you are
  // ALREADY on does not change the pathname, so those links close it explicitly too.
  const [opened, setOpened] = useState<{ path: string; group: string } | null>(null)
  const openGroup = opened && opened.path === pathname ? opened.group : null
  const setOpenGroup = (group: string | null) => setOpened(group ? { path: pathname, group } : null)

  // Escape is the keyboard's tap-outside.
  useEffect(() => {
    if (!openGroup) return
    const onKey = (e: KeyboardEvent) => {
      // `setOpened`, not the `setOpenGroup` wrapper: the wrapper closes over `pathname` and would
      // have to be a dependency of this subscription, re-binding the listener on every navigation
      // for no reason. A setState function is stable; closing is `null` either way.
      if (e.key === 'Escape') setOpened(null)
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [openGroup])

  const open = NAV_CELLS.find((c) => c.kind === 'group' && c.id === openGroup)
  const openMembers = open?.kind === 'group' ? open : null

  return (
    <nav aria-label="Primary" data-testid="app-nav" className="relative border-t border-edge bg-surface">
      {openMembers && (
        <>
          {/* Tap anywhere else to dismiss. It sits BELOW the panel and below the bar (z-10 against
              z-20), so both stay pressable — a backdrop that swallows the bar's own taps would be
              the collapse rule broken by another route. */}
          <button
            type="button"
            aria-label={`Close ${openMembers.label}`}
            onClick={() => setOpenGroup(null)}
            tabIndex={-1}
            className="absolute inset-x-0 bottom-full z-10 h-screen cursor-default"
          />
          <div
            id={`nav-group-${openMembers.id}`}
            data-testid="nav-group-panel"
            role="group"
            aria-label={openMembers.label}
            className="absolute inset-x-0 bottom-full z-20 border-t border-edge bg-surface"
          >
            <div className={`mx-auto grid max-w-4xl ${navGridClass(openMembers.members.length)}`}>
              {openMembers.members.map((m) => (
                <TabCell key={m.to} tab={m} onNavigate={() => setOpenGroup(null)} />
              ))}
            </div>
          </div>
        </>
      )}

      {/* THE BAR. Rendered identically whether a group is open or shut — this markup does not read
          `openGroup` for anything but the chevron's direction and the cell's own lit state. */}
      <div
        data-testid="nav-bar"
        className={`relative z-20 mx-auto grid max-w-4xl bg-surface ${navGridClass(NAV_CELLS.length)}`}
      >
        {NAV_CELLS.map((cell) => {
          // Leaving for a destination shuts an open panel on the way out.
          if (cell.kind === 'tab')
            return <TabCell key={cell.to} tab={cell} onNavigate={() => setOpenGroup(null)} />

          const isOpen = openGroup === cell.id
          // A group cell is lit when you are standing on one of its members. It keeps its own NAME
          // in every state: a cell whose word changes with the route is not a name, and the screen
          // you are on prints its own title anyway.
          const active = cell.members.some((m) => m.to === pathname)
          return (
            <button
              key={cell.id}
              type="button"
              data-testid={`nav-${cell.label.toLowerCase()}`}
              aria-expanded={isOpen}
              aria-controls={`nav-group-${cell.id}`}
              onClick={() => setOpenGroup(isOpen ? null : cell.id)}
              // TWO DIFFERENT THINGS, DELIBERATELY SPELT DIFFERENTLY. The cell is lit while it is
              // open OR while you stand on a member, because both mean "this is the one you are
              // dealing with". Only the ROUTE earns the hairline and the weight below — that mark
              // answers "where am I", and an open panel is not an answer to it.
              className={cellClass(active || isOpen)}
            >
              <CellFace label={cell.label} active={active}>
                {/* Points UP at what it will reveal, DOWN at the panel once it has. The only thing
                    a press changes about the bar, and it changes nothing about its geometry. */}
                <Icon
                  name={cell.icon}
                  size={18}
                  className={isOpen ? 'rotate-90' : '-rotate-90'}
                />
              </CellFace>
            </button>
          )
        })}
      </div>
    </nav>
  )
}
