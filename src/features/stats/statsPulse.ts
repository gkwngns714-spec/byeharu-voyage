import { useCallback, useEffect, useState } from 'react'
import { useReaskAtEdge } from '../../components/ui'
import { useShellState } from '../../app/shellState'
import { serverNow } from '../../lib/serverClock'
import { STATS_REFRESH_MS } from './statsFaces'

// THE TAB'S PULSE — how old the figures are RIGHT NOW, when the next count is due, and the one
// trigger that re-asks the open face.
//
// THE OWNER, 2026-10-20 (request 187): *"I want stats to be in real time — by seconds updated."*
// The rollup behind this tab is written every fifteen minutes and that cadence is what keeps it
// cheap on a live database (docs/OWNER_REQUESTS.md row 187: per-second snapshots would multiply a
// ~50 MB table by nine hundred). So the answer is split, and this file is the client half of it:
//   · the LIVE figures move every few seconds on the world's own beat, with no new read at all —
//     LiveNow.tsx, out of the store the shell already polls;
//   · the ROLLUP figures arrive within a second or two of the server writing them, because the
//     countdown below knows when the next count is due and re-asks AT THAT EDGE;
//   · and the age on screen ticks every second, so a player can see the tab is alive.
// No new migration, no new write, no second poller.
//
// MEASURED AS A GAP, NEVER AS A DATE. The server says how old its newest row is (`age_seconds`);
// `servedNow` stamps the instant that answer reached this device, and the age on screen is the one
// plus the time ELAPSED since the other. Both instants come from the one clock (lib/serverClock, the
// same reading AppShell's `nowMs` is made of), and a device whose clock is wrong by an hour still
// measures an elapsed minute as a minute — which is the whole reason the server was asked for an
// AGE rather than for a timestamp (Rank's idiom).
//
// THE EDGE CANNOT LOOP. An edge is armed only when the next count was still in the FUTURE at the
// moment the answer landed, and `useReaskAtEdge` fires once per edge (its own termination rule). A
// server that is late writing its row therefore arms nothing: the age is already past the slot, and
// the backstop — one re-ask a minute, as 0214 shipped it — is what catches up.

/** What a face reports about the answer it has just drawn: the server's own age for it, how long a
 *  count covers, and when it reached this device. A face with no rollup behind it (Me) reports null. */
export interface StatsServed {
  ageSeconds: number | null
  slotSeconds: number | null
  /** The instant this answer landed here, on the one clock. */
  atMs: number
}

/** The served shape every rollup read carries, stamped with its arrival — the one spelling of it,
 *  so five faces do not keep five. Called in the face's own effect, where the answer lands. */
export function servedNow(view: { age_seconds: number | null; slot_seconds: number } | null): StatsServed | null {
  if (view === null) return null
  return { ageSeconds: view.age_seconds, slotSeconds: view.slot_seconds, atMs: serverNow() }
}

export interface StatsPulse {
  /** Handed to every face's `useServedRead` as its `trigger`: it moves on the backstop and at the
   *  edge of the next count, and never on the world's 3-s beat. */
  beat: number
  /** How old the figures on screen are, in ms, ticking each second. Null before the first answer. */
  ageMs: number | null
  /** Until the next count, in ms, ticking each second. Null when it cannot be known, and never
   *  negative — a count that is overdue reads as due. */
  dueMs: number | null
}

/** A moment of grace after the slot turns, because the job runs a little after the slot it writes
 *  (prod's cron: `6,21,36,51`). Re-asking the instant the slot ends would ask for a row the server
 *  has not written yet and then wait a whole minute for the backstop. */
const GRACE_MS = 20_000

export function useStatsPulse(served: StatsServed | null): StatsPulse {
  const { nowMs } = useShellState()
  const [beat, setBeat] = useState(0)
  const reask = useCallback(() => setBeat((b) => b + 1), [])

  // THE BACKSTOP. One re-ask a minute while a face is open: enough to keep "Updated N min ago"
  // honest within the minute it prints, cheap enough for the heaviest of the six reads.
  useEffect(() => {
    const id = window.setInterval(reask, STATS_REFRESH_MS)
    return () => window.clearInterval(id)
  }, [reask])

  const age = served === null || served.ageSeconds === null ? null : served.ageSeconds * 1000
  const slot = served === null || served.slotSeconds === null ? null : served.slotSeconds * 1000
  const ageMs = age === null || served === null ? null : age + Math.max(0, nowMs - served.atMs)
  const dueMs = ageMs === null || slot === null ? null : Math.max(0, slot - ageMs)
  // Armed only while the next count was ahead of us when the answer landed (see the header).
  const dueAtLanding = age === null || slot === null ? null : slot - age
  const edgeMs =
    served === null || dueAtLanding === null || dueAtLanding <= 0 ? null : served.atMs + dueAtLanding + GRACE_MS
  useReaskAtEdge(edgeMs, served === null ? null : served.atMs, nowMs, reask)

  return { beat, ageMs, dueMs }
}
