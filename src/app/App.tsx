import { useEffect } from 'react'
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import { useAuthStore } from '../store/authStore'
import { RequireAuth } from './RequireAuth'
import { AppShell } from './AppShell'
import { HOME_TAB } from './navTabs'
import { AuthPage } from '../features/auth/AuthPage'
import { GalleryScreen } from '../features/gallery/GalleryScreen'
import { CommandScreen } from '../features/command/CommandScreen'
import { FleetsScreen } from '../features/fleets/FleetsScreen'
import { PortScreen } from '../features/port/PortScreen'
import { MarketScreen } from '../features/market/MarketScreen'
import { MapScreen } from '../features/map/MapScreen'
import { LedgerScreen } from '../features/ledger/LedgerScreen'
import { RankScreen } from '../features/rank/RankScreen'
import { CompendiumScreen } from '../features/compendium/CompendiumScreen'
import { ProfileScreen } from '../features/profile/ProfileScreen'

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
      <Routes>
        <Route path="/auth" element={<AuthPage />} />
        {/* THE DESIGN-SYSTEM GALLERY (docs/UI_DIRECTION.md §7 step 2). Outside RequireAuth and
            outside AppShell on purpose: it reads nothing from the world, so it renders instantly
            and tests/primitives.geometry.spec.ts can measure the twelve primitives without paying
            the cold chain — and without skipping on a cloud build. It is not in the tab table and
            nothing links to it. See features/gallery/GalleryScreen.tsx. */}
        <Route path="/ui" element={<GalleryScreen />} />
        <Route
          element={
            <RequireAuth>
              <AppShell />
            </RequireAuth>
          }
        >
          <Route path="/command" element={<CommandScreen />} />
          <Route path="/fleets" element={<FleetsScreen />} />
          <Route path="/port" element={<PortScreen />} />
          <Route path="/market" element={<MarketScreen />} />
          <Route path="/map" element={<MapScreen />} />
          <Route path="/ledger" element={<LedgerScreen />} />
          <Route path="/rank" element={<RankScreen />} />
          <Route path="/compendium" element={<CompendiumScreen />} />
          <Route path="/profile" element={<ProfileScreen />} />
        </Route>
        <Route path="/" element={<Navigate to={HOME_TAB} replace />} />
        <Route path="*" element={<Navigate to={HOME_TAB} replace />} />
      </Routes>
    </BrowserRouter>
  )
}
