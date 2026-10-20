import { useEffect, useState } from 'react'
import { Button, Figure, Note, Row, Stepper, Tray, type TrayDetent, type TrayMode } from '../components/ui'
import { OrderCheck } from './orderCheck'
import type { StepOrder } from './useStepOrder'
import { fleetStores, worstHullFraction } from '../domain/fleet'
import { enumNaming } from '../domain/order'
import { hasBuilding } from '../domain/port'
import { formatInt, formatPct, formatVoyageDays } from '../lib/format'
import type { FleetView, SnapshotPort } from '../lib/rpc'
import { useT, t } from '../lib/i18n'

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
  mode,
  onClose,
}: {
  fleet: FleetView
  /** Where the ship is — the snapshot port, for the shipyard. */
  port: SnapshotPort | null
  step: StepOrder
  /** Where the tray stands — PORT's docked default; the MAP's city panel passes `side-next`. */
  mode?: TrayMode
  onClose: () => void
}) {
  const t = useT()
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
      mode={mode}
      data-testid="step-tray"
      action={
        <Button
          variant="primary"
          className="w-full"
          disabled={issuing || refused || (bound !== null && bound.max <= 0)}
          busy={issuing}
          busyLabel={t('ship.sending')}
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
  return t(verb === 'REPAIR' ? 'ship.repairShips' : 'ship.resupply')
}

function actLabel(verb: string, value: number, provisionFull: boolean): string {
  if (verb === 'REPAIR') return t('ship.repairTo', { n: formatInt(value) })
  return provisionFull ? t('ship.fillUp') : t('ship.resupplyN', { n: formatInt(value) })
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
    return { min: Math.min(now + 1, 100), max: 100, step: 5, unit: '%', label: t('ship.repairToLabel'), empty: t('ship.noDamage') }
  }
  // days — a floor of 0, not 1: nought days is FULL, and a floor of 1 would put "fill up"
  // out of reach of `−` the moment a day count had been chosen.
  return { min: 0, max: 120, step: 5, unit: t('ship.daysUnit'), label: t('ship.daysOf'), empty: '' }
}

/** The ship's state, in rows — the one figure this verb is a decision about, and the port fact it needs. */
function Reading({ fleet, port, verb }: { fleet: FleetView; port: SnapshotPort | null; verb: string }) {
  const t = useT()
  if (verb === 'REPAIR') {
    const worst = Math.round(worstHullFraction(fleet) * 100)
    const yard = port && hasBuilding(port, 'shipyard')
    return (
      <>
        {/* Row 86: damage TAKEN, as PortShipyard prints it — `13% damaged` is a reading; `87%` was a quiz. */}
        <Row label={t('ship.damage')} value={<Figure value={formatPct(1 - worst / 100, 0)} unit={t('ship.damaged')} tone={worst < 50 ? 'danger' : 'ink'} size="figure" />} />
        <Row
          label={t('ship.repairHere')}
          tone={yard ? 'default' : 'muted'}
          value={port ? t(yard ? 'ship.yes' : 'ship.noRepair') : t('ship.atSea')}
          hairline={false}
        />
      </>
    )
  }
  const stores = fleetStores(fleet)
  return (
    <>
      <Row label={t('ship.supplies')} value={<Figure value={formatVoyageDays(fleet.endurance_days)} size="figure" />} />
      <Row
        label={t('ship.onBoard')}
        value={<Figure value={t('ship.waterFood', { water: stores.waterT.toFixed(0), food: stores.foodT.toFixed(0) })} />}
        hairline={false}
      />
    </>
  )
}
