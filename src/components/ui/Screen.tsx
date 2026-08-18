import type { ReactNode } from 'react'
import { screenBodyClass } from './screenLayout'

// Design-system Screen: the ONE page scaffold every tab mounts (owns its scroll inside the shell,
// centers the content column, and sets the space-y-4 panel rhythm PageHeader and the cards rely
// on). Screens NEVER hand-copy this frame. `wide` switches to the desktop two-column width; the
// class logic lives in ./screenLayout.ts (pure, testable).

export function Screen({
  children,
  wide = false,
  className = '',
}: {
  children: ReactNode
  wide?: boolean
  className?: string
}) {
  return (
    <div className={`h-full overflow-y-auto ${className}`}>
      <div className={screenBodyClass(wide)}>{children}</div>
    </div>
  )
}
