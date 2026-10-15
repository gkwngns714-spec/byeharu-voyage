// Run by playwright.npc-on.config.ts only (acceptance.yml's `npc-on-world` job): build the
// merchants-on world ONCE, through the fixture's own code and every one of its own checks, and
// leave it in node_modules/.cache/byeharu-npc-on for the shards. Not a spec — it asserts nothing
// the fixture does not already assert, and it is never in `playwright test --list`.
import { test } from '@playwright/test'
import { npcOn } from './npcOn.fixture'

test('build the merchants-on world once for the shards', async () => {
  test.setTimeout(60 * 60_000)
  const image = await npcOn()
  console.log(`merchants-on world: ${image.length} bytes`)
})
