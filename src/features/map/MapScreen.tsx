import { useCallback, useMemo, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { fineClass, Notice, overlaySlotClass } from '../../components/ui'
import { formatRealShort } from '../../lib/format'
import { unproject, type Point, type ViewBox } from '../../lib/geo'
import type { FleetView, Refusal, SnapshotConfig, SnapshotPort, VerbSpec } from '../../lib/rpc'
import type { SeaNav } from '../../lib/sea'
import { snapSeaPoint } from '../../domain/passage'
import { useShellState } from '../../app/shellState'
import { useWorld } from '../../live/worldStore'
// THE HAND-OFF SEAM — `domain/order`'s draft, which is the SAME one FLEETS, PORT and MARKET
// already write into. Nothing new was built to carry an order off this screen; see the header.
import { useCommandDraft } from '../../domain/order'
// THE CHART IS A SECTION OF ITS OWN (src/chart), and no longer this tab's property. Every module
// below was a file in this folder until 2026-08-23; they moved so the Command tab could draw the
// same chart on SAIL without copying a layer across a boundary — the silent copy docs/SECTIONS.md
// warns a boundary produces. This screen's COMPOSITION did not change; only these paths did, and
// the seven-line paint order became `ChartCanvas` so there is one of it rather than two.
import {
  buildChartModel,
  CHART_CAPTION,
  ChartCanvas,
  COMPACT_WIDTH_PX,
  GLYPH,
  hitTest,
  mapFleetsOf,
  mapPortsOf,
  Minimap,
  minTierForSpan,
  openingBounds,
  toggleSelection,
  useChartSurface,
  useCoastline,
  ViewControls,
  visiblePorts,
  type MapSelection,
} from '../../chart'
import { DetailPanel } from './DetailPanel'
import { FleetsPanel } from './FleetsPanel'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// MAP — YOU CAN ACT FROM IT, AND IT STILL COMPOSES NOTHING.
//
// ── WHAT THIS BLOCK USED TO SAY, AND WHY IT IS GONE (2026-08-23) ───────────────────────────────
// It was headed *"MAP — READ-ONLY, BY DESIGN AND FOREVER"* and it argued: *"Any future pull to
// 'just let them tap the port to sail there' adds a second place orders come from, and there is
// exactly one."* The caption at the foot of the chart said the same thing to the player, in four
// words: **view only · orders on Command**. That sentence is a screen confessing it is unfinished
// — you could see your fleet lying in Lisbon and 214 harbours around her, and you could not do a
// single thing from any of them; you had to remember the name, leave, and find it in a list.
//
// **The premise was wrong, not the conclusion.** The thing worth protecting is that there is ONE
// composer, ONE grammar, ONE judge of legality and ONE issue path — not that the map is a
// picture. Tapping a harbour here does not compose an order: the SEND FLEET flow (2026-08-24, the
// owner's own spelling: *"press send fleet, then it will unfold to my fleets … then i will press
// and it will send, without going to another screen"*) unfolds the fleets, their verdicts and the
// standing-order step beneath the tapped place, and sends through the same `worldStore.issue`
// Command's button calls. The old paragraph mistook the transport for the authority; the only
// hand-off left is a refusal's FIX that genuinely needs composing.
//
// So the rule that survives, in the form that is actually load-bearing:
//
//   **NOTHING IN `features/map` MAY PICK AN ARGUMENT, BOUND A QUANTITY, OR JUDGE AN ORDER.**
//   There is no picker on this screen, no stepper, and no `if (endurance < …)`. The one action
//   asks `cmd.preview()` — the real verb, run and rolled back — and prints what it answered,
//   refusal included. See ./SailHere.tsx, which is where all of that lives.
//
// ── THE SEAM, AND THE THREE THAT WERE REJECTED ─────────────────────────────────────────────────
// `docs/SECTIONS.md` forbids a screen importing another screen, so the map cannot reach into
// Command. The honest mechanism is a HAND-OFF, and this repo already had exactly one:
// `domain/order`'s draft — *"the ONE order being composed right now"* — written by FLEETS, PORT and
// MARKET through `handOff(intent)` and followed by `navigate('/command')`. The map is the fourth
// caller of a seam with three; nothing new carries an order off this screen.
//
// Rejected, each for the same reason — it would be a SECOND place a pending order lives:
//   · a field of its own on `live/worldStore` — two drafts, and the store is the world, not the
//     order being made;
//   · router state (`navigate('/command', { state })`) — invisible to the draft's session
//     persistence, so a reload would lose an order the composer would otherwise still hold;
//   · a search param (`?verb=SAIL&dest=CAD`) — the URL becomes a second authority for the draft
//     AND needs parsing on arrival, which is a second parser in a game whose whole point is that
//     there is one.
//
// ── WHERE THE PICTURE COMES FROM ───────────────────────────────────────────────────────────────
// The live world, and nowhere else (src/live/worldStore.ts):
//   snapshot.ports  214 real harbours with Wikidata coordinates and a `size_tier`
//   world.fleets    your fleets — and for one at sea, `voyage.position`, the closed form of §D.2
//   snapshot.config the time compression printed in the caption, rather than a number typed here
// ./liveWorld.ts is the only module that has seen the wire format. The stub it replaced
// (sampleVoyages.ts: twelve invented ports, four invented fleets) is deleted.
//
// ── NOTHING ON THIS SCREEN MOVES BY ITSELF ─────────────────────────────────────────────────────
// The position is the SERVER's, copied. There is no client clock driving a glyph, no per-frame
// re-derivation, no animation state — the old ./voyage.ts and its rAF clock are deleted, because a
// second implementation of the movement rule on this side of the wire is exactly what the live
// store's third rule forbids. A read is the catch-up, so the picture changes when the world is read
// again, and the caption says how long ago that was rather than pretending to be live.
// The ONE clock-dependent thing left is the wording of a countdown, against the server's own `eta`.
//
// ── WHAT IS ON THIS SCREEN, AND WHAT IS NOT ────────────────────────────────────────────────────
//   drawn   one pale coastline · the sea lanes, close in only · three glyphs (port, fleet,
//           destination) · a dotted track for the CURRENT leg · two corner panels · a caption
//   absent  OTHER PLAYERS. §E.5: drawing rivals would make the chart a targeting surface, and
//           there is no PvP (§J.2). No prop on any layer here can carry one.
//   absent  the planned route beyond the current leg — the server does not serve it (README §4.8),
//           so the destination is RINGED and no line is drawn to it. The chart never invents water.
//   absent  every control that is not pan, zoom, find, fold, dismiss — or the ONE hand-off.
//
// ── EVERY CONTROL IS ANCHORED TO THE GLASS, NEVER TO A COORDINATE ──────────────────────────────
// `docs/CORE_REUSE.md` §1.5: an action may never live in a region that can scroll or clip it. A
// chart pans and zooms, so an action drawn at a map coordinate is an action the player can send off
// the screen — that is the same defect as a button in a capped rail, reached by a different route.
// The `Sail here` button is therefore in the CORNER PANEL, inside the chrome layer, which is
// positioned against the chart box and does not move when the world under it does. `ChartCanvas`
// still produces exactly one value on a tap: a selection.
//
// ── 214 PORTS ON ONE SHEET ─────────────────────────────────────────────────────────────────────
// Three rules, all keyed on one column and one number:
//   1. the zoom sets a `size_tier` floor (PORT_TIER_BANDS) — the world shows the 35 great ports,
//      a sea adds the 79 middling, a coast adds all 100 small ones. YOUR ports are always drawn.
//   2. the mark is scaled by the tier (portMarkScale), so the hierarchy is visible, not implied.
//   3. names are planned as a SET over the visible ports only, dropped rather than overprinted,
//      and ranked by role first and tier second (./labels.ts).
//
// ── KEYBOARD AND SCREEN READERS ────────────────────────────────────────────────────────────────
// The chart itself is `role="img"` with a description, and it holds NO focusable elements. That is
// a decision, not an omission: dozens of invisible tab stops on a picture is worse than none, and
// everything the chart says is also said in the panels — the fleet list names every fleet, where
// it is and when it arrives, as ordinary keyboard-reachable buttons, and selecting one there fills
// the same detail panel a tap does. Nothing on this screen is reachable ONLY by pointer.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

export function MapScreen() {
  const phase = useWorld((s) => s.phase)
  const fatal = useWorld((s) => s.fatal)
  const snapshot = useWorld((s) => s.snapshot)
  const seaNav = useWorld((s) => s.seaNav)
  const fleets = useWorld((s) => s.fleets)
  const readAt = useWorld((s) => s.readAt)

  // A FAILURE IS RENDERED, NEVER SPUN ON. The refusal arrives with a code and a sentence a player
  // can read (DESIGN §F.5); printing it here is the whole handling.
  if (phase === 'failed') return <ChartMessage refusal={fatal} />
  // Opening: one quiet line on the chart's own sea, so the tab does not flash a different surface
  // before settling. Never an endless spinner — the store's phase always resolves.
  if (phase !== 'ready' || !snapshot || !seaNav) return <ChartMessage refusal={null} />

  // The chart mounts ONLY with the world in hand. That is what lets it freeze its opening frame at
  // its own mount (see below) on real fleets rather than on an empty model.
  return (
    <Chart
      ports={snapshot.ports}
      seaNav={seaNav}
      config={snapshot.config}
      // THE SERVER'S OWN GRAMMAR, handed down so the one action can be composed by the one
      // composer. Nothing in this folder lists a verb.
      verbs={snapshot.verbs}
      fleets={fleets}
      readAt={readAt}
    />
  )
}

/** The chart's sea with one line on it: opening, or the reason it could not open. */
function ChartMessage({ refusal }: { refusal: Refusal | null }) {
  return (
    <div
      className="bv-sea flex h-full w-full items-center justify-center p-6"
      data-testid="map-chart"
    >
      {refusal ? (
        <Notice tone="danger" className="max-w-sm" data-testid="map-fatal">
          <span className="block font-mono text-[10px] uppercase tracking-wider">{refusal.code}</span>
          {refusal.sentence}
        </Notice>
      ) : (
        <p className={fineClass()} data-testid="map-loading">
          opening the chart…
        </p>
      )}
    </div>
  )
}

function Chart({
  ports: snapshotPorts,
  seaNav,
  config,
  verbs,
  fleets: fleetViews,
  readAt,
}: {
  ports: readonly SnapshotPort[]
  /** The served navigable-water grid — the tap-on-open-water snap reads it (0039). */
  seaNav: SeaNav
  config: SnapshotConfig
  verbs: readonly VerbSpec[]
  fleets: readonly FleetView[]
  readAt: number | null
}) {
  // THE ONE CLOCK (src/app/shellState.ts). It ticks a countdown's wording and nothing else on this
  // screen: no glyph, no track and no frame is a function of it.
  const { nowMs } = useShellState()
  const navigate = useNavigate()

  // ── WHICH HULL IS IN HAND ────────────────────────────────────────────────────────────────────
  // `domain/order`'s draft owns that, app-wide, and has since the day it was written: *"The
  // selected fleet lives here too, because a short order carries no fleet."* The Command tab's
  // fleet strip sets it; MARKET and PORT read it. Selecting a fleet on the chart or in the list
  // (or in the send flow's own fleet step) also selects her for the composer, so Command opens on
  // her. Selectors, not the store (worldStore.ts rule 4 — a zustand action is a stable reference).
  const selectFleet = useCommandDraft((s) => s.selectFleet)
  const handOff = useCommandDraft((s) => s.handOff)

  // THE HAND-OFF, in the two lines every other screen uses (FleetsScreen.tsx:104,
  // PortScreen.tsx:151, MarketScreen.tsx:235) — and since 2026-08-24 it fires ONLY for a
  // refusal's FIX that genuinely needs composing (the owner: *"without going to another screen or
  // creating a new screen"* — the send itself completes on this screen, in SendFleet). The map
  // still composes nothing either way.
  const compose = useCallback(
    (intent: Parameters<typeof handOff>[0]) => {
      handOff(intent)
      navigate('/command')
    },
    [handOff, navigate],
  )

  const ports = useMemo(() => mapPortsOf(snapshotPorts), [snapshotPorts])
  const portsByCode = useMemo(() => new Map(ports.map((p) => [p.code, p])), [ports])
  const fleets = useMemo(() => mapFleetsOf(fleetViews), [fleetViews])
  // 0075 — THE MAP TAB IS THE ONE CALLER THAT PASSES A CLOCK, and this is where the marker stops
  // teleporting. `nowMs` ticks once a second in the shell, so the model is rebuilt at that rate
  // and a fleet at sea is drawn a little further along the leg the server put her on rather than
  // standing still for the whole three seconds between reads. `./drift.ts` carries the law that
  // makes this a finer reading of the server's answer and not a second one; it can never place her
  // past the vertex the next read will hand back.
  const model = useMemo(
    () => buildChartModel(fleets, ports, [], { nowMs, readAtMs: readAt }),
    [fleets, ports, nowMs, readAt],
  )

  const [selection, setSelection] = useState<MapSelection>(null)

  // THE OPENING VIEW frames WHAT YOU HAVE — your fleets and the ports they are using — not the 214
  // harbours of the world; and how much of it depends on the shape of the glass (openingBounds
  // carries the measured arithmetic, and the floor that stops a lone docked fleet opening on a
  // 1.5° harbour approach).
  //
  // Taken from the model AT MOUNT, once. It has to be stable: it is the frame the "fit" control
  // returns to, and a bounds that moved with the fleets would re-frame the chart under the player
  // every time the world was read.
  const [openingModel] = useState(() => model)
  const frameBounds = useCallback(
    (aspect: number) => openingBounds(openingModel.focusPoints, openingModel.motionPoints, ports, aspect),
    [openingModel, ports],
  )
  const chartRef = useRef<HTMLDivElement>(null)

  // THE ONLY THING A TAP ON THE CHART DOES. The nearest glyph within `GLYPH.hitRadius` wins
  // (./hitTest.ts explains why that is one function and not a touch circle per glyph); tapping the
  // same thing again, or tapping open water, clears the selection. The surface hands over the
  // scale AND the viewBox at the moment of the tap, so the reach is the same number of SCREEN
  // pixels at every zoom and the ports it tests are exactly the ports that were drawn — the same
  // `visiblePorts` rule, applied to the same box, with no second idea of what is on the sheet.
  //
  // The reach is not typed here and never was: src/chart/glyphs.ts derives it, from the touch
  // floor and the size of the thing actually drawn, and carries the browser measurements that say
  // why it is 38 px rather than 22 (a tap on a harbour's NAME used to open the open sea beside it).
  //
  // A TAP STILL PRODUCES EXACTLY ONE VALUE — a selection. `hitTest` returns a NAME, never a verb
  // (tests/map.voyage.spec.ts asserts the shape), and there is still no second callback on this
  // surface. What changed on 2026-08-23 is what the SCREEN does with a selection that names a
  // fleet: it points the composer's draft at her too, because "which hull is in hand" has one
  // authority and this screen reads it (see `acting` above). That is a selection, not an order.
  const onTap = useCallback(
    (at: Point, unitsPerPx: number, view: ViewBox) => {
      const tappable = visiblePorts(ports, model.portRoles, view, minTierForSpan(view.width))
      const hit = hitTest(model, tappable, at, GLYPH.hitRadius * unitsPerPx)
      if (hit?.kind === 'fleet') selectFleet(hit.id)
      if (hit) {
        setSelection((current) => toggleSelection(current, hit))
        return
      }
      // 0039 — THE PINPOINT: a tap on open water SELECTS that water (the owner: "in map, i should
      // be able to pinpoint anywhere in the ocean to make a fleet move"). The point is snapped to
      // the nearest sailable cell, so what the panel offers is water by construction; a tap deep
      // inland still clears the selection, which keeps the dismiss gesture every map has.
      const sea = snapSeaPoint(seaNav, unproject(at))
      setSelection(sea ? { kind: 'sea', at: sea } : null)
    },
    [model, ports, selectFleet, seaNav],
  )

  const surface = useChartSurface(chartRef, frameBounds, onTap)
  const box = surface.viewBox

  const coastline = useCoastline()

  // A phone is not a small desktop. Below `sm` the chart is ~390 px wide and a panel that opens by
  // default eats most of it, so the fleet list starts folded to its header chip there and open at
  // desktop widths (defect 3). `surface.width` is 0 until the box is measured, which is why the
  // panels wait for it — Collapsible reads `defaultOpen` once, at mount, so it must be right then.
  const compact = surface.width > 0 && surface.width < COMPACT_WIDTH_PX

  return (
    <div
      ref={chartRef}
      {...surface.handlers}
      // `surface.touchClass` is `touch-none` on this full-tab surface — every touch goes to the
      // pan/zoom handler, none to a page scroller. The class comes from the hook rather than being
      // typed here, because the gesture posture and its `touch-action` are ONE fact and the hook
      // owns it (useChartSurface's header; SmallChart is the other posture).
      // `select-none` stops a drag across the chart highlighting the labels.
      //
      // `bv-sea` IS KEPT DELIBERATELY, though the chart now paints its own sea as the first mark
      // on the sheet (2026-08-23). It is not redundant: `ChartCanvas` mounts only once `box` has
      // been measured (`{box && …}` below), so for the frames before that this class is the only
      // thing painting, and dropping it would flash the app's background where the sea will be.
      // `ChartMessage` uses it for the same reason.
      className={`bv-sea relative h-full w-full ${surface.touchClass} select-none overflow-hidden`}
      data-testid="map-chart"
    >
      {/* THE PICTURE. Which ports are drawn, which lanes, which names and in what paint order are
          `ChartCanvas`'s to decide (src/chart/ChartCanvas.tsx) — they were forty lines here until
          the SAIL composer became the chart's second caller, and two copies of the paint order can
          disagree. The tap above asks `visiblePorts` the same question with the same box, which is
          what keeps "what you can touch" and "what you can see" the same list. */}
      {box && (
        <ChartCanvas
          model={model}
          ports={ports}
          box={box}
          unitsPerPx={surface.unitsPerPx}
          coastlineD={coastline.data?.d ?? ''}
          selection={selection}
          // WHAT IS SITTING ON TOP OF THE SHEET (2026-08-23, from the chart side). The label
          // planner drops a name rather than overprint another name — but it could not see this
          // screen's own opaque chrome, so at 390px `Saint-Malo` rendered as `Sain`, `Nantes` as a
          // bare `s`, and `Bristol` not at all, all three under the zoom column, with the chart
          // believing it had printed them. The boxes are measured off the `CHART_CHROME` marker
          // the gesture handlers already respect, so every panel here is covered by the ONE thing
          // this screen hands back — including the port card the new tap-a-port flow opens, which
          // is a `MapPanel` and therefore carries the marker already. No coordinate, scale or
          // viewBox crosses this line; `ChartCanvas` converts.
          keepOut={surface.chromeBoxes}
          ariaLabel="Chart of the world's harbours and the sea lanes between them, showing your fleets"
          className="absolute inset-0 h-full w-full"
        />
      )}

      {/* ── THE CHROME LAYER ─────────────────────────────────────────────────────────────────
          EVERY corner panel and control on this chart lives inside this one box, and the box stops
          `CHART_CAPTION.clearClass` short of the bottom edge — exactly the height the caption bar
          below occupies. That is the whole of "clear the caption", stated ONCE, in the layer that
          owns the corners; it replaces the hand-tuned `bottom-11` the detail panel used to carry
          and the differently-hand-tuned `bottom-9` the coastline note carried for the same reason.
          Panels can now simply say which corner they are in (OVERLAY_SLOTS).

          Pointer-transparent itself, so it cannot swallow a pan gesture over open water; every
          child that is meant to be pressed turns pointer events back on for itself. */}
      <div
        className={`pointer-events-none absolute inset-x-0 top-0 z-10 ${CHART_CAPTION.clearClass}`}
      >
        {/* PANEL ONE — top-left. Held back until the surface has been measured, so it mounts
            knowing whether it is on a phone (see `compact`). */}
        {surface.width > 0 && (
          <FleetsPanel
            model={model}
            portsByCode={portsByCode}
            selection={selection}
            nowMs={nowMs}
            compact={compact}
            // Selecting from the LIST also brings the chart to the fleet. The opening frame holds
            // what is moving, which on a phone can leave a fleet lying in a far-off port off the
            // glass; this is how you get to it, and it is still only a view change.
            //
            // …and it points the composer's draft at her, exactly as tapping her glyph does
            // (`onTap` above). One authority for "which hull is in hand", two ways to reach it.
            onSelect={(id) => {
              selectFleet(id)
              setSelection((current) => toggleSelection(current, { kind: 'fleet', id }))
              const target = model.fleets.find((f) => f.fleet.id === id)
              if (target) surface.centreOn(target.at)
            }}
          />
        )}

        {/* PANEL TWO — bottom-right, and only when something is selected. It carries the screen's
            ONE act when that something is a place; see ./DetailPanel.tsx and ./SendFleet.tsx. */}
        <DetailPanel
          model={model}
          portsByCode={portsByCode}
          selection={selection}
          nowMs={nowMs}
          compact={compact}
          verbs={verbs}
          onCompose={compose}
          onDismiss={() => setSelection(null)}
        />

        {/* THE VIEW CONTROLS — the complete set, and since SmallChart grew gestures they are ONE
            component with two callers (src/chart/ViewControls.tsx, which carries the corner-slot
            and no-jargon reasoning that used to live here). "find" returns to the opening frame,
            which `openingBounds` builds around what you HAVE — your fleets and the harbours they
            are using — which is why this surface's aria sentence names them. */}
        <ViewControls
          surface={surface}
          findAriaLabel="Find your fleets"
          findTestId="map-find"
          testId="map-view-controls"
        />

      {/* THE MINIMAP — the whole world, always, with every fleet on it and the window this chart
          is currently looking through (the owner, 2026-08-23: "a small miniturized map at the
          corner of the map, that shows where my fleets are in color + symbol"). It fills the one
          free corner; everything it draws and every reason it is shaped the way it is lives in
          src/chart/Minimap.tsx. A tap on it is `centreOn` — the same one camera move the fleet
          list uses, so nothing appears, vanishes or resizes (OWNER_REQUESTS row 32). Being
          CHART_CHROME it is measured into `keepOut` above, so no harbour's name prints under it.

          The coastline note shares the corner: a missing backdrop is worth one quiet line, never
          a crash — the chart (and the minimap) still work without it. It used to carry its own
          `bottom-9`, a second guess at the caption clearance the layer above now makes for
          everything in it. */}
      <div className={`absolute ${overlaySlotClass('bottom-left')} flex flex-col items-start gap-1`}>
        {coastline.error && (
          <p className="font-mono text-[10px] text-ink-faint">coastline unavailable</p>
        )}
        <Minimap
          model={model}
          ports={ports}
          coastlineD={coastline.data?.d ?? ''}
          viewport={box}
          onJump={surface.centreOn}
          ariaLabel="The whole world, your fleets marked on it, and the part of it this chart is showing. Tap a place to look there."
        />
      </div>
      </div>

      {/* THE PERMANENT CAPTION. TWO facts the player should never have to work out or be told
          twice: the time scale (§D.3 asks for it here, always — and it is the SERVER's
          `time_compression`, not a number typed into this file), and WHEN the picture was read.
          That last one is the honest half of "the position is the server's": the chart is a
          reading, and a reading has an age.

          THERE WERE THREE. The middle one read **view only · orders on Command**, and it is
          deleted with the behaviour it described (2026-08-23) — a caption that has become false is
          worse than no caption, and this one had become false in the same commit that gave a
          tapped harbour a `Sail here`. The `data-testid="map-is-a-view"` went with the sentence:
          a hook named after a claim the screen no longer makes is the same lie, one layer down.

          Pointer-transparent, so it can never swallow a pan gesture near the bottom edge. Its
          height is `CHART_CAPTION.barClass` rather than whatever its padding happens to make it,
          because the chrome layer above is inset by exactly that much. One fact, one place. */}
      <div
        className={`pointer-events-none absolute inset-x-0 bottom-0 z-10 flex items-center gap-2 bg-app/70 px-3 backdrop-blur ${CHART_CAPTION.barClass}`}
        data-testid="map-caption"
      >
        <span className="shrink-0 font-mono text-[10px] text-ink-faint">
          1 min = {config.time_compression / 60} h sail
        </span>
        {readAt !== null && (
          <span className="ml-auto shrink-0 font-mono text-[10px] text-ink-faint" data-testid="map-read-age">
            read {formatRealShort(nowMs - readAt)} ago
          </span>
        )}
      </div>

    </div>
  )
}
