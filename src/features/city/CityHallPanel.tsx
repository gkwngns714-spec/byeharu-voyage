import { useState } from 'react'
import { Figure, Note, Row, Skeleton, SummaryRow, Tray, type TrayDetent } from '../../components/ui'
import { InvestorRow } from '../../live/CityInvestors'
import { TownHallInfluence } from '../../live/TownHallInfluence'
import type { CityInvestor, Refusal, SnapshotPort, TownHallView } from '../../lib/rpc'
import { formatDucats, formatInt } from '../../lib/format'
import { useT } from '../../lib/i18n'
import { CityPanel } from './CityPanel'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE TOWN HALL, IN PLACE (owner, 2026-10-31)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, verbatim: *"the HQ tab, when pressed town hall, the city image you've created should
// show up. right now the city image is at center, move it the left side, and then at the right side
// show what you would see the page pop up,. no need market info. tax info. influence yes, investors
// - tappable where when tapped, a list slides to the right where you can close."*
//
// ── THE INFLUENCE IS FOLDABLE — THE ONE OWNER-ORDERED FOLD (2026-10-31) ───────────────────────
// *"CITY HALL - THERE IS A SCROLL YOU NEED TO DO FOR INFLUENCE. MAKE INFLUENCE FOLDABLE, ADD
// POPULATION GOLD STATUS RELATIONSHIP EMPLOYEES ON THE RIGHT SIDE SINCE THERE WILL BE MORE ROOM"*
// Collapsed (the default) Influence is ONE row: its word, your served points and the disclosure
// chevron, ≥ 44 px. A press expands the INFLUENCE BOOK in place — the rows the hall has always
// carried, with the TAX ROWS OFF (`showTax={false}`; the owner, 2026-10-30: *"no need market info.
// tax info. influence yes…"* — that instruction stands, unchanged, and is not ours to supersede) —
// and a second press folds it. This fold is owner-ordered and is the one sanctioned fold; the
// game's "enough with folding" law is about in-place re-flow nobody asked for.
//
// ── THE FIVE FIGURES ARE THE HALL'S SINGLE HOME (owner, 2026-10-31) ───────────────────────────
// *"I DON'T NEED TO SEEP POPULATION AND RELATION, ANYTHING THAT WAS ALREADY SHOWN ON TOWN HALL"* —
// the frame's full-width figures card was removed (CityScreen), and this panel carries the block:
// Population (≈, the stated estimate off the served size tier) · Gold (the hall's purse) · Status
// (your influence points) · Relationship (the harbour's served stance) · Employees (the crew aboard
// your hulls). One compact line each — label at `t-caption`, figure at `t-body` — so the whole
// block costs ~130 px, not the 52-px rows of a list. No other city face prints any of these words.
//
// ── NO SCROLL AT ANY SERVED GLASS ─────────────────────────────────────────────────────────────
// The book's rows are compressed inside this panel (`[data-row-line]` loses the 52-px floor's
// padding and min-height): at 390×568 the panel shows the fold row, the expanded book, the five
// figures and the Investors row with no scroll in either state; at 320×568 the COLLAPSED state fits
// and the EXPANDED book may scroll inside the panel — stated and measured by tests/city.audit.spec
// — while the page itself never scrolls. The investors drawer is still the design system's side
// Tray (fixed, full-width on a phone below lg), opened by its own 44-px row, and it covers nothing
// that the press law protects: it is a dismissal surface with its own close.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/** The book's rows inside the hall panel: no 52-px floor padding, nothing but the served lines. */
const BOOK_DENSE = '[&_[data-row-line]]:min-h-0 [&_[data-row-line]]:py-0'

export function CityHallPanel({
  port,
  hall,
  refusal,
  population,
  employees,
  relation,
}: {
  port: SnapshotPort
  hall: TownHallView | null
  refusal: Refusal | null
  /** The stated estimate off the served size tier (CityScreen's one curve). */
  population: number
  /** The crew aboard your hulls (the frame's old figure, now the block's). */
  employees: number
  /** The harbour's relationship, worded and carrying its served facts (for the spec's data attrs). */
  relation: { word: string; stance: string | null; nation: string | null }
}) {
  const t = useT()
  const [investorsOpen, setInvestorsOpen] = useState(false)
  const [influenceOpen, setInfluenceOpen] = useState(false)

  if (refusal) {
    return (
      <CityPanel testId="city-hall-panel">
        <Note tone="danger" code={refusal.code} figures={refusal.figures}>
          {refusal.sentence}
        </Note>
      </CityPanel>
    )
  }
  if (!hall) {
    return (
      <CityPanel testId="city-hall-panel">
        <Skeleton className="h-24 w-full" />
      </CityPanel>
    )
  }

  const you = hall.influence.you
  return (
    <CityPanel
      testId="city-hall-panel"
      scrollTestId="city-hall-scroll"
      contentClassName="max-[360px]:px-2 max-[360px]:py-1"
      footer={
        <>
          {/* INVESTORS — one real tappable row (44 px), pinned under the panel's scroll so it is
              always reachable, even on the smallest glass. The drawer it opens is the served
              board. */}
          <div className="shrink-0 border-t border-edge">
            <SummaryRow title={t('town.investors')} figure={hall.investors.length} onClick={() => setInvestorsOpen(true)} data-testid="city-hall-investors" />
          </div>
          {investorsOpen && <InvestorsDrawer investors={hall.investors} onClose={() => setInvestorsOpen(false)} />}
        </>
      }
    >
      {/* THE INFLUENCE FOLD — the shared summary row (the one row): its word, your points beside it,
          the chevron at the edge, ≥ 44 px, and `aria-expanded` saying the state. */}
      <SummaryRow
        title={t('town.influence')}
        figure={you ? formatInt(you.points) : undefined}
        aria-expanded={influenceOpen}
        onClick={() => setInfluenceOpen((v) => !v)}
        data-testid="city-hall-influence"
      />
      {influenceOpen && (
        <div className={BOOK_DENSE} data-testid="city-hall-book">
          <TownHallInfluence port={port} influence={hall.influence} docked={hall.you.docked} showTax={false} compact />
        </div>
      )}

      {/* THE FIVE FIGURES — Population · Gold · Status · Relationship · Employees. The hall is
          their single home; no other city face prints one of these words. */}
      <div data-testid="city-hall-figures" className="mt-1">
        <Row label={t('city.population')} value={<Figure value={`≈ ${formatInt(population)}`} size="body" tone="ink" />} hairline={false} size="compact" data-testid="city-population" />
        <Row label={t('city.gold')} value={<Figure value={formatDucats(hall.purse.ducats)} size="body" tone="ink" />} hairline={false} size="compact" data-testid="city-gold" />
        <Row
          label={t('city.status')}
          value={you ? <Figure value={formatInt(you.points)} size="body" tone="ink" /> : <span className="text-ink-faint">—</span>}
          hairline={false}
          size="compact"
          data-testid="city-status"
        />
        <div data-testid="city-relationship" data-stance={relation.stance ?? 'none'} data-nation={relation.nation ?? 'none'}>
          <Row label={t('city.relationship')} value={<span className="text-t-caption text-ink">{relation.word}</span>} hairline={false} size="compact" />
        </div>
        <Row label={t('city.employees')} value={<Figure value={formatInt(employees)} size="body" tone="ink" />} hairline={false} size="compact" data-testid="city-employees" />
      </div>
    </CityPanel>
  )
}


/** THE INVESTORS DRAWER — the design system's side Tray (mode="side"): it slides in from the RIGHT
 *  (`bv-slide-in-right`), is the full width below `lg` (owner: "you know that this game is also for
 *  mobile right?") and 39rem wide on a wide glass. Its own 44-px ✕ closes it, the served board
 *  scrolls inside it, and it is fixed over the page, so nothing behind it reflows. */
function InvestorsDrawer({ investors, onClose }: { investors: readonly CityInvestor[]; onClose: () => void }) {
  const t = useT()
  const [detent, setDetent] = useState<TrayDetent>('full')
  return (
    <Tray
      detent={detent}
      onDetentChange={(next) => {
        if (next === 'closed') onClose()
        else setDetent(next)
      }}
      title={t('town.investors')}
      mode="side"
      data-testid="city-investors-drawer"
    >
      {investors.length === 0 ? (
        <Row label={t('town.nobody')} tone="muted" hairline={false} data-testid="city-investors-none" />
      ) : (
        investors.map((x, i) => <InvestorRow key={`${x.name}:${i}`} investor={x} />)
      )}
    </Tray>
  )
}
