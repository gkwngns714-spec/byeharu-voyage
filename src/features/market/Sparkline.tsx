// The 7-DAY column of E.4, drawn as inline SVG.
//
// Small, silent and honest: it plots the last seven game-days of `mid` with no axis, no label and
// no tooltip, because the number it is next to already says what today's price is. All the
// sparkline adds is the SHAPE — whether you are looking at a spike that is about to fall back or a
// trend you can still catch. Nothing animates (E's "nothing blinks, nothing pulses").
//
// It is deliberately NOT a design-system primitive: it exists for one column of one table, and a
// chart in components/ui would invite a second, differently-behaved one.

export function Sparkline({
  values,
  width = 56,
  height = 16,
  tone = 'currentColor',
}: {
  values: readonly number[]
  width?: number
  height?: number
  tone?: string
}) {
  if (values.length < 2) {
    return (
      <span aria-hidden className="font-mono text-[11px] text-ink-faint">
        —
      </span>
    )
  }
  const min = Math.min(...values)
  const max = Math.max(...values)
  const span = max - min
  const stepX = width / (values.length - 1)
  // A flat series would divide by zero; draw it down the middle instead, which is what it means.
  const y = (v: number) => (span === 0 ? height / 2 : height - 1 - ((v - min) / span) * (height - 2))
  const d = values.map((v, i) => `${i === 0 ? 'M' : 'L'}${(i * stepX).toFixed(2)} ${y(v).toFixed(2)}`).join(' ')
  const first = values[0]
  const last = values[values.length - 1]
  const direction = last > first ? 'rising' : last < first ? 'falling' : 'flat'

  return (
    <svg
      width={width}
      height={height}
      viewBox={`0 0 ${width} ${height}`}
      role="img"
      aria-label={`seven-day price, ${direction}: ${values.map((v) => Math.round(v)).join(', ')}`}
      className="inline-block align-middle"
    >
      <path d={d} fill="none" stroke={tone} strokeWidth={1.25} strokeLinejoin="round" strokeLinecap="round" />
      <circle cx={width} cy={y(last)} r={1.6} fill={tone} />
    </svg>
  )
}
