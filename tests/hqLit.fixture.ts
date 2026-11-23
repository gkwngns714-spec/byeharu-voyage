import type { Page } from '@playwright/test'
import { patchedWorldImage, serveWorldImage } from './worldImage.fixture'

// A WORLD WITH THE SWITCHES PRODUCTION RUNS LIT (docs/design/playable-2026-11-22.md §6; the visual overhaul's audit world), for the
// HQ board's spec and shots (docs/design/hq-command-2026-11-23.md): the shipped image with each gameplay switch thrown and the sea
// conditions left dark, as production has them since 2026-11-23. A key the image does not carry is simply not changed.

const LIT = [
  'raid_companies_enabled',
  'yard_order_enabled',
  'hold_requests_enabled',
  'houses_board_enabled',
  'level_unlocks_enabled',
  'world_events_enabled',
  'pirate_bounties_enabled',
  'first_hour_enabled',
  'pirates_bite',
  'regard_enabled',
  'levels_bite',
  'standing_routes_enabled',
  'pirates_joinable',
  'land_enabled',
] as const

/** Serve the lit world to `page` in place of the shipped image. `served`: the HQ board from the server lit too (0480, hq_board_enabled).
 *  `jobs`: the standing fleet jobs lit too (0481, fleet_jobs_enabled). `contracts`: courier contracts lit (0483, contracts_enabled, with
 *  the stored courses), and one house contract posted from Lisbon to the nearest harbour 150 miles or more away that trades its good. */
export async function serveHqLit(
  page: Page,
  { served = false, jobs = false, contracts = false }: { served?: boolean; jobs?: boolean; contracts?: boolean } = {},
): Promise<void> {
  const keys = [
    ...LIT,
    ...(served ? ['hq_board_enabled'] : []),
    ...(jobs ? ['fleet_jobs_enabled'] : []),
    ...(contracts ? ['contracts_enabled', 'sea_courses_enabled'] : []),
  ]
  await serveWorldImage(
    page,
    await patchedWorldImage(contracts ? 'hq-contracts' : jobs ? 'hq-jobs' : served ? 'hq-served' : 'hq-lit', async (pg) => {
      await pg.exec(`update public.world_config set value = 'true'::jsonb where key in (${keys.map((k) => `'${k}'`).join(', ')})`)
      await pg.exec(`update public.world_config set value = 'false'::jsonb where key = 'sea_conditions_bite'`)
      if (contracts) await pg.exec(POST_ONE_CONTRACT)
    }),
  )
}

/** 0483: one house contract from Lisbon (the lightest good it offers, 10 units, reward 800, collateral 1,000, two hours to deliver), open
 *  for a month, posted by the richest house through the one writer (public.courier_post). */
const POST_ONE_CONTRACT = `
  with lis as (select p.id from public.ports p where p.code = 'LIS'),
       g as (select g.id from lis cross join public.port_offered_goods(lis.id) o join public.goods g on g.id = o.good_id
               join public.port_goods pg on pg.port_id = lis.id and pg.good_id = g.id where g.bulk > 0 order by g.bulk, g.code limit 1),
       b as (select r.port_id from lis cross join voyage.reach_from(lis.id) r join public.ports p on p.id = r.port_id and p.kind = 'HARBOUR'
               join public.port_goods pg on pg.port_id = r.port_id and pg.good_id = (select g.id from g)
              where r.nm >= 150 and public.sea_course(lis.id, r.port_id) is not null order by r.nm, r.code limit 1),
       h as (select h.player_id from public.npc_houses h join public.players p on p.id = h.player_id order by p.ducats desc, h.roster_ord limit 1),
       c as (select public.courier_post('house', (select h.player_id from h), (select lis.id from lis), (select b.port_id from b), (select g.id from g),
                                        10, 800, 1000, 7200, now()) as id)
  update public.courier_contracts x set expires_at = now() + interval '30 days' from c where x.id = c.id`
