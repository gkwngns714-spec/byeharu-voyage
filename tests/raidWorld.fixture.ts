// THE SHIPPED WORLD WITH ONE RAID OF FIXED FACTS — for the fight log's page spec (0353, docs/COMBAT_LOG.md).
//
// A page spec cannot wait for the sea to send raiders, and a real raid's numbers follow the hull the house was rolled
// (0276). So the patch fixes ONE raid, on ONE pinned voyage, and leaves the rest of the chain alone:
//   * standing orders are LIT (`raid_orders_enabled`), so the fleet page draws the picker;
//   * when the house's fleet is given an order through the real door (`cmd.raid_order` writes `fleet_raid_orders`),
//     she DEPARTS on a 30-second passage back to the harbour she lies in (the real `voyage.depart`, so her order is
//     frozen on the segment by the real freeze) and the voyage's id is pinned;
//   * on that voyage alone the day's hazard is a raid, and the fight's ANSWER is the fixed one below (`voyage.fight`
//     answers it for the pinned voyage and is the chain's own body for every other). The real `voyage.settle` then
//     writes the day and the VOYAGE_REPORT from it, the real `world.ledger` serves it, and the client draws it.
//     What the engine really answers is proof 56's business; this fixture is for what the glass DRAWS.
//   * at the founding the house is given one OLD report (a fight with sentences and no log, as every report before
//     0353), so the spec can read an old event beside a new one.
// The fixed fight is a real one: scripts/ops/harness/combat-log/orders-scene.sql printed it (a barca under Flee against
// the worst sea's mid roll, away in round 6).

import type { Page } from '@playwright/test'
import { patchedWorldImage, serveWorldImage } from './worldImage.fixture'

export const RAID_VOYAGE = '00000000-0353-4000-8000-00000000fa57'

/** The fixed fight, as the log keeps it (shape v 1). */
export const RAID_LOG = {
  v: 1,
  order: 'FLEE',
  first: 'THEY',
  foe: { n: 'Şebek (xebec)', k: 1.42, crew: 50, hull: 751.2 },
  you: [['Gaivota', 400, 400, 8]],
  r: [
    [1, 'L', 0, 0, 0, 0, 1, 2, 0, 0, 400, 751.2, [], 0.06],
    [2, 'L', 0, 0, 0, 0, 1, 2, 0, 0, 400, 751.2, [], 0.06],
    [3, 'L', 0, 0, 0, 0, 1, 2, 0, 0, 400, 751.2, [], 0.06],
    [4, 'M', 0, 0, 0, 0, 1, 2, 0, 0, 400, 751.2, [], 0.06],
    [5, 'M', 0, 0, 0, 0, 1, 2, 0, 0, 400, 751.2, [], 0.06],
    [6, 'C', 0, 0, 0, 0, 1, 2, 2, 67.9, 332.1, 751.2, [[1, 17]], 0.06],
  ],
  end: 'FLED',
  after: [['Gaivota', 332.11]],
} as const

export const RAID_ROUNDS = [
  'Raiders: about 1 × Şebek (xebec), 50 crew.',
  'They saw you before your lookout saw them.',
  'You turn and run.',
  'Round 1 · long range — you run before them; they miss.',
  'Round 6 · close range — you run before them; they hit Gaivota for 17% damage (armour turned 2%).',
  'You get clear of them.',
]

/** The old report's sentences: a fight before 0353 kept these and nothing else. */
export const OLD_ROUNDS = [
  'Raiders: about 2 × Şebek (xebec), 81 crew.',
  'They saw you before your lookout saw them.',
  'Round 1 · long range — you are caught unready; they miss.',
  'Close quarters: they come alongside — your 8 crew against their 81. They board and take what they can carry.',
]

const q = (v: unknown) => `'${JSON.stringify(v).replace(/'/g, "''")}'::jsonb`

export function raidWorld(): Promise<Buffer> {
  return patchedWorldImage('raid-world', async (pg) => {
    await pg.exec(`
      update public.world_config set value = 'true'::jsonb where key in ('raid_orders_enabled', 'combat_bite');

      -- the pinned voyage's day is a raid; every other voyage rolls as the chain rolls
      alter function voyage.hazard_roll(uuid, integer) rename to hazard_roll_real_spec;
      create function voyage.hazard_roll(p_voyage uuid, p_day integer)
      returns table (occurred boolean, kind text, magnitude numeric, p_hazard numeric)
      language plpgsql stable security definer set search_path = public, pg_temp as $$
      begin
        if p_voyage = '${RAID_VOYAGE}'::uuid then
          return query select true, 'PIRATES'::text, 0.5::numeric, 1::numeric;
        else
          return query select * from voyage.hazard_roll_real_spec(p_voyage, p_day);
        end if;
      end $$;

      -- the pinned voyage's fight answers the fixed fight; every other is the chain's own body
      alter function voyage.fight(uuid, integer, uuid, numeric) rename to fight_real_spec;
      create function voyage.fight(p_voyage uuid, p_day integer, p_fleet uuid, p_raider numeric)
      returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
      begin
        if p_voyage <> '${RAID_VOYAGE}'::uuid then
          return voyage.fight_real_spec(p_voyage, p_day, p_fleet, p_raider);
        end if;
        return jsonb_build_object(
          'outcome', 'EVADED', 'sentence', 'We ran, and got clear of them.', 'rounds', ${q(RAID_ROUNDS)},
          'hull_lost', (select jsonb_object_agg(s.id::text, 67.89) from public.ships s where s.fleet_id = p_fleet and s.is_flagship),
          'first', 'THEY', 'rounds_fought', 6,
          'raiders', jsonb_build_object('class', 'xebec', 'ships', 1.42, 'crew', 50, 'damaged_pct', 0),
          'hits', jsonb_build_object('yours', 0, 'theirs', 2), 'fled', true, 'log', ${q(RAID_LOG)});
      end $$;

      -- an order given through the door sends her on a 30-second passage back to her own harbour, the voyage pinned
      create function public.spec_raid_sail() returns trigger
      language plpgsql security definer set search_path = public, pg_temp as $$
      declare
        v_port uuid;
        v_lat  numeric;
        v_lon  numeric;
        v_voy  uuid;
      begin
        if exists (select 1 from public.voyages v where v.id = '${RAID_VOYAGE}'::uuid) then return null; end if;
        select f.port_id into v_port from public.fleets f where f.id = new.fleet_id and f.status = 'DOCKED';
        if v_port is null then return null; end if;
        select r.roadstead_lat, r.roadstead_lon into v_lat, v_lon from public.sea_reaches r where r.port_id = v_port limit 1;
        update public.fleets f set ready_at = null where f.id = new.fleet_id;
        v_voy := voyage.depart(new.fleet_id,
          jsonb_build_array(jsonb_build_object('a', jsonb_build_array(v_lat, v_lon), 'b', jsonb_build_array(v_lat, v_lon),
            'nm', voyage.fleet_speed(new.fleet_id) * 8, 'sea_id', (select p.sea_id from public.ports p where p.id = v_port), 'hazard_mult', 1)),
          v_port, v_port, now());
        update public.voyages set id = '${RAID_VOYAGE}'::uuid where id = v_voy;
        return null;
      end $$;
      create constraint trigger spec_raid_sail after insert on public.fleet_raid_orders
        deferrable initially deferred for each row execute function public.spec_raid_sail();

      -- the founding leaves one OLD report in her ledger (a fight in sentences, no log)
      create function public.spec_old_report() returns trigger
      language plpgsql security definer set search_path = public, pg_temp as $$
      begin
        if exists (select 1 from public.players p where p.id = new.player_id and p.is_npc) then return null; end if;
        perform public.emit_event(new.player_id, 'VOYAGE_REPORT', jsonb_build_object(
          'fleet', 'Gaivota', 'voyage_id', '00000000-0353-4000-8000-00000000fa58', 'from', 'LIS', 'to', 'FNC', 'total_nm', 520,
          'lines', jsonb_build_array('Day 1. A quiet watch; nothing to report.', 'Day 2. Sail sighted to windward. They came aboard and took what they could carry.'),
          'fights', jsonb_build_array(jsonb_build_object('line', 1, 'rounds', ${q(OLD_ROUNDS)}))));
        return null;
      end $$;
      create trigger spec_old_report after insert on public.ships
        for each row when (new.is_flagship) execute function public.spec_old_report();
    `)
  })
}

/** Serve the raid world to `page` in place of the shipped image. */
export async function serveRaidWorld(page: Page): Promise<void> {
  await serveWorldImage(page, await raidWorld())
}
