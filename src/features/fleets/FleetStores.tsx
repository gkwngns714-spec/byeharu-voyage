import { Button, Figure, Hint, Note, Row, SheetSection, Stepper } from '../../components/ui'
import { formatFixed, formatInt, formatVoyageDays } from '../../lib/format'
import { useWorld } from '../../live/worldStore'
import type { FleetView, ProvisionPreset, ProvisionPresetBook } from '../../lib/rpc'
import { fleetCrew, fleetStores } from '../../domain/fleet'
import { keepDays } from './standingOrder'

// THE STORES, AND THE ORDER THAT KEEPS THEM — the galley face, as rows and one stepper.
//
// It was a seven-row mono `dl` (water · food · provision · keep · crew · cargo · a day) with a ⓘ
// on `cargo`, then a strip of chips naming the book's presets. What decides a voyage is how many
// days of stores she has and how many the house wants her kept at; water and food are what those
// days are made of, and the crew is what they are sized against. Those four are rows. "A day"
// (crew × a config knob) is gone — §5, no screen prints a config knob — and "cargo" was the hold
// figure the row and the Ships face already print.
//
// ── THE ORDER IS ONE NUMBER ────────────────────────────────────────────────────────────────────
// `Keep 15 d [−][+]` (§6's sketch). The stepper's chips are the book's own orders, so a level
// another fleet is kept at is one tap here; the days-to-book operations are standingOrder.ts's
// rule and this face never sees a name. The slider's end is a chosen scale, not a rule — the
// server takes 1 to 999 (0034) and says so itself if asked for more.

/** The stepper's end. Two months of stores is more than any hull in the game can stow. */
const KEEP_SCALE = 60

export function FleetStores({
  fleet,
  order,
  book,
  days,
  onDays,
}: {
  fleet: FleetView
  /** The order she sails under, or null. */
  order: ProvisionPreset | null
  book: ProvisionPresetBook | null
  /** The stepper's figure — the draft, or the served days when there is none. */
  days: number
  onDays: (days: number) => void
}) {
  const refusal = useWorld((s) => s.refusal)
  const dismissRefusal = useWorld((s) => s.dismissRefusal)
  const stores = fleetStores(fleet)
  const crew = fleetCrew(fleet)
  // Docked under an order she no longer meets — the "hire 20 at Cádiz and her range collapses"
  // case, made visible BEFORE she sails. The served figure against the served target, with the
  // same 0.01-day dust floor the server's own satisfied-check uses (0034).
  const short = order !== null && fleet.status === 'DOCKED' && fleet.endurance_days < order.days - 0.01

  // The book's levels, each once, as the stepper's chips.
  const levels = [...new Set((book?.presets ?? []).map((p) => p.days))].sort((a, b) => a - b)

  return (
    <>
      {/* BARE FIGURES, THE UNIT ON THE FIGURE. lib/format's `formatTuns` / `formatVoyageDays`
          carry their own unit word; `Figure` sets the unit small and dim beside the value, so a
          Figure is given the number alone or the unit prints twice — measured ("15.0 days days"). */}
      <Row
        label="Stores"
        value={<Figure value={formatFixed(fleet.endurance_days, 1)} unit="days" tone={short ? 'warning' : 'ink'} />}
        data-testid="fleet-stores-days"
      />
      <Row label="Water" value={<Figure value={formatFixed(stores.waterT, 1)} unit="t" />} />
      <Row label="Food" value={<Figure value={formatFixed(stores.foodT, 1)} unit="t" />} />
      <Row
        label="Crew"
        value={
          <Figure
            value={`${formatInt(crew.aboard)}/${formatInt(crew.max)}`}
            unit="aboard"
            tone={crew.short > 0 ? 'danger' : 'ink'}
          />
        }
        hairline={false}
      />

      <SheetSection heading="Keep her at">
        <Stepper
          label={`days of stores to keep ${fleet.name} at`}
          value={days}
          onChange={onDays}
          max={KEEP_SCALE}
          unit={days === 1 ? 'day' : 'days'}
          presets={levels.map((d) => ({ label: keepDays(d), value: d }))}
          data-testid="fleet-keep-stepper"
        />
        <Hint className="mt-2">
          {short && order
            ? `She is under her ${formatVoyageDays(order.days)} order and short of it.`
            : 'Topped up to this on every arrival, and charged to the purse.'}
        </Hint>
        {refusal && (
          <Note
            tone="danger"
            code={refusal.code}
            className="mt-2"
            action={
              <Button variant="quiet" size="sm" onClick={dismissRefusal}>
                Dismiss
              </Button>
            }
          >
            {refusal.sentence}
          </Note>
        )}
      </SheetSection>
    </>
  )
}
