import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import {
  Badge,
  Button,
  Card,
  CardHeader,
  CollapsibleCard,
  Explain,
  Gauge,
  Input,
  Meter,
  Notice,
  PageHeader,
  Screen,
  SectionLabel,
  TabRow,
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
  formatOfTotal,
  formatPct,
  formatPctPoints,
  formatRealShort,
  formatTuns,
  formatVoyageDays,
} from '../../lib/format'
import { useShellState } from '../../app/shellState'
import { portNameOf, useWorld } from '../../live/worldStore'
import type { FleetShip, FleetView, ProvisionPreset, SnapshotConfig } from '../../lib/rpc'
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
import { pointLabel } from '../../domain/passage'
import { WorldFailed, WorldLoading } from '../../live/WorldGate'

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
// There is no tick loop. `world.fleets()` settles every voyage server-side before it answers, and
// AppShell makes that read every thirty seconds and on every tab focus — the clock needs no
// button, which is why the header's `read again` control is DELETED (the owner, 2026-08-23:
// "read again on top left of the game is useless. remove it"). The countdown below is display
// only: when it reaches zero the fleet has NOT arrived, it is DUE, and the next read — moments
// away — is what lands it. The roster says exactly that rather than pretending.

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
  const loadPresets = useWorld((s) => s.loadPresets)

  // The book of standing orders rides on this tab: the server fires them on arrival whether or
  // not anyone looks, so the read is display, not mechanism — unlike world.fleets, it winds
  // nothing and one fetch per mount is enough (the preset verbs each re-read it themselves).
  useEffect(() => {
    void loadPresets()
  }, [loadPresets])

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
  // The one authority for code -> name (worldStore.portNameOf). This was one of seven copies.
  const portName = (code: string | null) => (code ? portNameOf(portByCode, code) : null)

  return (
    <Screen>
      <PageHeader
        eyebrow="Assets"
        title="Fleets"
        /* THE UNITS ARE GLOSSED HERE, ONCE. The owner, 2026-08-22: "i want common words, stores?
           t? kn? what is theses." Three abbreviations carry most of this game's figures and
           nothing on any screen said what they were. This is the screen where all three appear
           together, so the glossary lives behind its dot rather than as a fourth footnote per
           panel. NOTE FOR WHOEVER OWNS src/lib/format: the real fix is that `formatVoyageDays`
           prints "15.0 d" while `formatDucats` prints "8,000 d." — the same letter for two units.
           A gloss cannot repair that; one authority spelling them out can. */
        explain="What you own, and the state it is in. t is a TUN — one cask of cargo room. kn is KNOTS, sea miles an hour. A figure in d is a voyage-day, and one voyage-day is three real minutes."
        actions={
          <span className="font-mono text-xs text-ink-faint">
            {counts ? counts.fleets : '—'}/{config.fleet_max} fleets ·{' '}
            {counts ? counts.ships : '—'}/{config.ship_max} ships
          </span>
        }
      />

      {fleets.length === 0 ? (
        <Card>
          <CardHeader eyebrow="Roster" title="No fleets" />
          <p className="text-sm text-ink-muted">
            The house owns nothing that floats. Not an error — a state.
          </p>
        </Card>
      ) : (
        <Card>
          {/* THE ENDURANCE SENTENCE WAS WRITTEN TWICE — here and on the PageHeader eight lines up,
              word for word. Two dots on one screen opening the same sentence is two authorities
              for it (docs/NO_SPAGHETTI.md §1); the header keeps it, because it is true of the
              whole screen, and this card explains only what is its own. */}
          <CardHeader
            eyebrow="Roster"
            title="All fleets"
            subtitle="Tap a fleet to command it."
            explain="Speed and provision are the server's own figures — the ones SAIL refuses on."
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
                    {/* "provision", not "endurance" or "range" — one figure had three names
                        across FLEETS and COMMAND, and PROVISION is the verb that refills it, so
                        the figure and the order share one word (owner label sweep, 2026-08-23). */}
                    <span className="text-ink-faint">provision</span>
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
                <TH align="num">Provision</TH>
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

      <PresetsCard />

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
            The game reads the world every half minute on its own — that read is what settles a
            voyage and brings a fleet in. Nothing here needs pressing.
          </Explain>
        </p>
      )}
    </Screen>
  )
}


// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE BOOK OF STANDING ORDERS (0034) — the house's provision presets, written and adjusted here.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// A preset is "keep her at N days of stores", named by the player, fired by the SERVER when a
// fleet under it makes port — sized there, from the crew aboard then. This card is the CRUD
// surface; which fleet sails under which order lives on each fleet's galley face, beside the
// figures the order governs. Controls are plain rows: pressing anything SELECTS or SAVES — no
// fold, no re-flow, nothing docked (the owner's rule, three times on 2026-08-23).
//
// NOT SEEDED, deliberately: a standing order is the player's own words, and six rows they did not
// write are clutter. New composes one ("Preset N", 15 days) already valid and obviously editable.

function PresetsCard() {
  const book = useWorld((s) => s.presets)
  const savePreset = useWorld((s) => s.savePreset)
  const refusal = useWorld((s) => s.refusal)
  const dismissRefusal = useWorld((s) => s.dismissRefusal)
  if (!book) return null

  // "Order N", not "Preset N": a preset is a software word, and the card already calls the thing
  // by its game name — a standing order. The player renames it anyway; the default just must not
  // teach them the schema's vocabulary (the owner's plain-words rule, 2026-08-23).
  const nextName = () => {
    for (let n = 1; n <= book.max + 1; n += 1) {
      const name = `Order ${n}`
      if (!book.presets.some((p) => p.name.toLowerCase() === name.toLowerCase())) return name
    }
    return 'Order'
  }

  return (
    <Card>
      <CardHeader
        title="Standing orders"
        subtitle="Keep a fleet at so many days of stores."
        explain="A preset is a standing order the server fills when the fleet makes port: it tops her stores up to the named days, sized for the crew aboard at that moment, and charges the purse. Stores share the hold with cargo, so a deeper order is less room to trade with. Apply one on a fleet's Galley face."
        aside={
          <span className="font-mono text-xs text-ink-faint">
            {book.presets.length}/{book.max}
          </span>
        }
      />
      {refusal && (
        <Notice tone="danger" className="mb-2">
          {refusal.sentence}{' '}
          <button type="button" className="underline" onClick={dismissRefusal}>
            dismiss
          </button>
        </Notice>
      )}
      {book.presets.length === 0 ? (
        <p className="text-sm text-ink-muted">The book is empty. Not an error — a state.</p>
      ) : (
        <ul className="space-y-2">
          {book.presets.map((preset) => (
            // Keyed on the SERVED values, so a save that lands re-seats the inputs on the
            // server's answer and a refused one is corrected on the next successful read.
            <PresetRow key={`${preset.id}:${preset.name}:${preset.days}`} preset={preset} />
          ))}
        </ul>
      )}
      <div className="mt-3">
        <Button variant="secondary" onClick={() => void savePreset(null, nextName(), 15)}>
          New
        </Button>
      </div>
    </Card>
  )
}

/** One standing order: its name, its days, the fleets under it, and the strike. Inputs commit on
 *  blur or Enter; a commit that changes nothing calls nothing. */
function PresetRow({ preset }: { preset: ProvisionPreset }) {
  const savePreset = useWorld((s) => s.savePreset)
  const deletePreset = useWorld((s) => s.deletePreset)

  const commitName = (raw: string) => {
    const name = raw.trim()
    if (name && name !== preset.name) void savePreset(preset.id, name, null)
  }
  const commitDays = (raw: string) => {
    const days = Math.trunc(Number(raw))
    if (Number.isFinite(days) && days !== preset.days) void savePreset(preset.id, null, days)
  }
  const blurOnEnter = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Enter') e.currentTarget.blur()
  }

  return (
    <li>
      {/* The WRAPPERS own the widths: Input's base recipe is w-full (its own header), so a width
          utility on the component fights it and the winner is CSS order — measured losing here,
          with the name squeezed to nothing. A sized span is unambiguous. */}
      <div className="flex items-center gap-2">
        <span className="min-w-0 flex-1">
          <Input
            defaultValue={preset.name}
            aria-label={`name of ${preset.name}`}
            onBlur={(e) => commitName(e.currentTarget.value)}
            onKeyDown={blurOnEnter}
            maxLength={24}
            className="font-mono"
          />
        </span>
        <span className="w-16 shrink-0">
          <Input
            defaultValue={String(preset.days)}
            aria-label={`days of ${preset.name}`}
            inputMode="numeric"
            onBlur={(e) => commitDays(e.currentTarget.value)}
            onKeyDown={blurOnEnter}
            className="text-right font-mono"
          />
        </span>
        <span className={fineClass()}>days</span>
        <Button
          variant="ghost"
          size="icon"
          aria-label={`delete ${preset.name}`}
          title="delete"
          onClick={() => void deletePreset(preset.id)}
        >
          ✕
        </Button>
      </div>
      {preset.fleets.length > 0 && (
        <p className={fineClass('mt-0.5')}>
          {preset.fleets.map((f) => f.name).join(' · ')}
        </p>
      )}
    </li>
  )
}

/** The three faces of one fleet. Not routes — a fleet is one card, and these are its sides. */
type FleetFace = 'ships' | 'cargo' | 'stores'

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
  const book = useWorld((s) => s.presets)
  const applyPreset = useWorld((s) => s.applyPreset)
  const cargo = fleetCargo(fleet)
  // Which standing order this fleet sails under — the BOOK is the authority (the fleet points at
  // a preset by reference on the server; the book serves that edge), so nothing here is a copy.
  const preset = book?.presets.find((p) => p.fleets.some((f) => f.id === fleet.id)) ?? null
  // Docked under an order she no longer meets: the served figure against the served target, with
  // the same 0.01-day dust floor the server's own satisfied-check uses (0034).
  const presetShort =
    preset !== null && fleet.status === 'DOCKED' && fleet.endurance_days < preset.days - 0.01
  // WHICH FACE OF THIS FLEET IS TURNED TOWARDS YOU. Per-fleet, not shared: two cards open at once
  // must be able to show different faces, and a single shared value would move both.
  const [face, setFace] = useState<FleetFace>('ships')
  const crew = fleetCrew(fleet)
  const stores = fleetStores(fleet)
  const flagship = fleet.ships.find((s) => s.is_flagship) ?? null
  const fraction = voyageFraction(fleet)
  const etaMs = voyageEtaMs(fleet)
  const goodName = (code: string) => goodByCode[code]?.name ?? code
  const portName = (code: string) => portNameOf(portByCode, code)

  return (
    <CollapsibleCard
      title={fleet.name}
      subtitle={flagship ? `flagship: ${flagship.name} (${flagship.class})` : 'no flagship'}
      aside={<Badge tone={fleetStatusTone(fleet.status)}>{fleet.status}</Badge>}
      storageKey={`fleet-${fleet.id}`}
      defaultOpen
    >
      <div className="space-y-4">
        {fleet.voyage && fraction !== null && (
          <div className="space-y-1">
            <div className="flex flex-wrap items-baseline justify-between gap-2 font-mono text-xs">
              <span className="text-ink">
                {/* 0039: a course has no port-pair under her keel any more; the passage reads as
                    where she is bound - a harbour, or the pinpointed water. */}
                {'→ '}
                {fleet.voyage.to
                  ? portName(fleet.voyage.to)
                  : fleet.voyage.dest_point
                    ? pointLabel({ lat: fleet.voyage.dest_point[0], lon: fleet.voyage.dest_point[1] })
                    : 'open sea'}
              </span>
              <span className="text-ink-muted">
                {formatNm(fleet.voyage.nm_done)} / {formatNm(fleet.voyage.total_nm)} ·{' '}
                {dueText(fleet, nowMs)}
              </span>
            </div>
            <Meter pct={fraction * 100} tone="accent" />
            <p className={fineClass()}>
              Bound for{' '}
              {fleet.voyage.to
                ? portName(fleet.voyage.to)
                : fleet.voyage.dest_point
                  ? pointLabel({ lat: fleet.voyage.dest_point[0], lon: fleet.voyage.dest_point[1] })
                  : 'open sea'}{' '}
              at {formatKnots(fleet.speed_kn)}.
              {etaMs !== null && nowMs >= etaMs && ' She is DUE — any moment now.'}
              <Explain label="this passage" dotClassName="ml-0.5">
                The ETA was frozen at departure and never moves (B.5); the position is the server's
                closed form, not an interpolation.
              </Explain>
            </p>
          </div>
        )}

        {/* THE GALLEY IS ITS OWN FACE (the owner, 2026-08-23: "내 주방 separate tab but next the
            dishes. like before"). A fleet card used to stack all three of these down one column, so
            the stores — the figures that decide whether she can sail at all — sat below a cargo
            table and were read last, if at all. "like before" is the PORT panel, whose faces this
            copies; TabRow is the same primitive, and it WRAPS rather than scrolls for the reason
            written in its header. */}
        <TabRow
          label={`${fleet.name} faces`}
          value={face}
          onChange={setFace}
          tabs={[
            { id: 'ships', label: 'Ships', hint: fleet.ships.length },
            { id: 'cargo', label: 'Cargo', hint: cargo.length || undefined },
            { id: 'stores', label: 'Galley' },
          ]}
        />

        <div role="tabpanel">
          {face === 'ships' && (
            <>
              <div>
                <SectionLabel>
                  Ships
                  <Explain label="Ships" dotClassName="ml-0.5">
                    Speed is a FLEET figure — {formatKnots(fleet.speed_kn)}, the slowest hull with the
                    formation penalty in it. The server reports no per-hull speed, so no column prints one.
                  </Explain>
                </SectionLabel>
                <Table scrollHint className={scrollTableClass()}>
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
              </div>
            </>
          )}
          {face === 'cargo' && (
            <>
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
            </>
          )}
          {face === 'stores' && (
            <>
              <div>
                {/* NO HEADING HERE. The tab above already says GALLEY, and a panel that repeats its
                    own tab's name spends a line saying nothing — the same "too much unnecessary
                    info" the owner named. ("Stores and hands" was the older phrase; it is a
                    sailor's, not a common one, which is why the tab is not called that either.)
                    The disclosure it used to carry did not die with the heading — it moved DOWN to
                    the `hold` row, which is the row it is actually about (stores share the hold; a
                    quartermaster stretches it). A dot floating alone above a grid, attached to
                    nothing, was the shape that replaced it, and that is not better than a heading. */}
                {/* ═══════════════════════════════════════════════════════════════════════════════════
                    SIX FACTS IN ONE SENTENCE BECAME SIX LABELLED ROWS.
                    ═══════════════════════════════════════════════════════════════════════════════════
                    This was one run-on mono paragraph — "water 3.5 t · food 0.2 t · 15.0 d of range · 8
                    hands (6 needed, 20 berths) · burns 0.42 and 8 d. a voyage-day." — with the hold on a
                    second line beneath it. At 390px it wrapped to four lines and no figure could be
                    found without reading the prose around it, which is exactly what
                    docs/UI_DIRECTION.md §4 rule 2 forbids: the number is the hero, tabular and aligned,
                    and the label is the small dim thing beside it.

                    Every figure is the same figure it was, from the same reading (`fleetStores`,
                    `fleetCrew`, and the SERVER's `free_hold` — `public.fleet_free_hold`, 0017:183, which
                    clamps per hull, so it is NOT `total − used` and is never printed as though it were).
                    The grid is the roster's own two-column recipe, ten lines above. */}
                <dl className="grid grid-cols-[auto_1fr] gap-x-3 gap-y-0.5 font-mono text-xs">
                  <dt className="text-ink-faint">water</dt>
                  <dd className="text-ink">{formatTuns(stores.waterT, 1)}</dd>
                  <dt className="text-ink-faint">food</dt>
                  <dd className="text-ink">{formatTuns(stores.foodT, 1)}</dd>
                  {/* "provision", not "range" — the same served figure had three names across two
                      screens (endurance / range / provision); PROVISION is the verb that refills
                      it, so the figure, the verb and the standing order share one word. WARNING
                      tone while she is docked under a standing order she no longer meets — the
                      "hire 20 at Cádiz and her range collapses" case, made visible BEFORE she
                      sails rather than discovered at sea. The figure itself is still the server's
                      endurance_days; nothing here recomputes it. */}
                  <dt className="text-ink-faint">provision</dt>
                  <dd className={presetShort ? 'text-warning' : 'text-ink'}>
                    {formatVoyageDays(fleet.endurance_days)}
                    {presetShort && preset && ` — under her ${formatVoyageDays(preset.days)} order`}
                  </dd>
                  {/* THE STANDING ORDER, and the crew it is measured against ("crew now, but show
                      it clearly" — the owner). The days figure is meaningless without the crew it
                      assumes, so the two travel together; the crew is the crew ABOARD, read live,
                      because that is exactly what the server will size the next top-up from. */}
                  <dt className="text-ink-faint">keep</dt>
                  <dd className="text-ink">
                    {preset
                      ? `${preset.name} · ${formatVoyageDays(preset.days)} · at ${formatInt(crew.aboard)} crew`
                      : '—'}
                  </dd>
                  {/* "crew", NOT "hands" (the owner, 2026-08-23: "and hands? seriously? change it
                      like crew or something"). Sailor's cant reads as period flavour to whoever
                      writes it and as nonsense to whoever plays it — same no-jargon rule that
                      renamed the map's `fit` control. The server's own refusals and voyage
                      reports said "hands" too until migration 0030 renamed them the same day —
                      one wording decision, both sides of the wire. */}
                  <dt className="text-ink-faint">crew</dt>
                  <dd className="text-ink">
                    {formatInt(crew.aboard)}/{formatInt(crew.max)} · {formatInt(crew.required)} needed
                  </dd>
                  {/* "cargo", matching the COMMANDING card's label and figure shape for the same
                      pair (one name per figure — the label sweep, 2026-08-23). The served
                      free_hold stays: it clamps per hull (0017) and is NOT total − used, which is
                      why it is printed rather than derived. */}
                  <dt className="text-ink-faint">cargo</dt>
                  <dd className="text-ink">
                    {formatOfTotal(fleetHoldUsed(fleet), fleetHoldTotal(fleet))} t ·{' '}
                    {formatPct(fleetHoldTotal(fleet) > 0 ? fleetHoldUsed(fleet) / fleetHoldTotal(fleet) : 0)} full ·{' '}
                    {formatTuns(fleet.free_hold, 1)} free
                    {/* THIS SENTENCE USED TO SAY "Officers arrive with V1 (C.6): at V0 every expertise
                        coefficient is 1.00". Migration 0017 made that false — a quartermaster stretches
                        the hold and a purser shaves the spread — and a hold figure that had quietly
                        grown while the screen swore no officer could touch it is exactly the kind of lie
                        one authority is supposed to end. `officer_pct` is the SERVER's own reading of
                        what this fleet's officers are worth (already summed within the specialty and
                        clamped at the world cap), so it cannot drift from the number beside it. */}
                    <Explain label="the hold" dotClassName="ml-0.5">
                      Stores share the hold with the cargo.{' '}
                      {fleet.officer_pct.QUARTERMASTER > 0
                        ? `Her quartermasters stow ${formatPctPoints(fleet.officer_pct.QUARTERMASTER)} more into the same hulls, and the figure above already carries it.`
                        : 'No quartermaster is posted to her, so the hold is what the shipwright built.'}
                    </Explain>
                  </dd>
                  <dt className="text-ink-faint">a day</dt>
                  <dd className="text-ink">
                    {formatTuns(crew.aboard * (config.water_per_crew_day + config.food_per_crew_day), 2)}{' '}
                    · {formatDucats(crew.aboard * config.wage_per_crew_day)}
                  </dd>
                </dl>

                {/* WHICH ORDER SHE SAILS UNDER — one tap to set, one tap (None) to clear, every
                    chip 44px, and pressing one SELECTS: nothing folds, moves or re-flows. The
                    order fires when she makes port, and only there; nothing is bought here. */}
                {book && book.presets.length > 0 && (
                  <div className="mt-3 flex flex-wrap gap-2">
                    <Button
                      variant={preset === null ? 'chip-on' : 'chip'}
                      onClick={() => void applyPreset(fleet.id, null)}
                    >
                      None
                    </Button>
                    {book.presets.map((p) => (
                      <Button
                        key={p.id}
                        variant={p.id === preset?.id ? 'chip-on' : 'chip'}
                        onClick={() => void applyPreset(fleet.id, p.id)}
                      >
                        {p.name} · {formatVoyageDays(p.days)}
                      </Button>
                    ))}
                  </div>
                )}
              </div>
            </>
          )}
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
