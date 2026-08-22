import { useEffect, useState, type RefObject } from 'react'

// HOW BIG IS THIS BOX — measured, once, by one hook.
//
// Every chart in the app needs the same two numbers for the same two reasons: the ASPECT decides
// what the opening frame can hold without drowning it in empty water (`openingBounds`), and the
// WIDTH turns a glyph size in CSS pixels into chart units (`unitsPerPixel`), which is what keeps a
// port mark the same size on screen at every zoom.
//
// It was written inside `./useChartSurface.ts` while the map was the only chart. It is out here
// because it is now the second thing that needs it — `./SmallChart.tsx` frames itself from the same
// two numbers and takes no gestures at all, so it must NOT mount `useChartSurface`, whose
// non-passive wheel listener calls `preventDefault()` and would eat the page's own scroll wherever
// a small chart is embedded. Two ResizeObservers, written twice, would have been the copy
// `docs/NO_SPAGHETTI.md` §1 counts.
//
// The element ref is the CALLER's, for the reason `useChartSurface` gives: a ref handed back inside
// a result object makes every later read of that object look, to the react-hooks rules, like
// touching a ref during render.

export interface ElementSize {
  /** Measured CSS pixels. Both are zero until the first layout. */
  readonly width: number
  readonly height: number
}

export function useElementSize(ref: RefObject<HTMLElement | null>): ElementSize {
  const [size, setSize] = useState<ElementSize>({ width: 0, height: 0 })

  // The ResizeObserver is the external system; the size is what it reports. Nothing else is stored.
  useEffect(() => {
    const element = ref.current
    if (!element) return
    const observer = new ResizeObserver((entries) => {
      const box = entries[0]?.contentRect
      if (box) setSize({ width: box.width, height: box.height })
    })
    observer.observe(element)
    const rect = element.getBoundingClientRect()
    setSize({ width: rect.width, height: rect.height })
    return () => observer.disconnect()
  }, [ref])

  return size
}
