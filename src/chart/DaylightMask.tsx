import { CHART_HEIGHT, CHART_WIDTH } from '../lib/geo'

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
      {copies.map((k) => (
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
    </mask>
  )
}
