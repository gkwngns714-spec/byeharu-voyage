import { useState } from 'react'
import { Bar, Row, Sheet } from '../../components/ui'
import { formatOfTotal, formatPct, formatVoyageDays } from '../../lib/format'
import { useShellState } from '../../app/shellState'
import { portNameOf, useWorld } from '../../live/worldStore'
import type { FleetView } from '../../lib/rpc'
import { fleetHoldTotal, fleetHoldUsed, fleetStatusTone, worstHullFraction } from '../../domain/fleet'
import { WorldFailed, WorldLoading } from '../../live/WorldGate'
import { FleetTray } from './FleetTray'
import { fleetDue, fleetWhere } from './fleetLine'

// FLEETS — what you own, one row each, redrawn to docs/UI_DIRECTION.md §6 (§7 step 7).
//
// ── ONE FLEET, ONE PLACE ───────────────────────────────────────────────────────────────────────
// §2 item 11, measured: this screen showed the same fleet THREE times — a roster block
// (where / due / provision / hold / hull), the same data again as a seven-column table from 640px,
// and a collapsible card per fleet with an eight-column ships table that sheared at CREW and
// printed "Swipe the table for the rest." Plus `1/2 fleets · 1/8 ships` in the header, which RANK
// also printed. Now a fleet is one `Row` — status mark, name, where she is or where she is bound
// and when, and one caption line of the three figures that decide the next order: stores, hold,
// hull. Tapping the row opens her in a `Tray` (FleetTray.tsx); nothing on the list moves.
//
// ── WHAT WENT, AND WHY ─────────────────────────────────────────────────────────────────────────
// The header counts (limits are not assets; a refusal says so when one bites). The ≥640px table
// (the same served fleet drawn twice is two authorities for one reading). The "Standing orders /
// The book is empty. Not an error — a state." card (the order is a number on the fleet's stores
// face now — standingOrder.ts). The `Read 1s ago · local` footer (§5: no screen prints a readAt
// or a mode). Load and Free, which were Hold twice. The glossary behind the title's dot: t, kn and
// days ride on the figures as units (`Figure`), which is where a unit is read.
//
// ── THE NUMBERS ARE THE SERVER'S ───────────────────────────────────────────────────────────────
// `speed_kn`, `endurance_days` and `free_hold` are computed inside the transaction that owns them
// and are the figures SAIL and BUY refuse on. What is derived here is a ratio and a fold across
// the hulls of one fleet (domain/fleet), each cited to the SQL it agrees with. Reading is how time
// passes: AppShell re-reads every half minute and on focus, and that read is what lands a voyage —
// so a countdown past its instant says "due", never "arrived".

export function FleetsScreen() {
  // FIELDS, NOT THE STORE (worldStore.ts rule 4).
  const phase = useWorld((s) => s.phase)
  const fatal = useWorld((s) => s.fatal)
  const snapshot = useWorld((s) => s.snapshot)

  if (phase === 'failed') {
    return <WorldFailed eyebrow="Assets" title="Fleets" refusal={fatal} />
  }
  if (phase !== 'ready' || !snapshot) {
    return <WorldLoading eyebrow="Assets" title="Fleets" subtitle="What you own, and the state it is in." panels={3} />
  }
  return <FleetsBody />
}

function FleetsBody() {
  const fleets = useWorld((s) => s.fleets)
  const portByCode = useWorld((s) => s.portByCode)
  const { nowMs } = useShellState()
  // WHICH FLEET IS OPEN, BY ID — not by reference. The store re-reads the world every half minute
  // and hands out a new FleetView each time; looking her up by id on every render is what keeps
  // the open tray reading the live fleet rather than the one that was tapped.
  const [openId, setOpenId] = useState<string | null>(null)
  const open = openId ? (fleets.find((f) => f.id === openId) ?? null) : null
  // The one authority for code → name (worldStore.portNameOf).
  const portName = (code: string | null) => (code ? portNameOf(portByCode, code) : null)

  return (
    <Sheet title="Fleets" data-testid="fleets">
      {fleets.length === 0 ? (
        <Row label="The house owns nothing that floats." tone="muted" hairline={false} />
      ) : (
        fleets.map((fleet, i) => (
          <FleetRow
            key={fleet.id}
            fleet={fleet}
            where={[fleetWhere(fleet, portName), fleetDue(fleet, nowMs)].filter(Boolean).join(' · ')}
            last={i === fleets.length - 1}
            onOpen={() => setOpenId(fleet.id)}
          />
        ))
      )}

      {open && <FleetTray fleet={open} onClose={() => setOpenId(null)} />}
    </Sheet>
  )
}

/** The status mark's colour is the meaning domain/fleet gives the status — the same five names
 *  the design system's tones carry, so a section that knows no component can still say "trouble". */
const MARK: Record<ReturnType<typeof fleetStatusTone>, string> = {
  neutral: 'bg-ink-faint',
  accent: 'bg-accent',
  success: 'bg-success',
  warning: 'bg-warning',
  danger: 'bg-danger',
}

function FleetRow({
  fleet,
  where,
  last,
  onOpen,
}: {
  fleet: FleetView
  /** `Lisbon`, `to Cádiz · 1.2 d`, `Lisbon · 2 h` — fleetLine.ts's words, joined by the caller. */
  where: string
  last: boolean
  onOpen: () => void
}) {
  const used = fleetHoldUsed(fleet)
  const total = fleetHoldTotal(fleet)
  const hull = worstHullFraction(fleet)

  return (
    <Row
      mark={<span aria-label={fleet.status.toLowerCase()} className={`h-2.5 w-2.5 rounded-chip ${MARK[fleetStatusTone(fleet.status)]}`} />}
      /* WHERE SHE IS RIDES ON THE NAME'S LINE, not in the row's value slot. The value slot stands
         beside the WHOLE band, so with it filled the caption line under the name was squeezed to
         the label's width and the bars measured 12px — a mood ring. Composed as a stack (Row's
         own allowance: "a string, or a small stack the caller composes") the bars get the band. */
      label={
        <span className="flex items-baseline justify-between gap-3">
          <span className="truncate">{fleet.name}</span>
          <span className="shrink-0 text-t-body text-ink">{where}</span>
        </span>
      }
      chevron
      onClick={onOpen}
      hairline={!last}
      data-testid="fleet-row"
    >
      {/* THE THREE FACTS THAT DECIDE THE NEXT ORDER, on one caption line: whether to sail is
          "how many days of stores", whether to buy is "how much room is left", whether to repair
          is "how sound is the worst hull". The figure stays beside each bar — a bar you cannot
          read exactly is a mood ring, and this is a ledger. */}
      <span className="mt-1 flex items-center gap-3 text-t-caption text-ink-faint" data-testid="fleet-row-bars">
        <span className="shrink-0 tabular-nums">{formatVoyageDays(fleet.endurance_days)}</span>
        <Bar
          pct={total > 0 ? (used / total) * 100 : 0}
          tone={fleet.free_hold <= 0 ? 'warning' : 'accent'}
          label={`hold, ${formatOfTotal(used, total)} tuns`}
          figure={<span className="tabular-nums">{formatOfTotal(used, total)} t</span>}
          className="min-w-0 flex-1"
        />
        {/* §4.4: a hull that is merely sound is NEUTRAL — green is for gain, and a whole fleet
            painted green spends the one colour that means "cheap" on a hull that is fine. */}
        <span className="shrink-0">hull</span>
        <Bar
          pct={hull * 100}
          tone={hull < 0.4 ? 'danger' : hull < 0.75 ? 'warning' : 'neutral'}
          label={`worst hull, ${formatPct(hull)}`}
          figure={<span className="tabular-nums">{formatPct(hull)}</span>}
          className="min-w-0 flex-1"
        />
      </span>
    </Row>
  )
}
