import { useNavigate } from 'react-router-dom'
import {
  Badge,
  Card,
  CardHeader,
  CollapsibleCard,
  Explain,
  Gauge,
  Meter,
  PageHeader,
  Screen,
  SectionLabel,
  TABLE_SCROLL_HINT,
  TD,
  TH,
  Table,
  scrollTableClass,
  fineClass,
  rowLinkClass,
} from '../../components/ui'
import {
  formatDucats,
  formatInt,
  formatKnots,
  formatNm,
  formatPct,
  formatPctPoints,
  formatRealShort,
  formatTuns,
  formatVoyageDays,
} from '../../lib/format'
import { useShellState } from '../../app/shellState'
import { useWorld } from '../../live/worldStore'
import type { FleetShip, FleetView, SnapshotConfig } from '../../lib/rpc'
import { useCommandDraft } from '../../domain/order'
import type { CommandIntent } from '../../domain/order'
import {
  busyUntilMs,
  fleetCargo,
  fleetCrew,
  fleetHoldTotal,
  fleetHoldUsed,
  fleetStatusTone,
  fleetStores,
  hullFraction,
  worstHullFraction,
  shipHoldFree,
  shipHoldUsed,
  voyageEtaMs,
  voyageFraction,
} from '../../domain/fleet'
import { ReadAgain, WorldFailed, WorldLoading } from '../../live/WorldGate'

// FLEETS — E.2's roster. THE READ-ONLY TAB.
//
// "No commands here. Every row is a READ; tapping a row copies its name into the CMD line." So
// this screen has exactly one interaction and it is a handoff: tapping a fleet writes a draft into
// the shared store and goes to Command. It never issues anything, and it never grows a button that
// does — law 2, "commands live on their own tab".
//
// ── THE NUMBERS ARE THE SERVER'S ────────────────────────────────────────────────────────────────
// This screen used to say "every number here is DERIVED, in fleetMath.ts, from the formulas in B.3,
// C.4 and C.5". That is no longer true and the file that made it true is deleted. `world.fleets()`
// carries `speed_kn` and `endurance_days`, computed inside the transaction that owns them — and it
// is THOSE figures SAIL refuses on. A client that recomputed them would eventually print a number
// the game does not obey, which is worse than printing nothing. What is left on this side is a
// ratio and a fold (fleetDerive.ts), each cited to the SQL it agrees with.
//
// ── READING IS HOW TIME PASSES ──────────────────────────────────────────────────────────────────
// There is no tick loop. `world.fleets()` settles every voyage server-side before it answers, so
// "Read again" is not a refresh button in the web sense — it is the clock. The countdown below is
// display only: when it reaches zero the fleet has NOT arrived, it is DUE, and the next read is
// what lands it. The roster says exactly that rather than pretending.

export function FleetsScreen() {
  // FIELDS, NOT THE STORE (worldStore.ts rule 4).
  const phase = useWorld((s) => s.phase)
  const fatal = useWorld((s) => s.fatal)
  const snapshot = useWorld((s) => s.snapshot)

  if (phase === 'failed') {
    return <WorldFailed eyebrow="Assets" title="Fleets" refusal={fatal} />
  }
  if (phase !== 'ready' || !snapshot) {
    return <WorldLoading eyebrow="Assets" title="Fleets" subtitle="What you own, and the state it is in." panels={3} />
  }
  return <FleetsBody config={snapshot.config} />
}

function FleetsBody({ config }: { config: SnapshotConfig }) {
  const fleets = useWorld((s) => s.fleets)
  const house = useWorld((s) => s.player)
  const portByCode = useWorld((s) => s.portByCode)
  const readAt = useWorld((s) => s.readAt)
  const mode = useWorld((s) => s.mode)
  const { nowMs } = useShellState()
  const navigate = useNavigate()
  const handOff = useCommandDraft((s) => s.handOff)

  // The draft is a structured INTENT, not a half-typed line (commandDraft.ts): the player is
  // making an order, not typing one. A hand-off from here says the verb and the fleet and leaves
  // the rest of the pickers open on Command.
  const command = (intent: CommandIntent) => {
    handOff(intent)
    navigate('/command')
  }

  // THE HOUSE COUNTS ITS OWN HULLS. `world.player()` serves `fleets` and `ships` (migration
  // 0014:140-141, straight `count(*)`), and this screen and RankScreen each folded the roster to
  // reach the same two figures. Reading them is one line shorter AND cannot disagree with the
  // Profile tab, which was already printing the served pair.
  //
  // NULL, NOT A FALLBACK FOLD. `?? fleets.length` would put the old count back as a second
  // answer for exactly the case the two answers could differ — a player read that failed while
  // the fleets read succeeded. An unread house prints a dash; the roster below is still drawn.
  const counts = house ? { fleets: house.fleets, ships: house.ships } : null
  const portName = (code: string | null) => (code ? (portByCode[code]?.name ?? code) : null)

  return (
    <Screen>
      <PageHeader
        eyebrow="Assets"
        title="Fleets"
        explain="What you own, and the state it is in. Endurance is in voyage-days; one voyage-day is three real minutes."
        actions={
          <>
            <span className="font-mono text-xs text-ink-faint">
              {counts ? counts.fleets : '—'}/{config.fleet_max} fleets ·{' '}
              {counts ? counts.ships : '—'}/{config.ship_max} ships
            </span>
            <ReadAgain />
          </>
        }
      />

      {fleets.length === 0 ? (
        <Card>
          <CardHeader eyebrow="Roster" title="No fleets" />
          <p className="text-sm text-ink-muted">
            The house owns nothing that floats. That is a world state, not an error.
          </p>
        </Card>
      ) : (
        <Card>
          <CardHeader
            eyebrow="Roster"
            title="All fleets"
            subtitle="Tap a fleet to command it."
            explain="Speed and endurance are the server's own figures — the ones SAIL refuses on. Endurance is in voyage-days; one voyage-day is three real minutes."
          />

          {/* ── THE ROSTER, TWICE ──────────────────────────────────────────────────────────────
              Six columns do not fit 390px. Scrolling them sideways is legitimate and every other
              table on this screen does exactly that — but ENDURANCE is the punchline of this
              particular table (it is the number that decides whether a voyage can be ordered at
              all), and putting the punchline behind a swipe is the same defect as clipping it.
              So below `sm` the roster STACKS: one block per fleet, every field labelled, nothing
              off-screen and nothing to swipe. From `sm` the table returns.
              Both read the SAME served fleet — there is no second source of these numbers. */}
          <ul className="space-y-2 sm:hidden">
            {fleets.map((fleet) => (
              <li key={fleet.id}>
                <button
                  type="button"
                  onClick={() => command({ verb: 'SAIL', fleetId: fleet.id })}
                  className="w-full rounded-md border border-edge bg-surface-2 p-3 text-left transition hover:border-accent/60"
                >
                  <span className="flex flex-wrap items-center gap-2">
                    <span className="font-mono text-sm text-accent">{fleet.name}</span>
                    <Badge tone={fleetStatusTone(fleet.status)}>{fleet.status}</Badge>
                    <span className={fineClass('ml-auto')}>
                      {fleet.ships.length} ship{fleet.ships.length === 1 ? '' : 's'}
                    </span>
                  </span>
                  <span className="mt-2 grid grid-cols-[auto_1fr] gap-x-3 gap-y-0.5 font-mono text-xs">
                    <span className="text-ink-faint">where</span>
                    <span className="text-ink">{whereText(fleet, portName)}</span>
                    <span className="text-ink-faint">due</span>
                    <span className="text-ink">{dueText(fleet, nowMs)}</span>
                    <span className="text-ink-faint">endurance</span>
                    <span className="text-ink">{formatVoyageDays(fleet.endurance_days)}</span>

                    {/* THE TWO FACTS THAT DECIDE THE NEXT ORDER, DRAWN AS COUNTABLE BLOCKS.
                        Hold and hull were figures buried in the per-fleet detail panel, one tap
                        and a scroll away. They belong on the roster: whether to buy is "how much
                        room is left", and whether to sail is "how sound is the worst hull". The
                        figure stays beside the blocks — a gauge you cannot read exactly is a mood
                        ring, and this is a ledger. See Gauge.tsx for why blocks and not a bar. */}
                    <span className="text-ink-faint">hold</span>
                    <span className="flex items-center gap-2">
                      <Gauge
                        value={fleetHoldUsed(fleet)}
                        max={fleetHoldTotal(fleet)}
                        tone={fleet.free_hold <= 0 ? 'warning' : 'accent'}
                        label={`hold, ${fleetHoldUsed(fleet)} of ${fleetHoldTotal(fleet)} tuns`}
                      />
                      <span className="text-ink">
                        {formatTuns(fleetHoldUsed(fleet), 0)}/{formatTuns(fleetHoldTotal(fleet), 0)}
                      </span>
                    </span>
                    <span className="text-ink-faint">hull</span>
                    <span className="flex items-center gap-2">
                      <Gauge
                        value={worstHullFraction(fleet)}
                        max={1}
                        tone={
                          worstHullFraction(fleet) < 0.4
                            ? 'danger'
                            : worstHullFraction(fleet) < 0.75
                              ? 'warning'
                              : 'success'
                        }
                        label={`worst hull, ${formatPct(worstHullFraction(fleet))}`}
                      />
                      <span className="text-ink">{formatPct(worstHullFraction(fleet))}</span>
                    </span>
                  </span>
                </button>
              </li>
            ))}
          </ul>

          <Table className={`hidden sm:block ${scrollTableClass()}`}>
            <thead>
              <tr>
                <TH>Name</TH>
                <TH align="num">Ships</TH>
                <TH>Status</TH>
                <TH>Where</TH>
                <TH align="num">Due</TH>
                <TH align="num">Speed</TH>
                <TH align="num">End.</TH>
              </tr>
            </thead>
            <tbody>
              {fleets.map((fleet) => (
                <tr key={fleet.id}>
                  <TD>
                    <button
                      type="button"
                      className={rowLinkClass('min-h-11 text-left font-mono')}
                      onClick={() => command({ verb: 'SAIL', fleetId: fleet.id })}
                    >
                      {fleet.name}
                    </button>
                  </TD>
                  <TD align="num">{fleet.ships.length}</TD>
                  <TD>
                    <Badge tone={fleetStatusTone(fleet.status)}>{fleet.status}</Badge>
                  </TD>
                  <TD>{whereText(fleet, portName)}</TD>
                  <TD align="num">{dueText(fleet, nowMs)}</TD>
                  <TD align="num">{formatKnots(fleet.speed_kn)}</TD>
                  <TD align="num">{formatVoyageDays(fleet.endurance_days)}</TD>
                </tr>
              ))}
            </tbody>
          </Table>
        </Card>
      )}

      {fleets.map((fleet) => (
        <FleetDetail
          key={fleet.id}
          fleet={fleet}
          config={config}
          nowMs={nowMs}
          onCommand={command}
        />
      ))}

      {readAt !== null && (
        <p className={fineClass('text-center')}>
          Read {formatRealShort(Math.max(0, nowMs - readAt))} ago
          {mode ? ` · ${mode}` : ''}
          <Explain label="how fresh this is" dotClassName="ml-0.5">
            A read is the catch-up: nothing on this screen ticks, so reading again is what settles a
            voyage and brings a fleet in.
          </Explain>
        </p>
      )}
    </Screen>
  )
}

function FleetDetail({
  fleet,
  config,
  nowMs,
  onCommand,
}: {
  fleet: FleetView
  config: SnapshotConfig
  nowMs: number
  onCommand: (intent: CommandIntent) => void
}) {
  // The two name INDEXES, selected here rather than handed down as part of a whole `world` prop.
  // Both are rebuilt only when the snapshot is (worldStore.ts:open), so a panel that draws a cargo
  // line is now untouched by a read that only moved a fleet.
  const goodByCode = useWorld((s) => s.goodByCode)
  const portByCode = useWorld((s) => s.portByCode)
  const cargo = fleetCargo(fleet)
  const crew = fleetCrew(fleet)
  const stores = fleetStores(fleet)
  const flagship = fleet.ships.find((s) => s.is_flagship) ?? null
  const fraction = voyageFraction(fleet)
  const etaMs = voyageEtaMs(fleet)
  const goodName = (code: string) => goodByCode[code]?.name ?? code
  const portName = (code: string) => portByCode[code]?.name ?? code

  return (
    <CollapsibleCard
      title={fleet.name}
      subtitle={flagship ? `flag: ${flagship.name} (${flagship.class})` : 'no flagship'}
      aside={<Badge tone={fleetStatusTone(fleet.status)}>{fleet.status}</Badge>}
      storageKey={`fleet-${fleet.id}`}
      defaultOpen
    >
      <div className="space-y-4">
        {fleet.voyage && fraction !== null && (
          <div className="space-y-1">
            <div className="flex flex-wrap items-baseline justify-between gap-2 font-mono text-xs">
              <span className="text-ink">
                {fleet.voyage.position
                  ? `${portName(fleet.voyage.position.from_code)} → ${portName(fleet.voyage.position.to_code)}`
                  : `→ ${portName(fleet.voyage.to)}`}
              </span>
              <span className="text-ink-muted">
                {formatNm(fleet.voyage.nm_done)} / {formatNm(fleet.voyage.total_nm)} ·{' '}
                {dueText(fleet, nowMs)}
              </span>
            </div>
            <Meter pct={fraction * 100} tone="accent" />
            <p className={fineClass()}>
              Bound for {portName(fleet.voyage.to)} at {formatKnots(fleet.speed_kn)}.
              {etaMs !== null && nowMs >= etaMs && ' She is DUE — read again to bring her in.'}
              <Explain label="this passage" dotClassName="ml-0.5">
                The ETA was frozen at departure and never moves (B.5); the position is the server's
                closed form, not an interpolation.
              </Explain>
            </p>
          </div>
        )}

        <div>
          <SectionLabel>
            Ships
            <Explain label="Ships" dotClassName="ml-0.5">
              Speed is a FLEET figure — {formatKnots(fleet.speed_kn)}, the slowest hull with the
              formation penalty already in it. The server does not report a per-hull speed, so this
              table does not print one.
            </Explain>
          </SectionLabel>
          <Table className={scrollTableClass()}>
            <thead>
              <tr>
                <TH>Ship</TH>
                <TH>Class</TH>
                <TH align="num">Hull</TH>
                <TH align="num">Crew</TH>
                <TH align="num">Hold</TH>
                <TH align="num">Load</TH>
                <TH align="num">Free</TH>
              </tr>
            </thead>
            <tbody>
              {fleet.ships.map((ship) => (
                <ShipRow key={ship.id} ship={ship} />
              ))}
            </tbody>
          </Table>
          <p className={fineClass('mt-1')}>{TABLE_SCROLL_HINT}</p>
        </div>

        <div>
          <SectionLabel>
            Cargo
            <Explain label="Cargo" dotClassName="ml-0.5">
              No average-cost column: the server carries what is aboard, not what it cost. The price
              you paid is on the Ledger, in the BOUGHT entry for the parcel.
            </Explain>
          </SectionLabel>
          {cargo.length === 0 ? (
            <p className="text-sm text-ink-muted">Empty hold.</p>
          ) : (
            <>
              <Table className={scrollTableClass()}>
                <thead>
                  <tr>
                    <TH>Good</TH>
                    <TH align="num">Units</TH>
                    <TH align="num">Bulk</TH>
                  </tr>
                </thead>
                <tbody>
                  {cargo.map((line) => (
                    <tr key={line.code}>
                      <TD>
                        <button
                          type="button"
                          className={rowLinkClass('min-h-11 text-left')}
                          onClick={() =>
                            onCommand({
                              verb: 'SELL',
                              fleetId: fleet.id,
                              // A good travels as its CODE: the parser splits on whitespace and a
                              // display name like "black pepper" would arrive as two arguments.
                              args: { good: line.code, qty: 'ALL' },
                            })
                          }
                        >
                          {goodName(line.code)}
                        </button>
                      </TD>
                      <TD align="num">{formatInt(line.qty)}</TD>
                      <TD align="num">{goodByCode[line.code]?.bulk ?? '—'}</TD>
                    </tr>
                  ))}
                  <tr>
                    <TD className="font-mono text-xs text-ink-faint">stowed</TD>
                    <TD align="num">{formatInt(cargo.reduce((n, l) => n + l.qty, 0))}</TD>
                    <TD align="num">
                      {formatTuns(fleet.ships.reduce((n, s) => n + s.cargo_tuns, 0), 1)}
                    </TD>
                  </tr>
                </tbody>
              </Table>
            </>
          )}
        </div>

        <div>
          <SectionLabel>
            Stores and hands
            {/* THIS USED TO SAY "Officers arrive with V1 (C.6): at V0 every expertise coefficient
                is 1.00". Migration 0017 made that false — a quartermaster now stretches the hold
                and a purser shaves the spread — and a hold figure that had quietly grown while the
                screen swore no officer could touch it is exactly the kind of lie one authority is
                supposed to end. `officer_pct` is the SERVER's own reading of what this fleet's
                officers are worth (already summed within the specialty and clamped at the world
                cap), so this sentence cannot drift from the number above it again. */}
            <Explain label="Stores and hands" dotClassName="ml-0.5">
              Stores share the hold with the cargo.{' '}
              {fleet.officer_pct.QUARTERMASTER > 0
                ? `Her quartermasters stow ${formatPctPoints(fleet.officer_pct.QUARTERMASTER)} more into the same hulls, and the hold figure below already carries it.`
                : 'No quartermaster is posted to her, so the hold is what the shipwright built.'}
            </Explain>
          </SectionLabel>
          <p className="font-mono text-xs text-ink-muted">
            water {formatTuns(stores.waterT, 1)} · food {formatTuns(stores.foodT, 1)} ·{' '}
            {formatVoyageDays(fleet.endurance_days)} of range · {formatInt(crew.aboard)} hands (
            {formatInt(crew.required)} needed, {formatInt(crew.max)} berths) · burns{' '}
            {formatTuns(crew.aboard * (config.water_per_crew_day + config.food_per_crew_day), 2)} and{' '}
            {formatDucats(crew.aboard * config.wage_per_crew_day)} a voyage-day.
          </p>
          {/* `free_hold` is not `total − used`, and printing it as though it were is what the
              deleted client copies did. It is the SERVER's `public.fleet_free_hold` (0017:183),
              which clamps per hull — a fleet with one over-stowed hull has less room than the
              subtraction suggests, and this line says the number a BUY will actually obey. */}
          <p className={fineClass('mt-1')}>
            hold {formatTuns(fleetHoldUsed(fleet), 1)} / {formatTuns(fleetHoldTotal(fleet))} ·{' '}
            {formatTuns(fleet.free_hold, 1)} free.
          </p>
        </div>

      </div>
    </CollapsibleCard>
  )
}

function ShipRow({ ship }: { ship: FleetShip }) {
  const hull = hullFraction(ship)
  const used = shipHoldUsed(ship)
  return (
    <tr>
      <TD>
        <span className="text-sm text-ink">
          {ship.name}
          {ship.is_flagship && (
            <span aria-label="flagship" title="flagship" className="ml-1 text-accent">
              ⚑
            </span>
          )}
        </span>
      </TD>
      <TD>
        <span className="text-xs text-ink-muted">{ship.class}</span>
      </TD>
      <TD align="num">
        <span className={hull < 0.5 ? 'text-danger' : hull < 0.8 ? 'text-warning' : ''}>
          {formatPct(hull)}
        </span>
      </TD>
      <TD align="num">
        <span className={ship.crew < ship.crew_required ? 'text-danger' : ''}>
          {formatInt(ship.crew)}/{formatInt(ship.crew_max)}
        </span>
      </TD>
      <TD align="num">{formatTuns(ship.hold)}</TD>
      <TD align="num">
        {formatTuns(used, 1)} ({formatPct(ship.hold > 0 ? used / ship.hold : 0)})
      </TD>
      <TD align="num">{formatTuns(shipHoldFree(ship), 1)}</TD>
    </tr>
  )
}

/** Where she lies, or where she is bound. `port` is a CODE and null at sea. */
function whereText(fleet: FleetView, portName: (code: string | null) => string | null): string {
  const here = portName(fleet.port)
  if (here) return here
  if (fleet.voyage) return `→ ${portName(fleet.voyage.to) ?? fleet.voyage.to}`
  return '—'
}

/**
 * The countdown. Two different served instants answer it — a voyage's `eta` and a busy fleet's
 * `busy_until` — and both are ISO STRINGS, parsed once in fleetDerive.ts.
 *
 * Past the instant it says "due", never "arrived": the client clock does not settle anything. The
 * server does, on the next read.
 */
function dueText(fleet: FleetView, nowMs: number): string {
  const at = voyageEtaMs(fleet) ?? busyUntilMs(fleet)
  if (at === null) return '—'
  return nowMs >= at ? 'due' : formatRealShort(at - nowMs)
}
