import type { Page } from '@playwright/test'

// THE ONE READ OF "DO THE PEOPLE WALK" — for tests/city.page.spec.ts and tests/drive.hq.spec.ts.
//
// 2026-11-08: the drive audit found the HQ's 36 walkers STILL on every fresh load (D1 in
// docs/dev-log/2026-11-08-drive-audit.md) while city.page.spec's "the people walk" was green — it
// read one dot right after a viewport change, when the plate re-scaled under the dot. So this read
// is movement SAMPLED OVER TIME, on the page as it stands: every walker's place on the glass, taken
// inside the page `samples` times `everyMs` apart (no driver round trips between samples), plus two
// clips of the plan before and after. The caller loads fresh and touches nothing in between.
//
// What it returns: how many walkers travelled more than a pixel, the farthest travel, the biggest
// single step in plan units (a walker's pace is 2-5 units a second; a lap restart or a re-scale is a
// step the size of a street), the witness dot's distinct x values, and whether the plan's own picture
// changed between the two clips.

export interface WalkRead {
  dots: number
  moved: number
  farthest: number
  maxStepUnits: number
  witnessDistinct: number
  visible: DocumentVisibilityState
  framesDiffer: boolean
}

export async function sampleWalkers(page: Page, { samples = 12, everyMs = 250 } = {}): Promise<WalkRead> {
  // On a phone the hall panel stands first and the plan below it, inside the page's own sheet: bring the plan onto
  // the glass the way a player does (a scroll of the sheet, never a viewport change) and let a frame pass.
  const plan = page.getByTestId('city-info-image')
  await plan.scrollIntoViewIfNeeded()
  await page.waitForTimeout(300)
  const box = (await plan.boundingBox())!
  const first = await page.screenshot({ clip: box })
  const r = await page.evaluate(
    async ({ samples, everyMs }) => {
      const svg = document.querySelector('[data-testid="city-scene"]') as SVGSVGElement
      const dots = [...svg.querySelectorAll('[data-testid="city-dots"] circle')]
      const rect = svg.getBoundingClientRect()
      // `xMidYMid meet`: the plate's scale is the smaller side over the viewBox
      const pxPerUnit = Math.min(rect.width, rect.height) / svg.viewBox.baseVal.width
      const at = () => dots.map((c) => {
        const b = c.getBoundingClientRect()
        return [b.x + b.width / 2, b.y + b.height / 2] as [number, number]
      })
      const series: [number, number][][] = [at()]
      for (let i = 1; i < samples; i++) {
        await new Promise((res) => setTimeout(res, everyMs))
        series.push(at())
      }
      let moved = 0
      let farthest = 0
      let maxStep = 0
      for (let d = 0; d < dots.length; d++) {
        let travel = 0
        for (let i = 1; i < series.length; i++) {
          const step = Math.hypot(series[i][d][0] - series[i - 1][d][0], series[i][d][1] - series[i - 1][d][1])
          travel += step
          maxStep = Math.max(maxStep, step)
        }
        if (travel > 1) moved++
        farthest = Math.max(farthest, travel)
      }
      const witness = new Set(series.map((s) => (s[0] ? s[0][0].toFixed(1) : '-')))
      return {
        dots: dots.length,
        moved,
        farthest: +farthest.toFixed(1),
        maxStepUnits: +(maxStep / pxPerUnit).toFixed(2),
        witnessDistinct: witness.size,
        visible: document.visibilityState,
      }
    },
    { samples, everyMs },
  )
  const second = await page.screenshot({ clip: box })
  return { ...r, framesDiffer: Buffer.compare(first, second) !== 0 }
}

/** The law, in words the failure prints: on a fresh load most of the people walk, none jumps, the picture changes. */
export function walkVerdict(r: WalkRead, where: string): string[] {
  const faults: string[] = []
  if (r.dots < 30) faults.push(`${where}: only ${r.dots} walkers on the plan`)
  if (r.moved < Math.ceil(r.dots / 2)) faults.push(`${where}: ${r.moved} of ${r.dots} walkers moved over 3 s (farthest ${r.farthest} px) — the people stand still`)
  if (r.maxStepUnits > 3) faults.push(`${where}: a walker jumped ${r.maxStepUnits} plan units between two samples — a restart or a re-scale, not a walk`)
  if (!r.framesDiffer) faults.push(`${where}: the plan's two clips 3 s apart are byte-identical`)
  return faults
}
