import { useState, type ReactNode } from 'react'
import { Empty, Icon, Skeleton, Tray, TrayTitle, deltaTone, goodIcon, type TrayDetent } from '../components/ui'
import { CHART_CHROME, GoToLink } from '../chart'
import { useShellState } from '../app/shellState'
import { formatDucats, formatDucatsDelta, formatInt, formatRealShort } from '../lib/format'
import { worldFleetTrades, type FleetTrades, type TradeDay, type TradeLap, type TradeLine, type TradeStop } from '../lib/rpc'
import { portNameOf, useWorld } from './worldStore'
import { useServedRead } from './useServedRead'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// TRADE HISTORY — what a fleet bought and sold, lap by lap, and where (owner, 2026-10-15):
//
//   *"by clicking fleet, i want to be able to click on laps, so far, a lap and so on which tells me
//    what the ship has bought and sold, where it sold, and so on. info about trading."*
//
// A second side panel (`Tray mode="side-next"`), slid out from a merchant's sheet (MerchantSheet:
// the "So far"/"A day" and "A lap" tiles and each "Last laps" pill) or from your own fleet's tray
// (VoyageTray: its route's laps). The same slot ShipPanel opens in; one of the two at a time.
//
// ONE READ, `world.fleet_trades` (0121), asked while the panel is open. Every figure is the
// server's — the lap's books are the closer's own sums (0116's net), a stop's lines are what the
// executors returned, the day's goods are summed over the laps that keep their trades. Nothing is
// added up on this side of the wire (worldStore rule 3); the panel only lays it out.
//
// THE PICK is the caller's (it opened the panel on one), and the strip at the top switches it:
// the day, the lap under way, and the newest seven laps — the same seven as the sheet's pills, in
// the same order, so pill i is lap i here.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

export type TradePick = { kind: 'day' } | { kind: 'open' } | { kind: 'lap'; index: number }

export function TradeHistoryPanel({
  fleetId,
  pick,
  onPick,
  onClose,
}: {
  fleetId: string
  pick: TradePick
  onPick: (next: TradePick) => void
  onClose: () => void
}) {
  const [detent, setDetent] = useState<TrayDetent>('half')
  const read = useServedRead<FleetTrades>(fleetId, () => worldFleetTrades(fleetId))
  const t = read.view

  return (
    <Tray
      mode="side-next"
      detent={detent}
      onDetentChange={(next) => (next === 'closed' ? onClose() : setDetent(next))}
      title={<TrayTitle name="Trading" line={t?.route?.name ?? ''} testId="trade-history-name" />}
      data-testid="trade-history"
      {...CHART_CHROME}
    >
      {!t ? (
        read.loading ? (
          <Skeleton className="mt-2 h-40 w-full" />
        ) : (
          <Empty className="mt-2">No trading to show for this fleet.</Empty>
        )
      ) : !t.route ? (
        <Empty className="mt-2">She sails no route, so she keeps no laps.</Empty>
      ) : (
        <TradeBody t={t} pick={pick} onPick={onPick} />
      )}
    </Tray>
  )
}

function TradeBody({ t, pick, onPick }: { t: FleetTrades; pick: TradePick; onPick: (next: TradePick) => void }) {
  const lap = pick.kind === 'lap' ? t.laps[pick.index] : undefined
  return (
    <div data-testid="trade-history-body">
      <PickStrip t={t} pick={pick} onPick={onPick} />
      {pick.kind === 'day' && t.day && <DayView day={t.day} />}
      {pick.kind === 'open' && t.open && <OpenView open={t.open} />}
      {pick.kind === 'lap' && (lap ? <LapView lap={lap} /> : <Empty className="mt-2">That lap is no longer held.</Empty>)}
      {pick.kind === 'open' && !t.open && <Empty className="mt-2">No lap is under way — she is resting at home.</Empty>}
    </div>
  )
}

// ── THE STRIP: the day, the lap under way, the newest seven laps ─────────────────────────────────
function PickStrip({ t, pick, onPick }: { t: FleetTrades; pick: TradePick; onPick: (next: TradePick) => void }) {
  const chip = (on: boolean) =>
    [
      'flex min-h-11 shrink-0 flex-col items-start justify-center rounded-control px-3 py-1.5 text-left transition',
      on ? 'bg-accent-soft ring-1 ring-accent' : 'bg-surface-2 ring-1 ring-transparent hover:ring-ink-faint/30',
    ].join(' ')
  return (
    <div className="-mx-gutter overflow-x-auto px-gutter pb-1 pt-2" data-testid="trade-pick">
      <div className="flex gap-1.5">
        {t.day && (
          <button type="button" className={chip(pick.kind === 'day')} onClick={() => onPick({ kind: 'day' })} data-testid="trade-pick-day">
            <span className="text-t-caption text-ink-faint">{t.day.full ? 'A day' : 'So far'}</span>
            <span className={`text-t-caption tabular-nums ${TONE_TEXT[deltaTone(t.day.net)]}`}>{formatDucatsDelta(t.day.net)}</span>
          </button>
        )}
        {t.open && (
          <button type="button" className={chip(pick.kind === 'open')} onClick={() => onPick({ kind: 'open' })} data-testid="trade-pick-open">
            <span className="text-t-caption text-ink-faint">{`Lap ${formatInt(t.open.lap_no)}`}</span>
            <span className="text-t-caption text-accent">under way</span>
          </button>
        )}
        {t.laps.map((l, i) => (
          <button
            key={l.lap_no}
            type="button"
            className={chip(pick.kind === 'lap' && pick.index === i)}
            onClick={() => onPick({ kind: 'lap', index: i })}
            data-testid="trade-pick-lap"
          >
            <span className="text-t-caption text-ink-faint">{`Lap ${formatInt(l.lap_no)}`}</span>
            <span className={`text-t-caption tabular-nums ${TONE_TEXT[deltaTone(l.net)]}`}>{formatDucatsDelta(l.net)}</span>
          </button>
        ))}
      </div>
    </div>
  )
}

const TONE_TEXT: Record<string, string> = {
  success: 'text-success',
  danger: 'text-danger',
  ink: 'text-ink',
}

// ── ONE CLOSED LAP ───────────────────────────────────────────────────────────────────────────────
function LapView({ lap }: { lap: TradeLap }) {
  const { nowMs } = useShellState()
  const took = Date.parse(lap.closed_at) - Date.parse(lap.started_at)
  return (
    <div data-testid="trade-lap">
      <Plate
        net={lap.net}
        title={`Lap ${formatInt(lap.lap_no)}`}
        caption={`closed ${formatRealShort(nowMs - Date.parse(lap.closed_at))} ago · took ${formatRealShort(took)}`}
      />
      <Books b={lap} />
      <Heading trailing={lap.stops && <Faint>{`${lap.stops.length} ${lap.stops.length === 1 ? 'stop' : 'stops'}`}</Faint>}>
        Stops
      </Heading>
      {lap.stops ? (
        <Stops stops={lap.stops} />
      ) : (
        <Empty className="mt-2">Only the newest seven laps keep what was traded. This lap keeps its books above.</Empty>
      )}
    </div>
  )
}

// ── THE LAP UNDER WAY ────────────────────────────────────────────────────────────────────────────
function OpenView({ open }: { open: NonNullable<FleetTrades['open']> }) {
  const { nowMs } = useShellState()
  return (
    <div data-testid="trade-open">
      <div className="mt-2 rounded-sheet bg-gradient-to-br from-accent/15 via-surface-2 to-surface-2 p-4">
        <div className="text-t-caption uppercase tracking-wider text-ink-faint">{`Lap ${formatInt(open.lap_no)} · under way`}</div>
        <div className="mt-1 text-t-body text-ink">{`started ${formatRealShort(nowMs - Date.parse(open.started_at))} ago`}</div>
        <div className="mt-1 text-t-caption text-ink-faint">Her books close when she is home again.</div>
      </div>
      <Heading>So far</Heading>
      {open.stops.length > 0 ? <Stops stops={open.stops} /> : <Empty className="mt-2">Nothing traded yet this lap.</Empty>}
    </div>
  )
}

// ── THE DAY ──────────────────────────────────────────────────────────────────────────────────────
function DayView({ day }: { day: TradeDay }) {
  const { nowMs } = useShellState()
  const portByCode = useWorld((s) => s.portByCode)
  const caption =
    day.laps === 0
      ? 'no lap closed yet'
      : `${formatInt(day.laps)} ${day.laps === 1 ? 'lap' : 'laps'} ${
          day.full ? 'in the last real day' : day.since ? `over the last ${formatRealShort(nowMs - Date.parse(day.since))}` : ''
        }`
  // GROUPED BY HARBOUR, in the server's order — a grouping, not a sum.
  const ports: { port: string; goods: TradeDay['goods'] }[] = []
  for (const g of day.goods) {
    const last = ports[ports.length - 1]
    if (last && last.port === g.port) last.goods.push(g)
    else ports.push({ port: g.port, goods: [g] })
  }
  return (
    <div data-testid="trade-day">
      <Plate net={day.net} title={day.full ? 'A day' : 'So far'} caption={caption} />
      <Books b={day} />
      <Heading
        trailing={
          day.laps_traded < day.laps && <Faint>{`from the newest ${formatInt(day.laps_traded)} of ${formatInt(day.laps)} laps`}</Faint>
        }
      >
        Where she traded
      </Heading>
      {ports.length === 0 ? (
        <Empty className="mt-2">No trades are held for these laps.</Empty>
      ) : (
        <ol className="flex flex-col gap-2">
          {ports.map((p) => (
            <li key={p.port} className="rounded-control bg-surface-2 p-3" data-testid="trade-day-port">
              <PortHead code={p.port} name={portNameOf(portByCode, p.port)} />
              <div className="mt-2 grid grid-cols-[minmax(0,1fr)_auto_auto] gap-x-3 gap-y-1 text-t-caption">
                <span className="text-ink-faint">Good</span>
                <span className="text-right text-ink-faint">Sold</span>
                <span className="text-right text-ink-faint">Bought</span>
                {p.goods.map((g) => (
                  <DayGoodRow key={g.good} g={g} />
                ))}
              </div>
            </li>
          ))}
        </ol>
      )}
    </div>
  )
}

function DayGoodRow({ g }: { g: TradeDay['goods'][number] }) {
  const cell = (qty: number, total: number, sign: 1 | -1) =>
    qty > 0 ? (
      <span className="text-right tabular-nums">
        <span className={sign > 0 ? 'text-success' : 'text-ink'}>{formatDucatsDelta(sign * total)}</span>
        <span className="block text-ink-faint">{`${formatInt(qty)} units`}</span>
      </span>
    ) : (
      <span className="text-right text-ink-faint">—</span>
    )
  return (
    <>
      <GoodName code={g.good} />
      {cell(g.sold_qty, g.sold_total, 1)}
      {cell(g.bought_qty, g.bought_total, -1)}
    </>
  )
}

// ── SHARED PIECES ────────────────────────────────────────────────────────────────────────────────

/** THE NET, large, on ShipPanel's lit plate — green a profit, red a loss. */
function Plate({ net, title, caption }: { net: number; title: string; caption: string }) {
  const tone = deltaTone(net)
  const wash = tone === 'success' ? 'from-success/15' : tone === 'danger' ? 'from-danger/15' : 'from-accent/15'
  return (
    <div className={`mt-2 rounded-sheet bg-gradient-to-br ${wash} via-surface-2 to-surface-2 p-4`} data-testid="trade-net">
      <div className="text-t-caption uppercase tracking-wider text-ink-faint">{title}</div>
      <div className={`mt-1 text-t-title tabular-nums ${TONE_TEXT[tone]}`}>{formatDucatsDelta(net)}</div>
      <div className="mt-1 text-t-caption text-ink-faint">{caption}</div>
    </div>
  )
}

/** THE BOOKS — every term of the 0116 net, in the order it is written; a running cost that is
 *  nought is left out (a merchant's are, since 0116), the trading lines never are. */
function Books({
  b,
}: {
  b: Pick<TradeLap, 'sold' | 'bought' | 'supplies' | 'repairs' | 'wages' | 'stock_in' | 'stock_out' | 'net'>
}) {
  const rows: { label: string; value: number; sign: 1 | -1; always?: boolean; hint?: string }[] = [
    { label: 'Sold', value: b.sold, sign: 1, always: true },
    { label: 'Bought', value: b.bought, sign: -1, always: true },
    { label: 'Supplies', value: b.supplies, sign: -1 },
    { label: 'Repairs', value: b.repairs, sign: -1 },
    { label: 'Wages', value: b.wages, sign: -1, hint: 'paid from profit' },
    { label: 'Cargo carried in', value: b.stock_in, sign: -1, hint: 'bought last lap, sold in this one' },
    { label: 'Cargo carried out', value: b.stock_out, sign: 1, hint: 'on board at the close, sold next lap' },
  ]
  return (
    <section data-testid="trade-books">
      <Heading>Books</Heading>
      <dl className="rounded-control bg-surface-2 px-3 py-1">
        {rows
          .filter((r) => r.always || r.value !== 0)
          .map((r) => (
            <div key={r.label} className="flex items-baseline justify-between gap-3 border-b border-ink-faint/10 py-1.5">
              <dt className="min-w-0">
                <span className="block text-t-body text-ink">{r.label}</span>
                {r.hint && <span className="block text-t-caption text-ink-faint">{r.hint}</span>}
              </dt>
              <dd className={`shrink-0 text-t-body tabular-nums ${r.sign > 0 && r.value > 0 ? 'text-success' : 'text-ink'}`}>
                {formatDucatsDelta(r.sign * r.value)}
              </dd>
            </div>
          ))}
        <div className="flex items-baseline justify-between gap-3 py-2">
          <dt className="text-t-body font-semibold text-ink">Net</dt>
          <dd className={`text-t-body font-semibold tabular-nums ${TONE_TEXT[deltaTone(b.net)]}`}>{formatDucatsDelta(b.net)}</dd>
        </div>
      </dl>
    </section>
  )
}

/** EVERY STOP, in sailing order: the harbour, then what she sold and what she bought there. */
function Stops({ stops }: { stops: readonly TradeStop[] }) {
  const portByCode = useWorld((s) => s.portByCode)
  return (
    <ol className="flex flex-col gap-2" data-testid="trade-stops">
      {stops.map((s, i) => (
        <li key={`${s.port}-${i}`} className="rounded-control bg-surface-2 p-3" data-testid="trade-stop">
          <PortHead code={s.port} name={portNameOf(portByCode, s.port)} n={i + 1} />
          {s.sold.length === 0 && s.bought.length === 0 ? (
            <p className="mt-1.5 text-t-caption text-ink-faint">Called here and traded nothing.</p>
          ) : (
            <div className="mt-2 grid grid-cols-[minmax(0,1fr)_auto_auto_auto] gap-x-3 gap-y-1 text-t-caption">
              <span className="text-ink-faint">Good</span>
              <span className="text-right text-ink-faint">Qty</span>
              <span className="text-right text-ink-faint">Price</span>
              <span className="text-right text-ink-faint">Total</span>
              <Side label="Sold" lines={s.sold} sign={1} />
              <Side label="Bought" lines={s.bought} sign={-1} />
            </div>
          )}
        </li>
      ))}
    </ol>
  )
}

function Side({ label, lines, sign }: { label: string; lines: readonly TradeLine[]; sign: 1 | -1 }) {
  if (lines.length === 0) return null
  return (
    <>
      <span className={`col-span-4 mt-1 text-[0.6875rem] uppercase tracking-wider ${sign > 0 ? 'text-success' : 'text-ink-muted'}`}>
        {label}
      </span>
      {lines.map((l) => (
        <TradeLineRow key={`${label}-${l.good}`} l={l} sign={sign} />
      ))}
    </>
  )
}

function TradeLineRow({ l, sign }: { l: TradeLine; sign: 1 | -1 }) {
  return (
    <>
      <GoodName code={l.good} />
      <span className="text-right tabular-nums text-ink">{formatInt(l.qty)}</span>
      <span className="text-right tabular-nums text-ink-muted">{l.price === null ? '—' : formatDucats(l.price)}</span>
      <span className={`text-right tabular-nums ${sign > 0 ? 'text-success' : 'text-ink'}`}>{formatDucatsDelta(sign * l.total)}</span>
    </>
  )
}

function GoodName({ code }: { code: string }) {
  const good = useWorld((s) => s.goodByCode[code])
  return (
    <span className="flex min-w-0 items-center gap-1.5 text-ink">
      <Icon name={goodIcon(code, good?.category ?? '')} size={14} className="shrink-0 text-ink-faint" />
      <span className="truncate">{good?.name ?? code}</span>
    </span>
  )
}

function PortHead({ code, name, n }: { code: string; name: string; n?: number }) {
  return (
    <div className="flex items-center gap-2">
      {n !== undefined && (
        <span className="flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-accent/15 text-[0.6875rem] tabular-nums text-accent">
          {n}
        </span>
      )}
      <span className="truncate text-t-body text-ink">
        <GoToLink to={{ kind: 'port', code }}>{name}</GoToLink>
      </span>
    </div>
  )
}

function Heading({ children, trailing }: { children: ReactNode; trailing?: ReactNode }) {
  return (
    <div className="flex items-baseline justify-between gap-2 pb-2 pt-4">
      <h3 className="text-t-caption uppercase tracking-wider text-ink-faint">{children}</h3>
      {trailing}
    </div>
  )
}

function Faint({ children }: { children: ReactNode }) {
  return <span className="text-t-caption text-ink-faint">{children}</span>
}

