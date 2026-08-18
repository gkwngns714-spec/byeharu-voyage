import { NavLink } from 'react-router-dom'
import { Icon } from '../components/ui'
import { NAV_TABS, navGridClass } from './navTabs'

// THE ONE navigation. Extracted from AppShell so it can be RENDERED AND MEASURED on its own at a
// 320px viewport without booting the shell (which needs auth and Supabase) — a number in a comment
// is not a measurement, and that proof is what navTabs.ts's width claim is waiting on.
//
// Text-first: the LABEL is the tab. The glyph is a small quiet mark above it, never the only
// signal — a word cannot be misread the way an icon can.

export function NavBar() {
  return (
    <nav aria-label="Primary" data-testid="app-nav" className="border-t border-edge bg-surface">
      <div className={`mx-auto grid max-w-4xl ${navGridClass(NAV_TABS.length)}`}>
        {NAV_TABS.map((t) => (
          <NavLink
            key={t.to}
            to={t.to}
            data-testid={`nav-${t.label.toLowerCase()}`}
            className={({ isActive }) =>
              `relative flex min-h-14 flex-col items-center justify-center gap-0.5 transition ${
                isActive ? 'text-accent' : 'text-ink-muted hover:text-ink'
              }`
            }
          >
            {({ isActive }) => (
              <>
                <Icon name={t.icon} size={18} />
                {/* The label is its own measurable box: a fit proof reads scrollWidth vs
                    clientWidth on THIS element. `truncate` would HIDE a clip instead of failing
                    the proof, so it is deliberately absent. */}
                <span
                  data-testid={`nav-label-${t.label.toLowerCase()}`}
                  className={`whitespace-nowrap font-mono text-[10px] uppercase tracking-wider ${
                    isActive ? 'font-medium' : ''
                  }`}
                >
                  {t.label}
                </span>
                {isActive && <span aria-hidden className="absolute inset-x-3 top-0 h-px bg-accent" />}
              </>
            )}
          </NavLink>
        ))}
      </div>
    </nav>
  )
}
