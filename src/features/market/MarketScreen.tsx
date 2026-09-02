import { useCallback, useEffect, useMemo, useState } from 'react'
import type { ReactNode } from 'react'
import { useNavigate } from 'react-router-dom'
import {
  Badge,
  Button,
  Card,
  CardHeader,
  Explain,
  EntryTileLine,
  GoodTile,
  Input,
  Notice,
  PageHeader,
  Screen,
  Sparkline,
  SectionLabel,
  Skeleton,
  fineClass,
  tileFieldClass,
} from '../../components/ui'
import { formatInt, formatPct, formatTuns } from '../../lib/format'
import { fold, foldedMatch } from '../../lib/text'
import { useWorld } from '../../live/worldStore'
import { WorldFailed, WorldLoading } from '../../live/WorldGate'
import type {
  MarketGood,
  PriceHistory,
  PricePoint,
  Refusal,
  SnapshotPort,
} from '../../lib/rpc'
import { handOffTrade } from '../../domain/order'
import { housePortCode } from '../../domain/fleet'
// WHICH HARBOUR THIS HOUSE IS READING — one owner, shared with PORT; the MAP is its named next
// caller (src/store/harbour.ts carries the whole reasoning).
import { harbourCode, useHarbour } from '../../store/harbour'
// WHERE A GOOD IS WORTH MORE THAN IT IS HERE — a section, not this screen's. The Command tab's
// unfolded good row names the same destination from the same read, so the index moved out of
// ./marketRows into src/domain/trade rather than being copied across a screen boundary.
import {
  type MarketBlock,
  type MarketFilter,
  type SortKey,
  buyableHere,
  countRows,
  marketBlocks,
  sortWord,
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
// THE PRICES RIDE THE WORLD'S OWN CADENCE. The header's `read again` control is DELETED (the
// owner, 2026-08-23: "read again on top left of the game is useless. remove it") — AppShell
// already re-reads the world every thirty seconds and on every tab focus, and `readAt` is that
// read's stamp. This screen keys its market fetch on it, so the prices are re-asked on the same
// beat instead of waiting for a button that taught the player their tap did something the game
// was already doing. The re-ask is also what steps the drift walk where pg_cron is absent
// (migration 0029's contract), so the prices genuinely move while the tab is open.
//
// A MARKET THAT WOULD NOT LOAD still draws its own refusal with a retry. That one is not a world
// gate — it is a fact about ONE PORT, which WorldGate has nothing to say about. No state of this
// screen is an endless spinner.
//
// MOBILE: THE GOODS ARE TILES, NOT ROWS (the owner, 2026-08-23: "make trade goods in blocks as
// well, not all alligned in sentences — horizontally"). Seven columns never fit 390px and the
// table answered that with a sideways scroll, which hid the trend and the destination behind a
// swipe. `GoodTile` (design system) draws each good as a block — its own mark, its name, its
// rarity, the figures aligned beneath — in a two-column field, so nothing scrolls sideways and
// nothing is hidden. The whole tile is the tap target, ≥44px by construction.

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

  // WHICH HARBOUR — the ONE owner (src/store/harbour.ts), shared with PORT. This was a
  // component-local `chosenPortId` that died on every tab switch (pick Cádiz, check the fleet,
  // come back: Lisboa) while PORT persisted its own copy of the same choice — the seam both files
  // named on 2026-08-22 and this promotion closes. By port CODE, because that is the world's
  // stable name; the market fetch converts to id through `portByCode`.
  const picked = useHarbour((s) => s.picked)
  const pick = useHarbour((s) => s.pick)
  const [loadError, setLoadError] = useState<{ portId: string; refusal: Refusal | null } | null>(
    null,
  )
  const [sort, setSort] = useState<SortKey>('name')
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
  // The pick, else the player's port, else the first port of the world so that a house with no
  // fleet at all still opens on a real market — `harbourCode` is the ONE spelling of that
  // fallback, and PORT calls the same function.
  const portCode = harbourCode(picked, fleets, snapshot?.ports ?? [])
  const port = portCode ? (portByCode[portCode] ?? null) : null
  const portId = port?.id ?? null
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

  // KEYED ON `readAt`, DELIBERATELY (see the header). The world's own thirty-second read stamps
  // `readAt`; re-asking this port's prices on the same stamp is what keeps them live now that the
  // `read again` button is deleted. A port change re-asks immediately for the same reason. The
  // cached payload stays up while the fresh one is in flight, so nothing flickers.
  const readAt = useWorld((s) => s.readAt)
  useEffect(() => {
    if (!portId || readAt === null) return
    fetchMarket(portId)
  }, [portId, readAt, fetchMarket])

  // The remembered prices ride beside the live ones. A FAILED history read is deliberately silent
  // (worldStore.loadHistory swallows it): a market with no line is one whose record has not been
  // kept yet, which is a normal state on a young world rather than a failure worth a banner.
  useEffect(() => {
    if (!portId || history[portId]) return
    void loadHistory(portId)
  }, [portId, history, loadHistory])

  // 0071: THE COMPARISON USED TO BE READ HERE — a second call to world.trade_routes, cached per
  // port, that ranked every harbour in reach by what it would pay for what is on this quay. It is
  // gone with "where to sail" and "pays at", which were its two renderings.

  const config = snapshot?.config ?? null

  const blocks = useMemo(
    () => (view && config ? marketBlocks(view.goods, sort, filter) : []),
    [view, sort, filter, config],
  )

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
    if (!buyableHere(good)) return
    const verb = verbFor(good)
    handOffTrade({
      fleetId: fleetHere?.id ?? fleets[0]?.id ?? null,
      verb,
      goodCode: good.code,
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
                {sortWord(sort)} · {filter}
              </span>
              <span aria-hidden className="font-mono text-xs text-ink-faint">
                {optionsOpen ? '▴' : '▾'}
              </span>
            </button>
          </div>

          {portsOpen && (
            <PortPicker
              // Harbours only (0036): a SEA PLACE keeps no book, so a market picker offering the
              // Dogger Bank would open onto seventy rows of nothing. The SAIL picker still offers
              // every sea place — this filter is about what can be READ here, not where she may go.
              ports={(snapshot?.ports ?? []).filter((p) => p.kind === 'HARBOUR')}
              query={query}
              onQuery={setQuery}
              current={portCode}
              home={homePort}
              onPick={(code) => {
                pick(code)
                setPortsOpen(false)
              }}
            />
          )}

          {optionsOpen && (
            <div className="space-y-2 border-t border-edge pt-3">
              <div className="flex flex-wrap items-center gap-1.5">
                <SectionLabel className="mb-0">Sort</SectionLabel>
                {(['name', 'price', 'stock'] as const).map((k) => (
                  <Chip key={k} active={sort === k} onClick={() => setSort(k)}>
                    {sortWord(k)}
                  </Chip>
                ))}
              </div>
              <div className="flex flex-wrap items-center gap-1.5">
                <SectionLabel className="mb-0">Filter</SectionLabel>
                {/* 0071: these used to be all / buy / sell — the server's advice, offered as a
                    filter. What is left is the one FACT worth narrowing by: whether this city
                    deals in the row at all, or it is only here because she is carrying it. */}
                {(['all', 'traded'] as const).map((f) => (
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
              Try again
            </Button>
          </div>
        </Card>
      ) : !view ? (
        <SkeletonTable note={`Reading ${port?.name ?? 'the port'}'s prices.`} />
      ) : (
        /* THE DOCKED PANEL (docs/UI_DIRECTION.md §2). The goods are this screen's subject, so
           they wear the reference's panel: a full-bleed header bar over the body, parted by a gold
           hairline, with the count riding in the bar rather than floating in the padding.

           THE BAR HOLDS ONE LINE. A title, a dot and a count — nothing that wraps. The first cut
           of this put the tap-affordance line in the bar too and it grew to 100px, which cost two
           price rows above the fold; on a screen whose whole job is prices, the chrome does not
           get to eat them. The affordance moved into the body, where it is one small line. */
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
              aside={<Badge tone="accent">{countRows(blocks)} goods</Badge>}
            />
          }
        >
          <p className="mb-2 text-xs text-ink-muted">Tap a good to send it to Command.</p>
          {/* THE FIELD OF TILES — the owner's "blocks, not sentences". Each block heading keeps
              the band's own tone and threshold; under it the goods sit two abreast, every figure
              labelled in place, nothing behind a sideways swipe. The order inside each band is
              unchanged from the table it replaces (marketRows.ts owns it). */}
          <div className="space-y-4">
            {blocks.map((b) => (
              <GoodsBlock
                key={b.block}
                label={b.label}
                block={b.block}
                rows={b.rows}
                history={portId ? history[portId] : undefined}
                onTap={tap}
              />
            ))}
          </div>

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
                trade {view.port.dev_commerce}/10 · {view.port.culture} culture
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

      {/* 0071 — "WHERE TO SAIL" IS GONE. It ranked every port in reach by what it would pay for
          what is on this quay, which is the same comparison as the nearby index and the same
          answer: decision 3 of DESIGN_V1 §13, put to the owner and answered YES. A player finds
          the trade by carrying a cargo and remembering what it fetched. */}

      {/* THE RULE IS THE TITLE; THE ESSAY IS BEHIND THE DOT. The old title here was "Below 90,
          buy. Above 110, sell." — read as an instruction, followed, and it lost money. The nearby
          figure is a local price index and the title now says so; what names a trade is the panel
          above. ("nearby", never `%NBR` — the schema's name for the column, which the player
          never reads. COMMAND's good rows made the same call, for the same reason.) */}
      <Card tone="accent">
        <CardHeader
          eyebrow="How to read it"
          title="NEARBY says cheap HERE — not profitable."
          explain={
            <>
              The nearby figure is this port&rsquo;s price against the ports within{' '}
              {config?.neighbour_radius_nm ?? '—'} nm — high <em>here</em>, which is not a profit. A
              profit is two ports, two taxes, two spreads and what your own order does to the
              price. <strong>Pays at</strong> answers that, priced through the same quote
              your order executes at. Crew wages are not in it.
            </>
          }
        />
      </Card>
    </Screen>
  )
}

// ── the tiles ───────────────────────────────────────────────────────────────────────────────────

function GoodsBlock({
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
    <div>
      <p
        className={[
          'mb-1.5 border-b border-edge pb-1 font-mono text-[11px] uppercase tracking-wider',
          // 0071: the colour said cheap/dear, which was the advice. A block is a fact now, so the
          // heading is plain and only the block a player cannot trade in is faded.
          block === 'traded' ? 'text-ink-muted' : 'text-ink-faint',
        ].join(' ')}
      >
        ▾ {label}
      </p>
      <div className={tileFieldClass()}>
        {rows.map((good) => (buyableHere(good) ? (
          <TradedTile
            key={good.good_id}
            good={good}
            points={history?.goods[good.code]}
            onTap={onTap}
          />
        ) : (
          <UntradedTile key={good.good_id} good={good} />
        )))}
      </div>
    </div>
  )
}

function TradedTile({
  good,
  points,
  onTap,
}: {
  good: MarketGood
  /** The remembered mids for THIS good at THIS port, oldest first. Undefined while the history read
   *  is in flight, and absent for a good the record has never sampled — the Sparkline prints a dash
   *  for both, because "no record" is not "no movement" and neither of them is a line. */
  points: PricePoint[] | undefined
  /** Where this good is worth more than it is here, if anywhere in reach is (0019). Undefined
   *  while the read is in flight AND for a good no reachable port pays more for; the line prints
   *  a dash for both, because neither of those is a destination. */
  onTap: (good: MarketGood) => void
}) {
  return (
    <GoodTile
      code={good.code}
      category={good.category}
      name={good.name}
      rarity={good.rarity}
      onTap={() => onTap(good)}
      tapTitle={`${verbFor(good)} ${good.name} (${good.category}) — load onto Command`}
      testId="good-tile"
    >
      {/* 0071 — THE RANGE AND THE SHAPE OF WHERE IT HAS BEEN. This line was the neighbour index,
          the one figure that answered "is this cheap compared with everywhere else". The owner
          removed that answer twice over ("no nearby price info needed"; "the game is to challenge
          players for finding the best prices by themselves"), so what stands here is a fact about
          THIS price: the low and high the drift band allows it, at this quay, today.

          The sparkline keeps its neutral tone. It used to borrow the advice's colour, which made
          the shape of the past argue a case about the present. */}
      <EntryTileLine label="range">
        <span className="font-mono tabular-nums">
          {formatInt(good.range_lo)}–{formatInt(good.range_hi)}
        </span>
        <Sparkline
          width={44}
          values={(points ?? []).map((pt) => pt.mid)}
          tone="even"
          label={`${good.name}: ${points?.length ?? 0} remembered price(s)`}
        />
      </EntryTileLine>
      {/* TWO LINES, NOT ONE PAIR. `buy · sell — 364 · 334` wrapped mid-figure at 390px (measured:
          the pair plus its label is ~1px over a tile's 138px of content, and four-digit prices are
          well over). A figure is one token; two labelled lines cost the same height the wrap did
          and can never shear a number. */}
      <EntryTileLine label="buy">{formatInt(good.buy)}</EntryTileLine>
      <EntryTileLine label="sell">{formatInt(good.sell)}</EntryTileLine>
      <EntryTileLine label="stock">
        <span
          className="text-ink-muted"
          title={`${formatTuns(good.stock)} of a ${formatTuns(good.stock_target)} target`}
        >
          {stockBar(good.stock_band)}
        </span>
      </EntryTileLine>
    </GoodTile>
  )
}

/** §B.4 — the port's culture will not trade this good AT ALL. That is a fact about the port, so it
 *  is printed as one: the tile is struck through and dim, the prices are absent rather than zero,
 *  and there is nothing to tap because there is no order to hand over. */
function UntradedTile({ good }: { good: MarketGood }) {
  return (
    <GoodTile code={good.code} category={good.category} name={good.name} rarity={good.rarity} muted>
      <span className={fineClass()}>not traded here</span>
    </GoodTile>
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
  /** The harbour being read, by port CODE — src/store/harbour.ts's currency. */
  current: string | null
  home: SnapshotPort | null
  onPick: (code: string) => void
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
          <PortChip port={home} active={home.code === current} onPick={onPick} />
        </div>
      )}

      {listed.length === 0 ? (
        <p className="pt-2 text-sm text-ink-muted">
          No port matches. Clear the field for all {ports.length}.
        </p>
      ) : (
        <div className="flex flex-wrap gap-1.5 pt-2">
          {listed.map((p) => (
            <PortChip key={p.id} port={p} active={p.code === current} onPick={onPick} />
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
  onPick: (code: string) => void
}) {
  return (
    <Button
      variant={active ? 'chip-on' : 'chip'}
      onClick={() => onPick(port.code)}
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
