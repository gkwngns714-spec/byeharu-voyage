import { useState } from 'react'
import { Icon, Note, Row, Skeleton, StatCell, Tray, type TrayDetent } from '../../components/ui'
import { InvestorRow } from '../../live/CityInvestors'
import { TownHallInfluence } from '../../live/TownHallInfluence'
import type { CityInvestor, Refusal, SnapshotPort, TownHallView } from '../../lib/rpc'
import { formatDucats, formatInt } from '../../lib/format'
import { useT } from '../../lib/i18n'
import { STEP_TONE, stepWords } from './populationWords'
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
// Population (0304: the SERVED population, `hall.people` — a real-world figure c. 1650 that grows, holds or
// shrinks every 10 minutes; under it the last step's arrow and why) · Gold (the hall's purse; under it the
// tax its people pay it a day) · Status
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

export function CityHallPanel({
  port,
  hall,
  refusal,
  employees,
  relation,
}: {
  port: SnapshotPort
  hall: TownHallView | null
  refusal: Refusal | null
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
      <CityPanel testId="city-hall-panel" title={t('city.cityHall')}>
        <Note tone="danger" code={refusal.code} figures={refusal.figures}>
          {refusal.sentence}
        </Note>
      </CityPanel>
    )
  }
  if (!hall) {
    return (
      <CityPanel testId="city-hall-panel" title={t('city.cityHall')}>
        <Skeleton className="h-24 w-full" />
      </CityPanel>
    )
  }

  const you = hall.influence.you
  const people = hall.people ?? null
  return (
    <CityPanel
      testId="city-hall-panel"
      scrollTestId="city-hall-scroll"
      title={t('city.cityHall')}
      footer={
        <>
          {/* INVESTORS — one real tappable row (44 px), pinned under the panel's scroll so it is
              always reachable, even on the smallest glass. The drawer it opens is the served
              board. */}
          <div className="mt-4 border-t border-edge">
            <button
              type="button"
              onClick={() => setInvestorsOpen(true)}
              data-testid="city-hall-investors"
              className="flex min-h-12 w-full items-center gap-2 pt-2 text-left text-ink-muted transition hover:text-ink"
            >
              <span className="text-t-label">{t('town.investors')}</span>
              <span className="shrink-0 text-t-label tabular-nums">{hall.investors.length}</span>
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
        className="flex min-h-12 w-full shrink-0 items-center gap-2 rounded-control border-b border-edge text-left text-ink-muted transition hover:text-ink"
      >
        <span className="text-t-label">{t('town.influence')}</span>
        <span className="shrink-0 text-t-label tabular-nums">{you ? formatInt(you.points) : null}</span>
        <Icon name="chevron" size={16} className={`ml-auto text-ink-faint transition ${influenceOpen ? 'rotate-180' : ''}`} />
      </button>
      {influenceOpen && (
        <div data-testid="city-hall-book">
          <TownHallInfluence port={port} influence={hall.influence} docked={hall.you.docked} showTax={false} compact />
        </div>
      )}

      {/* THE FIVE FIGURES — Population · Gold · Status · Relationship · Employees, at 24 px with their labels over them, two across
          (the page pattern's stacked figure; the hall is their single home, no other city face prints one of these words). */}
      <div data-testid="city-hall-figures" className="mt-5 grid grid-cols-2 gap-x-4 gap-y-5">
        <StatCell
          look="stacked"
          label={t('city.population')}
          text={people ? formatInt(people.population) : '—'}
          tone="ink"
          delta={people ? { text: stepWords(t, people), tone: STEP_TONE[people.kind] } : undefined}
          data-testid="city-population"
          data-population={people?.population ?? 'none'}
          data-kind={people?.kind ?? 'none'}
          data-reason={people?.reason ?? 'none'}
        />
        <StatCell
          look="stacked"
          label={t('city.gold')}
          text={formatDucats(hall.purse.ducats)}
          tone="ink"
          delta={people ? { text: t('city.perDay', { n: formatDucats(people.per_day) }), tone: 'muted' } : undefined}
          data-testid="city-gold"
          data-per-day={people?.per_day ?? 'none'}
        />
        <StatCell look="stacked" label={t('city.status')} text={you ? formatInt(you.points) : '—'} tone="ink" data-testid="city-status" />
        <StatCell look="stacked" label={t('city.employees')} text={formatInt(employees)} tone="ink" data-testid="city-employees" />
        <StatCell
          look="stacked"
          label={t('city.relationship')}
          text={relation.word}
          tone="ink"
          className="col-span-2"
          data-testid="city-relationship"
          data-stance={relation.stance ?? 'none'}
          data-nation={relation.nation ?? 'none'}
        />
      </div>
    </CityPanel>
  )
}

/** THE INVESTORS DRAWER — the design system's docked Tray: from 1,024 px it slides over the page's SIDE column (the same x and width, nothing behind it
 *  moves — the page pattern's tray, Tray.tsx reads the page), below it a sheet up from the bottom edge. Its own 44-px ✕ closes it and the served
 *  board scrolls inside it. (2026-11-04: it was the map's full-height `side` panel, 39 rem wide, over the plan as much as the panel.) */
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
