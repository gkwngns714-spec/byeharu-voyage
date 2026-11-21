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
// the job does. And from 0266 a route whose rest is over starts her lap in its own job, not in the
// beat: so right after the beat this backend runs that job's one pass too, `call
// public.tick_lap_starts(false)` (THE SAME PROCEDURE the lap-start job runs, in this transaction).

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
 *  holds nothing), and — until the record reaches one slot's length back — a copy of the start of the
 *  recent record one slot further back, so a fresh record has a line to draw ("the market as it stands").
 *  Since 0226 the chain's own apply writes the present slot (its backfill run), so a world image built
 *  minutes ago holds one slot, and one point is not a line (tests/layout.spec.ts, the Trend row). The
 *  planner setting comes first by CASE's own evaluation order (each WHEN in turn), so the job is planned
 *  under it.
 *
 *  THE SLOT EDGE (2026-11-18, docs/dev-log/2026-11-18-play-faults.md; tests/news.dotSize.spec.ts at 1280 red
 *  once on CI). The copy used to be "the present slot, while the previous slot holds nothing". A copy never
 *  sees the rows the same statement's snapshot writes, so the boot's call writes the present slot and the
 *  NEXT call copies it back. A tab that booted seconds before a slot's edge wrote slot N at boot and read
 *  in slot N+1: slot N, the new "previous slot", was not empty, so nothing was ever copied back, and the
 *  record began at the boot (two points 4.5 s apart on CI, run 43784696446). Every chart then started
 *  after anything that happened before the tab opened, and world.news_marks, asked from the record's
 *  first minute, gave its news no dot. The condition is now the one the line needs, read by time: no row
 *  of the last two slots is a slot's length old. `clock` is the SQL instant (now() in the tab; a spec
 *  fixes it to reproduce an edge). */
export const recordSqlAt = (clock: string) => `with t as (
    select case when ${RECORD_PLAN_SQL} is null then null
                when not exists (select 1 from public.price_history where slot = public.drift_slot_of(${clock}))
                then public.tick_price_snapshot(${clock}) end as r
  ), c as (
    insert into public.price_history (port_id, good_id, slot, at, mid, stock, ask, bid)
    select h.port_id, h.good_id, h.slot - 1, h.at - make_interval(secs => public.wc_num('drift_slot_seconds')::double precision),
           h.mid, h.stock, h.ask, h.bid
      from public.price_history h
     where h.slot = (select min(r.slot) from public.price_history r where r.slot >= public.drift_slot_of(${clock}) - 1)
       and not exists (select 1 from public.price_history p
                        where p.slot >= public.drift_slot_of(${clock}) - 2
                          and p.at <= ${clock} - make_interval(secs => public.wc_num('drift_slot_seconds')::double precision))
    on conflict (port_id, good_id, slot) do nothing
    returning 1
  )
  select t.r as result from t`
const RECORD_SQL = recordSqlAt('now()')

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
// 0316: the history job follows the count, in this tab as on the server
const STATS_SQL = 'with s as materialized (select public.tick_stats(now()) as r) select public.tick_history(now()) as result from s'
const STATS_READS: readonly RpcName[] = [
  'worldStatsOverview',
  'worldStatsMarkets',
  'worldStatsCities',
  'worldStatsCity',
  'worldStatsMerchants',
  'worldStatsMe',
  'worldStatsFleets',
  'worldStatsFleetList',
  'worldStatsFleet',
  'worldHistory',
  // 0467: the houses' board is counted by the history job's run
  'worldHousesWeek',
]

// AND THE MARKET (2026-11-18, docs/dev-log/2026-11-18-play-faults.md). On Supabase byeharu-voyage:drift steps every
// harbour's market rows each minute (public.tick_market_drift_each_port: the drift, and the stock regenerated over the game
// days passed); in this tab nothing did, so a harbour's rows moved only when its own market was read (world.market ticks
// that one quay). Every other harbour kept the stock the world image was built with, hundreds of game days behind:
// world.quote priced a sale at Setubal from that stale stock (cinnamon 1,116 a unit, the card "+22,416"), and the sale,
// on rows caught up by then, paid 680 a unit (+617). The card, the plan and the sale already share world.quote; what
// differed was the row it read. So the tab plays THE SAME STEP the job's runs add up to — public.tick_market_drift for
// every harbour (the job splits it one harbour a transaction, which a CALL inside this tab's transaction cannot do) —
// once at boot, before the app's first read, and then every minute, as the job does. Idempotent by slot and game day:
// a call with nothing due changes nothing. The cloud backend does nothing of the kind, because the job does. Node specs
// that build this backend themselves are not affected: only the app's own boot (src/lib/rpc/init.ts) runs it.

/** How often this tab plays the drift job: the job's own schedule on Supabase (every minute). */
export const MARKET_EVERY_MS = 60_000
const MARKET_SQL = 'select public.tick_market_drift(now()) as result'

// A SLOT AHEAD OF THE CLOCK (2026-11-19; the "seen, not fixed" of docs/dev-log/2026-11-18-play-faults.md). The world image holds 54,432
// market rows (224 harbours x 243 goods) whose drift_slot is 2,986,699, with the present slot near 1,994,000. Migration 0053 (frozen)
// ends with `select public.tick_market_drift(now())` at the chain's own apply, when drift_slot_seconds was still 600: it stamped
// floor(epoch / 600). The knob went to 900 and, with 0413's anchor, to 4,500 s; a stored slot is in the units of its day, so those rows
// stand 1.5 times as far on as the clock. `tick_market_drift` steps only `drift_slot < present`, so their drift never moves in a tab.
// Production reads 0 such rows (06:2x UTC 2026-11-18), so the job there has nothing to repair; the image's chain has. Each such row
// is put at the slot of its own `updated_at` read in today's counter (what the job would have left it at: the image's other 62,160
// stamped rows, written in the same minute under the 900 s knob, read 1,991,133 and are caught up by the step below), then stepped as
// any other. A write in the job, once per row, never a clamp on a read.
const RESTAMP_SQL = `update public.port_goods set drift_slot = public.drift_slot_of(updated_at)
   where drift_slot > (select public.drift_slot_of(now()))`

/** Play the drift job once: every harbour's rows brought to the present slot and game day. */
export function playMarket(db: Pick<LocalCaller, 'callAs'>): Promise<void> {
  return db
    .callAs<unknown>(RESTAMP_SQL)
    .then(() => db.callAs<unknown>(MARKET_SQL))
    .then(
      () => undefined,
      (err: unknown) => console.warn('[rpc] local: the market step failed; the next minute plays it again', err),
    )
}

// AND THE BATTLES (0364, the map's rings). On Supabase byeharu-voyage:battles fights every round that is due, each minute
// (public.tick_battles, 0323 / 0357); in this tab nothing does, so a battle somebody else is in would never move for a
// watcher. So before a read of the battles on the map (world.fights, world.fight) this backend runs THE SAME FUNCTION:
// one read of one partial index when no battle is due, which is every call while attacks are dark.
const BATTLES_SQL = 'select public.tick_battles(now()) as result'

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
          ? db
              .callAs<unknown>('select public.tick_arrivals(now()) as result')
              .then(() => db.callAs<unknown>('call public.tick_lap_starts(false)'))
          : name === 'worldFights' || name === 'worldFight'
            ? db.callAs<unknown>(BATTLES_SQL)
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
