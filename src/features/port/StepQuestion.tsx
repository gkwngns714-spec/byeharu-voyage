import { useEffect, useState } from 'react'
import { Bar, Button, Figure, Note, Row, Stepper, Tray, type TrayDetent } from '../../components/ui'
import { OrderCheck } from './orderCheck'
import type { StepOrder } from './useStepOrder'
import { fleetCrew, fleetStores, worstHullFraction } from '../../domain/fleet'
import { enumNaming } from '../../domain/order'
import { buildingTier, hasBuilding } from '../../domain/port'
import { formatInt, formatPct, formatVoyageDays } from '../../lib/format'
import type { FleetView, SnapshotPort } from '../../lib/rpc'

// HIRE · REPAIR · PROVISION — the three verbs whose question is a single quantity. §6: "the Stepper
// is the question; the tray shows the server's cost line and the button."
//
// ── IT STANDS ON PORT NOW, AT THE BUILDING WHOSE ACT IT IS (2026-09-09) ────────────────────────
// The owner: *"they should be located accordingly at different locations - the command."* This tray
// used to open from COMMAND's verb grid for all three; the Inn asks it for HIRE, the Shipyard for
// REPAIR and the quay for PROVISION. The tray is the same one, moved — the reading rows, the
// stepper, the dry run and the one button — and the act behind it is `useStepOrder`. It reads no
// store itself: the fleet, the port and the act arrive as props, so a face composes it without
// the file learning which face it is on.
//
// Each is a decision about the fleet's own state, so the tray reads that state first — her crew,
// her worst hull, her stores — then the stepper, then the server's dry run, then the one button.
// The cost is priced on the day by the server (`lib/rpc/types.ts:18`), which is why no price is
// invented here — the dry run names it.

export function StepQuestion({
  fleet,
  port,
  step,
  onClose,
}: {
  fleet: FleetView
  /** Where she lies — the snapshot port, for the yard and the idle men. */
  port: SnapshotPort | null
  step: StepOrder
  onClose: () => void
}) {
  const { spec, args, setArg, check, issuing, timeCompression } = step
  const [detent, setDetent] = useState<TrayDetent>('half')
  const numberArg = spec?.args.find((a) => a.type === 'number')

  // Seed the one default the server would otherwise supply, so the dry run runs and the button is
  // live: HIRE needs a count, REPAIR mends to whole. PROVISION is complete with FULL — no seed.
  useEffect(() => {
    if (!spec || !numberArg) return
    if (args[numberArg.name] !== undefined) return
    if (spec.verb === 'HIRE') setArg('count', '1')
    else if (spec.verb === 'REPAIR') setArg('to_pct', '100')
  }, [spec, numberArg, args, setArg])

  if (!spec) return null

  const bound = numberArg ? boundOf(numberArg.name, fleet) : null
  const raw = numberArg ? args[numberArg.name] : undefined
  const value = raw && /^\d+$/.test(raw) ? Number(raw) : (bound?.min ?? 0)

  const setValue = (n: number) => {
    if (!numberArg) return
    if (spec.verb === 'PROVISION') {
      // The days stepper starts at nothing, which MEANS "fill her up" (mode FULL). A number turns
      // it into a day target, which is what the enum names (domain/order's enumNaming).
      if (n <= 0) {
        setArg('days', null)
        setArg('mode', null)
        return
      }
      const naming = enumNaming(spec, numberArg)
      if (naming) setArg(naming.enumArg.name, naming.value)
    }
    setArg(numberArg.name, String(n))
  }

  const refused = check.status === 'refused' || check.status === 'checking'
  const label = actLabel(spec.verb, value, spec.verb === 'PROVISION' && !raw)

  return (
    <Tray
      detent={detent}
      onDetentChange={(next) => (next === 'closed' ? onClose() : setDetent(next))}
      title={title(spec.verb)}
      data-testid="step-tray"
      action={
        <Button
          variant="primary"
          className="w-full"
          disabled={issuing || refused || (bound !== null && bound.max <= 0)}
          busy={issuing}
          busyLabel="Sending…"
          onClick={step.send}
          data-testid="step-send"
        >
          {label}
        </Button>
      }
    >
      <Reading fleet={fleet} port={port} verb={spec.verb} />

      {numberArg && bound && bound.max > 0 ? (
        <div className="py-3">
          <Stepper
            value={Math.min(value, bound.max)}
            onChange={setValue}
            min={bound.min}
            max={bound.max}
            step={bound.step}
            unit={bound.unit}
            label={bound.label}
            presets={presetsFor(spec.verb, Math.min(value, bound.max), bound)}
          />
        </div>
      ) : bound && bound.max <= 0 ? (
        <Note tone="neutral">{bound.empty}</Note>
      ) : null}

      <OrderCheck check={check} timeCompression={timeCompression} />
    </Tray>
  )
}

function title(verb: string): string {
  return verb === 'HIRE' ? 'Hire crew' : verb === 'REPAIR' ? 'Repair ships' : 'Resupply'
}

function actLabel(verb: string, value: number, provisionFull: boolean): string {
  if (verb === 'HIRE') return `Hire ${formatInt(value)}`
  if (verb === 'REPAIR') return `Repair to ${formatInt(value)}%`
  return provisionFull ? 'Fill up' : `Resupply ${formatInt(value)} days`
}

interface Bound {
  /** The least that means anything — the stepper's floor, and the value shown before one is set.
   *  For `days` it is 0, because 0 IS an answer: "fill her up" (mode FULL, the `n <= 0` arm above). */
  min: number
  max: number
  step: number
  unit: string
  label: string
  empty: string
}

/**
 * THE JUMPS THE OWNER ASKED FOR BY NAME — row 16: *"how many crew to hire, have it + 10, +100, max,
 * make it more friendly"*, and row 29: *"what is max 12 in hire? just max is enough"*, which is why
 * the last chip reads `Max` and not `Max 12`. The figure is already on the rail beside it.
 *
 * BOTH ROWS READ "DONE — verified" AND NEITHER WAS TRUE IN THE SHIPPED GAME. `Stepper` has carried
 * a `presets` prop since it was written, `TradeTray`, `FleetStores` and the gallery all pass one,
 * and this tray — the only place HIRE is asked — passed none. The screens were rebuilt on the
 * twelve primitives (DEV_LOG D45-D52) and the chips did not come across. Found 2026-09-09 by
 * reading who calls `presets`, not by looking at the screen.
 *
 * A JUMP IS RELATIVE AND THE CEILING IS ABSOLUTE, so `+10` is computed from where the player is
 * now and `Max` is not. Jumps that would land at or past the end are dropped rather than shown as
 * three chips that all mean the same thing, and `Stepper` clamps every one of them anyway.
 *
 * WHAT THIS DELIBERATELY DOES NOT DO: row 16 also says MAX must be the smallest of berths free,
 * the port's idle crew, and what the purse can pay. That is a SERVED ceiling — `Stepper`'s `cap`,
 * whose own contract says it "is never recomputed here: this game has already had SEVEN answers to
 * how much fits in this hull". No such figure is served for HIRE today, so this passes none and the
 * server's dry run keeps refusing an over-large hire, as it does now. The served ceiling is owed.
 */
function presetsFor(verb: string, value: number, bound: Bound) {
  if (verb !== 'HIRE' || bound.max <= 0) return undefined
  const jumps = [10, 100]
    .filter((n) => value + n < bound.max)
    .map((n) => ({ label: `+${n}`, value: value + n }))
  return [...jumps, { label: 'Max', value: bound.max }]
}

function boundOf(name: string, fleet: FleetView): Bound {
  if (name === 'count') {
    const berths = fleetCrew(fleet).berths
    return { min: 1, max: berths, step: 1, unit: 'crew', label: 'crew to hire', empty: 'This fleet has no free crew slots.' }
  }
  if (name === 'to_pct') {
    const now = Math.round(worstHullFraction(fleet) * 100)
    return { min: Math.min(now + 1, 100), max: 100, step: 5, unit: '%', label: 'repair to', empty: 'All ships are at full hull.' }
  }
  // days — a floor of 0, not 1: nought days is FULL, and a floor of 1 would put "fill up"
  // out of reach of `−` the moment a day count had been chosen.
  return { min: 0, max: 120, step: 5, unit: 'days', label: 'days of supplies', empty: '' }
}

/** Her state, in rows — the one figure this verb is a decision about, and the port fact it needs. */
function Reading({ fleet, port, verb }: { fleet: FleetView; port: SnapshotPort | null; verb: string }) {
  if (verb === 'HIRE') {
    const crew = fleetCrew(fleet)
    return (
      <>
        <Row label="Crew" value={<Figure value={formatInt(crew.aboard)} unit={`of ${formatInt(crew.max)}`} size="figure" />}>
          <Bar value={crew.aboard} of={10} tone={crew.short > 0 ? 'danger' : 'success'} label="crew" className="mt-1" />
        </Row>
        <Row label="Available here" value={<Figure value={port ? formatInt(port.crew_pool) : '—'} />} hairline={false} />
      </>
    )
  }
  if (verb === 'REPAIR') {
    const worst = Math.round(worstHullFraction(fleet) * 100)
    const yard = port && hasBuilding(port, 'shipyard')
    return (
      <>
        <Row label="Hull (worst ship)" value={<Figure value={formatPct(worst / 100, 0)} tone={worst < 50 ? 'danger' : 'ink'} size="figure" />} />
        <Row
          label="Shipyard"
          tone={yard ? 'default' : 'muted'}
          value={port ? (yard ? `Level ${buildingTier(port, 'shipyard')}` : 'none here') : 'at sea'}
          hairline={false}
        />
      </>
    )
  }
  const stores = fleetStores(fleet)
  return (
    <>
      <Row label="Supplies" value={<Figure value={formatVoyageDays(fleet.endurance_days)} size="figure" />} />
      <Row
        label="On board"
        value={<Figure value={`${stores.waterT.toFixed(0)} tons water · ${stores.foodT.toFixed(0)} tons food`} />}
        hairline={false}
      />
    </>
  )
}
