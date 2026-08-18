import { useEffect } from 'react'
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import { useAuthStore } from '../store/authStore'
import { RequireAuth } from './RequireAuth'
import { AppShell } from './AppShell'
import { HOME_TAB } from './navTabs'
import { AuthPage } from '../features/auth/AuthPage'
import { CommandScreen } from '../features/command/CommandScreen'
import { FleetsScreen } from '../features/fleets/FleetsScreen'
import { PortScreen } from '../features/port/PortScreen'
import { MarketScreen } from '../features/market/MarketScreen'
import { MapScreen } from '../features/map/MapScreen'
import { LedgerScreen } from '../features/ledger/LedgerScreen'
import { RankScreen } from '../features/rank/RankScreen'
import { ProfileScreen } from '../features/profile/ProfileScreen'

// THE ROUTE TABLE. One destination per tab (src/app/navTabs.ts is the tab table; these are the
// routes it names) under the ONE persistent shell. Everything authenticated sits inside
// RequireAuth + AppShell; /auth is the only route outside it.

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
          <Route path="/profile" element={<ProfileScreen />} />
        </Route>
        <Route path="/" element={<Navigate to={HOME_TAB} replace />} />
        <Route path="*" element={<Navigate to={HOME_TAB} replace />} />
      </Routes>
    </BrowserRouter>
  )
}
