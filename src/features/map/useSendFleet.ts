import { useCallback, useEffect, useMemo, useState } from 'react'
import type { LatLon } from '../../lib/geo'
import type { FleetView, Refusal, VerbSpec } from '../../lib/rpc'
import { findVerb, fixAction, isComplete, orderText, sailEstimate, useCommandDraft, verbWord, type SailInsurance } from '../../domain/order'
import { fleetNow, passageLines, proposeCourse, roadsteadCourseNote, sailOrigin, sailTarget, shutByReach, type PassagePlan } from '../../domain/passage'
import { planPassage } from '../../live/passagePlan'
import { useWorld } from '../../live/worldStore'
import {
  destArgs,
  destName,
  standingOf as standingFor,
  type Act,
  type Fix,
  type SailDest,
  type Standing,
  type Verdict,
} from './sendRules'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE SEND FLOW — every decision the place tray makes, and no markup.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// THE OWNER, 2026-08-24: *"press send fleet, then it will unfold to my fleets, then when i press
// fleet, it will show how i can set my cargo/provision ratio. then i will press and it will send,
// without going to another screen."* That flow is unchanged; what changed on 2026-09-09 is that
// it lives in a `Tray` (SendFleet.tsx) and its rules live here and in sendRules.ts. `SendFleet.tsx`
// was 753 lines in one component with twelve selectors, five `useState`s and the async closures
// inline; this is the selectors and the closures, and the tray is the markup.
//
// NOT A SECOND COMPOSER. One grammar (`cmd.verb_schema()`), one judge (`cmd.preview()` runs the
// real verb and rolls it back) and ONE issue path (`worldStore.issue` → `cmd.issue`). Everything
// here is a second CALLER of an existing authority.
//
// THE KEEP CONTROL IS GONE (owner row 203, 0225): supplies are bought automatically by every SAIL
// (`cmd.do_sail` through `public.supply_need`), so the tray no longer asks how many days to keep her
// at, holds no book of standing orders and writes none. What is left under a picked fleet is the
// insurance press (0213).
//
// EVERY ROW SAYS ITS OWN TRUTH: each sendable fleet is DRY-RUN against this exact destination —
// `cmd.preview` over the same course the send will carry — once, sequentially (every preview
// writes the store's one `refusal` slot), and only once the tray is open past its peek.
//
// A FAR CITY IS SENT IN ONE PRESS (the owner, 2026-11-13: *"i want the game to calculate which cities to cross
// automatically, and just tell me the final time, price reaching the destination when pressed send fleet"*). A harbour
// one leg cannot reach used to end the row at the server's "Leg too far". Now the one passage planner
// (domain/passage/chain.ts, live/passagePlan.ts) is asked: the harbours between are the SERVER's, every leg is one it
// calls open, and the row prints the whole trip's days and supplies. Send queues every SAIL through the one plan path
// (`worldStore.issueLines` → cmd.issue_lines), all or none. Her navigation still bounds each leg; only when no chain
// exists does the refusal stay, and it says so. A fleet under way still turns in one leg (cmd.divert), as before.
//
// STATE IS NOT STAMPED WITH THE PLACE ANY MORE. The tray is keyed by its destination, so a tap on
// the next harbour REMOUNTS it and every piece of state below starts clean by construction.

const NO_VERBS: readonly VerbSpec[] = []

export function useSendFleet(dest: SailDest, open: boolean) {
  const fleets = useWorld((s) => s.fleets)
  const preview = useWorld((s) => s.preview)
  const issue = useWorld((s) => s.issue)
  const issueLines = useWorld((s) => s.issueLines)
  const divert = useWorld((s) => s.divert)
  const portByCode = useWorld((s) => s.portByCode)
  const seaNav = useWorld((s) => s.seaNav)
  const cancelOrder = useWorld((s) => s.cancel)
  const clearQueue = useWorld((s) => s.clear)
  // A served reference or a frozen constant — never `?? []` inside the selector (React #185).
  const verbs = useWorld((s) => s.snapshot?.verbs) ?? NO_VERBS
  // Pressing a fleet also points the app-wide draft at her — "which hull is in hand" has one
  // authority (domain/order's draft) and the last pointing gesture wins.
  const selectFleet = useCommandDraft((s) => s.selectFleet)

  const [picked, setPicked] = useState<string | null>(null)
  const [verdicts, setVerdicts] = useState<Record<string, Verdict>>({})
  // What the one passage planner said of each row's trip: its days and supplies, or why no chain of harbours opens it.
  const [plans, setPlans] = useState<Record<string, PassagePlan>>({})
  const [act, setAct] = useState<Act | null>(null)
  // 0213: whether to insure her cargo on THIS passage. Off until pressed; the price is the dry run's
  // (`sailEstimate(...).insurance`, quoted by the server on the unasked SAIL), never worked out here.
  const [insured, setInsured] = useState<Record<string, boolean>>({})

  // WHERE THE PASSAGE ENDS, read off the intent's own tokens by the ONE authority
  // (domain/passage): for a harbour that is her ROADS (0076), not her quay.
  const args = useMemo(() => destArgs(dest), [dest])
  const target: LatLon | null = useMemo(() => sailTarget(args, portByCode), [args, portByCode])
  const roads = dest.kind === 'port' ? roadsteadCourseNote(portByCode[dest.code]?.roadstead.nm ?? 0) : null
  const spec = findVerb(verbs, 'SAIL')
  const standingOf = useCallback(
    (f: FleetView): Standing => standingFor(dest, f, (code) => portByCode[code] !== undefined),
    [dest, portByCode],
  )

  // ── THE DRY RUNS — sequential, once per fleet, only while the tray is open past its peek.
  useEffect(() => {
    if (!open || !spec || !seaNav || !target) return
    const todo = fleets.filter((f) => standingOf(f) === 'send' && verdicts[f.id] === undefined)
    if (todo.length === 0) return
    let alive = true
    void (async () => {
      for (const f of todo) {
        const origin = sailOrigin(f, portByCode)
        const course = origin ? proposeCourse(seaNav, origin, target) : null
        const result = await preview(f.id, orderText(spec, args, f.name), course)
        if (!alive) return
        const refusal = useWorld.getState().refusal
        let verdict: Verdict = result
          ? { kind: 'ok', result }
          : refusal
            ? { kind: 'refused', refusal }
            : { kind: 'silent' }
        // THE WHOLE TRIP, from the one passage planner: for a passage that sails, its supplies; for one refused by its
        // length or its stores, the way through the harbours between. Then the FIRST SAIL of that way is dry-run like
        // any other, so a row never offers a trip her first leg would refuse (short of crew, in debt).
        let plan: PassagePlan | null = null
        if (dest.kind === 'port' && (verdict.kind === 'ok' || (verdict.kind === 'refused' && shutByReach(verdict.refusal.code)))) {
          plan = await planPassage(f, dest.code, seaNav, portByCode)
          if (!alive) return
          if (verdict.kind === 'refused' && plan?.kind === 'open' && plan.stops.length > 0) {
            const leg = plan.legs[0]
            const first = await preview(f.id, orderText(spec, { dest: leg.to }, f.name), leg.path)
            if (!alive) return
            const why = useWorld.getState().refusal
            verdict = first ? { kind: 'chain', plan, first } : why ? { kind: 'refused', refusal: why } : { kind: 'silent' }
          }
        }
        const told = plan
        if (told) setPlans((p) => ({ ...p, [f.id]: told }))
        const said = verdict
        setVerdicts((v) => ({ ...v, [f.id]: said }))
      }
    })()
    return () => {
      alive = false
    }
  }, [open, fleets, spec, seaNav, target, args, dest, portByCode, preview, verdicts, standingOf])


  const pick = (f: FleetView) => {
    selectFleet(f.id)
    setPicked((p) => (p === f.id ? null : f.id))
  }

  /** THE PRICE OF INSURING HER CARGO on this passage, from her row's dry run — the server's quote on
   *  the unasked SAIL (0213). Null when the dry run has not answered, was refused, or quoted nothing
   *  (an empty hold). A fleet under way is never offered it: the cover is written in port. */
  const insuranceOf = (f: FleetView): SailInsurance | null => {
    if (f.voyage) return null
    const v = verdicts[f.id]
    return v?.kind === 'ok' ? sailEstimate(v.result.estimate).insurance : null
  }
  const insureOf = (f: FleetView): boolean => insured[f.id] === true && insuranceOf(f) !== null
  const setInsure = (f: FleetView, on: boolean) => setInsured((d) => ({ ...d, [f.id]: on }))

  /** What the one passage planner said of her trip here; null before it answered (or for a point of open sea). */
  const planOf = (f: FleetView): PassagePlan | null => plans[f.id] ?? null

  const busyOn = (f: FleetView) => act?.state === 'busy' && act.fleetId === f.id
  const fail = (f: FleetView) => setAct({ fleetId: f.id, state: 'refused', refusal: useWorld.getState().refusal })

  // ── THE SEND — THE ONE PATH: the one mover's own act for where she is: `issue` from a quay or an
  // anchor, `divert` when she is under way. Same authorities, same refusal channel, nothing decided
  // here. Her supplies for the passage are the SAIL's own business (0225).
  const send = (f: FleetView) => {
    if (busyOn(f) || !spec || !seaNav || !target) return
    setAct({ fleetId: f.id, state: 'busy', refusal: null })
    void (async () => {
      let okay: boolean
      if (f.voyage) {
        // READ, THEN TURN: at speed she makes real way between reads, and a course proposed from a
        // stale position can clip a coast she has already cleared (E_LAND on the bridge, found in
        // an acceptance drive).
        await useWorld.getState().refresh()
        const fresh = useWorld.getState().fleets.find((x) => x.id === f.id) ?? f
        const now = fleetNow(fresh, portByCode)
        const course = now ? proposeCourse(seaNav, now, target) : null
        okay = await divert(
          f.id,
          dest.kind === 'port' ? (portByCode[dest.code]?.id ?? null) : null,
          dest.kind === 'sea' ? { lat: dest.at.lat, lon: dest.at.lon } : null,
          course,
        )
      } else if (verdicts[f.id]?.kind === 'chain') {
        // THE WHOLE CHAIN IN ONE PRESS: every SAIL of the plan, queued all or none by the one plan path
        const v = verdicts[f.id]
        okay = v.kind === 'chain' && (await issueLines(f.id, passageLines(v.plan)))
      } else {
        const origin = sailOrigin(f, portByCode)
        const course = origin ? proposeCourse(seaNav, origin, target) : null
        // 0213: `SAIL <dest> INSURED` when asked — the grammar's own word (cmd.verb_schema's `insurance`
        // enum), written by the one line composer; the server prices and charges it at departure.
        const sailArgs = insureOf(f) ? { ...args, insurance: 'INSURED' } : args
        okay = await issue(f.id, orderText(spec, sailArgs, f.name), course)
      }
      if (!okay) return fail(f)
      setAct({ fleetId: f.id, state: 'sent', refusal: null })
    })()
  }

  /**
   * A FIX THAT NEEDS NO CHOICE IS DONE HERE (OWNER_REQUESTS row 51: no new page for a fix). A whole
   * order — `isComplete` is the one authority — goes down the SAME `cmd.issue` path with the SAME
   * `orderText` line every doorway sends.
   *
   * A FIX WITH AN ARGUMENT STILL TO CHOOSE IS NOT A BUTTON (2026-09-09). It used to hand off to
   * COMMAND's composer; COMMAND composes nothing now (the owner: *"they should be located
   * accordingly at different locations"*), and the choice such a fix asks for is made where its
   * verb lives — `SAIL TO <a nearer port>` by tapping that harbour on this chart, `SELL <good> ALL`
   * on PORT's Trade face. The refusal's own sentence names it; `fixesOf` offers no press for it.
   */
  const runFix = (f: FleetView, verb: string, fixArgs: Record<string, string>) => {
    const fixSpec = findVerb(verbs, verb)
    if (!fixSpec || !isComplete(fixSpec, fixArgs) || busyOn(f)) return
    setAct({ fleetId: f.id, state: 'busy', refusal: null })
    void (async () => {
      const okay = await issue(f.id, orderText(fixSpec, fixArgs, f.name), null)
      if (!okay) return fail(f)
      // A FIX CHANGES THE ANSWER. The verdict on her row was the refusal this fix was for; it is
      // forgotten, so the dry run asks the server again and the row says what is true NOW — a
      // passage, or the next refusal — instead of a stale "no" beside a fix that has already run.
      setAct(null)
      setPlans((p) => {
        const next = { ...p }
        delete next[f.id]
        return next
      })
      setVerdicts((v) => {
        const next = { ...v }
        delete next[f.id]
        return next
      })
    })()
  }

  /** A refusal's fixes as real presses — every one of them runs here, whole; a fix that still
   *  needs a choice is words in the refusal, not a dead button. */
  const fixesOf = (f: FleetView, refusal: Refusal): Fix[] =>
    refusal.fixes
      .map((fix) => fixAction(fix, verbs))
      .flatMap((action) => {
        if (action.kind === 'queue') {
          const run = () => void (action.verb === 'CLEAR' ? clearQueue(f.id) : cancelOrder(f.id, action.index))
          return [{ label: verbWord(action.verb), run }]
        }
        if (action.kind === 'compose') {
          const fixSpec = findVerb(verbs, action.verb)
          if (!fixSpec || !isComplete(fixSpec, action.args)) return []
          return [{ label: verbWord(action.verb), run: () => runFix(f, action.verb, action.args) }]
        }
        return []
      })

  return {
    fleets,
    destName: destName(dest),
    roads,
    standingOf,
    verdicts,
    planOf,
    picked,
    pick,
    act,
    insuranceOf,
    insureOf,
    setInsure,
    send,
    fixesOf,
  }
}

export type SendFlow = ReturnType<typeof useSendFleet>
