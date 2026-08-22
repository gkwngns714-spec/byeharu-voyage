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
  PriceIndex,
  Screen,
  Sparkline,
  SectionLabel,
  Skeleton,
  TABLE_SCROLL_HINT,
  TD,
  TH,
  Table,
  scrollTableClass,
} from '../../components/ui'
import { formatInt, formatPct, formatTuns } from '../../lib/format'
import { useWorld } from '../../live/worldStore'
import type {
  FleetView,
  MarketGood,
  PriceHistory,
  PricePoint,
  Refusal,
  SnapshotPort,
} from '../../lib/rpc'
import { handOffTrade } from '../../domain/order'
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
  const history = useWorld((s) => s.history)
  const loadHistory = useWorld((s) => s.loadHistory)
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

  // The remembered prices ride beside the live ones. A FAILED history read is deliberately silent
  // (worldStore.loadHistory swallows it): a market with no line is one whose record has not been
  // kept yet, which is a normal state on a young world rather than a failure worth a banner.
  useEffect(() => {
    if (!portId || history[portId]) return
    void loadHistory(portId)
  }, [portId, history, loadHistory])

  const blocks = useMemo(
    () => (view ? marketBlocks(view.goods, sort, filter) : []),
    [view, sort, filter],
  )

  const fleetHere = fleets.find((f) => port && f.port === port.code) ?? null
  const holdFree = fleetHere ? freeHold(fleetHere) : 0

  // THE ONE CALL INTO THE ORDER SECTION (domain/order). A row that the port refuses to trade is
  // not tappable: there is no order to hand over.
  //
  // BOTH SIDES HAND OVER `ALL`, AND NEITHER COMPUTES A MAXIMUM. This used to prefill a BUY with
  // the free hold, which ignored the purse — so the very first tap a new player made arrived on
  // Command already refused: "60 tuns of Black Pepper cost 8020 d. and you hold 8000". Twenty
  // ducats over, on a screen they had not touched yet.
  //
  // It was the THIRD copy of the rule D10 was written to kill ("two places computing a maximum,
  // both ignoring the price"). D10 fixed the MAX chip and `cmd.resolve_qty`; this one survived
  // because nothing pointed at it. The fix deletes the copy rather than correcting it: buy-side
  // `ALL` is resolved server-side through `public.fleet_buy_capacity()`, which walks the same
  // stepped book a committed trade walks and stops at whichever of hold, stock, daily cap or
  // PURSE binds first. `ALL` is read when the order RUNS, so it is still right after a voyage
  // that changed the hold.
  const tap = (good: MarketGood) => {
    if (!good.available) return
    const verb = good.advice === 'sell' ? 'SELL' : 'BUY'
    handOffTrade({
      fleetId: fleetHere?.id ?? fleets[0]?.id ?? null,
      verb,
      goodCode: good.code,
      qty: 'ALL',
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
        explain={`Every price is the server's, read against the ports within ${NEIGHBOUR_RADIUS_NM} nm. Orders execute in steps, each repricing — buying raises the price you are still buying at (§G.2). The server does that walk; these figures are today's opening ones.`}
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
        /* THE DOCKED PANEL (docs/UI_DIRECTION.md §2). The goods table is this screen's subject, so
           it wears the reference's panel: a full-bleed header bar over the body, parted by a gold
           hairline, with the row count riding in the bar rather than floating in the padding. */
        /* THE DOCKED PANEL (docs/UI_DIRECTION.md §2). The goods table is this screen's subject, so
           it wears the reference's panel: a full-bleed header bar over the body, parted by a gold
           hairline, with the row count riding in the bar rather than floating in the padding.

           THE BAR HOLDS ONE LINE. A title, a dot and a count — nothing that wraps. The first cut
           of this put the tap-affordance line in the bar too and it grew to 100px, which cost two
           price rows above the fold; on a screen whose whole job is rows, the chrome does not get
           to eat them. The affordance moved into the body, where it is one small line. */
        <Card
          head={
            <CardHeader
              flush
              title="Goods"
              explain="These are today's opening prices. An order executes in steps, each one repricing — buying raises the price you are still buying at (§G.2), and the server does that walk when the order runs. The TREND line is the remembered mid, sampled once per drift slot (0013) — the shape of the move, not its size; the figures beside it carry that. A good with no line is one the record has not sampled yet, which is the normal state of a world where nothing schedules the tick: local play keeps no cron, so lines fill in on the live server and stay empty here."
              aside={<Badge tone="accent">{countRows(blocks)} rows</Badge>}
            />
          }
        >
          <p className="mb-2 text-xs text-ink-muted">Tap a good to load the order onto Command.</p>
          <Table className={scrollTableClass()}>
            <thead>
              <tr>
                {/* %NBR IS SECOND, AND THAT IS THE WHOLE POINT.
                    It was sixth, and at 390px it fell off the right edge: the column the entire
                    game turns on — this port's price as a percentage of what its neighbours pay —
                    was the one you had to swipe to see, while `131` and `139`, which mean nothing
                    on their own, sat in plain view. The first column is sticky (tableLayout.ts),
                    so a column placed second is the last one guaranteed to be on screen without
                    scrolling. The prices did not get less important; they got less URGENT. */}
                <TH>Good</TH>
                <TH align="num">%NBR</TH>
                <TH align="num">Buy</TH>
                <TH align="num">Sell</TH>
                <TH>Stock</TH>
                {/* 0013 gave the market a memory, so the line this screen used to say it could not
                    draw is drawn. It sits after the figures because it is a SHAPE — the numbers
                    tell you the size of a move, the line tells you which way it has been going. */}
                <TH>Trend</TH>
                <TH>Note</TH>
              </tr>
            </thead>
            <tbody>
              {blocks.map((b) => (
                <BlockRows
                  key={b.block}
                  label={b.label}
                  block={b.block}
                  rows={b.rows}
                  history={portId ? history[portId] : undefined}
                  onTap={tap}
                />
              ))}
            </tbody>
          </Table>

          {/* WHAT STAYS PRINTED: the live reading of this quay and the swipe affordance. The two
              standing paragraphs that used to sit under them — how a stepped order reprices, and
              what the trend line is and is not — are behind the dot on the card's title. */}
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
          </dl>
        </Card>
      )}

      {/* THE RULE IS THE TITLE; THE ESSAY IS BEHIND THE DOT. A player who has learnt %NBR needs
          the threshold and nothing else, and they need it on every visit for the rest of the game.
          A player meeting it for the first time taps once. */}
      <Card tone="accent">
        <CardHeader
          eyebrow="How to read it"
          title={`Below ${ADVICE_BUY_BELOW}, buy. Above ${ADVICE_SELL_ABOVE}, sell.`}
          explain={
            <>
              The %NBR column is this port's price as a percentage of what the same good fetches in
              the ports within {NEIGHBOUR_RADIUS_NM} nm of it. It is the whole game in one column: it
              tells you nothing about whether a price is high, and everything about whether it is
              high <em>here</em>. Salt in {port?.name ?? 'a port'} is not cheap because salt is
              cheap; it is cheap because somebody two days' sail away will pay more for it.
            </>
          }
        />
      </Card>
    </Screen>
  )
}

// ── the rows ────────────────────────────────────────────────────────────────────────────────────

function BlockRows({
  label,
  block,
  rows,
  history,
  onTap,
}: {
  label: string
  block: MarketBlock
  rows: readonly MarketGood[]
  history: PriceHistory | undefined
  onTap: (good: MarketGood) => void
}) {
  return (
    <>
      <tr>
        <td colSpan={7} className="border-b border-edge px-2 pb-1 pt-4">
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
        <TradedRow
          key={good.good_id}
          good={good}
          points={history?.goods[good.code]}
          onTap={onTap}
        />
      ) : (
        <UntradedRow key={good.good_id} good={good} />
      )))}
    </>
  )
}

function TradedRow({
  good,
  points,
  onTap,
}: {
  good: MarketGood
  /** The remembered mids for THIS good at THIS port, oldest first. Undefined while the history read
   *  is in flight, and absent for a good the record has never sampled — the Sparkline prints a dash
   *  for both, because "no record" is not "no movement" and neither of them is a line. */
  points: PricePoint[] | undefined
  // No `block` prop any more. The row used to take it only to tint the %NBR figure, and the pill
  // now carries that meaning from the server's own `advice` (PriceIndex.tsx) — the band heading
  // and the pill were two renderings of one fact, and this was the copy that had to go.
  onTap: (good: MarketGood) => void
}) {
  return (
    <tr>
      <TD>
        {/* ONE LINE, NOT TWO. The category used to print under the name, which made every row
            62px and fitted four of them above the fold — the reference fits eleven. The category
            is a fact about the good, not about its price today, so it moved to the row's title
            (hover on a desktop, and the good's own name already implies it); what stays is the
            name and the 44px target the reach law requires. Four rows became seven. */}
        <button
          type="button"
          onClick={() => onTap(good)}
          title={`${good.advice === 'sell' ? 'SELL' : 'BUY'} ${good.name} (${good.category}) — load onto Command`}
          className="flex min-h-11 w-full items-center text-left"
        >
          <span className="block text-sm text-accent underline-offset-4 hover:underline">
            {good.name}
          </span>
        </button>
      </TD>
      {/* THE PILL, NOT A BARE FIGURE (docs/UI_DIRECTION.md §2). %NBR is the number the game is
          played from, and in the reference it rides directly behind the good's name as a coloured
          pill — the shape is what makes it scannable down a column of eleven rows. The tone is the
          SERVER'S `advice`; nothing here compares pct against a threshold. */}
      <TD align="num">
        <PriceIndex pct={good.pct_nbr} advice={good.advice} />
      </TD>
      <TD align="num">{formatInt(good.buy)}</TD>
      <TD align="num">{formatInt(good.sell)}</TD>
      <TD>
        <span
          className="font-mono text-xs text-ink-muted"
          title={`${formatTuns(good.stock)} of a ${formatTuns(good.stock_target)} target`}
        >
          {stockBar(good.stock_band)}
        </span>
      </TD>
      {/* THE LINE THIS SCREEN USED TO SAY IT COULD NOT DRAW. 0013 gave the market a memory; the
          tone is the server's own advice, so the line never introduces a fifth colour vocabulary. */}
      <TD>
        <Sparkline
          values={(points ?? []).map((pt) => pt.mid)}
          tone={good.advice === 'buy' ? 'cheap' : good.advice === 'sell' ? 'dear' : 'even'}
          label={`${good.name}: ${points?.length ?? 0} remembered price(s)`}
        />
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
      {/* No trend either, and for a better reason than "no data": a port whose culture refuses a
          good has never priced it, so there is nothing for the record to have remembered. */}
      <TD>
        <span className="font-mono text-[10px] text-ink-faint">—</span>
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
