import { create } from 'zustand'
import type { Session, User } from '@supabase/supabase-js'
import { hasCloud, supabase } from '../lib/supabase'

/**
 * Where this session's authority lives.
 *
 * - `cloud`  — a Supabase project. Sign-in is real; the server is the authority.
 * - `local`  — no project configured. The game runs against the local chain (D6) and there is
 *              nobody to sign in as, so the gate opens for a single local captain.
 *
 * There is ONE authority for "may this player see the game": `authed`. Every gate reads that
 * field and nothing else, so the two modes cannot drift apart.
 */
export type AuthMode = 'cloud' | 'local'

interface AuthState {
  mode: AuthMode
  session: Session | null
  user: User | null
  /** The one gate. True when the player may see the game, in either mode. */
  authed: boolean
  /** True until the initial session check completes. Guards routing. */
  loading: boolean
  signUp: (email: string, password: string) => Promise<{ error: string | null }>
  signIn: (email: string, password: string) => Promise<{ error: string | null }>
  signOut: () => Promise<void>
  /** Wire up auth listening. Call once on app mount. */
  init: () => () => void
}

const NO_CLOUD = 'This build has no cloud project configured, so there is nobody to sign in as.'

export const useAuthStore = create<AuthState>((set) => ({
  mode: hasCloud ? 'cloud' : 'local',
  session: null,
  user: null,
  authed: false,
  loading: true,

  signUp: async (email, password) => {
    if (!supabase) return { error: NO_CLOUD }
    const { error } = await supabase.auth.signUp({ email, password })
    return { error: error?.message ?? null }
  },

  signIn: async (email, password) => {
    if (!supabase) return { error: NO_CLOUD }
    const { error } = await supabase.auth.signInWithPassword({ email, password })
    return { error: error?.message ?? null }
  },

  signOut: async () => {
    if (!supabase) return
    await supabase.auth.signOut()
  },

  init: () => {
    if (!supabase) {
      // Local mode: there is no session to wait for. Open the gate immediately rather than
      // leaving the app on its boot skeleton forever.
      set({ mode: 'local', session: null, user: null, authed: true, loading: false })
      return () => {}
    }

    supabase.auth.getSession().then(({ data }) => {
      set({
        session: data.session,
        user: data.session?.user ?? null,
        authed: Boolean(data.session),
        loading: false,
      })
    })

    const { data: sub } = supabase.auth.onAuthStateChange((_event, session) => {
      set({
        session,
        user: session?.user ?? null,
        authed: Boolean(session),
        loading: false,
      })
    })

    return () => sub.subscription.unsubscribe()
  },
}))
