import { useEffect, useState } from 'react'
import { Badge, Button, fineClass } from '../../components/ui'
import { formatNm, formatVoyageDays } from '../../lib/format'
import type { LatLon } from '../../lib/geo'
import type { FleetView, PreviewResult, Refusal, VerbSpec } from '../../lib/rpc'
import { findVerb, orderText, sailEstimate } from '../../domain/order'
import { fleetNow, pointLabel, pointToken, proposeCourse, sailOrigin } from '../../domain/passage'
import { useWorld } from '../../live/worldStore'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// SAIL HERE — the map's one act, and it does not compose an order
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// THE OWNER, 2026-08-23: the Map tab's caption read *"view only · orders on Command"*, which is a
// screen confessing it is unfinished — you could see your fleet, and 214 harbours, and act from
// none of them. It is gone, and this block is what replaced it. 0039 widened its subject once:
// the owner's *"i should be able to pinpoint anywhere in the ocean to make a fleet move"* means
// the destination may now be a bare point of open water as well as a harbour — same block, same
// rules, one more kind of place.
//
// ── WHAT THIS IS NOT, AND THAT IS THE WHOLE DESIGN ─────────────────────────────────────────────
// It is NOT a second order composer. There is exactly one of those (`features/command`), one
// grammar (`cmd.verb_schema()`), and one judge of legality (the server, through `cmd.preview()`).
// This block contains **no argument picker, no quantity control and no legality check** — the three
// things whose appearance here would mean the defect had been rebuilt. What it does is:
//
//   1. name ONE intent — "SAIL, to this place, with the fleet the draft has in hand";
//   2. ask the SERVER whether that exact line would be accepted, and print its answer;
//   3. hand the intent to `domain/order`'s draft and go to Command, where it is composed.
//
// Step 3 is the same seam FLEETS, PORT and MARKET already use — `handOff(intent)` then
// `navigate('/command')`. A water point rides the intent as `dest_point`, the same "lat,lon"
// token the order line will carry — one spelling, owned by `domain/passage`.
//
// ── THE COURSE RIDES THE PREVIEW (0039) ────────────────────────────────────────────────────────
// The server does not find paths; the client PROPOSES one and the server verifies and measures it
// (docs/NAVIGATION_PLAN.md §3). So the dry run here attaches the same proposal the composer will
// attach at issue — `domain/passage.proposeCourse`, the one pathfinder — and the figures printed
// are still the SERVER's: `cmd.preview` runs the real verb over the real course and rolls it
// back. Nothing here measures anything.
//
// ── AND WHY THE ANSWER IS `cmd.preview()` AND NOT A CHECK OF OUR OWN ───────────────────────────
// `voyage.sail_refusal()` is THE answer to "may she sail there?" — crew, flagship, draught, ice,
// endurance with the no-chandler round trip (0039) — and `cmd.do_sail` RAISES exactly what it
// returns. It is revoked from every client role, deliberately, so the only honest way to ask it
// from a browser is to run the verb and throw it away, which is what `cmd.preview()` is.
//
// NOTHING IS EVER GREYED OUT SILENTLY, AND THE BUTTON IS NEVER DISABLED — same rule the haggle
// block keeps. A refused SAIL still hands over, because Command renders the refusal's FIXES as
// tappable orders ("PROVISION first"), and the fix is the thing the player actually wants.
//
// ── THE REACH LAW ──────────────────────────────────────────────────────────────────────────────
// `docs/CORE_REUSE.md` §1.5: an action may never live in a region that can scroll or clip it. This
// block renders inside `MapPanel`'s content, anchored to a CORNER OF THE GLASS — chrome, not ink —
// so panning the chart cannot carry the button off the screen.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/** The place the act is about: a harbour, or a pinpointed spot of open water (0039). */
export type SailDest =
  | { readonly kind: 'port'; readonly code: string; readonly name: string }
  | { readonly kind: 'sea'; readonly at: LatLon }

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
  dest,
  verbs,
  onSail,
}: {
  /** The hull the order is for — `domain/order`'s draft is the one authority for which that is,
   *  and this screen READS it rather than keeping a second idea of it. Null when the house has
   *  chosen none yet, in which case the hand-off carries none and Command asks. */
  fleet: FleetView | null
  dest: SailDest
  /** The server's own grammar (`world.snapshot().verbs`). Nothing here lists verbs. */
  verbs: readonly VerbSpec[]
  onSail: (fleetId: string | null, args: Record<string, string>) => void
}) {
  const preview = useWorld((s) => s.preview)
  const divert = useWorld((s) => s.divert)
  const portByCode = useWorld((s) => s.portByCode)
  const seaNav = useWorld((s) => s.seaNav)
  // THE ANSWER, STAMPED WITH THE LINE IT IS ABOUT — keeping the answer rather than a status means
  // the state can never describe an order the player has already changed. Tapping the next place
  // puts this back to `asking` BY DERIVATION (below), so nothing has to be reset in an effect.
  const [checked, setChecked] = useState<{ line: string; answer: Answer } | null>(null)
  // THE HELM (0039), stamped with the place it is about — same derivation trick as `checked`.
  const [helm, setHelm] = useState<
    { key: string; state: 'busy' | 'turned' | 'refused'; refusal: Refusal | null } | null
  >(null)

  const destName = dest.kind === 'port' ? dest.name : pointLabel(dest.at)
  const destKey = dest.kind === 'port' ? dest.code : pointToken(dest.at)
  const target: LatLon | null =
    dest.kind === 'port'
      ? ((p) => (p ? { lat: p.lat, lon: p.lon } : null))(portByCode[dest.code])
      : dest.at

  // THE ONE INTENT, stated once. The preview below and the hand-off both read this object, which
  // is what makes them the same order rather than two orders that agree today. A water point is
  // the `dest_point` token — the same token the order line carries and the parser reads.
  const args: Record<string, string> =
    dest.kind === 'port' ? { dest: dest.code } : { dest_point: pointToken(dest.at) }
  const spec = findVerb(verbs, 'SAIL')
  const line = spec && fleet ? orderText(spec, args, fleet.name) : null

  // SHE IS LYING AT THIS VERY QUAY — one served field against the place that was tapped. A fleet
  // at sea and bound here keeps the button (the panel above already says she is on passage).
  const sheLiesHere = dest.kind === 'port' && fleet?.port === dest.code
  // UNDER WAY, the act changes (0039): the same tap is a DIVERT — she turns where she is — and
  // which act it is follows from where she is, exactly as the button's label says.
  const underWay = fleet !== null && fleet.voyage != null
  const boundHere =
    underWay &&
    (dest.kind === 'port'
      ? fleet?.voyage?.to === dest.code
      : fleet?.voyage?.dest_point != null &&
        pointToken({ lat: fleet.voyage.dest_point[0], lon: fleet.voyage.dest_point[1] }) === destKey)
  const asking = line !== null && fleet !== null && !sheLiesHere && !underWay

  // THE PROPOSAL (0039): the same course the composer will attach at issue, so the estimate the
  // server prints here is priced over the same water the order will sail. Computed on the pick
  // (worst measured search ~166 ms in Node; the browser figure is in the acceptance report).
  const origin = fleet && seaNav ? sailOrigin(fleet, portByCode) : null
  const course = asking && seaNav && origin && target ? proposeCourse(seaNav, origin, target) : null

  // THE DRY RUN, debounced — every preview is a real transaction on the server (it runs the verb
  // and rolls it back), and a player crossing a crowded coast selects several places on the way.
  useEffect(() => {
    if (!asking || !line || !fleet) return
    let alive = true
    const timer = setTimeout(() => {
      void preview(fleet.id, line, course).then((result) => {
        if (!alive) return
        const refusal = useWorld.getState().refusal
        setChecked({
          line,
          answer: result
            ? { kind: 'ok', result }
            : refusal
              ? { kind: 'refused', refusal }
              : { kind: 'silent' },
        })
      })
    }, 250)
    return () => {
      alive = false
      clearTimeout(timer)
    }
    // `course` is derived from the same inputs as `line`; listing it would re-run the effect on
    // every identity change of an equal array.
    // eslint-disable-next-line react-hooks/exhaustive-deps
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

  // ── UNDER WAY: THE HELM (0039) ──────────────────────────────────────────────────────────────
  // The same tap, the same corner — the act is DIVERT because she is at sea. The server settles
  // her, truncates the passage at her own position, and departs the onward course — proposed
  // here from where she is, bridged and VERIFIED as water server-side like every other course.
  // The refusal, when there is one, is the server's sentence.
  if (underWay && fleet) {
    if (boundHere) {
      return (
        <p className={fineClass('mt-2')} data-testid="map-divert-bound">
          {fleet.name} is already bound here.
        </p>
      )
    }
    const portId = dest.kind === 'port' ? (portByCode[dest.code]?.id ?? null) : null
    const shown = helm?.key === destKey ? helm : null
    return (
      <div className="mt-2 space-y-1.5" data-testid="map-divert">
        <Button
          variant="primary"
          className="w-full justify-center"
          data-testid="map-divert-button"
          onClick={() => {
            if (shown?.state === 'busy') return
            if (dest.kind === 'port' && !portId) return
            setHelm({ key: destKey, state: 'busy', refusal: null })
            void (async () => {
              // READ, THEN TURN. At 1 real second = 8 sim minutes she makes ~0.6 nm, so a course
              // proposed from a 30-second-old position starts ~15 nm behind her — and the
              // server's bridge from her TRUE position to it can clip a coast she has already
              // cleared (found in the acceptance drive: E_LAND on the bridge). A fresh read
              // shrinks the bridge to a mile or two, which the verifier's own allowance covers.
              await useWorld.getState().refresh()
              const fresh =
                useWorld.getState().fleets.find((f) => f.id === fleet.id) ?? fleet
              const now = seaNav ? fleetNow(fresh, portByCode) : null
              const turnCourse =
                seaNav && now && target ? proposeCourse(seaNav, now, target) : null
              const okay = await divert(
                fleet.id,
                portId,
                dest.kind === 'sea' ? { lat: dest.at.lat, lon: dest.at.lon } : null,
                turnCourse,
              )
              setHelm({
                key: destKey,
                state: okay ? 'turned' : 'refused',
                refusal: okay ? null : useWorld.getState().refusal,
              })
            })()
          }}
        >
          {`Divert ${fleet.name} here`}
        </Button>
        {shown === null && (
          <p className={fineClass()} data-testid="map-divert-note">
            She is at sea — she turns where she is and makes for {destName}.
          </p>
        )}
        {shown?.state === 'busy' && (
          <p className={fineClass()} data-testid="map-divert-busy">
            putting the helm over…
          </p>
        )}
        {shown?.state === 'turned' && (
          <p className={fineClass()} data-testid="map-divert-turned">
            Helm answered — she turns where she is and makes for {destName}.
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
        {fleet ? `Sail ${fleet.name} here` : `Sail to ${destName}`}
      </Button>

      {!fleet && (
        <p className={fineClass()} data-testid="map-sail-no-fleet">
          No fleet chosen — Command will ask which.
        </p>
      )}

      {answer?.kind === 'asking' && (
        <p className={fineClass()} data-testid="map-sail-asking">
          checking the passage…
        </p>
      )}

      {/* WHAT IT WOULD BE — the SERVER's own sailed miles and voyage-days over the proposed
          course, read once for the whole app in `domain/order/estimate.ts`. Never a straight line
          across this sheet. */}
      {answer?.kind === 'ok' &&
        (answer.result.queued ? (
          <p className={fineClass()} data-testid="map-sail-queued">
            She is at sea — this would wait in her queue.
          </p>
        ) : (
          <Passage result={answer.result} />
        ))}

      {/* WHY SHE MAY NOT — the sentence `cmd.issue` would have raised, right beside the thing she
          cannot do. Never a silent grey-out. The fixes are real orders and live on the tab this
          button already goes to. */}
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
