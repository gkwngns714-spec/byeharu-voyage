import { useCallback, useEffect, useMemo, useState } from 'react'
import { formatVoyageDays } from '../../lib/format'
import type { LatLon } from '../../lib/geo'
import type { FleetView, Refusal, VerbSpec } from '../../lib/rpc'
import { findVerb, fixAction, isComplete, orderText, useCommandDraft, verbWord, type CommandIntent } from '../../domain/order'
import { fleetNow, proposeCourse, roadsteadCourseNote, sailOrigin, sailTarget } from '../../domain/passage'
import { useWorld } from '../../live/worldStore'
import {
  atLeastOneDay,
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
// real verb and rolls it back), ONE issue path (`worldStore.issue` → `cmd.issue`) and ONE
// standing-order authority (`worldStore.applyPreset`/`savePreset` — a fleet holds a REFERENCE,
// 0034). Everything here is a second CALLER of an existing authority.
//
// THE RATIO IS A NUMBER OF DAYS, RESOLVED THROUGH THE BOOK: if the house already keeps an order at
// those days it IS that order, and only otherwise is one written (named for its depth, through
// `formatVoyageDays`, so FLEETS' book reads exactly like the figure it was set from). The map
// cannot mint a second, parallel set of standing orders (row 45's rule). A preset chip SETS the
// days; the one pinned button sends — there used to be two spellings of "what she sails under"
// (a chip that sent on press, and a days figure); now there is one, and `nudge`/`setDays` write
// nothing and send nothing.
//
// EVERY ROW SAYS ITS OWN TRUTH: each sendable fleet is DRY-RUN against this exact destination —
// `cmd.preview` over the same course the send will carry — once, sequentially (every preview
// writes the store's one `refusal` slot), and only once the tray is open past its peek.
//
// STATE IS NOT STAMPED WITH THE PLACE ANY MORE. The tray is keyed by its destination, so a tap on
// the next harbour REMOUNTS it and every piece of state below starts clean by construction.

const NO_VERBS: readonly VerbSpec[] = []

export function useSendFleet(dest: SailDest, open: boolean, onCompose: (intent: CommandIntent) => void) {
  const fleets = useWorld((s) => s.fleets)
  const preview = useWorld((s) => s.preview)
  const issue = useWorld((s) => s.issue)
  const divert = useWorld((s) => s.divert)
  const portByCode = useWorld((s) => s.portByCode)
  const seaNav = useWorld((s) => s.seaNav)
  const book = useWorld((s) => s.presets)
  const loadPresets = useWorld((s) => s.loadPresets)
  const applyPreset = useWorld((s) => s.applyPreset)
  const savePreset = useWorld((s) => s.savePreset)
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
  const [days, setDaysHeld] = useState<Record<string, number>>({})

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

  // The book of standing orders, read once the ratio step first matters.
  useEffect(() => {
    if (picked !== null && book === null) void loadPresets()
  }, [picked, book, loadPresets])

  const presetOf = (fleetId: string) => book?.presets.find((p) => p.fleets.some((fl) => fl.id === fleetId)) ?? null

  /**
   * THE DEPTH THE RATIO OPENS ON — every branch READS a served figure; none computes one:
   * (1) what the player set on this tray, (2) the standing order she sails under (0034's book),
   * (3) the SERVER's own `need` off this row's refusal, (4) the deepest order the book holds,
   * (5) her range NOW, `endurance_days` (0016), rounded up. Never an invented default: a number
   * typed here would be a rule about how deep a hold should be provisioned, which is the server's.
   */
  const daysOf = (f: FleetView): number => {
    if (days[f.id] !== undefined) return days[f.id]
    const current = presetOf(f.id)
    if (current) return current.days
    const v = verdicts[f.id]
    const need = v?.kind === 'refused' ? (v.refusal.figures?.need ?? null) : null
    if (need !== null && need > 0) return atLeastOneDay(need)
    const deepest = (book?.presets ?? []).reduce((most, p) => Math.max(most, p.days), 0)
    if (deepest > 0) return deepest
    return atLeastOneDay(f.endurance_days)
  }
  /** Move the figure. No ceiling on purpose: what a hold can carry is judged by `cmd.do_provision`
   *  and the days are bound by the table's own CHECK, and neither is restated here. */
  const setDays = (f: FleetView, to: number) => setDaysHeld((d) => ({ ...d, [f.id]: Math.max(1, to) }))
  const nudge = (f: FleetView, by: number) => setDays(f, daysOf(f) + by)

  const pick = (f: FleetView) => {
    selectFleet(f.id)
    setPicked((p) => (p === f.id ? null : f.id))
  }

  const busyOn = (f: FleetView) => act?.state === 'busy' && act.fleetId === f.id
  const fail = (f: FleetView) => setAct({ fleetId: f.id, state: 'refused', refusal: useWorld.getState().refusal })

  // ── THE SEND — THE ONE PATH. The standing order through the book, applied only when it CHANGES
  // her, then the one mover's own act for where she is: `issue` from a quay or an anchor, `divert`
  // when she is under way. Same authorities, same refusal channel, nothing decided here.
  const send = (f: FleetView) => {
    if (busyOn(f) || !spec || !seaNav || !target) return
    const keep = daysOf(f)
    setAct({ fleetId: f.id, state: 'busy', refusal: null })
    void (async () => {
      const held = () => useWorld.getState().presets?.presets.find((p) => p.days === keep)
      let order = held()
      if (!order) {
        if (!(await savePreset(null, formatVoyageDays(keep, 0), keep))) return fail(f)
        // `savePreset` re-reads the book before it returns; it FAILS CLOSED if the order it just
        // wrote cannot be found rather than sailing her under one nobody asked for.
        order = held()
        if (!order) return fail(f)
      }
      const current = presetOf(f.id)?.id ?? null
      if (order.id !== current && !(await applyPreset(f.id, order.id))) return fail(f)
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
        okay = await issue(f.id, orderText(spec, args, f.name), course)
      }
      if (!okay) return fail(f)
      setAct({ fleetId: f.id, state: 'sent', refusal: null })
    })()
  }

  /**
   * A FIX THAT NEEDS NO CHOICE IS DONE HERE (OWNER_REQUESTS row 51: no new page for a provision
   * fix). `PROVISION FULL` is a whole order already — `isComplete` is the one authority — and it
   * goes down the SAME `cmd.issue` path with the SAME `orderText` line COMMAND would send. It fills
   * to her standing order (`daysOf`), not to the brim: FULL took Gaivota to 89.3 days and 0 t of
   * hold free on production, 2026-08-31. The hand-off SURVIVES where it is honest — a fix with an
   * argument still to choose (`SAIL TO <a nearer port>`) genuinely needs the composer.
   */
  const runFix = (f: FleetView, verb: string, fixArgs: Record<string, string>) => {
    const fixSpec = findVerb(verbs, verb)
    if (!fixSpec || !isComplete(fixSpec, fixArgs)) {
      onCompose({ fleetId: f.id, verb, args: fixArgs })
      return
    }
    if (busyOn(f)) return
    const runArgs = verb === 'PROVISION' ? { mode: 'DAYS', days: String(daysOf(f)) } : fixArgs
    setAct({ fleetId: f.id, state: 'busy', refusal: null })
    void (async () => {
      const okay = await issue(f.id, orderText(fixSpec, runArgs, f.name), null)
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

  /** A refusal's fixes as real presses: never a dead line. */
  const fixesOf = (f: FleetView, refusal: Refusal): Fix[] =>
    refusal.fixes
      .map((fix) => fixAction(fix, verbs))
      .flatMap((action) => {
        if (action.kind === 'queue') {
          const run = () => void (action.verb === 'CLEAR' ? clearQueue(f.id) : cancelOrder(f.id, action.index))
          return [{ label: verbWord(action.verb), run }]
        }
        if (action.kind === 'compose') return [{ label: verbWord(action.verb), run: () => runFix(f, action.verb, action.args) }]
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
    daysOf,
    setDays,
    nudge,
    send,
    fixesOf,
    /** The house's standing orders; null until the book has been read. */
    presets: book?.presets ?? null,
  }
}

export type SendFlow = ReturnType<typeof useSendFleet>
