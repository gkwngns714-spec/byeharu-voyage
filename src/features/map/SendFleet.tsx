import { useEffect, useState } from 'react'
import {
  Explain, Button, Gauge, HeroFigure, RefusalNote, SectionLabel, fineClass } from '../../components/ui'
import { formatFixed, formatNm, formatVoyageDays } from '../../lib/format'
import type { LatLon } from '../../lib/geo'
import type { FleetView, PreviewResult, Refusal, SnapshotPort, VerbSpec } from '../../lib/rpc'
import {
  findVerb,
  fixAction,
  isComplete,
  orderText,
  sailEstimate,
  useCommandDraft,
  type CommandIntent,
} from '../../domain/order'
import { fleetNow, pointLabel, pointToken, proposeCourse, sailOrigin } from '../../domain/passage'
import { portNameOf, useWorld } from '../../live/worldStore'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// SEND FLEET — the map's one act, completed ON the map, unfolding step by step
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// THE OWNER, 2026-08-24: *"in map, instead of send gaviota tab, i want to press send fleet, then
// it will unfold to my fleets, then when i press fleet, it will show how i can set my
// cargo/provision ratio. then i will press and it will send, without going to another screen or
// creating a new screen."*
//
//   tap a place →  [ Send fleet ]
//                     ↓ unfolds beneath it
//                  her fleets, each with the passage's own verdict on its row
//                     ↓ press one, unfolds beneath THAT row
//                  her standing order (0034's provision presets) — press one, and it sends
//                  …and, beneath the orders she already has, THE RATIO ITSELF — a bar, two
//                  figures, and one named press that writes it into the book and sends her
//
// Each step unfolds under the thing that was pressed (the BUY good-row pattern, the owner's own
// favourite); nothing navigates, nothing is replaced, and the map stays the map. This supersedes
// the first cut of this block (SailHere), which named the intent and then NAVIGATED to Command to
// press Issue — a new screen standing between the decision and the act.
//
// ── WHAT THIS IS NOT, AND THAT IS THE WHOLE DESIGN ─────────────────────────────────────────────
// It is NOT a second order composer. One composer (`features/command`), one grammar
// (`cmd.verb_schema()`), one judge (`cmd.preview()` runs the real verb and rolls it back), ONE
// issue path (`worldStore.issue` → `cmd.issue`) and ONE standing-order authority
// (`worldStore.applyPreset`/`savePreset` → `cmd.provision_preset_apply`/`_save`, the same two
// calls the FLEETS book presses — a fleet holds a REFERENCE, 0034). Everything here is a second
// CALLER of an existing authority; nothing here picks an argument for a VERB, bounds a quantity,
// or judges an order.
//
// ── THE RATIO IS SET HERE NOW, AND WHY THAT IS STILL NOT A COMPOSER (2026-08-25) ───────────────
// This block used to end at the preset chips, and the owner's row 45 was therefore only half
// built: *"then when i press fleet, **it will show how i can set my cargo/provision ratio**"*. A
// house that had authored no standing order saw ONE chip — `None` — and had to leave the map for
// FLEETS to write a ratio before the fold could offer anything. That is exactly the screen-hop
// the request exists to delete.
//
// A standing order is NOT an order. `cmd.issue` composes a verb against a fleet and the server
// judges it; `cmd.provision_preset_save` writes a row in the house's own book — a target the
// server later fires at a quay, sized there, spent there. So setting a ratio here breaks neither
// the one-composer law (no verb, no argument, no legality check crosses this file) nor the
// one-authority law: the arithmetic of what a ratio COSTS lives in `cmd.do_provision` (0017's
// capacity authority) and is not restated, estimated or previewed on this side of the wire. The
// map holds a NUMBER OF DAYS and hands it to the book.
//
// The book is still the one place a ratio lives, which is why a ratio set here is LOOKED UP in it
// first and only written when it is not there — so the map cannot mint a second, parallel set of
// standing orders beside the ones FLEETS shows. `docs/OWNER_REQUESTS.md` row 45: *"Must COMPOSE
// 0034's presets, not mint a second way to set a ratio."*
//
// ── AND IT MUST NOT BECOME EASIER TO SEND BY ACCIDENT ──────────────────────────────────────────
// The chips send the instant they are pressed, which is the owner's own flow and stays. The ratio
// therefore had to be built so that ADJUSTING IT WRITES NOTHING AND SENDS NOTHING: − and + move a
// number held in this component and touch neither the book nor the fleet. Exactly one control in
// the ratio block dispatches a voyage, it is on its own line under the figures rather than beside
// them, and it says both what it will keep and that it will send. A stray tap while adjusting
// lands on a stepper, and a stepper cannot sail a fleet.
//
// ── EVERY ROW SAYS ITS OWN TRUTH ───────────────────────────────────────────────────────────────
// When the fleet list unfolds, each sendable fleet's row is DRY-RUN against this exact
// destination — `cmd.preview` over the same proposed course the send will carry — and the row
// prints the server's verdict: the passage's own miles and days, or the refusal, concisely
// (RefusalNote: figures when served, the sentence until then, the fixes as real buttons). A
// fleet that cannot be sent is never a silently dead entry: she lies here, she is already bound
// here, or the server's reason is printed on her row.
//
// ── THE REACH LAW ──────────────────────────────────────────────────────────────────────────────
// The whole flow lives in `MapPanel`'s content in a corner of the glass — chrome, not ink — in
// ordinary flow with no scroll cap, so no step can clip the press that finishes it.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/** The place the act is about: a harbour, or a pinpointed spot of open water (0039). */
export type SailDest =
  | { readonly kind: 'port'; readonly code: string; readonly name: string }
  | { readonly kind: 'sea'; readonly at: LatLon }

/**
 * WHAT SHE IS TO SAIL UNDER — the one argument the send takes besides the fleet.
 *
 *   `preset`  a standing order that already exists (a chip, or `null` for none)
 *   `days`    a ratio the player just set on the fold: LOOKED UP in the book, and written into it
 *             only if the book does not already hold it
 *
 * Two spellings of one thing rather than two send paths: `send` resolves this to a preset id
 * through the book's own RPCs and everything after that point is identical, so the ratio cannot
 * grow a second issue path, a second refusal channel or a second idea of what a standing order is.
 */
type Keep = { readonly kind: 'preset'; readonly id: string | null } | { readonly kind: 'days'; readonly days: number }

/** The server's verdict on one fleet's passage to this place — the dry run's answer, kept whole. */
type Verdict =
  | { kind: 'ok'; result: PreviewResult }
  | { kind: 'refused'; refusal: Refusal }
  /** The call came back with neither an estimate nor a refusal; the row stops saying "checking". */
  | { kind: 'silent' }

export function SendFleet({
  dest,
  verbs,
  onCompose,
}: {
  dest: SailDest
  /** The server's own grammar (`world.snapshot().verbs`). Nothing here lists verbs. */
  verbs: readonly VerbSpec[]
  /** A refusal's FIX that needs composing (PROVISION first, …) hands off to the one composer —
   *  the same seam FLEETS, PORT and MARKET use. The send itself never calls this. */
  onCompose: (intent: CommandIntent) => void
}) {
  const fleets = useWorld((s) => s.fleets)
  const preview = useWorld((s) => s.preview)
  const issue = useWorld((s) => s.issue)
  const divert = useWorld((s) => s.divert)
  const portByCode = useWorld((s) => s.portByCode)
  const seaNav = useWorld((s) => s.seaNav)
  const book = useWorld((s) => s.presets)
  const loadPresets = useWorld((s) => s.loadPresets)
  const applyPreset = useWorld((s) => s.applyPreset)
  // The ONE way a standing order is written, anywhere in the game — the same call FLEETS' book
  // makes. The map never inserts a preset by another route and never edits one it did not write.
  const savePreset = useWorld((s) => s.savePreset)
  const cancelOrder = useWorld((s) => s.cancel)
  const clearQueue = useWorld((s) => s.clear)
  // Pressing a fleet here also points the app-wide draft at her — "which hull is in hand" has one
  // authority (domain/order's draft) and the last pointing gesture wins, exactly as tapping her
  // glyph on the chart does.
  const selectFleet = useCommandDraft((s) => s.selectFleet)

  // THE FLOW'S TWO FOLDS, stamped with the place they are about: tapping the next place puts the
  // whole flow back to its button BY DERIVATION — nothing is reset in an effect.
  const [flow, setFlow] = useState<{ key: string; open: boolean; picked: string | null } | null>(null)
  // THE VERDICTS, per fleet, stamped the same way. Filled by the dry-run effect below.
  const [verdicts, setVerdicts] = useState<{ key: string; byFleet: Record<string, Verdict> } | null>(null)
  // THE SEND, stamped with place AND fleet — 'sent' survives the world's read-back so the row can
  // say "under way" rather than "already bound here" in the frame the player's own press caused.
  const [act, setAct] = useState<
    { key: string; fleetId: string; state: 'busy' | 'sent' | 'refused'; refusal: Refusal | null } | null
  >(null)
  // THE RATIO THE PLAYER IS SETTING, stamped with place AND fleet like everything else here. Null
  // means "they have not touched it", and the figure shown is then DERIVED (`ratioDays` below) —
  // so the control opens on something true about her rather than on a number typed into this file.
  // Nothing outside this component sees it until a send resolves it into the book.
  const [ratio, setRatio] = useState<{ key: string; fleetId: string; days: number } | null>(null)

  const destName = dest.kind === 'port' ? dest.name : pointLabel(dest.at)
  const destKey = dest.kind === 'port' ? dest.code : pointToken(dest.at)
  const target: LatLon | null =
    dest.kind === 'port'
      ? ((p) => (p ? { lat: p.lat, lon: p.lon } : null))(portByCode[dest.code])
      : dest.at

  // THE ONE INTENT'S ARGS — the same tokens a hand-off would carry and the order line will read.
  const args: Record<string, string> =
    dest.kind === 'port' ? { dest: dest.code } : { dest_point: pointToken(dest.at) }
  const spec = findVerb(verbs, 'SAIL')

  const open = flow?.key === destKey ? flow.open : false
  const picked = flow?.key === destKey ? flow.picked : null
  const byFleet = verdicts?.key === destKey ? verdicts.byFleet : {}

  const liesHere = (f: FleetView) =>
    dest.kind === 'port'
      ? f.port === dest.code
      : f.anchor != null && pointToken({ lat: f.anchor[0], lon: f.anchor[1] }) === destKey
  const boundHere = (f: FleetView) =>
    f.voyage != null &&
    (dest.kind === 'port'
      ? f.voyage.to === dest.code
      : f.voyage.dest_point != null &&
        pointToken({ lat: f.voyage.dest_point[0], lon: f.voyage.dest_point[1] }) === destKey)
  /** WHERE SHE STANDS RELATIVE TO THIS DESTINATION — the fold's ONE verdict about a fleet, read by
   *  the dry runs, by the row, and by the line that says the whole list is dead. There were two
   *  before this and they disagreed: a `sendable` that excluded every fleet at sea, and a row-local
   *  `!lies && !bound` that called those same fleets pressable. Both were right about their own
   *  question and neither could answer "can ANY of them go" — which is the question a player asks
   *  by pressing the button.
   *
   *    send  — lying at a quay or an anchor somewhere else: a real passage, previewed
   *    turn  — already at sea and bound elsewhere: her act is a divert, judged at the helm
   *    lies  — she is already AT this destination
   *    bound — she is already sailing to it
   */
  type Standing = 'send' | 'turn' | 'lies' | 'bound'
  const standingOf = (f: FleetView): Standing =>
    liesHere(f) ? 'lies' : boundHere(f) ? 'bound' : f.voyage != null ? 'turn' : 'send'

  // ── THE DRY RUNS — one per sendable fleet, once per destination, only while the list is open.
  // SEQUENTIAL, because every preview writes the store's one `refusal` slot and two in flight
  // would race for it; and each is a real transaction on the server. The verdict map already
  // holding a fleet is what stops this re-asking on every world read.
  useEffect(() => {
    if (!open || !spec || !seaNav || !target) return
    const todo = fleets.filter((f) => standingOf(f) === 'send' && byFleet[f.id] === undefined)
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
        setVerdicts((v) => ({
          key: destKey,
          byFleet: { ...(v?.key === destKey ? v.byFleet : {}), [f.id]: verdict },
        }))
      }
    })()
    return () => {
      alive = false
    }
    // `args`, `target`, `sendable` and `byFleet` are all derived from the deps listed — listing
    // the objects themselves would re-run the effect on every identity change of an equal value.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, destKey, fleets, spec, seaNav, portByCode, preview, verdicts])

  // The book of standing orders, read once the ratio step first matters. `loadPresets` re-reads
  // after every preset verb anyway; this only covers a map session that never visited FLEETS.
  useEffect(() => {
    if (picked !== null && book === null) void loadPresets()
  }, [picked, book, loadPresets])

  // ── THE SEND — THE ONE PATH, whether the order came from a chip or from the ratio.
  // The standing order is resolved through the book first, applied only when it CHANGES her, and
  // then the one mover's own act for where she is: `issue` from a quay or an anchor, `divert`
  // when she is under way. Same authorities, same refusal channel, nothing decided on this side
  // of the wire — and a second entrance for the ratio would have been a second one of all three.
  const send = (f: FleetView, keep: Keep) => {
    // ONE PRESS AT A TIME — but only for the press that is in flight. This guard used to read
    // `act?.state === 'busy'` unstamped, while the note that SHOWS "issuing the order…" is stamped
    // (`acted`, below) with the destination and the fleet. A request that never settles — and
    // nothing on this path has a timeout — therefore left every OTHER send on the map dead, with
    // its spinner invisible because the player had moved to a different harbour. Press, nothing,
    // press again, nothing, for the rest of the session: OWNER_REQUESTS row 49's own words.
    if (act?.state === 'busy' && act.key === destKey && act.fleetId === f.id) return
    if (!spec || !seaNav || !target) return
    setAct({ key: destKey, fleetId: f.id, state: 'busy', refusal: null })
    void (async () => {
      const fail = () =>
        setAct({
          key: destKey,
          fleetId: f.id,
          state: 'refused',
          refusal: useWorld.getState().refusal,
        })
      // ── THE STANDING ORDER SHE SAILS UNDER, resolved through the BOOK and nothing else.
      // A chip already names one. A ratio names a number of days: if the book holds an order at
      // those days it IS that order (the book is a set of day-targets, so asking for 15 when
      // "15 days" stands is not a new order), and only otherwise is one written. That is what
      // keeps the map from minting a second, parallel set of standing orders beside FLEETS'.
      const orderOf = async (): Promise<{ id: string | null } | null> => {
        if (keep.kind === 'preset') return { id: keep.id }
        const held = () => useWorld.getState().presets?.presets.find((p) => p.days === keep.days)
        const known = held()
        if (known) return { id: known.id }
        if (!(await savePreset(null, orderName(keep.days), keep.days))) return null
        // `savePreset` re-reads the book before it returns, and the days it just wrote are unique
        // in it by the branch above — so this cannot miss. It FAILS CLOSED if it ever does rather
        // than sailing her under an order nobody asked for.
        const written = held()
        return written ? { id: written.id } : null
      }
      const order = await orderOf()
      if (!order) return fail()
      const presetId = order.id
      const current = presetOf(f.id)?.id ?? null
      if (presetId !== current && !(await applyPreset(f.id, presetId))) return fail()
      let okay: boolean
      if (f.voyage) {
        // READ, THEN TURN. At speed she makes real way between reads, and a course proposed from
        // a stale position can clip a coast she has already cleared (found in an acceptance
        // drive: E_LAND on the bridge). A fresh read shrinks the bridge to what the server's own
        // allowance covers.
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
      if (!okay) return fail()
      setAct({ key: destKey, fleetId: f.id, state: 'sent', refusal: null })
    })()
  }

  const presetOf = (fleetId: string) =>
    book?.presets.find((p) => p.fleets.some((fl) => fl.id === fleetId)) ?? null

  /**
   * THE DEPTH THE RATIO OPENS ON — every branch READS a served figure; none of them computes one.
   *
   *   1. what the player has already set on this fold for this fleet, if they have touched it
   *   2. the standing order she already sails under (0034's book — the fleet holds a reference)
   *   3. the SERVER's own `need` from this row's refusal, when it serves figures — the forward
   *      contract `RefusalNote` already reads (OWNER_REQUESTS row 47's serving migration is not
   *      landed, so this is dark today and lights up with it, with no edit here)
   *   4. the deepest order the book already holds — the house's own habit
   *   5. her range NOW, `endurance_days` (0016's one authority), rounded up
   *
   * Never an invented default: a number typed here would be a rule about how deep a hold should
   * be provisioned, and that rule belongs to the server.
   */
  const ratioDays = (f: FleetView): number => {
    if (ratio?.key === destKey && ratio.fleetId === f.id) return ratio.days
    const current = presetOf(f.id)
    if (current) return current.days
    const v = byFleet[f.id]
    const need = v?.kind === 'refused' ? (v.refusal.figures?.need ?? null) : null
    if (need !== null && need > 0) return atLeastOneDay(need)
    const deepest = (book?.presets ?? []).reduce((most, p) => Math.max(most, p.days), 0)
    if (deepest > 0) return deepest
    return atLeastOneDay(f.endurance_days)
  }

  /** Move the figure. It writes NOTHING and sends NOTHING — see the header's last block. There is
   *  no ceiling here on purpose: what a hold can actually carry is judged by `cmd.do_provision`
   *  and the days bound by the table's own CHECK, and neither is restated on this side. */
  const nudge = (f: FleetView, by: number) =>
    setRatio({ key: destKey, fleetId: f.id, days: Math.max(1, ratioDays(f) + by) })

  /**
   * A FIX THAT NEEDS NO CHOICE IS DONE HERE — the owner, 2026-08-31 (OWNER_REQUESTS row 51):
   * *"when i press provision on map, it shouldn't go to a command page - no new page, but there
   * should be provision settings on map as well, on the same page"*.
   *
   * That is rows 15/20/25/28/45/46 said again about the one hand-off this screen still had, and a
   * repeated instruction means the wrong thing was built — so the hand-off GOES for the case it
   * was wrong about, rather than gaining a wrapper. `PROVISION FULL` is a whole order already:
   * the server's own grammar says so, and `isComplete` is the one authority that answers it.
   *
   * It is not a second way to provision. It goes down the SAME `cmd.issue` path with the SAME
   * `orderText` line COMMAND would have sent — this screen still composes nothing and still owns
   * no grammar. The only thing that changed is that it stopped navigating away to press a button
   * the player had already pressed.
   *
   * THE HAND-OFF SURVIVES where it is honest: a fix with an argument still to choose (`SAIL TO
   * <a nearer port>` — `fixAction` stops at the placeholder, so `args` is short) genuinely needs
   * the composer, and sending her under a guessed argument would be worse than a screen change.
   */
  const runFix = (f: FleetView, verb: string, args: Record<string, string>) => {
    const fixSpec = findVerb(verbs, verb)
    if (!fixSpec || !isComplete(fixSpec, args)) {
      onCompose({ fleetId: f.id, verb, args })
      return
    }
    /*
     * A PROVISION FIX FILLS TO HER STANDING ORDER, NOT TO THE BRIM.
     *
     * Driven on production 2026-08-31, immediately after this button first worked. The server's
     * fix text is `PROVISION FULL`, and FULL means every spare ton: Gaivota went from 0.9 to
     * **89.3 days** of stores for 81 ducats and came out **60/60 t, 0 t of hold free**. She could
     * then sail anywhere and buy nothing — one dead end swapped for another, and the quay went on
     * offering 0 routes because a hold with no room can carry no cargo.
     *
     * FULL is not wrong; it is the wrong DEFAULT for a one-tap fix on a fleet with an empty hold.
     * The owner has a system for exactly this — row 24's adjustable, saveable provision presets
     * (migration 0034) — and the fold two steps below already honours it. Only this button did not.
     *
     * `ratioDays` is that authority and it is reused rather than restated: her standing order
     * first, then the SERVER's own `need` off this very refusal, then the house's deepest habit,
     * then her present range. Every branch reads a served figure and none invents one, which is
     * why the fix can be re-pointed here without a rule about how deep a hold should be provisioned
     * appearing on the client.
     *
     * The verb's own grammar carries the shape: `mode` is an enum of FULL and DAYS (0008:186), so
     * this swaps one served enum value for the other and adds the number the same schema asks for.
     */
    const runArgs =
      verb === 'PROVISION' ? { mode: 'DAYS', days: String(ratioDays(f)) } : args
    // Stamped, for the same reason `send` is — this is the fix button on the same rows.
    if (act?.state === 'busy' && act.key === destKey && act.fleetId === f.id) return
    setAct({ key: destKey, fleetId: f.id, state: 'busy', refusal: null })
    void (async () => {
      const okay = await issue(f.id, orderText(fixSpec, runArgs, f.name), null)
      setAct({
        key: destKey,
        fleetId: f.id,
        state: okay ? 'sent' : 'refused',
        refusal: okay ? null : useWorld.getState().refusal,
      })
    })()
  }

  /** A refusal's fixes as real buttons: a composable fix is RUN here when it needs no choice and
   *  loads the one composer when it does; a queue fix acts on the queue through the store's own
   *  cancel/clear. Never a dead line. */
  const fixButtons = (f: FleetView, refusal: Refusal) => {
    if (refusal.fixes.length === 0) return null
    const actions = refusal.fixes
      .map((fix) => ({ fix, action: fixAction(fix, verbs) }))
      .filter(({ action }) => action.kind !== 'none')
    if (actions.length === 0) return null
    return (
      <span className="flex flex-wrap gap-2">
        {actions.map(({ fix, action }) => (
          <Button
            key={fix}
            variant="secondary"
            onClick={() => {
              if (action.kind === 'queue') {
                if (action.verb === 'CLEAR') void clearQueue(f.id)
                else void cancelOrder(f.id, action.index)
                return
              }
              if (action.kind === 'compose') {
                runFix(f, action.verb, action.args)
              }
            }}
          >
            {action.kind === 'queue' || action.kind === 'compose' ? action.verb : fix}
          </Button>
        ))}
      </span>
    )
  }

  return (
    <div className="mt-2 space-y-1.5" data-testid="map-send">
      {/* STEP ONE — the act's name, the owner's own words. Pressing it REVEALS (aria-expanded);
          pressing again is the same gesture undone. Never disabled. */}
      <Button
        variant="primary"
        className="w-full justify-center"
        aria-expanded={open}
        onClick={() => setFlow({ key: destKey, open: !open, picked: null })}
        data-testid="map-send-fleet"
      >
        Send fleet
      </Button>

      {open && fleets.length === 0 && (
        <p className={fineClass()} data-testid="map-send-none">
          No fleets yet — a house founds one before it can sail.
        </p>
      )}

      {/* THE DEAD END, NAMED. OWNER_REQUESTS row 49: *"i can't send a fleet in map."* A house with
          ONE fleet taps the harbour she is lying in — which is the most natural tap on the map,
          because her marker and her harbour's name are printed on top of each other — presses
          "Send fleet", and gets a list in which nothing can be pressed. Every row said why on
          itself, honestly, and the fold still read as broken: the player pressed SEND and no send
          existed. It says so ONCE, at the top, before they hunt for the control. */}
      {open && fleets.length > 0 && !fleets.some((f) => standingOf(f) !== 'lies' && standingOf(f) !== 'bound') && (
        <p className={fineClass()} data-testid="map-send-nowhere">
          {fleets.every((f) => standingOf(f) === 'lies')
            ? `Nothing to send — ${fleets.length === 1 ? 'she is' : 'they are'} already at ${destName}.`
            : `Nothing to send — every fleet is at ${destName} or bound for it.`}
        </p>
      )}

      {/* STEP TWO — her fleets, each row carrying its own verdict about THIS destination. */}
      {open && fleets.length > 0 && (
        <div className="space-y-1.5" data-testid="map-send-fleets">
          {fleets.map((f) => {
            const acted = act?.key === destKey && act.fleetId === f.id ? act : null
            const v = byFleet[f.id]
            const standing = standingOf(f)
            const lies = standing === 'lies'
            const pressable = standing === 'send' || standing === 'turn'
            const on = picked === f.id
            const current = presetOf(f.id)
            return (
              <div
                key={f.id}
                className={`rounded-md border p-2 ${on ? 'border-accent bg-accent-soft' : 'border-edge bg-app'}`}
                data-testid="map-send-row"
              >
                {pressable ? (
                  <button
                    type="button"
                    aria-expanded={on}
                    onClick={() => {
                      selectFleet(f.id)
                      setFlow({ key: destKey, open: true, picked: on ? null : f.id })
                    }}
                    className="block min-h-11 w-full text-left"
                    data-testid="map-send-row-head"
                  >
                    <span className="block font-mono text-xs text-ink">{f.name}</span>
                    <span className={fineClass('block')}>{whereOf(f, portByCode)}</span>
                  </button>
                ) : (
                  // NOT SILENTLY DEAD: a fleet that cannot be sent says why, on her row.
                  <p className="min-h-11 py-1">
                    <span className="block font-mono text-xs text-ink">{f.name}</span>
                    <span className={fineClass('block')} data-testid="map-send-row-note">
                      {lies
                        ? 'lies here'
                        : acted?.state === 'sent'
                          ? `Under way — she makes for ${destName}.`
                          : 'already bound here'}
                    </span>
                  </p>
                )}

                {/* THE ROW'S VERDICT — the server's, from the dry run over the same course the
                    send will carry. An at-sea fleet is not previewed: her act is a TURN, judged
                    when the helm goes over. */}
                {pressable && f.voyage != null && (
                  <p className={fineClass()}>at sea — she turns where she is</p>
                )}
                {pressable && f.voyage == null && v === undefined && (
                  <p className={fineClass()} data-testid="map-send-checking">
                    checking the passage…
                  </p>
                )}
                {pressable && v?.kind === 'ok' && (
                  <Passage result={v.result} />
                )}
                {pressable && v?.kind === 'refused' && (
                  <RefusalNote refusal={v.refusal} testId="map-send-refusal">
                    {fixButtons(f, v.refusal)}
                  </RefusalNote>
                )}

                {/* STEP THREE — her standing order (0034), unfolded beneath the pressed row.
                    Pressing an order chip SETS it (through the same applyPreset the FLEETS galley
                    presses) and SENDS her — the owner's "then i will press and it will send".
                    Nothing here writes a preset; the book is written on FLEETS. Gone once she is
                    under way (`pressable` flips), which is what puts the sent line on the row. */}
                {on && pressable && (
                  <div className="mt-2 space-y-1.5 border-t border-edge pt-2" data-testid="map-send-keep">
                    {/* THE LABEL IS THE INSTRUCTION. "press one - it sets her order and sends her" stood
                        here: a sentence explaining a row of buttons, on the very screen the owner had just
                        called too wordy - "make it very concise. This concise concept will have to be
                        applied to all aspects of the game." A chip that both sets the order and sends her is
                        NAMED for what it does, and then it needs no caption. The reason it also sends lives
                        behind the dot, where prose belongs (UI_DIRECTION section 4). */}
                    <SectionLabel className="mb-0">
                      Keep &amp; send
                      <Explain label="Keep and send" dotClassName="ml-0.5">
                        Pressing an order sets it and sends her at once. The bar sets a new one: stores share
                        the hold with cargo, so a deeper order is less room to trade with. Moving it sends
                        nothing — the press under it does.
                      </Explain>
                    </SectionLabel>
                    <span className="flex flex-wrap gap-2">
                      <Button
                        variant={current === null ? 'chip-on' : 'chip'}
                        onClick={() => send(f, { kind: 'preset', id: null })}
                        data-testid="map-send-keep-none"
                      >
                        None
                      </Button>
                      {(book?.presets ?? []).map((p) => (
                        <Button
                          key={p.id}
                          variant={current?.id === p.id ? 'chip-on' : 'chip'}
                          onClick={() => send(f, { kind: 'preset', id: p.id })}
                          data-testid="map-send-keep-preset"
                        >
                          {p.name} · {formatVoyageDays(p.days)}
                        </Button>
                      ))}
                    </span>
                    {book === null && (
                      <p className={fineClass()}>reading her standing orders…</p>
                    )}

                    {/* THE RATIO — the owner's *"it will show how i can set my cargo/provision ratio"*,
                        drawn as figures and a gauge rather than as a form (OWNER_REQUESTS row 46's law:
                        `▁▁▁▂ 2.9 / 33 days`, never a paragraph). The hero is `range now / the depth this
                        order keeps her at`, both in voyage-days: LEFT is the SERVER's `endurance_days`,
                        RIGHT is what the standing order would ask for. The gauge under it is `Gauge`
                        because stores are a COUNTABLE resource — its own header names "days of stores" as
                        the case it exists for, and `Meter` as the wrong one.

                        THE STEPPERS MOVE A NUMBER AND NOTHING ELSE: no RPC, no write to the book, no
                        send. Exactly one control here dispatches a voyage, it is on its own line below
                        the figures rather than beside them, and it names both halves of what it does.
                        Nothing is drawn until her book has been read, so the figure can never open on a
                        default that a standing order would have overruled. */}
                    {book !== null && (
                      <div className="space-y-1.5" data-testid="map-send-ratio">
                        {/* THE FIGURE GETS THE WHOLE WIDTH. It shared a row with the two steppers
                            once and wrapped mid-figure at 390 px — `15.0 /` over `16 days` — and a
                            hero broken across two lines is not a hero. The steppers go under it,
                            at the two ends, with the gauge between them. */}
                        <span className="block text-center" data-testid="map-send-ratio-figures">
                          <HeroFigure value={`${formatFixed(f.endurance_days, 1)} / ${ratioDays(f)}`} unit="days" />
                        </span>
                        <div className="flex items-center gap-2">
                          <Button
                            size="icon"
                            aria-label={`fewer days of stores for ${f.name}`}
                            onClick={() => nudge(f, -1)}
                            data-testid="map-send-ratio-less"
                          >
                            −
                          </Button>
                          <span className="flex min-w-0 flex-1 justify-center">
                            <Gauge
                              value={f.endurance_days}
                              max={ratioDays(f)}
                              tone={f.endurance_days >= ratioDays(f) ? 'success' : 'accent'}
                              label={`stores, ${formatFixed(f.endurance_days, 1)} of ${ratioDays(f)} days`}
                            />
                          </span>
                          <Button
                            size="icon"
                            aria-label={`more days of stores for ${f.name}`}
                            onClick={() => nudge(f, 1)}
                            data-testid="map-send-ratio-more"
                          >
                            +
                          </Button>
                        </div>
                        <Button
                          variant="primary"
                          className="w-full justify-center"
                          onClick={() => send(f, { kind: 'days', days: ratioDays(f) })}
                          data-testid="map-send-ratio-send"
                        >
                          Keep {ratioDays(f)} &amp; send
                        </Button>
                      </div>
                    )}
                    {acted?.state === 'busy' && (
                      <p className={fineClass()} data-testid="map-send-busy">
                        issuing the order…
                      </p>
                    )}
                    {acted?.state === 'sent' && (
                      <p className={fineClass()} data-testid="map-send-sent">
                        Under way — she makes for {destName}.
                      </p>
                    )}
                    {acted?.state === 'refused' && acted.refusal && (
                      <RefusalNote refusal={acted.refusal} testId="map-send-issue-refusal">
                        {fixButtons(f, acted.refusal)}
                      </RefusalNote>
                    )}
                    {/* A REFUSAL THE SERVER DID NOT NAME still has to say she did not sail. The
                        branch above is guarded on `acted.refusal`, so every path that fails
                        WITHOUT one — `savePreset` returning false with the store's refusal slot
                        empty is the live one — rendered absolutely nothing: the press was eaten,
                        the fleet stayed, and the screen said neither. That is the silence row 49
                        is about, and it is the same silence whatever caused it. */}
                    {acted?.state === 'refused' && !acted.refusal && (
                      <p className={fineClass()} data-testid="map-send-silent">
                        She did not sail, and the server gave no reason — try once more.
                      </p>
                    )}
                  </div>
                )}
              </div>
            )
          })}
        </div>
      )}
    </div>
  )
}

/** A whole number of days, never less than one — the shape the book's `days` column takes. It
 *  ROUNDS UP, because a target rounded down is a target that does not cover the thing it was read
 *  from. Not a rule about provisioning: the server judges every one of these. */
function atLeastOneDay(days: number): number {
  return Number.isFinite(days) ? Math.max(1, Math.ceil(days)) : 1
}

/**
 * WHAT A STANDING ORDER WRITTEN FROM THE MAP IS CALLED.
 *
 * A preset needs a name (0034: 2–24 characters, unique per house) and there is nobody on a map to
 * type one, so it is named for the only thing it is: its depth. Through `formatVoyageDays`, so the
 * game has ONE spelling of a days figure and this is not a second one — and so the name the book
 * shows on FLEETS reads exactly like the figure the fold set it from.
 *
 * It is NOT `nextName()` from the FLEETS book ("Order 1", "Order 2", …) and must never become a
 * copy of it: that rule numbers a row the player is about to rename, and this one describes a row
 * the player never sees being made. Two different jobs, deliberately not one shared helper with a
 * flag. If the house already holds an order under this exact name at OTHER days, the server's own
 * E_NAME_TAKEN comes back and is printed on the row like every other refusal.
 */
function orderName(days: number): string {
  return formatVoyageDays(days, 0)
}

/** Where she is, in the fleet chip's own wording — one line under the name. */
function whereOf(f: FleetView, portByCode: Record<string, SnapshotPort>): string {
  if (f.port) return portNameOf(portByCode, f.port)
  if (f.voyage) return 'at sea'
  if (f.anchor) return `at anchor · ${pointLabel({ lat: f.anchor[0], lon: f.anchor[1] })}`
  return f.status.toLowerCase()
}

/** The two figures a SAIL estimate carries — the SERVER's own sailed miles and voyage-days over
 *  the proposed course, read once for the whole app in `domain/order/estimate.ts`. */
function Passage({ result }: { result: PreviewResult }) {
  const { nm, days } = sailEstimate(result.estimate)
  if (nm === null && days === null) return null
  return (
    <p className="font-mono text-sm text-ink" data-testid="map-send-passage">
      {[nm === null ? null : formatNm(nm), days === null ? null : formatVoyageDays(days)]
        .filter(Boolean)
        .join(' · ')}
    </p>
  )
}
