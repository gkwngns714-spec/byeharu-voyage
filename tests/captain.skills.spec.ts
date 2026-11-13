import { test, expect, type Locator, type Page } from '@playwright/test'
import { reachable, ready } from './appReady.fixture'
import { readTray, trayViolations } from './trayLaw.fixture'
import { SKILL_CAPTAIN, SKILL_REPUTATION, serveCaptainSkillsWorld } from './captainSkills.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// CAPTAIN SKILLS ON THE GLASS — a step of a skill, bought with Reputation (migration 0355, slice R2 of docs/REPUTATION.md; owner row 317)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// A real B navigator is seated through the game's own doors and the company holds 260 Reputation (tests/captainSkills.fixture.ts: nothing is stubbed). Her card
// on the You tab carries the block "Captain skills" / "선장 스킬", one row a skill she knows, in the design's text:
//
//   Navigator · 2 / 5 · +8 %          [ Upgrade · 300 ]
//   항해사 · 2 / 5 · +8 %             [ 강화 · 300 ]
//
// The spec presses Upgrade twice and holds every figure to a fixed fact, all of them served:
//   · the row goes 0 / 5 · +0 % -> 1 / 5 · +4 % -> 2 / 5 · +8 %, and the button 50 -> 150 -> 300;
//   · the company's Reputation goes 260 -> 210 -> 60 (the block's own served figure, and the top bar's);
//   · her speed line on the SAME card (the sheet's Seamanship parts, public.crew_terms through world.captain_stats) goes +6.5% -> +6.8% -> +7%
//     (6.5, 6.76, 7.02 as the server words a part):
//     the step is one term, read by every reader;
//   · at 60 the third step (300) cannot be bought: the button is greyed and the server's own reason stands under it, with its figures;
//   · the card's old heading "Traits" now reads "Skills · 2 / 3" / "스킬 · 2 / 3";
//   · History says what was bought, and no gold moved;
//   · the tray's width law holds with the rows in it, and nothing is cut with an ellipsis.
// Phone (390) and desk (1280), English and Korean, headless.
//
// Run it: npm run build && npx vite preview --port 47355 --strictPort, then PLAYWRIGHT_BASE_URL=http://localhost:47355/byeharu-voyage/ npx playwright test captain.skills.spec.ts

const SIZES = [
  { width: 320, height: 568 },
  { width: 390, height: 844 },
  { width: 1280, height: 800 },
] as const

const WORDS = {
  en: {
    heading: 'Captain skills',
    uses: 'Skills · 2 / 3',
    row: (rank: number, pct: number) => `Navigator · ${rank} / ${SKILL_CAPTAIN.max} · +${pct} %`,
    pilot: `Pilot · 0 / ${SKILL_CAPTAIN.max} · +0 %`,
    button: (cost: number) => `Upgrade · ${cost}`,
    why: 'Needs 300 Reputation: you have 60.',
    history: `${SKILL_CAPTAIN.name}: Navigator 2 · 150 Reputation.`,
  },
  ko: {
    heading: '선장 스킬',
    uses: '스킬 · 2 / 3',
    row: (rank: number, pct: number) => `항해사 · ${rank} / ${SKILL_CAPTAIN.max} · +${pct} %`,
    pilot: `도선사 · 0 / ${SKILL_CAPTAIN.max} · +0 %`,
    button: (cost: number) => `강화 · ${cost}`,
    why: '평판 부족. (60 / 300 평판)',
    history: `${SKILL_CAPTAIN.name}: 항해사 2 · 평판 150.`,
  },
} as const

const text = async (l: Locator) => (await l.innerText()).replace(/\s+/g, ' ').trim()

/** The skill row of `trait` inside her tray: its label cell, its button and the reason under it. */
function skillRow(tray: Locator, trait: string) {
  const row = tray.getByTestId(`captain-skill-${trait}`)
  return { row, label: row.locator('[data-row-cell="label"]'), button: tray.getByTestId(`captain-skill-up-${trait}`), why: tray.getByTestId(`captain-skill-why-${trait}`) }
}

/** Nothing in the block is cut: no cell clips its text, and no text ends in an ellipsis. */
async function nothingCut(page: Page) {
  return page.evaluate(() => {
    const block = document.querySelector('[data-testid="captain-skills"]')!
    const cut: string[] = []
    for (const el of [...block.querySelectorAll('[data-row-cell], button, h4, [data-testid^="captain-skill-why-"]')] as HTMLElement[]) {
      const t = (el.textContent ?? '').trim()
      if (el.scrollWidth > el.clientWidth + 1) cut.push(`clipped: ${t}`)
      if (/(…|\.\.\.)$/.test(t)) cut.push(`ellipsis: ${t}`)
    }
    return cut
  })
}

for (const size of SIZES) {
  for (const lang of ['en', 'ko'] as const) {
    test.describe(`captain skills at ${size.width}×${size.height}, ${lang}`, () => {
      test.use({ viewport: size, locale: lang === 'ko' ? 'ko-KR' : 'en-US' })

      test('two steps are bought with Reputation, the third is greyed with the server’s reason', async ({ page, request, baseURL }) => {
        test.setTimeout(600_000)
        expect(await reachable(request, baseURL ?? ''), `nothing served at ${baseURL}: run a preview (or set PLAYWRIGHT_BASE_URL)`).toBe(true)
        const words = WORDS[lang]
        await serveCaptainSkillsWorld(page)
        await page.goto('you')
        await ready(page)
        expect(await page.evaluate(() => document.documentElement.lang)).toBe(lang)
        await expect(page.getByTestId('your-captain')).toHaveCount(1, { timeout: 120_000 })
        await page.getByTestId('your-captain').click()
        const tray = page.getByTestId('your-captain-tray')
        await expect(tray).toBeVisible()
        const block = tray.getByTestId('captain-skills')
        const nav = skillRow(tray, 'NAVIGATOR')
        await expect(nav.row, 'her skills did not land').toBeVisible({ timeout: 60_000 })

        // THE BLOCK: its heading, one row a skill she knows, in her kit's order; the card's own list is headed "Skills" now
        await expect(block.locator('h4')).toHaveText(words.heading)
        const ids = await block.locator('[data-testid^="captain-skill-"][data-row-line]').evaluateAll((els) => els.map((e) => e.getAttribute('data-testid')))
        expect(ids).toEqual(SKILL_CAPTAIN.known.map((t) => `captain-skill-${t}`))
        await expect(tray.locator('h4', { hasText: words.uses })).toHaveCount(1)
        const speed = tray.getByTestId('captain-stat-seamanship-parts')

        // STEP BY STEP: the row, the button, the Reputation left and her speed line on the same card
        for (const step of [0, 1, 2] as const) {
          if (step > 0) {
            await expect(nav.button).toBeEnabled()
            await nav.button.click()
          }
          await expect(nav.label).toHaveText(words.row(step, step * 4), { timeout: 30_000 })
          await expect(nav.button).toHaveText(words.button(SKILL_REPUTATION.costs[step]))
          await expect(nav.row).toHaveAttribute('data-rank', String(step))
          await expect(nav.row).toHaveAttribute('data-max', String(SKILL_CAPTAIN.max))
          await expect(block).toHaveAttribute('data-reputation', String(SKILL_REPUTATION.after[step]))
          await expect(page.getByTestId('reputation'), 'the top bar reads the same balance').toHaveAttribute('data-value', String(SKILL_REPUTATION.after[step]), { timeout: 30_000 })
          await expect(speed, `her speed line at step ${step}`).toContainText(SKILL_CAPTAIN.speed[step], { timeout: 30_000 })
        }

        // 60 LEFT, 300 ASKED: greyed, with the server's reason and its figures under the button
        await expect(nav.button).toBeDisabled()
        await expect(nav.row).toHaveAttribute('data-can', 'false')
        await expect(nav.why).toHaveText(words.why)
        expect((await nav.why.boundingBox())!.y, 'the reason stands under the button').toBeGreaterThanOrEqual((await nav.button.boundingBox())!.y + (await nav.button.boundingBox())!.height - 1)
        // a skill she has not raised: still pressable (50 <= 60), and its row is whole
        const pilot = skillRow(tray, 'PILOT')
        await expect(pilot.label).toHaveText(words.pilot)
        await expect(pilot.button).toBeEnabled()
        await expect(pilot.button).toHaveText(words.button(50))
        await expect(pilot.why).toHaveCount(0)
        await expect(tray.getByTestId('captain-skill-refused'), 'no press was refused').toHaveCount(0)

        // THE GLASS: the tray's width law with the rows in it, every button inside the tray, nothing cut
        const read = await readTray(page, 'your-captain-tray')
        const broken = trayViolations(read, `${size.width}×${size.height} ${lang}`, (r) => !/^captain-(trait|level|stat)-/.test(r.id))
        expect(broken, broken.join('\n')).toEqual([])
        expect(read.rows.filter((r) => r.id.startsWith('captain-skill-')).length).toBe(SKILL_CAPTAIN.known.length)
        const box = (await tray.boundingBox())!
        for (const trait of SKILL_CAPTAIN.known) {
          const b = (await skillRow(tray, trait).button.boundingBox())!
          expect(b.x, `${trait}: the button starts inside the tray`).toBeGreaterThanOrEqual(box.x)
          expect(b.x + b.width, `${trait}: the button ends inside the tray`).toBeLessThanOrEqual(box.x + box.width + 0.5)
          expect(b.height, `${trait}: the button is a finger tall`).toBeGreaterThanOrEqual(44)
        }
        expect(await nothingCut(page)).toEqual([])
        const rowText = `${await text(nav.label)} [ ${await text(nav.button)} ] ${await text(nav.why)}`
        // the picture for the PR, only when asked for: CAPTAIN_SKILLS_SHOTS=<folder>
        if (process.env.CAPTAIN_SKILLS_SHOTS) {
          await nav.row.scrollIntoViewIfNeeded()
          await page.screenshot({ path: `${process.env.CAPTAIN_SKILLS_SHOTS}/captain-skills-${size.width}-${lang}.png` })
        }

        // HISTORY says what was bought; the steps moved no gold
        await tray.getByTestId('tray-close').click()
        await expect(tray).toHaveCount(0)
        // by the Menu, not by a reload: the steps live in this tab's own world
        await page.locator('[data-testid="nav-bar"] > button').first().click()
        await page.getByTestId('nav-group-panel').locator('a[href$="/ledger"]').click()
        await expect(page.getByTestId('ledger-row').filter({ hasText: words.history }), 'History does not say the second step').toHaveCount(1, { timeout: 60_000 })
        console.log(`captain skills ${size.width} ${lang}: ${rowText} · speed ${SKILL_CAPTAIN.speed.join(' -> ')} · Reputation ${SKILL_REPUTATION.after.join(' -> ')}`)
      })
    })
  }
}
