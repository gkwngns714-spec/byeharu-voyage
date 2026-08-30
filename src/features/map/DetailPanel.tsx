import { formatInt, formatNm, formatRealShort } from '../../lib/format'
import type { VerbSpec } from '../../lib/rpc'
import type { CommandIntent } from '../../domain/order'
import { fleetsAtPort, fleetsBoundFor, type ChartModel, type MapPort, type MapSelection } from '../../chart'
import { pointLabel } from '../../domain/passage'
import { MapPanel } from './MapPanel'
import { SendFleet } from './SendFleet'
import { WatersAhead } from './WatersAhead'

// PANEL TWO, BOTTOM-RIGHT — the detail of whatever is selected, and the ONE place you act from.
// DESIGN §E.5's "selected fleet detail", widened by one case: a port, when a port is what was
// tapped.
//
// ONE PANEL FOR BOTH, and one `MapSelection` behind it, deliberately. A second floating card for
// ports would be a third panel (§E.5 allows two), it would have to be positioned somewhere, and
// two selections could then disagree about what the player is looking at. So: one selection, one
// detail, in one corner. Nothing is ever drawn over the middle of the chart.
//
// EVERY NUMBER HERE IS THE SERVER'S. `sailed / total` is `voyage.position.nm_done` against
// `total_nm` — SAILED miles, so a passage that rounds a cape reads the distance it really is — and
// the countdown is `voyage.eta` against the shell clock. The map computes none of it.
//
// ── IT USED TO SAY "IT IS READ-ONLY, ALL OF IT" (deleted 2026-08-23) ───────────────────────────
// The paragraph that stood here read: *"There is no 'sail here', no 'set course', no button that
// starts an order half-composed. The panel ends with where orders actually come from."* Every word
// of it was true, and it was the defect — the owner's verdict on this tab was that a map you
// cannot act from is a picture, and the caption at the foot of the chart said so out loud.
//
// A selected PORT (or spot of open sea) now carries exactly one act, `SendFleet` — the owner's
// unfolding flow, completed ON the map (2026-08-24). The distinction the old paragraph was
// reaching for survives whole, and it is the important half: **this panel still composes
// nothing.** Every verdict it prints is the server's, every send goes down the one issue path,
// and there is still no argument picker on this screen, no quantity control, and no legality
// check. See SendFleet.tsx for the flow and its rules.

/**
 * WHAT TO DO WITH THE SHIP YOU JUST TAPPED — the one sentence that was missing.
 *
 * ── WHY THIS IS A SENTENCE AND NOT A SEND BUTTON ───────────────────────────────────────────────
 * The owner, playing production on 2026-08-31: *"i can't send a fleet in map."* Driven in the
 * running game, the cause was not a broken control — it was NO control: tapping your own ship
 * opened a panel carrying her name, her state and her position, and nothing else. The two
 * branches below a fleet's (open sea, port) each end in `SendFleet`; the fleet's ended in a
 * `Line`. Pressing the ship you want to send is the first thing anybody tries, and it was a
 * silent dead end.
 *
 * The fix is NOT a second way to send, and that is the whole point. This screen sends
 * DESTINATION-FIRST — tap where she should go, then choose which fleet goes — and `SendFleet` is
 * the one authority for it (docs/NO_SPAGHETTI.md §7B: decide where a concept lives BEFORE the
 * second caller exists). A "send from the ship" button would need its own destination picker, its
 * own ratio control and its own issue path: a second mover on this screen, whose own header
 * records what four movers cost this project. So the panel does the only honest thing left — it
 * NAMES THE GESTURE, in the game's own words, and gets out of the way.
 *
 * Shown only when she can actually be sent (lying at a quay, or at anchor). A ship already under
 * way is not waiting for an instruction, and telling her captain to tap somewhere would be a
 * sentence the game will not honour — docs/UI_DIRECTION.md forbids printing one of those.
 */
function SendHint() {
  return (
    <p
      className="mt-1.5 border-t border-rule pt-1.5 font-mono text-[10px] leading-snug text-ink-faint"
      data-testid="map-send-hint"
    >
      Tap where she should go — a harbour, or any water.
    </p>
  )
}

/** One label/value line — the panel is a tiny table and nothing more. */
function Line({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-baseline justify-between gap-2 py-0.5">
      <span className="shrink-0 font-mono text-[10px] text-ink-faint">{label}</span>
      <span className="min-w-0 truncate text-right font-mono text-[11px] text-ink">{value}</span>
    </div>
  )
}

export function DetailPanel({
  model,
  portsByCode,
  selection,
  nowMs,
  compact,
  verbs,
  onCompose,
  onDismiss,
}: {
  model: ChartModel
  /** The WHOLE port table: the selected fleet's destination may be well off the glass. */
  portsByCode: ReadonlyMap<string, MapPort>
  selection: MapSelection
  nowMs: number
  compact: boolean
  /** The server's own verb grammar (`world.snapshot().verbs`). Nothing here lists verbs. */
  verbs: readonly VerbSpec[]
  /** The hand-off to the one composer — reached ONLY by a refusal's fix that needs composing
   *  (PROVISION first, …). The send itself completes on this screen (SendFleet). MapScreen owns
   *  the two lines, exactly as FleetsScreen, PortScreen and MarketScreen each do. */
  onCompose: (intent: CommandIntent) => void
  onDismiss: () => void
}) {
  if (!selection) return null

  const nameOf = (code: string) => portsByCode.get(code)?.name ?? code

  if (selection.kind === 'fleet') {
    const fleet = model.fleets.find((f) => f.fleet.id === selection.id)
    if (!fleet) return null

    return (
      <MapPanel
        slot="bottom-right"
        title="Fleet"
        compact={compact}
        onDismiss={onDismiss}
        storageKey="map.detail"
        // A FLEET AT SEA CARRIES THE WATERS AHEAD, so she needs the same width the port case
        // needed and for the same reason: the default compact column (`max-w-[55vw]`, ~214 px at
        // 390) was sized for four short label/value lines, and a sea's name beside a distance
        // wraps in it. The chart clips at its own edge, so panel HEIGHT is what must stay bounded
        // — and width is what buys height back. A docked fleet keeps the narrow column.
        widthClassName={
          fleet.voyage && fleet.voyage.waters.length > 0
            ? compact
              ? 'w-[74vw] max-w-[74vw]'
              : 'w-56 max-w-[45vw]'
            : undefined
        }
        testId="map-detail-panel"
      >
        <p className="mb-1 truncate font-serif text-sm text-ink">{fleet.fleet.name}</p>
        {fleet.dockedAtCode ? (
          <Line label="at" value={nameOf(fleet.dockedAtCode)} />
        ) : fleet.fleet.kind === 'anchored' ? (
          <Line label="at anchor" value={pointLabel(fleet.at)} />
        ) : (
          fleet.voyage && (
            <>
              {/* 0039: a destination is a port, or a pinpointed spot of open water. */}
              <Line
                label="to"
                value={
                  fleet.voyage.destinationCode
                    ? nameOf(fleet.voyage.destinationCode)
                    : fleet.voyage.destPoint
                      ? pointLabel(fleet.voyage.destPoint)
                      : '—'
                }
              />
              <Line
                label="sailed"
                value={`${formatInt(fleet.voyage.sailedNm)} / ${formatNm(fleet.voyage.totalNm)}`}
              />
              <Line label="arrives" value={formatRealShort(fleet.voyage.etaMs - nowMs)} />
              {/* 0055 — WHAT WATER IS STILL IN FRONT OF HER, and how far off it is. A list of
                  places, never a forecast; see ./WatersAhead.tsx. */}
              <WatersAhead waters={fleet.voyage.waters} />
            </>
          )
        )}
        {/* SHE IS WAITING FOR AN ORDER AND THE PANEL USED TO SAY NOTHING. See SendHint above for
            why this is a sentence rather than a second send path. The condition is the same one
            the two lines above test — lying at a quay, or at anchor — and NOT `!fleet.voyage`,
            which would also catch a fleet in the yard. */}
        {(fleet.dockedAtCode || fleet.fleet.kind === 'anchored') && <SendHint />}
      </MapPanel>
    )
  }

  // ── OPEN SEA (0039): the owner's pinpoint. The tapped spot arrives already SNAPPED to
  // sailable water (MapScreen), so what this panel offers to sail to is water by construction.
  // Same corner, same one act, same rules — a destination is a destination.
  if (selection.kind === 'sea') {
    return (
      <MapPanel
        slot="bottom-right"
        title="Open sea"
        compact={compact}
        onDismiss={onDismiss}
        storageKey="map.detail"
        widthClassName={compact ? 'w-[74vw] max-w-[74vw]' : 'w-56 max-w-[45vw]'}
        testId="map-detail-panel"
      >
        <p className="mb-1 truncate font-serif text-sm text-ink" data-testid="map-sea-label">
          {pointLabel(selection.at)}
        </p>
        <SendFleet dest={{ kind: 'sea', at: selection.at }} verbs={verbs} onCompose={onCompose} />
      </MapPanel>
    )
  }

  const port = portsByCode.get(selection.code)
  if (!port) return null

  const here = fleetsAtPort(model, port.code)
  const bound = fleetsBoundFor(model, port.code)

  return (
    <MapPanel
      slot="bottom-right"
      title="Port"
      compact={compact}
      onDismiss={onDismiss}
      storageKey="map.detail"
      // A PORT CARRIES AN ACTION, so this panel is wider than the fleet's on a phone. The compact
      // default (`max-w-[55vw]`, ~214 px at 390) was sized for four short label/value lines; a
      // refusal is a SENTENCE the server wrote, and squeezing it into a 214 px column turns a
      // readable reason into a ragged tower that pushes the button toward the top of the glass.
      // The chart div clips at its own edge, so panel HEIGHT is the thing that has to stay bounded
      // — and width is what buys height back.
      widthClassName={compact ? 'w-[74vw] max-w-[74vw]' : 'w-56 max-w-[45vw]'}
      testId="map-detail-panel"
    >
      <p className="mb-1 truncate font-serif text-sm text-ink">{port.name}</p>
      <Line label="in" value={port.country} />
      <Line
        label="yours here"
        value={here.length > 0 ? here.map((f) => f.fleet.name).join(', ') : 'none'}
      />
      {bound.length > 0 && <Line label="on passage" value={bound.map((f) => f.fleet.name).join(', ')} />}

      {/* THE ONE ACT ON THIS SCREEN. It composes nothing — see this file's header and SendFleet's. */}
      <SendFleet
        dest={{ kind: 'port', code: port.code, name: port.name }}
        verbs={verbs}
        onCompose={onCompose}
      />
    </MapPanel>
  )
}
