import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import '../../index.css'
import { MapScreen } from './MapScreen'

// RENDER HARNESS — dev only. See preview.html for what it is and why it exists.
//
// It mounts the REAL MapScreen with the REAL design tokens, so what appears at
// /src/features/map/preview.html under `npm run dev` is the same component the Map tab mounts.
// It touches no store, no router and no Supabase client, which is the whole point: the map takes
// no orders and needs no session to be looked at.
//
// `vite build` only compiles index.html, so nothing here reaches a production bundle.

const host = document.getElementById('map-preview')
if (host) {
  createRoot(host).render(
    <StrictMode>
      <MapScreen />
    </StrictMode>,
  )
}
