import type { CrewBonuses as Bonuses } from '../lib/rpc'

// WHAT THE CAPTAINS ADD TO THIS FLEET (0157, docs/SKILLS_AND_CAPTAINS.md §4.4) — `world.crew_bonuses`,
// served on the fleet: one line per source (captain · trait · cabin · what it adds) and the total per
// effect as public.crew_pct gives it (capped). Every word is the server's; nothing is summed here. A
// fleet whose captains add nothing draws nothing.
export function CrewBonuses({ crew }: { crew: Bonuses | undefined }) {
  if (!crew || crew.lines.length === 0) return null
  return (
    <section data-testid="crew-bonuses">
      <div className="flex items-baseline justify-between pb-2 pt-4">
        <h3 className="text-t-caption uppercase tracking-wider text-ink-faint">Crew bonuses</h3>
        <span className="text-t-caption tabular-nums text-accent">{crew.totals.map((t) => t.line).join(' · ')}</span>
      </div>
      <ul className="flex flex-col gap-1">
        {crew.lines.map((l, i) => (
          <li key={`${l.captain}-${l.trait}-${l.effect}-${i}`}
            className="flex items-baseline justify-between gap-3 rounded-control bg-surface-2 px-3 py-2">
            <span className="min-w-0 truncate text-t-caption text-ink">{`${l.captain} · ${l.trait} · ${l.cabin_word}`}</span>
            <span className="shrink-0 text-t-caption tabular-nums text-accent">{l.line}</span>
          </li>
        ))}
      </ul>
    </section>
  )
}
