import { useEffect, useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import {
  Badge,
  Button,
  Card,
  CardHeader,
  Collapsible,
  DetailRow,
  Explain,
  Input,
  Notice,
  PageHeader,
  Screen,
  SectionLabel,
  TabRow,
  StatLegend,
  TD,
  TH,
  Table,
  scrollTableClass,
  fineClass,
} from '../../components/ui'
import { formatInt, formatNm, formatPct, formatPctPoints, formatTuns, formatVoyageDays } from '../../lib/format'
import { portNameOf, useWorld } from '../../live/worldStore'
import type { FleetView, MarketGood, MarketView, SnapshotPort, WorldSnapshot } from '../../lib/rpc'
import { fold, foldedMatch } from '../../lib/text'
import { useCommandDraft } from '../../domain/order'
import { AcademyFace, OfficersFace } from './PortFaces'
import { QuayToday } from './PortFair'
import { PORT_FACES, usePortView } from './portView'
import { harbourCode, useHarbour } from '../../store/harbour'
import type { CommandIntent } from '../../domain/order'
import { findVerb, orderText } from '../../domain/order'
import {
  SHIP_STATS,
  fleetCrew,
  fleetMaxDraft,
  fleetPortCode,
  housePortCode,
  hullFraction,
  shipHoldUsed,
  shipStatItems,
  worstHullFraction,
} from '../../domain/fleet'
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

export function PortScreen() {
  // FIELDS, NOT THE STORE (worldStore.ts rule 4).
  const phase = useWorld((s) => s.phase)
  const fatal = useWorld((s) => s.fatal)
  const snapshot = useWorld((s) => s.snapshot)

  if (phase === 'failed') {
    return <WorldFailed eyebrow="Harbour" title="Port" refusal={fatal} />
  }
  if (phase !== 'ready' || !snapshot) {
    return <WorldLoading eyebrow="Harbour" title="Port" subtitle="Where you are, and what is here." panels={3} />
  }
  return <PortBody snapshot={snapshot} />
}

function PortBody({ snapshot }: { snapshot: WorldSnapshot }) {
  const fleets = useWorld((s) => s.fleets)
  const portByCode = useWorld((s) => s.portByCode)
  const reaches = useWorld((s) => s.reaches)
  const loadReach = useWorld((s) => s.loadReach)
  const markets = useWorld((s) => s.markets)
  const navigate = useNavigate()
  const handOff = useCommandDraft((s) => s.handOff)
  const draftFleetId = useCommandDraft((s) => s.fleetId)
  const loadMarket = useWorld((s) => s.loadMarket)

  // WHICH HARBOUR — the ONE owner (src/store/harbour.ts), shared with MARKET, so a harbour picked
  // on either tab is the harbour both read. WHICH FACE — this screen's own chrome (portView.ts).
  // Both persisted, because both were being lost every time the player left the tab.
  const picked = useHarbour((s) => s.picked)
  const setPicked = useHarbour((s) => s.pick)
  const face = usePortView((s) => s.face)
  const setFace = usePortView((s) => s.turnTo)

  // THE DEFAULT IS WHERE THE HOUSE IS, AND A FLEET AT SEA IS SOMEWHERE.
  //
  // This read `fleets.find((f) => f.port)?.port ?? snapshot.ports[0]?.code`, so the moment the only
  // fleet weighed anchor the whole screen fell through to the FIRST PORT IN THE SNAPSHOT — served
  // by CODE, so in practice Acapulco, ~10,000 nm from a house sailing the Iberian coast. It was not
  // merely a wrong heading: every action on the Quay composes an order for the ACTING fleet, so a
  // player sailing Lisbon → Porto could tap Acapulco's `BUY porcelain 86` and queue it to run at
  // Porto, where the price, the stock and the hold are all different.
  //
  // `harbourCode` (src/store/harbour.ts) is now the ONE spelling of pick-else-house-else-first-
  // port, composed on `housePortCode` (domain/fleet) — MARKET calls the same function, so the two
  // tabs cannot derive different defaults.
  const homeCode = housePortCode(fleets)
  const portCode = harbourCode(picked, fleets, snapshot.ports)
  const port = portCode ? (portByCode[portCode] ?? null) : null

  // The market is fetched per port, on demand — the store caches it, so this asks once per harbour.
  // Never for a SEA PLACE (0036): open water keeps no book, and asking for one would cache an
  // empty market that looks exactly like a real market with nothing in it.
  const isSeaPlace = port?.kind === 'SEA_PLACE'
  const portId = port?.id ?? null
  const market: MarketView | undefined = portId ? markets[portId] : undefined
  const marketLoaded = market !== undefined
  useEffect(() => {
    if (portId && !marketLoaded && !isSeaPlace) void loadMarket(portId)
  }, [portId, marketLoaded, isSeaPlace, loadMarket])
  // The sailed distances out of here (world.reach, 0039) - the "nearest water" list below reads
  // them. Cached in the store; a reach never changes within a chain version.
  useEffect(() => {
    if (portId) void loadReach(portId)
  }, [portId, loadReach])

  const draftOfClass = useMemo(() => {
    const byName = new Map(snapshot.ship_classes.map((c) => [c.name, c.draft]))
    return (className: string) => byName.get(className)
  }, [snapshot.ship_classes])

  const docked = port ? fleets.filter((f) => f.port === port.code) : []
  const acting =
    docked[0] ?? fleets.find((f) => f.id === draftFleetId) ?? fleets[0] ?? null
  // ONE reading of her hands, from the fleet section (domain/fleet). The Quay used to call
  // `fleetCrew(acting)` twice in one template string and then spell "berths still empty" a THIRD
  // way inside `hireCount` below — three foldings of one payload on one screen.
  const actingCrew = acting ? fleetCrew(acting) : null
  // WHERE THE ACTING FLEET'S NEXT ORDER WOULD RUN — alongside, or the harbour she is bound for.
  // Read ONCE, from the fleet section, and used for both the banner and the gate on the Quay.
  const actingPortCode = acting ? fleetPortCode(acting) : null
  const actingIsHere = actingPortCode !== null && actingPortCode === port?.code

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
        <Notice tone="warning">The world served no ports.</Notice>
      </Screen>
    )
  }

  // WHICH FACES THIS HARBOUR HAS, and which of them is up. A persisted face can outlive the port
  // it was chosen on — turn to ACADEMY in Sagres, then read a harbour that keeps no school — so the
  // shown face is derived from what is OFFERED rather than trusted from storage. Falling back to
  // the Quay is the same rule as the tab list: never leave a face up that this port cannot host.
  const offeredFaces = PORT_FACES.filter((f) => f.id !== 'academy' || port.has_academy)
  const shownFace = offeredFaces.find((f) => f.id === face) ?? offeredFaces[0]

  // The nearest water from here — the server's sailed figures (world.reach, 0039: the same
  // distance table the endurance gate and the trade scan read; the approach detour is inside
  // every number). The old one-leg graph is gone; "near" is now simply near, by sea.
  const reachHere = reaches[port.id]?.reaches ?? null
  const oneLeg = (reachHere ? Object.entries(reachHere) : [])
    .map(([code, nm]) => ({ port: portByCode[code] ?? null, code, nm }))
    .filter((r) => r.port !== null && r.port.kind === 'HARBOUR')
    .sort((a, b) => a.nm - b.nm)

  // 0036: A SEA PLACE HAS NO SHORE, so it gets the anchorage view and none of the harbour faces.
  // The served `kind` decides — the screen never infers "no quay" from an empty market, because an
  // empty market and a missing market must not look alike (NO_SPAGHETTI §7C). Everything shown is
  // served: the approach line the LANDFALL report speaks, your hulls lying here, and the sailed
  // legs out — each of which composes the same SAIL hand-off every other row on this screen uses.
  if (port.kind === 'SEA_PLACE') {
    return (
      <Screen>
        <PageHeader
          eyebrow="Open water"
          title={port.name}
          subtitle={`${port.country} · ${port.sea}`}
          actions={<Badge tone="neutral">sea place</Badge>}
        />
        {port.approach && (
          <Card>
            <p className="text-sm italic leading-relaxed text-ink">{port.approach}</p>
          </Card>
        )}
        <Card>
          <CardHeader title="At anchor" />
          {docked.length === 0 ? (
            <p className="text-sm text-ink-muted">None of your hulls are lying here.</p>
          ) : (
            docked.map((f) => (
              <DetailRow key={f.id} label={f.name} value={`${f.ships.length} ship(s), holding station`} />
            ))
          )}
          <p className={fineClass('mt-2')}>
            There is no quay here — no market, no chandler, no crew, no shipyard. Stores are bought
            in harbour, and the sailing gate already made her carry enough to leave again.
          </p>
        </Card>
        <Card>
          <CardHeader title="Sailing on" subtitle="The nearest water, by sailed miles." />
          <div className="space-y-1">
            {oneLeg.map(({ port: p, code, nm }) => (
              <Button
                key={code}
                variant="secondary"
                className="w-full justify-between font-mono text-xs"
                onClick={() => command({ verb: 'SAIL', args: { dest: code } })}
              >
                <span>{lineOf({ verb: 'SAIL', args: { dest: code } })}</span>
                <span className="text-ink-faint">
                  {p?.name ?? code} · {formatInt(Math.round(nm))} nm
                </span>
              </Button>
            ))}
          </div>
        </Card>
      </Screen>
    )
  }

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
        // "latin culture", not a bare "latin" — the raw culture value read as a word from
        // nowhere between a country and a sea (the plain-words sweep, 2026-08-23).
        subtitle={`${port.country} · ${port.culture} culture · ${port.sea}`}
        /* THE FIGURE THE OWNER MET BARE. `draft 5` stood here with no unit and nothing saying what
           it decides — the question that started the whole stat-gloss pass. The sentence is
           domain/fleet's ONE draft sentence (statGloss.ts), the same one the compendium's ships
           legend prints — composed, never respelt, so two screens cannot explain draft apart. */
        explain={SHIP_STATS.draft.line}
        actions={<Badge tone="neutral">draft {port.max_draft}</Badge>}
      />

      {/* THE BANNER SAYS WHERE SHE IS, NOT WHERE A LIST OF FLEETS STARTS. It used to read "your
          NEAREST fleet is at X" off `fleets.find(f => f.port)`, which is neither nearest nor,
          for a fleet at sea, true — she is at neither end of her passage. The two states are
          different sentences because they are different situations: a hull alongside somewhere
          else can be sailed here; a hull at sea is committed until she arrives. */}
      {acting && !actingIsHere && (
        /* IT WAS A <p> INSIDE A <p>. `Notice` renders a paragraph (Notice.tsx:19) and this put a
           <p> and a <Button> inside it — invalid markup the browser silently reparents, which is
           why the button sat outside the tint. A <div> with the same tint through `Notice`'s own
           token is not available to a caller, so the shape changed instead: ONE short line, and
           the "these are only your factors' figures" disclosure behind the dot where every other
           standing sentence in this app lives. Nothing was dropped — it got shorter and folded. */
        <Notice tone="warning" className="text-xs">
          {acting.status === 'SAILING' && acting.voyage
            ? `${acting.name} is at sea, bound for ${acting.voyage.to ? portNameOf(portByCode, acting.voyage.to) : 'open water'}. Orders run there.`
            : actingPortCode
              ? `${acting.name} lies at ${portNameOf(portByCode, actingPortCode)}. Orders run there.`
              : `${acting.name} is alongside nowhere.`}
          <Explain label="reading a harbour you are not in" dotClassName="ml-1">
            {port.name} is being read from a distance — these are what your factors report, not
            what you are lying in.
          </Explain>
          {actingPortCode && (
            <Button variant="secondary" className="mt-2" onClick={() => setPicked(actingPortCode)}>
              Read {portNameOf(portByCode, actingPortCode)} instead
            </Button>
          )}
        </Notice>
      )}

      {/* WHAT IS ON AT THE QUAY, ABOVE THE PANEL AND ABOVE THE FOLD (0026, PortFair.tsx).
          It sits OUTSIDE the faces on purpose: a fair is not a side of the port you turn to, it is
          a fact about the harbour that changes the price on every face at once — the Quay's buy
          lines, the City's spread and the Market tab's whole column are all quoting through it. A
          face would have hidden it behind a tap, and 1.6 per cent of port-days is exactly the
          frequency at which a player never finds the tap.
          It costs ONE dim line while the quay is quiet, and becomes a panel only when something is
          actually on. */}
      <QuayToday portId={portId} />

      {/* ONE PLACE WITH FACES, NOT FOUR CARDS DOWN A PAGE (docs/UI_DIRECTION.md §2).
          The reference draws a port as a single panel with 기본/교역/시설/투자 along its top. This
          screen used to be four sibling Cards, which at 390px meant the fourth began ~1,200px down
          and was, in practice, never read. Same content, same order lines, one panel.

          THE QUAY IS THE FIRST FACE, deliberately. §3a's second trap is "the action lives on the
          wrong screen" — the most-praised patch in that game's four-year convenience backlog added
          no feature at all, it moved an action to the screen where the need arises. What you can
          DO here opens first; what the city IS is one tap away. */}
      <Card
        head={
          /* No eyebrow and no draft badge here: the PageHeader above already carries both, and
             this panel sits directly beneath it. One fact, one place — the same rule that took the
             purse off two screens in D12.

             THE HEADING NAMES THE FACE THAT IS UP. It was hard-coded "The quayside" on all six,
             so CITY, SERVICES, OFFICERS and ACADEMY each sat under the name of a face they were
             not. Both the heading and the strip below now read the one FACES table. */
          <CardHeader
            flush
            title={shownFace.title}
            /* THE ALONGSIDE FACE PRINTS SHIP COLUMNS (Hull · Crew · Hold), so its explanation
               carries the ONE sentence each of those figures has — domain/fleet's statGloss,
               the same lines FLEETS' ships table opens (docs/NO_SPAGHETTI.md §1: one authority,
               two callers, never two spellings). The other faces keep their own line. */
            explain={
              shownFace.id === 'ships' ? (
                <>
                  {shownFace.explain}
                  <StatLegend items={shipStatItems(['hull', 'crew', 'hold'])} className="mt-1" />
                </>
              ) : (
                shownFace.explain
              )
            }
          />
        }
      >
        <TabRow
          label="Port faces"
          value={face}
          onChange={setFace}
          className="mb-3"
          /* HIRING AND STUDYING LIVE WHERE THEY HAPPEN. §3a's second trap is "the action lives on
             the wrong screen"; an officer signs on at a quay and a trade is learned at an academy,
             so both are faces of the PORT rather than tabs of their own. The academy face is only
             offered where there IS one — a face that always refuses is a menu item that wastes a
             tap, and `offeredFaces` is where that one exception lives. */
          tabs={offeredFaces.map((f) => ({
            id: f.id,
            label: f.label,
            hint: f.id === 'ships' ? docked.length || undefined : undefined,
          }))}
        />

        <div role="tabpanel">
          {shownFace.id === 'quay' && (
            <>
              {/* THE QUAY ONLY OFFERS ORDERS FOR THE HARBOUR SHE IS ACTUALLY IN.
                  Every line here composes an order for the ACTING fleet, and an order runs where
                  she is — so printing `BUY porcelain …` under a port she is 10,000 nm from is the
                  screen offering a trade at one market that would execute at another. Measured in
                  the playtest: sailing Lisbon → Porto, Acapulco's buy line composed cleanly and
                  would have run at Porto. Reading a far harbour is a real thing to want; giving it
                  ORDERS is not, so the reading stays and the actions go. */}
              {!acting ? (
                <p className="text-sm text-ink-muted">No fleet to give an order to yet.</p>
              ) : !actingIsHere ? (
                <p className="text-sm text-ink-muted">
                  Nothing to order from here — {acting.name} is elsewhere. City and Services still
                  read this harbour.
                </p>
              ) : (
                <>
                  <p className="mb-3 text-xs text-ink-muted">
                    Tap one to send it to Command as {acting.name}&apos;s order.
                  </p>
                  <div className="space-y-4">
                    {/* AN ACTION THAT WOULD BE REFUSED IS NOT OFFERED. HIRE used to be printed
                        unconditionally with `Math.max(1, …)` hands, so a fleet with every berth
                        filled — or a port with an empty pool — was handed `HIRE 1`, which the
                        server answers with E_CREW_MAX. REPAIR was printed beside a whole hull.
                        Both are the same defect as the BUY line below and are gated the same way:
                        the picker never offers what the server would refuse. */}
                    <ActionGroup
                      label="Supplies and crew"
                      actions={[
                        {
                          intent: { verb: 'PROVISION', args: { mode: 'FULL' } },
                          // "provision", not "range" — the same served figure carried three names
                          // (endurance / range / provision) and FLEETS settled on the verb that
                          // refills it. This note was the last "range" left on a screen.
                          note: `provision ${formatVoyageDays(acting.endurance_days)}`,
                        },
                        ...(hireCount(acting, port) > 0
                          ? [
                              {
                                intent: { verb: 'HIRE', args: { count: String(hireCount(acting, port)) } },
                                // "at the inn", not "pool" — the Services face calls the same
                                // figure the Inn's, and a schema word must not name it here.
                                note: `berths ${formatInt(actingCrew?.aboard ?? 0)}/${formatInt(actingCrew?.max ?? 0)} · ${formatInt(port.crew_pool)} at the inn`,
                              },
                            ]
                          : []),
                        ...(port.has_yard && worstHullFraction(acting) < 1
                          ? [
                              {
                                intent: { verb: 'REPAIR', args: { to_pct: '100' } },
                                note: `worst hull ${formatPct(worstHullFraction(acting))} · shipyard tier ${port.yard_tier}`,
                              },
                            ]
                          : []),
                      ]}
                      lineOf={lineOf}
                      onPick={command}
                    />

                    {/* ═══════════════════════════════════════════════════════════════════════
                        HOW MUCH TO BUY IS THE SERVER'S ANSWER. THE FOURTH COPY IS DELETED.
                        ═══════════════════════════════════════════════════════════════════════
                        This line used to carry a number from a private `affordableUnits(fleet,
                        bulk)` — `floor(free_hold / bulk)`, floored at 1 — which was called
                        "affordable" and never once read the purse. On a fresh 8,000 d. save, two
                        of the four buys it offered were refused the instant they were issued:
                        `BUY porcelain 186` → "cost 75701 d. and you hold 8000", `BUY black-pepper
                        93` → "cost 12532 d. and you hold 8000". Its `Math.max(1, …)` also offered
                        `BUY olive-oil 1` on a full hold, which refuses with E_HOLD_FULL.

                        It was the FOURTH copy of a rule D10 was written to kill twice, and the
                        answer is the one MarketScreen.tsx:168-175 records: hand over the word
                        `ALL` and let `public.fleet_buy_capacity()` resolve it. That walks the same
                        stepped book a committed trade walks (§G.2 — buying raises the price you
                        are still buying at) and stops at whichever of hold, stock, daily cap or
                        PURSE binds first. The copy is DELETED, not given a purse term: a fifth
                        correct-today arithmetic is still a second authority.

                        `ALL` is also read when the order RUNS rather than when it is made (F.2),
                        so a buy queued from here is still right after a voyage that changed the
                        hold. Nothing on this screen needs the figure; where one is ever needed,
                        `world.buy_capacity(fleet, good)` is on the RPC surface and in the store
                        (features/command/useBuyCapacity.ts). */}
                    {/* THE HOLD IS ONE FACT, SO IT IS PRINTED ONCE. `… free in the hold` used to
                        ride on EVERY buy row — the same four words and the same figure, four
                        times, wrapping each row onto a second line (docs/UI_DIRECTION.md §4 rule
                        3: one row, four facts). It is the GROUP's fact, not the row's, so it sits
                        on the group's label. `free_hold` is still the SERVER's reading
                        (public.fleet_free_hold, 0017:183) — the one a BUY is checked against. */}
                    <ActionGroup
                      label={marketLoaded ? 'Worth buying' : 'Trade'}
                      note={
                        marketLoaded && acting.free_hold > 0
                          ? `${formatTuns(acting.free_hold, 0)} free in the hold`
                          : undefined
                      }
                      actions={
                        marketLoaded && acting.free_hold > 0
                          ? worthBuying.map((good) => ({
                              intent: {
                                verb: 'BUY',
                                // CODES, never display names: `cmd.parse()` splits on whitespace.
                                args: { good: good.code, qty: 'ALL' },
                              },
                              note: buyNote(good),
                            }))
                          : []
                      }
                      empty={
                        !marketLoaded
                          ? 'Reading the market…'
                          : acting.free_hold <= 0
                            ? 'Hold full. Sell before you buy.'
                            : 'Nothing cheap here — the Market tab has the whole list.'
                      }
                      lineOf={lineOf}
                      onPick={command}
                    />

                    <ActionGroup
                      label="Nearest by sea"
                      actions={oneLeg.slice(0, 6).map(({ port: p, code, nm }) => ({
                        intent: { verb: 'SAIL', args: { dest: code } },
                        note: `${formatNm(nm)} · ${
                          p === null
                            ? 'unknown harbour'
                            : p.max_draft < fleetMaxDraft(acting, draftOfClass)
                              ? 'too shallow'
                              : `draft ${p.max_draft}`
                        }`,
                      }))}
                      empty="The distances are still being fetched."
                      lineOf={lineOf}
                      onPick={command}
                    />
                  </div>
                </>
              )}
            </>
          )}

          {shownFace.id === 'city' && (
            <>
                {/* THE ROW RULE (see DetailRow.tsx): a short figure keeps the right-aligned two-column
                    StatRow, because a column of figures has to line up. A value that is a SENTENCE — a
                    dot-separated list, a figure with a parenthetical — uses DetailRow and flows
                    left-aligned, because right-aligning prose leaves its tail stranded as a fragment. */}
                <dl className="space-y-1">
                  {/* THREE RAW COLUMN NAMES USED TO BE PRINTED HERE — `industry 4 · commerce 7 ·
                      military 2` — with no scale, no unit and no consequence, which is a database
                      row wearing a label. All three are 0–20 (migration 0002:98-100), and two of
                      them really do change what a player pays: `dev_commerce` narrows the spread
                      and shaves the mid price (0005:299,331), `dev_industry` takes 1% off a repair
                      per point (0007:736). `dev_military` is read by nothing, and the hint says so
                      rather than letting it look like it matters — the alternative was to drop it,
                      but a city with a garrison has one whether or not the rules notice yet. */}
                  {/* `/20` THREE TIMES IS THE SAME SCALE THREE TIMES, and it wrapped the value
                      onto a second line. It moves into the LABEL, where one printing serves all
                      three figures — the scale is still on screen, which is what "never show a
                      number you cannot defend" asks for. */}
                  <DetailRow
                    label="How grown, of 20"
                    mono
                    value={`trade ${port.dev_commerce} · crafts ${port.dev_industry} · garrison ${port.dev_military}`}
                    hint="Out of twenty. Trade narrows the cut this city takes on a deal; crafts make its shipyard cheaper. The garrison is recorded and nothing reads it yet, so it changes no price you pay."
                  />
                  <DetailRow
                    label="Market tax"
                    mono
                    value={formatPct(port.tax_rate, 1)}
                    hint="The Mayor's cut of every deal, between nothing and 8%. It cannot be waived, so what is printed is what you pay."
                  />
                  <DetailRow
                    label="Spread"
                    mono
                    value={market?.port ? formatPct(market.port.spread, 1) : 'reading…'}
                    /* THE HINT STOPPED BEING THE WHOLE RULE WHEN 0026 LANDED. `world.spread()` is
                       now development LESS whatever is running on the quay, so a sentence naming
                       only development described a number the game had stopped computing that way
                       — the same "a screen's sentence became false, so it was corrected in the
                       change that made it false" standard docs/NO_SPAGHETTI.md §8 asks for. The
                       FIGURE is untouched: this is still `world.market()`'s one spread, and the
                       fair is not printed again here (PortFair.tsx says why). */
                    hint="The cut between what this port buys at and what it sells at. It narrows as a city's trade grows, and narrows again while a fair is on — this figure already has both in it."
                  />
                  <DetailRow
                    label="Cheapest here"
                    value={
                      cheapHere.length === 0
                        ? marketLoaded
                          ? 'nothing undercuts its neighbours'
                          : 'reading…'
                        : cheapHere
                            .map((g) => `${g.name} ${formatPctPoints(g.pct_nbr ?? 0)}`)
                            .join(' · ')
                    }
                    hint="What this port charges as a share of what its neighbours charge — today's market, not a list of what the town is famous for."
                  />
                </dl>
            </>
          )}

          {shownFace.id === 'services' && (
            <>
              {/* THE PARAGRAPH IS GONE AND NOTHING IT SAID IS. It ran three sentences over the
                  rows to disclose that no port keeps a Bureau or a Mayor's office, and to point at
                  two tabs that are one tap away and visible. The disclosure is now a ROW, in the
                  same list as the shipyard and the inn — which is what rule 5 asks for anyway
                  ("unavailable is shown with its reason") and what rule 3 asks for instead of a
                  paragraph. The signposting to Officers and Academy is deleted: the tab strip is
                  directly above, so it was telling the player what they could already see. */}
                <dl className="space-y-1">
                  <DetailRow
                    label="Harbour"
                    mono
                    value={`${docked.length} alongside · draft ${port.max_draft}`}
                    hint="Your own hulls only. What another house has lying here is not something a harbour will tell you."
                  />
                  {/* "Shipyard", not "Yard" — the owner's own example of the jargon sweep
                      ("yard" → shipyard, 2026-08-23); migration 0033 made the served strings say
                      the same word, and this label was the last "Yard" on a screen. */}
                  <DetailRow
                    label="Shipyard"
                    mono
                    value={port.has_yard ? `tier ${port.yard_tier}` : 'none'}
                    hint={port.has_yard ? 'The shipyard prices a REPAIR when the order runs; PREVIEW it on Command for the quote.' : undefined}
                  />
                  {/* "crew", NOT "hands" (the owner, 2026-08-23: "change it like crew or
                      something"). "a hand-day" was that jargon squared — a made-up unit built on a
                      sailor's word. The rate is unchanged; only its unit is said in the player's
                      words. The SERVER said "hands" too until migration 0030 sliced cmd.do_hire's three
                      refusals, voyage.report_line's burial and short-ration prose and the HIRE
                      verb's own help text; 0033 did the same for "yard". The wire says crew and
                      shipyard now, so there is nothing left here for a client gloss to paper over
                      — which is the point: a client gloss over served copy would have been a
                      second author for the game's own words. */}
                  <DetailRow
                    label="Chandler"
                    mono
                    value={`water ${formatTuns(snapshot.config.water_per_crew_day, 2)} · food ${formatTuns(snapshot.config.food_per_crew_day, 3)} per crew member a day`}
                    hint="What one crew member drinks and eats per voyage-day. What stores COST is settled when PROVISION runs — no chandler posts a price list on the quay, so PREVIEW the order on Command for the figure."
                  />
                  <DetailRow
                    label="Inn"
                    mono
                    value={`${formatInt(port.crew_pool)} crew`}
                    hint="Crew waiting to sign on. Take on more than the pool holds and the rest are found at short notice, at two and a half times the wage — quoted when HIRE runs."
                  />
                  <DetailRow label="Academy" mono value={port.has_academy ? 'yes' : 'none'} />
                  <DetailRow
                    label="Bureau"
                    mono
                    value="none"
                    hint="No port keeps one open to callers yet. Nothing is being hidden from you — there is nothing there to visit."
                  />
                  <DetailRow
                    label="Mayor"
                    mono
                    value="none"
                    hint="No port keeps an office open to callers yet. Nothing is being hidden from you — there is nothing there to visit."
                  />
                  {port.is_ice_closed && <DetailRow label="Ice" mono value="CLOSED — nothing sails" />}
                </dl>
            </>
          )}

          {shownFace.id === 'officers' && <OfficersFace port={port} acting={acting} />}

          {shownFace.id === 'academy' && <AcademyFace acting={acting} />}

          {shownFace.id === 'ships' && (
            <>
                {docked.length === 0 ? (
                  <p className="text-sm text-ink-muted">
                    No fleet of yours in {port.name}.{' '}
                    {(() => {
                      const atSea = fleets.filter((f) => f.status === 'SAILING')
                      // ONE SENTENCE, NOT ONE PER HULL. This mapped every sailing fleet to its own
                      // "X is at sea." and joined them, so a house with four fleets out printed
                      // four sentences saying one thing.
                      return atSea.length === 0
                        ? ''
                        : `${atSea.map((f) => f.name).join(', ')} at sea.`
                    })()}
                  </p>
                ) : (
                  /* THE FLEET COLUMN ONLY EXISTS WHEN THERE ARE TWO FLEETS TO TELL APART.
                     A fleet is one to EIGHT hulls by design, so with one fleet alongside this
                     column printed the same word eight times down a 390px table and pushed the
                     hold off the right edge. Measured with eight hulls: 489px of table in a 332px
                     box with the column, 411px without — the swipe stops being needed at all for
                     a single fleet. It is not "hidden to save room": with a second fleet docked,
                     which ship belongs to which is the only thing this table cannot say without
                     it, so it comes back. */
                  <Table scrollHint className={scrollTableClass()}>
                    <thead>
                      <tr>
                        <TH>Ship</TH>
                        {docked.length > 1 && <TH>Fleet</TH>}
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
                            {docked.length > 1 && <TD>{fleet.name}</TD>}
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
            </>
          )}
        </div>
      </Card>

      <ElsewherePanel
        ports={snapshot.ports}
        current={port.code}
        home={homeCode}
        onPick={setPicked}
      />
    </Screen>
  )
}

/** How many hands the Inn can actually sign: berths still empty, capped by the pool it has.
 *  `berths` is `fleetCrew`'s — `sum(crew_max - crew)`, the spelling `cmd.do_hire` refuses on
 *  (0007:659). This used to compute it inline as `max(0, max - aboard)`, which is a different
 *  function once a hull is over-crewed and was one of two client spellings of the rule.
 *
 *  IT MAY RETURN ZERO, AND ZERO MEANS "DO NOT OFFER THIS". It used to floor at 1, which handed a
 *  fully-crewed fleet — or a port with an empty pool — a `HIRE 1` the server answers with
 *  E_CREW_MAX. The Quay reads the zero and leaves the line out; see the gate at the call site. */
function hireCount(fleet: FleetView, port: SnapshotPort): number {
  return Math.min(Math.floor(port.crew_pool), Math.max(0, fleetCrew(fleet).berths))
}

// `affordableUnits(fleet, bulk)` STOOD HERE AND IS DELETED, not corrected. It answered "the most
// she can buy" from `floor(free_hold / bulk)` and never read the purse — the fourth copy of a rule
// D10 killed twice. The one authority is `public.fleet_buy_capacity()`, reached either by handing
// the server the word `ALL` (what the Quay does) or by asking `world.buy_capacity(fleet, good)`
// (what the composer does, via features/command/useBuyCapacity.ts). See the BUY group above for
// the measured refusals it produced.

/**
 * READING A HARBOUR YOU ARE NOT IN — 214 ports, in the order they are PRINTED, behind one tap.
 *
 * ── THREE THINGS WERE WRONG WITH THE GRID THIS REPLACES ────────────────────────────────────────
 * 1. IT WAS SORTED BY A COLUMN IT DOES NOT SHOW. `world.snapshot()` serves the ports ordered by
 *    CODE and the buttons print NAMES, so the strip read *Antalya, Arkhangelsk, Antwerp* and
 *    *Barcelona, Bandar Abbas, Beirut* — alphabetical, in an alphabet the player cannot see, which
 *    reads as shuffled. Sorting by what is shown is the whole fix; `localeCompare` is used because
 *    the names carry diacritics (`Ávila` sorts under A, not after Z).
 * 2. THERE WAS NO WAY TO FIND ONE. 214 chips and no filter, while the Market tab's picker and the
 *    Command tab's have had one for weeks. It matches through `lib/text`'s `foldedMatch`, which is
 *    the same folding `cmd.fold()` does on the server — so a port found by typing `sao` is a port
 *    the parser will accept spelt that way, and this screen cannot drift from the other two the
 *    way MARKET's bare `toLowerCase()` once did.
 * 3. IT SAT UNDER EVERY FACE. The panel is outside the tabpanel, so all ~214 buttons were below
 *    the Quay, the City, Services, Alongside, Officers AND the Academy — a column of scroll between
 *    a player and the bottom of every face they open. It is folded now, and its header says how
 *    many are inside, so it costs one tap instead of a thousand pixels.
 *
 * IT IS PORT'S CHIP LIST, and it is deliberately not the row-picker `features/command/ArgPickers`
 * offers: that one answers "where shall she SAIL", so its rows carry a sailed distance, a draught
 * and a one-leg badge. This one answers "whose market am I reading", where the only thing that
 * matters is the name. The two are named as separate controls in docs/NO_SPAGHETTI.md §7's debt
 * list; what they must NOT do is match text two different ways, and they no longer can.
 */
function ElsewherePanel({
  ports,
  current,
  home,
  onPick,
}: {
  ports: readonly SnapshotPort[]
  /** The harbour being read now. */
  current: string
  /** Where the house is — pinned first, so getting back is one tap and not a search. */
  home: string | null
  onPick: (code: string) => void
}) {
  const [query, setQuery] = useState('')

  const listed = useMemo(() => {
    const needle = fold(query.trim())
    return ports
      .filter((p) => foldedMatch(needle, p.name, p.code, p.country, p.region))
      .sort((a, b) => a.name.localeCompare(b.name))
  }, [ports, query])

  const homePort = home ? (ports.find((p) => p.code === home) ?? null) : null

  return (
    <Card>
      {/* THE EYEBROW SITS OUTSIDE THE TOGGLE, not inside it. A Collapsible's header IS a <button>,
          and <SectionLabel> is an <h3> — not phrasing content, so it may not go there. The
          alternative was to hand-write the eyebrow's classes inside the span, which is how the
          design system ended up with two copies of that recipe already (NO_SPAGHETTI §7). One tap
          target, one label above it, no third copy. */}
      <SectionLabel>Elsewhere</SectionLabel>
      <Collapsible
        defaultOpen={false}
        storageKey="port.elsewhere"
        header={
          <span className="min-w-0 text-sm text-ink">
            Read another harbour — {formatInt(ports.length)} of them
          </span>
        }
        contentClassName="pt-3"
      >
        {/* "A reading only — orders still happen where your fleet is." STOOD HERE AND IS DELETED,
            not folded. The moment a far harbour is picked, the banner at the top of the screen says
            where orders actually run (and carries the reading-from-a-distance disclosure behind its
            dot), and the Quay face refuses with "Nothing to order from here". A third statement of
            one rule, printed before the player has even picked, is the duplication this sweep
            exists to remove — moving it behind a dot would have kept two authorities for it. */}
        <Input
          size="sm"
          type="search"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          aria-label="Find a harbour by name, code, country or region"
          placeholder="Find a harbour by name, code, country or region"
          spellCheck={false}
          autoCorrect="off"
        />
        <p className={fineClass('mt-2')}>
          {query.trim()
            ? `${formatInt(listed.length)} of ${formatInt(ports.length)} match.`
            : `All ${formatInt(ports.length)}, by name.`}
        </p>

        {/* ONE HARBOUR IS ALWAYS ONE TAP AWAY: the one the house is in. Without it, a player who
            had wandered off to read Aden had to type their own port's name to get back. */}
        {homePort && !query.trim() && (
          <div className="mt-2 flex flex-wrap items-center gap-1.5">
            <SectionLabel className="mb-0">Your fleet</SectionLabel>
            <Button
              variant={homePort.code === current ? 'chip-on' : 'chip'}
              onClick={() => onPick(homePort.code)}
            >
              {homePort.name}
            </Button>
          </div>
        )}

        {/* THE DESIGN SYSTEM'S CHIP, not a fourteenth hand-written copy of it. This grid used to
            spell out its own `bg-accent text-app` / `border border-edge bg-surface-2` pair, which
            is exactly the recipe `chip` / `chip-on` exists to be (buttonStyles.ts). It is also NOT
            wrapped in a local `PortChip` component: MARKET already declares one
            (features/market/MarketScreen.tsx:683) for the same job, and a second declaration of
            that name is the silent copy docs/SECTIONS.md warns a boundary converts sharing into.
            Two <Button>s composing one recipe is not a duplication; two components would be. */}
        <div className="mt-2 flex flex-wrap gap-1.5">
          {listed.map((p) => (
            <Button
              key={p.code}
              variant={p.code === current ? 'chip-on' : 'chip'}
              onClick={() => onPick(p.code)}
            >
              {p.name}
            </Button>
          ))}
        </div>
        {listed.length === 0 && (
          <p className="text-sm text-ink-muted">No harbour matches. Clear the field for all {formatInt(ports.length)}.</p>
        )}
      </Collapsible>
    </Card>
  )
}

function buyNote(good: MarketGood): string {
  // "of nearby ports", matching the one word the game uses for this figure ("nearby" — COMMAND's
  // good rows and MARKET's tiles). "neighbours" was a third name for it on a third screen.
  const nbr = good.pct_nbr === null ? 'alone on this coast' : `${formatPctPoints(good.pct_nbr)} of nearby ports`
  return `${good.buy} d./t · ${nbr}`
}

function ActionGroup({
  label,
  note,
  actions,
  empty,
  lineOf,
  onPick,
}: {
  label: string
  /** ONE live figure that is true of the whole group, printed once beside the label instead of
   *  repeated on every row (the free hold, which used to ride on all four buy lines). */
  note?: string
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
      <SectionLabel>
        {label}
        {note && <span className="ml-2 normal-case text-ink-muted">{note}</span>}
      </SectionLabel>
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
                  {a.note && <span className={fineClass('mt-0.5 block')}>{a.note}</span>}
                </button>
              </li>
            )
          })}
        </ul>
      )}
    </div>
  )
}
