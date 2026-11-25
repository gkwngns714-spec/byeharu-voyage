import { useLayoutEffect, useMemo, useRef } from 'react'
import { CHART_WIDTH, sheetCopies, type ViewBox } from '../lib/geo'
import { FOG_COLS, FOG_ROWS, cellSet, type ChartFog } from './fog'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE FOG ON THE GLASS (0526; ./fog.ts says what is in sight, charted and unseen).
//
// ONE CANVAS over the whole chart, the size of the glass, and nothing else: black where she has never been, a
// grey veil where she has (the coast and a known city show through it, greyed), clear within sight of each of
// her fleets. It is drawn in three steps a frame and no more:
//   1. the glass filled black;
//   2. her charted squares cut out of it and the grey veil laid there in its place: one 360 x 180 picture (a pixel
//      a square, built only when her squares change) stretched over each copy of the sheet, smoothed, so the grey
//      has a soft edge;
//   3. a soft-edged circle cut clean round each fleet (an ellipse on this chart: a degree of longitude is shorter
//      away from the equator).
// No svg mask and no filter: a mask the size of the glass is rasterised again on every frame of a pan (the day
// sheet's lesson, ./ChartCanvas.tsx), and three canvas strokes are not. Drawn at one canvas pixel a CSS pixel on
// purpose: the fog has no hard edge to keep sharp.
// It takes no pointer: a press goes to the chart under it, and what a press may name is the screen's list.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/** How much of the map the grey hides where she has been (the "grey map, showing lands partly (transparent)"). */
const VEIL = 0.6
/** The grey itself: the colour her charted squares' picture is made of. */
const GREY = 62
/** Where a fleet's circle starts to fade, as a share of its radius. */
const SIGHT_SOFT_FROM = 0.88

export function FogLayer({ fog, box, unitsPerPx }: { fog: ChartFog; box: ViewBox; unitsPerPx: number }) {
  const ref = useRef<HTMLCanvasElement>(null)
  const w = Math.max(1, Math.round(box.width / unitsPerPx))
  const h = Math.max(1, Math.round(box.height / unitsPerPx))

  // HER SQUARES AS A PICTURE: opaque where charted. Rebuilt only when the squares change.
  const picture = useMemo(() => {
    if (typeof document === 'undefined') return null
    const c = document.createElement('canvas')
    c.width = FOG_COLS
    c.height = FOG_ROWS
    const ctx = c.getContext('2d')
    if (!ctx) return null
    const img = ctx.createImageData(FOG_COLS, FOG_ROWS)
    for (let k = 0; k < FOG_COLS * FOG_ROWS; k++) if (cellSet(fog.cells, k)) img.data.set([GREY, GREY, GREY, 255], k * 4)
    ctx.putImageData(img, 0, 0)
    return c
  }, [fog.cells])

  useLayoutEffect(() => {
    const canvas = ref.current
    const ctx = canvas?.getContext('2d')
    if (!canvas || !ctx) return
    if (canvas.width !== w) canvas.width = w
    if (canvas.height !== h) canvas.height = h
    const px = (x: number) => (x - box.x) / unitsPerPx
    const py = (y: number) => (y - box.y) / unitsPerPx
    ctx.globalCompositeOperation = 'source-over'
    ctx.globalAlpha = 1
    ctx.fillStyle = '#000'
    ctx.fillRect(0, 0, w, h)
    ctx.globalCompositeOperation = 'destination-out'
    const copies = sheetCopies(box)
    if (picture) {
      ctx.imageSmoothingEnabled = true
      const lay = () => {
        for (const k of copies) ctx.drawImage(picture, px(-CHART_WIDTH / 2 + k * CHART_WIDTH), py(-90), CHART_WIDTH / unitsPerPx, 180 / unitsPerPx)
      }
      lay()
      // added, not laid over: at a soft edge the map's share falls evenly from the grey to the black
      ctx.globalCompositeOperation = 'lighter'
      ctx.globalAlpha = VEIL
      lay()
    }
    ctx.globalCompositeOperation = 'destination-out'
    ctx.globalAlpha = 1
    const ry = fog.sightNm / 60 / unitsPerPx
    for (const eye of fog.eyes) {
      const rx = Math.min(180, fog.sightNm / (60 * Math.max(0.01, Math.cos((eye.lat * Math.PI) / 180)))) / unitsPerPx
      for (const k of copies) {
        const cx = px(eye.lon + k * CHART_WIDTH)
        const cy = py(-eye.lat)
        if (cx + rx < 0 || cx - rx > w || cy + ry < 0 || cy - ry > h) continue
        ctx.save()
        ctx.translate(cx, cy)
        ctx.scale(rx, ry)
        const g = ctx.createRadialGradient(0, 0, SIGHT_SOFT_FROM, 0, 0, 1)
        g.addColorStop(0, 'rgba(0,0,0,1)')
        g.addColorStop(1, 'rgba(0,0,0,0)')
        ctx.fillStyle = g
        ctx.beginPath()
        ctx.arc(0, 0, 1, 0, Math.PI * 2)
        ctx.fill()
        ctx.restore()
      }
    }
  }, [fog, picture, box, unitsPerPx, w, h])

  return <canvas ref={ref} className="pointer-events-none absolute inset-0 h-full w-full" aria-hidden="true" data-testid="map-fog" data-fog-sight={fog.sightNm} />
}
