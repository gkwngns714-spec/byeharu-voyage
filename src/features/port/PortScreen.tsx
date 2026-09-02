import { useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import {
  Badge,
  Button,
  Card,
  CardHeader,
  DetailRow,
  Explain,
  Notice,
  PageHeader,
  Screen,
  SectionLabel,
  TabRow,
  fineClass,
} from '../../components/ui'
import { formatInt, formatPct } from '../../lib/format'
import { portNameOf, useWorld } from '../../live/worldStore'
import type { MarketView, WorldSnapshot } from '../../lib/rpc'
import { useCommandDraft } from '../../domain/order'
import { AcademyFace } from './PortFaces'
import { PortTrade } from './PortTrade'
import { QuayToday } from './PortFair'
import { buildingsOf, buildingTier, hasBuilding } from '../../domain/port'
import { PortWarehouse } from './PortWarehouse'
import { PortWorkstation } from './PortWorkstation'
import { PORT_FACES, usePortView } from './portView'
import { harbourCode, useHarbour } from '../../store/harbour'
import type { CommandIntent } from '../../domain/order'
import { findVerb, orderText } from '../../domain/order'
import {
  SHIP_STATS,
  fleetPortCode,
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
  // tabs cannot derive different defaults. It still folds `housePortCode` internally; this screen
  // no longer names the house port separately, because the panel that pinned it first — the
  // harbour search — is gone (row 54).
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

  const docked = port ? fleets.filter((f) => f.port === port.code) : []
  const acting =
    docked[0] ?? fleets.find((f) => f.id === draftFleetId) ?? fleets[0] ?? null
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
  // shown face is derived from what is OFFERED rather than trusted from storage: never leave a
  // face up that this port cannot host.
  //
  // 0067: this line used to read `f.id !== 'academy' || port.has_academy` — one facility, named by
  // hand, in a screen. It is now the general rule it always was: a face that names a BUILDING is
  // offered where that building stands. The owner's warehouse, workstation, building yard and Inn
  // are each one entry in PORT_FACES and one row per city, and no line here changes for any of
  // them. That is the whole of what "a building is a concept" buys.
  const offeredFaces = PORT_FACES.filter((f) => f.building === null || hasBuilding(port, f.building))
  const shownFace = offeredFaces.find((f) => f.id === face) ?? offeredFaces[0]

  // The nearest water from here — the server's sailed figures (world.reach, 0039: the same
  // distance table the endurance gate and the trade scan read; the approach detour is inside
  // every number). The old one-leg graph is gone; "near" is now simply near, by sea.
  // 0067: the kinds, keyed once. The screen never names a building — the server does.
  const kindByCode = Object.fromEntries(snapshot.building_kinds.map((k) => [k.kind, k]))

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
            /* The Alongside face carried a ship-stat legend here; that face is gone (row 56),
               so every remaining face is its own one line and there is no branch left to make. */
            explain={shownFace.explain}
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
            /* The Alongside face carried a count of your hulls here; that face is gone
               (row 56) and no remaining face has a figure to put on its tab. */
          }))}
        />

        <div role="tabpanel">

          {/* ROW 53 — TRADE HAPPENS ON THE QUAY YOU ARE STANDING ON. The market read is the one
              this screen ALREADY makes (`markets[portId]`, above); the fold, the capacity read and
              the order line are COMMAND's own, imported rather than copied. See PortTrade.tsx for
              why this screen stopped being read-only. A fleet lying HERE is the one that trades:
              `docked[0]`, not `acting`, because `acting` may be a fleet bound elsewhere and a quay
              deals with the hull alongside it. */}
          {shownFace.id === 'market' && (
            <PortTrade
              goods={market?.goods ?? []}
              fleet={docked[0] ?? null}
              verbs={snapshot.verbs}
              step={snapshot.config.trade_step_tuns}
            />
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
                  {/* "CHEAPEST HERE" IS GONE — the owner, 2026-09-01: *"there is no need info -
                      cheapest here, the game is to challenge players for finding the best prices
                      by themselves."*

                      It is not a layout complaint, it is a rule about what this game IS. The row
                      ranked the port's three best bargains against their neighbours and printed
                      them, which is the answer to the question a trading game exists to ask. A
                      screen that hands over the answer has not saved the player a step; it has
                      removed the play.

                      Deleted rather than hidden, and `cheapHere` with it, so nothing computes an
                      answer nobody may read. What the city IS — how grown, the tax, the spread —
                      stays: those are facts about the place, not a ranking of where the money is.
                      The MARKET face beside it still prices every good on the quay, which is the
                      evidence the player reads to find the answer for themselves. */}
                </dl>

                {/* ── WHAT THIS CITY KEEPS (0067) ───────────────────────────────────────────
                    The owner: *"buildings are market, a workstation where you can create ship
                    related items - sail etc. inn where you can hire crew, find captains. etc. it
                    is a concept."*

                    This is the concept, visible. Every line is a ROW the server sent — the name
                    and the sentence come from `building_kinds`, so nothing here knows what a
                    workstation is, and a city that later builds one grows a line without this
                    file changing. Bilbao shows Bilbao's; a small harbour shows fewer.

                    A tier is printed only where it is above 1, because "Tier 1" on every line is
                    a column of noise: what a player wants to see is which city is BETTER at
                    something than the last one. */}
                <div className="mt-4">
                  <SectionLabel className="mb-1.5">What this city keeps</SectionLabel>
                  <dl className="space-y-1">
                    {buildingsOf(port).map((b) => {
                      const kind = kindByCode[b.kind]
                      return (
                        <DetailRow
                          key={b.kind}
                          label={kind?.name ?? b.kind}
                          value={`${kind?.does ?? ''}${b.tier > 1 ? ` · tier ${formatInt(b.tier)}` : ''}`}
                        />
                      )
                    })}
                  </dl>
                </div>
            </>
          )}

          {shownFace.id === 'warehouse' && <PortWarehouse portId={port.id} fleet={acting} />}

          {shownFace.id === 'workstation' && (
            <PortWorkstation
              portId={port.id}
              fleet={acting}
              tier={buildingTier(port, 'workstation')}
            />
          )}

          {shownFace.id === 'academy' && <AcademyFace acting={acting} />}
        </div>
      </Card>

    </Screen>
  )
}



