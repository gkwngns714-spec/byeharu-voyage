/// <reference types="node" />
// THE MERCHANTS-ON WORLD, BUILT ONCE PER CI RUN (2026-10-15) — not a spec, a warm-up.
//
// tests/npcOn.fixture.ts builds the merchants-on world in Node and keeps it on disk under
// node_modules/.cache/byeharu-npc-on. On CI every shard used to build it for itself, and with two
// workers per shard both workers built it at once: measured on run 38689111316 the first test to
// ask paid 14-33 minutes, on several runners in parallel, for the same world. acceptance.yml's
// `npc-on-world` job now runs THIS config once and hands the kept file to every shard, where
// `npcOn()` finds it on disk exactly as it does on a developer's second run.
//
// Its own config so the warm-up is never a test: playwright.config.ts's default testMatch does not
// match tests/npcOn.warm.ts, so `playwright test --list` (the verdict's denominator) never counts it.
import { defineConfig } from '@playwright/test'
import base from './playwright.config'

export default defineConfig({
  ...base,
  testMatch: 'npcOn.warm.ts',
  workers: 1,
  reporter: [['list']],
})
