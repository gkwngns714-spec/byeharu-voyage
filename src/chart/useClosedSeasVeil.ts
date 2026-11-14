import { useMemo } from 'react'
import { closedMask, type ZoneCells } from '../domain/seas'

// THE PICTURE OF THE CLOSED SEAS (./ClosedSeasLayer.tsx paints it): one pixel a cell of the server's zone raster.

/** The veil's colour: a faint dimming, and nothing more (owner, 2026-11-14: *"the map graphic of the sea, it is
 *  messed up. when zoom out the color changes"*). The slate veil of the same morning painted every ocean a new
 *  player may not enter a second, fogged colour with stepped edges, which showed as soon as the chart was pulled
 *  back. The sea is ONE colour, by night and by day; a closed sea is that colour a shade dimmer. */
const VEIL: readonly [number, number, number, number] = [6, 8, 14, 46]

/** The same colour for CSS: the swatch of the map's key (the one place that names the shade). */
export const CLOSED_SEAS_VEIL_CSS = `rgba(${VEIL[0]}, ${VEIL[1]}, ${VEIL[2]}, ${(VEIL[3] / 255).toFixed(2)})`

/** The picture of the closed seas as an image URL; null when nothing is closed, or before the raster is in hand. */
export function useClosedSeasVeil(cells: ZoneCells | null, closed: ReadonlySet<string>): string | null {
  // The picture is remade when the SET of closed seas changes, not when the read that carries it is asked again.
  const key = [...closed].sort().join(',')
  return useMemo(() => {
    const shut = new Set(key === '' ? [] : key.split(','))
    if (!cells || shut.size === 0 || typeof document === 'undefined') return null
    const mask = closedMask(cells, shut)
    const canvas = document.createElement('canvas')
    canvas.width = cells.cols
    canvas.height = cells.rows
    const ctx = canvas.getContext('2d')
    if (!ctx) return null
    const image = ctx.createImageData(cells.cols, cells.rows)
    for (let i = 0; i < mask.length; i++) {
      if (mask[i] === 0) continue
      image.data[i * 4] = VEIL[0]
      image.data[i * 4 + 1] = VEIL[1]
      image.data[i * 4 + 2] = VEIL[2]
      image.data[i * 4 + 3] = VEIL[3]
    }
    ctx.putImageData(image, 0, 0)
    return canvas.toDataURL('image/png')
  }, [cells, key])
}
