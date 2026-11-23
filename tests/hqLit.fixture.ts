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
 *  `jobs`: the standing fleet jobs lit too (0481, fleet_jobs_enabled). */
export async function serveHqLit(page: Page, { served = false, jobs = false }: { served?: boolean; jobs?: boolean } = {}): Promise<void> {
  const keys = [...LIT, ...(served ? ['hq_board_enabled'] : []), ...(jobs ? ['fleet_jobs_enabled'] : [])]
  await serveWorldImage(
    page,
    await patchedWorldImage(jobs ? 'hq-jobs' : served ? 'hq-served' : 'hq-lit', async (pg) => {
      await pg.exec(`update public.world_config set value = 'true'::jsonb where key in (${keys.map((k) => `'${k}'`).join(', ')})`)
      await pg.exec(`update public.world_config set value = 'false'::jsonb where key = 'sea_conditions_bite'`)
    }),
  )
}
