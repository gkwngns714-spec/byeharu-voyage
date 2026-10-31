import { useState, type ReactNode } from 'react'
import { Button, CargoBar, DetailPage, Figure, Note, Row, Skeleton, SummaryRow } from '../../components/ui'
import { buildingTier, hasBuilding } from '../../domain/port'
import { fleetCargoByCode, fleetCrew, fleetHoldTotal, fleetHoldUsed, worstHullFraction } from '../../domain/fleet'
import { PortForge } from '../../live/PortForge'
import { groupsByTier } from '../../live/forgeGroups'
import { PortInn } from '../../live/PortInn'
import { PortPrices } from '../../live/PortPrices'
import { PORT_FACES } from '../../live/cityFaces'
import { PortShipyard } from '../../live/PortShipyard'
import { PortStorage } from '../../live/PortStorage'
import { PortTrade } from '../../live/PortTrade'
import { PortYard } from '../../live/PortYard'
import { useForge } from '../../live/useForge'
import { useInn } from '../../live/useInn'
import { useManifestPreview } from '../../live/useManifestPreview'
import { usePortMarket } from '../../live/usePortMarket'
import { TRADE_FACES, useTradeFace, type TradeFace } from '../../live/tradeFace'
import type { FleetView, SnapshotPort } from '../../lib/rpc'
import { formatDucats, formatInt, formatOfTotal, formatPct } from '../../lib/format'
import { linesFor, useManifest } from '../../store/manifest'
import { useT, type TKey } from '../../lib/i18n'
import { CityPanel } from './CityPanel'

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
//   forge     one row per product tier, the count beside it; the tier opens its products. A
//             product's control carries the product's NAME (1-2 words); its ingredients are in
//             the tray the press opens (audit row 39).
//   port      Build · Repair — the yard and the shipwright, each opening its own face.
//   storage   the warehouse's own face (a short board at every served size).
//   inn       Crew · Captains here — the inn's face, packed, opening as a page.
//
// NO DUPLICATES OF THE HALL (owner, 2026-10-31): the Town Hall panel is the single home of
// Population · Gold · Status · Relationship · Employees; none of these words appears on any other
// face.
//
// THE FACES THEMSELVES ARE NOT REWRITTEN: the market is PortTrade/PortPrices, the forge PortForge,
// the yard PortYard, the shipwright PortShipyard, the storage PortStorage, the inn PortInn — the
// same components the desk and the map compose. This file adds only the compact rows, the in-panel
// basket summary and the pages; nothing here is a second authority for a rule.

export type CityBuilding = 'market' | 'storage' | 'forge' | 'port' | 'inn'

/** One word per building, and the word's key beside it — never derived from the id. */
const BUILDING_LABEL: Record<CityBuilding, TKey> = {
  market: 'city.market',
  storage: 'city.storage',
  forge: 'city.forge',
  port: 'city.port',
  inn: 'city.inn',
}

/** A face's own player word, read off the one face table (live/cityFaces.ts) — never restated. */
function faceWord(id: 'market' | 'warehouse' | 'inn' | 'building_yard' | 'shipyard'): string {
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
  return (
    <CityPanel testId="city-face-panel" building={building}>
      <h2 className="pb-1 text-t-caption text-ink-faint">{t(BUILDING_LABEL[building])}</h2>
      {building === 'market' && <MarketFace port={port} fleet={fleet} />}
      {building === 'storage' && <StorageFace port={port} fleet={fleet} />}
      {building === 'forge' && <ForgeFace port={port} fleet={fleet} />}
      {building === 'port' && <PortFace port={port} fleet={fleet} />}
      {building === 'inn' && <InnFace port={port} fleet={fleet} />}
    </CityPanel>
  )
}

/** THE QUAY — Basket in this panel (never an overlay), the board's three faces as rows. */
function MarketFace({ port, fleet }: { port: SnapshotPort; fleet: FleetView | null }) {
  const t = useT()
  const quay = usePortMarket(port.kind === 'HARBOUR' ? port.id : null)
  const [open, setOpen] = useState<TradeFace | null>(null)
  const [basketOpen, setBasketOpen] = useState(false)
  const staged = useManifest((s) => linesFor(s, fleet?.id ?? '', port.code))
  if (!hasBuilding(port, 'market')) return <Note tone="neutral">{t('city.noMarket')}</Note>
  if (quay.market === undefined) {
    return quay.refusal !== null ? (
      <Note
        tone="danger"
        code={quay.refusal.code}
        figures={quay.refusal.figures}
        action={
          <Button size="sm" onClick={quay.retry}>
            {t('common.retry')}
          </Button>
        }
      >
        {quay.refusal.sentence}
      </Note>
    ) : (
      <Skeleton className="h-28 w-full" />
    )
  }
  const goods = quay.market.goods
  const cargoLines = fleet ? Object.keys(fleetCargoByCode(fleet)).length : undefined
  const FIGURES: Record<TradeFace, number | undefined> = { buy: goods.length, sell: cargoLines, requests: undefined }
  const turn = (face: TradeFace) => {
    // The board's face is the ONE store every caller reads (live/tradeFace.ts) — never a second
    // copy of "which face".
    useTradeFace.getState().turnTo(face)
    setOpen(face)
  }
  return (
    <>
      {basketOpen && fleet ? (
        <BasketSummary fleet={fleet} port={port} onClose={() => setBasketOpen(false)} onOpenBoard={turn} />
      ) : (
        <>
          {fleet && (
            <Row
              label={t('trade.basket')}
              value={formatInt(staged.length)}
              chevron
              onClick={() => setBasketOpen(true)}
              data-testid="city-market-basket"
            />
          )}
          {TRADE_FACES.map((f) => (
            <SummaryRow
              key={f.id}
              title={f.label}
              figure={FIGURES[f.id] === undefined ? undefined : formatInt(FIGURES[f.id]!)}
              onClick={() => turn(f.id)}
              data-testid={`city-market-${f.id}`}
            />
          ))}
        </>
      )}
      {open !== null && (
        <DetailPage title={t('city.market')} onClose={() => setOpen(null)} data-testid={`city-market-${open}-page`}>
          <PageBody>
            {fleet ? <PortTrade goods={goods} fleet={fleet} port={port} /> : <PortPrices goods={goods} port={port} reader={null} />}
          </PageBody>
        </DetailPage>
      )}
    </>
  )
}

/** THE BASKET, IN THE PANEL (owner, 2026-10-31: no popping block) — the staged line count, the
 *  served total, the hold bar, and one row to the board. It computes nothing: the lines are the
 *  manifest store's and the total is `cmd.preview_basket`'s (useManifestPreview). */
function BasketSummary({
  fleet,
  port,
  onClose,
  onOpenBoard,
}: {
  fleet: FleetView
  port: SnapshotPort
  onClose: () => void
  onOpenBoard: (face: TradeFace) => void
}) {
  const t = useT()
  const lines = useManifest((s) => linesFor(s, fleet.id, port.code))
  const preview = useManifestPreview(fleet.id, port.code, lines)
  const totals = preview.estimate?.totals ?? null
  return (
    <div data-testid="city-basket">
      <div className="flex min-h-11 items-center justify-between gap-2 border-b border-edge">
        <span className="text-t-caption text-ink-faint">{t('trade.basket')}</span>
        <span className="flex items-center gap-2 text-t-caption tabular-nums text-ink-muted">
          {lines.length === 0 ? t('trade.basketEmpty') : formatInt(lines.length)}
          {totals !== null && <Figure value={formatDucats(totals.net)} size="body" />}
        </span>
      </div>
      <CargoBar used={fleetHoldUsed(fleet)} total={fleetHoldTotal(fleet)} free={fleet.free_hold} className="py-2" />
      <SummaryRow title={t('town.f_market')} onClick={() => onOpenBoard('buy')} data-testid="city-basket-board" />
      <Row label={t('common.back')} chevron onClick={onClose} hairline={false} data-testid="city-basket-back" />
    </div>
  )
}

/** THE FORGE — one row per product tier; a tier opens its products. The rows' grouping is
 *  PortForge's own fold (`groupsByTier`), so the counts and the page can never disagree. */
function ForgeFace({ port, fleet }: { port: SnapshotPort; fleet: FleetView | null }) {
  const t = useT()
  const { view, loading } = useForge(port.id)
  const [openTier, setOpenTier] = useState<number | null>(null)
  if (loading && !view) return <Skeleton className="h-28 w-full" />
  if (!view) return <Note tone="neutral">{t('city.forgeNone')}</Note>
  const groups = groupsByTier(view.recipes)
  return (
    <>
      {groups.length === 0 && <Note tone="neutral">{t('city.forgeNone')}</Note>}
      {groups.map(([tier, recipes]) => (
        <SummaryRow
          key={tier}
          title={t('city.forgeTier', { n: formatInt(tier) })}
          figure={formatInt(recipes.length)}
          onClick={() => setOpenTier(tier)}
          data-testid={`city-forge-tier-${tier}`}
        />
      ))}
      {openTier !== null && (
        <DetailPage
          title={t('city.forgeTier', { n: formatInt(openTier) })}
          onClose={() => setOpenTier(null)}
          data-testid="city-forge-page"
        >
          <PageBody>
            <PortForge portId={port.id} fleet={fleet} tier={openTier} />
          </PageBody>
        </DetailPage>
      )}
    </>
  )
}

function StorageFace({ port, fleet }: { port: SnapshotPort; fleet: FleetView | null }) {
  const t = useT()
  if (!hasBuilding(port, 'warehouse')) return <Note tone="neutral">{t('inn.noStorage')}</Note>
  return <PortStorage portId={port.id} fleet={fleet} />
}

/** THE PORT — the yard and the shipwright as two rows; each opens its own face. The rows are the
 *  buildings PRESENT here (the same `hasBuilding` rule the desk reads), and their words are the
 *  face table's, never a second map. */
function PortFace({ port, fleet }: { port: SnapshotPort; fleet: FleetView | null }) {
  const t = useT()
  const yard = hasBuilding(port, 'building_yard')
  const repair = hasBuilding(port, 'shipyard')
  const [open, setOpen] = useState<'yard' | 'repair' | null>(null)
  if (!yard && !repair) return <Note tone="neutral">{t('city.noYard')}</Note>
  const buildWord = faceWord('building_yard')
  const repairWord = faceWord('shipyard')
  const damage = fleet ? formatPct(1 - worstHullFraction(fleet), 0) : undefined
  return (
    <>
      {yard && <SummaryRow title={buildWord} onClick={() => setOpen('yard')} data-testid="city-port-yard" />}
      {repair && <SummaryRow title={repairWord} figure={damage} onClick={() => setOpen('repair')} data-testid="city-port-repair" />}
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
        title={t('inn.crew')}
        figure={crew ? formatOfTotal(crew.aboard, crew.max) : undefined}
        onClick={() => setOpen(true)}
        data-testid="city-inn-crew"
      />
      <SummaryRow
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
