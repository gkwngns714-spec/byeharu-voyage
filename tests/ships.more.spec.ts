import { test, expect, type Page } from '@playwright/test'
import { readFileSync } from 'node:fs'
import path from 'node:path'
import { reachable, ready } from './appReady.fixture'
import { KO_HULLS } from '../src/lib/i18n/names/realms'
import { HULL_JOBS, HULL_JOB_CODES } from '../src/live/hullJobs.generated'
import { JOB_WORD } from '../src/live/hullJobWord'
import { translate } from '../src/lib/i18n'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// MORE SHIPS (migration 0366, owner row 322: "i need more trade ships, cargo, and especially combat related ships")
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// THE FILES AGREE (plain Node): Wave E of data/ships.generated.json (the generator's) is what the migration loads, row for row; every
// one of its hulls has a Korean name that is whole; the faces' job table is the generator's; every job has its word in both languages;
// combat is the largest share, and every shipbuilding line gained a hull that fights and a hull that carries.
// THE FACES SHOW THEM (a browser, 390 and 320 px, English and Korean): the Codex lists the new hulls with their job, the Job picker
// narrows the list to one job, a hull's sheet says her job and the five figures the fight reads, the build yard offers the hulls of
// its own country with the same badge and the same figures, every name stands whole, and nothing scrolls sideways.
// Screenshots go to MORE_SHIPS_SHOTS when it names a folder (the builder's review), else to the run's own output.

interface Hull {
  wave: string; class: string; name: string; line: string; size: number; role: string; tech: string; job?: string | null
  family: string; rig: string; tier: number; hold: number; crewRequired: number; crewMax: number; speedKn: number; durability: number; guns: number
  draft: number; buildHours: number; buildCost: number; handling: number; armour: number; attack: number; accuracy: number; reach: number
  sighting: number; waveResistance: number; deck: number; cabins: number; yardTier: number; ducats: number; note: string
  goods: { in: string; qty: number }[]; requirements: { skill: string; level: number }[]; racks: Record<string, number>
}
const read = (rel: string) => readFileSync(path.resolve(rel), 'utf8')
const ALL = (JSON.parse(read('data/ships.generated.json')) as { hulls: Hull[] }).hulls
const NEW = ALL.filter((h) => h.wave === 'E')
const OLD = ALL.filter((h) => h.wave !== 'E')
const q = (s: string) => `'${s.replace(/'/g, "''")}'`

test('Wave E is 54 hulls, combat first, and every line gained a hull that fights and a hull that carries', () => {
  expect(NEW).toHaveLength(54)
  const by = (role: string) => NEW.filter((h) => h.role === role).length
  expect({ combat: by('combat'), support: by('support'), trade: by('trade') }).toEqual({ combat: 31, support: 4, trade: 19 })
  expect(by('combat') + by('support'), 'combat and escorts are not the larger share').toBeGreaterThan(by('trade'))
  const lines = [...new Set(OLD.map((h) => h.line))].sort()
  expect(lines).toHaveLength(11)
  for (const line of lines) {
    expect(NEW.some((h) => h.line === line && (h.role === 'combat' || h.role === 'support')), `${line} gained no hull that fights`).toBe(true)
    expect(NEW.some((h) => h.line === line && h.role === 'trade'), `${line} gained no hull that carries`).toBe(true)
  }
  // at least one armed trader and one very large slow carrier (the largest hold of any hull that is not a famous ship, and the slowest hull)
  expect(NEW.some((h) => h.job === 'armed')).toBe(true)
  const big = NEW.filter((h) => h.job === 'carrier').sort((a, b) => b.hold - a.hold)[0]
  expect(big.hold).toBeGreaterThan(Math.max(...OLD.filter((h) => h.tech !== 'F').map((h) => h.hold)))
  expect(big.speedKn).toBeLessThan(Math.min(...OLD.map((h) => h.speedKn)))
  // no new code or name is an older one's
  const taken = new Set(OLD.flatMap((h) => [h.class, h.name.toLowerCase()]).concat(['barca', 'carlat', 'nau']))
  expect(NEW.filter((h) => taken.has(h.class) || taken.has(h.name.toLowerCase())).map((h) => h.class)).toEqual([])
  // every one is T1 and asks only its own line's hull skill and the ladder's role skills
  for (const h of NEW) {
    expect(h.tech, h.class).toBe('T1')
    expect(h.requirements.length, h.class).toBeGreaterThan(0)
    for (const r of h.requirements) {
      expect(r.skill.startsWith(`${h.line}_`) || ['MERCHANT_SHIPS', 'SHIPS_OF_WAR', 'ESCORT_SUPPORT', 'COMMAND', 'FLEET_COMMAND'].includes(r.skill), `${h.class} asks ${r.skill}`).toBe(true)
    }
  }
})

test('the migration loads the generator\'s rows, figure for figure', () => {
  const sql = read('supabase/migrations/20260818000366_more_ships_to_trade_carry_and_fight.sql')
  expect(sql.includes('\r'), 'the migration is not LF-only').toBe(false)
  for (const h of NEW) {
    const cls = `  (${q(h.class)}, ${q(h.name)}, ${q(h.family)}, ${q(h.rig)}, ${h.hold}, ${h.crewRequired}, ${h.crewMax}, ${h.speedKn.toFixed(2)}, ${h.durability}, ${h.guns}, ${h.draft}, ${h.buildHours.toFixed(2)}, ${h.buildCost.toFixed(2)}, ${h.tier}, ${h.handling}, ${h.armour}, ${h.attack}, ${h.accuracy}, ${h.reach}, ${h.sighting.toFixed(1)}, ${h.waveResistance})`
    expect(sql, `${h.class}: her class row`).toContain(cls)
    expect(sql, `${h.class}: her profile`).toContain(`  (${q(h.class)}, ${q(h.line)}, ${h.size}, ${q(h.role)}, ${q(h.tech)}, ${h.deck}, false)`)
    expect(sql, `${h.class}: her cabins`).toContain(`  (${q(h.class)}, ${h.cabins})`)
    expect(sql, `${h.class}: her recipe`).toContain(`  (${q(h.class)}, ${h.yardTier}, ${h.ducats}, ${q(h.note)})`)
    for (const g of h.goods) expect(sql, `${h.class}: ${g.in}`).toContain(`  (${q(h.class)}, ${q(g.in)}, ${g.qty})`)
    for (const r of h.requirements) expect(sql, `${h.class}: ${r.skill}`).toContain(`  ('hull', ${q(h.class)}, ${q(r.skill)}, ${r.level})`)
    for (const [rack, n] of Object.entries(h.racks)) if (n > 0) expect(sql, `${h.class}: ${rack}`).toContain(`  (${q(h.class)}, ${q(rack)}, ${n})`)
  }
  // rows only: no function, table, column or knob
  expect(sql).not.toMatch(/\b(create|alter|drop)\s+(or\s+replace\s+)?(table|index|trigger|policy)\b/i)
  expect(sql).not.toMatch(/\b(insert\s+into|update|delete\s+from)\s+public\.world_config\b/i)
  expect((sql.match(/create function /g) ?? []).length, 'only the two pg_temp digest helpers are made, and both are dropped').toBe(2)
  expect((sql.match(/drop function pg_temp\./g) ?? []).length).toBe(2)
})

test('every new hull has a Korean name, whole, and its job word in both languages', () => {
  const missing = NEW.filter((h) => !KO_HULLS[h.name]).map((h) => h.name)
  expect(missing, 'no Korean name').toEqual([])
  const names = NEW.map((h) => KO_HULLS[h.name])
  expect(names.filter((n) => /…|\.\.\.|[A-Za-z]/.test(n) || n.trim() !== n || n.length === 0), 'a Korean name is cut, empty or still Latin').toEqual([])
  expect(new Set(names).size, 'two hulls share a Korean name').toBe(names.length)
  expect(NEW.filter((h) => /…|\.\.\./.test(h.name)).map((h) => h.name)).toEqual([])
  // the faces' job table is the generator's
  expect(Object.fromEntries(NEW.filter((h) => h.job).map((h) => [h.class, h.job]))).toEqual({ ...HULL_JOBS })
  expect(OLD.filter((h) => h.class in HULL_JOBS).map((h) => h.class), 'an older hull was given a job').toEqual([])
  for (const job of HULL_JOB_CODES) {
    expect(NEW.some((h) => h.job === job), `no hull has the job ${job}`).toBe(true)
    const en = translate('en', JOB_WORD[job])
    const ko = translate('ko', JOB_WORD[job])
    expect(en.length > 0 && en.split(' ').length <= 2, `${job}: "${en}" is not one or two words`).toBe(true)
    expect(/[가-힣]/.test(ko) && !/[A-Za-z]/.test(ko), `${job}: "${ko}" is not Korean`).toBe(true)
  }
})

// ── the faces ──────────────────────────────────────────────────────────────────────────────────
const SHOTS = process.env.MORE_SHIPS_SHOTS

async function noSideways(page: Page, what: string) {
  const over = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)
  expect(over, `${what} scrolls sideways by ${over} px`).toBeLessThanOrEqual(0)
}

/** Every name of the list as it reads, with the ones that are clipped or turned inside a word. Self-contained, shipped into the page. */
const NAMES = (selector: string) => {
  const faults: string[] = []
  const names: string[] = []
  for (const el of document.querySelectorAll<HTMLElement>(selector)) {
    const text = (el.textContent ?? '').trim()
    names.push(text)
    if (text.includes('…') || el.scrollWidth > el.clientWidth + 1) faults.push(`"${text}" is cut`)
    const node = [...el.childNodes].find((n) => n.nodeType === 3 && (n.textContent ?? '').trim()) as Text | undefined
    if (!node) continue
    for (const m of node.data.matchAll(/\S+/g)) {
      const range = document.createRange()
      range.setStart(node, m.index)
      range.setEnd(node, m.index + m[0].length)
      const lines = new Set([...range.getClientRects()].filter((r) => r.width > 0).map((r) => Math.round(r.top)))
      if (lines.size > 1) faults.push(`"${text}": the word "${m[0]}" stands on ${lines.size} lines`)
    }
  }
  return { names, faults }
}

for (const locale of ['en-US', 'ko-KR'] as const) {
  const ko = locale === 'ko-KR'
  const lang = ko ? 'ko' : 'en'
  const shown = (name: string) => (ko ? KO_HULLS[name] : name)
  for (const width of [390, 320] as const) {
    test.describe(`more ships — ${locale} at ${width} px`, () => {
      test.use({ locale, viewport: { width, height: width === 390 ? 844 : 640 }, deviceScaleFactor: 2 })

      test('the Codex lists the new hulls with their job, the Job picker narrows them, and a sheet says what she fights with', async ({ page, request, baseURL }, info) => {
        test.setTimeout(480_000)
        test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
        const shot = (name: string) => page.screenshot({ path: SHOTS ? path.join(SHOTS, `${name}-${width}-${lang}.png`) : info.outputPath(`${name}.png`) })
        await page.goto('compendium')
        await ready(page)
        await page.locator('[data-testid="codex"] [role="tablist"] [role="tab"]').nth(1).click()
        await expect(page.getByTestId('ship-tile').first()).toBeVisible({ timeout: 120_000 })
        await expect(page.getByTestId('ship-tile')).toHaveCount(3 + ALL.length)
        await noSideways(page, 'the Codex ships')

        // the Job picker: one job at a time, each tile badged with that job's word, each name whole
        const pick = page.getByTestId('filter-pick-job')
        await expect(pick, 'the Codex has no Job picker').toBeVisible()
        for (const job of HULL_JOB_CODES) {
          await pick.selectOption(job)
          const want = NEW.filter((h) => h.job === job).map((h) => shown(h.name)).sort()
          await expect(page.getByTestId('ship-tile')).toHaveCount(want.length)
          const got = await page.evaluate(NAMES, '[data-testid="ship-tile"] [data-row-cell="label"]')
          expect([...got.names].sort(), `${job}: the hulls listed`).toEqual(want)
          expect(got.faults, `${job}: a name is not whole at ${width} px`).toEqual([])
          const badges = await page.getByTestId('ship-tile').getByTestId('hull-job').allTextContents()
          expect(new Set(badges.map((b) => b.trim())), `${job}: the badge`).toEqual(new Set([translate(lang, JOB_WORD[job])]))
          await noSideways(page, `the Codex ships, ${job}`)
          if (job === 'gunship' || job === 'carrier') {
            await page.evaluate(() => document.fonts.ready)
            await shot(`codex-${job}`)
          }
        }
        // a gunship's sheet: her job, and the five figures the fight reads
        await pick.selectOption('gunship')
        const galley = NEW.find((h) => h.class === 'greatgalley')!
        await page.getByTestId('ship-tile').filter({ hasText: shown(galley.name) }).click()
        const tray = page.getByTestId('ship-tray')
        await expect(tray).toBeVisible()
        await expect(tray.getByTestId('codex-ship-job')).toContainText(translate(lang, JOB_WORD.gunship))
        const fight = tray.getByTestId('hull-fight')
        await expect(fight).toBeVisible()
        const figures = (await fight.locator('[data-row-cell="value"]').allTextContents()).map((s) => Number(s.replace(/[^\d.]/g, '')))
        expect(figures, 'attack, accuracy, reach, armour, sighting').toEqual([galley.attack, galley.accuracy, galley.reach, galley.armour, galley.sighting])
        await noSideways(page, 'a ship sheet')
        await fight.scrollIntoViewIfNeeded()
        await shot('codex-sheet')
      })

      test('the build yard offers the hulls of its own country with their job, and a sheet says what she fights with', async ({ page, request, baseURL }, info) => {
        test.setTimeout(480_000)
        test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
        const shot = (name: string) => page.screenshot({ path: SHOTS ? path.join(SHOTS, `${name}-${width}-${lang}.png`) : info.outputPath(`${name}.png`) })
        await page.goto('port')
        await ready(page)
        await page.getByRole('tablist', { name: translate(lang, 'desk.cityBuildings') }).getByRole('tab', { name: translate(lang, 'town.f_building_yard'), exact: true }).click()
        await expect(page.getByTestId('port-yard')).toBeVisible({ timeout: 60_000 })
        const more = page.getByTestId('yard-more')
        if ((await more.count()) > 0 && (await more.getAttribute('aria-expanded')) !== 'true') await more.click()
        // a fresh company is Portuguese, at Lisbon: the five Portuguese hulls of 0366 are hulls of this yard's country
        const mine = NEW.filter((h) => h.line === 'PRT')
        expect(mine.length).toBe(5)
        for (const h of mine) {
          const tile = page.getByTestId(`hull-${h.class}`)
          await expect(tile, `${h.name} is not offered at Lisbon`).toBeVisible({ timeout: 60_000 })
          await expect(tile).toContainText(shown(h.name))
          if (h.job) await expect(tile.getByTestId('hull-job')).toHaveText(translate(lang, JOB_WORD[h.job as keyof typeof JOB_WORD]))
          else await expect(tile.getByTestId('hull-job')).toHaveCount(0)
          await expect(page.getByTestId('yard-elsewhere').getByTestId(`hull-${h.class}`), `${h.name} is listed as another country's`).toHaveCount(0)
        }
        // a hull of another line is offered too, as built elsewhere
        await expect(page.getByTestId('yard-elsewhere').getByTestId('hull-greatgalley')).toBeVisible()
        await noSideways(page, 'the yard')
        const gale = NEW.find((h) => h.class === 'gale')!
        await page.getByTestId('hull-gale').scrollIntoViewIfNeeded()
        await page.evaluate(() => document.fonts.ready)
        await shot('yard')
        await page.getByTestId('hull-gale').click()
        const tray = page.getByTestId('yard-tray')
        await expect(tray).toBeVisible()
        await expect(tray.getByTestId('yard-job')).toContainText(translate(lang, JOB_WORD.boarder))
        const fight = tray.getByTestId('hull-fight')
        await expect(fight).toBeVisible()
        const figures = (await fight.locator('[data-row-cell="value"]').allTextContents()).map((s) => Number(s.replace(/[^\d.]/g, '')))
        expect(figures, 'attack, accuracy, reach, armour, sighting').toEqual([gale.attack, gale.accuracy, gale.reach, gale.armour, gale.sighting])
        await noSideways(page, 'the yard sheet')
        await shot('yard-sheet')
      })
    })
  }
}
