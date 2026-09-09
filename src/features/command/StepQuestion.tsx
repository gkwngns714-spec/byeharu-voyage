import { useEffect, useState } from 'react'
import { Bar, Button, Figure, Note, Row, Stepper, Tray, type TrayDetent } from '../../components/ui'
import { OrderCheck, type CheckState } from './orderCheck'
import { fleetCrew, fleetStores, worstHullFraction } from '../../domain/fleet'
import { enumNaming } from '../../domain/order'
import { buildingTier, hasBuilding } from '../../domain/port'
import { formatInt, formatPct, formatVoyageDays } from '../../lib/format'
import type { FleetView, SnapshotPort, VerbSpec } from '../../lib/rpc'

// HIRE · REPAIR · PROVISION — the three verbs whose question is a single quantity. §6: "the Stepper
// is the question; the tray shows the server's cost line and the button."
//
// Each is a decision about the fleet's own state, so the tray reads that state first — her crew,
// her worst hull, her stores — then the stepper, then the server's dry run, then the one button.
// This is the whole of what the old FleetRail (600 lines, four blocks, a sticky column) and the
// number pickers were; the reading is rows now, and the cost is priced on the day by the server
// (`lib/rpc/types.ts:18`), which is why no price is invented here — the dry run names it.

export function StepQuestion({
  fleet,
  spec,
  port,
  args,
  setArg,
  check,
  timeCompression,
  issuing,
  onIssue,
  onClose,
}: {
  fleet: FleetView
  spec: VerbSpec
  /** Where she lies (or is bound) — the snapshot port, for the yard and the idle men. Null at sea. */
  port: SnapshotPort | null
  args: Record<string, string>
  setArg: (name: string, value: string | null) => void
  check: CheckState
  timeCompression: number
  issuing: boolean
  onIssue: () => void
  onClose: () => void
}) {
  const [detent, setDetent] = useState<TrayDetent>('half')
  const numberArg = spec.args.find((a) => a.type === 'number')

  // Seed the one default the server would otherwise supply, so the dry run runs and the button is
  // live: HIRE needs a count, REPAIR mends to whole. PROVISION is complete with FULL — no seed.
  useEffect(() => {
    if (!numberArg) return
    if (args[numberArg.name] !== undefined) return
    if (spec.verb === 'HIRE') setArg('count', '1')
    else if (spec.verb === 'REPAIR') setArg('to_pct', '100')
  }, [spec.verb, numberArg, args, setArg])

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
          busyLabel="Issuing…"
          onClick={onIssue}
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
  return verb === 'HIRE' ? 'Sign on crew' : verb === 'REPAIR' ? 'Mend her hulls' : 'Provision her'
}

function actLabel(verb: string, value: number, provisionFull: boolean): string {
  if (verb === 'HIRE') return `Hire ${formatInt(value)}`
  if (verb === 'REPAIR') return `Mend to ${formatInt(value)}%`
  return provisionFull ? 'Fill the barrels' : `Provision ${formatInt(value)} days`
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

function boundOf(name: string, fleet: FleetView): Bound {
  if (name === 'count') {
    const berths = fleetCrew(fleet).berths
    return { min: 1, max: berths, step: 1, unit: 'crew', label: 'crew to sign on', empty: 'Every berth in this fleet is filled.' }
  }
  if (name === 'to_pct') {
    const now = Math.round(worstHullFraction(fleet) * 100)
    return { min: Math.min(now + 1, 100), max: 100, step: 5, unit: '%', label: 'mend her to', empty: 'Every hull is whole.' }
  }
  // days — a floor of 0, not 1: nought days is FULL, and a floor of 1 would put "fill the barrels"
  // out of reach of `−` the moment a day count had been chosen.
  return { min: 0, max: 120, step: 5, unit: 'days', label: 'days of stores', empty: '' }
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
        <Row label="Idle here" value={<Figure value={port ? formatInt(port.crew_pool) : '—'} />} hairline={false} />
      </>
    )
  }
  if (verb === 'REPAIR') {
    const worst = Math.round(worstHullFraction(fleet) * 100)
    const yard = port && hasBuilding(port, 'shipyard')
    return (
      <>
        <Row label="Worst hull" value={<Figure value={formatPct(worst / 100, 0)} tone={worst < 50 ? 'danger' : 'ink'} size="figure" />} />
        <Row
          label="Shipyard"
          tone={yard ? 'default' : 'muted'}
          value={port ? (yard ? `Tier ${buildingTier(port, 'shipyard')}` : 'none here') : 'at sea'}
          hairline={false}
        />
      </>
    )
  }
  const stores = fleetStores(fleet)
  return (
    <>
      <Row label="Stores" value={<Figure value={formatVoyageDays(fleet.endurance_days)} size="figure" />} />
      <Row
        label="Aboard"
        value={<Figure value={`${stores.waterT.toFixed(0)} water · ${stores.foodT.toFixed(0)} food`} />}
        hairline={false}
      />
    </>
  )
}
