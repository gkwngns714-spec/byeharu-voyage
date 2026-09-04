import { test, expect } from '@playwright/test'
import { readFileSync } from 'node:fs'
import path from 'node:path'
import { fitToViewBox } from '../src/lib/geo'
import { FIT_PADDING, openingBounds } from '../src/chart'
import { sailOrigin, sailTarget } from '../src/domain/passage'
import { REAL_PORTS, dockedFleet, portAt } from './mapWorld.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE MAP'S ONE ACT, DRIVEN — three defects found in a real browser on the running game, each one
// with an assertion that fails without its fix.
//
// They were found by playing, not by reading, and they are all one class: **a screen that looks
// like it worked.** A tap that misses a harbour opens a plausible OPEN SEA panel for a different
// destination. A fold that can use a standing order but not write one looks like a control with
// one dead option. An opening frame with no land in it looks like a broken renderer. None of them
// throws, none of them logs, and the first two cost the player a voyage.
//
//   1. A TAP ON A HARBOUR'S NAME IS A TAP ON THE HARBOUR   (browser, and it was not)
//   2. THE RATIO IS SET ON THE FOLD, AND SETTING IT SENDS NOTHING   (browser)
//   3. THE OPENING FRAME ALWAYS HAS A COAST IN IT   (pure + browser)
//
// ── HOW EACH ONE IS PROVEN, AND WHY IT CANNOT PASS VACUOUSLY ───────────────────────────────────
// The browser half drives THE REAL GAME: a real PostgreSQL (PGlite) in the tab running the real
// migration chain, the §K.1 founding house, real `cmd.preview` dry runs. Nothing here is stubbed,
// so a green line means the chain answered. Every assertion is measured off the DOM the player
// actually touches — the text element of a port's name, the rendered coastline path — never off a
// prop or a constant this file also owns.
//
// It SKIPS with a stated reason when nothing is served rather than passing (tests/layout.spec.ts's
// rule, and the reason acceptance.yml has a non-vacuity floor).
//
// Run it: npm run build && npm run preview, then `npx playwright test map.sendfleet.spec.ts`.
// Point it elsewhere with PLAYWRIGHT_BASE_URL.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/** iPhone 14 Pro logical viewport — the device the owner's rules are written for. */
const PHONE = { width: 390, height: 844 }
const PHONE_ASPECT = PHONE.width / PHONE.height

/** Every harbour there is, as the chart takes them. A harbour is where land meets water, which is
 *  why the opening frame can find land with no coastline in hand (src/chart/chartView.ts). */
const WORLD = REAL_PORTS.map((p) => ({ lat: p.lat, lon: p.lon }))

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// 3a. THE OPENING FRAME ALWAYS HAS A COAST IN IT — pure, no browser.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/** What the player would actually be looking at: `openingBounds` as `useChartSurface` uses it —
 *  through `fitView`, so the padding and the aspect are the real ones and not this file's idea. */
function opensOn(focus: { lat: number; lon: number }) {
  const bounds = openingBounds([focus], [focus], WORLD, PHONE_ASPECT)
  const box = fitToViewBox(bounds, PHONE_ASPECT, FIT_PADDING)
  return {
    minLon: box.x,
    maxLon: box.x + box.width,
    // The projection is y = −lat (src/lib/geo/projection.ts), so the box's top is the HIGHER
    // latitude. Read through it rather than assuming a sign.
    minLat: -(box.y + box.height),
    maxLat: -box.y,
  }
}

function harboursIn(frame: ReturnType<typeof opensOn>): string[] {
  return REAL_PORTS.filter(
    (p) =>
      p.lon >= frame.minLon && p.lon <= frame.maxLon && p.lat >= frame.minLat && p.lat <= frame.maxLat,
  ).map((p) => p.code)
}

test.describe('the opening frame is never a frame of empty water', () => {
  // The case that made the rule. A fleet may ride at anchor on any point of open water (0039,
  // OWNER_REQUESTS row 42), and the old frame was 12° of whatever was around her — which mid-ocean
  // is 12° of nothing. Measured on the seeded world: this point's frame held ZERO harbours before
  // the fix, and the tab therefore opened on a featureless field with a few names floating on it.
  test('a fleet anchored in the middle of the Atlantic still opens on a coast', () => {
    const frame = opensOn({ lat: 35, lon: -40 })
    const found = harboursIn(frame)
    expect(
      found.length,
      `the opening frame for a mid-Atlantic anchor holds no harbour, so it holds no coast: ` +
        `${frame.minLat.toFixed(1)}…${frame.maxLat.toFixed(1)}°N by ` +
        `${frame.minLon.toFixed(1)}…${frame.maxLon.toFixed(1)}°E`,
    ).toBeGreaterThan(0)
  })

  // The far case, stated rather than left undefined: mid-Pacific, the nearest land is genuinely an
  // ocean away, and the frame is as wide as it has to be. That is the honest picture of where she
  // is; `clampView` caps the worst case at the globe, which is still a map.
  test('mid-Pacific, the frame widens as far as it must — and says where she is by showing it', () => {
    const frame = opensOn({ lat: 0, lon: -140 })
    expect(harboursIn(frame).length).toBeGreaterThan(0)
  })

  // A frame that already held a coast must not move: the rule only ever WIDENS, exactly like the
  // 12° floor it sits behind. Lisbon is the §K.1 opening house, so this is the frame every new
  // player sees, and it must be the same frame after the fix as before it.
  test('a fleet lying in a harbour is not re-framed — the rule only widens', () => {
    const lisbon = { lat: 38.72, lon: -9.13 }
    const bounds = openingBounds([lisbon], [lisbon], WORLD, PHONE_ASPECT)
    // 12° across is `OPENING_MIN_SPAN_DEG`'s own floor, untouched by the coast rule.
    expect(bounds.maxLon - bounds.minLon).toBeCloseTo(12, 6)
    expect(harboursIn(opensOn(lisbon)).length).toBeGreaterThan(1)
  })
})

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// 4. WHERE THE ORDER AIMS — the roadstead (0076), pure, no browser.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// A fourth defect of the same class as the three above: **an order that looks like it worked and
// is refused.** After migration 0076 the server verifies a SAIL against the port's ROADSTEAD — the
// one point of open water it is reached from — and grants a flat 25 nm of slack at each end. A
// client still proposing quay to quay hands over a line beginning up to 67.7 nm from where the
// server has her lying, and every order for a port snapping further than `course_join_nm` (15 nm)
// comes back `E_OFF_COURSE`: 139 of the world's 238 places, Lisbon (23.30 nm) among them. Nothing
// throws, nothing logs; the row just says no.

const PORT_BY_CODE = Object.fromEntries(REAL_PORTS.map((p) => [p.code, p]))

test.describe('a SAIL begins and ends in the roads, not at the quay', () => {
  test('a harbour destination resolves to its SERVED roadstead', () => {
    const ams = portAt('AMS')
    expect(sailTarget({ dest: 'AMS' }, PORT_BY_CODE)).toEqual({ lat: 52.875, lon: 4.375 })
    // …which is 35.47 nm from her quay, so this is not the same answer under another name.
    expect(sailTarget({ dest: 'AMS' }, PORT_BY_CODE)).not.toEqual({ lat: ams.lat, lon: ams.lon })
    expect(ams.roadstead.nm).toBe(35.47)
  })

  test('a fleet lying at a quay departs from that harbour’s roads', () => {
    const gaivota = dockedFleet('g', 'Gaivota', 'LIS')
    // Lisbon is the §K.1 opening house, and she snaps 23.30 nm — further than the 15 nm join
    // tolerance. The player's very first voyage is the one this fix exists for.
    expect(sailOrigin(gaivota, PORT_BY_CODE)).toEqual({ lat: 38.625, lon: -9.625 })
    expect(portAt('LIS').roadstead.nm).toBe(23.3)
  })

  test('a port that stands on her own water is her own roadstead — the same answer as before', () => {
    const brs = portAt('BRS')
    expect(brs.roadstead.nm).toBe(0)
    expect(sailTarget({ dest: 'BRS' }, PORT_BY_CODE)).toEqual({ lat: brs.lat, lon: brs.lon })
  })

  test('a tapped point of open water is untouched — it is already water by construction', () => {
    expect(sailTarget({ dest_point: '33,-15' }, PORT_BY_CODE)).toEqual({ lat: 33, lon: -15 })
    expect(sailTarget({}, PORT_BY_CODE)).toBeNull()
    expect(sailTarget({ dest: 'NOPE' }, PORT_BY_CODE)).toBeNull()
  })

  test('both screens ask the ONE authority — neither builds a course target of its own', () => {
    // This is the guard on the shape rather than on the answer. `SendFleet` and `CommandScreen`
    // each held their own `{ lat: p.lat, lon: p.lon }` before 0076, which meant this slice had to
    // be applied twice on the same afternoon or one screen would have gone on proposing courses
    // the server refuses. They now read `domain/passage`'s `sailTarget`, and every proposal is
    // made with its result.
    const SRC = path.resolve(process.cwd(), 'src', 'features')
    for (const file of ['map/SendFleet.tsx', 'command/CommandScreen.tsx']) {
      const text = readFileSync(path.join(SRC, file), 'utf8')
      const calls = [...text.matchAll(/proposeCourse\(([^)]*)\)/g)]
      expect(calls.length, `${file} proposes no course at all — has it moved?`).toBeGreaterThan(0)
      for (const call of calls) {
        const args = call[1].split(',').map((s) => s.trim())
        expect(
          args[2],
          `${file} proposes a course to something other than the one authority's answer. Where a ` +
            `SAIL aims is domain/passage's sailTarget, and for a harbour that is her roadstead.`,
        ).toBe('target')
      }
      expect(
        text,
        `${file} does not read sailTarget. A second answer to "where does this order aim" is how ` +
          `this line came to be written twice in the first place.`,
      ).toMatch(/const target[^=]*=\s*sailTarget\(/)
    }
  })
})

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE BROWSER HALF — the real chain, the real chart, at 390×844.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

test.describe('the whole send, driven on a phone', () => {
  test.use({ viewport: PHONE })
  // The local engine applies the WHOLE migration chain to a real PostgreSQL in the tab on first
  // boot. That is the point — nothing here is a fixture — and it is why this one drive is given a
  // long clock rather than being split into tests that would each pay for it again.
  test.setTimeout(600_000)

  test('a harbour is tappable by its name, and a ratio can be set without sailing', async ({
    page,
    request,
    baseURL,
  }) => {
    const reachable = await request
      .get(baseURL ?? '')
      .then((r) => r.ok())
      .catch(() => false)
    test.skip(
      !reachable,
      `nothing served at ${baseURL} — run \`npm run build && npm run preview\` (or set ` +
        `PLAYWRIGHT_BASE_URL) and re-run`,
    )

    await page.goto('map')
    await page.waitForSelector('[data-testid="map-ports"] > g', { timeout: 300_000 })
    const chart = page.locator('svg[aria-label^="Chart of the world"]')
    await expect(chart.getByTestId('map-coastline')).toHaveCount(1)

    // ── DEFECT 3, at the glass ────────────────────────────────────────────────────────────────
    // Not "the coastline element exists" — that is true of an opening frame in mid-ocean, which is
    // the defect. LAND IS ON SCREEN: a grid of points over the viewBox actually on the glass, each
    // asked of the rendered path itself through `isPointInFill`, which is the browser's own answer
    // to "is this spot land". Nothing in this measurement comes from the app's own arithmetic.
    const grid = await chart.evaluate((svg) => {
      const path = svg.querySelector('[data-testid="map-coastline"]') as SVGGeometryElement | null
      const box = (svg as SVGSVGElement).viewBox.baseVal
      if (!path || box.width <= 0) return { samples: 0, land: 0 }
      const step = 24
      let samples = 0
      let land = 0
      for (let i = 0; i < step; i += 1) {
        for (let j = 0; j < step; j += 1) {
          const x = box.x + ((i + 0.5) / step) * box.width
          const y = box.y + ((j + 0.5) / step) * box.height
          samples += 1
          if (path.isPointInFill(new DOMPoint(x, y))) land += 1
        }
      }
      return { samples, land }
    })
    expect(grid.samples, 'the coastline path was never sampled — the measurement is vacuous').toBe(576)
    // MEASURED on the §K.1 house at 390×844: 154 of 576 sample points (26.7%) fall on land, which
    // is Iberia and north-west Africa in the opening frame. The floor is set at a twentieth of the
    // sheet — far enough below the measurement to survive a coastline retune, far enough above zero
    // that "a few floating names on a dark field" cannot pass it.
    expect(
      grid.land / grid.samples,
      `the opening frame is ${((grid.land / grid.samples) * 100).toFixed(1)}% land — a chart that ` +
        `shows the player no coast teaches them nothing about a game whose one spatial law is ` +
        `"she never touches land"`,
    ).toBeGreaterThan(0.05)
    await page.screenshot({ path: 'map-open-390.png' })

    // ── DEFECT 1: the name IS the harbour ─────────────────────────────────────────────────────
    // The player reads a name and puts a thumb on it. Measured in a browser drive at 1389×900
    // before the fix: the centre of the word "Cadiz" is 24.8 px from its mark, the reach was 22 px,
    // and a tap there returned `OPEN SEA 36.4°N 6.4°W` — a plausible panel for a wasted voyage.
    const name = await chart.evaluate((svg) => {
      const text = svg.querySelector('text[data-label-id="port:CAD"]')
      if (!text) return null
      const r = text.getBoundingClientRect()
      return { cx: r.x + r.width / 2, cy: r.y + r.height / 2, width: r.width }
    })
    expect(name, 'Cadiz was not named on the opening frame — nothing was aimed at').not.toBeNull()
    await page.mouse.click(name!.cx, name!.cy)

    const detail = page.getByTestId('map-detail-panel')
    await expect(detail).toBeVisible()
    await expect(
      detail,
      'a tap on the word "Cadiz" did not select Cadiz — the harbour a player sees is the mark AND ' +
        'its name, and missing it silently offers a different destination',
    ).toContainText('Cadiz')

    // ── DEFECT 2: the fold can now WRITE a ratio, and writing it is not sailing ────────────────
    await page.getByTestId('map-send-fleet').click()
    const row = page.getByTestId('map-send-row-head').first()
    await expect(row).toBeVisible()
    const her = (await row.innerText()).split('\n')[0]
    await row.click()

    const keep = page.getByTestId('map-send-keep')
    await expect(keep).toBeVisible()
    const ratio = page.getByTestId('map-send-ratio')
    await expect(
      ratio,
      'the fold offers no way to SET a ratio, so a house with no standing order must leave the ' +
        'map to write one — the screen-hop OWNER_REQUESTS row 45 exists to delete',
    ).toBeVisible()

    const figures = page.getByTestId('map-send-ratio-figures')
    const before = await figures.innerText()
    await page.getByTestId('map-send-ratio-more').click()
    await page.getByTestId('map-send-ratio-more').click()
    await expect(figures).not.toHaveText(before)
    const deeper = await figures.innerText()
    await page.getByTestId('map-send-ratio-less').click()
    await expect(figures).not.toHaveText(deeper)

    // ARMED, NOT FIRED. Three independent readings of "she has not sailed", because this is the
    // dangerous half: a ratio control one stray tap from dispatching a real voyage would be worse
    // than no control.
    await expect(page.getByTestId('map-send-busy')).toHaveCount(0)
    await expect(page.getByTestId('map-send-sent')).toHaveCount(0)
    // A fleet that HAS been sent loses her row head (`pressable` flips) and gains a note in its
    // place, so the head still standing with her own name on it is the world saying she is where
    // she was.
    await expect(page.getByTestId('map-send-row-head').first()).toContainText(her)

    // NOTHING WAS COLLAPSED, REPLACED OR DESTROYED — the owner's standing rule. Every step of the
    // fold that was open before the ratio moved is open after it.
    await expect(page.getByTestId('map-send-fleet')).toHaveAttribute('aria-expanded', 'true')
    await expect(page.getByTestId('map-send-fleets')).toBeVisible()
    await expect(keep).toBeVisible()
    await expect(page.getByTestId('map-send-keep-none')).toBeVisible()
    // And the one control that WILL sail her is present, named, and separate.
    await expect(page.getByTestId('map-send-ratio-send')).toBeEnabled()

    await page.screenshot({ path: 'map-fold-ratio-390.png' })

    // ── HOW A HARBOUR IS AIMED AT FROM HERE ON ────────────────────────────────────────────────
    // By CODE, off the mark, not by the printed word. DEFECT 1 above proves the word is tappable
    // and that is its own assertion; but the declutterer drops a harbour's NAME when a fleet's
    // label takes that spot, and the chart re-frames as she sails, so a saved coordinate or a
    // search by text both go stale. The code does not.
    const tapHarbour = async (code: string) => {
      // DISMISS THE OPEN CARD FIRST. It is pinned bottom-right OVER the chart, so a mark that
      // happens to lie under it takes the tap as a press on the card's own header and the card
      // simply folds shut — which is how this assertion first failed, reading back a panel whose
      // whole content was the word "Port". The player has the same ✕; the drive uses it.
      const dismiss = page.getByTestId('map-detail-panel-close')
      if ((await dismiss.count()) > 0 && (await dismiss.isVisible())) await dismiss.click()
      const at = await chart.evaluate((svg, want: string) => {
        const mark = svg.querySelector(`g[data-port-code="${want}"] path`)
        if (!mark) return null
        const r = (mark as SVGGeometryElement).getBoundingClientRect()
        return { cx: r.x + r.width / 2, cy: r.y + r.height / 2 }
      }, code)
      if (!at) return false
      await page.mouse.click(at.cx, at.cy)
      // And if an earlier tap DID fold it, open it again — a folded card is not a missing card,
      // and asserting against its header would be asserting against chrome.
      const unfold = page.getByTestId('map-detail-panel-fold-toggle')
      if ((await unfold.count()) > 0 && (await unfold.getAttribute('aria-expanded')) === 'false') {
        await unfold.click()
      }
      return true
    }

    const fleetsPanel = page.getByTestId('map-fleets-panel')
    // At 390 the panel starts FOLDED by design (FleetsPanel's defect-3 note); open it if it is.
    const fold = page.getByTestId('map-fleets-panel-fold-toggle')
    if ((await fold.count()) > 0 && (await fold.getAttribute('aria-expanded')) === 'false') {
      await fold.click()
    }
    const herRow = fleetsPanel.locator('li button').first()
    await expect(herRow).toBeVisible()

    // ── DEFECT 5: THE ACT ITSELF HAD NEVER BEEN PROVEN ────────────────────────────────────────
    // Everything above this line, in every version of this file, stopped one press short: the
    // suite asserted that the fold OPENS, that the ratio MOVES, and that nothing sailed. Not once
    // did it assert that pressing send makes a voyage. That gap is why OWNER_REQUESTS row 49 could
    // stand for three days against a green suite. It fires now, and the WORLD is asked, twice.
    // The armed-not-fired readings above are complete before this line, so firing here takes
    // nothing away from them — it adds the half that was missing.
    await page.getByTestId('map-send-ratio-send').click()

    // Reading 1: her row in the fold flips out of `pressable`, which happens only because the WORLD
    // now says she has a voyage — the store is re-read from the server, never patched here.
    await expect(page.getByTestId('map-send-row-note').first()).toContainText('Under way', {
      timeout: 60_000,
    })
    // Reading 2, independent of the fold entirely: the corner panel derives her line from the world
    // payload, and a fleet at sea reads "→ <destination> · <clock>".
    await expect(herRow).toContainText('→ Cadiz', { timeout: 60_000 })

    // ── DEFECT 4: "i can't send a fleet in map" — the dead end, OWNER_REQUESTS row 49 ──────────
    // Reported live on production while playing, never reproduced by a test, and reproduced in ten
    // seconds by driving the real game: tap a harbour where none of your fleets can be sent, press
    // **Send fleet**, and the fold opens onto a list in which NOTHING is pressable. Every row is a
    // note. A house with one fleet has pressed SEND and found no send. Each row was individually
    // honest and the fold as a whole was a dead end — which is the difference between a rule and a
    // screen.
    //
    // On production it was the harbour her fleet was LYING in: her marker and that harbour's name
    // are printed on top of each other. **That exact tap is not reachable at 390.** The label
    // engine drops the harbour's name in favour of the fleet's, and the surface's nearest-wins hit
    // test then hands a tap on that spot to the FLEET, whose card carries no send control at all —
    // a second face of the same complaint, and the one DetailPanel's `SendHint` already answers.
    // So the state is reached the other way the fold reaches it, through the fleet she is BOUND
    // for, which the press above just made true and which lands on the identical branch.
    expect(await tapHarbour('CAD'), "Cadiz's mark is not on the glass").toBe(true)
    await expect(detail).toContainText('Cadiz')
    await page.getByTestId('map-send-fleet').click()

    // THE FIX, MEASURED. Before it, `map-send-nowhere` did not exist and this fold held one row
    // whose whole content was a note. The player had pressed the one control the screen offered
    // and the screen had answered with nothing they could act on.
    await expect(
      page.getByTestId('map-send-nowhere'),
      'the fold opened onto a list with nothing pressable in it and never said so — this is ' +
        'exactly what "i cannot send a fleet in map" looks like from the other side of the glass',
    ).toBeVisible()
    // And it is the REAL dead end being named, not a line printed beside a working list.
    await expect(page.getByTestId('map-send-row-head')).toHaveCount(0)
    // Her row says which kind of dead end it is. WHICH of the two wordings stands depends on
    // whether this fold still holds the press that sent her — `acted` is stamped with the
    // destination and the fleet — so both are accepted here; the assertion is that the row is a
    // NOTE and names her state, not that it names one particular one.
    await expect(page.getByTestId('map-send-row-note').first()).toHaveText(
      /Under way|already bound here/,
    )

    // POSITIVE CONTROL — the line must be ABSENT wherever a send IS possible, or it says nothing
    // at all. Any other harbour on the glass will do: she is at sea and may TURN for it.
    const other = await chart.evaluate((svg, taken: string) => {
      const marks = Array.from(svg.querySelectorAll('g[data-port-code]'))
      const hit = marks.find((g) => g.getAttribute('data-port-code') !== taken)
      return hit ? hit.getAttribute('data-port-code') : null
    }, 'CAD')
    expect(
      other,
      'only one harbour is marked on the opening frame, so the positive control has nowhere to ' +
        'aim — without it the assertion above proves only that a string can be rendered',
    ).not.toBeNull()
    expect(await tapHarbour(other!), `${other}'s mark went off the glass`).toBe(true)
    await expect(page.getByTestId('map-send-fleet')).toBeVisible()
    await page.getByTestId('map-send-fleet').click()
    await expect(page.getByTestId('map-send-nowhere')).toHaveCount(0)
    await expect(page.getByTestId('map-send-row-head').first()).toBeVisible()
  })
})
