import { useMemo, useState } from 'react'
import { whereabouts } from '../../domain/fleet'
import { proposeCourse, sailTarget } from '../../domain/passage'
import { routeOfFleet } from '../../domain/route'
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
//   Via N  (B3) → a shut leg the server can break at N harbours (`via`): Confirm reads "Via N" and keeps the N
//                 harbours and the city; every one of those legs is then judged by the server like any other
//   Repeat (B4) → the kept stops become a LOOP in the one route editor (live/RouteEditor.tsx, seeded): her harbour
//                 first, then the kept stops. The closing leg (last stop → her harbour) is judged with the rest
//
// NOT A SECOND AUTHORITY. The courses are the one course author's (`useSailLegs` → `proposeCourse`, as a plan's and a
// queued trip's); whether a leg is open is the SERVER's (`world.route_legs` → voyage.leg_refusal, 0346), printed and
// never worked out here; the lines are queued by the one plan path (`worldStore.issueLines` → cmd.issue_lines). The
// stop cap is the routes book's served `stop_max`, the knob a standing route keeps. "Same city" is not a rule of the
// sea: a stop that is already the last one is simply not a new stop. The harbours of "Via N" are the SERVER's
// (`reach_passage`, served on the shut leg) and are never searched for here. A KEPT leg the server calls shut (a via
// harbour whose proposed course it measures longer, a hold that filled since) holds Final and Repeat back, and its
// line says why; Undo takes it away.

export type RouteHold =
  | { kind: 'open' }
  | { kind: 'none' } // no next stop tapped
  | { kind: 'checking' } // the server has not answered for this route yet
  | { kind: 'same' } // the tapped city is the last stop already
  | { kind: 'max'; n: number } // the kept stops are at the cap
  | { kind: 'shut'; leg: RouteLeg } // the server calls the leg shut
  | { kind: 'via'; leg: RouteLeg; stops: readonly string[] } // shut, but the server names harbours between that open it
  | { kind: 'noWater' } // no water joins it (the course author found none)

/** Whether the kept stops can be made a loop (Repeat), and — when they can — the loop's stops, her harbour first. */
export type RouteRepeat =
  | { kind: 'open'; stops: readonly string[] }
  | { kind: 'none' } // nothing to repeat: no stop kept, she is not in a harbour, routes are not open, or she runs one
  | { kind: 'checking' } // the server has not judged the closing leg yet
  | { kind: 'max'; n: number } // her harbour and the kept stops are more than a route holds
  | { kind: 'shut'; leg: RouteLeg } // the server calls the closing leg shut
  | { kind: 'noWater' } // no water closes the loop

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
  const book = useWorld((s) => s.routes)
  const seaNav = useWorld((s) => s.seaNav)
  const portByCode = useWorld((s) => s.portByCode)
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

  // THE LOOP (Repeat): her harbour, then the kept stops; a trip that already ends at her harbour closes itself. A
  // standing route starts only from one of its own stops with the fleet in port (cmd.standing_route_assign), so a
  // fleet at sea has no loop to offer. THE CLOSING LEG — last stop → her harbour — is proposed by the one course
  // author between the two roadsteads, as the editor's save proposes it (standingRouteDraft.ts), and judged by the
  // server in the SAME read as the other legs.
  const home = where?.kind === 'docked' ? where.port : null
  const loopKey = home !== null && kept.length > 0 ? [home, ...(last === home ? kept.slice(0, -1) : kept)].join(' ') : ''
  const loop = useMemo(() => (loopKey.includes(' ') ? loopKey.split(' ') : null), [loopKey])
  const closeFrom = loop !== null && last !== null && last !== home ? last : null
  const closeCourse = useMemo(() => {
    if (closeFrom === null || home === null || !seaNav) return null
    const from = sailTarget({ dest: closeFrom }, portByCode)
    const to = sailTarget({ dest: home }, portByCode)
    return from && to ? proposeCourse(seaNav, from, to) : null
  }, [closeFrom, home, seaNav, portByCode])
  const asked = useMemo<RouteLegAsk[]>(
    () => (closeFrom !== null && home !== null && closeCourse ? [...ask, { from: closeFrom, to: home, course: closeCourse }] : ask),
    [ask, closeFrom, home, closeCourse],
  )
  const closing = asked.length > ask.length
  const read = useServedRead(fleet?.id ?? null, () => worldRouteLegs(fleet?.id ?? '', asked), {
    name: 'worldRouteLegs',
    question: question !== null && closing ? `${question}|${home}` : question,
  })
  const answer = !read.stale && !read.loading && read.view && read.view.legs.length === asked.length ? read.view.legs : null
  const served = useMemo(() => (answer ? answer.slice(0, legs.length) : null), [answer, legs.length])
  const closeLeg = closing ? (answer?.[legs.length] ?? null) : null

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
              : !nextLeg.shut
                ? { kind: 'open' }
                : nextLeg.via && nextLeg.via.length > 0 && kept.length + nextLeg.via.length + 1 <= stopMax
                  ? { kind: 'via', leg: nextLeg, stops: nextLeg.via }
                  : { kind: 'shut', leg: nextLeg }

  // A KEPT STOP THE TRIP CANNOT USE: no water to it, or a leg the server calls shut. Final and Repeat wait for Undo.
  const blocked = legs.length < kept.length || (served?.slice(0, kept.length).some((l) => l.shut !== null) ?? false)
  const repeat: RouteRepeat =
    !fleet || loop === null || blocked || !book?.enabled || routeOfFleet(book, fleet.id) !== null
      ? { kind: 'none' }
      : stopMax !== null && loop.length > stopMax
        ? { kind: 'max', n: stopMax }
        : closeFrom === null
          ? { kind: 'open', stops: loop }
          : !closing
            ? { kind: 'noWater' }
            : !closeLeg
              ? { kind: 'checking' }
              : closeLeg.shut
                ? { kind: 'shut', leg: closeLeg }
                : { kind: 'open', stops: loop }

  const tap = (code: string) => edit(() => ({ next: code, refusal: null }))
  const confirm = () => {
    if ((hold.kind !== 'open' && hold.kind !== 'via') || next === null) return
    // "Via N": the server's harbours between, then the city
    const between = hold.kind === 'via' ? hold.stops : NO_STOPS
    edit((d) => ({ kept: [...d.kept, ...between, next], next: null }))
  }
  const undo = () =>
    edit((d) => (d.next !== null ? { next: null, refusal: null } : { kept: d.kept.slice(0, -1), refusal: null }))
  /** Out of route mode: the draft is dropped, nothing is sent. */
  const reset = () => setDraft(EMPTY)
  /** A draft handed in from outside the map (routeSeed.ts): these stops are kept, up to the cap. Every leg is judged
   *  by the server like a confirmed one; a shut leg holds Final back and says why, and Undo takes it away. */
  const seed = (fleetId: string, stops: readonly string[]) =>
    setDraft({ fleetId, kept: stopMax !== null ? stops.slice(0, stopMax) : [...stops], next: null, refusal: null })
  /** Every kept stop, one SAIL line each with its proposed course, queued all or none. True when queued. */
  const final = async (): Promise<boolean> => {
    if (!fleet || sending || kept.length === 0 || blocked) return false
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
    blocked,
    repeat,
    sending,
    refusal,
    tap,
    confirm,
    undo,
    final,
    reset,
    seed,
  }
}

export type RouteBuilder = ReturnType<typeof useRouteBuilder>
