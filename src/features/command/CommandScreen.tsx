import { useEffect, useMemo } from 'react'
import { Chip, Note, Row, Sheet, SheetSection } from '../../components/ui'
import { Queue } from './Queue'
import { useCommandDraft } from '../../domain/order'
import { formatInt, formatVoyageDays } from '../../lib/format'
import { portNameOf, useWorld } from '../../live/worldStore'
import type { FleetView, SnapshotPort } from '../../lib/rpc'

// COMMAND — whose orders, and what she has been told. Nothing here composes a verb any more.
//
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A VERB'S DOORWAY BELONGS WHERE ITS ACT HAPPENS (the owner, 2026-09-09).
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// *"In command, there are so many things, like buy, sell, fit, take etc. Buy and sell should be
// in port - market. Get it? they should be located accordingly at different locations - the
// command."*
//
// This screen drew twelve verb tiles in one grid — Sail, Buy, Sell, Provision, Hire, Make, Store,
// Take, Build, Fit, Unfit, Repair — and then one question for whichever was pressed. Every one of
// those acts happens somewhere, and that somewhere already has a face: BUY and SELL on PORT's
// Trade face, STORE and TAKE on its Store face, MAKE on Craft, BUILD on Yard, HIRE on the Inn,
// REPAIR at the Shipyard, PROVISION on the quay, SAIL on the MAP. So the grid is gone, and with it
// the trade question, the sail question and the step question this file used to mount; the step
// question moved to PORT with the two faces that ask it (features/port/StepQuestion.tsx).
//
// WHAT IS LEFT IS THE ONE THING THAT BELONGS TO NO BUILDING: which hull is in hand, and her queue
// — the orders she has been given, the halt if one of them refused, and the two acts the queue
// itself owns (CANCEL, CLEAR — domain/order's QUEUE_VERBS). The grammar, the door (`cmd.issue`)
// and the judge (`cmd.preview`) did not move: every doorway still composes through `domain/order`
// and issues through `worldStore.issue`. Only the entry points moved.
//
// `useCommandDraft` still holds WHICH FLEET is in hand (the map's tap and FLEETS' "Command her"
// point it here); its verb and argument fields have no writer left on any screen.

export function CommandScreen() {
  const phase = useWorld((s) => s.phase)
  const fatal = useWorld((s) => s.fatal)
  const snapshot = useWorld((s) => s.snapshot)
  const fleets = useWorld((s) => s.fleets)
  const portByCode = useWorld((s) => s.portByCode)
  const busy = useWorld((s) => s.busy)
  const readAt = useWorld((s) => s.readAt)
  const open = useWorld((s) => s.open)
  const cancel = useWorld((s) => s.cancel)
  const clearQueue = useWorld((s) => s.clear)

  const fleetId = useCommandDraft((s) => s.fleetId)
  const selectFleet = useCommandDraft((s) => s.selectFleet)

  useEffect(() => {
    void open()
  }, [open])

  const fleet = useMemo(() => fleets.find((f) => f.id === fleetId), [fleets, fleetId])
  useEffect(() => {
    if (fleet) return
    const first = fleets.find((f) => f.status === 'DOCKED') ?? fleets[0]
    if (first) selectFleet(first.id)
  }, [fleet, fleets, selectFleet])

  if (phase === 'failed' && fatal) {
    return (
      <Sheet title="Command">
        <Note tone="danger" code={fatal.code}>{fatal.sentence}</Note>
      </Sheet>
    )
  }
  if (!snapshot) {
    return (
      <Sheet title="Command">
        <Row label="Opening the world…" tone="muted" hairline={false} />
      </Sheet>
    )
  }
  if (fleets.length === 0) {
    return (
      <Sheet title="Command">
        <Note tone="neutral">There is nothing to command yet. A house founds its first fleet before it can give an order.</Note>
      </Sheet>
    )
  }

  return (
    <Sheet title="Command" data-testid="command">
      {/* WHOSE ORDERS — fleet chips scroll sideways; pressing one SELECTS her and moves nothing. */}
      <div className="-mx-gutter flex gap-2 overflow-x-auto px-gutter pb-1">
        {fleets.map((f) => (
          <Chip key={f.id} on={f.id === fleetId} onClick={() => selectFleet(f.id)} className="shrink-0 whitespace-nowrap">
            {f.name} · {whereOf(f, portByCode)}
          </Chip>
        ))}
      </div>

      {fleet && (
        <>
          {/* HER ONE LINE: how far she can sail, and her room. */}
          <Row label={fleetLine(fleet)} hairline={false} data-testid="command-line" />
          <SheetSection heading="Orders" data-testid="command-queue">
            <Queue
              fleet={fleet}
              busy={busy}
              readAt={readAt}
              onCancel={(seq) => void cancel(fleet.id, seq)}
              onClear={() => void clearQueue(fleet.id)}
            />
          </SheetSection>
        </>
      )}
    </Sheet>
  )
}

/** Where a fleet lies or is bound, in a word — for the chip. */
function whereOf(f: FleetView, portByCode: Record<string, SnapshotPort>): string {
  if (f.port) return portNameOf(portByCode, f.port)
  if (f.voyage) return `→ ${f.voyage.to ? portNameOf(portByCode, f.voyage.to) : 'sea'}`
  if (f.anchor) return `at anchor`
  return f.status.toLowerCase()
}

/** The two facts a first glance wants: how far she can sail, and her room. */
function fleetLine(fleet: FleetView): string {
  return `${formatVoyageDays(fleet.endurance_days)} stores · ${formatInt(fleet.free_hold)} t free`
}
