import type { ReactNode } from 'react'
import { Figure, Icon, Row, goodIcon } from '../../components/ui'
import { routeStopLines, type StopLine } from '../../domain/route'
import { portNameOf, useWorld } from '../../live/worldStore'
import type { StandingRouteStop } from '../../lib/rpc'

// ONE STOP OF A ROUTE — its port, what it SELLS, what it BUYS, and the quiet line under both.
//
// The owner, 2026-09-30: *"right now command sell all buy all is ... in one line and not
// distinguished which is confusing and looks very simple."* A stop was one faint caption —
// `Sell all · Buy Iron, 20 units, Max 12 🪙 each` — and the editor put `Sell all` and every
// `Buy <good>` in one row of identical chips.
//
// ── ONE SKELETON, TWO CALLERS (the ActCell precedent, src/components/ui/ActCell.tsx:5-11) ──────
// RouteFold draws a running route's stops READ-ONLY (`RouteStopFace`); RouteEditor draws the same
// block with its controls in the two groups. Both compose `RouteStopBlock`, so a stop has one shape
// whether it is being read or changed, and its height never depends on what it holds (an empty
// group is one quiet `Nothing` row).
//
// ── HOW SELL AND BUY ARE TOLD APART, WITHOUT COLOUR ────────────────────────────────────────────
// Green and red mean cheap/dear and gain/loss only (docs/UI_DIRECTION.md §4.4). So the trade
// face's own means are reused: a SIDE WORD printed once per group in a fixed left column, in the
// label voice of the ledger's `buy` / `sell` cells (TradeRow's ActCells); POSITION — sell always
// above buy, the order the server runs them in (0092 `cmd.standing_route_lines`); a HAIRLINE
// between the groups (the Row's own `border-edge`); the LIMIT'S VOICE — a buy caps (`Max`), a
// sell floors (`Min`, `Only sell above cost`); and each good's own MARK. Every word is
// src/domain/route's `routeStopLines`, which says each line through domain/order's
// `tradeLineWords` — the queue's rows say a route's orders through the same function.

/** One stop's block. `header` is the port (a Row, or the editor's port field); `sell` and `buy` are
 *  each group's body. */
export function RouteStopBlock({
  header,
  sell,
  buy,
  quiet,
  last,
  ...rest
}: {
  header: ReactNode
  sell: ReactNode
  buy: ReactNode
  quiet: string
  /** The last stop draws no parting hairline under itself. */
  last: boolean
} & { 'data-testid'?: string }) {
  return (
    <div className={last ? '' : 'border-b border-edge'} data-testid={rest['data-testid'] ?? 'route-stop'}>
      {header}
      <SideGroup side="Sell" data-testid="route-stop-sell">
        {sell}
      </SideGroup>
      <SideGroup side="Buy" divided data-testid="route-stop-buy">
        {buy}
      </SideGroup>
      <span className="block pb-2 text-t-caption text-ink-faint" data-testid="route-stop-quiet">
        {quiet}
      </span>
    </div>
  )
}

function SideGroup({
  side,
  divided = false,
  children,
  ...rest
}: {
  side: 'Sell' | 'Buy'
  divided?: boolean
  children: ReactNode
} & { 'data-testid'?: string }) {
  return (
    <div className={`flex gap-3 ${divided ? 'border-t border-edge' : ''}`} {...rest}>
      <span className="flex min-h-row w-10 shrink-0 items-center text-t-caption text-ink-muted">{side}</span>
      <div className="min-w-0 flex-1">{children}</div>
    </div>
  )
}

/** One trade line, read: the good's mark and name, how much under it, the limit on the right. */
export function StopLineRow({ line }: { line: StopLine }) {
  return (
    <Row
      mark={<Icon name={line.code ? goodIcon(line.code, line.category ?? '') : 'ship'} size={20} className="text-ink-muted" />}
      label={line.name}
      value={<Figure value={line.limit} tone="muted" />}
      hairline={false}
      data-testid="route-stop-line"
    >
      <span className="block text-t-caption text-ink-faint">{line.amount}</span>
    </Row>
  )
}

/** A group with no line still stands, so a stop's shape never depends on what it trades. */
export function NothingRow() {
  return <Row label="Nothing" tone="muted" hairline={false} />
}

/** A group's read lines, or `Nothing`. */
export function StopLines({ lines }: { lines: readonly StopLine[] }) {
  return lines.length === 0 ? <NothingRow /> : lines.map((l) => <StopLineRow key={l.key} line={l} />)
}

/** The port a stop is at, as the block's header. */
export function StopPortRow({ port }: { port: string }) {
  const portByCode = useWorld((s) => s.portByCode)
  return (
    <Row
      mark={<Icon name="anchor" size={20} className="text-ink-muted" />}
      label={portNameOf(portByCode, port)}
      hairline={false}
      data-testid="route-stop-port"
    />
  )
}

/** A running route's stop, read-only (RouteFold). */
export function RouteStopFace({ stop, last }: { stop: StandingRouteStop; last: boolean }) {
  const goodByCode = useWorld((s) => s.goodByCode)
  const { sell, buy, quiet } = routeStopLines(stop, goodByCode)
  return (
    <RouteStopBlock
      header={<StopPortRow port={stop.port} />}
      sell={<StopLines lines={sell} />}
      buy={<StopLines lines={buy} />}
      quiet={quiet}
      last={last}
    />
  )
}
