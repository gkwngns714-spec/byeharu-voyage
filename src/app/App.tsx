import { useEffect } from 'react'
import { BrowserRouter, Routes, Route, Navigate, useLocation } from 'react-router-dom'
import { useAuthStore } from '../store/authStore'
import { RequireAuth } from './RequireAuth'
import { AppShell } from './AppShell'
import { NewVersionToast } from './NewVersionToast'
import { HOME_TAB, LANDING } from './navTabs'
import { hqHref } from './hqPlace'
import { PORT_PLACE } from '../live/cityFaces'
import { pageVarsClass } from '../components/ui'
import { AuthPage } from '../features/auth/AuthPage'
import { GalleryScreen } from '../features/gallery/GalleryScreen'
import { PageGalleryScreen } from '../features/gallery/PageGalleryScreen'
import { BattleGalleryScreen } from '../features/gallery/BattleGalleryScreen'
import { GatesGalleryScreen } from '../features/found/GatesGalleryScreen'
import { FleetsScreen } from '../features/fleets/FleetsScreen'
import { MapScreen } from '../features/map/MapScreen'
import { StatsScreen } from '../features/stats/StatsScreen'
import { LedgerScreen } from '../features/ledger/LedgerScreen'
import { RankScreen } from '../features/rank/RankScreen'
import { RoutesScreen } from '../features/routes/RoutesScreen'
import { CompendiumScreen } from '../features/compendium/CompendiumScreen'
import { CityScreen } from '../features/city/CityScreen'
import { ProfileScreen } from '../features/profile/ProfileScreen'
import { YouScreen } from '../features/you/YouScreen'
import { LevelsScreen } from '../features/you/LevelsScreen'
import { LogbookScreen } from '../features/you/LogbookScreen'
import { LandScreen } from '../features/land/LandScreen'

// THE ROUTE TABLE. One destination per tab (src/app/navTabs.ts is the tab table; these are the
// routes it names) under the ONE persistent shell. Everything authenticated sits inside
// RequireAuth + AppShell. Two routes sit outside it: /auth, and /ui — the design-system gallery
// step 2 of docs/UI_DIRECTION.md §7 added, which reads nothing from the world.

export function App() {
  const init = useAuthStore((s) => s.init)

  useEffect(() => {
    // Subscribe to Supabase auth once for the app's lifetime.
    const unsubscribe = init()
    return unsubscribe
  }, [init])

  return (
    <BrowserRouter basename={import.meta.env.BASE_URL}>
      {/* A NEWER BUILD IS LIVE — one fixed corner toast, over every route: the sign-in page and the
          gallery as much as the shell, because a stale tab is stale wherever it is parked. It is
          outside RequireAuth and AppShell on purpose, and it reads nothing from the world
          (src/app/NewVersionToast.tsx). */}
      <NewVersionToast />
      {/* THE PAGE'S TWO VARIABLES, SET ONCE FOR EVERY ROUTE (screenLayout.ts "THE PAGE"): the split and the docked tray read them, so a tray
          stands over the side column on any screen — page, desk, map, gallery. `contents` adds no box. */}
      <div className={`contents ${pageVarsClass()}`}>
      <Routes>
        <Route path="/auth" element={<AuthPage />} />
        {/* THE DESIGN-SYSTEM GALLERY (docs/UI_DIRECTION.md §7 step 2). Outside RequireAuth and
            outside AppShell on purpose: it reads nothing from the world, so it renders instantly
            and tests/primitives.geometry.spec.ts can measure the twelve primitives without paying
            the cold chain — and without skipping on a cloud build. It is not in the tab table and
            nothing links to it. See features/gallery/GalleryScreen.tsx. */}
        <Route path="/ui" element={<GalleryScreen />} />
        {/* THE PAGE PATTERN (2026-11-02, owner row 267): the gallery's second page — a stat strip, MAIN | SIDE, cards, a card list, a tray over the side. */}
        <Route path="/ui/page" element={<PageGalleryScreen />} />
        {/* THE BATTLE SCREEN, FED A FIXTURE (0435): read by tests/battle.screen.spec.ts. Reads nothing from the world. */}
        <Route path="/ui/battle" element={<BattleGalleryScreen />} />
        {/* THE THREE DOORS (2026-11-05): the book a new captain signs, the world opening, the world refusing — read by tests/gates.design.spec.ts. */}
        <Route
          path="/ui/gates/:state"
          element={
            <RequireAuth>
              <GatesGalleryScreen />
            </RequireAuth>
          }
        />
        {/* THE CITY PAGE (2026-10-30, owner's "Game screen development"). A FULL-SCREEN city with
            its own header and its own bottom rail, so it is INSIDE RequireAuth but OUTSIDE AppShell
            — the shell's tab bar would be a second navigation on the same glass. It opens the world
            itself (idempotent) and provides the shell clock its building faces read. It is HQ, the home screen. */}
        <Route
          path="/city"
          element={
            <RequireAuth>
              <CityScreen />
            </RequireAuth>
          }
        />
        <Route
          element={
            <RequireAuth>
              <AppShell />
            </RequireAuth>
          }
        >
          {/* THE LANDING, AND THE OLD ROUTES (H3 `desk-into-hq`, 2026-11-24). The Trade desk (`/command`) and the Office (`/office`)
              are gone: their faces are HQ's plates and sheets. An old link opens HQ, on the sheet that face became where one is
              named (`OldRoute`). They stand INSIDE the shell so a captain with no house meets the register first (navTabs LANDING). */}
          <Route path={LANDING} element={<Navigate to={HOME_TAB} replace />} />
          <Route path="/command" element={<Navigate to={HOME_TAB} replace />} />
          <Route path="/office" element={<OldOffice />} />
          <Route path="/fleets" element={<FleetsScreen />} />
          <Route path="/port" element={<Navigate to={HOME_TAB} replace />} />
          <Route path="/map" element={<MapScreen />} />
          {/* 0455: the Land tab. Its cell is on the bar only while the world serves land_enabled; dark, this route prints "Not open yet." */}
          <Route path="/land" element={<LandScreen />} />
          <Route path="/stats" element={<StatsScreen />} />
          <Route path="/ledger" element={<LedgerScreen />} />
          <Route path="/rank" element={<RankScreen />} />
          {/* X3 (2026-11-23): the world's lanes moved to /lanes (a door on Stats > Markets); an old /routes link opens HQ, whose
              Market plate's "From here" line names what to sell where from her harbour. */}
          <Route path="/lanes" element={<RoutesScreen />} />
          <Route path="/routes" element={<Navigate to={HOME_TAB} replace />} />
          <Route path="/compendium" element={<CompendiumScreen />} />
          <Route path="/you" element={<YouScreen />} />
          <Route path="/levels" element={<LevelsScreen />} />
          {/* 0478: the logbook (roadmap slice 9). Its door is You's logbook card, drawn only while the server serves it on. */}
          <Route path="/logbook" element={<LogbookScreen />} />
          <Route path="/profile" element={<ProfileScreen />} />
        </Route>
        <Route path="/" element={<Navigate to={LANDING} replace />} />
        <Route path="*" element={<Navigate to={LANDING} replace />} />
      </Routes>
      </div>
    </BrowserRouter>
  )
}

/** An old `/office` link: HQ, on the sheet or plate its face became. `?face=invest|report` are HQ's two sheets; the City face's
 *  yard, repair dock and gear are HQ's Port plate; its academy is the Skills sheet; every other building is a plate on HQ itself. */
function OldOffice() {
  const q = new URLSearchParams(useLocation().search)
  const face = q.get('face')
  const building = q.get('building')
  const to =
    face === 'invest' || face === 'report'
      ? hqHref({ ask: { sheet: face } })
      : building === 'academy'
        ? hqHref({ ask: { sheet: 'academy' } })
        : building === 'building_yard' || building === 'shipyard' || building === 'gear'
          ? hqHref({ place: PORT_PLACE })
          : HOME_TAB
  return <Navigate to={to} replace />
}
