import { useEffect, useMemo, useState, type ReactNode } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { Icon, Nav, Note, Row, StatCell, Tray, type IconName, type NavItem } from '../../components/ui'
import { ShellStateContext, useShellState } from '../../app/shellState'
import { NAV_CELLS, tabHref } from '../../app/navTabs'
import { alongsideAt, fleetPortCode, housePortCode } from '../../domain/fleet'
import { useCommandDraft } from '../../domain/order'
import { useTownHall } from '../../live/useTownHall'
import { PortFlag } from '../../live/PortFlag'
import { CityFlag } from '../../live/CityFlag'
import { portNationOf, useWorld } from '../../live/worldStore'
import type { SnapshotPort } from '../../lib/rpc'
import { formatDucats, formatInt, gameSunInstantMs } from '../../lib/format'
import { daylightAt, subsolarPoint } from '../../chart/sun'
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
//              already serves), your own gold (`world.ledger` purse) and your EMPLOYEES (the crew
//              aboard your hulls, from `world.fleets`), and every building face, which is the
//              existing one composed (CityFace.tsx).
//   placeholder Population, Status and Relationship are NOT on the wire yet (the data migration is
//              a later slice). They print "—", carry `data-placeholder`, and one caption line says
//              so. Nothing here invents a number.
//
// ── WHY IT SITS OUTSIDE AppShell ──────────────────────────────────────────────────────────────
// The page draws its OWN bottom rail and its OWN header, so the shell's tab bar would be a second
// navigation on the same glass. It is therefore a sibling of `/ui`, inside `RequireAuth` but not
// inside `AppShell` (src/app/App.tsx) — and for the same reason it provides the one thing the
// shell normally provides to a face: the clock (`ShellStateContext`). It opens the world itself,
// idempotently. `data-world` is on the root so the browser specs' one "is the world up" wait
// (tests/appReady.fixture.ts) works here too.

export function CityScreen() {
  const t = useT()
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

  if (phase === 'failed') {
    const fatal = useWorld.getState().fatal
    return gate(
      <div className="p-gutter">
        <Note tone="danger" code={fatal?.code} figures={fatal?.figures}>
          {fatal?.sentence ?? t('city.failed')}
        </Note>
      </div>,
    )
  }
  if (phase !== 'ready') return gate(<Note tone="neutral" className="p-gutter">{t('city.loading')}</Note>)
  if (!port || port.kind !== 'HARBOUR') return gate(<Note tone="neutral" className="p-gutter">{t('city.noCity')}</Note>)

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
  ducats,
  employees,
  allegiance,
  onOpen,
  onNavigate,
}: {
  port: SnapshotPort
  cityGold: number | null
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
        {/* CITY INFO — the drawing, with its population dots. */}
        <div className="min-h-[110px] flex-[1.15] overflow-hidden" data-testid="city-info-image">
          <CityScene sizeTier={port.size_tier} night={night} />
        </div>

        {/* SUMMARY — four figures. Gold is the city's purse (served); the other three are the
            data slice's, and say so. */}
        <section className="grid shrink-0 grid-cols-2 gap-x-4 gap-y-2 sm:grid-cols-4" data-testid="city-summary">
          <StatCell
            label={t('city.gold')}
            value={cityGold ?? undefined}
            format={formatDucats}
            text={cityGold === null ? '—' : undefined}
            size="body"
            data-testid="city-gold"
          />
          <div data-placeholder="true" data-testid="city-population">
            <StatCell label={t('city.population')} text="—" size="body" />
          </div>
          <div data-placeholder="true" data-testid="city-status">
            <StatCell label={t('city.status')} text="—" size="body" />
          </div>
          <div data-placeholder="true" data-testid="city-relationship">
            <StatCell label={t('city.relationship')} text="—" size="body" />
          </div>
          <p className="col-span-2 text-t-caption text-ink-faint sm:col-span-4" data-testid="city-soon">
            {t('city.soonLine')}
          </p>
        </section>

        {/* BUILDINGS — six, in a field that wraps (never sideways). */}
        <section className="flex min-h-0 flex-[1.5] flex-col" data-testid="city-building-grid">
          <h2 className="shrink-0 pb-1 text-t-caption text-ink-faint">{t('city.buildings')}</h2>
          <div className="grid min-h-0 flex-1 grid-cols-3 grid-rows-2 gap-2 lg:grid-cols-6 lg:grid-rows-1">
            {buildings.map((b) => (
              <button
                key={b.id}
                type="button"
                onClick={() => onOpen(b.id)}
                data-testid={`city-building-${b.id}`}
                className="flex min-h-0 flex-col items-center justify-center gap-1 rounded-tile bg-surface px-1 py-1 text-ink-muted transition hover:bg-surface-2 hover:text-ink"
              >
                <Icon name={b.icon} size={22} />
                <span className="max-w-full truncate text-t-caption">{t(b.label)}</span>
              </button>
            ))}
          </div>
        </section>

        {/* YOUR EARNINGS — your purse and the crew you employ. */}
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

/** THE BOTTOM RAIL — HQ · Levels · map · stats · menu. A group reveals its members in a tray and
 *  moves no cell (the rail's one law, components/ui/Nav.tsx). */
function CityRail({ locale, onNavigate }: { locale: ReturnType<typeof useLocale>; onNavigate: ReturnType<typeof useNavigate> }) {
  const t = useT()
  const [panel, setPanel] = useState<'menu' | 'levels' | null>(null)

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
    { id: 'hq', label: t('city.hq'), icon: 'compass', href: tabHref('/city') },
    // Levels is a placeholder, but it is a DESTINATION-shaped cell, not a group: it carries an href
    // (this page) so the rail does not turn its glyph as if it revealed a tray, and its press
    // opens the "next slice" note (below).
    { id: 'levels', label: t('city.levels'), icon: 'wreath', href: tabHref('/city') },
    { id: '/map', label: t('city.map'), icon: 'chart', href: tabHref('/map') },
    { id: '/stats', label: t('city.stats'), icon: 'stats', href: tabHref('/stats') },
    { id: 'menu', label: t('city.menu'), icon: 'chevron' },
  ]

  return (
    <div className="relative shrink-0" data-testid="city-rail">
      {panel !== null && (
        <>
          <button
            type="button"
            aria-label={t('common.close')}
            onClick={() => setPanel(null)}
            tabIndex={-1}
            className="absolute inset-x-0 bottom-full z-10 h-screen cursor-default"
          />
          <div className="absolute inset-x-0 bottom-full z-20">
            <Tray mode="inline" detent="half" onDetentChange={(next) => (next === 'closed' ? setPanel(null) : undefined)} title={panel === 'menu' ? t('city.menu') : t('city.levels')}>
              {panel === 'levels' ? (
                <Note tone="neutral" data-testid="city-levels-soon">{t('city.levelsSoon')}</Note>
              ) : members.length === 0 ? null : (
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
        onGroup={(id) => setPanel((p) => (p === id ? null : (id as 'menu' | 'levels')))}
        onNavigate={(item) => {
          if (item.id === 'levels') {
            setPanel('levels')
            return
          }
          setPanel(null)
          if (item.id === '/map' || item.id === '/stats') onNavigate(item.id)
        }}
      />
    </div>
  )
}
