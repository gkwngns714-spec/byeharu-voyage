/// <reference types="node" />
// Node globals are granted to THIS FILE, not to the whole test project: tsconfig.test.json keeps
// `types: ["vite/client"]` so a spec is held to exactly the same rules as the source it imports.
// A config file that genuinely needs `process` asks for it here, where the need is.
import { defineConfig, devices } from '@playwright/test'

// Browser acceptance — runs against a local preview by default; point it at the deployed Pages
// site (or any build) with PLAYWRIGHT_BASE_URL. Test infrastructure only: no game code imports it.
const BASE = process.env.PLAYWRIGHT_BASE_URL || 'http://127.0.0.1:4173/byeharu-voyage/'

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
