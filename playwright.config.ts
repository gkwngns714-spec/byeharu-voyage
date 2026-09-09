/// <reference types="node" />
// Node globals are granted to THIS FILE, not to the whole test project: tsconfig.test.json keeps
// `types: ["vite/client"]` so a spec is held to exactly the same rules as the source it imports.
// A config file that genuinely needs `process` asks for it here, where the need is.
import { defineConfig, devices } from '@playwright/test'

// Browser acceptance — runs against a local preview by default; point it at the deployed Pages
// site (or any build) with PLAYWRIGHT_BASE_URL. Test infrastructure only: no game code imports it.
// localhost, NOT the 127.0.0.1 literal: `vite preview` binds the IPv6 loopback [::1] only, so the
// v4 address answers 000 and Playwright SILENTLY SKIPS every browser spec — a green with a
// shrunken denominator, which is worse than a red. Cost three agents a wasted run on 2026-08-25.
const BASE = process.env.PLAYWRIGHT_BASE_URL || 'http://localhost:4173/byeharu-voyage/'

export default defineConfig({
  testDir: './tests',
  timeout: 120_000,
  expect: { timeout: 20_000 },
  retries: 0,
  reporter: [['list'], ['html', { open: 'never' }]],
  use: {
    baseURL: BASE,
    // THE SUITE MEASURES THE SKIN THE GAME ACTUALLY SHIPS. src/index.css carries two schemes since
    // 2026-09-09 and DARK IS THE DEFAULT; Playwright's own default is to emulate a LIGHT system
    // preference, which would have silently repointed every colour proof at the day palette —
    // tests/chart.ink.spec.ts would then measure a chart nobody sees first and report it as the
    // chart. Pinned here rather than per-spec so there is one answer. A spec that wants the day
    // sea overrides it with `test.use({ colorScheme: 'light' })`.
    colorScheme: 'dark',
    screenshot: 'on',
    trace: 'on',
    video: 'retain-on-failure',
  },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
})
