// The map's loading meter, as the page records it (src/features/map: `data-testid="map-load"`, `data-load-pct`, `data-load-step`). One definition for the
// drive specs that watch it (tests/drive.map.spec.ts in the plain pool, tests/drive.map.merchants.spec.ts in the merchants-on pool): a copy drifts.

type MeterEntry = { pct: number | null; step: string | null; gone: boolean; position: string | null; world: string | null; chart: string | null }
export type MeterWindow = { __meter?: MeterEntry[] }

/** Shipped into the page before its first paint: every appearance, change and removal of the map's meter, with what stood around it. */
export function watchMeter() {
  const w = window as unknown as MeterWindow
  w.__meter = []
  const chartBox = () => {
    const r = document.querySelector('[data-testid="map-chart"]')?.getBoundingClientRect()
    return r ? [r.x, r.y, r.width, r.height].map(Math.round).join(',') : null
  }
  const record = (el: Element | null, gone: boolean) => {
    const host = el?.closest('[data-testid="map-load-host"]') ?? el
    w.__meter!.push({
      pct: el ? Number(el.getAttribute('data-load-pct')) : null,
      step: el?.getAttribute('data-load-step') ?? null,
      gone,
      position: host ? getComputedStyle(host).position : null,
      world: document.querySelector('[data-world]')?.getAttribute('data-world') ?? null,
      chart: chartBox(),
    })
  }
  const meterIn = (n: Node): Element | null =>
    n instanceof Element ? (n.matches('[data-testid="map-load"]') ? n : n.querySelector('[data-testid="map-load"]')) : null
  try {
    new MutationObserver((list) => {
      for (const m of list) {
        if (m.type === 'attributes' && m.target instanceof Element && m.target.matches('[data-testid="map-load"]')) record(m.target, false)
        else if (m.type === 'childList') {
          for (const n of m.addedNodes) {
            const el = meterIn(n)
            if (el) record(el, false)
          }
          for (const n of m.removedNodes) if (meterIn(n)) record(null, true)
        }
      }
    }).observe(document, { subtree: true, attributes: true, attributeFilter: ['data-load-pct'], childList: true })
  } catch {
    /* no observer: the log stays empty and the law fails on its floor */
  }
}

