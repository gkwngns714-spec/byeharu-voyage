import { useCallback, useEffect, useMemo, useState } from 'react'
import type { ReactNode } from 'react'
import { useNavigate } from 'react-router-dom'
import {
  Badge,
  Button,
  Card,
  CardHeader,
  Notice,
  PageHeader,
  Screen,
  SectionLabel,
  Skeleton,
  TABLE_SCROLL_HINT,
  TD,
  TH,
  Table,
  scrollTableClass,
} from '../../components/ui'
import { formatInt, formatPct, formatPctPoints, formatTuns } from '../../lib/format'
import { useWorld } from '../../live/worldStore'
import type { FleetView, MarketGood, Refusal, SnapshotPort } from '../../lib/rpc'
import { handOffTrade } from './handOff'
import {
  ADVICE_BUY_BELOW,
  ADVICE_SELL_ABOVE,
  NEIGHBOUR_RADIUS_NM,
  type MarketBlock,
  type MarketFilter,
  type SortKey,
  countRows,
  marketBlocks,
  stockBar,
} from './marketRows'

// MARKET — §E.4, "the most important table in the game", and now A WINDOW ONTO THE SERVER'S PRICES
// rather than a second opinion about them.
//
// EVERY NUMBER ON THIS SCREEN CAME OVER THE WIRE. `world.market(port_uuid)` returns buy, sell,
// mid, %NBR, stock, stock_target, stock_band, `available` and `advice`, all derived inside the
// transaction that owns the row. `features/market/prices.ts` — which computed mid/ask/bid/%NBR
// here — is DELETED, because the price the money moves on is the server's and two authorities for
// a price is exactly what this project forbids. There is no arithmetic about money in this folder.
//
// %NBR IS STILL THE COLUMN THE GAME IS PLAYED FROM. The table is cut into the three bands and BUY
// sits at the top, so a player who knows nothing sees the two rows that pay without scrolling.
// The cutting lives in ./marketRows.ts and reads the server's `advice`; the screen renders it.
//
// A REFUSAL IS RENDERED, NEVER SPUN ON. `phase !== 'ready'` draws Skeletons; `phase === 'failed'`
// draws the fatal refusal; a market that would not load draws its own refusal with a retry. No
// state of this screen is an endless spinner.
//
// MOBILE: six columns do not fit 390px, so the table scrolls INSIDE its own box (Table's
// structural rule + scrollTableClass) and the page never moves sideways. The tap target is the
// FIRST column, which scrollTableClass pins — it can never be scrolled out of reach.

export function MarketScreen() {
  const navigate = useNavigate()
  const phase = useWorld((s) => s.phase)
  const fatal = useWorld((s) => s.fatal)
  const snapshot = useWorld((s) => s.snapshot)
  const fleets = useWorld((s) => s.fleets)
  const markets = useWorld((s) => s.markets)
  const portByCode = useWorld((s) => s.portByCode)
  const loadMarket = useWorld((s) => s.loadMarket)
  const open = useWorld((s) => s.open)

  const [chosenPortId, setChosenPortId] = useState<string | null>(null)
  const [loadError, setLoadError] = useState<{ portId: string; refusal: Refusal | null } | null>(
    null,
  )
  const [sort, setSort] = useState<SortKey>('nbr')
  const [filter, setFilter] = useState<MarketFilter>('all')
  const [portsOpen, setPortsOpen] = useState(false)
  const [optionsOpen, setOptionsOpen] = useState(false)
  const [query, setQuery] = useState('')

  // The store's open() is its own guard (it returns unless phase is 'idle'), so a tab opened
  // straight on /market still has a world to read. The shell calling it first makes this a no-op.
  useEffect(() => {
    void open()
  }, [open])

  // WHERE THE PLAYER IS, not where an alphabet starts: the market opens on the port the fleet is
  // lying in, and on the port it is sailing TO while at sea — the next market it can trade in.
  const homePort = useMemo(() => portOfPlayer(fleets, portByCode), [fleets, portByCode])
  // The player's port first; the first port of the world only so that a house with no fleet at all
  // still opens on a real market rather than on nothing.
  const portId = chosenPortId ?? homePort?.id ?? snapshot?.ports[0]?.id ?? null
  const port = portId ? (snapshot?.ports.find((p) => p.id === portId) ?? null) : null
  const view = portId ? markets[portId] : undefined

  // ONE read of one port's prices. `loadMarket` keeps its refusal in the store rather than
  // throwing, so the ABSENCE of the payload afterwards is how this screen learns the read failed —
  // and it learns it in the settle callback, never synchronously on the way into the effect.
  const fetchMarket = useCallback(
    (id: string) => {
      void loadMarket(id).then(() => {
        const state = useWorld.getState()
        setLoadError(state.markets[id] ? null : { portId: id, refusal: state.refusal })
      })
    },
    [loadMarket],
  )

  useEffect(() => {
    if (!portId || markets[portId]) return
    fetchMarket(portId)
  }, [portId, markets, fetchMarket])

  const blocks = useMemo(
    () => (view ? marketBlocks(view.goods, sort, filter) : []),
    [view, sort, filter],
  )

  const fleetHere = fleets.find((f) => port && f.port === port.code) ?? null
  const holdFree = fleetHere ? freeHold(fleetHere) : 0

  // THE ONE CALL INTO THE COMMAND FEATURE (./handOff.ts). A row that the port refuses to trade is
  // not tappable: there is no order to hand over.
  const tap = (good: MarketGood) => {
    if (!good.available) return
    const verb = good.advice === 'sell' ? 'SELL' : 'BUY'
    handOffTrade({
      fleetId: fleetHere?.id ?? fleets[0]?.id ?? null,
      verb,
      goodCode: good.code,
      qty: verb === 'SELL' ? 'ALL' : Math.max(1, Math.floor(holdFree)),
    })
    navigate('/command')
  }

  if (phase === 'failed') {
    return (
      <Screen wide>
        <PageHeader eyebrow="Trade" title="Market" />
        <Notice tone="danger">
          <span className="font-mono text-xs uppercase tracking-wider">
            {fatal?.code ?? 'E_WORLD_CLOSED'}
          </span>{' '}
          — {fatal?.sentence ?? 'The world could not be opened, so there are no prices to read.'}
        </Notice>
        {fatal?.detail && (
          <Card>
            <p className="font-mono text-[11px] text-ink-faint">{fatal.detail}</p>
          </Card>
        )}
      </Screen>
    )
  }

  if (phase !== 'ready') {
    return <MarketSkeleton note="Opening the world." />
  }

  return (
    <Screen wide>
      <PageHeader
        eyebrow="Trade"
        title={`Market · ${port?.name ?? '—'}`}
        subtitle={`Every price is the server's, read against the ports within ${NEIGHBOUR_RADIUS_NM} nm.`}
        actions={
          portId ? (
            <Button onClick={() => fetchMarket(portId)}>Read again</Button>
          ) : undefined
        }
      />

      {/* ── CONTROLS, FOLDED ─────────────────────────────────────────────────────────────────
          §K.1's beat is "MARKET tab. The BUY block is at the top; you did not have to know
          anything to see it." Chips for two hundred ports plus a SORT row plus a FILTER row would
          consume the whole first screenful and push the first price under the fold, so the
          controls collapse to ONE row: where you are, and how the table is arranged. */}
      <Card>
        <div className="space-y-3">
          <div className="flex flex-wrap items-center gap-2">
            <button
              type="button"
              onClick={() => setPortsOpen((v) => !v)}
              aria-expanded={portsOpen}
              className="flex min-h-11 items-center gap-2 rounded-md border border-edge bg-surface-2 px-3 text-sm text-ink transition hover:border-accent/60"
            >
              <span className="font-mono text-[10px] uppercase tracking-wider text-ink-faint">Port</span>
              <span className="font-mono text-sm text-accent">{port?.name ?? 'choose'}</span>
              <span aria-hidden className="font-mono text-xs text-ink-faint">
                {portsOpen ? '▴' : '▾'}
              </span>
            </button>
            <button
              type="button"
              onClick={() => setOptionsOpen((v) => !v)}
              aria-expanded={optionsOpen}
              className="ml-auto flex min-h-11 items-center gap-2 rounded-md border border-edge bg-surface-2 px-3 text-sm transition hover:border-accent/60"
            >
              <span className="font-mono text-xs text-ink-muted">
                {sort === 'nbr' ? '%↑' : sort} · {filter}
              </span>
              <span aria-hidden className="font-mono text-xs text-ink-faint">
                {optionsOpen ? '▴' : '▾'}
              </span>
            </button>
          </div>

          {portsOpen && (
            <PortPicker
              ports={snapshot?.ports ?? []}
              query={query}
              onQuery={setQuery}
              current={portId}
              home={homePort}
              onPick={(id) => {
                setChosenPortId(id)
                setPortsOpen(false)
              }}
            />
          )}

          {optionsOpen && (
            <div className="space-y-2 border-t border-edge pt-3">
              <div className="flex flex-wrap items-center gap-1.5">
                <SectionLabel className="mb-0">Sort</SectionLabel>
                {(['nbr', 'name', 'price', 'stock'] as const).map((k) => (
                  <Chip key={k} active={sort === k} onClick={() => setSort(k)}>
                    {k === 'nbr' ? '%↑' : k}
                  </Chip>
                ))}
              </div>
              <div className="flex flex-wrap items-center gap-1.5">
                <SectionLabel className="mb-0">Filter</SectionLabel>
                {(['all', 'buy', 'sell'] as const).map((f) => (
                  <Chip key={f} active={filter === f} onClick={() => setFilter(f)}>
                    {f}
                  </Chip>
                ))}
              </div>
            </div>
          )}
        </div>
      </Card>

      {loadError && loadError.portId === portId ? (
        <Card>
          <Notice tone="danger">
            <span className="font-mono text-xs uppercase tracking-wider">
              {loadError.refusal?.code ?? 'E_NO_MARKET'}
            </span>{' '}
            —{' '}
            {loadError.refusal?.sentence ??
              `The prices for ${port?.name ?? 'this port'} did not come back.`}{' '}
            Nothing is being guessed in their place.
          </Notice>
          <div className="mt-3">
            <Button variant="primary" onClick={() => fetchMarket(loadError.portId)}>
              Try the read again
            </Button>
          </div>
        </Card>
      ) : !view ? (
        <SkeletonTable note={`Reading ${port?.name ?? 'the port'}'s prices.`} />
      ) : (
        <Card>
          <CardHeader
            title="Goods"
            subtitle="Tap a good to load the order onto Command."
            aside={<Badge tone="accent">{countRows(blocks)} rows</Badge>}
          />
          <Table className={scrollTableClass()}>
            <thead>
              <tr>
                <TH>Good</TH>
                <TH align="num">Buy</TH>
                <TH align="num">Sell</TH>
                <TH align="num">%NBR</TH>
                <TH>Stock</TH>
                <TH>Note</TH>
              </tr>
            </thead>
            <tbody>
              {blocks.map((b) => (
                <BlockRows key={b.block} label={b.label} block={b.block} rows={b.rows} onTap={tap} />
              ))}
            </tbody>
          </Table>

          <dl className="mt-4 space-y-1 font-mono text-[11px] text-ink-faint">
            {view.port && (
              <div>
                tax {formatPct(view.port.tax_rate, 1)} · spread {formatPct(view.port.spread, 1)} at
                dev_commerce {view.port.dev_commerce} · culture {view.port.culture}
              </div>
            )}
            <div>
              {fleetHere
                ? `${fleetHere.name} is lying here with ${formatTuns(holdFree)} of hold free.`
                : 'No fleet of yours is in this port, so an order tapped here will need a fleet on Command.'}
            </div>
            <div>{TABLE_SCROLL_HINT}</div>
            <div>
              Orders execute in steps, each repricing — buying raises the price you are still buying
              at (§G.2). The server does that walk; these figures are today's opening ones.
            </div>
            {/* The one quiet line the deleted sparkline earned. */}
            <div>
              No seven-day line is drawn: a price history is a record that has to be kept before it
              can be shown, and nothing in the chain keeps one yet.
            </div>
          </dl>
        </Card>
      )}

      <Card tone="accent">
        <CardHeader
          eyebrow="How to read it"
          title={`Below ${ADVICE_BUY_BELOW}, buy. Above ${ADVICE_SELL_ABOVE}, sell.`}
        />
        <p className="text-sm text-ink-muted">
          The %NBR column is this port's price as a percentage of what the same good fetches in the
          ports within {NEIGHBOUR_RADIUS_NM} nm of it. It is the whole game in one column: it tells
          you nothing about whether a price is high, and everything about whether it is high{' '}
          <em>here</em>. Salt in {port?.name ?? 'a port'} is not cheap because salt is cheap; it is
          cheap because somebody two days' sail away will pay more for it.
        </p>
      </Card>
    </Screen>
  )
}

// ── the rows ────────────────────────────────────────────────────────────────────────────────────

function BlockRows({
  label,
  block,
  rows,
  onTap,
}: {
  label: string
  block: MarketBlock
  rows: readonly MarketGood[]
  onTap: (good: MarketGood) => void
}) {
  return (
    <>
      <tr>
        <td colSpan={6} className="border-b border-edge px-2 pb-1 pt-4">
          <span
            className={[
              'font-mono text-[11px] uppercase tracking-wider',
              block === 'buy'
                ? 'text-success'
                : block === 'sell'
                  ? 'text-accent'
                  : 'text-ink-faint',
            ].join(' ')}
          >
            ▾ {label}
          </span>
        </td>
      </tr>
      {rows.map((good) => (good.available ? (
        <TradedRow key={good.good_id} good={good} block={block} onTap={onTap} />
      ) : (
        <UntradedRow key={good.good_id} good={good} />
      )))}
    </>
  )
}

function TradedRow({
  good,
  block,
  onTap,
}: {
  good: MarketGood
  block: MarketBlock
  onTap: (good: MarketGood) => void
}) {
  const tone =
    block === 'buy' ? 'text-success' : block === 'sell' ? 'text-accent' : 'text-ink-muted'
  return (
    <tr>
      <TD>
        <button
          type="button"
          onClick={() => onTap(good)}
          title={`${good.advice === 'sell' ? 'SELL' : 'BUY'} ${good.name} — load onto Command`}
          className="min-h-11 w-full text-left"
        >
          <span className="block text-sm text-accent underline-offset-4 hover:underline">
            {good.name}
          </span>
          <span className="block font-mono text-[10px] text-ink-faint">{good.category}</span>
        </button>
      </TD>
      <TD align="num">{formatInt(good.buy)}</TD>
      <TD align="num">{formatInt(good.sell)}</TD>
      <TD align="num">
        <span className={tone}>
          {good.pct_nbr === null ? '—' : formatPctPoints(good.pct_nbr)}
        </span>
      </TD>
      <TD>
        <span
          className="font-mono text-xs text-ink-muted"
          title={`${formatTuns(good.stock)} of a ${formatTuns(good.stock_target)} target`}
        >
          {stockBar(good.stock_band)}
        </span>
      </TD>
      <TD>
        <span className="font-mono text-[11px] text-ink-faint">
          {good.stock_band <= 1 ? 'scarce' : good.stock_band >= 6 ? 'glut' : ''}
        </span>
      </TD>
    </tr>
  )
}

/** §B.4 — the port's culture will not trade this good AT ALL. That is a fact about the port, so it
 *  is printed as one: the row is struck through, the prices are absent rather than zero, and there
 *  is nothing to tap because there is no order to hand over. */
function UntradedRow({ good }: { good: MarketGood }) {
  return (
    <tr>
      <TD>
        <span className="block min-h-11 py-2 text-sm text-ink-faint line-through">{good.name}</span>
      </TD>
      <TD align="num">—</TD>
      <TD align="num">—</TD>
      <TD align="num">—</TD>
      <TD>
        <span className="font-mono text-xs text-ink-faint">——————</span>
      </TD>
      <TD>
        <span className="font-mono text-[11px] text-ink-faint">not traded here</span>
      </TD>
    </tr>
  )
}

// ── the port picker ─────────────────────────────────────────────────────────────────────────────

/** Two hundred ports is a list, not a chip row: it is filtered by name, code or region, and the
 *  port the player's fleet is in stays one tap away at the top. */
function PortPicker({
  ports,
  query,
  onQuery,
  current,
  home,
  onPick,
}: {
  ports: readonly SnapshotPort[]
  query: string
  onQuery: (q: string) => void
  current: string | null
  home: SnapshotPort | null
  onPick: (id: string) => void
}) {
  const needle = query.trim().toLowerCase()
  const matches = needle
    ? ports.filter(
        (p) =>
          p.name.toLowerCase().includes(needle) ||
          p.code.toLowerCase().includes(needle) ||
          p.region.toLowerCase().includes(needle),
      )
    : ports
  const shown = matches.slice(0, 40)

  return (
    <div className="space-y-2 border-t border-edge pt-3">
      <input
        type="search"
        value={query}
        onChange={(e) => onQuery(e.target.value)}
        placeholder="Find a port by name, code or region"
        className="min-h-11 w-full rounded-md border border-edge bg-surface-2 px-3 text-sm text-ink placeholder:text-ink-faint focus:border-accent/60 focus:outline-none"
      />
      {home && (
        <div className="flex flex-wrap items-center gap-1.5">
          <SectionLabel className="mb-0">Your fleet</SectionLabel>
          <PortChip port={home} active={home.id === current} onPick={onPick} />
        </div>
      )}
      <div className="flex flex-wrap gap-1.5">
        {shown.map((p) => (
          <PortChip key={p.id} port={p} active={p.id === current} onPick={onPick} />
        ))}
      </div>
      <p className="font-mono text-[11px] text-ink-faint">
        {matches.length > shown.length
          ? `${shown.length} of ${matches.length} ports — narrow the search.`
          : `${matches.length} port${matches.length === 1 ? '' : 's'}.`}
      </p>
    </div>
  )
}

function PortChip({
  port,
  active,
  onPick,
}: {
  port: SnapshotPort
  active: boolean
  onPick: (id: string) => void
}) {
  return (
    <button
      type="button"
      onClick={() => onPick(port.id)}
      className={[
        'min-h-11 rounded-md px-3 font-mono text-xs transition',
        active
          ? 'bg-accent text-app'
          : 'border border-edge bg-surface-2 text-ink-muted hover:text-ink',
      ].join(' ')}
    >
      {port.name}
    </button>
  )
}

// ── the waiting states ──────────────────────────────────────────────────────────────────────────

function MarketSkeleton({ note }: { note: string }) {
  return (
    <Screen wide>
      <PageHeader eyebrow="Trade" title="Market" subtitle={note} />
      <Card>
        <Skeleton className="h-11 w-full" />
      </Card>
      <SkeletonTable note={note} />
    </Screen>
  )
}

function SkeletonTable({ note }: { note: string }) {
  return (
    <Card>
      <CardHeader title="Goods" subtitle={note} />
      <div className="space-y-2">
        <Skeleton className="h-4 w-24" />
        {Array.from({ length: 8 }, (_, i) => (
          <Skeleton key={i} className="h-8 w-full" />
        ))}
      </div>
      <p className="sr-only" role="status">
        {note}
      </p>
    </Card>
  )
}

function Chip({
  active,
  onClick,
  children,
}: {
  active: boolean
  onClick: () => void
  children: ReactNode
}) {
  return (
    <Button variant={active ? 'primary' : 'secondary'} onClick={onClick}>
      {children}
    </Button>
  )
}

// ── where the player is ─────────────────────────────────────────────────────────────────────────

/** The port the market opens on: the one a fleet is lying in, or — at sea — the one it is sailing
 *  to, which is the next market that fleet can actually trade in. */
function portOfPlayer(
  fleets: readonly FleetView[],
  portByCode: Record<string, SnapshotPort>,
): SnapshotPort | null {
  for (const f of fleets) {
    if (f.port && portByCode[f.port]) return portByCode[f.port]
  }
  for (const f of fleets) {
    const to = f.voyage?.to
    if (to && portByCode[to]) return portByCode[to]
  }
  return null
}

/** Tuns the fleet can still take aboard — what a BUY is prefilled with. */
function freeHold(fleet: FleetView): number {
  return fleet.ships.reduce((n, s) => n + Math.max(0, s.hold - s.cargo_tuns), 0)
}
