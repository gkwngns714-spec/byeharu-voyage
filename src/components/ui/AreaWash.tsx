import { useId } from 'react'
import type { WashFade } from './seriesChartModel'

// THE GROUND UNDER A LINE, WITHOUT A WALL AT ITS END (owner, 2026-11-06: "in chart, i don't like the right edge chart to drop verticley").
// A wash closed straight down from its last point stands as a cliff at the right edge of every chart. So the wash fades out over its
// last stretch (`WashFade`, from the model: ONE spelling for the series chart and the price chart) and arrives at nothing exactly where
// the line ends. The fill only is faded: the line itself is drawn by the caller, untouched, and nothing is drawn past the last point.

export function AreaWash({ d, fade, className, fillOpacity }: { d: string; fade: WashFade | null; className: string; fillOpacity?: number }) {
  const id = useId()
  if (!d) return null
  if (!fade) return <path d={d} className={className} fillOpacity={fillOpacity} stroke="none" />
  return (
    <>
      <defs>
        <linearGradient id={`${id}-g`} gradientUnits="userSpaceOnUse" x1={fade.from} x2={fade.to} y1={0} y2={0}>
          <stop offset="0" stopColor="#fff" />
          <stop offset="1" stopColor="#000" />
        </linearGradient>
        <mask id={`${id}-m`} maskUnits="userSpaceOnUse" x={-10000} y={-10000} width={20000} height={20000}>
          <rect x={-10000} y={-10000} width={20000} height={20000} fill={`url(#${id}-g)`} />
        </mask>
      </defs>
      <path d={d} className={className} fillOpacity={fillOpacity} stroke="none" mask={`url(#${id}-m)`} data-wash-fade />
    </>
  )
}
