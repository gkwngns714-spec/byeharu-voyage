// HOW LONG A SPEC WAITS FOR A NEAR TRIP TO LAND — one figure, for every spec that sends a fleet and waits for her.
//
// THE ARITHMETIC, read off the chain (the live bodies at head 0352, dumped from the cached local world):
//   * A voyage-day is 24 sim-hours, and `time_compression` is 960: 24 × 3600 / 960 = 90 real seconds.
//   * A near trip (Lisbon to Setubal or Porto, what `findCarry` picks for a new company) is a fraction of a voyage-day:
//     about 0.1 days, 9 seconds, to Setubal.
//   * EVERY voyage-day is rolled once (`voyage.hazard_roll`): something happens with p = the sea's `hazard_base`
//     (0.006 to 0.020) × the leg's `hazard_mult`, never more than `hazard_p_max` = 0.06.
//   * What the roll costs is ONE table, `voyage.day_delay_hours` (20260818000125, read through
//     `voyage.day_delay_for` since 0154): a STORM +36 h (1.5 voyage-days, 135 s); a CALM +round((1 + 3 × magnitude) × 24, 2) h,
//     that is 24 to 96 h (1 to 4 voyage-days, 90 to 360 s); a FAIR WIND gives back at most the delay already accrued.
//   * THE DAYS GROW WITH THE DELAY. `voyage.arrival_at` and `voyage.settle` roll every day up to
//     ceil((sim-hours + delay) / 24) (`voyage.total_days`), so each day a calm adds is rolled too and may be becalmed again.
//
// SO THERE IS NO GREATEST DELAY. One roll costs at most 4 voyage-days (a near trip then lands 0.1 + 4 = 4.1 days,
// 369 real seconds, after she sails); a second calm on one of the added days makes it up to 8.1 days (729 s); a third 12.1.
// With every day rolled at the 0.06 ceiling and every event taken as a calm (20,000,000 simulated trips, 30 s of slack for
// the arrivals beat and the page's own read): later than 300 s, 2.5 in 100; later than 480 s, 5 in 1,000 (two events, or
// one on a longer hop); later than 900 s, 4 in 10,000. The real odds are lower: these seas roll well under the ceiling
// and not every event is a calm.
//
// THE WAIT is ten voyage-days: any TWO delays of any size on a trip of up to a day (1 + 4 + 4 = 9 days, 810 s) and a
// day of margin. It is paid only by a run that fails: a spec goes on the moment the card stands. A red here is three
// delays on one short hop (rare; the message below says she is still under way) or a card that never came (a bug; the
// message says she lies in port).
//
// tests/trade.flow.spec.ts (PR #600) carries its own `LANDS_WITHIN_MS = 480_000`: it should import this one after it merges.
import { expect, type Locator, type Page } from '@playwright/test'

/** A voyage-day in real milliseconds (`time_compression` 960). */
export const VOYAGE_DAY_MS = 90_000

/** How long a near trip may take to land: ten voyage-days (see the arithmetic above). */
export const LANDS_WITHIN_MS = 10 * VOYAGE_DAY_MS

/** The per-test timeout of a spec that waits for one landing: the wait, and five minutes for everything else
 *  (the world's first load, the buy, the send, what is read after the card, and the failure's own read of Fleets). */
export const LANDING_TEST_TIMEOUT_MS = LANDS_WITHIN_MS + 300_000

const oneLine = (s: string) => s.replace(/\s+/g, ' ').trim()

/** The places a page says where a fleet is: the Trade status line (PR #600), a fleet's row (Fleets, the desk's
 *  picker), the desk's fleet strip, the queue's passage line. */
const VOYAGE_WORDS = ['trade-status', 'fleet-row', 'fleet-strip', 'queue-passage'] as const

/** What THIS page says about the voyage, as it stands now: every line that names where she is, or that it has none. */
export async function voyageWords(page: Page): Promise<string> {
  const said: string[] = []
  for (const id of VOYAGE_WORDS) {
    const texts = await page.getByTestId(id).allInnerTexts().catch(() => [] as string[])
    for (const t of texts) if (oneLine(t)) said.push(`${id} ${JSON.stringify(oneLine(t))}`)
  }
  return said.length ? said.join('; ') : 'nothing (this page has no line about a voyage)'
}

/** WAIT FOR THE ARRIVAL CARD, up to LANDS_WITHIN_MS, and return it. When it does not come, the failure says what the
 *  page said about the voyage at that moment, and what the Fleets page says (it is opened for that: the test has failed). */
export async function arrivalCard(page: Page, where: string): Promise<Locator> {
  const card = page.getByTestId('arrival-card')
  const began = Date.now()
  let failed: unknown = null
  try {
    await expect(card).toBeVisible({ timeout: LANDS_WITHIN_MS })
  } catch (e) {
    failed = e
  }
  if (failed === null) return card

  const waited = Math.round((Date.now() - began) / 1000)
  const here = await voyageWords(page).catch((e: unknown) => `(not read: ${String(e)})`)
  let fleets: string
  try {
    await page.goto('fleets')
    const rows = page.getByTestId('fleet-row')
    await expect(rows.first()).toBeVisible({ timeout: 30_000 })
    fleets = (await rows.allInnerTexts()).map((t) => JSON.stringify(oneLine(t))).join('; ')
  } catch (e) {
    fleets = `(the Fleets page did not answer: ${oneLine(String(e)).slice(0, 200)})`
  }
  throw new Error(
    `${where}: no arrival card ${waited} s after the wait began (the bound is ${LANDS_WITHIN_MS / 1000} s, ten voyage-days; ` +
      `tests/arrivalWait.fixture.ts). The page said: ${here}. Fleets says: ${fleets}. ` +
      `A fleet still "to" a harbour is the sea's delay (three on one hop); a fleet lying in port is a card that never came.\n` +
      oneLine(String(failed)).slice(0, 400),
  )
}
