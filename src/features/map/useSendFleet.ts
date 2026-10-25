import { useCallback, useEffect, useMemo, useState } from 'react'
import type { LatLon } from '../../lib/geo'
import type { FleetView, Refusal, VerbSpec } from '../../lib/rpc'
import { findVerb, fixAction, isComplete, orderText, sailEstimate, useCommandDraft, verbWord, type SailInsurance } from '../../domain/order'
import { fleetNow, proposeCourse, roadsteadCourseNote, sailOrigin, sailTarget } from '../../domain/passage'
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
// STATE IS NOT STAMPED WITH THE PLACE ANY MORE. The tray is keyed by its destination, so a tap on
// the next harbour REMOUNTS it and every piece of state below starts clean by construction.

const NO_VERBS: readonly VerbSpec[] = []

export function useSendFleet(dest: SailDest, open: boolean) {
  const fleets = useWorld((s) => s.fleets)
  const preview = useWorld((s) => s.preview)
  const issue = useWorld((s) => s.issue)
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
  const standingOf = useCallback((f: FleetView): Standing => standingFor(dest, f), [dest])

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
        const verdict: Verdict = result
          ? { kind: 'ok', result }
          : refusal
            ? { kind: 'refused', refusal }
            : { kind: 'silent' }
        setVerdicts((v) => ({ ...v, [f.id]: verdict }))
      }
    })()
    return () => {
      alive = false
    }
  }, [open, fleets, spec, seaNav, target, args, portByCode, preview, verdicts, standingOf])


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
