import { Bar } from '../../../components/ui'
import { boundForLabel, voyageFraction, whereLine, whereabouts } from '../../../domain/fleet'
import { PortFlag } from '../../../live/PortFlag'
import { portNameOf, useWorld } from '../../../live/worldStore'
import { useShellState } from '../../../app/shellState'
import { formatClock, formatRealShort } from '../../../lib/format'
import type { FleetView } from '../../../lib/rpc'
import { useT } from '../../../lib/i18n'

// WHERE SHE IS, AT THE HEAD OF TRADE (2026-11-11, the trade-flow slice; docs/dev-log/2026-11-11-trade-flow-1.md).
//
// At sea the Trade screen said nothing of the passage: it opened the market of the harbour her leg ended at (a stop for
// supplies on the way), named it "Not docked", and drew every card "Cargo full". One strip says it now, in one fixed box:
//
//   in port     In port · Lisbon
//   under way   to Yeosu · arrives 02:14 · 4m          and a bar of the miles sailed
//               (a far trip, on a leg to a stop:)  to Yeosu · next stop Saint-Louis 02:14 · 4m
//
// NOTHING HERE IS A SECOND READING. Which state she is in, and the words "to X", are `domain/fleet`'s one rule and one
// sentence (`whereabouts`, `whereLine`: the Map's fleet tray and the Fleets row read the same); the bar is `voyageFraction`,
// the two served distances; the clock is the served arrival instant of the leg she is on. The DESTINATION is the one thing
// the voyage does not name on a far trip, and it is read from her own queue (`boundFor`, domain/order), by Trade.tsx, which
// opens the board on the same city. The arrival at a far destination is not served, so it is not printed: on a leg to a stop
// the clock stands beside the stop it belongs to.
//
// HER HOLD IS NOT REPEATED HERE: the desk's strip prints it directly above (FleetStrip.tsx), and the owner's rule on this
// face is one readout, one home (2026-10-31, *"no info duplicate info needed"*).
//
// THE BOX IS ONE HEIGHT in both states (40 px: the words alone in port, the words over the thin bar under way), so the board
// under it does not move when she leaves or lands. It is a statement, not a control, so it is not held to the 44-px floor;
// the 4 px are the fold's (tests/layout.spec.ts: two whole goods above the bar on a phone).

export function TradeStatus({ fleet, dest }: { fleet: FleetView; dest: string | null }) {
  const t = useT()
  const { nowMs } = useShellState()
  const portByCode = useWorld((s) => s.portByCode)
  const nameOf = (code: string) => portNameOf(portByCode, code)
  const w = whereabouts(fleet)
  const fraction = voyageFraction(fleet)
  const box = 'mb-2 flex min-h-10 flex-col justify-center gap-1 rounded-md bg-surface-2 px-3 py-1'
  if (w.kind !== 'sailing') {
    return (
      <div className={box} data-testid="trade-status" data-state={w.kind}>
        <span className="flex flex-wrap items-baseline gap-x-2 text-t-label text-ink" data-testid="trade-status-line">
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
      <span className="flex flex-wrap items-baseline gap-x-2 text-t-label text-ink" data-testid="trade-status-line">
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
      {fraction !== null && <Bar pct={fraction * 100} tone="info" label={t('fleets.howFar')} />}
    </div>
  )
}
