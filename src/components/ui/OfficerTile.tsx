import { Fragment, type ReactNode } from 'react'
import { formatPctPoints } from '../../lib/format'
import { Figure } from './Figure'
import { Icon } from './Icon'
import { Tile } from './Tile'

// ONE OFFICER, AS A TILE — moved here from features/compendium/CaptainsFace.tsx (2026-10-08) so the
// Codex and a merchant's sheet print one shape (docs/NPC_TRADERS.md §8.3). PURE PROPS; the caller
// resolves the home port's NAME. `signed` is a fact about the world (the Codex), never an offer;
// `takesEffect` false greys the bonus for an officer no rule reads yet. 0156: `role` is the word to print
// for her job (the Codex passes the server's `job_word`) and `grade` her served grade, printed first.
export function OfficerTile({
  name,
  role,
  grade = null,
  bonusPct,
  homePort = null,
  signed = false,
  level = null,
  takesEffect = true,
  onClick,
  testId = 'officer-tile',
}: {
  name: string
  /** The job, as the line prints it. */
  role: string
  /** 0156 — C / B / A / S, served; null draws nothing (a server before 0156). */
  grade?: string | null
  bonusPct: number
  /** The port NAME she calls home, when known (0015:63). */
  homePort?: ReactNode
  signed?: boolean
  /** 0127 — the level of your signing of her; null draws nothing (a merchant's, or one not signed). */
  level?: number | null
  takesEffect?: boolean
  onClick?: () => void
  testId?: string
}) {
  // The home port may be a go-to link (src/chart/GoToLink.tsx), so the line is joined as nodes.
  const meta = [grade, role, signed ? 'signed' : null, level != null ? `Lv ${level}` : null, homePort]
    .filter(Boolean)
    .map((part, i) => (
      <Fragment key={i}>
        {i > 0 && ' · '}
        {part}
      </Fragment>
    ))
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
