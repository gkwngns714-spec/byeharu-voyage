import { num, str } from '../lib/json'
import type { LedgerEvent } from '../lib/rpc'

// A LEVEL CROSSED, AS THE LEDGER SAYS IT (0356: `public.level_marks_settle` writes one LEVEL_UP event a level crossed, with the
// Reputation it gave). One reading for the two cards that say it: the arrival card's level lines and the level-up card (slice 10).

export interface LevelLine {
  /** The level's code (`public.level_skills`): since 0411 every level raised by doing fires the same LEVEL_UP. */
  track: string
  level: number
  /** 0468: the lowest level crossed on this card, so "Opens:" names what every level crossed opened, not only the highest. */
  low: number
  reputation: number
}

/** The LEVEL_UP events among these, one line a track: the highest level, and the Reputation of all its crossings added. */
export function levelLines(events: LedgerEvent[], into: LevelLine[] = []): LevelLine[] {
  const lines = [...into]
  for (const e of events) {
    if (e.kind !== 'LEVEL_UP') continue
    const track = str(e.payload, 'track')
    const level = num(e.payload, 'level')
    if (track === null || track === '' || level === null) continue
    const reputation = num(e.payload, 'reputation') ?? 0
    const at = lines.findIndex((l) => l.track === track)
    if (at < 0) lines.push({ track, level, low: level, reputation })
    else lines[at] = { track, level: Math.max(lines[at].level, level), low: Math.min(lines[at].low, level), reputation: lines[at].reputation + reputation }
  }
  return lines
}
