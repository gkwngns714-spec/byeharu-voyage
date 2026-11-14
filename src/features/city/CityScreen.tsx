import { useEffect, useMemo, useState, type ReactNode } from 'react'
import { useSearchParams } from 'react-router-dom'
import { Card, Icon, KEEP_WORDS_CLASS, LoadMeter, Note, PageSplit, Row, ScrollPane, Sheet, type IconName, type LoadStep } from '../../components/ui'
import { ShellStateContext, useShellState } from '../../app/shellState'
import { ShellFrame } from '../../app/ShellFrame'
import { alongsideAt, fleetPortCode, housePortCode, whereabouts, whereLine } from '../../domain/fleet'
import { useCommandDraft } from '../../domain/order'
import { MarketLeft } from '../../live/MarketLeft'
import { PORT_PLACE, PRODUCTION_PLACE } from '../../live/cityFaces'
import { PortProduction } from '../../live/PortProduction'
import { useCityKinds } from '../../live/useCityKind'
import { useTownHall } from '../../live/useTownHall'
import { PortFlag } from '../../live/PortFlag'
import { CityFlag } from '../../live/CityFlag'
import { portNameOf, portNationOf, useWorld } from '../../live/worldStore'
import { useWorldBeat } from '../../live/worldStore'
import { worldLoadSteps } from '../../live/loadSteps'
import type { FleetView, Refusal, SnapshotPort, TownHallView } from '../../lib/rpc'
import { gameSunInstantMs } from '../../lib/format'
import { daylightAt, subsolarPoint } from '../../chart'
import { serverNow } from '../../lib/serverClock'
import { useT, type TKey } from '../../lib/i18n'
import { regardBandWord } from '../../domain/port'
import { CityFacePanel, type CityBuilding } from './CityFace'
import { CityHallPanel } from './CityHallPanel'
import { CityScene } from './CityScene'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE CITY PAGE — a city, full screen (owner's "Game screen development", 2026-10-30)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// THE PAGE (2026-11-04, owner row 267: *"everything is on left, too packed. this was a mistake"*): the HQ is no longer a 100dvh frame
// split 50/50 with panels that scroll inside themselves. It is a PAGE on the pattern Stats set (`Sheet layout="page"`, docs/dev-log/
// 2026-11-04-hq-design.md): the name for the title, the six places as a row of cards, then MAIN | SIDE from 1,024 px — MAIN the plan,
// SIDE the tray's column (your purse over the open place's panel); one column below it, the panel before the plan. The page scrolls.
// The brief below stands, with its words moved: "left" is MAIN, "right" is SIDE.
//
// THE BRIEF: THE HQ SCREEN IS A FRAME AROUND TWO REGIONS (owner, 2026-10-31: *"in buildings 6
// building tappable should always be inside. when pressed each building, HQ stays the same, but
// the the location where the city image is, as well as the right side should only change."*). The
// frame — the header, the six building tiles, the rail — never moves. The two regions: the city's
// plan on the LEFT (its mark moving to the open place) and on the RIGHT the open place's panel —
// the Town Hall by default, else the building's own COMPACT panel. The plan stays on the glass for
// every place (owner, 2026-10-31: the market's basket "opens inside the building's own region —
// the right-hand panel (with the city-image area left)").
//
// ── THE FIGURES LIVE IN THE HALL PANEL, NOT THE FRAME (owner, 2026-10-31) ─────────────────────
// *"I DON'T NEED TO SEEP POPULATION AND RELATION, ANYTHING THAT WAS ALREADY SHOWN ON TOWN HALL"*
// and *"MARKET- BASKET? WTF IS THIS POPPING UP BLOCKING THE WHOLE SCREEN? FIX THIS…"* — the frame's
// full-width figures card printed Population · Gold · Status · Relationship · Your earnings above
// every building face, repeating the hall. The five are now the hall panel's own compact block
// (Population · Gold · Status · Relationship · Employees) and no other face prints them. The frame
// is header + six tiles + rail, identical across every press, and the room the card gave back is
// what lets the hall show its book and its fold at 390×568 without scrolling.
//
// YOUR purse is the STATUS STRIP's (app/TopBar.tsx), as on every other screen. The frame kept a
// "Your earnings" line of its own while the HQ had no strip; S9 (2026-11-11) gave it the shell's
// frame, the line then printed the same `ducats` twice on one glass, and it was removed.
//
// ── WHAT IS REAL ON THIS SLICE, AND WHAT IS NOT ────────────────────────────────────────────────
// This is the SHELL. It is client-only: there is no migration and no new served field.
//   real       the city (the fleet's docked port, or `?port=`), its flag and country, day/night off
//              the served clock, the city's GOLD (`world.town_hall` purse — the treasury the server
//              already serves), your own influence points (`world.town_hall.influence.you.points`),
//              your EMPLOYEES (the crew aboard your hulls, from `world.fleets`), RELATIONSHIP (the
//              harbour's served stance toward that nation — `world.town_hall.dues.stance`,
//              `public.power_stance`: home / ally / peace / rival / war), and every building face,
//              which is the existing one composed (CityFace.tsx).
//   served     Population too, since 0304: `world.town_hall.people` (a real-world figure that grows, holds or
//              shrinks every 10 minutes). Nothing here is a guess, and the five figures ride the hall's ONE
//              served block — no cell asks a second read.
//
// ── WHY IT SITS OUTSIDE AppShell ──────────────────────────────────────────────────────────────
// The page draws its OWN header, and it stands in the shell's own FRAME (app/ShellFrame.tsx: the status
// strip, the page, and the one NavBar as its rail — never a second nav). It is a sibling of `/ui`,
// inside `RequireAuth` but not inside `AppShell` (src/app/App.tsx) — and for the same reason it
// provides the one thing the shell normally provides to a face: the clock (`ShellStateContext`).
// It opens the world itself, idempotently. `data-world` is on the root so the browser specs' one
// "is the world up" wait (tests/appReady.fixture.ts) works here too.

/** The served stances (`public.power_stance`, via `world.town_hall.dues`: home / ally / peace /
 *  rival / war) and the plain facts left when the dues block is not served (economy open, purse
 *  dark, no company): the two SERVED nations, compared — never a guessed ally or war. */
type Relation = 'home' | 'ally' | 'peace' | 'rival' | 'war' | 'different' | 'free' | 'none'
const RELATION_WORDS: Record<Relation, TKey> = {
  home: 'city.relationHome',
  ally: 'city.relationAlly',
  peace: 'city.relationPeace',
  rival: 'city.relationRival',
  war: 'city.relationWar',
  different: 'city.relationDifferent',
  free: 'city.relationFree',
  none: 'city.relationNone',
}

/** THE LOADING METER'S STEPS (owner, 2026-10-31: "show percentage of its loading time") — the
 *  screen's REAL reads, each `done` at its own completion event and nothing else. The world's
 *  three boot completions are every screen's (live/loadSteps.ts, which the map composes too);
 *  the fourth is the city's own served read, the hall. Four equal steps until a caller knows a size. */
function loadStepsFor(t: ReturnType<typeof useT>, boot: number, hallDone: boolean): readonly LoadStep[] {
  return [...worldLoadSteps(t, boot), { id: 'hall', label: t('city.loadHall'), done: hallDone }]
}

/** THE FIVE PLACES — one row of the frame, the Town Hall first (the page's main panel), then the
 *  buildings. Production takes the page under the row, storage, cargo and recipes across (owner, 2026-11-06). A press changes the plan's mark and the right panel; it moves no cell (owner,
 *  2026-10-31: the frame "stays the same"). */
type CitySelection = 'hall' | typeof PRODUCTION_PLACE | CityBuilding
const CITY_TILES: readonly { id: CitySelection; icon: IconName; label: TKey }[] = [
  { id: 'hall', icon: 'wreath', label: 'city.cityHall' },
  { id: 'market', icon: 'chart', label: 'city.market' },
  { id: PRODUCTION_PLACE, icon: 'mallet', label: 'city.production' },
  { id: 'port', icon: 'ship', label: 'city.port' },
  { id: 'inn', icon: 'crew', label: 'city.inn' },
]

export function CityScreen() {
  const t = useT()
  const [params] = useSearchParams()
  const phase = useWorld((s) => s.phase)
  // THE BOOT'S REAL STEPS, for the loading meter (worldStore's own completion counts).
  const boot = useWorld((s) => s.boot)

  // THE WORLD OPENS HERE, once, exactly as AppShell opens it for the tabs (open() is idempotent).
  useEffect(() => {
    void useWorld.getState().open()
  }, [])
  // AND THE SAME BEAT the shell arms: this page stands outside AppShell, so without it the city's
  // served reads (the hall, the market, the requests) were asked once and frozen while the player
  // stood here. One spelling (live/worldStore.ts's useWorldBeat).
  useWorldBeat()

  // THE ONE CLOCK, for the faces composed inside a building (the shell's own contract, shellState.ts).
  // This route is outside AppShell, so it is the shell for the length of this page.
  const [nowMs, setNowMs] = useState(() => serverNow())
  useEffect(() => {
    const id = window.setInterval(() => setNowMs(serverNow()), 1000)
    return () => window.clearInterval(id)
  }, [])
  const shell = useMemo(() => ({ nowMs }), [nowMs])

  const fleets = useWorld((s) => s.fleets)
  const portByCode = useWorld((s) => s.portByCode)
  const draftFleetId = useCommandDraft((s) => s.fleetId)

  // THE CITY IN HAND: an explicit `?port=`, else the port of the fleet in hand (its docked port,
  // or where she is bound), else the house's — `housePortCode` is domain/fleet's one answer.
  const explicit = params.get('port')
  const draftPort = fleets.find((f) => f.id === draftFleetId)
  const code = explicit ?? (draftPort ? fleetPortCode(draftPort) : null) ?? housePortCode(fleets)
  const port = code ? (portByCode[code] ?? null) : null

  const gate = (body: ReactNode) => (
    <ShellStateContext.Provider value={shell}>
      {/* THE SHELL'S FRAME (2026-11-11, S9): the same status strip every tab has over the page, and the nav — a bar on a phone,
          the rail from `lg` — in its slot, named `city-rail`. Every state below draws inside it, so none is a dead end. */}
      <ShellFrame data-world={phase} data-testid="city-screen" navTestId="city-rail">
        {body}
      </ShellFrame>
    </ShellStateContext.Provider>
  )

  // A page that cannot draw its city still keeps its RAIL: since this route is the app's landing
  // screen, a failure or a fleet with no harbour must never be a dead end — map, stats, the menu and
  // the way back to the desk stay one press away.
  if (phase === 'failed') {
    const fatal = useWorld.getState().fatal
    return gate(
      <>
        <div className="flex-1 p-gutter">
          <Note tone="danger" code={fatal?.code} figures={fatal?.figures}>
            {fatal?.sentence ?? t('city.failed')}
          </Note>
        </div>
      </>,
    )
  }
  if (phase !== 'ready')
    return gate(
      <>
        <div className="flex-1 p-gutter">
          <LoadMeter steps={loadStepsFor(t, boot, false)} data-testid="city-load" />
        </div>
      </>,
    )
  if (!port || port.kind !== 'HARBOUR')
    return gate(
      <>
        <NoCity fleets={fleets} inHand={draftPort ?? null} />
      </>,
    )

  return gate(<CityBody port={port} draftFleetId={draftFleetId} />)
}

/** THE HQ WITH NO CITY IN HAND (2026-11-02, the HQ-on-a-phone slice; the sweep's row 8). The fleet in hand is bound for a cape or open water, so there is no harbour to
 *  stand in — and the page was ONE line ("No city in hand.") over 740 px of nothing at 390, with no way to pick another fleet. It says what it can: that line, and YOUR
 *  FLEETS — each with what she is doing now (the one where-rule, `whereLine`, her countdown on the page's clock), the one in hand in gold — and a press on a fleet
 *  SELECTS her (the command draft's one selection, the same the desk's picker and the Map write): bring one that lies in a harbour into hand and the page is that
 *  harbour. The picker's own component belongs to another screen (`features/command`), which this one may not import (tests/sections.spec.ts); the list is the picker
 *  here, as rows, and it needs no popover because the glass has the room. The rail stays as it was. */
function NoCity({ fleets, inHand }: { fleets: readonly FleetView[]; inHand: FleetView | null }) {
  const t = useT()
  const { nowMs } = useShellState()
  const portByCode = useWorld((s) => s.portByCode)
  const selectFleet = useCommandDraft((s) => s.selectFleet)
  return (
    <div className="flex min-h-0 flex-1 flex-col px-gutter pb-1.5 pt-1.5" data-testid="city-nocity">
      <Note tone="neutral">{t('city.noCity')}</Note>
      {fleets.length > 0 && (
        <section className="mt-2 flex min-h-0 flex-col rounded-tile bg-surface px-gutter pt-1" data-testid="city-nocity-fleets">
          <h2 className="pb-1 text-t-caption text-ink-faint">{t('command.fleets')}</h2>
          <ScrollPane className="min-h-0">
            {fleets.map((f) => (
              <Row
                key={f.id}
                label={f.name}
                chevron
                tone={f.id === inHand?.id ? 'accent' : 'default'}
                onClick={() => selectFleet(f.id)}
                data-testid="city-nocity-fleet"
              >
                <span className="block text-t-caption text-ink-faint">{whereLine(whereabouts(f), (code) => portNameOf(portByCode, code), nowMs)}</span>
              </Row>
            ))}
          </ScrollPane>
        </section>
      )}
    </div>
  )
}

/** Everything that reads served city data — mounted only once the world is up. */
function CityBody({
  port,
  draftFleetId,
}: {
  port: SnapshotPort
  draftFleetId: string | null
}) {
  const fleets = useWorld((s) => s.fleets)
  const allegiance = useWorld((s) => s.allegiance)

  // The fleet acting for this city: one of yours lying here, else nobody (a read-only city).
  const { docked } = alongsideAt(fleets, port.code, draftFleetId)
  const fleet = docked[0] ?? null
  const [params] = useSearchParams()

  // ONE HALL READ FEEDS THE WHOLE PAGE: the hall panel (the treasury, the influence book, the
  // investors board) and its five-figure block — the city's gold, YOUR STATUS
  // (`influence.you.points`) and the town's RELATIONSHIP (`dues.stance`). Nothing recomputed here.
  const hallRead = useTownHall(port.id)
  const hall = hallRead.view?.view ?? null
  const hallRefusal = hallRead.view?.refusal ?? null

  const employees = useMemo(
    () => fleets.reduce((n, f) => n + f.ships.reduce((m, s) => m + s.crew, 0), 0),
    [fleets],
  )

  // WHICH PLACE IS OPEN — the Town Hall until a tile is pressed.
  // `?place=production` is the door the desk's Production tab and every old Storage link goes through.
  const [selected, setSelected] = useState<CitySelection>(params.get('place') === PRODUCTION_PLACE ? PRODUCTION_PLACE : params.get('place') === PORT_PLACE ? PORT_PLACE : 'hall')

  return (
    <CityFrame
      port={port}
      fleet={fleet}
      docked={docked}
      hall={hall}
      hallRefusal={hallRefusal}
      employees={employees}
      allegiance={portNationOf(allegiance, port.code)}
      selected={selected}
      onSelect={setSelected}
    />
  )
}

/** The frame itself: header, the HQ split (plan + the open place's panel), the six tiles, the rail.
 *  The frame is box-stable across every press — the plan's MARK and the right panel are the only
 *  things a press changes. */
function CityFrame({
  port,
  fleet,
  docked,
  hall,
  hallRefusal,
  employees,
  allegiance,
  selected,
  onSelect,
}: {
  port: SnapshotPort
  /** A fleet of yours lying HERE (the city's acting fleet), or null — a read-only city. */
  fleet: FleetView | null
  /** Your fleets lying here: Production picks among them. */
  docked: readonly FleetView[]
  hall: TownHallView | null
  hallRefusal: Refusal | null
  employees: number
  allegiance: ReturnType<typeof portNationOf>
  selected: CitySelection
  onSelect: (s: CitySelection) => void
}) {
  const t = useT()
  const { nowMs } = useShellState()
  const kind = useCityKinds()(port.code)
  // THE LOADING METER, WHILE THE SCREEN IS STILL LOADING: the world steps ride `boot`, the hall
  // step is this screen's own read. It is NOT part of the frame (it is gone at ready, when every
  // frame proof runs), and it updates on step completion only.
  const boot = useWorld((s) => s.boot)
  const hallDone = hall !== null || hallRefusal !== null
  // DAY/NIGHT is the world's ONE sun (chart/sun), at the game clock's hour, over THIS city — never a
  // local-time hour: every player sees the same night, and it matches the Map's own day sheet.
  const night = daylightAt({ lat: port.lat, lon: port.lon }, subsolarPoint(gameSunInstantMs(nowMs))) < 0.5

  // THE RELATIONSHIP IS THE SERVER'S STANCE while the hall answers it (`public.power_stance`,
  // between the nation you sail for and the city's holder): home / ally / peace / rival / war.
  // While the dues block is not served it falls back to the two SERVED nations themselves — the
  // same `world.allegiance` holder the header's flag reads and your own house's nation: same
  // nation is a fact, different nations are a fact, never a guessed ally or war.
  const houseNation = useWorld((s) => s.player?.nation ?? null)
  const portNation = allegiance?.nation ?? null
  const stance = hall?.dues?.stance ?? null
  // 0319: lit, the Relationship reads what this country thinks of YOUR company, which the stance only starts (`dues.regard`, docs/WORLD_POWERS.md §2.1).
  const regard = hall?.dues?.regard ?? null
  const relation: Relation =
    stance ?? (houseNation === null ? 'none' : portNation === null ? 'free' : houseNation === portNation ? 'home' : 'different')

  return (
    <>
      {/* THE PAGE (2026-11-04, owner row 267: *"everything is on left, too packed"* — the HQ takes the pattern Stats set, `Sheet layout="page"`,
          docs/dev-log/2026-11-04-hq-design.md): the city's name for the title, the day or night beside it, then the six places as a row of
          cards across the page, then MAIN | SIDE — MAIN the plan (the market's chart when the market is open), SIDE the tray's column: your purse
          over the open place's panel. The page scrolls; nothing inside it does. */}
      <main className="min-h-0 flex-1">
        <Sheet
          layout="page"
          data-testid="city-page"
          title={
            // THE NAME TURNS ONLY AT A SPACE, AND THE KIND GOES UNDER IT WHOLE (2026-11-14, owner row 318): on a 320-px glass "Port Royal",
            // "Island capital" and the day stood on one line, each of the two turned in half. The flag and the name are one piece.
            <span className="flex flex-wrap items-center gap-x-3 gap-y-0.5" data-testid="city-header">
              <span className="flex min-w-0 items-center gap-3">
                <PortFlag code={port.code} size="title" />
                <span className={KEEP_WORDS_CLASS} data-testid="city-name">
                  {port.name}
                </span>
              </span>
              {kind && (
                <span className="whitespace-nowrap text-t-label font-normal text-ink-muted" data-testid="city-kind">
                  {t(kind.label)}
                </span>
              )}
            </span>
          }
          trailing={
            <span
              className="rounded-chip bg-surface-2 px-3 py-1 text-t-label text-ink-muted"
              data-testid="city-phase"
              data-phase={night ? 'night' : 'day'}
            >
              {night ? t('city.night') : t('city.day')}
            </span>
          }
        >
          {!hallDone && (
            <div data-testid="city-load-host">
              <LoadMeter steps={loadStepsFor(t, boot, hallDone)} data-testid="city-load" />
            </div>
          )}

          {/* THE FIVE PLACES — a row of cards across the page, always there: a press swaps the plan and the side panel and moves nothing here
              (owner, 2026-10-31: "in buildings 6 building tappable should always be inside"). */}
          <nav aria-label={t('city.buildings')} data-testid="city-buildings">
            {/* FIVE TILES LEAVE NO HOLE (2026-11-14, the second look pass): on a phone the words do not fit five across ("Production" is
                71 px in a 53-px cell at 320), and three columns left an empty sixth cell. So the phone's rail is two over three on six
                tracks: the first two tiles take three tracks each, the rest two. From `sm` it is one row of five, as before. */}
            <div className="grid grid-cols-6 gap-3 sm:grid-cols-5 md:gap-4 xl:gap-6" data-testid="city-building-grid">
              {CITY_TILES.map((b, i) => (
                <button
                  key={b.id}
                  type="button"
                  onClick={() => onSelect(b.id)}
                  aria-pressed={selected === b.id}
                  data-testid={`city-building-${b.id}`}
                  className={`${i < 2 ? 'col-span-3' : 'col-span-2'} flex min-h-16 min-w-0 flex-col items-center justify-center gap-1.5 rounded-tile px-1 py-2 transition sm:col-span-1 ${
                    selected === b.id
                      ? 'bg-surface-2 text-ink ring-1 ring-inset ring-accent'
                      : 'bg-surface text-ink-muted hover:bg-surface-2 hover:text-ink'
                  }`}
                >
                  <Icon name={b.icon} size={20} />
                  <span className="max-w-full text-balance text-center text-t-label leading-tight">{t(b.label)}</span>
                </button>
              ))}
            </div>
          </nav>

          {selected === PRODUCTION_PLACE ? (
            <div data-testid="city-open-panel">
              <div data-testid="city-face-panel" data-building={PRODUCTION_PLACE}>
                <PortProduction key={port.id} port={port} docked={docked} />
              </div>
            </div>
          ) : (
            <PageSplit
              sideFirst
              data-testid="city-top"
              main={
                <Card title={allegiance ? <CityFlag allegiance={allegiance} /> : undefined} data-testid="city-plan">
                  {/* THE PLAN, the full town, never cropped (CityScene fits the whole square plate inside the box with `xMidYMid meet`); the box is
                      the same square for every place (the market's chart, on a phone, stands at its own height: it is a card that must not scroll inside itself), so a press moves the plan's mark and nothing else. The market's left region is its CHART
                      (owner, 2026-10-31: "when pressing a market, instead of city, i would like to have a graph shown"). */}
                  <div
                    className={`mx-auto w-full max-w-[clamp(20rem,calc(100dvh-22rem),44rem)] overflow-hidden ${selected === 'market' ? 'lg:aspect-square' : 'aspect-square'}`}
                    data-testid="city-info-image"
                  >
                    {selected === 'market' ? <MarketLeft port={port} /> : <CityScene sizeTier={port.size_tier} night={night} seed={port.code} />}
                  </div>
                </Card>
              }
              side={
                selected === 'hall' ? (
                  <CityHallPanel
                    port={port}
                    hall={hall}
                    refusal={hallRefusal}
                    employees={employees}
                    relation={{ word: regard ? regardBandWord(regard.band) : t(RELATION_WORDS[relation]), stance, nation: portNation, band: regard?.band ?? null }}
                  />
                ) : (
                  <div data-testid="city-open-panel">
                    <CityFacePanel building={selected} port={port} fleet={fleet} />
                  </div>
                )
              }
            />
          )}
        </Sheet>
      </main>
    </>
  )
}
