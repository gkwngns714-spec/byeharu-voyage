import { useState } from 'react'
import { Figure, Icon, Note, Row, Skeleton, Tray, type TrayDetent } from '../../components/ui'
import { InvestorRow } from '../../live/CityInvestors'
import { TownHallInfluence } from '../../live/TownHallInfluence'
import type { CityInvestor, Refusal, SnapshotPort, TownHallView } from '../../lib/rpc'
import { formatDucats } from '../../lib/format'
import { useT } from '../../lib/i18n'
import { CityPanel } from './CityPanel'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE TOWN HALL, IN PLACE (owner, 2026-10-31)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, verbatim: *"the HQ tab, when pressed town hall, the city image you've created should
// show up. right now the city image is at center, move it the left side, and then at the right side
// show what you would see the page pop up,. no need market info. tax info. influence yes, investors
// - tappable where when tapped, a list slides to the right where you can close."* And, before this
// could be called done: *"you know that this game is also for mobile right?"*
//
// So the hall is the City page's MAIN PANEL, not a face: the plan stands LEFT, this panel RIGHT, at
// every glass. It composes the same served block the town hall face reads (`world.town_hall`):
//   · the city's TREASURY (the purse the hall's own core figure),
//   · the INFLUENCE book — with the tax rows off (`showTax={false}`): the owner cut tax info from
//     THIS view; the map's Town Hall and the desk's Invest still show it (they pass no switch),
//   · ONE tappable INVESTORS row; the served board opens a drawer from the RIGHT, full-width on a
//     phone, with its own close. The drawer is fixed over the page, so nothing behind it reflows
//     (the press law) — and the panel and the drawer scroll INSIDE themselves, never the page.
//
// NO market info (the hall's day book) and NO works/Invest here either: the owner did not ask for
// them in this panel, and the desk's Invest face and the map's Town Hall keep them whole.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

export function CityHallPanel({
  port,
  hall,
  refusal,
}: {
  port: SnapshotPort
  hall: TownHallView | null
  refusal: Refusal | null
}) {
  const t = useT()
  const [investorsOpen, setInvestorsOpen] = useState(false)

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

  return (
    <CityPanel
      testId="city-hall-panel"
      scrollTestId="city-hall-scroll"
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
              className="flex min-h-11 w-full items-center justify-between gap-2 py-2 text-left text-ink-muted transition hover:text-ink"
            >
              <span className="text-t-caption">{t('town.investors')}</span>
              <span className="flex items-center gap-1 text-t-caption tabular-nums">
                {hall.investors.length}
                <Icon name="chevron" size={16} className="text-ink-faint" />
              </span>
            </button>
          </div>
          {investorsOpen && <InvestorsDrawer investors={hall.investors} onClose={() => setInvestorsOpen(false)} />}
        </>
      }
    >
      <h2 className="pb-1 text-t-caption text-ink-faint">{t('city.cityHall')}</h2>
      <Row
        label={<span className="text-t-caption">{t('city.gold')}</span>}
        value={<Figure value={formatDucats(hall.purse.ducats)} size="figure" />}
        data-testid="city-hall-purse"
      />
      <h3 className="pb-1 pt-2 text-t-caption uppercase tracking-wider text-ink-faint">{t('town.influence')}</h3>
      <TownHallInfluence port={port} influence={hall.influence} docked={hall.you.docked} showTax={false} compact />
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
