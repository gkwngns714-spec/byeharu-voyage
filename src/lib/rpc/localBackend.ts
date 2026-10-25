// The LOCAL backend: the same function call, as SQL, against the chain running in this tab.
//
// It knows two things the cloud backend does not have to: the SQL text (built from the catalogue)
// and the local captain's identity (set inside the same transaction as the call, because
// `cmd.assume_identity()` is transaction-local by design). Neither leaks upward — `invoke` returns
// the same jsonb PostgREST would.
//
// THE ONE PLACE THIS BACKEND PLAYS THE CLOCK (0099, docs/NPC_TRADERS.md §8.5). On Supabase,
// pg_cron's arrivals job settles every merchant fleet every minute; in this tab there is no
// pg_cron, so nothing would ever move a merchant between reads and a local world's merchants would
// freeze at their ETA. So immediately before every MERCHANT read that is about where a merchant IS
// — `world.sea_traffic()`, and from 0104 `world.port_merchants()`, which is the whole of what PORT
// asks and would otherwise never see one arrive — this backend runs `public.tick_arrivals(now())`:
// THE SAME FUNCTION the job runs, a different driver. A player's own fleets need no such thing
// (every read of theirs settles them first). The cloud backend does nothing of the kind, because
// the job does.

//
// AND THE PRICE RECORD (2026-10-18, the COMMAND desk). On Supabase the snapshot job records every
// offered price each drift slot (public.tick_price_snapshot, pg_cron); in this tab nothing does, and a
// fresh world's only record was 0061's self-assert snapshot at now() + 1 hour — a row on no present
// slot, which 0170 removed with the rest of its kind. So before a read of the RECORD (world.price_series,
// world.watchlist) this backend runs the SAME function the job runs: at most once in RECORD_EVERY_MS,
// idempotent per slot (the first sample in a slot is the sample). A world with nothing in the present
// window starts its record at the previous slot boundary and now — the market as it stands, the two
// points a line needs — exactly as the job's first two runs would have. The cloud backend does nothing
// of the kind, because the job does.
//
// AND THE STATS ROLLUP (0214, the Stats tab). On Supabase byeharu-voyage:stats writes the world's figures
// every fifteen minutes (public.tick_stats); in this tab nothing does, so before a read of them
// (world.stats_*) this backend runs THE SAME FUNCTION, at most once in STATS_EVERY_MS; it is idempotent per
// slot, so a re-ask is a no-op. The same idiom as the record above, for the same reason.

import { RPCS, localSql, rpcLabel, type RpcName } from './catalog'
import type { RpcBackend } from './backend'

/** How often this tab may play the snapshot job — a slot is 15 minutes; a re-ask within this is a no-op. */
const RECORD_EVERY_MS = 30_000

/** The snapshot job, as this tab plays it: the present slot, and — until the present window holds TWO
 *  slots — the previous boundary first, so a fresh record has a line to draw. Two, not "any": since 0226
 *  the chain's own apply writes the present slot (its backfill run), so a world image built minutes ago
 *  already holds one slot, and one point is not a line (tests/layout.spec.ts, the Trend row). */
const RECORD_SQL = `select case
    when (select count(distinct slot) from public.price_history where slot >= public.drift_slot_of(now()) - 1) >= 2
      then public.tick_price_snapshot(now())
    else public.tick_price_snapshot(now() - make_interval(secs => public.wc_num('drift_slot_seconds')::double precision))
         || public.tick_price_snapshot(now())
  end as result`

/** How often this tab may play the stats job (0214). Its row is per slot; a re-ask inside a slot writes nothing. */
const STATS_EVERY_MS = 60_000
const STATS_SQL = 'select public.tick_stats(now()) as result'
const STATS_READS: readonly RpcName[] = [
  'worldStatsOverview',
  'worldStatsMarkets',
  'worldStatsCities',
  'worldStatsCity',
  'worldStatsMerchants',
  'worldStatsMe',
]

/** The slice of LocalDb this needs — structural, so a spec can hand in its own engine. */
export interface LocalCaller {
  callAs<T>(sql: string, params?: unknown[]): Promise<T>
  readonly authUid: string
  readonly fingerprint: string
}

export function createLocalBackend(db: LocalCaller): RpcBackend {
  let recordedAt = 0
  let statsAt = 0
  return {
    kind: 'local',
    describe: `PGlite in this tab · chain ${db.fingerprint} · captain ${db.authUid}`,
    invoke(name: RpcName, values: readonly unknown[]) {
      // The catalogue fixes the arity: the SQL always names every parameter, so the parameter
      // ARRAY always has to be that long. Postgres applies a DEFAULT only to an argument that is
      // absent, not to one that is present and null — and every optional parameter in this chain
      // defaults to null, so a padded null is the identical call.
      const params = RPCS[name].args.map((_, i) => values[i] ?? null)
      const record = name === 'worldPriceSeries' || name === 'worldWatchlist'
      const due = record && Date.now() - recordedAt >= RECORD_EVERY_MS
      if (due) recordedAt = Date.now()
      const statsDue = STATS_READS.includes(name) && Date.now() - statsAt >= STATS_EVERY_MS
      if (statsDue) statsAt = Date.now()
      const clock =
        name === 'worldSeaRoster' || name === 'worldPortMerchants'
          ? db.callAs<unknown>('select public.tick_arrivals(now()) as result')
          : due
            ? db.callAs<unknown>(RECORD_SQL)
            : statsDue
              ? db.callAs<unknown>(STATS_SQL)
              : Promise.resolve(null)
      return clock.then(() => db.callAs<unknown>(localSql(name), params)).catch((err: unknown) => {
        if (err instanceof Error) err.message = `${err.message} (in ${rpcLabel(name)})`
        throw err
      })
    },
  }
}
