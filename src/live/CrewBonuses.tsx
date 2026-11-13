import { BonusRows, WRAP_ROW_CLASS } from '../components/ui'
import type { CrewBonuses as Bonuses } from '../lib/rpc'
import { useT } from '../lib/i18n'

// WHAT THE CAPTAINS ADD TO THIS FLEET (0157, docs/SKILLS_AND_CAPTAINS.md §4.4) — `world.crew_bonuses`,
// served on the fleet: one line per source (captain · trait · cabin · what it adds) and the total per
// effect as public.crew_pct gives it (capped). Every word is the server's; nothing is summed here. A
// fleet whose captains add nothing draws nothing.
export function CrewBonuses({ crew }: { crew: Bonuses | undefined }) {
  const t = useT()
  if (!crew || crew.lines.length === 0) return null
  return (
    <section data-testid="crew-bonuses">
      {/* THE TOTALS GO UNDER THE HEADING WHERE THEY DO NOT FIT BESIDE IT (2026-11-14, owner row 318): on a phone "CREW BONUSES" stood on two
          lines with four totals run up against it. The heading is one line. */}
      <div className={`${WRAP_ROW_CLASS} pb-2 pt-4`}>
        <h3 className="whitespace-nowrap text-t-caption uppercase tracking-wider text-ink-faint">{t('town.crewBonuses')}</h3>
        <span className="text-t-caption tabular-nums text-accent">{crew.totals.map((t) => t.line).join(' · ')}</span>
      </div>
      <BonusRows
        rows={crew.lines.map((l, i) => ({
          key: `${l.captain}-${l.trait}-${l.effect}-${i}`,
          source: `${l.captain} · ${l.trait} · ${l.cabin_word}`,
          effect: l.line,
        }))}
      />
    </section>
  )
}
