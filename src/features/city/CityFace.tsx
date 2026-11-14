import { useState, type ReactNode } from 'react'
import { DetailPage, Note, SUMMARY_STACK_CLASS, SummaryRow } from '../../components/ui'
import { buildingTier, hasBuilding } from '../../domain/port'
import { fleetCrew, worstHullFraction } from '../../domain/fleet'
import { PortInn } from '../../live/PortInn'
import { PORT_FACES } from '../../live/cityFaces'
import { PortGear } from '../../live/PortGear'
import { PortShipyard } from '../../live/PortShipyard'
import { PortYard } from '../../live/PortYard'
import { useInn } from '../../live/useInn'
import type { FleetView, SnapshotPort } from '../../lib/rpc'
import { formatInt, formatOfTotal, formatPct } from '../../lib/format'
import { useT, type TKey } from '../../lib/i18n'
import { CityPanel } from './CityPanel'
import { MarketFace } from './MarketFace'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A BUILDING'S FACE, IN THE RIGHT PANEL (the City page, 2026-10-31)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, 2026-10-31: *"when pressed each building, HQ stays the same, but the the location
// where the city image is, as well as the right side should only change."* The city image stays on
// the glass (CityScreen): a press moves the plan's MARK and swaps the right-hand panel. Every face
// here is the building's own compact panel; the plan region stays left.
//
// ── THE COMPACT SCREEN, AND THE PAGE A ROW OPENS (the audit's row 3, 2026-10-31) ──────────────
// A face that needs more room than the panel is a COMPACT SCREEN of rows — one per thing the face
// is about — and a press on a row opens the face itself as the one `DetailPage` (the same
// mechanism every tab got in #421): fixed over the page, its body the one scroller, back with the
// header's press or Escape. The panel itself never scrolls, the document never scrolls, and the
// six tiles stay where they were. Every page's content is packed in a `max-w-2xl` column so a wide
// glass never leaves content gutters wider than the content (owner, 2026-10-31: "INN, HORIZONTAL
// SPACE IS TOO LARGE. MAKE IT COMPACT").
//
//   market    Basket · Buy · Sell · Requests. THE BASKET IS NOT AN OVERLAY (owner, 2026-10-31:
//             "MARKET- BASKET? WTF IS THIS POPPING UP BLOCKING THE WHOLE SCREEN?"): its press shows
//             a compact summary IN THIS PANEL — the line count and the served total, the hold bar,
//             one row to the board — never a screen-covering Sheet. The board (the quay ledger and
//             the trade trays) is the page a face row opens.
//   port      Build · Repair — the yard and the shipwright, each opening its own face.
//   production  not here: it takes the whole page, not the side panel (live/PortProduction.tsx, CityScreen).
//   inn       Crew · Captains here — the inn's face, packed, opening as a page.
//
// NO DUPLICATES OF THE HALL (owner, 2026-10-31): the Town Hall panel is the single home of
// Population · Gold · Status · Relationship · Employees; none of these words appears on any other
// face.
//
// THE FACES THEMSELVES ARE NOT REWRITTEN: the market is PortTrade/PortPrices,
// the yard PortYard, the shipwright PortShipyard, the inn PortInn — the
// same components the desk and the map compose. This file adds only the compact rows, the in-panel
// basket summary and the pages; nothing here is a second authority for a rule.

export type CityBuilding = 'market' | 'port' | 'inn'

/** One word per building, and the word's key beside it — never derived from the id. */
const BUILDING_LABEL: Record<CityBuilding, TKey> = {
  market: 'city.market',
  port: 'city.port',
  inn: 'city.inn',
}

/** A face's own player word, read off the one face table (live/cityFaces.ts) — never restated. */
function faceWord(id: 'building_yard' | 'shipyard' | 'gear'): string {
  return PORT_FACES.find((f) => f.id === id)!.label
}

/** THE PAGE'S CONTENT COLUMN — packed, never spread edge to edge on a wide glass. */
function PageBody({ children }: { children: ReactNode }) {
  return <div className="mx-auto w-full max-w-2xl">{children}</div>
}

export function CityFacePanel({
  building,
  port,
  fleet,
}: {
  building: CityBuilding
  port: SnapshotPort
  /** A fleet of yours lying HERE (the city's acting fleet), or null — read-only city. */
  fleet: FleetView | null
}) {
  const t = useT()
  // THE FACE STANDS IN A PAGE CARD (2026-11-04, the HQ on the page pattern): its title is the building's word, its rows keep
  // Row's own 52-px rhythm (the 44-px compaction of 2026-11-01 is gone: row 267, "too packed") and the page scrolls.
  return (
    <CityPanel testId="city-face-panel" building={building} title={t(BUILDING_LABEL[building])}>
      {building === 'market' && <MarketFace port={port} fleet={fleet} />}
      {building === 'port' && <PortFace port={port} fleet={fleet} />}
      {building === 'inn' && <InnFace port={port} fleet={fleet} />}
    </CityPanel>
  )
}

/** THE PORT — the yard and the shipwright as two rows; each opens its own face. The rows are the
 *  buildings PRESENT here (the same `hasBuilding` rule the desk reads), and their words are the
 *  face table's, never a second map. */
function PortFace({ port, fleet }: { port: SnapshotPort; fleet: FleetView | null }) {
  const t = useT()
  const yard = hasBuilding(port, 'building_yard')
  const repair = hasBuilding(port, 'shipyard')
  const [open, setOpen] = useState<'yard' | 'repair' | 'gear' | null>(null)
  const buildWord = faceWord('building_yard')
  const repairWord = faceWord('shipyard')
  // 0425: the starter gear is sold at EVERY harbour (no building), so the Port always has this row
  const gearWord = faceWord('gear')
  const damage = fleet ? formatPct(1 - worstHullFraction(fleet), 0) : undefined
  return (
    <>
      {!yard && !repair && <Note tone="neutral" className="mb-2">{t('city.noYard')}</Note>}
      {yard && <SummaryRow className={`min-h-row! ${SUMMARY_STACK_CLASS}`} title={buildWord} onClick={() => setOpen('yard')} data-testid="city-port-yard" />}
      {repair && <SummaryRow className={`min-h-row! ${SUMMARY_STACK_CLASS}`} title={repairWord} figure={damage} onClick={() => setOpen('repair')} data-testid="city-port-repair" />}
      <SummaryRow className={`min-h-row! ${SUMMARY_STACK_CLASS}`} title={gearWord} onClick={() => setOpen('gear')} data-testid="city-port-gear" />
      {open === 'gear' && (
        <DetailPage title={gearWord} onClose={() => setOpen(null)} data-testid="city-port-gear-page">
          <PageBody>
            <PortGear fleet={fleet} />
          </PageBody>
        </DetailPage>
      )}
      {open === 'yard' && (
        <DetailPage title={buildWord} onClose={() => setOpen(null)} data-testid="city-port-yard-page">
          <PageBody>
            <PortYard portId={port.id} fleet={fleet} tier={buildingTier(port, 'building_yard')} />
          </PageBody>
        </DetailPage>
      )}
      {open === 'repair' && (
        <DetailPage title={repairWord} onClose={() => setOpen(null)} data-testid="city-port-repair-page">
          <PageBody>
            <PortShipyard port={port} fleet={fleet} />
          </PageBody>
        </DetailPage>
      )}
    </>
  )
}

/** THE INN — the crew you have and the captains drinking here, as two rows; both open the inn's
 *  one face as a packed page. The rows exist because the whole face overflowed the panel at both
 *  glasses (measured 873/548 at 390 and 633/504 at 1280, 2026-10-31). */
function InnFace({ port, fleet }: { port: SnapshotPort; fleet: FleetView | null }) {
  const t = useT()
  const room = useInn(port.id)
  const [open, setOpen] = useState(false)
  if (!hasBuilding(port, 'inn')) return <Note tone="neutral">{t('city.noInn')}</Note>
  const crew = fleet ? fleetCrew(fleet) : null
  return (
    <>
      <SummaryRow
          className={`min-h-row! ${SUMMARY_STACK_CLASS}`}
        title={t('inn.crew')}
        figure={crew ? formatOfTotal(crew.aboard, crew.max) : undefined}
        onClick={() => setOpen(true)}
        data-testid="city-inn-crew"
      />
      <SummaryRow
          className={`min-h-row! ${SUMMARY_STACK_CLASS}`}
        title={t('inn.captainsHere')}
        figure={room.view ? formatInt(room.view.present.length) : undefined}
        onClick={() => setOpen(true)}
        data-testid="city-inn-captains"
      />
      {open && (
        <DetailPage title={t('city.inn')} onClose={() => setOpen(false)} data-testid="city-inn-page">
          <PageBody>
            <PortInn port={port} alongside={fleet} />
          </PageBody>
        </DetailPage>
      )}
    </>
  )
}
