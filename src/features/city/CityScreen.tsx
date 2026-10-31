import { useEffect, useMemo, useState, type ReactNode } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { Counter, Figure, Icon, Nav, Note, Row, StatCell, TapAway, Tray, type IconName, type NavItem } from '../../components/ui'
import { ShellStateContext, useShellState } from '../../app/shellState'
import { NAV_CELLS, tabHref } from '../../app/navTabs'
import { alongsideAt, fleetPortCode, housePortCode } from '../../domain/fleet'
import { useCommandDraft } from '../../domain/order'
import { useTownHall } from '../../live/useTownHall'
import { PortFlag } from '../../live/PortFlag'
import { CityFlag } from '../../live/CityFlag'
import { portNationOf, useWorld } from '../../live/worldStore'
import type { PortDues, SnapshotPort } from '../../lib/rpc'
import { formatDucats, formatInt, gameSunInstantMs } from '../../lib/format'
import { daylightAt, subsolarPoint } from '../../chart'
import { serverNow } from '../../lib/serverClock'
import { translateMaybe, useLocale, useT, type TKey } from '../../lib/i18n'
import { CityFace, type CityBuilding } from './CityFace'
import { CityScene } from './CityScene'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE CITY PAGE — a city, full screen (owner's "Game screen development", 2026-10-30)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// THE BRIEF: a city image that changes with the hour and shows its people as dots; four figures
// (Gold · Population · Status · Relationship); a grid of six buildings, each opening a full-screen
// face; your earnings; and a bottom rail (HQ | Levels | map | stats | menu). NO PAGE SCROLL — the
// frame is one viewport, the grid wraps, and nothing goes sideways.
//
// ── WHAT IS REAL ON THIS SLICE, AND WHAT IS NOT ────────────────────────────────────────────────
// This is the SHELL. It is client-only: there is no migration and no new served field.
//   real       the city (the fleet's docked port, or `?port=`), its flag and country, day/night off
//              the served clock, the city's GOLD (`world.town_hall` purse — the treasury the server
//              already serves), your own gold (`world.ledger` purse), your EMPLOYEES (the crew
//              aboard your hulls, from `world.fleets`), STATUS (the influence points you hold in
//              this city under the country you sail for now — `world.town_hall.influence.you`.
//              `points`, the book every Share and Donation writes), RELATIONSHIP (the harbour's
//              served stance toward that nation — `world.town_hall.dues.stance`,
//              `public.power_stance`: home / ally / peace / rival / war), and every building face,
//              which is the existing one composed (CityFace.tsx).
//   estimate   Population only: `port.size_tier` is the one served size figure, so the number is a
//              stated curve off it with its caption. Nothing else here is a guess, and the three
//              figures ride the hall's ONE served block — no cell asks a second read.
//
// ── WHY IT SITS OUTSIDE AppShell ──────────────────────────────────────────────────────────────
// The page draws its OWN bottom rail and its OWN header, so the shell's tab bar would be a second
// navigation on the same glass. It is therefore a sibling of `/ui`, inside `RequireAuth` but not
// inside `AppShell` (src/app/App.tsx) — and for the same reason it provides the one thing the
// shell normally provides to a face: the clock (`ShellStateContext`). It opens the world itself,
// idempotently. `data-world` is on the root so the browser specs' one "is the world up" wait
// (tests/appReady.fixture.ts) works here too.

/** THE POPULATION IS AN ESTIMATE, NOT A SERVED COUNT (owner, 2026-10-31: "more tiny dot with huge
 *  number"). The only served size figure is `port.size_tier` (1-5), so the figure beneath the
 *  plan is a stated curve off it and the card's caption says so. The curve: tier 1 ≈ 8,000 ·
 *  2 ≈ 18,000 · 3 ≈ 45,000 · 4 ≈ 90,000 · 5 ≈ 160,000. */
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

export function CityScreen() {
  const t = useT()
  const locale = useLocale()
  const navigate = useNavigate()
  const [params] = useSearchParams()
  const phase = useWorld((s) => s.phase)

  // THE WORLD OPENS HERE, once, exactly as AppShell opens it for the tabs (open() is idempotent).
  useEffect(() => {
    void useWorld.getState().open()
  }, [])

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
        <CityRail locale={locale} onNavigate={navigate} />
      </>,
    )
  }
  if (phase !== 'ready')
    return gate(
      <>
        <div className="flex-1 p-gutter">
          <Note tone="neutral">{t('city.loading')}</Note>
        </div>
        <CityRail locale={locale} onNavigate={navigate} />
      </>,
    )
  if (!port || port.kind !== 'HARBOUR')
    return gate(
      <>
        <div className="flex-1 p-gutter">
          <Note tone="neutral">{t('city.noCity')}</Note>
        </div>
        <CityRail locale={locale} onNavigate={navigate} />
      </>,
    )

  return gate(<CityBody port={port} draftFleetId={draftFleetId} onNavigate={navigate} />)
}

/** Everything that reads served city data — mounted only once the world is up. */
function CityBody({
  port,
  draftFleetId,
  onNavigate,
}: {
  port: SnapshotPort
  draftFleetId: string | null
  onNavigate: ReturnType<typeof useNavigate>
}) {
  const fleets = useWorld((s) => s.fleets)
  const ducats = useWorld((s) => s.ducats)
  const allegiance = useWorld((s) => s.allegiance)

  // The fleet acting for this city: one of yours lying here, else nobody (a read-only city).
  const { docked } = alongsideAt(fleets, port.code, draftFleetId)
  const fleet = docked[0] ?? null

  const hall = useTownHall(port.id)
  const cityGold = hall.view?.view?.purse.ducats ?? null
  // THE TWO SERVED FACTS BENEATH THE PURSE (owner, 2026-10-31: "status and relationship too"):
  // the influence points you hold here under the country you sail for now (`influence.you.points`
  // — the book every Share and Donation writes), and the harbour's served stance toward that
  // nation (`dues.stance`, `public.power_stance`). Both ride the hall's one read; neither is
  // computed here.
  const statusPoints = hall.view?.view?.influence?.you?.points ?? null
  const stance = hall.view?.view?.dues?.stance ?? null

  const employees = useMemo(
    () => fleets.reduce((n, f) => n + f.ships.reduce((m, s) => m + s.crew, 0), 0),
    [fleets],
  )

  const [open, setOpen] = useState<CityBuilding | null>(null)

  return (
    <>
      <CityFrame
        port={port}
        cityGold={cityGold}
        statusPoints={statusPoints}
        stance={stance}
        ducats={ducats}
        employees={employees}
        allegiance={portNationOf(allegiance, port.code)}
        onOpen={setOpen}
        onNavigate={onNavigate}
      />
      {open !== null && <CityFace building={open} port={port} fleet={fleet} onClose={() => setOpen(null)} />}
    </>
  )
}

/** The frame itself: header, scene, the four figures, the six buildings, earnings, the rail. */
function CityFrame({
  port,
  cityGold,
  statusPoints,
  stance,
  ducats,
  employees,
  allegiance,
  onOpen,
  onNavigate,
}: {
  port: SnapshotPort
  cityGold: number | null
  statusPoints: number | null
  stance: PortDues['stance'] | null
  ducats: number | null
  employees: number
  allegiance: ReturnType<typeof portNationOf>
  onOpen: (b: CityBuilding) => void
  onNavigate: ReturnType<typeof useNavigate>
}) {
  const t = useT()
  const locale = useLocale()
  // THE HOUR is the served clock's, through the shell context (AppShell's one clock in every other
  // route; here this page provides it — CityScreen).
  const { nowMs } = useShellState()
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
  const relation: Relation =
    stance ?? (houseNation === null ? 'none' : portNation === null ? 'free' : houseNation === portNation ? 'home' : 'different')

  const buildings: readonly { id: CityBuilding; icon: IconName; label: TKey }[] = [
    { id: 'hall', icon: 'coin', label: 'city.cityHall' },
    { id: 'market', icon: 'chart', label: 'city.market' },
    { id: 'storage', icon: 'cask', label: 'city.storage' },
    { id: 'forge', icon: 'mallet', label: 'city.forge' },
    { id: 'port', icon: 'ship', label: 'city.port' },
    { id: 'inn', icon: 'crew', label: 'city.inn' },
  ]

  return (
    <>
      <header className="flex shrink-0 items-center gap-3 px-gutter py-2" data-testid="city-header">
        <PortFlag code={port.code} size="title" />
        <div className="min-w-0 flex-1">
          <h1 className="truncate text-t-title" data-testid="city-name">{port.name}</h1>
          <div className="truncate text-t-caption text-ink-faint">
            {allegiance ? <CityFlag allegiance={allegiance} /> : null}
          </div>
        </div>
        <span
          className="shrink-0 rounded-chip bg-surface-2 px-2.5 py-1 text-t-caption text-ink-muted"
          data-testid="city-phase"
          data-phase={night ? 'night' : 'day'}
        >
          {night ? t('city.night') : t('city.day')}
        </span>
      </header>

      <main className="flex min-h-0 flex-1 flex-col gap-3 px-gutter pb-3">
        {/* THE PLAN AND ITS BUILDINGS, side by side (owner, 2026-10-30: "have the city birds eye view
            as a square on the top left, and then buildings smaller that fits the right space";
            2026-10-31: "make the whole page better"): the plan stands at the top left — the full
            town, never cropped, whatever shape this panel takes: CityScene fits the whole square
            plate inside it (`xMidYMid meet`, on the plate's own ground colour), because on a wide
            or short window the flex row can flatten the panel and the old `slice` cropped the
            city (owner, 2026-10-31: "i told you that i need to see all the city, a closed one") —
            and the four figures sit directly beneath it; the six building tiles stand small beside
            it, each with its name at the top left and its served figure beneath. The earnings block
            stays pinned above the rail. */}
        <section className="flex min-h-0 flex-1 gap-2" data-testid="city-top">
          <div className="flex min-w-0 flex-[0_0_56%] flex-col gap-3">
            <div className="aspect-square min-h-[96px] w-full min-w-0 overflow-hidden" data-testid="city-info-image">
              <CityScene sizeTier={port.size_tier} night={night} seed={port.code} onOpen={onOpen} />
            </div>

            {/* SUMMARY — the population estimate is the headline (the huge number off the served
                size tier, said as an estimate); beneath it the city's purse, YOUR STATUS (the
                influence points you hold here — served, the book every Share and Donation writes)
                and the town's RELATIONSHIP to your nation (the harbour's served stance: Home port /
                Ally / Peace / Rival / War; the two served nations compared only while the dues
                block is not served). Its floor is its own content (`min-h-fit`): on a wide or short
                window the same flex squeeze that flattened the plan panel also crushed this card
                to a 16-px sliver, so the huge number vanished — the card keeps its height and the
                PLAN shrinks instead (the scene still draws the whole city, CityScene). */}
            <section className="flex min-h-fit flex-1 flex-col overflow-hidden rounded-tile bg-surface px-gutter py-2" data-testid="city-summary">
              <div className="shrink-0" data-testid="city-population">
                <span className="block text-t-caption text-ink-faint">{t('city.population')}</span>
                <Figure value={`≈ ${formatInt(population)}`} size="figure" tone="ink" />
                <span className="block text-t-caption text-ink-faint">{t('city.populationNote')}</span>
              </div>
              <div className="mt-2 flex min-h-0 flex-1 flex-col divide-y divide-edge">
                <div className="flex min-h-0 flex-1 items-center justify-between gap-2" data-testid="city-gold">
                  <span className="text-t-caption text-ink-faint">{t('city.gold')}</span>
                  {cityGold === null ? (
                    <Figure value="—" size="body" tone="faint" />
                  ) : (
                    <Counter value={cityGold} format={formatDucats} size="body" />
                  )}
                </div>
                <div className="flex min-h-0 flex-1 items-center justify-between gap-2" data-testid="city-status">
                  <span className="text-t-caption text-ink-faint">{t('city.status')}</span>
                  {statusPoints === null ? (
                    <Figure value="—" size="body" tone="faint" />
                  ) : (
                    <Figure value={formatInt(statusPoints)} size="body" tone="ink" />
                  )}
                </div>
                <div
                  className="flex min-h-0 flex-1 items-center justify-between gap-2"
                  data-testid="city-relationship"
                  data-stance={stance ?? 'none'}
                  data-nation={portNation ?? 'none'}
                >
                  <span className="text-t-caption text-ink-faint">{t('city.relationship')}</span>
                  <Figure value={t(RELATION_WORDS[relation])} size="body" tone="ink" />
                </div>
              </div>
            </section>
          </div>

          <div className="flex min-h-0 min-w-0 flex-1 flex-col">
            <h2 className="shrink-0 pb-1 text-t-caption text-ink-faint">{t('city.buildings')}</h2>
            <div className="grid auto-rows-[68px] grid-cols-2 gap-1.5" data-testid="city-building-grid">
              {buildings.map((b) => (
                <button
                  key={b.id}
                  type="button"
                  onClick={() => onOpen(b.id)}
                  data-testid={`city-building-${b.id}`}
                  className="relative flex min-h-11 min-w-0 flex-col items-start overflow-hidden rounded-tile bg-surface px-1.5 py-1 text-left text-ink-muted transition hover:bg-surface-2 hover:text-ink"
                >
                  <span className="max-w-full text-t-caption">{t(b.label)}</span>
                  {b.id === 'hall' && (
                    <span className="mt-0.5 block min-w-0 max-w-full overflow-hidden">
                      <Figure
                        value={cityGold === null ? '—' : formatDucats(cityGold)}
                        size="body"
                        tone={cityGold === null ? 'faint' : 'ink'}
                      />
                    </span>
                  )}
                  <Icon name={b.icon} size={14} className="absolute bottom-1 right-1 text-ink-faint" />
                </button>
              ))}
            </div>
          </div>
        </section>

        {/* YOUR EARNINGS — your purse and the crew you employ, above the rail. */}
        <section className="flex shrink-0 items-center justify-between gap-3 rounded-tile bg-surface px-gutter py-2" data-testid="city-earnings">
          <span className="text-t-caption text-ink-faint">{t('city.earnings')}</span>
          <div className="flex items-start gap-6">
            <StatCell
              label={t('city.gold')}
              value={ducats ?? undefined}
              format={formatDucats}
              text={ducats === null ? '—' : undefined}
              size="body"
              data-testid="city-your-gold"
            />
            <StatCell label={t('city.employees')} value={employees} format={formatInt} size="body" data-testid="city-employees" />
          </div>
        </section>
      </main>

      <CityRail locale={locale} onNavigate={onNavigate} />
    </>
  )
}

/** THE BOTTOM RAIL — HQ · map · stats · menu. A group reveals its members in a tray and moves no
 *  cell (the rail's one law, components/ui/Nav.tsx). NO Command cell (owner, 2026-10-31: *"i told
 *  you to remove the command tab"*): the desk is reached from this city's MARKET building, whose
 *  face composes the trade face (CityFace). */
function CityRail({ locale, onNavigate }: { locale: ReturnType<typeof useLocale>; onNavigate: ReturnType<typeof useNavigate> }) {
  const t = useT()
  const [panel, setPanel] = useState<'menu' | null>(null)

  // The cabin's members come from the ONE tab table (app/navTabs.ts) — never a second list.
  const cabin = NAV_CELLS.find((c) => c.kind === 'group')
  const members = cabin?.kind === 'group' ? cabin.members : []
  const word = (label: string) => translateMaybe(locale, 'shell', `tab_${label}`) ?? label

  useEffect(() => {
    if (panel === null) return
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setPanel(null)
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [panel])

  const items: NavItem[] = [
    { id: 'hq', label: t('city.hq'), icon: 'wreath', href: tabHref('/city') },
    { id: '/map', label: t('city.map'), icon: 'chart', href: tabHref('/map') },
    { id: '/stats', label: t('city.stats'), icon: 'stats', href: tabHref('/stats') },
    { id: 'menu', label: t('city.menu'), icon: 'chevron' },
  ]

  return (
    <div className="relative shrink-0" data-testid="city-rail">
      {panel !== null && (
        <>
          <TapAway label={t('common.close')} onClick={() => setPanel(null)} />
          <div className="absolute inset-x-0 bottom-full z-20">
            <Tray mode="inline" detent="half" onDetentChange={(next) => (next === 'closed' ? setPanel(null) : undefined)} title={t('city.menu')}>
              {members.length === 0 ? null : (
                members.map((m, i) => (
                  <Row
                    key={m.to}
                    mark={<Icon name={m.icon} size={20} />}
                    label={word(m.label)}
                    chevron
                    hairline={i < members.length - 1}
                    onClick={() => {
                      setPanel(null)
                      onNavigate(m.to)
                    }}
                  />
                ))
              )}
            </Tray>
          </div>
        </>
      )}

      <Nav
        data-testid="city-nav"
        items={items}
        current="hq"
        openGroup={panel ?? undefined}
        onGroup={(id) => setPanel((p) => (p === id ? null : 'menu'))}
        onNavigate={(item) => {
          setPanel(null)
          if (item.id === '/map' || item.id === '/stats') onNavigate(item.id)
        }}
      />
    </div>
  )
}
