import type { ReactNode } from 'react'
import { railSlotClass, shellColumnClass, shellFrameClass } from '../components/ui'
import { NavBar } from './NavBar'
import { TopBar } from './TopBar'

// THE SHELL'S FRAME — the one spelling of "status strip, page, nav" (2026-11-11, the remaster's S9).
//
// Two routes draw the game's chrome: AppShell (every tab) and the HQ (`/city`, which stands outside AppShell because it keeps its
// own clock and world beat — CityScreen.tsx says why). Each used to lay the chrome out itself, and the HQ had drawn no status strip
// at all: the one screen without the purse and the clock on top. Both now draw THIS frame, so the strip, the page and the nav
// stand the same way on every screen, and the bar-or-rail decision is screenLayout.ts's (THE SHELL), made once.
//
//   phone   the strip over the page, the 56-px bar at the foot — unchanged
//   lg      the rail down the window's left edge, the strip over the page beside it
//
// `nav` is false where there is nothing to navigate to yet (AppShell's register door). `navTestId` names the nav's slot on a screen
// whose specs read its rail by its own name (the HQ's `city-rail`).

export function ShellFrame({
  nav = true,
  navTestId,
  children,
  overlay,
  ...rest
}: {
  nav?: boolean
  navTestId?: string
  /** The page: what stands under the strip, beside the rail. */
  children: ReactNode
  /** A fixed layer over the frame (the arrival card) — outside the column, never in its flow. */
  overlay?: ReactNode
  'data-world'?: string
  'data-testid'?: string
}) {
  return (
    <div className={`bv-sea text-ink ${shellFrameClass()}`} {...rest}>
      <div className={shellColumnClass()}>
        {/* The persistent game chrome: a 32-px STATUS STRIP — the purse, the clocks, and the market countdown on a trade screen
            (TopBar.tsx carries what it dropped and why). */}
        <TopBar />
        {children}
      </div>
      {nav && (
        <div className={railSlotClass()} data-testid={navTestId}>
          <NavBar />
        </div>
      )}
      {overlay}
    </div>
  )
}
