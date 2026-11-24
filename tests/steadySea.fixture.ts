/// <reference types="node" />
// THE SHIPPED WORLD WITH A STEADY SEA AND THE FASTER CLOCK — for a spec that waits a trip out against the time the game showed.
//
// WHY. tests/map.autoroute.spec.ts sails a chained trip to its end and holds the arrival to the time on the row. The row's time is
// the trip with no weather: `voyage.hazard_roll` rolls every voyage-day, and a storm adds 36 sim-hours to the leg (a calm 24 to 96;
// `voyage.day_delay_hours`), which no quote can know. So the drive was red whenever the sea delayed her: Acceptance run 45402237343
// on main, about 11.5 real minutes late with the fleet still under way; one storm is 36 sim-hours, 11.25 real minutes at
// time_compression 192. The spec is about the planner, the one press and the price, not about the weather.
//
// WHAT, through the chain's own knobs and door only (a patched COPY of the built image, tests/worldImage.fixture.ts; no body is
// rewritten in the steady world):
//   * `hazard_p_max` 0. It is the ceiling of a day's chance in `voyage.hazard_roll` (p = least(hazard_p_max, the sea's base x the
//     leg's mult)), so no day of any voyage meets a storm, a calm, a fair wind or a raider. Sailing, stores, wages, dock fees, the
//     calls on the way and the queue are untouched: the trip is the one the row quoted.
//   * `public.clock_set(960)`, THE ONE DOOR TO MOVE THE CLOCK'S RATE (0413; 960 is the rate the world ran at before it, and that
//     file's own rollback). It moves the knob, the market's counters, the economy's rates per real time and the clock's anchor
//     together, so everything keeps its proportion to a voyage-day and only the real wait shrinks: a voyage-day is 90 real seconds,
//     not 450. Miles, knots, days, supplies, wages and dock fees are the same figures; a call in port stays its real minute
//     (`port_prep_seconds`), and the row's real time counts it.
//
// THE STORM SCENE (not run by the suite; it is how the cause was confirmed, and how it can be seen again):
//   STEADY_SEA_STORM=1 npx playwright test map.autoroute.spec.ts -g "one press"
// serves the same world with ONE storm put on day 1 of the first voyage the page's company sails (the first SAIL of the chain); the
// roll is pinned as tests/fightWorld.fixture.ts pins a raid, and every other day of every voyage rolls as the chain rolls (never,
// at the ceiling above). The drive then fails as the run on main did: she is under way to the city and arrives 36 sim-hours late
// (135 real seconds at 960), past the stated tolerance.

import type { Page } from '@playwright/test'
import { LOCAL_AUTH_UID } from '../src/lib/db/localDb'
import { patchedWorldImage, serveWorldImage } from './worldImage.fixture'

/** The rate the steady world sails at: the world's own before 0413 (a voyage-day is 90 real seconds). */
export const STEADY_TIME_COMPRESSION = 960

/** True when this run asks for the storm scene (see the head of this file). */
export const STORM_SCENE = process.env.STEADY_SEA_STORM === '1'

const STORM_SQL = `
  alter function voyage.hazard_roll(uuid, integer) rename to hazard_roll_real_spec;
  create function voyage.hazard_roll(p_voyage uuid, p_day integer)
  returns table (occurred boolean, kind text, magnitude numeric, p_hazard numeric)
  language plpgsql stable security definer set search_path = public, pg_temp as $$
  begin
    -- her FIRST voyage (the first SAIL of the chain), day 1: a storm. A pure function of the voyage and the day, as the real roll is.
    if p_day = 1 and p_voyage = (select v.id from public.voyages v join public.players p on p.id = v.player_id
                                  where p.auth_uid = '${LOCAL_AUTH_UID}'::uuid order by v.departed_at, v.id limit 1) then
      return query select true, 'STORM'::text, 0.5::numeric, 1::numeric;
    else
      return query select * from voyage.hazard_roll_real_spec(p_voyage, p_day);
    end if;
  end $$;
  revoke all on function voyage.hazard_roll(uuid, integer) from public, anon, authenticated;
`

/** The shipped world with no weather on any day and the clock at 960; with `storm`, one storm on the first leg she sails. */
export function steadySea(storm = false): Promise<Buffer> {
  return patchedWorldImage(storm ? 'steady-sea-storm' : 'steady-sea', async (pg) => {
    const knob = await pg.query(`update public.world_config set value = to_jsonb(0) where key = 'hazard_p_max' returning key`)
    if (knob.rows.length !== 1) throw new Error('world_config has no hazard_p_max row')
    const moved = await pg.query<{ time_compression: number }>(
      `select (public.clock_set(${STEADY_TIME_COMPRESSION}, now()) ->> 'time_compression')::int as time_compression`,
    )
    const rate = await pg.query<{ rate: number }>(`select public.wc_num('time_compression')::int as rate`)
    if (moved.rows[0]?.time_compression !== STEADY_TIME_COMPRESSION || rate.rows[0]?.rate !== STEADY_TIME_COMPRESSION) {
      throw new Error(`public.clock_set did not put the clock at ${STEADY_TIME_COMPRESSION}: ${JSON.stringify([moved.rows, rate.rows])}`)
    }
    if (storm) await pg.exec(STORM_SQL)
  })
}

/** Serve the steady world (or, in the storm scene, the one with the storm) to `page` in place of the shipped image. */
export async function serveSteadySea(page: Page): Promise<void> {
  await serveWorldImage(page, await steadySea(STORM_SCENE))
}
