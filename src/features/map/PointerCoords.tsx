import { useEffect, useRef, useState, type RefObject } from 'react'
import { pointLabel } from '../../lib/format'
import { unproject, wrapLon, type ViewBox } from '../../lib/geo'

// WHERE THE MOUSE IS, IN DEGREES (owner, 2026-11-14: "i want to see the coordinates where my mouse is on map").
//
// One chip in the chart's corner, printed with the one wording a water point has everywhere (`pointLabel`), while a
// MOUSE is over the chart. A finger has no hover, so a touch never shows it. The chip holds its own state, so a
// moving mouse re-renders these few characters and never the map screen; it listens on the chart's own element and
// reads the view's box through a ref, so a pan or a zoom under a still mouse needs no new listener.

/** The chart-unit box turned into the degrees under a point of the chart's element; null past a pole. */
function degreesAt(box: ViewBox, rect: DOMRect, clientX: number, clientY: number): { lat: number; lon: number } | null {
  if (rect.width <= 0 || rect.height <= 0) return null
  const at = unproject({
    x: box.x + ((clientX - rect.left) / rect.width) * box.width,
    y: box.y + ((clientY - rect.top) / rect.height) * box.height,
  })
  if (at.lat > 90 || at.lat < -90) return null
  // the sheet has no edge east or west: a view past the seam still reads a longitude of the world
  let lon = at.lon
  while (lon > 180 || lon < -180) {
    const next = wrapLon(lon)
    if (next === lon) break
    lon = next
  }
  return { lat: at.lat, lon }
}

export function PointerCoords({ chart, box }: { chart: RefObject<HTMLElement | null>; box: ViewBox | null }) {
  const [text, setText] = useState<string | null>(null)
  const boxRef = useRef(box)
  const last = useRef<{ x: number; y: number } | null>(null)

  // A pan or a zoom under a still mouse moves the water under it: read again with the new box.
  useEffect(() => {
    boxRef.current = box
    const el = chart.current
    const at = last.current
    if (!el || !box || !at) return
    const deg = degreesAt(box, el.getBoundingClientRect(), at.x, at.y)
    setText(deg ? pointLabel(deg) : null)
  }, [box, chart])

  useEffect(() => {
    const el = chart.current
    if (!el) return
    const move = (e: PointerEvent) => {
      if (e.pointerType !== 'mouse') return
      last.current = { x: e.clientX, y: e.clientY }
      const b = boxRef.current
      const deg = b ? degreesAt(b, el.getBoundingClientRect(), e.clientX, e.clientY) : null
      setText(deg ? pointLabel(deg) : null)
    }
    const leave = () => {
      last.current = null
      setText(null)
    }
    el.addEventListener('pointermove', move)
    el.addEventListener('pointerleave', leave)
    return () => {
      el.removeEventListener('pointermove', move)
      el.removeEventListener('pointerleave', leave)
    }
  }, [chart])

  if (text === null) return null
  return (
    <p
      data-testid="map-pointer-coords"
      className="pointer-events-none flex h-5 items-center rounded-chip bg-surface/90 px-2 text-t-caption tabular-nums text-ink-muted"
    >
      {text}
    </p>
  )
}
