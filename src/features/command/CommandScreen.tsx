import { useEffect, useMemo } from 'react'
import { Bar, Chip, Figure, Note, Row, Sheet, SheetSection } from '../../components/ui'
import { Queue } from './Queue'
import { RouteFold } from './RouteFold'
import { useCommandDraft } from '../../domain/order'
import { formatOfTotal, formatVoyageDays, tonsWord } from '../../lib/format'
import { fleetHoldTotal, fleetHoldUsed } from '../../domain/fleet'
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
// 2026-09-30 (0092, owner row 106): her STANDING ROUTE stands above the queue as one folded row —
// the one thing on this sheet that writes orders by itself, and only into this same queue.
//
// `useCommandDraft` still holds WHICH FLEET is in hand (the map's tap and FLEETS' "Command her"
// point it here); its verb and argument fields have no writer left on any screen.

export function CommandScreen() {
  const phase = useWorld((s) => s.phase)
  const fatal = useWorld((s) => s.fatal)
  const snapshot = useWorld((s) => s.snapshot)
  const fleets = useWorld((s) => s.fleets)
  const portByCode = useWorld((s) => s.portByCode)
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
        <Row label="Loading…" tone="muted" hairline={false} />
      </Sheet>
    )
  }
  if (fleets.length === 0) {
    return (
      <Sheet title="Command">
        <Note tone="neutral">No fleets yet. Start your company to get your first one.</Note>
      </Sheet>
    )
  }

  return (
    <Sheet title="Command" data-testid="command">
      {/* WHOSE ORDERS — fleet chips scroll sideways; pressing one SELECTS it and moves nothing. */}
      <div className="-mx-gutter flex gap-2 overflow-x-auto px-gutter pb-1">
        {fleets.map((f) => (
          <Chip key={f.id} on={f.id === fleetId} onClick={() => selectFleet(f.id)} className="shrink-0 whitespace-nowrap">
            {f.name} · {whereOf(f, portByCode)}
          </Chip>
        ))}
      </div>

      {fleet && (
        <>
          {/* ITS TWO FIGURES: how long it can sail, and its cargo — each with what it is out of
              (docs/WORDS.md law 2). They were ONE SENTENCE (`Supplies 15.0 days · Cargo 4 / 60
              tons`) until 2026-10-01, when the owner said the game "is like a text game": two
              numbers that decide the next order are figures, not prose, and cargo is a share, so
              it is also a bar. */}
          <FleetFigures fleet={fleet} />
          {/* 0092: HER ROUTE, one row above her queue — the standing order that writes the queue when
              it runs dry in port (RouteFold.tsx). It folds in place; the queue moves down. */}
          <RouteFold fleet={fleet} />
          {/* The queue's ✕ and Clear are busy only while their own press is on the wire (Queue.tsx
              wears the one `usePress`), so the verbs hand their promise down rather than a
              world-read flag — a background read never greys a control (owner, 2026-09-30). */}
          <SheetSection heading="Orders" surface data-testid="command-queue">
            <Queue
              fleet={fleet}
              readAt={readAt}
              onCancel={(seq) => cancel(fleet.id, seq)}
              onClear={() => clearQueue(fleet.id)}
            />
          </SheetSection>
        </>
      )}
    </Sheet>
  )
}

/** The fleet's two deciding figures, side by side — a caption over each, the cargo share drawn as a
 *  bar beside its figure (warning once the served free hold is gone).
 *
 *  EXACTLY THE ROW'S 52px, ON THE SHEET, NOT ON A PANEL. A first cut seated these on a `surface`
 *  panel with the figures at `t-figure` over a bar: 56px taller, and that was enough to push the
 *  route editor's port chips out of the glass, so a press there scrolled the sheet and the stops
 *  under the finger moved (tests/route.stopface.spec.ts, owner row 15). Caption 16 + figure 28 +
 *  8 of padding is the 52 the sentence stood in, so nothing below it moved by one pixel. */
function FleetFigures({ fleet }: { fleet: FleetView }) {
  const used = fleetHoldUsed(fleet)
  const total = fleetHoldTotal(fleet)
  return (
    <div className="grid min-h-row grid-cols-2 gap-4 py-1" data-testid="command-line">
      <div>
        <span className="block text-t-caption text-ink-faint">Supplies</span>
        <Figure value={formatVoyageDays(fleet.endurance_days)} size="figure" />
      </div>
      <div className="min-w-0">
        <span className="block text-t-caption text-ink-faint">Cargo</span>
        <span className="flex items-center gap-2">
          <Figure value={formatOfTotal(used, total)} unit={tonsWord(total)} size="figure" />
          <Bar
            pct={total > 0 ? (used / total) * 100 : 0}
            tone={fleet.free_hold <= 0 ? 'warning' : 'accent'}
            label={`cargo, ${formatOfTotal(used, total)} ${tonsWord(total)}`}
            className="min-w-0 flex-1"
          />
        </span>
      </div>
    </div>
  )
}

/** Where a fleet is or is heading, in a word — for the chip. */
function whereOf(f: FleetView, portByCode: Record<string, SnapshotPort>): string {
  if (f.port) return portNameOf(portByCode, f.port)
  if (f.voyage) return `→ ${f.voyage.to ? portNameOf(portByCode, f.voyage.to) : 'sea'}`
  if (f.anchor) return `anchored`
  return f.status.toLowerCase()
}
