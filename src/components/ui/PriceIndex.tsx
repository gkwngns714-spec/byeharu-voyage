// THE %NBR PILL — the one treatment of the number this game is played from.
//
// %NBR is this port's price as a percentage of what the same good fetches in the ports within
// 600 nm. It is the single figure a trader acts on, and in the reference captures it is drawn as a
// coloured pill sitting immediately after the good's name — not as a bare column you must scroll
// to (docs/UI_DIRECTION.md §2, "the row is the whole lesson").
//
// WHY THIS IS NOT A <Badge>. Badge is the status-WORD pill: uppercase, mono, 10px, for DOCKED /
// SAILING / HALTED. This is a FIGURE, and rule 2 says the number is the hero — at 10px it loses to
// the label beside it. Same shape, different job, so it gets its own primitive rather than a
// `size` prop bolted onto Badge that only one caller would ever pass.
//
// THE COLOUR IS THE SERVER'S OPINION, NOT OURS. The tone comes from `advice`, which `world.market`
// derives inside the transaction that owns the row — never from comparing `pct` against a
// threshold here. Two authorities for "is this cheap" is exactly what this project forbids, and
// the thresholds live in the chain (migration 0009).

export type PriceAdvice = 'buy' | 'sell' | 'hold'

const TONE: Record<PriceAdvice, string> = {
  // cheap here → BUY. Green, per rule 7: green is gain.
  buy: 'bg-cheap/20 text-cheap',
  // dear here → SELL. Red is "dear", which for a seller is where the money is; the WORD on the
  // band heading says which action it implies, so the colour never has to carry that alone.
  sell: 'bg-dear/20 text-dear',
  hold: 'bg-surface-2 text-even',
}

export function PriceIndex({
  pct,
  advice,
  className = '',
}: {
  /** The served `pct_nbr`. Null when the port has no neighbour trading the good — printed as an
   *  em dash, never as 100, because "no comparison exists" is not "the same as everywhere". */
  pct: number | null
  advice: PriceAdvice
  className?: string
}) {
  return (
    <span
      className={`inline-block min-w-[3.25rem] rounded px-1.5 py-0.5 text-center font-mono text-[13px] font-medium tabular-nums ${TONE[advice]} ${className}`}
    >
      {pct === null ? '—' : `${Math.round(pct)}%`}
    </span>
  )
}
