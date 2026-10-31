import { useNavigate } from 'react-router-dom'
import { Bar, Button, Figure, Row, SectionColumns, SheetSection } from '../../components/ui'
import { formatOfTotal } from '../../lib/format'
import { portNameOf, useWorld } from '../../live/worldStore'
import { useShellState } from '../../app/shellState'
import type { FleetView } from '../../lib/rpc'
import { useCommandDraft, type CommandIntent } from '../../domain/order'
import { voyageFraction, whereabouts, whereLine } from '../../domain/fleet'
import { FleetCargo } from './FleetCargo'
import { FleetShips } from './FleetShips'
import { FleetStores } from './FleetStores'
import { fleetDue } from './fleetLine'
import { useT } from '../../lib/i18n'

// ONE FLEET'S PAGE — owner row 89's SHAPE (2026-09-13): *"when folded, ships cargo supplies should
// be in one page with three columns"* — on the owner's 2026-10-31 mechanism: *"everything has
// folded. enough with folding things. make everything small, compact and once clicked show new
// page popping up."* The three faces therefore stand whole on `DetailPage` (FleetsScreen mounts
// this component inside it as `fleet-page`), never unfolded under the row.
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
// ── WHY A PLAIN REGION ON A PAGE, NOT A TRAY ───────────────────────────────────────────────────
// A TRAY brings a detent ladder (96 px · half the glass · all of it), a drag handle, a ✕, its own
// inner scroll box and a pinned action — none of which suit a block that is simply as tall as what
// it holds. The `DetailPage` already brings the one scroll, the title and the back press, so this
// stays a plain region: three `SheetSection`s in a grid, and one button at the foot.
//
// ── THE OWNER'S RULE, KEPT BY WHERE THIS IS MOUNTED ────────────────────────────────────────────
// Rows 6, 15, 25, 28, 45: pressing a control SELECTS; nothing at or above the press moves — and
// since 2026-10-31 nothing BELOW it moves either. This region stands on the fixed `DetailPage`
// overlay, so the whole list behind it keeps its boxes. tests/layout.spec.ts measures the phone
// page and the unmoved list at 390×844; tests/wide.layout.spec.ts its three columns at 1440×900.
//
// ── THREE COLUMNS ON A WIDE GLASS, ONE UNDER ANOTHER ON A PHONE ────────────────────────────────
// From `lg` (screenLayout.ts, the wide glass) the three sections stand side by side inside the
// 48 rem column — the owner's "one page with three columns". Below `lg` they stack, Ships then
// Cargo then Supplies, with the sheet's 24 px section rhythm between them. Each section is wrapped
// in its own cell so that `SheetSection`'s `first:mt-2` lands on all three alike and their tops
// agree to the pixel.
//
// ── THE ONE BUTTON ────────────────────────────────────────────────────────────────────────────
// "Command <fleet>" is the hand-off this tab has always had — it points COMMAND at her — and it
// stands at the fold's foot, in flow, never pinned. (The keep button went with the standing order,
// owner row 203 / 0225: supplies are bought automatically at every SAIL.)

export function FleetFold({ fleet }: { fleet: FleetView }) {
  const t = useT()
  const portByCode = useWorld((s) => s.portByCode)
  const { nowMs } = useShellState()
  const navigate = useNavigate()
  const handOff = useCommandDraft((s) => s.handOff)

  // The draft is a structured INTENT (domain/order): the verb and the fleet, the pickers open.
  const command = (intent: CommandIntent) => {
    handOff(intent)
    navigate('/command')
  }

  const fraction = voyageFraction(fleet)
  const where = whereLine(whereabouts(fleet), (code) => portNameOf(portByCode, code))

  return (
    // `flex flex-col` so the first section's `mt-2` cannot collapse through this box: MEASURED at
    // 390×844, without it the fold's own top edge sat 8px under the row it hangs from.
    <div role="region" aria-label={t('fleets.unfolded', { name: fleet.name })} className="flex flex-col pb-4" data-testid="fleet-fold">
      {/* THE VOYAGE, only while there is one: where it is heading, how far along, and when. The
          ETA is the server's and the position its closed form — nothing here interpolates. */}
      {fleet.voyage && fraction !== null && (
        <Row label={where} value={fleetDue(fleet, nowMs)} hairline={false} data-testid="fleet-passage">
          <Bar
            pct={fraction * 100}
            tone="info"
            label={t('fleets.howFar')}
            figure={
              <Figure value={formatOfTotal(fleet.voyage.nm_done, fleet.voyage.total_nm)} unit={t('fleets.unitMiles')} />
            }
            className="mt-1"
          />
        </Row>
      )}

      <SectionColumns count={3}>
        <SheetSection heading={t('fleets.ships')} data-testid="fleet-fold-section">
          <FleetShips fleet={fleet} />
        </SheetSection>
        <SheetSection heading={t('fleets.cargo')} data-testid="fleet-fold-section">
          <FleetCargo fleet={fleet} />
        </SheetSection>
        <SheetSection heading={t('fleets.supplies')} data-testid="fleet-fold-section">
          <FleetStores fleet={fleet} />
        </SheetSection>
      </SectionColumns>

      <Button
        variant="primary"
        className="mt-6 w-full"
        onClick={() => command({ fleetId: fleet.id })}
        data-testid="fleet-command"
      >
        {t('fleets.command', { name: fleet.name })}
      </Button>
    </div>
  )
}
