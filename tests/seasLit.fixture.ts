import type { Page } from '@playwright/test'
import { patchedWorldImage, serveWorldImage } from './worldImage.fixture'

// A WORLD WHOSE SEA CONDITIONS BITE (docs/SEA_CONDITIONS_AND_REGIONS.md section 10), for the specs that drive the
// closed seas: the shipped world with ONE switch thrown, `sea_conditions_bite`. Nothing else is patched: the founding
// company is the real one (title 1, one barca at Lisbon, wave resistance 12), so Europe is open to her and every sea
// beyond it is closed by her title.

const LIGHT = `update public.world_config set value = 'true'::jsonb where key = 'sea_conditions_bite'`

/** Serve the lit world to `page` in place of the shipped image. */
export async function serveLitSeas(page: Page): Promise<void> {
  await serveWorldImage(
    page,
    await patchedWorldImage('seas-lit', async (pg) => {
      await pg.exec(LIGHT)
    }),
  )
}
