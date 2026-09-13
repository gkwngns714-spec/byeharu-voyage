import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Bar, Button, Figure, Row, SheetSection } from '../../components/ui'
import { formatOfTotal } from '../../lib/format'
import { portNameOf, useWorld } from '../../live/worldStore'
import { useShellState } from '../../app/shellState'
import type { FleetView } from '../../lib/rpc'
import { useCommandDraft, type CommandIntent } from '../../domain/order'
import { voyageFraction } from '../../domain/fleet'
import { FleetCargo } from './FleetCargo'
import { FleetShips } from './FleetShips'
import { FleetStores } from './FleetStores'
import { fleetBoundFor, fleetDue } from './fleetLine'
import { keepDays, useStandingOrder } from './standingOrder'

// ONE FLEET, UNFOLDED UNDER ITS ROW — owner row 89 (2026-09-13):
//
//     "fleets, i want to be folded not creating a new pop up page when clicking a ship/fleet.
//      when folded, ships cargo supplies should be in one page with three columns"
//
// ── §7B, ANSWERED BEFORE THE FIRST LINE ────────────────────────────────────────────────────────
// The CONCEPT: a fleet's three sides — ships, cargo, supplies — read together, in the list, under
// the row that names her. It LIVES in features/fleets because it is FLEETS' own composition of
// three faces that already exist (FleetShips, FleetCargo, FleetStores) and nothing outside this
// screen unfolds a fleet. The SECOND CALLER is implausible: MAP's fleet corner and COMMAND's fleet
// chip point at a fleet, they do not read her hulls, and if either ever wants to, the whole of
// this file is what they compose — not a copy of its grid. What would make it the WRONG SHAPE is
// a fourth thing folded in here (an order queue, a history) — that is a second screen wearing a
// fold, and the tell is a fourth column.
//
// ── WHY NOT THE INLINE TRAY ────────────────────────────────────────────────────────────────────
// `Tray mode="inline"` is in flow, which is the half of the rule that matters — but it is still a
// TRAY: a detent ladder (96 px · half the glass · all of it), a drag handle, a ✕, its own inner
// scroll box and a pinned action. An unfold has none of those to offer: it is as tall as what it
// holds, it scrolls with the sheet, and it closes by pressing the row it hangs from. Composing the
// tray here would have meant a fold with a Resize handle that resizes nothing the player wants.
// So this is a plain region: three `SheetSection`s in a grid, and one button at the foot.
//
// ── THE OWNER'S RULE, KEPT BY WHERE THIS IS MOUNTED ────────────────────────────────────────────
// Rows 6, 15, 25, 28, 45: pressing a control SELECTS; nothing at or above the press moves. This
// region is rendered by FleetsScreen IMMEDIATELY AFTER the pressed row, so the row and everything
// above it are where they were, and what is below moves down — which is what an unfold IS.
// tests/layout.spec.ts measures it at 390×844; tests/wide.layout.spec.ts at 1440×900.
//
// ── THREE COLUMNS ON A WIDE GLASS, ONE UNDER ANOTHER ON A PHONE ────────────────────────────────
// From `lg` (screenLayout.ts, the wide glass) the three sections stand side by side inside the
// 48 rem column — the owner's "one page with three columns". Below `lg` they stack, Ships then
// Cargo then Supplies, with the sheet's 24 px section rhythm between them. Each section is wrapped
// in its own cell so that `SheetSection`'s `first:mt-2` lands on all three alike and their tops
// agree to the pixel.
//
// ── THE TWO BUTTONS ────────────────────────────────────────────────────────────────────────────
// The keep button belongs to the SUPPLIES column and appears only when the stepper differs from
// what the server holds (a primary button that is disabled every time it is first seen is §2
// item 1's complaint). "Command <fleet>" is the hand-off this tab has always had — it points
// COMMAND at her — and it stands at the fold's foot, in flow, never pinned.

export function FleetFold({ fleet }: { fleet: FleetView }) {
  const portByCode = useWorld((s) => s.portByCode)
  const { nowMs } = useShellState()
  const navigate = useNavigate()
  const handOff = useCommandDraft((s) => s.handOff)
  const standing = useStandingOrder(fleet)

  // THE STEPPER'S DRAFT, seated on the served figure. Null means "what the server holds", so a
  // read that lands while the fold is open re-seats the stepper and a committed change needs no
  // effect to clear it: the draft is dropped the moment the server agrees with it.
  const served = standing.order?.days ?? 0
  const [draft, setDraft] = useState<number | null>(null)
  const days = draft ?? served

  // The draft is a structured INTENT (domain/order): the verb and the fleet, the pickers open.
  const command = (intent: CommandIntent) => {
    handOff(intent)
    navigate('/command')
  }
  const commit = () => {
    void standing.keep(days).then((ok) => {
      if (ok) setDraft(null)
    })
  }

  const fraction = voyageFraction(fleet)
  const bound = fleetBoundFor(fleet, (code) => (code ? portNameOf(portByCode, code) : null))

  return (
    // `flex flex-col` so the first section's `mt-2` cannot collapse through this box: MEASURED at
    // 390×844, without it the fold's own top edge sat 8px under the row it hangs from.
    <div role="region" aria-label={`${fleet.name} unfolded`} className="flex flex-col pb-4" data-testid="fleet-fold">
      {/* THE VOYAGE, only while there is one: where it is heading, how far along, and when. The
          ETA is the server's and the position its closed form — nothing here interpolates. */}
      {fleet.voyage && fraction !== null && (
        <Row label={`to ${bound}`} value={fleetDue(fleet, nowMs)} hairline={false} data-testid="fleet-passage">
          <Bar
            pct={fraction * 100}
            tone="info"
            label="how far along the voyage"
            figure={
              <Figure value={formatOfTotal(fleet.voyage.nm_done, fleet.voyage.total_nm)} unit="miles" />
            }
            className="mt-1"
          />
        </Row>
      )}

      <div className="space-y-6 lg:grid lg:grid-cols-3 lg:gap-6 lg:space-y-0">
        <div>
          <SheetSection heading="Ships" data-testid="fleet-fold-section">
            <FleetShips fleet={fleet} />
          </SheetSection>
        </div>
        <div>
          <SheetSection heading="Cargo" data-testid="fleet-fold-section">
            <FleetCargo fleet={fleet} />
          </SheetSection>
        </div>
        <div>
          <SheetSection heading="Supplies" data-testid="fleet-fold-section">
            <FleetStores
              fleet={fleet}
              order={standing.order}
              book={standing.book}
              days={days}
              onDays={setDraft}
              refusal={standing.refusal}
              onDismissRefusal={standing.dismissRefusal}
            />
            {draft !== null && days !== served && (
              <Button
                variant="primary"
                className="mt-3 w-full"
                busy={standing.busy}
                busyLabel="Saving…"
                onClick={commit}
                data-testid="fleet-keep"
              >
                {days === 0 ? 'Stop keeping supplies' : `Keep ${keepDays(days)}`}
              </Button>
            )}
          </SheetSection>
        </div>
      </div>

      <Button
        variant="primary"
        className="mt-6 w-full"
        onClick={() => command({ fleetId: fleet.id })}
        data-testid="fleet-command"
      >
        Command {fleet.name}
      </Button>
    </div>
  )
}
