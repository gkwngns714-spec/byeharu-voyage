import { test, expect } from '@playwright/test'
import { HERE, WATERS_SHOWN, watersView } from '../src/features/map/watersRows'
import { DANGER_PIPS, DANGER_TIERS, dangerLabel, dangerPips, dangerTone } from '../src/components/ui'
import { mapFleetsOf } from '../src/chart'
import type { MapWater } from '../src/chart'
import { sailingFleet, dockedFleet } from './mapWorld.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE WATERS AHEAD — the map's answer to "the contacts panel with distances" (migration 0055)
//
// TWO KINDS OF PROOF IN ONE FILE, and the split is deliberate:
//
//   · THE CONTRACT, as data. Every decision the panel makes lives in `watersRows.ts` and
//     `dangerTiers.ts` with no React in either, so what a row SAYS is something a spec reads
//     rather than something it greps out of markup. That is the same split `rarityTiers.ts` and
//     `tileLayout.ts` already use here, and it is what lets these assertions be about the
//     owner's actual rules — "too long. make it very concise… Always show in graphics,
//     concisely" — instead of about class names.
//     (It is also the only split that WORKS: Playwright compiles JSX in anything a spec imports
//     with its own component-testing pragma, so `renderToStaticMarkup` of an app component throws
//     "Objects are not valid as a React child". Measured 2026-08-25 before this file was rewritten
//     — the render half is not missing, it is impossible in this harness.)
//
//   · THE SURFACE, measured, at 390×844. One browser test, for the one law only a real press can
//     prove: PRESSING A CONTROL SELECTS, AND NEVER DESTROYS THE SURFACE IT WAS PRESSED ON.
//     Selecting a fleet opens the detail panel; folding it keeps it. It SKIPS with a stated reason
//     when nothing is served — a proof that measures no pixels is not a proof (layout.spec.ts).
//
// THE PHONE IS 390×844 THROUGHOUT: `WATERS_SHOWN` is a law of the interface sized for that glass
// (docs/NO_SPAGHETTI.md §6, case 3), so its VALUE is pinned here as well as read from the module —
// asserting `rows.length === WATERS_SHOWN` alone is a tautology that passes for any cap, which a
// break-test proved by setting the cap to 2 and watching the test stay green.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const PHONE = { width: 390, height: 844 }

/** Five waters, taken from the world data migration 0040 authored — the tiers, the names and the
 *  notes are `public.seas` rows, not invented ones, so a row that reads badly here reads badly in
 *  the game. Ordered as `voyage.waters_ahead` orders them: the one she is in first. */
const WATERS: MapWater[] = [
  { code: 'BAY', name: 'Bay of Biscay', danger: 2, note: 'steep ugly seas', nmTo: 0, nmIn: 240, now: true },
  { code: 'NOR', name: 'North Atlantic Ocean', danger: 2, note: 'wide grey swells', nmTo: 240, nmIn: 1930, now: false },
  { code: 'MED', name: 'Mediterranean Sea', danger: 3, note: 'corsairs off the coasts', nmTo: 2170, nmIn: 640, now: false },
  { code: 'CAR', name: 'Caribbean Sea', danger: 4, note: 'buccaneers among the isles', nmTo: 2810, nmIn: 900, now: false },
  { code: 'STR', name: 'Strait of Malacca', danger: 5, note: 'thick with pirates', nmTo: 3710, nmIn: 120, now: false },
]

test.describe('the panel says what water is ahead, in figures', () => {
  test('every water she has not finished with gets a row, up to the phone’s cap', () => {
    // THE CAP IS PINNED, not read back from the module. `expect(rows).toHaveLength(WATERS_SHOWN)`
    // alone is a tautology — it passes for any cap, which a break-test on 2026-08-25 proved by
    // setting the constant to 2 and watching this test stay green. Four is a LAW OF THE INTERFACE
    // (docs/NO_SPAGHETTI.md §6, case 3): four rows plus the character line is the tallest this
    // panel can be at 390×844 and still leave the chart visible under it. Moving it is a decision
    // somebody makes on purpose, in both places.
    expect(WATERS_SHOWN).toBe(4)
    const view = watersView(WATERS)
    expect(view.rows).toHaveLength(WATERS_SHOWN)
    // …and what did not fit is SAID, not silently dropped: the header carries the true total and
    // the remainder is its own line. A truncated list that does not admit it is a lie about the sea.
    expect(view.total).toBe(WATERS.length)
    expect(view.hidden).toBe(WATERS.length - WATERS_SHOWN)
  })

  test('a short passage draws every row and has no remainder to print', () => {
    const view = watersView(WATERS.slice(0, 2))
    expect(view.rows).toHaveLength(2)
    expect(view.total).toBe(2)
    expect(view.hidden).toBe(0)
  })

  test('the distance is the hero figure with its unit, and the water she is in is named not numbered', () => {
    const figures = watersView(WATERS).rows.map((r) => r.figure)
    // EVE's number rule (docs/UI_DIRECTION.md §3): the unit is always attached and the figure is
    // grouped — `240 nm`, `2,170 nm`, never a bare 2170.
    expect(figures).toEqual([HERE, '240 nm', '2,170 nm', '2,810 nm'])
    // A distance of zero printed as a figure reads as a broken number, so the water she is IN gets
    // a NAME instead. One word; not a sentence.
    expect(HERE.split(' ')).toHaveLength(1)
    for (const f of figures.slice(1)) expect(f.endsWith(' nm')).toBe(true)
  })

  test('the tier and the name are the server’s, copied — nothing here derives one', () => {
    const rows = watersView(WATERS).rows
    expect(rows.map((r) => r.danger)).toEqual(WATERS.slice(0, WATERS_SHOWN).map((w) => w.danger))
    expect(rows.map((r) => r.name)).toEqual(WATERS.slice(0, WATERS_SHOWN).map((w) => w.name))
    expect(rows.map((r) => r.code)).toEqual(WATERS.slice(0, WATERS_SHOWN).map((w) => w.code))
    // Migration 0055 keys the per-sea encounter mix on this same `seas.danger_level`. If the panel
    // ever computed a tier of its own — from a distance, a piracy index, a hazard rate — the
    // picture and the rules would be two authorities, and this is the assertion that would go red.
  })

  test('no row is prose: the sea’s character is one line, on the water she is in, and nowhere else', () => {
    const rows = watersView(WATERS).rows
    expect(rows.filter((r) => r.note !== null).map((r) => r.note)).toEqual(['steep ugly seas'])
    expect(rows[0].note).toBe(WATERS[0].note)
    // `seas.note` is constrained to 3–60 characters by migration 0040 precisely because it is a
    // NAME and not a sentence; the panel trusts that and adds no full stop of its own.
    expect(rows[0].note!.length).toBeLessThanOrEqual(60)
    // And nothing on a row says what WILL happen. Migration 0055's header carries both reasons that
    // is a rule rather than a shortage: it would hand the player the dice, and a look-ahead of
    // voyage.hazard_roll is not even authoritative.
    const printed = rows.flatMap((r) => [r.name, r.figure, r.note ?? '']).join(' ').toLowerCase()
    expect(printed).not.toMatch(/storm|expect|likely|chance|risk|per cent|%/)
  })

  test('a fleet with no water ahead of her produces no rows at all, so the section is absent', () => {
    const view = watersView([])
    expect(view.rows).toHaveLength(0)
    expect(view.total).toBe(0)
    expect(view.hidden).toBe(0)
  })
})

test.describe('the danger mark', () => {
  test('the pip count IS the tier, and the unlit pips are still drawn', () => {
    for (const tier of DANGER_TIERS) {
      const pips = dangerPips(tier)
      expect(pips).toHaveLength(DANGER_PIPS)
      expect(pips.filter(Boolean)).toHaveLength(tier)
    }
  })

  test('the tone is the game’s colour language and nothing new', () => {
    // docs/UI_DIRECTION.md rule 7: green safe, amber caution, red danger. One meaning per colour,
    // everywhere, permanently — a five-step ramp would be two palette tokens that mean nothing
    // anywhere else in the game, which is a second colour language rather than a better one. The
    // full five-step resolution is carried by the pip COUNT, so nothing is lost.
    expect([1, 2].map(dangerTone)).toEqual(['text-success', 'text-success'])
    expect(dangerTone(3)).toBe('text-warning')
    expect([4, 5].map(dangerTone)).toEqual(['text-danger', 'text-danger'])
    expect(new Set(DANGER_TIERS.map(dangerTone)).size).toBe(3)
  })

  test('every tier has a word, and it is a name rather than a sentence', () => {
    // The word is the mark's accessible name, so a screen reader gets the tier where the eye gets
    // the pips: nothing on the row is reachable only by looking at it.
    for (const tier of DANGER_TIERS) {
      expect(dangerLabel(tier).length).toBeGreaterThan(0)
      expect(dangerLabel(tier).split(' ').length).toBeLessThanOrEqual(2)
    }
    expect(new Set(DANGER_TIERS.map(dangerLabel)).size).toBe(DANGER_TIERS.length)
  })

  test('a tier this build has never heard of degrades to a truthful lesser answer', () => {
    // A server newer than this client. NO_SPAGHETTI §7C's mirror rule: keep the truthful lesser
    // answer, never crash — the same arm RarityMark takes for a rarity it does not know. And the
    // mark stays inside its own geometry rather than drawing a ninth pip.
    expect(dangerLabel(9)).toBe('tier 9')
    expect(dangerPips(9)).toHaveLength(DANGER_PIPS)
    expect(dangerPips(9).filter(Boolean)).toHaveLength(DANGER_PIPS)
    expect(dangerPips(0).filter(Boolean)).toHaveLength(0)
  })
})

test.describe('the wire, turned into the panel', () => {
  test('every field is copied, and nothing between the wire and the ink invents a number', () => {
    const served = [
      { sea: 'BAY', name: 'Bay of Biscay', danger: 2, note: 'steep ugly seas', nm_to: 0, nm_in: 240.5, now: true },
      { sea: 'NOR', name: 'North Atlantic Ocean', danger: 2, note: 'wide grey swells', nm_to: 240.5, nm_in: 1930.25, now: false },
    ]
    const [fleet] = mapFleetsOf([
      sailingFleet({ id: 'aurora', name: 'Aurora', from: 'LIS', to: 'CAD', legFrac: 0.4, waters: served }),
    ])
    expect(fleet.kind).toBe('sailing')
    if (fleet.kind !== 'sailing') return
    expect(fleet.voyage.waters).toEqual([
      { code: 'BAY', name: 'Bay of Biscay', danger: 2, note: 'steep ugly seas', nmTo: 0, nmIn: 240.5, now: true },
      { code: 'NOR', name: 'North Atlantic Ocean', danger: 2, note: 'wide grey swells', nmTo: 240.5, nmIn: 1930.25, now: false },
    ])
    // …and the row model prints what arrived, to the digit the server rounded to.
    expect(watersView(fleet.voyage.waters).rows.map((r) => r.figure)).toEqual([HERE, '241 nm'])
  })

  test('a server that predates 0055 leaves the chart drawing a voyage with no waters, not crashing', () => {
    const [fleet] = mapFleetsOf([
      sailingFleet({ id: 'aurora', name: 'Aurora', from: 'LIS', to: 'CAD', legFrac: 0.4 }),
    ])
    expect(fleet.kind).toBe('sailing')
    if (fleet.kind !== 'sailing') return
    expect(fleet.voyage.waters).toEqual([])
    // and a docked fleet has no voyage to carry them at all
    expect(mapFleetsOf([dockedFleet('gaivota', 'Gaivota', 'LIS')])[0].kind).toBe('docked')
  })
})

// ── THE SURFACE, at 390×844 ────────────────────────────────────────────────────────────────────
test.describe('pressing a control selects, and never destroys the surface', () => {
  test.use({ viewport: PHONE })

  test('the fleet detail opens on a selection and survives its own fold', async ({
    page,
    request,
    baseURL,
  }) => {
    // The measured cold-boot budget tests/layout.spec.ts and tests/chart.ink.spec.ts both carry:
    // the migration chain applies inside this tab.
    test.setTimeout(420_000)
    let served: boolean
    try {
      served = (await request.get(baseURL ?? '')).ok()
    } catch {
      served = false
    }
    test.skip(
      !served,
      `nothing served at ${baseURL} — run \`npm run build && npx vite preview --port 4323\`, then ` +
        `PLAYWRIGHT_BASE_URL=http://localhost:4323/byeharu-voyage/ and re-run. LOCALHOST, not ` +
        `127.0.0.1: vite preview binds the IPv6 loopback, and measured on this machine ` +
        `2026-08-25 the v4 literal answers 000 while the name answers 200 — a base URL that ` +
        `cannot be fetched SKIPS this test, and a panel proof that presses nothing is not a proof.`,
    )

    await page.goto('map')
    await page.waitForFunction(
      () => !/—/.test(document.querySelector('[data-testid="purse"]')?.textContent ?? '—'),
      undefined,
      { timeout: 300_000 },
    )
    if (/\/auth$/.test(new URL(page.url()).pathname)) {
      test.skip(true, 'this build is in CLOUD mode and redirected to /auth — build without .env.local')
    }

    // At 390 px the fleet list starts folded to its header chip (MapPanel's `defaultOpen`), so the
    // first press is the fold. That is itself the law under test: it opens, it does not dismiss.
    const fleets = page.getByTestId('map-fleets-panel')
    await expect(fleets).toBeVisible()
    await page.getByTestId('map-fleets-panel-fold').click()
    await expect(fleets).toBeVisible()

    // Selecting a fleet fills the OTHER panel. A selection is a view change and nothing else.
    await fleets.locator('button[aria-pressed]').first().click()
    const detail = page.getByTestId('map-detail-panel')
    await expect(detail).toBeVisible()

    // …and folding the detail keeps it on the glass, twice over. This is the assertion the data
    // half cannot make, and the reason this file boots a browser at all.
    await page.getByTestId('map-detail-panel-fold').click()
    await expect(detail).toBeVisible()
    await page.getByTestId('map-detail-panel-fold').click()
    await expect(detail).toBeVisible()

    // A house's first fleet lies in her home port, so there is no water ahead of her and the
    // section is ABSENT rather than empty — the same rule `watersView([])` states above.
    await expect(page.getByTestId('map-waters')).toHaveCount(0)

    // The chart is still under it, and the panel is still a CORNER panel: it may not cover the
    // whole glass at 390 px, which is the defect MapPanel's compact mode exists to prevent.
    const box = await detail.boundingBox()
    expect(box).not.toBeNull()
    expect(box!.width).toBeLessThan(PHONE.width * 0.8)
  })
})
