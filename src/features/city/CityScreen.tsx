import { useEffect, useMemo, useState, type ReactNode } from 'react'
import { useSearchParams } from 'react-router-dom'
import { Figure, Icon, LoadMeter, Note, Row, type IconName, type LoadStep } from '../../components/ui'
import { ShellStateContext, useShellState } from '../../app/shellState'
import { NavBar } from '../../app/NavBar'
import { alongsideAt, fleetPortCode, housePortCode } from '../../domain/fleet'
import { useCommandDraft } from '../../domain/order'
import { MarketLeft } from '../../live/MarketLeft'
import { useTownHall } from '../../live/useTownHall'
import { PortFlag } from '../../live/PortFlag'
import { CityFlag } from '../../live/CityFlag'
import { portNationOf, useWorld } from '../../live/worldStore'
import { useWorldBeat } from '../../live/worldStore'
import type { FleetView, Refusal, SnapshotPort, TownHallView } from '../../lib/rpc'
import { formatDucats, gameSunInstantMs } from '../../lib/format'
import { daylightAt, subsolarPoint } from '../../chart'
import { serverNow } from '../../lib/serverClock'
import { useT, type TKey } from '../../lib/i18n'
import { CityFacePanel, type CityBuilding } from './CityFace'
import { CityHallPanel } from './CityHallPanel'
import { CityScene } from './CityScene'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE CITY PAGE — a city, full screen (owner's "Game screen development", 2026-10-30)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
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
// keeps ONE line of its own — YOUR purse ("Your earnings"), which the hall does not show — so the
// frame is header + six tiles + earnings + rail, identical across every press, and the room the
// card gave back is what lets the hall show its book and its fold at 390×568 without scrolling.
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
//   estimate   Population only: `port.size_tier` is the one served size figure, so the number is a
//              stated curve off it with its "≈" glyph. Nothing else here is a guess, and the five
//              figures ride the hall's ONE served block — no cell asks a second read.
//
// ── WHY IT SITS OUTSIDE AppShell ──────────────────────────────────────────────────────────────
// The page draws its OWN header and fills its own viewport, and it renders the shell's own NavBar
// as its rail (ONE tab table, app/NavBar.tsx — never a second nav). It is a sibling of `/ui`,
// inside `RequireAuth` but not inside `AppShell` (src/app/App.tsx) — and for the same reason it
// provides the one thing the shell normally provides to a face: the clock (`ShellStateContext`).
// It opens the world itself, idempotently. `data-world` is on the root so the browser specs' one
// "is the world up" wait (tests/appReady.fixture.ts) works here too.

/** THE POPULATION IS AN ESTIMATE, NOT A SERVED COUNT (owner, 2026-10-31: "more tiny dot with huge
 *  number"). The only served size figure is `port.size_tier` (1-5), so the figure the hall prints is
 *  a stated curve off it and carries "≈". The curve: tier 1 ≈ 8,000 · 2 ≈ 18,000 · 3 ≈ 45,000 ·
 *  4 ≈ 90,000 · 5 ≈ 160,000. */
const POPULATION_BY_TIER = [8000, 18000, 45000, 90000, 160000] as const
function populationEstimate(sizeTier: number): number {
  return POPULATION_BY_TIER[Math.max(0, Math.min(4, (sizeTier || 1) - 1))]
}

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
 *  three boot completions ride the store's `boot` (snapshot · sea · first beat read); the fourth
 *  is the city's own served read, the hall. Four equal steps until a caller knows a size. */
function loadStepsFor(t: ReturnType<typeof useT>, boot: number, hallDone: boolean): readonly LoadStep[] {
  return [
    { id: 'world', label: t('city.loadWorld'), done: boot >= 1 },
    { id: 'sea', label: t('city.loadSea'), done: boot >= 2 },
    { id: 'fleets', label: t('city.loadFleets'), done: boot >= 3 },
    { id: 'hall', label: t('city.loadHall'), done: hallDone },
  ]
}

/** THE SIX PLACES — one row of the frame, the Town Hall first (the page's main panel), then the
 *  five buildings. A press changes the plan's mark and the right panel; it moves no cell (owner,
 *  2026-10-31: the frame "stays the same"). */
type CitySelection = 'hall' | CityBuilding
const CITY_TILES: readonly { id: CitySelection; icon: IconName; label: TKey }[] = [
  { id: 'hall', icon: 'wreath', label: 'city.cityHall' },
  { id: 'market', icon: 'chart', label: 'city.market' },
  { id: 'storage', icon: 'cask', label: 'city.storage' },
  { id: 'forge', icon: 'mallet', label: 'city.forge' },
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
      <div
        className="bv-sea flex h-[100dvh] flex-col overflow-hidden text-ink"
        data-world={phase}
        data-testid="city-screen"
      >
        {body}
      </div>
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
        <div data-testid="city-rail" className="shrink-0"><NavBar /></div>
      </>,
    )
  }
  if (phase !== 'ready')
    return gate(
      <>
        <div className="flex-1 p-gutter">
          <LoadMeter steps={loadStepsFor(t, boot, false)} data-testid="city-load" />
        </div>
        <div data-testid="city-rail" className="shrink-0"><NavBar /></div>
      </>,
    )
  if (!port || port.kind !== 'HARBOUR')
    return gate(
      <>
        <div className="flex-1 p-gutter">
          <Note tone="neutral">{t('city.noCity')}</Note>
        </div>
        <div data-testid="city-rail" className="shrink-0"><NavBar /></div>
      </>,
    )

  return gate(<CityBody port={port} draftFleetId={draftFleetId} />)
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
  /** YOUR OWN PURSE — the frame's one line that repeats nothing from the hall (whose Gold is the
   *  CITY's purse). It is what the old earnings line carried, kept alone. */
  const ducats = useWorld((s) => s.ducats)

  // The fleet acting for this city: one of yours lying here, else nobody (a read-only city).
  const { docked } = alongsideAt(fleets, port.code, draftFleetId)
  const fleet = docked[0] ?? null

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
  const [selected, setSelected] = useState<CitySelection>('hall')

  return (
    <CityFrame
      port={port}
      fleet={fleet}
      hall={hall}
      hallRefusal={hallRefusal}
      employees={employees}
      ducats={ducats}
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
  hall,
  hallRefusal,
  employees,
  ducats,
  allegiance,
  selected,
  onSelect,
}: {
  port: SnapshotPort
  /** A fleet of yours lying HERE (the city's acting fleet), or null — a read-only city. */
  fleet: FleetView | null
  hall: TownHallView | null
  hallRefusal: Refusal | null
  employees: number
  /** YOUR purse — the frame's one earnings line; nothing else of the old figures card remains. */
  ducats: number | null
  allegiance: ReturnType<typeof portNationOf>
  selected: CitySelection
  onSelect: (s: CitySelection) => void
}) {
  const t = useT()
  const { nowMs } = useShellState()
  // THE LOADING METER, WHILE THE SCREEN IS STILL LOADING: the world steps ride `boot`, the hall
  // step is this screen's own read. It is NOT part of the frame (it is gone at ready, when every
  // frame proof runs), and it updates on step completion only.
  const boot = useWorld((s) => s.boot)
  const hallDone = hall !== null || hallRefusal !== null
  // DAY/NIGHT is the world's ONE sun (chart/sun), at the game clock's hour, over THIS city — never a
  // local-time hour: every player sees the same night, and it matches the Map's own day sheet.
  const night = daylightAt({ lat: port.lat, lon: port.lon }, subsolarPoint(gameSunInstantMs(nowMs))) < 0.5
  const population = populationEstimate(port.size_tier)

  // THE RELATIONSHIP IS THE SERVER'S STANCE while the hall answers it (`public.power_stance`,
  // between the nation you sail for and the city's holder): home / ally / peace / rival / war.
  // While the dues block is not served it falls back to the two SERVED nations themselves — the
  // same `world.allegiance` holder the header's flag reads and your own house's nation: same
  // nation is a fact, different nations are a fact, never a guessed ally or war.
  const houseNation = useWorld((s) => s.player?.nation ?? null)
  const portNation = allegiance?.nation ?? null
  const stance = hall?.dues?.stance ?? null
  const relation: Relation =
    stance ?? (houseNation === null ? 'none' : portNation === null ? 'free' : houseNation === portNation ? 'home' : 'different')

  return (
    <>
      <header className="flex shrink-0 items-center gap-2 px-gutter py-1.5" data-testid="city-header">
        <PortFlag code={port.code} size="title" />
        <div className="min-w-0 flex-1">
          <h1 className="truncate text-t-title" data-testid="city-name">{port.name}</h1>
          <div className="truncate text-t-caption text-ink-faint">
            {allegiance ? <CityFlag allegiance={allegiance} /> : null}
          </div>
        </div>
        <span
          className="shrink-0 rounded-chip bg-surface-2 px-2 py-0.5 text-t-caption text-ink-muted"
          data-testid="city-phase"
          data-phase={night ? 'night' : 'day'}
        >
          {night ? t('city.night') : t('city.day')}
        </span>
      </header>

      {!hallDone && (
        <div className="shrink-0 px-gutter" data-testid="city-load-host">
          <LoadMeter steps={loadStepsFor(t, boot, hallDone)} data-testid="city-load" />
        </div>
      )}

      {/* THE SIX BUILDINGS — the page's OWN ROW, always visible, part of the frame: a press swaps
          the plan's mark and the right panel and moves nothing here (owner, 2026-10-31: "in
          buildings 6 building tappable should always be inside"). */}
      <nav aria-label={t('city.buildings')} className="shrink-0 px-gutter pt-1" data-testid="city-buildings">
        <div className="grid grid-cols-3 gap-1 min-[361px]:grid-cols-6" data-testid="city-building-grid">
          {CITY_TILES.map((b) => (
            <button
              key={b.id}
              type="button"
              onClick={() => onSelect(b.id)}
              aria-pressed={selected === b.id}
              data-testid={`city-building-${b.id}`}
              className={`flex min-h-11 min-w-0 flex-col items-center justify-center gap-0.5 rounded-tile px-0.5 transition ${
                selected === b.id
                  ? 'bg-surface-2 text-ink ring-1 ring-inset ring-accent'
                  : 'bg-surface text-ink-muted hover:bg-surface-2 hover:text-ink'
              }`}
            >
              <Icon name={b.icon} size={14} />
              <span className="max-w-full text-balance text-center text-t-caption leading-tight">{t(b.label)}</span>
            </button>
          ))}
        </div>
      </nav>

      <main className="flex min-h-0 flex-1 flex-col px-gutter pb-1.5 pt-1.5">
        {/* THE HQ SPLIT (owner, 2026-10-31): the plan on the LEFT — the full town, never cropped
            (CityScene fits the whole square plate inside it with `xMidYMid meet` on the plate's own
            ground colour) — and the open place's panel on the RIGHT. The plan stays on the glass
            for every place: a press moves its mark and swaps the panel only. The five figures are
            NOT here; they are the hall panel's block (owner: "the hall panel is their single
            home"). */}
        <section className="flex min-h-0 flex-1 gap-2" data-testid="city-top">
          <div className="flex min-h-0 min-w-0 flex-[0_0_50%] flex-col">
            <div className="min-h-0 flex-1 overflow-hidden" data-testid="city-info-image">
              {/* THE MARKET'S LEFT REGION IS THE CHART (owner, 2026-10-31: "when pressing a market,
                  instead of city, i would like to have a graph shown") — every other place keeps the
                  city picture. The box is the frame's, unchanged. */}
              {selected === 'market' ? <MarketLeft port={port} /> : <CityScene sizeTier={port.size_tier} night={night} seed={port.code} />}
            </div>
          </div>
          <div className="flex min-h-0 min-w-0 flex-1 flex-col">
            {selected === 'hall' ? (
              <CityHallPanel
                port={port}
                hall={hall}
                refusal={hallRefusal}
                population={population}
                employees={employees}
                relation={{ word: t(RELATION_WORDS[relation]), stance, nation: portNation }}
              />
            ) : (
              <div className="flex min-h-0 min-w-0 flex-1 flex-col" data-testid="city-open-panel">
                <CityFacePanel building={selected} port={port} fleet={fleet} />
              </div>
            )}
          </div>
        </section>

        {/* THE FRAME'S ONE EARNINGS LINE — YOUR purse, and NOTHING repeated from the hall (the
            owner's five figures live only in the hall panel). It stays a frame row so the frame is
            the same shape at every press (and the merged audit's HQ-geometry proof still reads a
            `city-summary` between the split and the rail). */}
        <div data-testid="city-summary" className="shrink-0 pt-1">
          {/* THE EARNINGS LINE IS A ROW OF THE ONE ROW (2026-11-01 re-point): the compact size keeps
              the frame line on a 20-px data line while the shared columns place the purse beside
              its word. */}
          <Row
            className="px-1"
            label={t('city.earnings')}
            value={<Figure value={ducats === null ? '—' : formatDucats(ducats)} size="body" tone={ducats === null ? 'faint' : 'ink'} />}
            hairline={false}
            size="compact"
          />
        </div>
      </main>

      <div data-testid="city-rail" className="shrink-0"><NavBar /></div>
    </>
  )
}
