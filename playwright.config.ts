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
    screenshot: 'on',
    trace: 'on',
    video: 'retain-on-failure',
  },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
})
