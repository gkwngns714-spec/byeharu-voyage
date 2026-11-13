import { Bar } from '../../../components/ui'
import { boundForLabel, voyageFraction, whereLine, whereabouts } from '../../../domain/fleet'
import { PortFlag } from '../../../live/PortFlag'
import { portNameOf, useWorld } from '../../../live/worldStore'
import { useShellState } from '../../../app/shellState'
import { formatClock, formatRealShort } from '../../../lib/format'
import type { FleetView } from '../../../lib/rpc'
import { useT } from '../../../lib/i18n'
import { useTradeCity } from './tradeCity'

// WHERE SHE IS, ON TRADE (2026-11-11, the trade-flow slice; docs/dev-log/2026-11-11-trade-flow-1.md).
//
// At sea the Trade screen said nothing of the passage: it opened the market of the harbour her leg ended at (a stop for
// supplies on the way), named it "Not docked", and drew every card "Cargo full". One line says it now:
//
//   in port     In port · Lisbon
//   under way   to Yeosu · arrives 02:14 · 4m          and a bar of the miles sailed
//               (a far trip, on a leg to a stop:)  to Yeosu · next stop Saint-Louis 02:14 · 4m
//
// NOTHING HERE IS A SECOND READING. Which state she is in, and the words "to X", are `domain/fleet`'s one rule and one
// sentence (`whereabouts`, `whereLine`: the Map's fleet tray and the Fleets row read the same); the bar is `voyageFraction`,
// the two served distances; the clock is the served arrival instant of the leg she is on. The DESTINATION is the one thing
// the voyage does not name on a far trip: `useTradeCity` reads it from her own queue (`boundFor`, domain/order), and the
// board opens on the same city. The arrival at a far destination is not served, so it is not printed: on a leg to a stop
// the clock stands beside the stop it belongs to.
//
// HER HOLD IS NOT REPEATED HERE: the desk's strip prints it beside this line (FleetStrip.tsx), and the owner's rule on this
// face is one readout, one home (2026-10-31: no duplicate info).
//
// TWO PLACES, ONE COMPONENT, NO LINE OF THE PHONE'S GLASS:
//   wide     a strip at the head of Trade's left pane (40 px in both states, so nothing under it moves when she leaves or lands).
//   compact  the phone: two small lines at the right of her name, in the 44-px row the fleet picker already has
//            (CommandScreen.tsx, FleetStrip's `trailing`). The owner's one-page law (tests/onepage.spec.ts: the tab's own
//            sheet never scrolls) leaves the Trade face 22 px at 390×844, and a strip of its own is 48. With `board` (the
//            Trade face) the second line also says whose goods the board shows when it is not her port's: "Setubal · Not
//            docked", the line that used to appear and vanish above the cards, pushing them 30 px.

export function TradeStatus({ fleet, compact = false, board = false }: { fleet: FleetView; compact?: boolean; board?: boolean }) {
  const t = useT()
  const { nowMs } = useShellState()
  const portByCode = useWorld((s) => s.portByCode)
  const { dest, city } = useTradeCity(fleet)
  const nameOf = (code: string) => portNameOf(portByCode, code)
  const w = whereabouts(fleet)
  const fraction = voyageFraction(fleet)
  const box = compact
    ? 'relative ml-auto flex h-10 min-w-0 flex-col items-end justify-center pb-1 text-right'
    : 'mb-2 flex min-h-10 flex-col justify-center gap-1 rounded-md bg-surface-2 px-3 py-1'
  const line = compact ? 'flex flex-wrap items-baseline justify-end gap-x-1.5 text-t-caption text-ink' : 'flex flex-wrap items-baseline gap-x-2 text-t-label text-ink'
  const bar = compact ? 'absolute inset-x-0 bottom-0' : ''
  if (w.kind !== 'sailing') {
    // the board shows another city's goods than her port's: say so, here, where it moves nothing
    const away = compact && board && city !== null && w.kind === 'docked' && city !== w.port ? city : null
    return (
      <div className={box} data-testid="trade-status" data-state={w.kind}>
        <span className={line} data-testid="trade-status-line">
          {w.kind === 'docked' ? (
            <>
              <span className="text-ink-muted">{t('domain.inPort')}</span>
              <span className="font-semibold" data-testid="trade-status-place">
                <PortFlag code={w.port} /> {nameOf(w.port)}
              </span>
            </>
          ) : (
            <span className="font-semibold">{whereLine(w, nameOf)}</span>
          )}
        </span>
        {away && (
          <span className={`${line} text-ink-muted`} data-testid="trade-status-board">
            {nameOf(away)} · {t('desk.notDocked')}
          </span>
        )}
      </div>
    )
  }
  // the destination past the stops on the way, when her queue names one; else the voyage's own end
  const to = dest ?? w.to
  const stop = w.to !== null && w.to !== to ? w.to : null
  const eta = w.etaMs
  const clock = eta === null ? '—' : `${formatClock(eta)} · ${formatRealShort(eta - nowMs)}`
  return (
    <div className={box} data-testid="trade-status" data-state="sailing" data-to={to ?? ''} data-next={stop ?? ''}>
      <span className={line} data-testid="trade-status-line">
        <span className="font-semibold" data-testid="trade-status-place">
          {to && <PortFlag code={to} />} {whereLine({ ...w, to }, nameOf)}
        </span>
        {stop ? (
          <span className="text-ink-muted" data-testid="trade-status-next">
            {t('desk.nextStop', { city: boundForLabel(w, nameOf) })} <span className="tabular-nums">{clock}</span>
          </span>
        ) : (
          <span className="tabular-nums text-ink-muted" data-testid="trade-status-arrives">
            {t('desk.arrivesAt', { t: clock })}
          </span>
        )}
      </span>
      {fraction !== null && <Bar pct={fraction * 100} tone="info" label={t('fleets.howFar')} className={bar} />}
    </div>
  )
}
