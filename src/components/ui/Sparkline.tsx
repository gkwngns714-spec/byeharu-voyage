import { useT } from '../../lib/i18n'
// THE PRICE LINE — the one thing a trade game must have and this one could not draw until 0013.
//
// It is deliberately austere: a path, no axes, no grid, no labels, no tooltip. EVE's full market
// graph (median, hi/lo band, two moving averages, a volume histogram, a draggable range selector)
// is a desktop instrument; at 390px, inside a table row, the honest form is the shape of the line
// and nothing else. The numbers beside it are already exact.
//
// WHAT IT REFUSES TO DO:
//   · It does not interpolate. Points arrive one per drift slot; a gap in the record is a gap in
//     the line, because a smooth curve through missing data is a claim nobody made.
//   · It does not scale to zero. A price that moved 2% would look identical to one that halved if
//     the axis started at the origin — the band is the data's own min..max, so the line shows the
//     SHAPE of the move and the figures beside it carry the size.
//   · It draws nothing at all below two points. One point is not a trend, and a dot on an empty
//     box reads as a broken chart rather than as "no record yet".
//
// The caller says what it means: `tone` is the same buy/sell/hold language the row is already
// coloured by, so the line never introduces a fifth colour vocabulary.

export type SparkTone = 'cheap' | 'dear' | 'even'

const STROKE: Record<SparkTone, string> = {
  cheap: 'stroke-cheap',
  dear: 'stroke-dear',
  even: 'stroke-even',
}

export function Sparkline({
  values,
  tone = 'even',
  width = 64,
  height = 18,
  label,
  className = '',
}: {
  /** Oldest first. Fewer than two and this renders nothing. */
  values: readonly number[]
  tone?: SparkTone
  width?: number
  height?: number
  /** Announced to assistive tech, which cannot see a line ("salt, 12 readings, 118 to 131"). */
  label?: string
  className?: string
}) {
  const t = useT()
  // BELOW TWO POINTS THERE IS NO LINE, AND THIS DRAWS NOTHING (consistency audit row 37,
  // 2026-10-31). Until this fix the branch returned a "—" span, so every good whose served series
  // was empty or one point long printed a dash the desk read as a placeholder where a figure was
  // owed. The absence is now drawn as an absence, which is what the header above always claimed;
  // a caller that wants a word beside the gap says it itself — the chart never speaks.
  if (values.length < 2) return null

  const lo = Math.min(...values)
  const hi = Math.max(...values)
  const span = hi - lo
  // A perfectly flat line has no band to scale into; draw it down the middle rather than dividing
  // by zero, because "it did not move" is a real and interesting answer.
  const y = (v: number) => (span === 0 ? height / 2 : height - ((v - lo) / span) * (height - 2) - 1)
  const x = (i: number) => (i / (values.length - 1)) * width

  const d = values.map((v, i) => `${i === 0 ? 'M' : 'L'}${x(i).toFixed(1)} ${y(v).toFixed(1)}`).join(' ')

  return (
    <svg
      width={width}
      height={height}
      viewBox={`0 0 ${width} ${height}`}
      className={`inline-block align-middle ${className}`}
      role="img"
      aria-label={label ?? t('ui.readings', { n: values.length, lo, hi })}
      preserveAspectRatio="none"
    >
      <path
        d={d}
        fill="none"
        strokeWidth={1.25}
        strokeLinecap="round"
        strokeLinejoin="round"
        className={STROKE[tone]}
        vectorEffect="non-scaling-stroke"
      />
    </svg>
  )
}
