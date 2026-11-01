import { useState, type ReactNode } from 'react'
import { Figure, Icon, Note, Row, Skeleton, Tray, type TrayDetent } from '../../components/ui'
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
          <div className="shrink-0 border-t border-edge px-gutter">
            <button
              type="button"
              onClick={() => setInvestorsOpen(true)}
              data-testid="city-hall-investors"
              className="flex min-h-11 w-full items-center gap-2 py-2 text-left text-ink-muted transition hover:text-ink"
            >
              <span className="text-t-caption">{t('town.investors')}</span>
              <span className="shrink-0 text-t-caption tabular-nums">{hall.investors.length}</span>
              <Icon name="chevron" size={16} className="ml-auto text-ink-faint" />
            </button>
          </div>
          {investorsOpen && <InvestorsDrawer investors={hall.investors} onClose={() => setInvestorsOpen(false)} />}
        </>
      }
    >
      {/* THE INFLUENCE FOLD — collapsed: its word, your points hugging it, the chevron at the edge;
          ≥ 44 px. */}
      <button
        type="button"
        aria-expanded={influenceOpen}
        onClick={() => setInfluenceOpen((v) => !v)}
        data-testid="city-hall-influence"
        className="flex min-h-11 w-full shrink-0 items-center gap-2 rounded-control border-b border-edge text-left text-ink-muted transition hover:text-ink"
      >
        <span className="text-t-caption">{t('town.influence')}</span>
        <span className="shrink-0 text-t-caption tabular-nums">{you ? formatInt(you.points) : null}</span>
        <Icon name="chevron" size={16} className={`ml-auto text-ink-faint transition ${influenceOpen ? 'rotate-180' : ''}`} />
      </button>
      {influenceOpen && (
        <div className={BOOK_DENSE} data-testid="city-hall-book">
          <TownHallInfluence port={port} influence={hall.influence} docked={hall.you.docked} showTax={false} compact />
        </div>
      )}

      {/* THE FIVE FIGURES — Population · Gold · Status · Relationship · Employees. The hall is
          their single home; no other city face prints one of these words. */}
      <div data-testid="city-hall-figures" className="mt-1">
        <FigureLine label={t('city.population')} testid="city-population">
          <Figure value={`≈ ${formatInt(population)}`} size="body" tone="ink" />
        </FigureLine>
        <FigureLine label={t('city.gold')} testid="city-gold">
          <Figure value={formatDucats(hall.purse.ducats)} size="body" tone="ink" />
        </FigureLine>
        <FigureLine label={t('city.status')} testid="city-status">
          {you ? <Figure value={formatInt(you.points)} size="body" tone="ink" /> : <span className="text-ink-faint">—</span>}
        </FigureLine>
        <FigureLine label={t('city.relationship')} testid="city-relationship" data-stance={relation.stance ?? 'none'} data-nation={relation.nation ?? 'none'}>
          <span className="text-t-caption text-ink">{relation.word}</span>
        </FigureLine>
        <FigureLine label={t('city.employees')} testid="city-employees">
          <Figure value={formatInt(employees)} size="body" tone="ink" />
        </FigureLine>
      </div>
    </CityPanel>
  )
}

/** ONE COMPACT LINE — 20 px tall, the figure hugging its label (owner, 2026-11-01: *"empty spaces
 *  between words and numbers horizontally … make it so that htey are closer, more compact"*). The
 *  figure used to be pushed to the far edge by `justify-between`; it now stands 8 px behind its
 *  word, and nothing is spread across the panel.
 *
 *  A LABEL IS NEVER CUT, AND A FIGURE THAT DOES NOT FIT MOVES UNDER ITS LABEL (2026-11-02, the HQ on a phone: "Popul…" and "Relatio…" read
 *  as stumps at 390 and 320). Inside the panel's query container (`narrow:`, index.css) the line wraps: "Population ≈ 160,000" is 148 px
 *  and the panel's room 139 at 390, 120 at 320, so the figure drops one line, flush with its word. ONE EXCEPTION, STATED: on a glass
 *  under 600 px tall (`short:`) a second line is 16 px the panel does not have — at 320×568 with the Influence book open the panel
 *  already scrolls 11 px inside itself and tests/consistency.spec.ts holds it to 12 — so the line stays one line, the label is cut and
 *  carries its full word as its `title` (the one place in the HQ this is so, the sizes the unfold laws do not name). */
function FigureLine({
  label,
  testid,
  children,
  ...rest
}: {
  label: string
  testid: string
  children: ReactNode
} & { 'data-stance'?: string; 'data-nation'?: string }) {
  return (
    <div className="flex min-h-5 items-center gap-x-2 py-0 leading-tight narrow:flex-wrap short:narrow:flex-nowrap" data-testid={testid} {...rest}>
      <span
        data-row-cell="label"
        title={label}
        className="shrink-0 text-t-caption text-ink-faint short:narrow:min-w-0 short:narrow:shrink short:narrow:truncate"
      >
        {label}
      </span>
      <span className="shrink-0 tabular-nums">{children}</span>
    </div>
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
