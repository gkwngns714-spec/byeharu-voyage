import { createClient, type SupabaseClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY

/**
 * Is there a cloud to talk to?
 *
 * V0 is played against a local Postgres (PGlite) running the same migration chain — see D6 in
 * docs/DEV_LOG.md — so a missing Supabase project is a NORMAL state, not a broken one. The app
 * must boot and be playable without it.
 *
 * `createClient('', '')` throws `supabaseUrl is required` at module load, which took the whole
 * app down with a white screen. So the client is only constructed when there is something to
 * construct it against.
 */
export const hasCloud = Boolean(url && anonKey)

/**
 * THE ONE client, or null when running local-only. Every state change in this game is a Postgres
 * RPC — the client renders and requests, the server decides. There is no second client and no
 * direct table write.
 */
export const supabase: SupabaseClient | null = hasCloud
  ? createClient(url as string, anonKey as string, {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
      },
    })
  : null

if (!hasCloud) {
  console.info(
    '[byeharu-voyage] No VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY — running in LOCAL mode. ' +
      'The game runs against the local chain; sign-in is skipped. ' +
      'Copy .env.example to .env.local to point at a cloud project.',
  )
}
