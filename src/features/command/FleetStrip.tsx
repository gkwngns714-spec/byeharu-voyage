import type { ReactNode } from 'react'
import { Bar, Figure, Icon } from '../../components/ui'
import { fleetHoldTotal, fleetHoldUsed } from '../../domain/fleet'
import { formatOfTotal, formatVoyageDays, tonsWord } from '../../lib/format'
import type { FleetView } from '../../lib/rpc'
import { FleetPicker } from './FleetPicker'
import { useT } from '../../lib/i18n'

// THE FLEET STRIP (docs/COMMAND_DESK.md §3.1, §2.1) — which fleet the desk acts for, and her two
// deciding figures. Every face reads the fleet named here; an act at a place is offered only for
// the city she is docked at (the server refuses otherwise — the strip only names her).
//
// 2026-10-20: the fleet is ONE button, the picker (FleetPicker.tsx) — her flag, name, signal dot
// and ▾, opening the list of your fleets — where it was a chip per fleet with her where line. A
// press SELECTS and moves nothing; where she is now reads on the picker's rows. The figures stand
// beside the picker on the wide header and under it on the phone, exactly as before.

export function FleetStrip({
  fleets,
  onSelect,
  fleet,
  inline = false,
  trailing,
}: {
  fleets: readonly FleetView[]
  onSelect: (id: string) => void
  fleet: FleetView | null
  /** The wide desk's header: the picker and the two figures on ONE line (docs/COMMAND_DESK.md §3.9). */
  inline?: boolean
  /** The phone: what stands at the right of her name, in the picker's own 44-px row (the line that says where she is,
   *  buysell/TradeStatus.tsx): it costs the glass no line. */
  trailing?: ReactNode
}) {
  if (inline) {
    return (
      <div className="flex min-w-0 flex-1 items-center gap-6" data-testid="fleet-strip">
        <FleetPicker fleets={fleets} fleet={fleet} onSelect={onSelect} />
        {fleet && <FleetFigures fleet={fleet} wide />}
      </div>
    )
  }
  return (
    <div data-testid="fleet-strip">
      {/* The picker's own 16px of padding is pulled back to the gutter, so her name starts where the
          chips used to. One row of the 44 floor; the figures' 52 follow it. */}
      <div className="-ml-4 flex min-h-11 items-center gap-2">
        <FleetPicker fleets={fleets} fleet={fleet} onSelect={onSelect} />
        {trailing}
      </div>
      {fleet && <FleetFigures fleet={fleet} />}
    </div>
  )
}

/** The fleet's two deciding figures as GLYPH-FIGURES (the visual overhaul's slice 3: "[cask] 15.0 days", "[hold] 0 / 194 tons" with its bar,
 *  never the words "Supplies" and "Cargo" over them). The cask and the hold are the two marks slice 5 gave these facts on Fleets
 *  (`icons.ts`); each word stays the mark's accessible name and its tooltip.
 *
 *  EXACTLY THE ROW'S 52px ON A PHONE, ON THE SHEET, NOT ON A PANEL (tests/route.stopface.spec.ts, owner row 15): the line was a
 *  caption over a 28-px figure; it is now one line of mark and figure, no taller. On the wide header the two stand beside the
 *  picker, the figures at the page's 24-px figure (row 267) and each mark 20 px. */
function FleetFigures({ fleet, wide = false }: { fleet: FleetView; wide?: boolean }) {
  const t = useT()
  const used = fleetHoldUsed(fleet)
  const total = fleetHoldTotal(fleet)
  const of = formatOfTotal(used, total)
  return (
    <div
      className={wide ? 'flex shrink-0 items-center gap-6' : 'flex min-h-row min-w-0 items-center gap-4 py-1'}
      data-testid="command-line"
    >
      <span className="flex shrink-0 items-center gap-1.5" title={t('command.supplies')} data-testid="command-supplies">
        <span role="img" aria-label={t('command.supplies')} className="flex text-ink-muted" data-desk-mark="">
          <Icon name="cask" size={20} />
        </span>
        <Figure value={formatVoyageDays(fleet.endurance_days)} size="figure" />
      </span>
      <span className={`flex items-center gap-1.5 ${wide ? 'shrink-0' : 'min-w-0 flex-1'}`} title={t('command.cargo')} data-testid="command-cargo">
        <span role="img" aria-label={t('command.cargo')} className="flex text-ink-muted" data-desk-mark="">
          <Icon name="hold" size={20} />
        </span>
        <Figure value={of} unit={tonsWord(total)} size="figure" />
        <Bar
          pct={total > 0 ? (used / total) * 100 : 0}
          tone={fleet.free_hold <= 0 ? 'warning' : 'accent'}
          label={t('command.cargoBar', { of, word: tonsWord(total) })}
          className={wide ? 'ml-1 w-24' : 'ml-1 min-w-0 flex-1'}
        />
      </span>
    </div>
  )
}
