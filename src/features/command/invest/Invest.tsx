import { useState } from 'react'
import { Figure, Hint, Note, Row, SheetSection, Skeleton } from '../../../components/ui'
import { fleetPortCode } from '../../../domain/fleet'
import { CityTownHall } from '../../../live/CityTownHall'
import { WORK_NAME } from '../../../live/workNames'
import { PortFlag } from '../../../live/PortFlag'
import { useServedRead } from '../../../live/useServedRead'
import { useWorld } from '../../../live/worldStore'
import { formatDucats, formatDucatsDelta, formatInt } from '../../../lib/format'
import { worldHoldings, type FleetView, type Holdings } from '../../../lib/rpc'
import type { DeskLayout } from '../DeskFrame'

// INVEST — your money in the cities (docs/COMMAND_DESK.md §3.7, D6). The owner, 2026-10-17: *"… investing, and all"*.
//
//   Your holdings   world.holdings (0176): every (city, work) you hold — shares, what you paid, the coupons the city
//                   holds for you, a share's price there now — and the totals: held, owed, dividends collected
//                   today and in the last full day. Every figure served.
//   The Town Hall   of the city pressed, else the city the fleet is at: the purse and the day's money lines
//                   (Grant · Earnings · the crown · Paid by its people), its works and Invest — the ONE Town Hall
//                   (live/CityTownHall), which the map's city panel and City's Town face compose too. Invest runs
//                   only for a fleet docked there (the server refuses E_NOT_DOCKED; the hall says so).
//
// A row press SELECTS the city whose hall stands below; nothing above it moves.
//
// THE DESK LAYS IT OUT (DeskFrame.tsx, 2026-10-19): on a wide glass the holdings stand in the left pane,
// the Town Hall in the centre, and Invest / Donate (the hall's acts) in the right pane, the desk's slot;
// on a phone, one under the other, the act in flow.

export function Invest({ fleet, layout }: { fleet: FleetView; layout: DeskLayout }) {
  const portByCode = useWorld((s) => s.portByCode)
  const held = useServedRead<Holdings>('holdings', () => worldHoldings())
  const h = held.view
  const [picked, setPicked] = useState<string | null>(null)
  const hallCode = picked ?? fleetPortCode(fleet)
  const hall = hallCode ? (portByCode[hallCode] ?? null) : null

  return layout({
    testid: 'desk-invest',
    sideHint: "Press Invest on one of the Town Hall's works to buy its shares here.",
    list: (
      <SheetSection heading="Your holdings" data-testid="invest-holdings">
        {held.loading && !h ? (
          <Skeleton className="h-[120px] w-full" />
        ) : !h ? (
          <Note tone="danger">Your holdings could not be read.</Note>
        ) : (
          <>
            <div className="grid grid-cols-3 gap-3 pb-2" data-testid="invest-totals">
              <div className="min-w-0">
                <span className="block text-t-caption text-ink-faint">Held</span>
                <Figure value={formatDucats(h.held)} size="figure" />
              </div>
              <div className="min-w-0">
                <span className="block text-t-caption text-ink-faint">Paid today</span>
                <Figure value={formatDucatsDelta(h.paid.today)} tone={h.paid.today > 0 ? 'success' : 'muted'} size="figure" />
              </div>
              <div className="min-w-0">
                <span className="block text-t-caption text-ink-faint">Owed to you</span>
                <Figure value={formatDucats(h.owed)} size="figure" />
              </div>
            </div>
            <Hint>
              Yesterday the cities paid you {formatDucats(h.paid.yesterday)}. What they owe is paid when a fleet of yours
              docks there.
            </Hint>
            {h.rows.length === 0 ? (
              <Note tone="neutral" className="mt-2">
                {h.enabled ? 'You hold no shares yet. A city sells them in its Town Hall.' : 'City shares are not open yet.'}
              </Note>
            ) : (
              h.rows.map((r) => (
                <Row
                  key={`${r.port}:${r.kind}`}
                  onClick={() => setPicked(r.port)}
                  tone={r.port === hallCode ? 'accent' : 'default'}
                  mark={<PortFlag code={r.port} />}
                  label={`${r.name} · ${WORK_NAME[r.kind]}`}
                  value={
                    <span className="flex flex-col items-end">
                      <span className="whitespace-nowrap tabular-nums">{formatDucats(r.paid)}</span>
                      {r.owed > 0 && (
                        <span className="whitespace-nowrap text-t-caption tabular-nums text-success">
                          {formatDucatsDelta(r.owed)} owed
                        </span>
                      )}
                    </span>
                  }
                  data-testid="holding-row"
                >
                  <span className="block truncate text-t-caption text-ink-faint">
                    {formatInt(r.shares)} {r.shares === 1 ? 'share' : 'shares'} · level {r.level} / {r.level_max}
                    {r.share_price !== null ? ` · ${formatDucats(r.share_price)} a share now` : ''}
                  </span>
                </Row>
              ))
            )}
          </>
        )}
      </SheetSection>
    ),
    main:
      hall && hall.kind === 'HARBOUR' ? (
        <SheetSection
          heading={
            <span className="flex items-center gap-2">
              <PortFlag code={hall.code} />
              {hall.name} · Town Hall
            </span>
          }
          data-testid="invest-hall"
        >
          <CityTownHall key={hall.code} port={hall} />
        </SheetSection>
      ) : (
        <Note tone="neutral" className="mt-4">
          {fleet.name} is not at a city. Press a holding to read its Town Hall.
        </Note>
      ),
  })
}
