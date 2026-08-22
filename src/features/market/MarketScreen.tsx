import { useCallback, useEffect, useMemo, useState } from 'react'
import type { ReactNode } from 'react'
import { useNavigate } from 'react-router-dom'
import {
  Badge,
  Button,
  Card,
  CardHeader,
  Explain,
  Input,
  Notice,
  PageHeader,
  PriceIndex,
  Screen,
  Sparkline,
  SectionLabel,
  Skeleton,
  TD,
  TH,
  Table,
  scrollTableClass,
  fineClass,
  rowLinkClass,
} from '../../components/ui'
import { formatInt, formatPct, formatTuns, formatVoyageDays } from '../../lib/format'
import { fold, foldedMatch } from '../../lib/text'
import { useWorld } from '../../live/worldStore'
import { ReadAgain, WorldFailed, WorldLoading } from '../../live/WorldGate'
import type {
  MarketGood,
  PriceHistory,
  PricePoint,
  Refusal,
  SnapshotPort,
  TradeRoute,
  TradeRoutes,
} from '../../lib/rpc'
import { handOffTrade } from '../../domain/order'
import { housePortCode } from '../../domain/fleet'
import {
  type MarketBlock,
  type MarketFilter,
  type SortKey,
  countRows,
  marketBlocks,
  routesByGood,
  stockBar,
  verbFor,
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
// %NBR IS A PRICE INDEX AND THIS SCREEN NO LONGER PRETENDS IT IS ADVICE. It used to print "Below
// 90, buy. Above 110, sell." as a rule to play by, and a playability audit did exactly that and
// LOST MONEY: %NBR compares a port with its own neighbours, so it can say a good is dear at Porto
// while carrying it there from Lisboa loses 77 ducats to tax, spread and the order's own price
// impact (migration 0019's header carries the measurement). The bands still cut the table — cheap
// here, dear here — and they are still worth seeing. What names a TRADE is the WHERE column and
// the panel under the table, both fed by `world.trade_routes()`, priced in ducats through the same
// quote the money moves at.
//
// THE "WHERE" COLUMN REPLACED A COLUMN THAT LIED. It used to print `glut` — on all seventy rows,
// at every port, because 0005 seeds stock at its target and 0010 clamps regeneration there, so a
// full warehouse is this world's resting state and `glut` was a false word for it. It was also a
// second rendering of the STOCK meter beside it, which is the duplication docs/DEV_LOG.md:305
// killed once already. The column now carries the thing the screen could not say.
//
// THE WORLD GATE IS IMPORTED, NEVER RE-SPELT. `WorldFailed` (src/live/WorldGate.tsx:24) and
// `WorldLoading` (src/live/WorldGate.tsx:70) are the two non-ready renderings that every tab
// reading the live world has, and FLEETS, LEDGER, PORT and RANK all compose them. This screen used
// to carry its own copies of BOTH — an inline `phase === 'failed'` Notice and a `MarketSkeleton` —
// which made four copies of one rule, the exact duplication docs/UI_DIRECTION.md §4 and the dev
// log's standing "one authority per concept" exist to forbid. The rejected alternative was to keep
// the local pair because their fallback sentences were market-flavoured ("…so there are no prices
// to read"): a better sentence is not worth a fourth authority for what a failed world looks like,
// and the shared one prints the refusal's own `fixes`, which the local copy silently dropped.
//
// WHAT IS STILL LOCAL, AND WHY IT HAS TO BE. The header's `read again` is NOT WorldGate's
// `ReadAgain` (src/live/WorldGate.tsx:110). That component hard-codes `world.refresh()` — fleets,
// ledger and house (src/live/worldStore.ts:208) — while this screen's read is `loadMarket(portId)`
// (src/live/worldStore.ts:229), one port's prices. Composing ReadAgain here would put a button on
// the prices screen that re-reads everything EXCEPT the prices, so it stays a local Button wearing
// ReadAgain's exact word and skin: two tabs may not grow two vocabularies for one affordance even
// while they cannot yet share the component.
//
// A MARKET THAT WOULD NOT LOAD still draws its own refusal with a retry. That one is not a world
// gate — it is a fact about ONE PORT, which WorldGate has nothing to say about. No state of this
// screen is an endless spinner.
//
// MOBILE: seven columns do not fit 390px, so the table scrolls INSIDE its own box (Table's
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
  const routes = useWorld((s) => s.routes)
  const loadRoutes = useWorld((s) => s.loadRoutes)
  const open = useWorld((s) => s.open)

  // LEFT COMPONENT-LOCAL, DELIBERATELY (2026-08-22). PORT persists the same choice to
  // sessionStorage (`features/port/portView.ts:21-25` names this as a seam rather than copying
  // it), so a player who picks Cadiz here, checks their fleet and comes back does land on Lisboa
  // again. The fix is NOT to reach into PORT's module — a screen may not import another screen,
  // and copying it would be the second author `portView.ts` was careful not to create. It is to
  // promote "which port is this house LOOKING at" into a section of its own, which is a change to
  // two screens and a new module and does not belong inside the trade-finding slice. Named here so
  // it is not lost.
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

  // WHERE THE PLAYER IS, not where an alphabet starts. `housePortCode` (src/domain/fleet) is the
  // ONE answer to "where does this house's next order happen" — a fleet alongside wins, and a fleet
  // at sea stands in with the port she is BOUND for, which is the next market she can trade in.
  // This screen used to spell that out itself as `portOfPlayer`; it was the fourth of four copies
  // and the last one left standing.
  const homePort = useMemo(() => {
    const code = housePortCode(fleets)
    return code ? (portByCode[code] ?? null) : null
  }, [fleets, portByCode])
  // The player's port first; the first port of the world only so that a house with no fleet at all
  // still opens on a real market rather than on nothing.
  const portId = chosenPortId ?? homePort?.id ?? snapshot?.ports[0]?.id ?? null
  const port = portId ? (snapshot?.ports.find((p) => p.id === portId) ?? null) : null
  const view = portId ? markets[portId] : undefined
  const fleetHere = fleets.find((f) => port && f.port === port.code) ?? null

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

  // THE COMPARISON. A separate read from the prices because it is a separate question, and a
  // separate cache key for the same reason. The fleet lying here is named when there is one: that
  // is what turns "50 tuns, say" into what she can actually afford, carry and sail to.
  const fleetHereId = fleetHere?.id ?? null
  useEffect(() => {
    if (!portId || routes[portId]) return
    void loadRoutes(portId, fleetHereId)
  }, [portId, routes, loadRoutes, fleetHereId])

  const config = snapshot?.config ?? null

  const blocks = useMemo(
    () => (view && config ? marketBlocks(view.goods, sort, filter, config) : []),
    [view, sort, filter, config],
  )

  const routeView = portId ? routes[portId] : undefined
  const routeOf = useMemo(() => routesByGood(routeView), [routeView])
  // THE SERVER'S FIGURE, AND THE END OF A THREE-YEAR-OLD LIE. This screen carried its own
  // `freeHold()` at the foot of the file — `Σ max(0, hold − cargo_tuns)` — which forgot that water
  // and food occupy the same hold, so a fleet provisioned for a long passage was told it had room
  // it did not have. Migration 0017 folded the server's four copies of this rule onto
  // `public.fleet_free_hold` and serves the answer; the client copy is deleted, not corrected,
  // because correcting it would have left a second authority that was merely right today.
  const holdFree = fleetHere?.free_hold ?? 0

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
    const verb = verbFor(good)
    handOffTrade({
      fleetId: fleetHere?.id ?? fleets[0]?.id ?? null,
      verb,
      goodCode: good.code,
      qty: 'ALL',
    })
    navigate('/command')
  }

  /** A tap on a route is a tap on its BUY: the same hand-off a tap on a price row makes, for the
   *  good the quay named. The destination is not composed into an order here — SAIL is its own
   *  verb and the Command tab is where a queue is built — so this loads the leg that has to happen
   *  first and the player composes the rest where orders are composed. */
  const tapRoute = (route: TradeRoute) => {
    handOffTrade({
      fleetId: fleetHere?.id ?? fleets[0]?.id ?? null,
      verb: 'BUY',
      goodCode: route.code,
      qty: 'ALL',
    })
    navigate('/command')
  }

  // THE GATE, COMPOSED. Two calls where there used to be an inline eighteen-line refusal and a
  // local `MarketSkeleton`. `panels={2}` stands in for the controls card and the goods panel,
  // which is what this screen actually opens with.
  if (phase === 'failed') {
    return <WorldFailed eyebrow="Trade" title="Market" refusal={fatal} />
  }

  if (phase !== 'ready') {
    return (
      <WorldLoading
        eyebrow="Trade"
        title="Market"
        subtitle="Opening the world."
        panels={2}
      />
    )
  }

  return (
    <Screen wide>
      <PageHeader
        eyebrow="Trade"
        title={`Market · ${port?.name ?? '—'}`}
        explain={`Every price is the server's, read against the ports within ${config?.neighbour_radius_nm ?? '—'} nm. These are opening figures: an order fills in steps and each step reprices, so buying raises the price you are still buying at.`}
        // THE SHARED CONTROL, driven by THIS screen's read. `ReadAgain` used to hard-code
        // `world.refresh()` — fleets, ledger and house — which on the prices screen would have
        // re-read everything EXCEPT the prices, so this screen carried a fifth hand-written copy
        // of the affordance instead. WorldGate now takes an optional `read`, so the copy is gone
        // and the word, the skin and the 44px floor are one authority again for all five tabs.
        actions={
          portId ? <ReadAgain read={() => fetchMarket(portId)} /> : undefined
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
            Nothing is guessed in their place.
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
              /* THE PROVENANCE WENT WITH THE PARAGRAPH. `§G.2` and `(0013)` are section and
                 migration numbers — facts about this repository, not about the game
                 (docs/UI_DIRECTION.md §4 rule 4). The repricing sentence also stood here AND on
                 the page header two panels up; one authority, so it stays on the header and the
                 card explains only what the card's own columns mean. */
              explain="TREND is the remembered mid price — the shape of the move, not its size; the figures beside it carry that. A good with no line has not been sampled yet: nothing schedules the tick in a browser-local world, so lines fill in on the live server and stay empty here."
              aside={<Badge tone="accent">{countRows(blocks)} rows</Badge>}
            />
          }
        >
          <p className="mb-2 text-xs text-ink-muted">Tap a good to send it to Command.</p>
          <Table scrollHint className={scrollTableClass()}>
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
                {/* THE COLUMN THAT USED TO SAY `glut` ON EVERY ROW. It now says where this good
                    is worth more than it is here, and what the voyage's margin would be — the
                    server's own `world.trade_routes`, priced through the quote a real order
                    executes at. An empty cell is an honest empty cell: no port in reach pays more
                    for it. */}
                <TH>Where it pays</TH>
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
                  routeOf={routeOf}
                  onTap={tap}
                />
              ))}
            </tbody>
          </Table>

          {/* WHAT STAYS PRINTED: the live reading of this quay and the swipe affordance. The two
              standing paragraphs that used to sit under them — how a stepped order reprices, and
              what the trend line is and is not — are behind the dot on the card's title. */}
          {/* FOUR FIGURES, NOT A SENTENCE ABOUT FOUR FIGURES. This line read "…dealer's spread
              2.6%, narrowed by how well this port is set up for trade (7 of 10) · culture latin",
              which spends fourteen words explaining a relationship between two numbers that are
              both printed. The numbers stay and line up; the relationship is behind the dot
              (docs/UI_DIRECTION.md §4 rules 2 and 4). */}
          <dl className={fineClass('mt-4 space-y-1')}>
            {view.port && (
              <div>
                tax {formatPct(view.port.tax_rate, 1)} · spread {formatPct(view.port.spread, 1)} ·
                trade {view.port.dev_commerce}/10 · {view.port.culture}
                <Explain label="tax and spread" dotClassName="ml-1">
                  Tax is the Mayor&rsquo;s cut of every deal. The spread is the gap between what
                  this port buys at and sells at, and it narrows as the port&rsquo;s trade grows.
                </Explain>
              </div>
            )}
            <div>
              {fleetHere
                ? `${fleetHere.name} is here — ${formatTuns(holdFree)} of hold free.`
                : 'No fleet of yours here. A tap will need one named on Command.'}
            </div>
          </dl>
        </Card>
      )}

      {/* THE ANSWER TO "WHAT DO I DO NOW", under the prices rather than over them: the goods table
          is still the subject of this screen and still owns the top of it. */}
      <RoutesPanel
        routes={routeView}
        portName={port?.name ?? 'this port'}
        fleetName={fleetHere?.name ?? null}
        onTap={tapRoute}
      />

      {/* THE RULE IS THE TITLE; THE ESSAY IS BEHIND THE DOT. The old title here was "Below 90,
          buy. Above 110, sell." — read as an instruction, followed, and it lost money. %NBR is a
          local price index and the title now says so; what names a trade is the panel above. */}
      <Card tone="accent">
        <CardHeader
          eyebrow="How to read it"
          title="%NBR says cheap HERE — not profitable."
          explain={
            <>
              %NBR is this port&rsquo;s price against the ports within{' '}
              {config?.neighbour_radius_nm ?? '—'} nm — high <em>here</em>, which is not a profit. A
              profit is two ports, two taxes, two spreads and what your own order does to the
              price. <strong>Where it pays</strong> answers that, priced through the same quote
              your order executes at. Crew wages are not in it.
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
  routeOf,
  onTap,
}: {
  label: string
  block: MarketBlock
  rows: readonly MarketGood[]
  history: PriceHistory | undefined
  routeOf: Record<string, TradeRoute>
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
          route={routeOf[good.code]}
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
  route,
  onTap,
}: {
  good: MarketGood
  /** The remembered mids for THIS good at THIS port, oldest first. Undefined while the history read
   *  is in flight, and absent for a good the record has never sampled — the Sparkline prints a dash
   *  for both, because "no record" is not "no movement" and neither of them is a line. */
  points: PricePoint[] | undefined
  /** Where this good is worth more than it is here, if anywhere in reach is (0019). Undefined
   *  while the read is in flight AND for a good no reachable port pays more for; the cell prints
   *  nothing for both, because neither of those is a destination. */
  route: TradeRoute | undefined
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
          title={`${verbFor(good)} ${good.name} (${good.category}) — load onto Command`}
          className="flex min-h-11 w-full items-center text-left"
        >
          <span className={rowLinkClass('block')}>
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
      {/* WHERE IT PAYS. One line, so the row height (and the count of rows above the fold that
          tests/layout.spec.ts pins) does not move. The port code and the margin in ducats, both
          the server's; the title carries the sentence. */}
      <TD>
        {route ? (
          <span
            className="font-mono text-xs text-success"
            title={`${route.qty} tun(s) to ${route.to.name} — ${formatInt(route.nm)} nm, ${route.legs} leg(s)${route.days === null ? '' : `, ${route.days} voyage-days`}: pay ${formatInt(route.outlay)} d. here, receive ${formatInt(route.proceeds)} d. there. Wages are not in that margin.`}
          >
            {route.to.code} +{formatInt(route.profit)}
          </span>
        ) : (
          <span className={fineClass()}>—</span>
        )}
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
        <span className={fineClass()}>not traded here</span>
      </TD>
    </tr>
  )
}

/**
 * WHERE TO SAIL — the answer this screen could not give until migration 0019.
 *
 * NOT A TABLE, deliberately. `tests/layout.spec.ts` measures every `<table>` on the tab for fit,
 * wrapping and reach, and counts the complete price rows above the fold; a second table here would
 * be a second thing competing for the same 390 px and the same measurements. These are rows of a
 * list, one tap target each, and they sit BELOW the goods table because the goods table is the
 * subject of this screen.
 *
 * EVERY NUMBER IS THE SERVER'S. `profit` is proceeds minus outlay at the stated quantity, both out
 * of `world.quote()`; `nm` is the distance actually sailed; `days` is her own speed. Nothing here
 * multiplies, divides or rounds a figure into a different figure — and where the server sent null
 * (no fleet named, so no speed and no days) the row prints the distance and stops.
 */
function RoutesPanel({
  routes,
  portName,
  fleetName,
  onTap,
}: {
  routes: TradeRoutes | undefined
  portName: string
  fleetName: string | null
  onTap: (route: TradeRoute) => void
}) {
  const shown = (routes?.routes ?? []).slice(0, 6)

  return (
    <Card
      head={
        <CardHeader
          flush
          title="Where to sail"
          explain="Every good this port sells, against every port in reach, priced end to end through the same quote your order executes at. The distance is the route actually sailed. The margin is the TRADE's — a voyage also pays its crew every day at sea, and that is not in it."
          aside={
            routes ? <Badge tone="accent">{routes.basis.routes_found} routes</Badge> : undefined
          }
        />
      }
    >
      {!routes ? (
        <div className="space-y-2">
          <Skeleton className="h-4 w-40" />
          <Skeleton className="h-8 w-full" />
          <Skeleton className="h-8 w-full" />
        </div>
      ) : shown.length === 0 ? (
        <p className="text-sm text-ink-muted">
          Nothing {portName} sells pays within {routes.basis.max_legs} leg(s) — not after tax,
          spread and your own price impact.
        </p>
      ) : (
        <ul className="divide-y divide-edge">
          {shown.map((r) => (
            <li key={`${r.good_id}-${r.to.id}`}>
              <button
                type="button"
                onClick={() => onTap(r)}
                title={`Load BUY ${r.name} onto Command`}
                className="flex min-h-11 w-full items-center gap-2 py-1.5 text-left"
              >
                <span className={rowLinkClass('flex-1 truncate')}>{r.name}</span>
                <span className="shrink-0 font-mono text-xs text-ink-muted">
                  → {r.to.name}
                </span>
                <span className="shrink-0 font-mono text-sm text-success">
                  +{formatInt(r.profit)}
                </span>
              </button>
              {/* SIX FACTS, NOT A SENTENCE ABOUT SIX FACTS. "pay 5,793 d. here, receive 7,001 d.
                  there" spent five words on an arrow; at 390px the line wrapped to three. The
                  figures are the row (docs/UI_DIRECTION.md §4 rule 2) and the words that told you
                  which way the money goes are now the arrow that shows it. */}
              <p className={fineClass('-mt-1 pb-1.5')}>
                {formatTuns(r.qty)} · {formatInt(r.outlay)} → {formatInt(r.proceeds)} d. ·{' '}
                {formatInt(r.nm)} nm
                {/* `${r.days} voyage-days` printed the raw served numeric — "13.01 d" beside a
                    game that says "15.0 d" everywhere else. `formatVoyageDays` is the one spelling
                    of a voyage-day (lib/format/time.ts:38) and this row was the last caller not
                    using it. */}
                {r.days === null ? '' : ` · ${formatVoyageDays(r.days)}`}
                {r.return_pct === null ? '' : ` · +${Math.round(r.return_pct)}%`}
              </p>
            </li>
          ))}
        </ul>
      )}

      {/* WHAT THE ANSWER WAS COMPUTED UNDER, printed rather than assumed. A profit without a
          quantity is not a number, and a search without a stated reach is not a search. */}
      {routes && (
        <dl className={fineClass('mt-3 space-y-1')}>
          <div>
            {routes.basis.qty_from === 'fleet'
              ? `Priced at what ${fleetName ?? 'your fleet'} can afford and carry.`
              : `No fleet of yours here, so priced at ${routes.basis.tuns} tuns a time.`}
          </div>
          <div>
            {/* The server reports null reach when a caller PINS a destination; this screen never
                does, and printing "null leg(s)" for a case that cannot arise is worse than not
                printing the sentence. */}
            {routes.basis.max_legs === null
              ? `${routes.basis.to ?? 'One port'} only · ${routes.basis.keep_per_good} destination(s) per good.`
              : `${routes.basis.ports_considered} port(s) within ${routes.basis.max_legs} leg(s) · ${routes.basis.keep_per_good} destination(s) per good.`}
          </div>
        </dl>
      )}
    </Card>
  )
}

// ── the port picker ─────────────────────────────────────────────────────────────────────────────

/**
 * EVERY PORT IN THE WORLD, AND NOTHING SHORT OF IT.
 *
 * This used to render `matches.slice(0, 40)` and print "40 of 214 ports — narrow the search." A
 * picker that admits it cannot reach two thirds of the world is not a picker, and the admission did
 * not make it one: a player who does not already know a port's name, its three-letter code or its
 * region code could not get to it at all, and 174 of the chain's 214 ports (data/ports.json) were
 * simply unreachable from MARKET. The cap is gone. Nothing is hidden and nothing is capped.
 *
 * WHY FILTERING RATHER THAN TRUNCATION, WHICH IS THE OTHER PICKER'S ANSWER. Command's pickers
 * (src/features/command/ArgPickers.tsx:24) stop at `MAX_ROWS = 12` and say how many more the filter
 * is hiding, and their header explains why: their rows are tall, they carry live figures, and there
 * is a filter box to narrow them with. This one is the same law reaching the opposite conclusion,
 * for a reason that is in the shape of the row rather than in the law: a port chip is a NAME, so a
 * hundred of them cost a column of taps rather than a column of paragraphs, and the choice being
 * made here — "which market am I reading?" — has no shortlist that is right for everybody. What
 * both files share is the part that actually matters: NEITHER puts an action inside something that
 * scrolls or clips it. There is no max-height here, no inner scroll box and no `overflow` of any
 * kind; the list grows the page, which is the only surface a thumb already knows how to move.
 *
 * THE ONE CONTROL THAT SHORTENS THE LIST IS `sticky`, and that is the reach law rather than a
 * flourish: with 214 chips the page is thousands of pixels long, so a filter field left in plain
 * flow would be the first thing to leave the screen and the only thing that could bring it back.
 * It stays pinned to the top of the panel for as long as the panel is on screen.
 *
 * ORDER: the fleet's own waters first, then the rest by region and name — the same "where the
 * player is, not where an alphabet starts" this screen already opens on (see :117). The port the
 * fleet is lying in also keeps its own pinned row, one tap away, above everything.
 */
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
  const needle = fold(query.trim())

  // NAME, CODE AND REGION, MATCHED THE ONE WAY. This used to fold nothing and compare with a bare
  // `toLowerCase()`, while Command's pickers accent-folded — so `sao` found São Vicente on one tab
  // and not on the other. The comment that stood here said what should happen and then did not do
  // it: "when one [carries a diacritic], `fold()` should be lifted somewhere both pickers can
  // import". It is lifted (src/lib/text/match.ts) and both import it.
  const listed = useMemo(() => {
    const matched = ports.filter((p) => foldedMatch(needle, p.name, p.code, p.region))
    const ownWaters = home?.region ?? null
    return [...matched].sort(
      (a, b) =>
        Number(b.region === ownWaters) - Number(a.region === ownWaters) ||
        a.region.localeCompare(b.region) ||
        a.name.localeCompare(b.name),
    )
  }, [ports, needle, home])

  return (
    <div className="border-t border-edge pt-3">
      {/* THE FIELD AND THE COUNT, OUT OF THE SCROLL. Bled to the panel's edges and painted with the
          panel's own token so the chips pass UNDER it rather than beside it — a translucent bar
          over a moving list is unreadable, and `bg-panel` is what Card.tsx:24 paints. */}
      <div className="sticky top-0 z-10 -mx-4 space-y-2 bg-panel px-4 pb-2 sm:-mx-5 sm:px-5">
        <Input
          size="sm"
          type="search"
          value={query}
          onChange={(e) => onQuery(e.target.value)}
          aria-label="Find a port by name, code or region"
          placeholder="Find a port by name, code or region"
          spellCheck={false}
          autoCorrect="off"
        />
        {/* WHAT IT SAYS IS TRUE OF WHAT IT SHOWS. The old line here claimed a limit; there is no
            limit left, so the line counts rather than apologises. */}
        <p className={fineClass()}>
          {needle
            ? `${listed.length} of ${ports.length} match.`
            : home
              ? `All ${ports.length} ports — ${home.region} first.`
              : `All ${ports.length} ports.`}
        </p>
      </div>

      {home && (
        <div className="flex flex-wrap items-center gap-1.5 pt-2">
          <SectionLabel className="mb-0">Your fleet</SectionLabel>
          <PortChip port={home} active={home.id === current} onPick={onPick} />
        </div>
      )}

      {listed.length === 0 ? (
        <p className="pt-2 text-sm text-ink-muted">
          No port matches. Clear the field for all {ports.length}.
        </p>
      ) : (
        <div className="flex flex-wrap gap-1.5 pt-2">
          {listed.map((p) => (
            <PortChip key={p.id} port={p} active={p.id === current} onPick={onPick} />
          ))}
        </div>
      )}
    </div>
  )
}

/** THE DESIGN SYSTEM'S CHIP, not a thirteenth hand-written copy of it. `chip`/`chip-on`
 *  (src/components/ui/buttonStyles.ts:35) exist because an audit on 2026-08-20 found TWELVE
 *  hand-rolled versions of these two recipes across Command, Market and Fleets, drifting in border
 *  colour and hover — and this button, with its own `bg-accent`/`border-edge` pair, was one of
 *  them. `size` is left at `md`, which is the 44px floor the reach law asks of a tap target;
 *  `sm` exists for in-row secondary actions and would not clear it. */
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
    <Button
      variant={active ? 'chip-on' : 'chip'}
      onClick={() => onPick(port.id)}
      // The code and the region are what the field above matches on, so the chip carries them
      // where a pointer can read them. They are not printed: 214 chips each carrying three facts
      // is a wall, and the name is the fact the player is looking for.
      title={`${port.code} · ${port.region}`}
      className="max-w-full font-mono"
    >
      {port.name}
    </Button>
  )
}

// ── the waiting state that is NOT a world gate ──────────────────────────────────────────────────

/** The world is open and the SCREEN is up; it is this one port's prices that have not landed yet.
 *  WorldGate's `WorldLoading` cannot serve here and must not be stretched to: it replaces the whole
 *  screen, and this placeholder sits inside a screen that is already showing its header, its port
 *  picker and its controls. The whole-screen twin of this (`MarketSkeleton`) WAS a copy of
 *  WorldLoading and is deleted. */
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

/** The SORT and FILTER tokens. Same primitive as PortChip above, for the same reason: one chip
 *  vocabulary per screen, and this one was reaching for `primary` — which docs/UI_DIRECTION.md §2
 *  reserves for the ONE brass action on a screen, not for four sort keys and three filters. Same
 *  `md` box, so nothing above the fold moves. */
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
    <Button variant={active ? 'chip-on' : 'chip'} onClick={onClick}>
      {children}
    </Button>
  )
}

// ── where the player is ────────────────────────────────────────────────────────────────────────
//
// DELETED 2026-08-22: `portOfPlayer` lived here and answered "which port does this house act in?"
// by reading `fleet.port ?? fleet.voyage?.to` down the fleet list. It was one of FOUR spellings of
// that question and the last one still standing; `housePortCode` (src/domain/fleet) is the
// authority, and this screen composes it at the top of the file. A picker is not a screen's and
// neither is a rule about fleets.
