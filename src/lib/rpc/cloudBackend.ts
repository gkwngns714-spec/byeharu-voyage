// The CLOUD backend: the same function call, through PostgREST, against a Supabase project.
//
// The identity is the caller's JWT — `cmd.assume_identity()` is revoked from every client role and
// is not used here; `auth.uid()` is real. That is the only difference in the call path, and it is
// invisible above `invoke`.
//
// NOT PROVEN AGAINST A REAL PROJECT. DEV_LOG D7: both free Supabase slots are taken, so V0 runs on
// the local engine and this backend has never made a round trip. What it needs on the day it does:
// the project's API settings must expose the `world`, `cmd` and `voyage` schemas (PostgREST serves
// `public` only, by default), exactly as supabase/migrations/CHAIN.md's "What is NOT proven here"
// records. The alternative — `public.` wrapper functions — would be a second entry point to the
// game, and the chain refuses to have one.

import type { SupabaseClient } from '@supabase/supabase-js'
import { RPCS, namedArgs, type RpcName } from './catalog'
import type { RpcBackend } from './backend'

export function createCloudBackend(supabase: SupabaseClient, label = 'Supabase'): RpcBackend {
  return {
    kind: 'cloud',
    describe: `${label} · PostgREST · schemas world/cmd exposed`,
    async invoke(name: RpcName, values: readonly unknown[]) {
      const spec = RPCS[name]
      const { data, error } = await supabase
        .schema(spec.schema)
        .rpc(spec.fn, namedArgs(name, values))
      if (error) throw error
      return data
    },
  }
}
