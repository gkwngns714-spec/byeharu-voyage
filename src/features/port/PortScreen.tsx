import { useEffect } from 'react'
import {
  Button,
  Icon,
  Note,
  Row,
  Segmented,
  Sheet,
  SheetSection,
  Skeleton,
} from '../../components/ui'
import { portNameOf, useWorld } from '../../live/worldStore'
import { usePortMarket } from '../../live/usePortMarket'
import type { WorldSnapshot } from '../../lib/rpc'
import { useCommandDraft } from '../../domain/order'
import { PortAcademy } from './PortAcademy'
import { PortField } from './PortField'
import { PortPrices } from './PortPrices'
import { PortTrade } from './PortTrade'
import { PortTown } from './PortTown'
import { QuayFair } from './PortFair'
import { buildingTier, hasBuilding } from '../../domain/port'
import { PortWarehouse } from './PortWarehouse'
import { PortInn } from './PortInn'
import { PortYard } from './PortYard'
import { PortWorkstation } from './PortWorkstation'
import { PortShipyard } from './PortShipyard'
import { PORT_FACES, usePortView } from './portView'
import { harbourCode, harbourPick, useHarbour } from '../../store/harbour'
import { fleetPortCode } from '../../domain/fleet'
import { WorldFailed, WorldLoading } from '../../live/WorldGate'

// PORT — E.3, redrawn to docs/UI_DIRECTION.md §6. Where you are, what is here, what you can do.
//
// ── WHAT THE HEADER WAS, AND WHY ALL OF IT WENT ────────────────────────────────────────────────
// §2 item 9, measured: eyebrow `HARBOUR`, serif `Port · Lisbon ⓘ`, subtitle `Portugal · latin
// culture · North Atlantic Ocean`, a `DRAFT 5` badge, the roads sentence, the "quay is quiet"
// sentence, a card header, SEVEN face tabs wrapping to two rows, then Buy/Sell tabs, a filter and
// a count line — before the first price. Every one of those is a fact ABOUT the place rather than
// a decision made in it:
//   · the country and the sea are on the map, and you sailed here;
//   · the culture decides exactly one thing — a good this quay refuses — and it says so THERE
//     (TradeTray.tsx), on the good it refused;
//   · draft decides exactly one thing — a hull too deep — and it says so THERE (PortYard.tsx);
//   · the roads sentence explains a track on the chart, and the chart is where it belongs;
//   · "nothing is on" is news about nothing (PortFair.tsx).
// What is left is the harbour's name, who of yours is lying in it, and the faces.
//
// ── EVERY VERB'S DOORWAY IS ON THE FACE OF THE BUILDING WHOSE ACT IT IS (2026-09-09) ──────────
// The owner: *"Buy and sell should be in port - market. Get it? they should be located accordingly
// at different locations - the command."* COMMAND's twelve-tile grid is gone; what it composed
// now composes here — BUY/SELL and PROVISION on the Trade face (the quay is the chandler), STORE
// and TAKE on Store, MAKE on Craft, BUILD on Yard, HIRE on the Inn, REPAIR at the Shipyard — and
// SAIL on the MAP. The sea-place view's "Sailing on" rows, which handed a SAIL to COMMAND, went
// with the composer they led to: a passage from an anchorage is ordered where every passage is,
// by tapping the harbour on the chart.
//
// ── MARKET FOLDED IN (2026-09-11, owner row 76 — docs/QUAY_LEDGER.md §6 slice 1) ──────────────
// MARKET read prices at a harbour you are not standing on with the same rows, tray and harbour
// choice as this screen (RESUME.md measured them drifting). It is gone: the port field stands
// under the faces, the Trade face is the ledger either way, and ONE fact decides what a cell opens
// — a fleet of yours ALONGSIDE the harbour on screen (`docked`, the one spelling) trades through
// the tray; nobody alongside reads through PortPrices. `null` in the harbour store follows her.
export function PortScreen() {
  // FIELDS, NOT THE STORE (worldStore.ts rule 4).
  const phase = useWorld((s) => s.phase)
  const fatal = useWorld((s) => s.fatal)
  const snapshot = useWorld((s) => s.snapshot)

  if (phase === 'failed') {
    return <WorldFailed eyebrow="Harbour" title="Port" refusal={fatal} />
  }
  if (phase !== 'ready' || !snapshot) {
    return <WorldLoading eyebrow="Harbour" title="Port" subtitle="Where you are, and what is here." panels={3} />
  }
  return <PortBody snapshot={snapshot} />
}

function PortBody({ snapshot }: { snapshot: WorldSnapshot }) {
  const fleets = useWorld((s) => s.fleets)
  const portByCode = useWorld((s) => s.portByCode)
  const draftFleetId = useCommandDraft((s) => s.fleetId)

  // WHICH HARBOUR — the ONE owner (src/store/harbour.ts); the MAP is its named next caller.
  // WHICH FACE — this screen's own chrome (portView.ts).
  const picked = useHarbour((s) => s.picked)
  const setPicked = useHarbour((s) => s.pick)
  const face = usePortView((s) => s.face)
  const setFace = usePortView((s) => s.turnTo)

  // THE DEFAULT IS WHERE THE HOUSE IS, AND A FLEET AT SEA IS SOMEWHERE. `harbourCode` is the ONE
  // spelling of pick-else-house-else-first-port. A pick the served world no longer names (session
  // storage outliving a world rebuild) is a stale byte, not a harbour: it falls through to the
  // house's own quay and is cleared, so the player is never stranded on "no ports".
  const stalePick = picked !== null && portByCode[picked] === undefined
  useEffect(() => {
    if (stalePick) setPicked(null)
  }, [stalePick, setPicked])
  const portCode = harbourCode(stalePick ? null : picked, fleets, snapshot.ports)
  const port = portCode ? (portByCode[portCode] ?? null) : null

  // The market is read per port and re-read on the world's beat (usePortMarket). Never for a SEA
  // PLACE (0036): open water keeps no book, and asking for one would cache an empty market that
  // looks exactly like a real market with nothing in it.
  const portId = port?.id ?? null
  const quay = usePortMarket(port?.kind === 'HARBOUR' ? portId : null)

  // THE ONE "ALONGSIDE HERE" TEST. Read-only ⇔ nobody is.
  const docked = port ? fleets.filter((f) => f.port === port.code) : []
  const acting = docked[0] ?? fleets.find((f) => f.id === draftFleetId) ?? fleets[0] ?? null
  // WHERE THE ACTING FLEET'S NEXT ORDER WOULD RUN — alongside, or the harbour she is bound for.
  const actingPortCode = acting ? fleetPortCode(acting) : null
  const actingIsHere = actingPortCode !== null && actingPortCode === port?.code

  if (!port) {
    return (
      <Sheet title="Port">
        <Note tone="warning">No ports loaded.</Note>
      </Sheet>
    )
  }

  // 0036: A SEA PLACE HAS NO SHORE, so it gets the anchorage view and none of the harbour faces.
  // The served `kind` decides — the screen never infers "no quay" from an empty market.
  if (port.kind === 'SEA_PLACE') {
    return (
      <Sheet title={port.name} data-testid="port">
        {port.approach && <Note tone="neutral">{port.approach}</Note>}
        <SheetSection heading="Anchored here">
          {docked.length === 0 ? (
            <Row label="None of your fleets are here." tone="muted" hairline={false} />
          ) : (
            docked.map((f, i) => (
              <Row key={f.id} label={f.name} value="anchored" hairline={i < docked.length - 1} />
            ))
          )}
        </SheetSection>
      </Sheet>
    )
  }

  // WHICH FACES THIS HARBOUR HAS, and which of them is up. A persisted face can outlive the port it
  // was chosen on, so the shown face is derived from what is OFFERED rather than trusted from
  // storage. 0067: a face that names a BUILDING is offered where that building stands — one rule,
  // read from the rows, and no line here changes for a seventh building.
  const offeredFaces = PORT_FACES.filter((f) => f.building === null || hasBuilding(port, f.building))
  const shownFace = offeredFaces.find((f) => f.id === face) ?? offeredFaces[0]

  return (
    <Sheet
      title={port.name}
      data-testid="port"
      /* WHO OF YOURS IS HERE — the one thing about the harbour that is about YOU, on the title's
         own line (§6's sketch: `Lisbon                ⛵ Gaivota`). Nothing when none of your
         hulls is alongside: an empty label is not a state. */
      trailing={
        docked.length > 0 ? (
          <span className="flex items-center gap-2 text-t-label">
            <Icon name="ship" size={20} />
            {docked.length === 1 ? docked[0].name : `${docked.length} fleets`}
          </span>
        ) : undefined
      }
    >
      {/* ONE ROW, AND IT SCROLLS. Seven labels wrapped to two rows at 390px, which reads as a menu
          rather than a face (§2 item 9). `Segmented` is a single scrolling row of 44px cells. */}
      <Segmented
        label="Port faces"
        segments={offeredFaces.map((f) => ({ id: f.id, label: f.label }))}
        value={shownFace.id}
        onChange={setFace}
      />

      {/* A FAIR IS A FACT ABOUT THE WHOLE HARBOUR, not a face you turn to: it changes the price on
          every face at once. One accent row, only when one is running. */}
      <QuayFair portId={portId} />

      {/* WHICH HARBOUR IS READ — a leaf that reads the store itself (PortField.tsx). */}
      <PortField current={port} anchor={actingPortCode} />

      {/* READING A HARBOUR YOU ARE NOT LYING IN. Two states, because they are two situations: a
          hull alongside somewhere else can be sailed here; a hull at sea is committed until she
          arrives. One line, and one button that takes you back to where she actually is —
          `harbourPick` (store/harbour.ts) decides whether that is a clear or a pin. */}
      {acting && !actingIsHere && (
        <Note
          tone="warning"
          action={
            actingPortCode ? (
              <Button size="sm" onClick={() => setPicked(harbourPick(actingPortCode, fleets, snapshot.ports))}>
                {`Go to ${portNameOf(portByCode, actingPortCode)}`}
              </Button>
            ) : undefined
          }
        >
          {acting.status === 'SAILING' && acting.voyage
            ? `${acting.name} is sailing to ${acting.voyage.to ? portNameOf(portByCode, acting.voyage.to) : 'open sea'}. Orders will run there.`
            : actingPortCode
              ? `${acting.name} is docked at ${portNameOf(portByCode, actingPortCode)}. Orders will run there.`
              : `${acting.name} is not in any port.`}
        </Note>
      )}

      <div role="tabpanel" className="mt-3">
        {/* ROW 53 — TRADE HAPPENS ON THE QUAY YOU ARE STANDING ON. A fleet lying HERE is the one
            that trades: `docked[0]`, not `acting`, because `acting` may be bound elsewhere and a
            quay deals with the hull alongside it. Nobody alongside → the read-only ledger, read
            against the acting fleet's hold. Until the market lands, the one loading placeholder. */}
        {shownFace.id === 'market' &&
          (quay.market === undefined ? (
            quay.refusal !== null ? (
              <Note
                tone="danger"
                code={quay.refusal.code}
                action={
                  <Button size="sm" onClick={quay.retry}>
                    Try again
                  </Button>
                }
              >
                {quay.refusal.sentence}
              </Note>
            ) : (
              <Skeleton className="h-28 w-full" />
            )
          ) : docked[0] ? (
            <PortTrade goods={quay.market.goods} fleet={docked[0]} port={port} />
          ) : (
            <PortPrices goods={quay.market.goods} port={port} reader={acting} />
          ))}
        {shownFace.id === 'city' && <PortTown port={port} onOpenFace={setFace} />}
        {shownFace.id === 'warehouse' && <PortWarehouse portId={port.id} fleet={acting} />}
        {shownFace.id === 'workstation' && (
          <PortWorkstation portId={port.id} fleet={acting} tier={buildingTier(port, 'workstation')} />
        )}
        {shownFace.id === 'inn' && <PortInn port={port} fleet={acting} alongside={docked[0] ?? null} />}
        {shownFace.id === 'shipyard' && <PortShipyard port={port} fleet={docked[0] ?? null} />}
        {shownFace.id === 'building_yard' && (
          <PortYard
            portId={port.id}
            fleet={acting}
            tier={buildingTier(port, 'building_yard')}
            maxDraft={port.max_draft}
          />
        )}
        {shownFace.id === 'academy' && <PortAcademy acting={acting} />}
      </div>
    </Sheet>
  )
}
