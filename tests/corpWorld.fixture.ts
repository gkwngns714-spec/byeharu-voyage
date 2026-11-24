import { patchedWorldImage } from './worldImage.fixture'

// THE HQ COMPANY'S WORLD (tests/hq.corp.spec.ts, tests/hq.join.spec.ts): the shipped image with the switches production runs lit,
// the served board, the standing jobs and the Land lit; a fresh company, one barca at Lisbon, and the land party.
// THE JOBS TICK: on a server pg_cron calls public.tick_fleet_jobs every 2 minutes; a tab has no cron. So this world runs the same
// procedure (one pass, in the caller's transaction, as the migration's own self-assert does) right after a job is set.

const LIT = [
  'raid_companies_enabled',
  'yard_order_enabled',
  'hold_requests_enabled',
  'houses_board_enabled',
  'level_unlocks_enabled',
  'world_events_enabled',
  'pirate_bounties_enabled',
  'first_hour_enabled',
  'regard_enabled',
  'levels_bite',
  'land_enabled',
  'hq_board_enabled',
  'fleet_jobs_enabled',
]

/** `courses`: 0482's switch lit too (sea_courses_enabled: the server holds a course between any two harbours, so a job's run needs no
 *  voyage sailed before it, and a board card's run can be assigned as it stands).
 *  `home`: 0492's switch lit too (assign_home_enabled: Bring home and the run count). */
export const corpWorld = ({ courses = false, home = false }: { courses?: boolean; home?: boolean } = {}) =>
  patchedWorldImage(`hq-corp${courses ? '-courses' : ''}${home ? '-home' : ''}`, async (pg) => {
    const keys = [...LIT, ...(courses ? ['sea_courses_enabled'] : []), ...(home ? ['assign_home_enabled'] : [])]
    await pg.exec(`update public.world_config set value = 'true'::jsonb where key in (${keys.map((k) => `'${k}'`).join(', ')})`)
    await pg.exec(`update public.world_config set value = 'false'::jsonb where key = 'sea_conditions_bite'`)
    await pg.exec(`
      create function public.spec_tick_fleet_jobs() returns trigger language plpgsql security definer set search_path = public, pg_temp as $f$
      begin
        if pg_trigger_depth() = 1 then call public.tick_fleet_jobs(false); end if;
        return null;
      end $f$;
      create trigger spec_tick_fleet_jobs after insert or update of since on public.fleet_jobs
        for each statement execute function public.spec_tick_fleet_jobs();`)
  })
