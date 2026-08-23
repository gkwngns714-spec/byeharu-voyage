import { useEffect, useState } from 'react'
import { Badge, Button, fineClass } from '../../components/ui'
import { formatNm, formatVoyageDays } from '../../lib/format'
import type { FleetView, PreviewResult, Refusal, VerbSpec } from '../../lib/rpc'
import { findVerb, orderText, sailEstimate } from '../../domain/order'
import { useWorld } from '../../live/worldStore'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// SAIL HERE — the map's one act, and it does not compose an order
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// THE OWNER, 2026-08-23: the Map tab's caption read *"view only · orders on Command"*, which is a
// screen confessing it is unfinished — you could see your fleet, and 214 harbours, and act from
// none of them. It is gone, and this block is what replaced it.
//
// ── WHAT THIS IS NOT, AND THAT IS THE WHOLE DESIGN ─────────────────────────────────────────────
// It is NOT a second order composer. There is exactly one of those (`features/command`), one
// grammar (`cmd.verb_schema()`), and one judge of legality (the server, through `cmd.preview()`).
// This block contains **no argument picker, no quantity control and no legality check** — the three
// things whose appearance here would mean the defect had been rebuilt. What it does is:
//
//   1. name ONE intent — "SAIL, to this harbour, with the fleet the draft has in hand";
//   2. ask the SERVER whether that exact line would be accepted, and print its answer;
//   3. hand the intent to `domain/order`'s draft and go to Command, where it is composed.
//
// Step 3 is the same seam FLEETS, PORT and MARKET already use — `handOff(intent)` then
// `navigate('/command')`. Nothing new was invented to carry it: a route param or a store field of
// its own would be a second place a pending order lives, and there is one.
//
// ── ONE VALUE, TWO USES: WHY THE MAP CANNOT RECOMMEND WHAT `cmd.issue` WOULD REFUSE ────────────
// The `args` this block previews and the `args` it hands over are the SAME OBJECT, walked through
// the SAME composer (`orderText`, `domain/order`) that Command will walk when it re-derives the
// line. So the sentence the server judged and the sentence it is later asked to run are equal by
// construction rather than by agreement. `docs/DEV_LOG.md` records what the other shape cost: a
// picker that quoted Seville at 169 nm against the server's 286 and then SORTED by it.
//
// ── AND WHY THE ANSWER IS `cmd.preview()` AND NOT A CHECK OF OUR OWN ───────────────────────────
// `voyage.sail_refusal()` is THE answer to "may she sail there?" — crew, flagship, draught, ice,
// endurance (0019:396) — and `cmd.do_sail` RAISES exactly what it returns. It is also revoked from
// every client role (0019:461), deliberately, so the only honest way to ask it from a browser is
// to run the verb and throw it away, which is what `cmd.preview()` is. The refusal printed below is
// therefore not "our reading of the rules"; it is the sentence the commit would have produced.
//
// NOTHING IS EVER GREYED OUT SILENTLY, AND THE BUTTON IS NEVER DISABLED — same rule the haggle
// block keeps (`features/command/README.md` §10.1). A refused SAIL still hands over, because
// Command renders the refusal's FIXES as tappable orders ("PROVISION first"), and the fix is the
// thing the player actually wants. The map states the reason; Command offers the remedy.
//
// ── THE REACH LAW ──────────────────────────────────────────────────────────────────────────────
// `docs/CORE_REUSE.md` §1.5: an action may never live in a region that can scroll or clip it. This
// block is rendered inside `MapPanel`'s content, which carries no `max-h` and no `overflow` from
// the port branch of `DetailPanel`, and that panel is anchored to a CORNER OF THE GLASS — it is
// chrome, not ink, so panning the chart cannot carry the button off the screen. That is why the
// action is here and not on the marker: a control at a map coordinate can be panned away.

/** What the server said about this exact line. `null` while nothing has been asked. */
type Answer =
  | { kind: 'asking' }
  | { kind: 'ok'; result: PreviewResult }
  | { kind: 'refused'; refusal: Refusal }
  /** The call came back with neither an estimate nor a refusal. Nothing is printed, and — the
   *  point of having the case at all — the block stops saying "asking". */
  | { kind: 'silent' }

export function SailHere({
  fleet,
  portCode,
  portName,
  verbs,
  onSail,
}: {
  /** The hull the order is for — `domain/order`'s draft is the one authority for which that is,
   *  and this screen READS it rather than keeping a second idea of it. Null when the house has
   *  chosen none yet, in which case the hand-off carries none and Command asks. */
  fleet: FleetView | null
  portCode: string
  portName: string
  /** The server's own grammar (`world.snapshot().verbs`). Nothing here lists verbs. */
  verbs: readonly VerbSpec[]
  onSail: (fleetId: string | null, args: Record<string, string>) => void
}) {
  const preview = useWorld((s) => s.preview)
  const divert = useWorld((s) => s.divert)
  const portByCode = useWorld((s) => s.portByCode)
  // THE ANSWER, STAMPED WITH THE LINE IT IS ABOUT — `CommandScreen.tsx:176`'s shape, and for its
  // reason: keeping the answer rather than a status means the state can never describe an order
  // the player has already changed. Tapping the next harbour puts this back to `asking` BY
  // DERIVATION (below), so nothing has to be reset in an effect — which is also what keeps the
  // `react-hooks/set-state-in-effect` rule satisfied without disabling it.
  const [checked, setChecked] = useState<{ line: string; answer: Answer } | null>(null)
  // THE HELM (0037), stamped with the harbour it is about — same derivation trick as `checked`:
  // tapping another port makes this stale BY KEY, so nothing needs resetting in an effect.
  const [helm, setHelm] = useState<
    { code: string; state: 'busy' | 'turned' | 'refused'; refusal: Refusal | null } | null
  >(null)

  // THE ONE INTENT, stated once. Both the preview below and the hand-off read this object, which
  // is what makes them the same order rather than two orders that agree today.
  const args = { dest: portCode }
  const spec = findVerb(verbs, 'SAIL')
  const line = spec && fleet ? orderText(spec, args, fleet.name) : null

  // SHE IS LYING AT THIS VERY QUAY. Not a legality check — one served field, `fleet.port`, against
  // the port that was tapped. `features/command/README.md` §1 states the principle it follows: a
  // picker that cannot offer an impossible value is worth more than a refusal, and "sail to where
  // you are already tied up" is not an order anybody means.
  //
  // ⚠ AND IT IS DELIBERATELY **NOT** `fleetPortCode(fleet)`, WHICH IS A DIFFERENT QUESTION.
  // That one answers *"where does her NEXT ORDER happen"* — `fleet.port ?? fleet.voyage.to` — so
  // for a fleet at sea it returns the harbour she is BOUND for. The first draft of this line used
  // it, and driving the real game caught what that does: with Gaivota three minutes out of Lisbon
  // on a Cádiz passage, tapping Cádiz printed **"Gaivota lies here."** She was 248 nm away. One
  // field, two questions, and the wrong one was true-looking enough to ship.
  //
  // A fleet at sea and bound here therefore keeps the button. The panel above already says
  // `on passage · Gaivota`, and `cmd.preview` says the rest — the order would WAIT in her queue.
  // Neither of those is this file's opinion.
  const sheLiesHere = fleet?.port === portCode
  // UNDER WAY, the act changes (0037): the same tap on the same harbour is a DIVERT — she turns
  // at the next node and makes for it NOW — instead of a SAIL that would wait out the old passage
  // in her queue. Same panel, same corner, no mode: which act it is follows from where she is,
  // exactly as the button's label says. The queue-a-SAIL flow is still one tab away on Command.
  const underWay = fleet !== null && fleet.voyage != null
  const boundHere = underWay && fleet?.voyage?.to === portCode
  const asking = line !== null && fleet !== null && !sheLiesHere && !underWay

  // THE DRY RUN, debounced — every preview is a real transaction on the server (it runs the verb
  // and rolls it back), and a player crossing a crowded coast selects several ports on the way.
  // The same 250 ms the composer uses; the map does not own a second idea of "settle down".
  useEffect(() => {
    if (!asking || !line || !fleet) return
    let alive = true
    const timer = setTimeout(() => {
      void preview(fleet.id, line).then((result) => {
        if (!alive) return
        // A refusal arrives as store state, which is the store's stated contract for it ("the last
        // refusal any command produced, for the screen that issued it to render"). When the call
        // failed and left none, this prints NOTHING rather than a sentence of our own invention —
        // a fabricated reason is worse than a blank (docs/UI_DIRECTION.md §4 rule 5).
        const refusal = useWorld.getState().refusal
        setChecked({
          line,
          answer: result
            ? { kind: 'ok', result }
            : refusal
              ? { kind: 'refused', refusal }
              : // ANSWERED, WITH NOTHING TO SAY. `silent` exists so this ends: leaving `checked`
                // unset would strand the block on "asking the server…" for ever, which is what a
                // swallowed error looks like from the player's side (src/lib/db/README §1). It
                // prints nothing, because there is nothing true to print.
                { kind: 'silent' },
        })
      })
    }, 250)
    return () => {
      alive = false
      clearTimeout(timer)
    }
  }, [asking, line, fleet, preview])

  const answer: Answer | null = !asking
    ? null
    : checked?.line === line
      ? checked.answer
      : { kind: 'asking' }

  if (sheLiesHere && fleet) {
    return (
      <p className={fineClass('mt-2')} data-testid="map-sail-here-none">
        {fleet.name} lies here.
      </p>
    )
  }

  // ── UNDER WAY: THE HELM (0037) ──────────────────────────────────────────────────────────────
  // The same tap, the same corner — the act is DIVERT because she is at sea. The server settles
  // her, truncates the passage at the far node of the leg she is on (authored water, never a line
  // of our own), and queues the onward SAIL through the one parser. The refusal, when there is
  // one, is the server's sentence — this block invents no legality of its own, same as the
  // preview flow below it.
  if (underWay && fleet) {
    if (boundHere) {
      return (
        <p className={fineClass('mt-2')} data-testid="map-divert-bound">
          {fleet.name} is already bound here.
        </p>
      )
    }
    const portId = portByCode[portCode]?.id ?? null
    const shown = helm?.code === portCode ? helm : null
    return (
      <div className="mt-2 space-y-1.5" data-testid="map-divert">
        <Button
          variant="primary"
          className="w-full justify-center"
          data-testid="map-divert-button"
          onClick={() => {
            if (!portId || shown?.state === 'busy') return
            setHelm({ code: portCode, state: 'busy', refusal: null })
            void divert(fleet.id, portId).then((okay) => {
              setHelm({
                code: portCode,
                state: okay ? 'turned' : 'refused',
                refusal: okay ? null : useWorld.getState().refusal,
              })
            })
          }}
        >
          {`Divert ${fleet.name} here`}
        </Button>
        {shown === null && (
          <p className={fineClass()} data-testid="map-divert-note">
            She is at sea — she finishes the water she is on, turns at the next port, and makes
            for {portName}.
          </p>
        )}
        {shown?.state === 'busy' && (
          <p className={fineClass()} data-testid="map-divert-busy">
            putting the helm over…
          </p>
        )}
        {shown?.state === 'turned' && (
          <p className={fineClass()} data-testid="map-divert-turned">
            Helm answered — she turns at the next port, then makes for {portName}.
          </p>
        )}
        {shown?.state === 'refused' && shown.refusal && (
          <div className="space-y-1" data-testid="map-divert-refusal">
            <Badge tone="danger">{shown.refusal.code}</Badge>
            <p className="text-[11px] leading-snug text-ink">{shown.refusal.sentence}</p>
          </div>
        )}
      </div>
    )
  }

  return (
    <div className="mt-2 space-y-1.5" data-testid="map-sail-here">
      {/* THE ACT. `w-full` and the design system's own 44 px touch floor; the label names the hull
          so "which of my ships" is answered where the decision is made, not two screens away. */}
      <Button
        variant="primary"
        className="w-full justify-center"
        onClick={() => onSail(fleet?.id ?? null, args)}
        data-testid="map-sail-button"
      >
        {fleet ? `Sail ${fleet.name} here` : `Sail to ${portName}`}
      </Button>

      {!fleet && (
        <p className={fineClass()} data-testid="map-sail-no-fleet">
          No fleet chosen — Command will ask which.
        </p>
      )}

      {/* "checking the passage…", not "asking the server…" — the player is not talking to a
          server, they are asking whether she may sail (the plain-words sweep, 2026-08-23). */}
      {answer?.kind === 'asking' && (
        <p className={fineClass()} data-testid="map-sail-asking">
          checking the passage…
        </p>
      )}

      {/* WHAT IT WOULD BE — the SERVER's own sailed miles and voyage-days, read once for the whole
          app in `domain/order/estimate.ts`. Never a straight line across this sheet: Lisbon to
          Cádiz is 248 nm round Cape St Vincent and 188 nm as the crow flies, and the crow is not
          carrying the cargo.

          A fleet AT SEA gets no estimate, because `cmd.preview` does not run the verb for her —
          the order would WAIT in her queue and be priced on arrival. Saying so is the honest
          alternative to printing nothing; the composer's own longer wording is on the tab this
          button leads to. */}
      {answer?.kind === 'ok' &&
        (answer.result.queued ? (
          <p className={fineClass()} data-testid="map-sail-queued">
            She is at sea — this would wait in her queue.
          </p>
        ) : (
          <Passage result={answer.result} />
        ))}

      {/* WHY SHE MAY NOT — the sentence `cmd.issue` would have raised, in the player's words, right
          beside the thing she cannot do. Never a silent grey-out (docs/UI_DIRECTION.md §4 rule 5).
          The fixes are NOT rendered here: they are real orders, and tapping one loads the composer,
          which is on the tab this button already goes to. */}
      {answer?.kind === 'refused' && (
        <div className="space-y-1" data-testid="map-sail-refusal">
          <Badge tone="danger">{answer.refusal.code}</Badge>
          <p className="text-[11px] leading-snug text-ink">{answer.refusal.sentence}</p>
        </div>
      )}
    </div>
  )
}

/** The two figures a SAIL estimate carries. Same reading as the composer's readout, different
 *  chrome: a corner panel on a 390 px chart has room for the passage, not for a table. */
function Passage({ result }: { result: PreviewResult }) {
  const { nm, days } = sailEstimate(result.estimate)
  if (nm === null && days === null) return null
  return (
    <p className="font-mono text-sm text-ink" data-testid="map-sail-passage">
      {[nm === null ? null : formatNm(nm), days === null ? null : formatVoyageDays(days)]
        .filter(Boolean)
        .join(' · ')}
    </p>
  )
}
