import { useEffect, useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import {
  Badge,
  Card,
  CardHeader,
  DetailRow,
  Notice,
  PageHeader,
  Screen,
  SectionLabel,
  TabRow,
  TABLE_SCROLL_HINT,
  TD,
  TH,
  Table,
  scrollTableClass,
} from '../../components/ui'
import { formatInt, formatNm, formatPct, formatPctPoints, formatTuns, formatVoyageDays } from '../../lib/format'
import { useWorld } from '../../live/worldStore'
import type { LiveWorld } from '../../live/worldStore'
import type { FleetView, MarketGood, MarketView, SnapshotPort, WorldSnapshot } from '../../lib/rpc'
import { useCommandDraft } from '../../domain/order'
import type { CommandIntent } from '../../domain/order'
import { findVerb, orderText } from '../../domain/order'
import { fleetCrew, fleetHoldFree, fleetMaxDraft, hullFraction, shipHoldUsed, worstHullFraction } from '../../domain/fleet'
import { WorldFailed, WorldLoading } from '../../live/WorldGate'

// PORT — E.3. Where you are, what is here, and what you can do about it.
//
// THE TEACHING MOVE: every action on this screen is printed AS THE ORDER IT WOULD ISSUE. There is
// no "Provision" button that does a thing; there is a line that reads `PROVISION Gaivota FULL`, and
// tapping it hands that order — verb and arguments — to the Command tab with its pickers already
// filled. A player who taps ten of these has read the language ten times without being taught it,
// and the line they read is the exact line the server is sent (F.4: there is one parser, and one
// composer on this side of the wire — orderText.ts).
//
// It also keeps law 2 intact: commands live on their own tab. This screen never issues anything.
//
// ── WHAT THIS HARBOUR CANNOT TELL YOU, AND WHY IT SAYS SO ───────────────────────────────────────
// The fixture port carried a price list this quay does not have. `world.snapshot()` serves a port's
// id, geography, development, `tax_rate` and `crew_pool` — and nothing else about its services
// (src/lib/db/README.md §4.3). NOT SERVED, and therefore NOT PRINTED:
//
//   crewRate · waterPrice · foodPrice · repairRate   the server prices HIRE / PROVISION / REPAIR
//                                                    when the order runs; only `cmd.preview()` can
//                                                    quote one, and previewing is Command's job.
//   crewPoolMax                                      so the Inn shows a count, not a meter: a bar
//                                                    needs a denominator and inventing one is a lie.
//   languages                                        not in the schema at all.
//   fleetsDocked                                     other houses' presence is V1 (J.3). YOUR hulls
//                                                    alongside are served, and that is what shows.
//   specialties                                      an authored affinity that never crosses the
//                                                    wire. Replaced by a REAL reading: the live
//                                                    market's %NBR and its buy/hold/sell advice.
//
// A row that would have to be invented is deleted, and the ones that are thinner than they look
// say why on screen. DESIGN's rule for this: never show a number you cannot defend.

/** The four faces of one place. Not a route: a port is one screen, and these are its sides. */
type PortFace = 'quay' | 'city' | 'services' | 'ships'

export function PortScreen() {
  const world = useWorld()

  if (world.phase === 'failed') {
    return <WorldFailed eyebrow="Harbour" title="Port" refusal={world.fatal} />
  }
  if (world.phase !== 'ready' || !world.snapshot) {
    return <WorldLoading eyebrow="Harbour" title="Port" subtitle="Where you are, and what is here." panels={3} />
  }
  return <PortBody world={world} snapshot={world.snapshot} />
}

function PortBody({ world, snapshot }: { world: LiveWorld; snapshot: WorldSnapshot }) {
  const navigate = useNavigate()
  const handOff = useCommandDraft((s) => s.handOff)
  const draftFleetId = useCommandDraft((s) => s.fleetId)
  const loadMarket = useWorld((s) => s.loadMarket)

  // There is no served "current port" — it is client UI state, and its natural default is where
  // the first fleet is lying (README §4.1). A fleet at sea leaves the harbour unchosen, so the
  // first port in the world stands in until the player picks one.
  const [picked, setPicked] = useState<string | null>(null)
  // WHICH FACE OF THE PORT IS TURNED TOWARDS YOU. It opens on the Quay — the things you can do —
  // rather than on the city's statistics, because an action is why a player opens a port screen.
  const [face, setFace] = useState<PortFace>('quay')
  const defaultCode = world.fleets.find((f) => f.port)?.port ?? snapshot.ports[0]?.code ?? null
  const portCode = picked ?? defaultCode
  const port = portCode ? (world.portByCode[portCode] ?? null) : null

  // The market is fetched per port, on demand — the store caches it, so this asks once per harbour.
  const portId = port?.id ?? null
  const market: MarketView | undefined = portId ? world.markets[portId] : undefined
  const marketLoaded = market !== undefined
  useEffect(() => {
    if (portId && !marketLoaded) void loadMarket(portId)
  }, [portId, marketLoaded, loadMarket])

  const draftOfClass = useMemo(() => {
    const byName = new Map(snapshot.ship_classes.map((c) => [c.name, c.draft]))
    return (className: string) => byName.get(className)
  }, [snapshot.ship_classes])

  const bulkOfGood = (code: string) => world.goodByCode[code]?.bulk ?? 1

  const docked = port ? world.fleets.filter((f) => f.port === port.code) : []
  const acting =
    docked[0] ?? world.fleets.find((f) => f.id === draftFleetId) ?? world.fleets[0] ?? null
  const homeCode = world.fleets.find((f) => f.port)?.port ?? null

  // A hand-off is a structured INTENT (commandDraft.ts) — orders are MADE, not typed. The LINE
  // shown on the button is the one the server will receive, composed by the one function that
  // composes it (orderText.ts, walking `snapshot.verbs`). The screen does not write order strings
  // of its own: two composers would eventually print a line the parser rejects.
  const command = (intent: CommandIntent) => {
    handOff({ fleetId: acting?.id ?? null, ...intent })
    navigate('/command')
  }
  const lineOf = (intent: CommandIntent): string => {
    const spec = findVerb(snapshot.verbs, intent.verb ?? null)
    return spec ? orderText(spec, intent.args ?? {}, acting?.name ?? null) : (intent.verb ?? '')
  }

  if (!port) {
    return (
      <Screen>
        <PageHeader eyebrow="Harbour" title="Port" subtitle="No harbour to read." />
        <Notice tone="warning">The world served no ports. Nothing here is a harbour yet.</Notice>
      </Screen>
    )
  }

  // The legs the SERVER authored out of this port — with its own sailed `nm`, which includes the
  // detour around land. The client used to great-circle this itself; the server's figure is the one
  // the voyage is actually costed on (README §4.4), so it is the one printed.
  const oneLeg = snapshot.legs
    .filter((leg) => leg.from === port.code || leg.to === port.code)
    .map((leg) => ({
      code: leg.from === port.code ? leg.to : leg.from,
      nm: leg.nm,
    }))
    .map(({ code, nm }) => ({ port: world.portByCode[code] ?? null, code, nm }))
    .sort((a, b) => a.nm - b.nm)

  const cheapHere = market
    ? market.goods
        .filter((g) => g.available && g.pct_nbr !== null)
        .sort((a, b) => (a.pct_nbr ?? 0) - (b.pct_nbr ?? 0))
        .slice(0, 3)
    : []
  const worthBuying = market ? market.goods.filter((g) => g.available && g.advice === 'buy').slice(0, 4) : []

  return (
    <Screen>
      <PageHeader
        eyebrow="Harbour"
        title={`Port · ${port.name}`}
        subtitle={`${port.country} · ${port.culture} · ${port.sea}`}
        actions={<Badge tone="neutral">draft {port.max_draft}</Badge>}
      />

      {homeCode && port.code !== homeCode && (
        <Notice tone="warning" className="text-xs">
          You are not lying in {port.name} — this is what your factors report from there. Your
          nearest fleet is at {world.portByCode[homeCode]?.name ?? homeCode}.
        </Notice>
      )}

      {/* ONE PLACE WITH FACES, NOT FOUR CARDS DOWN A PAGE (docs/UI_DIRECTION.md §2).
          The reference draws a port as a single panel with 기본/교역/시설/투자 along its top. This
          screen used to be four sibling Cards, which at 390px meant the fourth began ~1,200px down
          and was, in practice, never read. Same content, same order lines, one panel.

          THE                 {acting && (
                  <div className="space-y-4">
                    <ActionGroup
                      label="Stores and hands"
                      actions={[
                        {
                          intent: { verb: 'PROVISION', args: { mode: 'FULL' } },
                          note: `${formatVoyageDays(acting.endurance_days)} of range at present`,
                        },
                        {
                          intent: { verb: 'HIRE', args: { count: String(hireCount(acting, port)) } },
                          note: `${formatInt(fleetCrew(acting).aboard)} of ${formatInt(fleetCrew(acting).max)} berths filled · ${formatInt(port.crew_pool)} hands in the pool`,
                        },
                        ...(port.has_yard
                          ? [
                              {
                                intent: { verb: 'REPAIR', args: { to_pct: '100' } },
                                note: `worst hull ${formatPct(worstHullFraction(acting))} · tier ${port.yard_tier} yard`,
                              },
                            ]
                          : []),
                      ]}
                      lineOf={lineOf}
                      onPick={command}
                    />

                    <ActionGroup
                      label={marketLoaded ? 'What this market says to buy' : 'Trade'}
                      actions={
                        marketLoaded
                          ? worthBuying.map((good) => ({
                              intent: {
                                verb: 'BUY',
                                // CODES, never display names: `cmd.parse()` splits on whitespace.
                                args: { good: good.code, qty: String(affordableUnits(acting, bulkOfGood(good.code))) },
                              },
                              note: `${buyNote(good)} · ${formatTuns(fleetHoldFree(acting), 0)} free in the hold`,
                            }))
                          : []
                      }
                      empty={
                        marketLoaded
                          ? 'This market is not advising a purchase here — read the Market tab for the whole list.'
                          : 'Reading the market…'
                      }
                      lineOf={lineOf}
                      onPick={command}
                    />

                    <ActionGroup
                      label="One leg from here"
                      actions={oneLeg.slice(0, 6).map(({ port: p, code, nm }) => ({
                        intent: { verb: 'SAIL', args: { dest: code } },
                        note: `${formatNm(nm)} · ${
                          p === null
                            ? 'unknown harbour'
                            : p.max_draft < fleetMaxDraft(acting, draftOfClass)
                              ? 'too shallow for this fleet'
                              : `draft ${p.max_draft}`
                        }`,
                      }))}
                      empty="No authored leg leaves this port."
                      lineOf={lineOf}
                      onPick={command}
                    />
                  </div>
                )} IS THE FIRST FACE, deliberately. §3a's second trap is "the action lives on the
          wrong screen" — the most-praised patch in that game's four-year convenience backlog added
          no feature at all, it moved an action to the screen where the need arises. What you can
          DO here opens first; what the city IS is one tap away. */}
      <Card
        head={
          /* No eyebrow and no draft badge here: the PageHeader above already carries both, and
             this panel sits directly beneath it. One fact, one place — the same rule that took the
             purse off two screens in D12. */
          <CardHeader
            flush
            title="The quayside"
            explain="Everything this port is, and everything you can do while lying in it. Nothing on any face issues an order — the Quay prints each one as the exact line it would become and hands it to Command."
          />
        }
      >
        <TabRow
          label="Port faces"
          value={face}
          onChange={setFace}
          className="mb-3"
          tabs={[
            { id: 'quay', label: 'Quay' },
            { id: 'city', label: 'City' },
            { id: 'services', label: 'Services' },
            { id: 'ships', label: 'Alongside', hint: docked.length || undefined },
          ]}
        />

        <div role="tabpanel">
          {face === 'quay' && (
            <>
              {acting && (
                <p className="mb-3 text-xs text-ink-muted">
                  Tap one to load it onto Command as {acting.name}&apos;s order.
                </p>
              )}
                {acting && (
                  <div className="space-y-4">
                    <ActionGroup
                      label="Stores and hands"
                      actions={[
                        {
                          intent: { verb: 'PROVISION', args: { mode: 'FULL' } },
                          note: `${formatVoyageDays(acting.endurance_days)} of range at present`,
                        },
                        {
                          intent: { verb: 'HIRE', args: { count: String(hireCount(acting, port)) } },
                          note: `${formatInt(fleetCrew(acting).aboard)} of ${formatInt(fleetCrew(acting).max)} berths filled · ${formatInt(port.crew_pool)} hands in the pool`,
                        },
                        ...(port.has_yard
                          ? [
                              {
                                intent: { verb: 'REPAIR', args: { to_pct: '100' } },
                                note: `worst hull ${formatPct(worstHullFraction(acting))} · tier ${port.yard_tier} yard`,
                              },
                            ]
                          : []),
                      ]}
                      lineOf={lineOf}
                      onPick={command}
                    />

                    <ActionGroup
                      label={marketLoaded ? 'What this market says to buy' : 'Trade'}
                      actions={
                        marketLoaded
                          ? worthBuying.map((good) => ({
                              intent: {
                                verb: 'BUY',
                                // CODES, never display names: `cmd.parse()` splits on whitespace.
                                args: { good: good.code, qty: String(affordableUnits(acting, bulkOfGood(good.code))) },
                              },
                              note: `${buyNote(good)} · ${formatTuns(fleetHoldFree(acting), 0)} free in the hold`,
                            }))
                          : []
                      }
                      empty={
                        marketLoaded
                          ? 'This market is not advising a purchase here — read the Market tab for the whole list.'
                          : 'Reading the market…'
                      }
                      lineOf={lineOf}
                      onPick={command}
                    />

                    <ActionGroup
                      label="One leg from here"
                      actions={oneLeg.slice(0, 6).map(({ port: p, code, nm }) => ({
                        intent: { verb: 'SAIL', args: { dest: code } },
                        note: `${formatNm(nm)} · ${
                          p === null
                            ? 'unknown harbour'
                            : p.max_draft < fleetMaxDraft(acting, draftOfClass)
                              ? 'too shallow for this fleet'
                              : `draft ${p.max_draft}`
                        }`,
                      }))}
                      empty="No authored leg leaves this port."
                      lineOf={lineOf}
                      onPick={command}
                    />
                  </div>
                )}
            </>
          )}

          {face === 'city' && (
            <>
                {/* THE ROW RULE (see DetailRow.tsx): a short figure keeps the right-aligned two-column
                    StatRow, because a column of figures has to line up. A value that is a SENTENCE — a
                    dot-separated list, a figure with a parenthetical — uses DetailRow and flows
                    left-aligned, because right-aligning prose leaves its tail stranded as a fragment. */}
                <dl className="space-y-1">
                  <DetailRow
                    label="Development"
                    mono
                    value={`industry ${port.dev_industry} · commerce ${port.dev_commerce} · military ${port.dev_military}`}
                  />
                  <DetailRow
                    label="Market tax"
                    mono
                    value={formatPct(port.tax_rate, 1)}
                    hint="set by the Mayor, banded 0–8%. Tax relief is not in the V0 chain, so what you pay is what is printed."
                  />
                  <DetailRow
                    label="Spread"
                    mono
                    value={market?.port ? formatPct(market.port.spread, 1) : 'reading the market…'}
                    hint="half-spread, derived from commerce — the server's figure, not a client formula"
                  />
                  <DetailRow
                    label="Cheapest here"
                    value={
                      cheapHere.length === 0
                        ? marketLoaded
                          ? 'Nothing this port undercuts its neighbours on.'
                          : 'reading the market…'
                        : cheapHere
                            .map((g) => `${g.name} ${formatPctPoints(g.pct_nbr ?? 0)}`)
                            .join(' · ')
                    }
                    hint="%NBR against ports within 600 nm — a live reading, not an authored specialty list"
                  />
                </dl>
            </>
          )}

          {face === 'services' && (
            <>
              <p className="mb-3 text-xs text-ink-muted">
                Bureau, officers and the Mayor are V1 — they are not drawn because there is nothing
                behind them yet.
              </p>
                <dl className="space-y-1">
                  <DetailRow
                    label="Harbour"
                    mono
                    value={`${docked.length} of your fleets alongside · max draft ${port.max_draft}`}
                    hint="Other houses' shipping is not reported by the V0 world (J.3 is V1)."
                  />
                  <DetailRow
                    label="Yard"
                    mono
                    value={port.has_yard ? `tier ${port.yard_tier}` : 'none'}
                    hint={port.has_yard ? 'The yard prices a REPAIR when the order runs; PREVIEW it on Command for the quote.' : undefined}
                  />
                  <DetailRow
                    label="Provisions"
                    mono
                    value={`${formatTuns(snapshot.config.water_per_crew_day, 2)} water and ${formatTuns(snapshot.config.food_per_crew_day, 3)} food per hand, per voyage-day`}
                    hint="What stores COST is set when PROVISION runs — no quayside price list crosses the wire."
                  />
                  <DetailRow
                    label="Inn"
                    mono
                    value={`${formatInt(port.crew_pool)} hands in the pool`}
                    hint="Beyond the pool, hands cost 2.5x — urgent recruitment (F.2). The rate is quoted when HIRE runs."
                  />
                  <DetailRow label="Academy" mono value={port.has_academy ? 'yes' : 'none'} />
                  {port.is_ice_closed && <DetailRow label="Ice" mono value="CLOSED — nothing sails in or out" />}
                </dl>
            </>
          )}

          {face === 'ships' && (
            <>
                {docked.length === 0 ? (
                  <p className="text-sm text-ink-muted">
                    You have no fleet in {port.name}.{' '}
                    {world.fleets
                      .filter((f) => f.status === 'SAILING')
                      .map((f) => `${f.name} is at sea.`)
                      .join(' ')}
                  </p>
                ) : (
                  <Table className={scrollTableClass()}>
                    <thead>
                      <tr>
                        <TH>Ship</TH>
                        <TH>Fleet</TH>
                        <TH align="num">Hull</TH>
                        <TH align="num">Crew</TH>
                        <TH align="num">Hold</TH>
                      </tr>
                    </thead>
                    <tbody>
                      {docked.flatMap((fleet) =>
                        fleet.ships.map((ship) => (
                          <tr key={ship.id}>
                            <TD>
                              {ship.name}
                              {ship.is_flagship && <span className="ml-1 text-accent">⚑</span>}
                              <span className="ml-2 text-xs text-ink-faint">{ship.class}</span>
                            </TD>
                            <TD>{fleet.name}</TD>
                            <TD align="num">{formatPct(hullFraction(ship))}</TD>
                            <TD align="num">
                              {formatInt(ship.crew)}/{formatInt(ship.crew_max)}
                            </TD>
                            <TD align="num">
                              {formatTuns(shipHoldUsed(ship), 1)} / {formatTuns(ship.hold)}
                            </TD>
                          </tr>
                        )),
                      )}
                    </tbody>
                  </Table>
                )}
                {docked.length > 0 && (
                  <p className="mt-1 font-mono text-[11px] text-ink-faint">{TABLE_SCROLL_HINT}</p>
                )}
            </>
          )}
        </div>
      </Card>

      <Card>
        <CardHeader
          eyebrow="Elsewhere"
          title="Other ports"
          explain="Read a harbour before you sail to it — the prices you see are the ones your factors report from there, not the ones you are lying in."
        />
        <div className="flex flex-wrap gap-1.5">
          {snapshot.ports.map((p) => (
            <button
              key={p.code}
              type="button"
              onClick={() => setPicked(p.code)}
              className={[
                'min-h-11 rounded-md px-3 font-mono text-xs transition',
                p.code === port.code
                  ? 'bg-accent text-app'
                  : 'border border-edge bg-surface-2 text-ink-muted hover:text-ink',
              ].join(' ')}
            >
              {p.name}
            </button>
          ))}
        </div>
      </Card>
    </Screen>
  )
}

/** How many hands the Inn can actually sign: berths short, capped by the pool it has. */
function hireCount(fleet: FleetView, port: SnapshotPort): number {
  const crew = fleetCrew(fleet)
  return Math.max(1, Math.min(Math.floor(port.crew_pool), Math.max(0, crew.max - crew.aboard)))
}

/** Units, not tuns: the hold is in tuns and a good's `bulk` is the tuns one unit occupies. */
function affordableUnits(fleet: FleetView, bulk: number): number {
  const byHold = bulk > 0 ? Math.floor(fleetHoldFree(fleet) / bulk) : 0
  return Math.max(1, byHold)
}

function buyNote(good: MarketGood): string {
  const nbr = good.pct_nbr === null ? 'alone on this coast' : `${formatPctPoints(good.pct_nbr)} of neighbours`
  return `${good.buy} d./t · ${nbr}`
}

function ActionGroup({
  label,
  actions,
  empty,
  lineOf,
  onPick,
}: {
  label: string
  actions: readonly { intent: CommandIntent; note?: string }[]
  /** What to say when there is nothing to offer — silence would read as a broken panel. */
  empty?: string
  /** The order line, composed by the ONE composer. The group never builds a string itself. */
  lineOf: (intent: CommandIntent) => string
  onPick: (intent: CommandIntent) => void
}) {
  if (actions.length === 0 && !empty) return null
  return (
    <div>
      <SectionLabel>{label}</SectionLabel>
      {actions.length === 0 ? (
        <p className="text-sm text-ink-muted">{empty}</p>
      ) : (
        <ul className="space-y-1">
          {actions.map((a) => {
            const line = lineOf(a.intent)
            return (
              <li key={line}>
                <button
                  type="button"
                  onClick={() => onPick(a.intent)}
                  className="min-h-11 w-full rounded-md border border-edge bg-surface px-3 py-2 text-left transition hover:border-accent/60"
                >
                  <code className="block break-words font-mono text-xs text-accent">{line}</code>
                  {a.note && <span className="mt-0.5 block font-mono text-[11px] text-ink-faint">{a.note}</span>}
                </button>
              </li>
            )
          })}
        </ul>
      )}
    </div>
  )
}
