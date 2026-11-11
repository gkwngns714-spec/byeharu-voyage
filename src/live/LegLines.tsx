import { useT } from '../lib/i18n'

// THE LEG LINES (owner row 191, docs/COMMAND_REDESIGN.md §3; row 209, docs/ROUTE_BUILDER.md §1) — one line per leg of a
// trip: its number, where it leaves and where it ends, its days, and one short tag. ONE component for the two places a
// trip is drawn as legs: the Trade face's mini route map (TradeMap.tsx, the plan being made) and the Map's route
// builder (features/map/RouteBar.tsx). Each caller hands in the words it already has — the days spelt, the tag — so
// this judges nothing and adds nothing up.

export interface LegLine {
  /** Harbour CODES; from is null when the leg leaves from open sea. */
  from: string | null
  to: string
  /** The days, already spelt ("1.2 d"), or "—". */
  days: string
  /** One short word or two after the days (the sea's ask, a shut leg's reason); null for none. */
  tag?: string | null
  /** Row 209: the stop tapped but not yet kept — numbered "?" and muted. */
  pending?: boolean
}

export function LegLines({
  legs,
  name,
  testId = 'plan-legs',
  itemTestId = 'plan-leg',
  className = 'mt-2 flex flex-col',
}: {
  legs: readonly LegLine[]
  name: (code: string) => string
  testId?: string
  itemTestId?: string
  className?: string
}) {
  const t = useT()
  return (
    <ol className={className} data-testid={testId}>
      {legs.map((leg, i) => (
        <li
          key={`${i}:${leg.to}`}
          className={`text-t-caption tabular-nums ${leg.pending ? 'text-ink-faint' : 'text-ink-muted'}`}
          data-testid={itemTestId}
          data-n={i + 1}
          data-from={leg.from ?? ''}
          data-to={leg.to}
          data-pending={leg.pending || undefined}
        >
          {`${leg.pending ? '?' : i + 1} ${t('desk.legLine', { from: leg.from ? name(leg.from) : t('desk.atSea'), to: name(leg.to) })} · ${leg.days}${leg.tag ? ` · ${leg.tag}` : ''}`}
        </li>
      ))}
    </ol>
  )
}
