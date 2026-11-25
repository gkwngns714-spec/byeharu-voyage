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

/** `near`: 0497's and 0498's switches lit too (jobs_wait_enabled, near_round_enabled: a job waits instead of losing, and the near
 *  round is offered). `nearLow`: and every near round is given a round of ONE mile as it is set (a spec's own trigger on her job's
 *  row), so nothing is within it and she waits for a price at her base at once: the wait state without hours of play.
 *  `courses`: 0482's switch lit too (sea_courses_enabled: the server holds a course between any two harbours, so a job's run needs no
 *  voyage sailed before it, and a board card's run can be assigned as it stands).
 *  `home`: 0492's switch lit too (assign_home_enabled: Bring home and the run count). */
export const corpWorld = ({ courses = false, home = false, near = false, nearLow = false, slow = false, wreck = false }: { courses?: boolean; home?: boolean; near?: boolean; nearLow?: boolean; slow?: boolean; wreck?: boolean } = {}) =>
  patchedWorldImage(`hq-corp${courses ? '-courses' : ''}${home ? '-home' : ''}${near ? '-near' : ''}${nearLow ? '-low' : ''}${slow ? '-slow' : ''}${wreck ? '-wreck' : ''}`, async (pg) => {
    // (0500: her job then WAITS for her repair. A tab has no cron, so the yard's work done is followed by the jobs' tick, as the next
    // two minutes would: the trigger at the foot of this world.)
    // `wreck`: the FIRST SAIL order ever queued finds its flagship a wreck (her hull put at nought as the order is written, once), so
    // the server refuses it E_FLAGSHIP_DISABLED and her job stops on it: prod's case of 24 Nov, without a fight.
    if (wreck)
      await pg.exec(`
        create sequence public.spec_wrecks;
        create function public.spec_wreck_once() returns trigger language plpgsql security definer set search_path = public, pg_temp as $f$
        begin
          if nextval('public.spec_wrecks') = 1 then
            update public.ships set durability = 0 where fleet_id = new.fleet_id and is_flagship;
          end if;
          return null;
        end $f$;
        -- the run's cargo may have taken all her coin (its good is the day's market's): when the sail is refused she has the yard's price
        create function public.spec_wreck_coin() returns trigger language plpgsql security definer set search_path = public, pg_temp as $f$
        begin
          perform public.credit(new.player_id, 'PROOF', 20000, null);
          return null;
        end $f$;
        create trigger spec_wreck_coin after update of status on public.orders for each row
          when (new.status = 'failed' and new.error_code = 'E_FLAGSHIP_DISABLED' and old.status <> 'failed') execute function public.spec_wreck_coin();
        create trigger spec_wreck_once after insert on public.orders for each row when (new.verb = 'SAIL') execute function public.spec_wreck_once();`)
    // `slow`: world.actions' FIRST answer is its last resort, closed E_SLOW (the read took too long), and every later one is the real
    // read: the real function is kept under another name and a spec's own door counts its calls.
    if (slow)
      await pg.exec(`
        alter function world.actions(text) rename to actions_real;
        create sequence public.spec_slow_asks;
        create function world.actions(p_worker text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $f$
        begin
          if nextval('public.spec_slow_asks') = 1 then
            return jsonb_build_object('company', true, 'worker', p_worker, 'kind', 'fleet', 'now', now(), 'ask_s', 300, 'options', '[]'::jsonb, 'cut', false,
                                      'closed', jsonb_build_object('code', 'E_SLOW', 'sentence', 'the quotes are slow just now: ask again in a moment'), 'ms', 5000);
          end if;
          return world.actions_real(p_worker);
        end $f$;
        revoke all on function world.actions(text) from public, anon;
        grant execute on function world.actions(text) to authenticated;`)
    const keys = [...LIT, ...(courses ? ['sea_courses_enabled'] : []), ...(home ? ['assign_home_enabled'] : []), ...(near ? ['jobs_wait_enabled', 'near_round_enabled'] : [])]
    if (nearLow)
      await pg.exec(`
        create function public.spec_near_low() returns trigger language plpgsql as $f$
        begin
          if new.params ? 'within' then new.params := new.params || jsonb_build_object('within', 1); end if;
          return new;
        end $f$;
        create trigger spec_near_low before insert or update of params on public.fleet_jobs
          for each row execute function public.spec_near_low();`)
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
    if (wreck)
      await pg.exec(`
        -- the yard works for seconds here, not minutes (nothing of it is asserted)
        update public.world_config set value = '0.04'::jsonb where key = 'repair_sim_hours_per_pct';
        create function public.spec_tick_repaired() returns trigger language plpgsql security definer set search_path = public, pg_temp as $f$
        begin
          if old.status = 'REPAIRING' and new.status = 'DOCKED' then
            -- the jobs' tick after the yard's work, and the one ten minutes on (a tab has no clock to wait for): 0500's first still stops her
            -- on the plan that failed when the sail was refused, until her next_at; the next lifts that stop and she goes on with her run
            call public.tick_fleet_jobs(false);
            update public.fleet_jobs set next_at = now() - interval '1 second' where fleet_id = new.id;
            call public.tick_fleet_jobs(false);
          end if;
          return null;
        end $f$;
        create constraint trigger spec_tick_repaired after update of status on public.fleets deferrable initially deferred
          for each row execute function public.spec_tick_repaired();`)
  })
