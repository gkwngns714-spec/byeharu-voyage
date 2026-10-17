import { useEffect, useState } from 'react'
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
import { PortField } from '../../live/PortField'
import { PortPrices } from '../../live/PortPrices'
import { PortTrade } from './PortTrade'
import { PortTown } from './PortTown'
import { QuayFair } from './PortFair'
import { buildingTier, hasBuilding } from '../../domain/port'
import { PortStorage } from './PortStorage'
import { PortInn } from '../../live/PortInn'
import { PortYard } from './PortYard'
import { PortWorkstation } from './PortWorkstation'
import { PortShipyard } from './PortShipyard'
import { TowNote } from '../../live/TowNote'
import { PORT_FACES, usePortView } from './portView'
import { harbourCode, harbourPick, useHarbour } from '../../store/harbour'
import { alongsideAt, boundForLabel, fleetPortCode, whereabouts } from '../../domain/fleet'
import { WorldFailed, WorldLoading } from '../../live/WorldGate'
// 0099 — the merchants: the same sheet MAP opens, read through the same card. 0104 (owner row 121):
// and the harbour's own list of them, with what each one is doing here.
import { MerchantSheet } from '../../live/MerchantSheet'
import { merchantParts } from '../../live/merchantLine'
import { PlaceLine } from '../../chart'
import { useMerchantCard } from '../../live/useMerchantCard'
import { MerchantsHere } from './MerchantsHere'
import { useMerchantsHere } from '../../live/useMerchantsHere'
import { useShellState } from '../../app/shellState'

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
    return <WorldFailed title="Port" refusal={fatal} />
  }
  if (phase !== 'ready' || !snapshot) {
    return <WorldLoading title="Port" />
  }
  return <PortBody snapshot={snapshot} />
}

// 0102's PORT SEA WINDOW IS GONE (0104). It existed for one reason — to make sure the windowed
// `world.sea_traffic` carried the merchants lying at THIS quay, because this screen's list was
// filtered out of that whole-world read. Owner row 121 asked the harbour a question that read
// cannot answer (what is she DOING here, and who is away on her way back), so the list is served
// by `world.port_merchants(port)` now and PORT reads no traffic at all. One screen, one read.

function PortBody({ snapshot }: { snapshot: WorldSnapshot }) {
  const fleets = useWorld((s) => s.fleets)
  const portByCode = useWorld((s) => s.portByCode)
  const draftFleetId = useCommandDraft((s) => s.fleetId)
  // THE OPEN MERCHANT SHEET, REMEMBERED WITH THE HARBOUR IT WAS OPENED FROM. The list is one
  // harbour's now (0104), so a sheet left open while the port field moves would be about a merchant
  // nothing on screen names, and her peek line — which comes from these rows — would go blank.
  // Carried as (harbour, fleet) and DERIVED below rather than cleared in an effect: a reset in an
  // effect is a cascading render, and the rule here is a derivation, not a synchronisation.
  const [openMerchant, setOpenMerchant] = useState<{ port: string; fleet: string } | null>(null)
  const { nowMs } = useShellState()

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

  // WHICH MERCHANTS THIS HARBOUR CONCERNS, AND WHAT EACH IS DOING (0104, owner row 121). Its own
  // read, asked when a city is opened and re-asked on the world's beat (useMerchantsHere.ts carries
  // the argument): what a merchant is DOING is a fact about a PORT, and `world.sea_traffic` — the
  // beat's whole-world read, windowed and capped since 0102 — has no harbour to be about and drops
  // the merchant who is away on her loop, who is half of what the owner asked to see. So PORT no
  // longer reads the traffic at all, and 0102's PORT window went with the list that needed it.
  // Never for a SEA PLACE: open water is on nobody's loop. HOOK ORDER: before the early returns.
  const merchants = useMerchantsHere(port?.kind === 'HARBOUR' ? portId : null)
  const merchantId = openMerchant !== null && openMerchant.port === portId ? openMerchant.fleet : null
  const { card: merchantCard } = useMerchantCard(merchantId)

  // THE ONE "ALONGSIDE HERE" TEST. Read-only ⇔ nobody is.
  // In port or not is `domain/fleet`'s one rule (`whereabouts`), never a bare `f.port` read here.
  // Who acts for this harbour is `domain/fleet`'s `alongsideAt` (the MAP's city panel asks it too).
  // No port (the early return below) is a harbour no fleet lies in: nobody docked, the draft acts.
  const { docked, acting } = alongsideAt(fleets, port?.code ?? '', draftFleetId)
  const actingWhere = acting ? whereabouts(acting) : null
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
          {/* At sea, in port or neither is `domain/fleet`'s one rule (`whereabouts`); this used to
              re-decide it from `status` and `voyage.to` with its own "open sea". */}
          {actingWhere?.kind === 'sailing'
            ? `${acting.name} is sailing to ${boundForLabel(actingWhere, (c) => portNameOf(portByCode, c))}. Orders will run there.`
            : actingWhere?.kind === 'docked'
              ? `${acting.name} is docked at ${portNameOf(portByCode, actingWhere.port)}. Orders will run there.`
              : `${acting.name} is not in any port.`}
        </Note>
      )}

      {/* A WRECK OF YOURS LYING HERE (0152): the tow, above every face — a harbour with no shipyard
          has no Repair face for it to stand on (src/live/TowNote.tsx). */}
      <TowNote docked={docked} />

      {/* MERCHANTS (0099, grown into owner row 121 by 0104) — the world's own companies this
          harbour concerns, named, because they are the harbour's furniture and not somebody's
          position, each with WHAT SHE IS DOING here and the loop that brings her. A section, never
          the `trailing` slot (that is about YOU). Hidden when there is none. A row opens the
          read-only sheet. */}
      <MerchantsHere
        rows={merchants.view?.enabled ? merchants.view.merchants : []}
        portCode={port.code}
        portName={(c) => portNameOf(portByCode, c)}
        nowMs={nowMs}
        onOpen={(fleet) => setOpenMerchant(portId === null ? null : { port: portId, fleet })}
      />
      {merchantId && (
        <MerchantSheet
          key={merchantId}
          card={merchantCard && merchantCard.fleet.id === merchantId ? merchantCard : null}
          line={(() => {
            const row = merchants.view?.merchants.find((t) => t.id === merchantId)
            return row ? <PlaceLine parts={merchantParts(row, (c) => portNameOf(portByCode, c), nowMs)} /> : ''
          })()}
          onClose={() => setOpenMerchant(null)}
        />
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
        {shownFace.id === 'warehouse' && <PortStorage portId={port.id} fleet={acting} />}
        {shownFace.id === 'workstation' && (
          <PortWorkstation portId={port.id} fleet={acting} tier={buildingTier(port, 'workstation')} />
        )}
        {shownFace.id === 'inn' && <PortInn port={port} alongside={docked[0] ?? null} />}
        {shownFace.id === 'shipyard' && <PortShipyard port={port} fleet={docked[0] ?? null} />}
        {shownFace.id === 'building_yard' && (
          <PortYard
            portId={port.id}
            fleet={acting}
            tier={buildingTier(port, 'building_yard')}
          />
        )}
        {shownFace.id === 'academy' && <PortAcademy />}
      </div>
    </Sheet>
  )
}
