import { useMemo, useState } from 'react'
import { whereabouts } from '../../domain/fleet'
import { worldRouteLegs, type FleetView, type RouteLeg, type RouteLegAsk } from '../../lib/rpc'
import { useSailLegs } from '../../live/useSailLegs'
import { useServedRead } from '../../live/useServedRead'
import { useWorld } from '../../live/worldStore'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE ROUTE BUILDER — every decision the Map's route mode makes, and no markup (RouteBar.tsx draws it).
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// THE OWNER, 2026-10-26 (row 209): *"in the map, let me click set route, and let me press city, undo, then confirm each
// visiting city, then press final - something like that."* docs/ROUTE_BUILDER.md B2.
//
//   tap a city  → it is the NEXT stop, not yet kept (another tap replaces it)
//   Confirm     → the next stop is kept (only while the server calls its leg open)
//   Undo        → the next stop goes; with none, the last kept stop goes
//   Final       → every kept stop is one SAIL line, queued through cmd.issue_lines, all or none
//
// NOT A SECOND AUTHORITY. The courses are the one course author's (`useSailLegs` → `proposeCourse`, as a plan's and a
// queued trip's); whether a leg is open is the SERVER's (`world.route_legs` → voyage.leg_refusal, 0346), printed and
// never worked out here; the lines are queued by the one plan path (`worldStore.issueLines` → cmd.issue_lines). The
// stop cap is the routes book's served `stop_max`, the knob a standing route keeps. "Same city" is not a rule of the
// sea: a stop that is already the last one is simply not a new stop.

export type RouteHold =
  | { kind: 'open' }
  | { kind: 'none' } // no next stop tapped
  | { kind: 'checking' } // the server has not answered for this route yet
  | { kind: 'same' } // the tapped city is the last stop already
  | { kind: 'max'; n: number } // the kept stops are at the cap
  | { kind: 'shut'; leg: RouteLeg } // the server calls the leg shut
  | { kind: 'noWater' } // no water joins it (the course author found none)

interface Draft {
  /** The fleet these stops are for: a draft for another fleet (or none) is no draft. */
  fleetId: string | null
  kept: readonly string[]
  next: string | null
  refusal: string | null
}

const EMPTY: Draft = { fleetId: null, kept: [], next: null, refusal: null }
const NO_STOPS: readonly string[] = []

/** The route mode of ONE fleet; null when the chart is not in route mode (the hook is then inert and asks nothing). */
export function useRouteBuilder(fleet: FleetView | null) {
  const issueLines = useWorld((s) => s.issueLines)
  const stopMax = useWorld((s) => s.routes?.stop_max ?? null)
  const [draft, setDraft] = useState<Draft>(EMPTY)
  const [sending, setSending] = useState(false)
  const mine = fleet !== null && draft.fleetId === fleet.id
  const kept = mine ? draft.kept : NO_STOPS
  const next = mine ? draft.next : null
  const refusal = mine ? draft.refusal : null
  /** A change to THIS fleet's draft (a draft left from another fleet starts over). */
  const edit = (change: (d: Draft) => Partial<Draft>) => {
    if (!fleet) return
    setDraft((d) => {
      const own = d.fleetId === fleet.id ? d : { ...EMPTY, fleetId: fleet.id }
      return { ...own, ...change(own) }
    })
  }

  // STOP 0, "Now": her harbour, or where her voyage ends; null when she lies at anchor on open water.
  const where = fleet ? whereabouts(fleet) : null
  const start = where?.kind === 'docked' ? where.port : where?.kind === 'sailing' ? where.to : null
  const last = kept.length > 0 ? kept[kept.length - 1] : start
  const same = next !== null && next === last
  const codes = useMemo(() => (next !== null && !same ? [...kept, next] : kept), [kept, next, same])
  const legs = useSailLegs(fleet, codes)

  // THE SERVER'S JUDGEMENT of every leg, asked whenever the stops change (and on the world's beat while the bar is up)
  const ask = useMemo<RouteLegAsk[]>(
    () => legs.map((l, i) => ({ from: l.from ?? (i === 0 ? start : null), to: l.to, course: l.path })),
    [legs, start],
  )
  const question = legs.length > 0 ? `${start ?? '-'}>${legs.map((l) => l.to).join('>')}` : null
  const read = useServedRead(fleet?.id ?? null, () => worldRouteLegs(fleet?.id ?? '', ask), { name: 'worldRouteLegs', question })
  const served = !read.stale && !read.loading && read.view && read.view.legs.length === legs.length ? read.view.legs : null

  const nextLeg = next !== null && !same && legs.length === codes.length ? (served?.[legs.length - 1] ?? null) : null
  const hold: RouteHold =
    next === null
      ? { kind: 'none' }
      : same
        ? { kind: 'same' }
        : stopMax !== null && kept.length >= stopMax
          ? { kind: 'max', n: stopMax }
          : legs.length < codes.length
            ? { kind: 'noWater' }
            : !nextLeg || stopMax === null
              ? { kind: 'checking' }
              : nextLeg.shut
                ? { kind: 'shut', leg: nextLeg }
                : { kind: 'open' }

  const tap = (code: string) => edit(() => ({ next: code, refusal: null }))
  const confirm = () => {
    if (hold.kind !== 'open' || next === null) return
    edit((d) => ({ kept: [...d.kept, next], next: null }))
  }
  const undo = () =>
    edit((d) => (d.next !== null ? { next: null, refusal: null } : { kept: d.kept.slice(0, -1), refusal: null }))
  /** Out of route mode: the draft is dropped, nothing is sent. */
  const reset = () => setDraft(EMPTY)
  /** Every kept stop, one SAIL line each with its proposed course, queued all or none. True when queued. */
  const final = async (): Promise<boolean> => {
    if (!fleet || sending || kept.length === 0) return false
    const keptLegs = legs.slice(0, kept.length)
    if (keptLegs.length !== kept.length) return false
    setSending(true)
    edit(() => ({ refusal: null }))
    const done = await issueLines(
      fleet.id,
      keptLegs.map((l) => ({ text: `SAIL ${l.to}`, path: l.path })),
    )
    setSending(false)
    if (!done) edit(() => ({ refusal: useWorld.getState().refusal?.sentence ?? null }))
    return done
  }

  return {
    start,
    kept,
    next: same ? null : next,
    legs,
    served,
    hold,
    sending,
    refusal,
    tap,
    confirm,
    undo,
    final,
    reset,
  }
}

export type RouteBuilder = ReturnType<typeof useRouteBuilder>
