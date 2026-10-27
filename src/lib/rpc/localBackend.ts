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

/** HOW THIS TAB LETS THE PLANNER RUN THE SNAPSHOT JOB: in the order its FROM clause is written
 *  (`join_collapse_limit = 1`, transaction-local — `set_config(…, true)` ends with callAs's transaction).
 *
 *  THE FREEZE (owner report via docs/WORK_QUEUE.md #349; measured 2026-10-27, Node PGlite, main's image):
 *  0226's writer (`public.tick_price_snapshot`, supabase/migrations/…0226…sql:241-249) joins
 *  `price_record_pairs()` (1,380 recorded pairs) to `port_goods` (138,990 rows) and the port terms. PGlite's
 *  planner, guessing 1,000 rows for the function scan, builds a hash over EVERY port_goods row of each port —
 *  so `world.mid_price` and `world.price_sides` ran 138,990 times to keep 1,380: 9.1 s native, tens of
 *  seconds in a tab, the whole of it on the one PGlite queue, so every read and every press waited for the
 *  first record read after each 15-minute slot edge. In the written order the recorded pairs drive and the
 *  port_goods primary key answers each one: 0.27 s, and the price_history / _hour / _day rows and the
 *  rollup marks are byte-identical (tests/rpc.recordEdge.spec.ts proves both on the shipped world).
 *
 *  A planner setting changes no answer, only the road to it, so 0226 (frozen) is not edited and the cloud,
 *  whose pg_cron runs the job off every player's request path, is untouched. Exported for that spec. */
export const RECORD_PLAN_SQL = `set_config('join_collapse_limit', '1', true)`

/** The snapshot job, as this tab plays it: the present slot (the job's own function, only when the slot
 *  holds nothing), and — until the previous slot holds something too — a copy of the present slot one
 *  slot back, so a fresh record has a line to draw ("the market as it stands"). Since 0226 the chain's
 *  own apply writes the present slot (its backfill run), so a world image built minutes ago holds one
 *  slot, and one point is not a line (tests/layout.spec.ts, the Trend row). The planner setting comes
 *  first by CASE's own evaluation order (each WHEN in turn), so the job is planned under it. */
const RECORD_SQL = `with t as (
    select case when ${RECORD_PLAN_SQL} is null then null
                when not exists (select 1 from public.price_history where slot = public.drift_slot_of(now()))
                then public.tick_price_snapshot(now()) end as r
  ), c as (
    insert into public.price_history (port_id, good_id, slot, at, mid, stock, ask, bid)
    select h.port_id, h.good_id, h.slot - 1, h.at - make_interval(secs => public.wc_num('drift_slot_seconds')::double precision),
           h.mid, h.stock, h.ask, h.bid
      from public.price_history h
     where h.slot = public.drift_slot_of(now())
       and not exists (select 1 from public.price_history p where p.slot = public.drift_slot_of(now()) - 1)
    on conflict (port_id, good_id, slot) do nothing
    returning 1
  )
  select t.r as result from t`

/** Play the snapshot job ONCE at boot, before the app's first read is queued. The world image is built
 *  minutes (in CI, a quarter-hour) before a tab opens it, so the present slot is usually empty and the
 *  first read of the record would run the job with nothing else answered (before RECORD_PLAN_SQL that
 *  was ~10 s native, far more in a tab — a tray left on "Checking max…", the sweep at 1440×900, main
 *  red 2026-10-26). Run here, its cost lands inside the boot wait where a screen is still loading. */
export function warmRecord(db: Pick<LocalCaller, 'callAs'>): Promise<void> {
  return db.callAs<unknown>(RECORD_SQL).then(
    () => undefined,
    () => undefined, // the first read of the record runs it again and reports a real failure
  )
}

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
