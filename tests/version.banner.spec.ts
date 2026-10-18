import { test, expect, type Page } from '@playwright/test'
import { mkdirSync } from 'node:fs'
import path from 'node:path'
import { PHONE, reachable } from './appReady.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE NEW-VERSION BANNER (2026-10-19) — a stale tab learns that a newer build is live
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner kept a tab open across deploys, played an old build, and reported a defect that was
// already fixed. So every build is stamped with an id (vite.config.ts, `byeharu:build-version`),
// written into the bundle and into `version.json` beside index.html, and the running tab
// (src/app/NewVersionToast.tsx, through src/lib/version.ts) compares the two on focus, on
// visibilitychange and every five minutes. This spec drives the seam the brief names:
//
//   * the served build publishes version.json, and the bundle it serves AGREES with it — so a
//     fresh tab, asked to check, shows nothing (the contract's quiet half);
//   * version.json is then swapped to a different id (served B while the tab runs A), focus is
//     triggered, and the banner appears: fixed, in a corner, moving nothing on the page;
//   * tapping it reloads the page; the ✕ dismisses it for the session and a reload keeps that
//     dismissal — while a THIRD id brings it back;
//   * a check that fails (the network, a 404 mid-deploy) shows nothing and throws nothing;
//   * every check busts both caches: `?t=` on the URL (GitHub Pages serves with max-age=600).
//
// WHERE: `/ui`, the gallery — outside RequireAuth and the world, so the spec pays no chain and
// does not skip on a cloud build; the toast is mounted in App.tsx over every route, so what is
// proven here holds on every tab. `ready()` is not used: there is no world to wait for.
//
// Screenshots at DPR 2 (1440×731 and 390×844) land in docs/dev-log/2026-10-19-new-version-banner/.
// Run it: npm run build && npx vite preview --port 4370, then
//   PLAYWRIGHT_BASE_URL=http://localhost:4370/byeharu-voyage/ npx playwright test version.banner
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const SHOTS = path.join(process.cwd(), 'docs', 'dev-log', '2026-10-19-new-version-banner')
const WIDE = { width: 1440, height: 731 }
const BANNER = '[data-testid="new-version"]'
const WORDS = 'New version — tap to refresh'
/** `<7-char commit>+<ISO time>` — the shape vite.config.ts stamps. */
const ID_SHAPE = /^[0-9a-f]{7}\+\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/

async function openGallery(page: Page, request: Parameters<typeof reachable>[0], baseURL: string | undefined) {
  test.skip(
    !(await reachable(request, baseURL ?? '')),
    `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`,
  )
  await page.goto('ui')
  await page.waitForSelector('[data-testid="gallery"]', { timeout: 30_000 })
}

/** The player comes back to the tab: one focus event, and the check it provokes has answered. */
async function comeBack(page: Page) {
  // The REQUEST, then its outcome: `Request.response()` resolves to null when the request failed
  // (an aborted route has no response for `waitForResponse` to see — it would wait forever).
  const asked = page.waitForRequest((r) => /\/version\.json\?t=\d+$/.test(r.url()))
  await page.evaluate(() => window.dispatchEvent(new Event('focus')))
  await (await asked).response()
  // One frame for React to draw what the answer decided.
  await page.waitForTimeout(100)
}

/** Serve `id` as the published build from here on. */
async function publish(page: Page, id: string) {
  await page.route(/\/version\.json(\?|$)/, (route) =>
    route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ id }) }),
  )
}

test.describe('phone', () => {
  test.use({ viewport: PHONE, deviceScaleFactor: 2 })

  test('the build publishes version.json, and a tab running that build shows nothing', async ({
    page,
    request,
    baseURL,
  }) => {
    await openGallery(page, request, baseURL)
    const res = await request.get(`${baseURL}version.json?t=${Date.now()}`)
    expect(res.ok(), 'version.json is served beside index.html').toBe(true)
    const { id } = (await res.json()) as { id: string }
    expect(id, 'the id is <commit>+<build time>').toMatch(ID_SHAPE)

    const errors: string[] = []
    page.on('pageerror', (e) => errors.push(e.message))
    await comeBack(page)
    await expect(page.locator(BANNER), 'the running build is the published one').toHaveCount(0)
    expect(errors).toEqual([])
  })

  test('the check busts both caches: a fresh ?t= on every ask', async ({ page, request, baseURL }) => {
    await openGallery(page, request, baseURL)
    const urls: string[] = []
    page.on('request', (r) => {
      if (r.url().includes('version.json')) urls.push(r.url())
    })
    await comeBack(page)
    await page.waitForTimeout(5)
    await comeBack(page)
    expect(urls.length, 'each focus asks once').toBe(2)
    for (const u of urls) expect(u, 'a distinct URL per ask, past the CDN').toMatch(/\/version\.json\?t=\d+$/)
    expect(urls[0]).not.toBe(urls[1])
  })

  test('a newer build shows the banner on focus, in a corner, moving nothing; a tap reloads', async ({
    page,
    request,
    baseURL,
  }) => {
    await openGallery(page, request, baseURL)
    const before = await page.evaluate(() =>
      [...document.querySelectorAll('[data-testid="gallery"] *')].slice(0, 40).map((el) => {
        const r = el.getBoundingClientRect()
        return [Math.round(r.top), Math.round(r.left), Math.round(r.width)].join(',')
      }),
    )

    await publish(page, 'b000000+2099-01-01T00:00:00.000Z')
    await comeBack(page)
    const banner = page.locator(BANNER)
    await expect(banner).toBeVisible()
    await expect(banner).toContainText(WORDS)

    // Fixed, in the top-right corner, and nothing on the page moved for it.
    const box = await banner.evaluate((el) => {
      const r = el.getBoundingClientRect()
      return { position: getComputedStyle(el).position, right: innerWidth - r.right, top: r.top, h: r.height, w: r.width }
    })
    expect(box.position).toBe('fixed')
    expect(box.right).toBeLessThanOrEqual(16)
    expect(box.top).toBeLessThanOrEqual(48)
    expect(box.h, 'a 44px target').toBeGreaterThanOrEqual(44)
    expect(box.w).toBeLessThan(PHONE.width)
    const after = await page.evaluate(() =>
      [...document.querySelectorAll('[data-testid="gallery"] *')].slice(0, 40).map((el) => {
        const r = el.getBoundingClientRect()
        return [Math.round(r.top), Math.round(r.left), Math.round(r.width)].join(',')
      }),
    )
    expect(after, 'the banner reflowed nothing').toEqual(before)

    mkdirSync(SHOTS, { recursive: true })
    await page.screenshot({ path: path.join(SHOTS, `banner-${PHONE.width}.png`) })

    // Tapping reloads: a marker set on the old document is gone from the new one.
    await page.evaluate(() => {
      ;(window as unknown as { __stale: number }).__stale = 1
    })
    const reloaded = page.waitForEvent('load')
    await banner.getByRole('button', { name: WORDS }).click()
    await reloaded
    expect(await page.evaluate(() => (window as unknown as { __stale?: number }).__stale)).toBeUndefined()
  })

  test('the ✕ dismisses it for the session — a reload keeps that, a third build brings it back', async ({
    page,
    request,
    baseURL,
  }) => {
    await openGallery(page, request, baseURL)
    await publish(page, 'b000000+2099-01-01T00:00:00.000Z')
    await comeBack(page)
    const banner = page.locator(BANNER)
    await expect(banner).toBeVisible()
    await banner.getByRole('button', { name: 'Dismiss' }).click()
    await expect(banner).toHaveCount(0)

    // Asked again, same answer: still dismissed.
    await comeBack(page)
    await expect(banner).toHaveCount(0)

    // Reloaded (sessionStorage survives), still dismissed.
    await page.reload()
    await page.waitForSelector('[data-testid="gallery"]')
    await comeBack(page)
    await expect(banner).toHaveCount(0)

    // A build newer than the one dismissed is news again.
    await page.unroute(/\/version\.json(\?|$)/)
    await publish(page, 'c000000+2099-02-01T00:00:00.000Z')
    await comeBack(page)
    await expect(banner).toBeVisible()
  })

  test('a failed check shows nothing and throws nothing', async ({ page, request, baseURL }) => {
    await openGallery(page, request, baseURL)
    const errors: string[] = []
    page.on('pageerror', (e) => errors.push(e.message))
    page.on('console', (m) => {
      // Chromium itself logs `Failed to load resource: …` for EVERY failed fetch, before the page
      // ever sees the result; no app can silence it, and it is not the app's error. What is
      // counted here is what the APP did about the failure: a thrown error, or a console.error.
      if (m.type() === 'error' && !/^Failed to load resource/.test(m.text())) errors.push(m.text())
    })

    // Offline.
    await page.route(/\/version\.json(\?|$)/, (route) => route.abort('failed'))
    await comeBack(page)
    await expect(page.locator(BANNER)).toHaveCount(0)

    // A 404 while a deploy is mid-flight.
    await page.unroute(/\/version\.json(\?|$)/)
    await page.route(/\/version\.json(\?|$)/, (route) => route.fulfill({ status: 404, body: 'not here' }))
    await comeBack(page)
    await expect(page.locator(BANNER)).toHaveCount(0)

    // A body that is not the file.
    await page.unroute(/\/version\.json(\?|$)/)
    await page.route(/\/version\.json(\?|$)/, (route) =>
      route.fulfill({ status: 200, contentType: 'text/html', body: '<html>maintenance</html>' }),
    )
    await comeBack(page)
    await expect(page.locator(BANNER)).toHaveCount(0)

    expect(errors, 'no error reached the console or the page').toEqual([])
  })
})

test.describe('wide', () => {
  test.use({ viewport: WIDE, deviceScaleFactor: 2 })

  test('the banner at 1440×731 — a corner glass, visibilitychange brings it too', async ({
    page,
    request,
    baseURL,
  }) => {
    await openGallery(page, request, baseURL)
    await publish(page, 'b000000+2099-01-01T00:00:00.000Z')
    // The other trigger: the tab becoming visible again.
    const answered = page.waitForResponse((r) => /\/version\.json\?t=\d+$/.test(r.url()))
    await page.evaluate(() => document.dispatchEvent(new Event('visibilitychange')))
    await answered
    const banner = page.locator(BANNER)
    await expect(banner).toBeVisible()
    const box = await banner.evaluate((el) => {
      const r = el.getBoundingClientRect()
      return { right: innerWidth - r.right, top: r.top }
    })
    expect(box.right).toBeLessThanOrEqual(16)
    expect(box.top).toBeLessThanOrEqual(48)
    mkdirSync(SHOTS, { recursive: true })
    await page.screenshot({ path: path.join(SHOTS, `banner-${WIDE.width}.png`) })
  })
})
