import { useNavigate } from 'react-router-dom'
import { Button, Clip, Note, ScrollPane, Segmented, Skeleton, WRAP_ROW_CLASS } from '../../../components/ui'
import { alongsideAt, boundForLabel, fleetPortCode, whereabouts } from '../../../domain/fleet'
import { buildingTier, hasBuilding } from '../../../domain/port'
import { PORT_FACES, productionHref, type PortFace } from '../../../live/cityFaces'
import { CityTownHall } from '../../../live/CityTownHall'
import { PortAcademy } from '../../../live/PortAcademy'
import { QuayFair } from '../../../live/PortFair'
import { PortFlag } from '../../../live/PortFlag'
import { PortInn } from '../../../live/PortInn'
import { PortPrices } from '../../../live/PortPrices'
import { PortShipyard } from '../../../live/PortShipyard'
import { PortTown } from '../../../live/PortTown'
import { PortTrade } from '../../../live/PortTrade'
import { PortWorkstation } from '../../../live/PortWorkstation'
import { PortYard } from '../../../live/PortYard'
import { TowNote } from '../../../live/TowNote'
import { usePortMarket } from '../../../live/usePortMarket'
import { portNameOf, useWorld } from '../../../live/worldStore'
import type { FleetView } from '../../../lib/rpc'
import type { DeskLayout } from '../DeskFrame'
import { useDeskView } from '../deskView'
import { useT } from '../../../lib/i18n'

// CITY — every building of the city the fleet is at, on the desk (docs/COMMAND_DESK.md §2.1, §3.6, D5). The
// owner, 2026-10-17: *"delete port tab, and focus on command tab … and all"*.
//
// THE CITY IS THE FLEET'S (§2.1): the one it is docked at — where every act here runs — or, at sea, the one it
// is bound for, read-only, with one line saying when its orders run. There is no port field: the desk reads
// other cities through a good's page, and the map reads any city.
//
// THE FACES ARE PORT'S, MOVED, NOT REWRITTEN: the one table (live/cityFaces.ts — which building a face is,
// and its one word) and the one component per face in src/live, which PORT composes too until it is deleted
// (D8). Trade is the quay's board with its basket, bargain, requests and supplies; Town is the city's
// buildings, with the Town Hall under it (the purse: Grant · Earnings · the crown · Paid by its people, and
// Invest). A face is offered only where its building stands. A press selects; nothing moves.
//
// THE DESK LAYS IT OUT (DeskFrame.tsx, 2026-10-19): on a wide glass the city and its buildings stand in
// the left pane, the building in the centre, and the act a building opens (a trade, the basket, a hire,
// a job) in the right pane — the desk's slot; on a phone, one under the other (an act pressed there rises as the bottom tray, which moves nothing).

export function City({ fleet, layout }: { fleet: FleetView; layout: DeskLayout }) {
  const t = useT()
  const navigate = useNavigate()
  const fleets = useWorld((s) => s.fleets)
  const portByCode = useWorld((s) => s.portByCode)
  const face = useDeskView((s) => s.cityFace)
  const setFace = useDeskView((s) => s.setCityFace)

  const where = whereabouts(fleet)
  const code = fleetPortCode(fleet)
  const port = code ? (portByCode[code] ?? null) : null
  const quay = usePortMarket(port?.kind === 'HARBOUR' ? port.id : null)
  // THE QUAY'S FAIR READ HAS LANDED (QuayFair, src/live/PortFair.tsx, owns the read; this only reports the store).
  // Its quiet state draws nothing, so unlike the market there is no Skeleton saying "not yet" — and a fair's
  // row arriving late is 52 px that moves everything under it. The frame carries the mark for a spec to wait on
  // (tests/desk.fixture.ts `openCityFace`), and the mark paints nothing.
  const fairRead = useWorld((s) => (port?.kind === 'HARBOUR' ? s.buffs[port.id] !== undefined : false))

  if (!port || port.kind !== 'HARBOUR') {
    return layout({
      testid: 'desk-city',
      list: (
        <Note tone="neutral">
          {fleet.name} is not at a city. Sail to one to use its buildings.
        </Note>
      ),
      main: null,
    })
  }

  // who of yours is docked HERE (the one that acts), and whether the selected fleet is one of them
  const { docked } = alongsideAt(fleets, port.code, fleet.id)
  const here = where.kind === 'docked' && where.port === port.code
  const offered = PORT_FACES.filter((f) => f.building === null || hasBuilding(port, f.building))
  // Storage and the Forge are one page of the HQ now: the `warehouse` tab and Town row go there, and a saved `warehouse` face falls to the first.
  const shown = offered.find((f) => f.id === face && f.id !== 'warehouse') ?? offered[0]
  const acting = here ? fleet : null
  const openFace = (next: PortFace) => (next === 'warehouse' ? void navigate(productionHref(port.code)) : setFace(next))

  return layout({
    testid: 'desk-city',
    mainFill: true,
    sideHint: t('desk.citySide'),
    marks: fairRead ? { 'data-fair-loaded': '' } : undefined,
    list: (
    <>
      {/* THE CITY PAGE'S DOOR (2026-10-30): the full-screen city, for the city in hand. The press
          navigates; it does not change this face, and the desk is exactly as it was when you return. */}
      {/* A WRAPPING LINE (2026-11-13): the name is never narrower than its longest word, and where the name and the door do not
          fit one line (the wide desk's left pane is 240 px inside at 1,280 px: "Machilipatnam" stood over "City view") the
          door stands on the next line, at the right. */}
      <div className={WRAP_ROW_CLASS}>
        <h2 className="flex min-w-min items-center gap-2 text-t-body font-semibold text-ink">
          <PortFlag code={port.code} />
          <Clip>{port.name}</Clip>
        </h2>
        <Button
          variant="secondary"
          className="ml-auto"
          onClick={() => navigate(`/city?port=${encodeURIComponent(port.code)}`)}
          data-testid="desk-city-open"
        >
          {t('city.open')}
        </Button>
      </div>
      {!here && (
        <Note tone="neutral" className="mt-2" data-testid="desk-city-bound">
          {where.kind === 'sailing'
            ? t('desk.sailingRO', { fleet: fleet.name, place: boundForLabel(where, (c) => portNameOf(portByCode, c)) })
            : t('desk.notDockedRO', { fleet: fleet.name })}
        </Note>
      )}
      <Segmented<PortFace>
        label={t('desk.cityBuildings')}
        segments={offered.map((f) => ({ id: f.id, label: f.label }))}
        value={shown.id}
        onChange={openFace}
        // In the desk's narrow left pane (272 px at 1,280) every building stays in sight: the row is a wrapping line there, each cell as wide as
        // its word at least. It was four equal 53-px columns, and "Production" (67 px) stood against "Town" and "Craft" (2026-11-14).
        className="mt-3 lg:flex lg:flex-wrap lg:*:min-w-11 lg:*:flex-auto lg:*:px-1!"
      />
      <QuayFair portId={port.id} />
      {/* 0255 (E6b, CLOSED_ECONOMY §4b): what this city wants now and pays a multiple for (absent while dark) */}
      {quay.market?.wants && quay.market.wants.length > 0 && (
        <Note tone="neutral" className="mt-3" data-testid="desk-city-wants">
          {t('ui.wanted', { mult: String(Number(quay.market.wants[0].mult)) })}: {quay.market.wants.map((w) => w.name).join(' · ')}
        </Note>
      )}
      <TowNote docked={docked} />
    </>
    ),
    main: (
      <div role="tabpanel" className="mt-3 flex min-h-0 flex-1 flex-col lg:mt-0">
        {/* THE BUILDING'S FACE IS THE ONE LONG BODY ON THE PHONE (2026-10-31, the sheet law): it
            scrolls inside its own pane, so the city, its buildings and its rail never travel.
            THE PANE TAKES THE GLASS THAT IS LEFT (2026-11-02): it was a 12-rem (192 px) cap inside a Sheet that ended 187 px below it, and
            its own controls (the supplies row, Buy · Sell · Requests, the filter: 150 px) took 150 of the 192 — at 390 forty px of goods stood on
            the glass, at 320 none. It is now the rest of the Sheet (7 rem at the least, so a short glass scrolls the Sheet rather than
            crush it) — and a QUERY CONTAINER (index.css, `pair:`), so a Trade row in a 288-px pane at 320 stands its name over its two
            price cells instead of squeezing the name to one letter. */}
        <ScrollPane className="@container min-h-28 flex-1 lg:max-h-none">
        {shown.id === 'market' &&
          (quay.market === undefined ? (
            quay.refusal !== null ? (
              <Note
                tone="danger"
                code={quay.refusal.code} figures={quay.refusal.figures}
                action={
                  <Button size="sm" onClick={quay.retry}>
                    {t('desk.tryAgain')}
                  </Button>
                }
              >
                {quay.refusal.sentence}
              </Note>
            ) : (
              <Skeleton className="h-28 w-full" />
            )
          ) : here ? (
            <PortTrade goods={quay.market.goods} fleet={fleet} port={port} />
          ) : (
            <PortPrices goods={quay.market.goods} port={port} reader={fleet} />
          ))}
        {shown.id === 'city' && (
          <>
            <PortTown port={port} onOpenFace={openFace} />
            <div className="mt-6" data-testid="desk-town-hall">
              <CityTownHall port={port} />
            </div>
          </>
        )}
        {shown.id === 'workstation' && (
          <PortWorkstation portId={port.id} fleet={acting} tier={buildingTier(port, 'workstation')} />
        )}
        {shown.id === 'inn' && <PortInn port={port} alongside={acting} />}
        {shown.id === 'shipyard' && <PortShipyard port={port} fleet={acting} />}
        {shown.id === 'building_yard' && (
          <PortYard portId={port.id} fleet={acting} tier={buildingTier(port, 'building_yard')} />
        )}
        {shown.id === 'academy' && <PortAcademy />}
        </ScrollPane>
      </div>
    ),
  })
}
