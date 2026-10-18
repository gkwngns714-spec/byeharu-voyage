import { useState } from 'react'
import { Figure, Hint, Note, SheetSection, Skeleton } from '../../../components/ui'
import { fleetPortCode } from '../../../domain/fleet'
import { CityTownHall } from '../../../live/CityTownHall'
import { WORK_NAME } from '../../../live/workNames'
import { PortFlag } from '../../../live/PortFlag'
import { useServedRead } from '../../../live/useServedRead'
import { useWorld } from '../../../live/worldStore'
import { formatDucats, formatDucatsDelta, formatInt } from '../../../lib/format'
import { worldHoldings, type FleetView, type Holdings } from '../../../lib/rpc'

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

export function Invest({ fleet }: { fleet: FleetView }) {
  const portByCode = useWorld((s) => s.portByCode)
  const held = useServedRead<Holdings>('holdings', () => worldHoldings())
  const h = held.view
  const [picked, setPicked] = useState<string | null>(null)
  const hallCode = picked ?? fleetPortCode(fleet)
  const hall = hallCode ? (portByCode[hallCode] ?? null) : null

  return (
    <div data-testid="desk-invest">
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
                <button
                  key={`${r.port}:${r.kind}`}
                  type="button"
                  onClick={() => setPicked(r.port)}
                  aria-pressed={r.port === hallCode}
                  className={`flex min-h-row w-full items-center gap-3 border-b border-edge py-2 text-left`}
                  data-testid="holding-row"
                >
                  <span className="min-w-0 flex-1">
                    <span className={`flex items-center gap-2 truncate text-t-body ${r.port === hallCode ? 'text-accent' : 'text-ink'}`}>
                      <PortFlag code={r.port} />
                      {r.name} · {WORK_NAME[r.kind]}
                    </span>
                    <span className="block truncate text-t-caption text-ink-faint">
                      {formatInt(r.shares)} {r.shares === 1 ? 'share' : 'shares'} · level {r.level} / {r.level_max}
                      {r.share_price !== null ? ` · ${formatDucats(r.share_price)} a share now` : ''}
                    </span>
                  </span>
                  <span className="flex shrink-0 flex-col items-end">
                    <span className="whitespace-nowrap text-t-body tabular-nums text-ink">{formatDucats(r.paid)}</span>
                    {r.owed > 0 && (
                      <span className="whitespace-nowrap text-t-caption tabular-nums text-success">
                        {formatDucatsDelta(r.owed)} owed
                      </span>
                    )}
                  </span>
                </button>
              ))
            )}
          </>
        )}
      </SheetSection>

      {hall && hall.kind === 'HARBOUR' ? (
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
      )}
    </div>
  )
}
