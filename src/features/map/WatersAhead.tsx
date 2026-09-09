import { Bar, DANGER_PIPS, dangerLabel, dangerTone, Figure, Row, type BarTone } from '../../components/ui'
import type { MapWater } from '../../chart'
import { watersView } from './watersRows'

// AHEAD — the waters a fleet at sea still has to cross, and how far off each one is.
//
// `docs/NAVIGATION_PLAN.md:173` asks for *"the contacts panel with distances"*. A CONTACT means a
// ship, and there are no ships to meet (docs/PLATFORM.md §3 SEAM 2 is deliberately unbuilt), so
// this names what there IS — the water itself, `seas.danger_level` and `seas.note` (0040), which
// until 0055 was read by no rule and shown on no screen.
//
// IT IS NOT A FORECAST, and that is a rule rather than a shortage. `voyage.hazard_roll` is a pure
// function of (voyage, day, world secret), so listing what WILL happen ahead is trivial and refused
// twice over: it hands the player the dice, and 0055 measured that a look-ahead is not even
// authoritative. Every figure here is frozen at departure except her own progress.
//
// THE SHAPE is the owner's concise law — *"Always show in graphics, concisely"*: one `Row` per sea,
// the danger tier as a countable `Bar`, the name, the distance as the figure. The sea she is in
// gets her character in the world's own words ("steep ugly seas") as the row's second line. Every
// decision about WHAT a row says is `watersRows.ts`'s; this file is markup.
//
// Nothing here is pressable: engaging a contact needs an actor, and there is none yet. The per-sea
// encounter MIX (0055) is authored and DARK; it becomes a fourth fact on the row the day it is lit.

/** The tier's tone as the `Bar` says it. `dangerTone` is the one colour language (green safe,
 *  amber caution, red danger) and it answers in a text utility; the bar wants the same word. */
function barTone(tier: number): BarTone {
  return dangerTone(tier).replace('text-', '') as BarTone
}

export function WatersAhead({ waters }: { waters: readonly MapWater[] }) {
  const { rows, total, hidden } = watersView(waters)
  if (rows.length === 0) return null

  return (
    <div className="mt-6" data-testid="map-waters">
      <Row label="Ahead" value={<Figure value={<span data-testid="map-waters-count">{total}</span>} />} />
      {rows.map((row) => (
        <Row
          key={`${row.code}-${row.figure}`}
          mark={
            <Bar
              of={DANGER_PIPS}
              value={row.danger}
              tone={barTone(row.danger)}
              label={dangerLabel(row.danger)}
              className="w-10"
            />
          }
          label={row.name}
          value={<Figure value={<span data-testid="map-water-distance">{row.figure}</span>} />}
          data-testid="map-water-row"
        >
          {row.note !== null && (
            <span className="block text-t-caption text-ink-faint" data-testid="map-water-note">
              {row.note}
            </span>
          )}
        </Row>
      ))}
      {hidden > 0 && <Row tone="muted" hairline={false} label={`+${hidden} beyond`} data-testid="map-waters-more" />}
    </div>
  )
}
