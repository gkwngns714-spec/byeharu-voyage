import { useEffect, useState } from 'react'
import {
  Explain, Button, RefusalNote, SectionLabel, fineClass } from '../../components/ui'
import { formatNm, formatVoyageDays } from '../../lib/format'
import type { LatLon } from '../../lib/geo'
import type { FleetView, PreviewResult, Refusal, SnapshotPort, VerbSpec } from '../../lib/rpc'
import {
  findVerb,
  fixAction,
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
//
// Each step unfolds under the thing that was pressed (the BUY good-row pattern, the owner's own
// favourite); nothing navigates, nothing is replaced, and the map stays the map. This supersedes
// the first cut of this block (SailHere), which named the intent and then NAVIGATED to Command to
// press Issue — a new screen standing between the decision and the act.
//
// ── WHAT THIS IS NOT, AND THAT IS THE WHOLE DESIGN ─────────────────────────────────────────────
// It is NOT a second order composer, and not a second preset editor either. One composer
// (`features/command`), one grammar (`cmd.verb_schema()`), one judge (`cmd.preview()` runs the
// real verb and rolls it back), ONE issue path (`worldStore.issue` → `cmd.issue`) and ONE
// standing-order authority (`worldStore.applyPreset` → `cmd.provision_preset_apply`, the same
// call the FLEETS galley chips make — a fleet holds a REFERENCE, 0034). Everything here is a
// second CALLER of an existing authority; nothing here is a picker of arguments, a quantity
// control, a legality rule, or a place presets are made (the book is written on FLEETS).
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
  /** A row that can be SENT from a quay or an anchor — at-sea fleets turn instead (divert). */
  const sendable = (f: FleetView) => f.voyage == null && !liesHere(f)

  // ── THE DRY RUNS — one per sendable fleet, once per destination, only while the list is open.
  // SEQUENTIAL, because every preview writes the store's one `refusal` slot and two in flight
  // would race for it; and each is a real transaction on the server. The verdict map already
  // holding a fleet is what stops this re-asking on every world read.
  useEffect(() => {
    if (!open || !spec || !seaNav || !target) return
    const todo = fleets.filter((f) => sendable(f) && byFleet[f.id] === undefined)
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

  // ── THE SEND — ratio first (only when it changes her), then the one mover's own act for where
  // she is: `issue` from a quay or an anchor, `divert` when she is under way. Same authorities,
  // same refusal channel, nothing decided on this side of the wire.
  const send = (f: FleetView, presetId: string | null) => {
    if (act?.state === 'busy') return
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

  /** A refusal's fixes as real buttons: a composable fix loads the one composer; a queue fix acts
   *  on the queue through the store's own cancel/clear. Never a dead line. */
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
                onCompose({ fleetId: f.id, verb: action.verb, args: action.args })
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

      {/* STEP TWO — her fleets, each row carrying its own verdict about THIS destination. */}
      {open && fleets.length > 0 && (
        <div className="space-y-1.5" data-testid="map-send-fleets">
          {fleets.map((f) => {
            const acted = act?.key === destKey && act.fleetId === f.id ? act : null
            const v = byFleet[f.id]
            const lies = liesHere(f)
            const bound = boundHere(f)
            const pressable = !lies && !bound
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
                        Pressing an order sets it and sends her at once. The book of standing orders itself is
                        written on Fleets.
                      </Explain>
                    </SectionLabel>
                    <span className="flex flex-wrap gap-2">
                      <Button
                        variant={current === null ? 'chip-on' : 'chip'}
                        onClick={() => send(f, null)}
                        data-testid="map-send-keep-none"
                      >
                        None
                      </Button>
                      {(book?.presets ?? []).map((p) => (
                        <Button
                          key={p.id}
                          variant={current?.id === p.id ? 'chip-on' : 'chip'}
                          onClick={() => send(f, p.id)}
                          data-testid="map-send-keep-preset"
                        >
                          {p.name} · {formatVoyageDays(p.days)}
                        </Button>
                      ))}
                    </span>
                    {book === null && (
                      <p className={fineClass()}>reading her standing orders…</p>
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
