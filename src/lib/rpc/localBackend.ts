// The LOCAL backend: the same function call, as SQL, against the chain running in this tab.
//
// It knows two things the cloud backend does not have to: the SQL text (built from the catalogue)
// and the local captain's identity (set inside the same transaction as the call, because
// `cmd.assume_identity()` is transaction-local by design). Neither leaks upward — `invoke` returns
// the same jsonb PostgREST would.

import { RPCS, localSql, rpcLabel, type RpcName } from './catalog'
import type { RpcBackend } from './backend'

/** The slice of LocalDb this needs — structural, so a spec can hand in its own engine. */
export interface LocalCaller {
  callAs<T>(sql: string, params?: unknown[]): Promise<T>
  readonly authUid: string
  readonly fingerprint: string
}

export function createLocalBackend(db: LocalCaller): RpcBackend {
  return {
    kind: 'local',
    describe: `PGlite in this tab · chain ${db.fingerprint} · captain ${db.authUid}`,
    invoke(name: RpcName, values: readonly unknown[]) {
      // The catalogue fixes the arity: the SQL always names every parameter, so the parameter
      // ARRAY always has to be that long. Postgres applies a DEFAULT only to an argument that is
      // absent, not to one that is present and null — and every optional parameter in this chain
      // defaults to null, so a padded null is the identical call.
      const params = RPCS[name].args.map((_, i) => values[i] ?? null)
      return db.callAs<unknown>(localSql(name), params).catch((err: unknown) => {
        if (err instanceof Error) err.message = `${err.message} (in ${rpcLabel(name)})`
        throw err
      })
    },
  }
}
