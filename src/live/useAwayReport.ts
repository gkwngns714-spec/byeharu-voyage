import { create } from 'zustand'
import {
  cmdClearFleetJob,
  cmdFleetJobsSeen,
  cmdSetFleetJob,
  worldAwayReport,
  type FleetJobsReport,
  type FleetJobKind,
  type FleetJobParams,
  type Refusal,
  type RpcResult,
} from '../lib/rpc'
import { useServedRead, type ServedRead } from './useServedRead'
import { useWorld } from './worldStore'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// STANDING FLEET JOBS (0481, docs/design/hq-command-2026-11-23.md v2) — world.away_report(): each of her fleets' standing jobs and what it
// did since she last read it. ONE READ, asked when HQ opens, when one of her fleets acts (a new version is a new question) and when she
// changes a job here; never on the beat. Dark it answers {on: false} after one knob read, kept a minute.
// The three doors (set, clear, seen) go through this file, so a press re-asks the read and its refusal stands where it was pressed.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/** How long a dark answer is kept: the switch is the owner's, thrown rarely. */
const DARK_MS = 60_000
/** How long a lit answer is kept when nothing of hers moved: a run of the job is a fleet's new version, which asks again anyway. */
const LIT_MS = 120_000

interface JobEdits {
  /** Moves on every committed press, so the read is asked again. */
  edits: number
  /** The press on the wire, by fleet (or 'seen'). */
  pending: string | null
  /** The server's refusal, by fleet (or 'seen'). */
  refused: Record<string, Refusal>
  done: (key: string, refusal: Refusal | null) => void
  start: (key: string) => void
}

export const useJobEdits = create<JobEdits>()((set) => ({
  edits: 0,
  pending: null,
  refused: {},
  start: (key) => set({ pending: key }),
  done: (key, refusal) =>
    set((s) => {
      const refused = { ...s.refused }
      if (refusal) refused[key] = refusal
      else delete refused[key]
      return { pending: null, refused, edits: refusal ? s.edits : s.edits + 1 }
    }),
}))

async function press<T>(key: string, r: () => Promise<RpcResult<T>>): Promise<boolean> {
  const s = useJobEdits.getState()
  if (s.pending !== null) return false
  s.start(key)
  const done = await r()
  useJobEdits.getState().done(key, done.ok ? null : done.refusal)
  if (done.ok) await useWorld.getState().refresh()
  return done.ok
}

/** Give her fleet a standing job. `key`: where its refusal stands (default her fleet's row; a card's Repeat names its own). */
export function setFleetJob(fleetId: string, kind: FleetJobKind, params: FleetJobParams = {}, key: string = fleetId): Promise<boolean> {
  return press(key, () => cmdSetFleetJob(fleetId, kind, params))
}

/** Take her fleet's standing job away. */
export function clearFleetJob(fleetId: string, key: string = fleetId): Promise<boolean> {
  return press(key, () => cmdClearFleetJob(fleetId))
}

/** She has read the away report. */
export function seenAwayReport(): Promise<boolean> {
  return press('seen', () => cmdFleetJobsSeen())
}

/** The away report, lit for her company; else null (dark, signed out, a merchant, unread). */
export function litAway(v: FleetJobsReport | null): Extract<FleetJobsReport, { company: true }> | null {
  return v && v.on && v.company ? v : null
}

export function useAwayReport(): ServedRead<FleetJobsReport> {
  const company = useWorld((s) => s.player?.id ?? null)
  const fleets = useWorld((s) => s.fleets)
  const edits = useJobEdits((s) => s.edits)
  const question = company === null ? null : `${company}:${edits}:${fleets.map((f) => `${f.id}.${f.version}`).join(',')}`
  return useServedRead<FleetJobsReport>(company, () => worldAwayReport(), {
    question,
    trigger: 0,
    name: 'away_report',
    freshMs: (v: FleetJobsReport) => (v.on && v.company ? LIT_MS : DARK_MS),
  })
}
