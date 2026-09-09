import { useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import {
  Button,
  Figure,
  Icon,
  Note,
  Row,
  Segmented,
  Sheet,
  SheetSection,
} from '../../components/ui'
import { formatNm } from '../../lib/format'
import { portNameOf, useWorld } from '../../live/worldStore'
import type { MarketView, WorldSnapshot } from '../../lib/rpc'
import { useCommandDraft } from '../../domain/order'
import { PortAcademy } from './PortAcademy'
import { PortTrade } from './PortTrade'
import { PortTown } from './PortTown'
import { QuayFair } from './PortFair'
import { buildingTier, hasBuilding } from '../../domain/port'
import { PortWarehouse } from './PortWarehouse'
import { PortInn } from './PortInn'
import { PortYard } from './PortYard'
import { PortWorkstation } from './PortWorkstation'
import { PORT_FACES, usePortView } from './portView'
import { harbourCode, useHarbour } from '../../store/harbour'
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
// ── THIS SCREEN NEVER PRINTS AN ORDER STRING ANY MORE ──────────────────────────────────────────
// The sea-place list used to draw `SAIL Gaivota TO CAD` on its buttons — the wire contract as UI
// (§2 item 14). A row now says where and how far, and the hand-off carries a structured INTENT to
// COMMAND, which is what it always was underneath.
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
  const reaches = useWorld((s) => s.reaches)
  const loadReach = useWorld((s) => s.loadReach)
  const markets = useWorld((s) => s.markets)
  const navigate = useNavigate()
  const handOff = useCommandDraft((s) => s.handOff)
  const draftFleetId = useCommandDraft((s) => s.fleetId)
  const loadMarket = useWorld((s) => s.loadMarket)

  // WHICH HARBOUR — the ONE owner (src/store/harbour.ts), shared with MARKET, so a harbour picked
  // on either tab is the harbour both read. WHICH FACE — this screen's own chrome (portView.ts).
  const picked = useHarbour((s) => s.picked)
  const setPicked = useHarbour((s) => s.pick)
  const face = usePortView((s) => s.face)
  const setFace = usePortView((s) => s.turnTo)

  // THE DEFAULT IS WHERE THE HOUSE IS, AND A FLEET AT SEA IS SOMEWHERE. `harbourCode` is the ONE
  // spelling of pick-else-house-else-first-port; MARKET calls the same function, so the two tabs
  // cannot derive different defaults.
  const portCode = harbourCode(picked, fleets, snapshot.ports)
  const port = portCode ? (portByCode[portCode] ?? null) : null

  // The market is fetched per port, on demand — the store caches it. Never for a SEA PLACE (0036):
  // open water keeps no book, and asking for one would cache an empty market that looks exactly
  // like a real market with nothing in it.
  const isSeaPlace = port?.kind === 'SEA_PLACE'
  const portId = port?.id ?? null
  const market: MarketView | undefined = portId ? markets[portId] : undefined
  const marketLoaded = market !== undefined
  useEffect(() => {
    if (portId && !marketLoaded && !isSeaPlace) void loadMarket(portId)
  }, [portId, marketLoaded, isSeaPlace, loadMarket])
  useEffect(() => {
    if (portId) void loadReach(portId)
  }, [portId, loadReach])

  const docked = port ? fleets.filter((f) => f.port === port.code) : []
  const acting = docked[0] ?? fleets.find((f) => f.id === draftFleetId) ?? fleets[0] ?? null
  // WHERE THE ACTING FLEET'S NEXT ORDER WOULD RUN — alongside, or the harbour she is bound for.
  const actingPortCode = acting ? fleetPortCode(acting) : null
  const actingIsHere = actingPortCode !== null && actingPortCode === port?.code

  if (!port) {
    return (
      <Sheet title="Port">
        <Note tone="warning">The world served no ports.</Note>
      </Sheet>
    )
  }

  // 0036: A SEA PLACE HAS NO SHORE, so it gets the anchorage view and none of the harbour faces.
  // The served `kind` decides — the screen never infers "no quay" from an empty market.
  if (port.kind === 'SEA_PLACE') {
    const legs = (reaches[port.id]?.reaches ? Object.entries(reaches[port.id].reaches) : [])
      .map(([code, nm]) => ({ port: portByCode[code] ?? null, code, nm }))
      .filter((r) => r.port !== null && r.port.kind === 'HARBOUR')
      .sort((a, b) => a.nm - b.nm)
    return (
      <Sheet title={port.name} data-testid="port">
        {port.approach && <Note tone="neutral">{port.approach}</Note>}
        <SheetSection heading="At anchor">
          {docked.length === 0 ? (
            <Row label="None of your hulls are lying here." tone="muted" hairline={false} />
          ) : (
            docked.map((f, i) => (
              <Row key={f.id} label={f.name} value="holding station" hairline={i < docked.length - 1} />
            ))
          )}
        </SheetSection>
        <SheetSection heading="Sailing on">
          {legs.map(({ port: p, code, nm }, i) => (
            <Row
              key={code}
              label={p?.name ?? code}
              value={<Figure value={formatNm(nm)} unit="nm" />}
              chevron
              onClick={() => {
                handOff({ fleetId: acting?.id ?? null, verb: 'SAIL', args: { dest: code } })
                navigate('/command')
              }}
              hairline={i < legs.length - 1}
            />
          ))}
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

      {/* READING A HARBOUR YOU ARE NOT LYING IN. Two states, because they are two situations: a
          hull alongside somewhere else can be sailed here; a hull at sea is committed until she
          arrives. One line, and one button that takes you to where she actually is. */}
      {acting && !actingIsHere && (
        <Note
          tone="warning"
          action={
            actingPortCode ? (
              <Button size="sm" onClick={() => setPicked(actingPortCode)}>
                {`Read ${portNameOf(portByCode, actingPortCode)}`}
              </Button>
            ) : undefined
          }
        >
          {acting.status === 'SAILING' && acting.voyage
            ? `${acting.name} is at sea, bound for ${acting.voyage.to ? portNameOf(portByCode, acting.voyage.to) : 'open water'}. Orders run there.`
            : actingPortCode
              ? `${acting.name} lies at ${portNameOf(portByCode, actingPortCode)}. Orders run there.`
              : `${acting.name} is alongside nowhere.`}
        </Note>
      )}

      <div role="tabpanel" className="mt-3">
        {/* ROW 53 — TRADE HAPPENS ON THE QUAY YOU ARE STANDING ON. A fleet lying HERE is the one
            that trades: `docked[0]`, not `acting`, because `acting` may be bound elsewhere and a
            quay deals with the hull alongside it. */}
        {shownFace.id === 'market' && (
          <PortTrade goods={market?.goods ?? []} fleet={docked[0] ?? null} culture={port.culture} />
        )}
        {shownFace.id === 'city' && <PortTown port={port} onOpenFace={setFace} />}
        {shownFace.id === 'warehouse' && <PortWarehouse portId={port.id} fleet={acting} />}
        {shownFace.id === 'workstation' && (
          <PortWorkstation portId={port.id} fleet={acting} tier={buildingTier(port, 'workstation')} />
        )}
        {shownFace.id === 'inn' && <PortInn portId={port.id} fleet={acting} />}
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
