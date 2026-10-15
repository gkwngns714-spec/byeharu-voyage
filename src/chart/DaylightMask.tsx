import { useEffect, useRef } from 'react'
import { gameSunInstantMs } from '../lib/format'
import { serverNow } from '../lib/serverClock'
import { CHART_HEIGHT, CHART_WIDTH } from '../lib/geo'
import { subsolarPoint } from './sun'

/** THE SOFT TERMINATOR (owner, 2026-10-15: "right now the light zone moves rigid. make it soft").
 *  The raster is drawn with the Sun over longitude 0 (useSunlight.ts); every animation frame this
 *  slides it to where the game clock puts the Sun — x IS longitude on this chart (lib/geo
 *  `project`) — by setting one transform attribute, no React render. One extra copy each side so
 *  the slide never shows an edge; the mask's own x/width clips it. */
function useSunSlide() {
  const ref = useRef<SVGGElement>(null)
  useEffect(() => {
    let frame = 0
    const step = () => {
      const lon = subsolarPoint(gameSunInstantMs(serverNow())).lon
      ref.current?.setAttribute('transform', `translate(${lon} 0)`)
      frame = requestAnimationFrame(step)
    }
    step()
    return () => cancelAnimationFrame(frame)
  }, [])
  return ref
}

// THE DAYLIGHT MASK — the Sun's raster (./useSunlight.ts) as an SVG <mask>, stretched over each
// copy of the sheet it is asked for. ONE definition of how the raster becomes a mask, used by
// the two sheets that paint a day picture: SeaLayer (the water, in the view's svg — which spans
// every copy on the glass, so it asks for them all) and CoastlineLayer (the coast, inside the
// base copy's group — which the <use> copies translate along with their mask, so it asks for one).
//
// AN ALPHA MASK, NOT A LUMINANCE ONE. SVG's default mask is luminance computed in linearRGB, which
// would bend the twilight: a raster value of 50% would let through ~21%. The raster is written
// into the image's ALPHA channel (useSunlight.ts), and `mask-type: alpha` reads it linearly, so
// the daylight the almanac computed is the daylight the picture shows. Bilinear filtering on the
// way up (`image-rendering: auto`) is what makes a 1°-per-pixel raster a smooth terminator.

export function DaylightMask({
  id,
  rasterUrl,
  copies,
}: {
  id: string
  rasterUrl: string
  /** The sheet copies (k) the mask must cover — `sheetCopies` of whatever it is applied over. */
  copies: readonly number[]
}) {
  const slide = useSunSlide()
  const first = Math.min(...copies)
  const last = Math.max(...copies)
  const x = first * CHART_WIDTH - CHART_WIDTH / 2
  return (
    <mask
      id={id}
      maskUnits="userSpaceOnUse"
      maskContentUnits="userSpaceOnUse"
      x={x}
      y={-CHART_HEIGHT / 2}
      width={(last - first + 1) * CHART_WIDTH}
      height={CHART_HEIGHT}
      style={{ maskType: 'alpha' }}
      data-testid="map-daylight-mask"
    >
      <g ref={slide}>
        {[first - 1, ...copies, last + 1].map((k) => (
        <image
          key={k}
          href={rasterUrl}
          x={k * CHART_WIDTH - CHART_WIDTH / 2}
          y={-CHART_HEIGHT / 2}
          width={CHART_WIDTH}
          height={CHART_HEIGHT}
          preserveAspectRatio="none"
          style={{ imageRendering: 'auto' }}
        />
        ))}
      </g>
    </mask>
  )
}
