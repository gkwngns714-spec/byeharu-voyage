import { createClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY

if (!url || !anonKey) {
  // Surfaced early so a missing .env is obvious in dev instead of a cryptic
  // network error later.
  console.warn(
    '[byeharu-voyage] Missing VITE_SUPABASE_URL or VITE_SUPABASE_ANON_KEY. ' +
      'Copy .env.example to .env.local and fill in your Supabase project values.',
  )
}

// THE ONE client. Every state change in this game is a Postgres RPC through here — the client
// renders and requests, the server decides. There is no second client and no direct table write.
export const supabase = createClient(url ?? '', anonKey ?? '', {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
  },
})
