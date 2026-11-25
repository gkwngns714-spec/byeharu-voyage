import { test, expect, type Page } from '@playwright/test'
import { reachable, ready } from './appReady.fixture'
import { translate } from '../src/lib/i18n'

// A COMPANY TAKES A NEW NAME, ON THE GLASS (0503; the owner's specification of 2026-11-25, plan slice A1). Profile, at a phone, a small
// phone and a laptop:
//   * the rename press stands beside the company's name, says the first is free, is at least 44 px each way and inside the glass,
//     and the name beside it is whole (never cut);
//   * the press opens a page OVER Profile: nothing on Profile moves (the pages-stand-still law), and the page's own controls are 44 px;
//   * a name with a special character, a country's name and a place's name are refused with the server's own sentence, printed;
//   * a good name is saved: Profile prints it, the press now says only Rename, and the card under the name has not moved;
//   * the next press says, in plain words, that another rename is not available yet, and offers no field.
// The founding step's field is read in the gates gallery (the local world founds its own house, so that door is proven in
// tests/rpc.companyName.spec.ts and proof 205): it stops at 24 characters and prints the rule in one line.

const GLASSES = [
  { width: 390, height: 844 },
  { width: 320, height: 640 },
  { width: 1440, height: 900 },
] as const

const box = (page: Page, sel: string) =>
  page.evaluate((s) => {
    const r = document.querySelector(s)?.getBoundingClientRect()
    return r ? { x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width), h: Math.round(r.height) } : null
  }, sel)

const BEHIND = ['[data-testid="house-line"]', '[data-testid="country"]', '[data-testid="profile-language"]', '[data-testid="sign-out"]']

for (const glass of GLASSES) {
  test(`Profile at ${glass.width}×${glass.height}: one free rename beside the name, refused names said plainly, the next rename not available yet`, async ({ page, request, baseURL }) => {
    test.setTimeout(600_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
    await page.setViewportSize(glass)
    await page.goto('profile')
    await ready(page)

    // the press, beside the name
    const press = page.getByTestId('company-rename')
    await expect(press).toBeVisible({ timeout: 120_000 })
    await expect(press).toHaveText(translate('en', 'profile.renameFree'))
    expect(await page.getByTestId('house-line').locator('[data-testid="company-rename"]').count(), 'the press stands in the company line').toBe(1)
    const pb = await box(page, '[data-testid="company-rename"]')
    expect(pb && pb.h >= 44 && pb.w >= 44, `the press is under 44 px: ${JSON.stringify(pb)}`).toBe(true)
    expect(pb && pb.x >= 0 && pb.x + pb.w <= glass.width, `the press runs off the glass: ${JSON.stringify(pb)}`).toBe(true)
    const name0 = (await page.getByTestId('house-line').locator('h2').innerText()).trim()
    const cut = await page.evaluate(() => {
      const h = document.querySelector('[data-testid="house-line"] h2') as HTMLElement
      return h.scrollWidth > h.clientWidth + 1
    })
    expect(cut, 'the company name is cut').toBe(false)
    expect(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth + 1), 'Profile scrolls sideways').toBe(false)
    await page.screenshot({ path: `test-results/company-name/profile-free-${glass.width}.png` })

    // the page opens OVER Profile: nothing behind it moves
    const before = await Promise.all(BEHIND.map((s) => box(page, s)))
    await press.click()
    const sheet = page.getByTestId('company-rename-page')
    await expect(sheet).toBeVisible()
    expect(await Promise.all(BEHIND.map((s) => box(page, s))), 'Profile moved when the rename page opened').toEqual(before)
    const field = page.getByTestId('company-rename-name')
    await expect(field).toHaveValue(name0)
    await expect(field).toHaveAttribute('maxlength', '24')
    const save = page.getByTestId('company-rename-save')
    await expect(save).toBeDisabled() // her own name again is no rename
    for (const sel of ['[data-testid="company-rename-save"]']) {
      const b = await box(page, sel)
      expect(b && b.h >= 44, `${sel} is under 44 px: ${JSON.stringify(b)}`).toBe(true)
    }
    await expect(sheet).toContainText(translate('en', 'profile.renameOnce'))

    // refused names: the server's own sentence, printed; the page stays, nothing is renamed
    for (const [typed, said] of [
      ['A*B', 'No special characters'],
      ['Portugal', 'country'],
      ['LISBON', 'place'],
    ] as const) {
      await field.fill(typed)
      await save.click()
      await expect(sheet.getByText(said, { exact: false }).first()).toBeVisible({ timeout: 60_000 })
      await expect(sheet).toBeVisible()
    }
    await page.screenshot({ path: `test-results/company-name/rename-refused-${glass.width}.png` })

    // a good name: saved, the page closes, Profile prints it, and the card under the name has not moved
    const next = `Casa Nova ${glass.width}`
    await field.fill(`  ${next} `)
    await save.click()
    await expect(sheet).toBeHidden({ timeout: 60_000 })
    await expect(page.getByTestId('house-line').locator('h2')).toHaveText(next, { timeout: 60_000 })
    await expect(press).toHaveText(translate('en', 'profile.rename'))
    const after = await Promise.all(BEHIND.slice(1).map((s) => box(page, s)))
    expect(after, 'a card under the company line moved when the name was saved').toEqual(before.slice(1))
    const pb2 = await box(page, '[data-testid="company-rename"]')
    expect(pb2 && pb2.h >= 44 && pb2.w >= 44, `the press is under 44 px after the rename: ${JSON.stringify(pb2)}`).toBe(true)
    await page.screenshot({ path: `test-results/company-name/profile-renamed-${glass.width}.png` })

    // the next rename: said in plain words, no field, no price
    await press.click()
    await expect(page.getByTestId('company-rename-used')).toHaveText(translate('en', 'profile.renameUsed'))
    await expect(page.getByTestId('company-rename-name')).toHaveCount(0)
    await expect(page.getByTestId('company-rename-save')).toHaveCount(0)
    await page.screenshot({ path: `test-results/company-name/rename-used-${glass.width}.png` })
    await page.keyboard.press('Escape')
    await expect(page.getByTestId('company-rename-page')).toBeHidden()
    await expect(page.getByTestId('house-line').locator('h2')).toHaveText(next)
  })
}

test('the founding step: the name field stops at 24 characters and the rule is printed in one line', async ({ page, request, baseURL }) => {
  test.setTimeout(600_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await page.setViewportSize({ width: 390, height: 844 })
  await page.goto('ui/gates/found')
  await ready(page)
  const field = page.locator('#house-name')
  await expect(field).toBeVisible({ timeout: 120_000 })
  await expect(field).toHaveAttribute('maxlength', '24')
  await expect(page.getByTestId('found-form')).toContainText(translate('en', 'found.nameRule'))
  await field.fill('A'.repeat(40))
  expect((await field.inputValue()).length).toBe(24)
  const fb = await box(page, '#house-name')
  expect(fb && fb.h >= 44, `the name field is under 44 px: ${JSON.stringify(fb)}`).toBe(true)
  await page.screenshot({ path: 'test-results/company-name/found-390.png' })
})
