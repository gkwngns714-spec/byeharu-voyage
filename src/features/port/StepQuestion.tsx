import { useEffect, useState } from 'react'
import { Button, Figure, Note, Row, Stepper, Tray, type TrayDetent } from '../../components/ui'
import { OrderCheck } from './orderCheck'
import type { StepOrder } from './useStepOrder'
import { fleetStores, worstHullFraction } from '../../domain/fleet'
import { enumNaming } from '../../domain/order'
import { buildingTier, hasBuilding } from '../../domain/port'
import { formatInt, formatPct, formatVoyageDays } from '../../lib/format'
import type { FleetView, SnapshotPort } from '../../lib/rpc'

// REPAIR · PROVISION — the two verbs whose question is a single quantity asked in a tray. §6: "the
// Stepper is the question; the tray shows the server's cost line and the button."
//
// ── IT STANDS ON PORT NOW, AT THE BUILDING WHOSE ACT IT IS (2026-09-09) ────────────────────────
// The owner: *"they should be located accordingly at different locations - the command."* This tray
// used to open from COMMAND's verb grid; the Shipyard asks it for REPAIR and the quay for
// PROVISION. The tray is the same one, moved — the reading rows, the stepper, the dry run and the
// one button — and the act behind it is `useStepOrder`. It reads no store itself: the fleet, the
// port and the act arrive as props, so a face composes it without the file learning which face it
// is on.
//
// ── HIRE LEFT THIS TRAY (2026-09-13, owner row 85) ─────────────────────────────────────────────
// The Inn asked it for HIRE until the crew became a face of their own (PortInn.tsx): a stepper for
// how many crew the ship should HAVE, hiring or dismissing by its direction, with the served cost
// per day beside it. One doorway per verb — the HIRE branch is DELETED here, not kept beside the
// new one (docs/NO_SPAGHETTI.md §5).
//
// Each is a decision about the fleet's own state, so the tray reads that state first — the worst
// hull, the supplies — then the stepper, then the server's dry run, then the one button. The cost
// is priced on the day by the server (`lib/rpc/types.ts:18`), which is why no price is invented
// here — the dry run names it.

export function StepQuestion({
  fleet,
  port,
  step,
  onClose,
}: {
  fleet: FleetView
  /** Where the ship is — the snapshot port, for the shipyard. */
  port: SnapshotPort | null
  step: StepOrder
  onClose: () => void
}) {
  const { spec, args, setArg, check, issuing, timeCompression } = step
  const [detent, setDetent] = useState<TrayDetent>('half')
  const numberArg = spec?.args.find((a) => a.type === 'number')

  // Seed the one default the server would otherwise supply, so the dry run runs and the button is
  // live: REPAIR repairs to whole. PROVISION is complete with FULL — no seed.
  useEffect(() => {
    if (!spec || !numberArg) return
    if (args[numberArg.name] !== undefined) return
    if (spec.verb === 'REPAIR') setArg('to_pct', '100')
  }, [spec, numberArg, args, setArg])

  if (!spec) return null

  const bound = numberArg ? boundOf(numberArg.name, fleet) : null
  const raw = numberArg ? args[numberArg.name] : undefined
  const value = raw && /^\d+$/.test(raw) ? Number(raw) : (bound?.min ?? 0)

  const setValue = (n: number) => {
    if (!numberArg) return
    if (spec.verb === 'PROVISION') {
      // The days stepper starts at nothing, which MEANS "fill it up" (mode FULL). A number turns
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
  return verb === 'REPAIR' ? 'Repair ships' : 'Resupply'
}

function actLabel(verb: string, value: number, provisionFull: boolean): string {
  if (verb === 'REPAIR') return `Repair to ${formatInt(value)}%`
  return provisionFull ? 'Fill up' : `Resupply ${formatInt(value)} days`
}

interface Bound {
  /** The least that means anything — the stepper's floor, and the value shown before one is set.
   *  For `days` it is 0, because 0 IS an answer: "fill it up" (mode FULL, the `n <= 0` arm above). */
  min: number
  max: number
  step: number
  unit: string
  label: string
  empty: string
}

function boundOf(name: string, fleet: FleetView): Bound {
  if (name === 'to_pct') {
    const now = Math.round(worstHullFraction(fleet) * 100)
    return { min: Math.min(now + 1, 100), max: 100, step: 5, unit: '%', label: 'repair to', empty: 'All ships are at full hull.' }
  }
  // days — a floor of 0, not 1: nought days is FULL, and a floor of 1 would put "fill up"
  // out of reach of `−` the moment a day count had been chosen.
  return { min: 0, max: 120, step: 5, unit: 'days', label: 'days of supplies', empty: '' }
}

/** The ship's state, in rows — the one figure this verb is a decision about, and the port fact it needs. */
function Reading({ fleet, port, verb }: { fleet: FleetView; port: SnapshotPort | null; verb: string }) {
  if (verb === 'REPAIR') {
    // DAMAGE, not "hull": what the repair is about is what has been taken, and a player reads
    // `13% damaged` as a thing to fix where `87%` of a hull reads as a score (owner row 86).
    // Formatted only — the worst hull's fraction is the served figure, and this prints 1 − it.
    const damaged = 1 - worstHullFraction(fleet)
    const yard = port && hasBuilding(port, 'shipyard')
    return (
      <>
        <Row
          label="Damage"
          value={<Figure value={`${formatPct(damaged, 0)} damaged`} tone={damaged > 0.5 ? 'danger' : 'ink'} size="figure" />}
        />
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
