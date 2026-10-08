import { formatPctPoints } from '../../lib/format'
import { Figure } from './Figure'
import { Icon } from './Icon'
import { Tile } from './Tile'

// ONE OFFICER, AS A TILE — moved here from features/compendium/CaptainsFace.tsx (2026-10-08) so the
// Codex and a merchant's sheet print one shape (docs/NPC_TRADERS.md §8.3). PURE PROPS; the caller
// resolves the home port's NAME. `signed` is a fact about the world (the Codex), never an offer;
// `takesEffect` false greys the bonus for an officer no rule reads yet.
export function OfficerTile({
  name,
  specialty,
  bonusPct,
  homePort = null,
  signed = false,
  takesEffect = true,
  onClick,
  testId = 'officer-tile',
}: {
  name: string
  specialty: string
  bonusPct: number
  /** The port NAME she calls home, when known (0015:63). */
  homePort?: string | null
  signed?: boolean
  takesEffect?: boolean
  onClick?: () => void
  testId?: string
}) {
  const role = specialty.toLowerCase()
  const meta = [role, signed ? 'signed' : null, homePort].filter(Boolean).join(' · ')
  return (
    <Tile
      mark={<Icon name="crew" size={20} />}
      name={name}
      meta={meta}
      figure={<Figure value={`+${formatPctPoints(bonusPct)}`} tone={takesEffect ? 'success' : 'faint'} />}
      state={takesEffect ? 'rest' : 'muted'}
      tap={onClick ? 'whole' : 'none'}
      onClick={onClick}
      data-testid={testId}
    />
  )
}
