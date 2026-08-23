// IS THIS BOX CLIPPED SIDEWAYS — the one measurement behind every "swipe for the rest" line.
//
// Whether a box overflows is not a fact a screen can know from its data: it depends on the
// rendered content and the width of the glass, which is why PORT once printed a swipe hint under
// a table that fitted (Table.tsx's header tells that story). The BOX knows, so the box is asked —
// and it is asked again whenever it or its children resize, so the answer is right after a read
// adds rows, after a rotation, and after a filter changes what the box holds.
//
// In its own file because the react-refresh rule forbids exporting hooks from a component file
// (reaskAtEdge.ts records the same constraint). Table.tsx and the compendium's filter strips are
// the two callers; a third box that scrolls sideways should call this rather than hand-rolling a
// ResizeObserver of its own.

import { useEffect, useState, type RefObject } from 'react'

/** True while `boxRef`'s content is wider than the box — i.e. while there is really something to
 *  swipe to. Observes the box AND its direct children, so content arriving late is measured. */
export function useClipped(boxRef: RefObject<HTMLElement | null>): boolean {
  const [clipped, setClipped] = useState(false)

  // No dependency array, deliberately (Table.tsx's original measurement ran the same way): the
  // box's CHILDREN are not stable across renders, and re-observing on every render is what keeps
  // a child swapped in by a filter under observation. The observer is torn down each time, so
  // nothing leaks.
  useEffect(() => {
    const box = boxRef.current
    if (!box) return
    // +1 absorbs sub-pixel rounding: content 331.4px wide in a 331px box is not clipped.
    const measure = () => setClipped(box.scrollWidth > box.clientWidth + 1)
    measure()
    const ro = new ResizeObserver(measure)
    ro.observe(box)
    for (const child of box.children) ro.observe(child)
    return () => ro.disconnect()
  })

  return clipped
}
