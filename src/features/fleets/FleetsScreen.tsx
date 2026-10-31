import { useState } from 'react'
import { Bar, CargoBar, DetailPage, FactsLine, IconDisc, Row, Sheet, type IconDiscTone, Clip } from '../../components/ui'
import { formatPct, formatVoyageDays } from '../../lib/format'
import { useShellState } from '../../app/shellState'
import { portNameOf, useWorld } from '../../live/worldStore'
import type { FleetView } from '../../lib/rpc'
import {
  fleetHoldTotal,
  fleetHoldUsed,
  fleetStatusTone,
  whereabouts,
  whereLine,
  worstHullFraction,
} from '../../domain/fleet'
import { routeCaption, routeOfFleet } from '../../domain/route'
import { WorldFailed, WorldLoading } from '../../live/WorldGate'
import { FleetFold } from './FleetFold'
import { fleetDue } from './fleetLine'
import { tabWord } from '../../app/navTabs'
import { useLocale, useT } from '../../lib/i18n'

// FLEETS — what you own, one row each, redrawn to docs/UI_DIRECTION.md §6 (§7 step 7).
//
// ── ONE FLEET, ONE PLACE ───────────────────────────────────────────────────────────────────────
// §2 item 11, measured: this screen showed the same fleet THREE times — a roster block
// (where / due / provision / hold / hull), the same data again as a seven-column table from 640px,
// and a collapsible card per fleet with an eight-column ships table that sheared at CREW and
// printed "Swipe the table for the rest." Plus `1/2 fleets · 1/8 ships` in the header, which RANK
// also printed. Now a fleet is one `Row` — status mark, name, where she is or where she is bound
// and when, and one caption line of the three figures that decide the next order: stores, hold,
// hull.
//
// ── PRESSING THE ROW OPENS HER PAGE (owner, 2026-10-31) ──────────────────────────────────────
// The owner's newest law, verbatim: *"everything has folded. enough with folding things. make
// everything small, compact and once clicked show new page popping up."* Row 89's unfold-under-the-
// row is therefore RETIRED — it re-flowed everything below the press, the one thing the press law
// forbids — and the fleet's ships, cargo and supplies now stand whole on the ONE pop-up page every
// other compact block uses (`DetailPage`): a fixed overlay with its own back press, so the row,
// the rows below it and the rail keep their boxes to the pixel while it is open.
//
// The row still SELECTS: it lights `accent` while its page is up, and the page is keyed by ID (the
// store hands out a new FleetView every half minute), so an open page survives a world read.
//
// ── THE CAPTAINS MOVED TO THE YOU TAB (owner row 181, 2026-10-20) ─────────────────────────
// 0160's roster stood at the foot of this screen until the owner asked for a personal tab and named
// captains in it (features/you/YouScreen.tsx). It is the SAME one face (src/live/YourCaptains.tsx),
// mounted there instead of here — not a copy, and not two places to read one list. This tab is what
// you own and where it is; who sails it is next door.
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
  // THE TITLE IS THE TAB'S OWN WORD (navTabs.tabWord) — one authority with the lit nav cell.
  const title = tabWord(useLocale(), '/fleets')
  // FIELDS, NOT THE STORE (worldStore.ts rule 4).
  const phase = useWorld((s) => s.phase)
  const fatal = useWorld((s) => s.fatal)
  const snapshot = useWorld((s) => s.snapshot)

  if (phase === 'failed') {
    return <WorldFailed title={title} refusal={fatal} />
  }
  if (phase !== 'ready' || !snapshot) {
    return <WorldLoading title={title} />
  }
  return <FleetsBody title={title} />
}

function FleetsBody({ title }: { title: string }) {
  const t = useT()
  const fleets = useWorld((s) => s.fleets)
  const portByCode = useWorld((s) => s.portByCode)
  const { nowMs } = useShellState()
  // 0092: THE ROUTE'S WORD on her row (`On route` / `Stopped` / `Paused`) — a READING of the served
  // route (src/domain/route), never a column: the route itself is COMMAND's (RouteFold.tsx). The
  // world read brings the routes with the fleets (worldStore.refresh), so this tab asks nothing.
  const routes = useWorld((s) => s.routes)
  // WHICH FLEET'S PAGE IS OPEN, BY ID (see the header). One page at a time, like every other compact
  // block; the row behind it never moves.
  const [openFleetId, setOpenFleetId] = useState<string | null>(null)
  const openFleet = fleets.find((f) => f.id === openFleetId) ?? null
  // The one authority for code → name (worldStore.portNameOf).
  const portName = (code: string) => portNameOf(portByCode, code)

  return (
    <Sheet title={title} data-testid="fleets">
      {fleets.length === 0 ? (
        <Row label={t('fleets.noFleets')} tone="muted" hairline={false} />
      ) : (
        fleets.map((fleet, i) => (
          <FleetRow
            key={fleet.id}
            fleet={fleet}
            where={[whereLine(whereabouts(fleet), portName), fleetDue(fleet, nowMs), routeCaption(routeOfFleet(routes, fleet.id))]
              .filter(Boolean)
              .join(' · ')}
            selected={openFleetId === fleet.id}
            last={i === fleets.length - 1}
            onOpen={() => setOpenFleetId(fleet.id)}
          />
        ))
      )}
      {openFleet !== null && (
        <DetailPage title={openFleet.name} onClose={() => setOpenFleetId(null)} data-testid="fleet-page">
          <FleetFold fleet={openFleet} />
        </DetailPage>
      )}
    </Sheet>
  )
}

/** The status mark's colour is the meaning domain/fleet gives the status — the same five names
 *  the design system's tones carry, so a section that knows no component can still say "trouble".
 *  Since 2026-10-01 the mark is a SHIP on a disc in that colour rather than a 10px dot: the same
 *  meaning, and a fleet now looks like a fleet ("it is like a text game"). */
const MARK: Record<ReturnType<typeof fleetStatusTone>, IconDiscTone> = {
  neutral: 'muted',
  accent: 'accent',
  success: 'success',
  warning: 'warning',
  danger: 'danger',
}

function FleetRow({
  fleet,
  where,
  selected,
  last,
  onOpen,
}: {
  fleet: FleetView
  /** `Lisbon`, `to Cádiz · 1.2 d`, `Lisbon · 2 h` — `whereLine` and `fleetDue`, joined by the caller. */
  where: string
  /** Her page is up. The row reads `accent` — §4.4: gold is "selected, yours". */
  selected: boolean
  last: boolean
  onOpen: () => void
}) {
  const t = useT()
  const used = fleetHoldUsed(fleet)
  const total = fleetHoldTotal(fleet)
  const hull = worstHullFraction(fleet)

  return (
    <Row
      mark={<IconDisc name="ship" tone={MARK[fleetStatusTone(fleet.status)]} label={fleet.status.toLowerCase()} />}
      /* WHERE SHE IS RIDES ON THE NAME'S LINE, not in the row's value slot. The value slot stands
         beside the WHOLE band, so with it filled the caption line under the name was squeezed to
         the label's width and the bars measured 12px — a mood ring. Composed as a stack (Row's
         own allowance: "a string, or a small stack the caller composes") the bars get the band. */
      label={
        <span className="flex items-baseline justify-between gap-3">
          <Clip>{fleet.name}</Clip>
          <span className="shrink-0 text-t-body text-ink">{where}</span>
        </span>
      }
      chevron
      tone={selected ? 'accent' : 'default'}
      onClick={onOpen}
      hairline={!last}
      data-testid="fleet-row"
    >
      {/* THE THREE FACTS THAT DECIDE THE NEXT ORDER, on one caption line: whether to sail is
          "how many days of supplies", whether to buy is "how much cargo space is left", whether to
          repair is "how sound is the worst hull". The figure stays beside each bar — a bar you cannot
          read exactly is a mood ring, and this is a ledger. */}
      {/* THE LINE WRAPS RATHER THAN OVERLAPS (2026-10-01). At 390px the three groups did not fit
          one line, the two bars were squeezed to nothing and `4 / 60 tons` was printed on top of
          `hull` (seen in the design pass's before-shot). On a phone the supplies figure takes its
          own line and each gauge keeps a floor — the width its word, a bar you can read and its
          figure need — so cargo and hull stack under it; from `sm` all three share one line. */}
      <FactsLine data-testid="fleet-row-bars">
        <span className="shrink-0 basis-full tabular-nums sm:basis-auto">{t('fleets.ofSupplies', { days: formatVoyageDays(fleet.endurance_days) })}</span>
        {/* ONE cargo gauge for the game (CargoBar): the basket panel on PORT draws the same one
            with its staged change washed on. */}
        <CargoBar used={used} total={total} free={fleet.free_hold} className="min-w-48 flex-1" />
        {/* §4.4: a hull that is merely sound is NEUTRAL — green is for gain, and a whole fleet
            painted green spends the one colour that means "cheap" on a hull that is fine. */}
        <span className="flex min-w-32 flex-1 items-center gap-3">
          <span className="shrink-0">{t('fleets.hull')}</span>
          <Bar
            pct={hull * 100}
            tone={hull < 0.4 ? 'danger' : hull < 0.75 ? 'warning' : 'neutral'}
            label={t('fleets.worstHull', { pct: formatPct(hull) })}
            figure={<span className="tabular-nums">{formatPct(hull)}</span>}
            className="min-w-0 flex-1"
          />
        </span>
      </FactsLine>
    </Row>
  )
}
