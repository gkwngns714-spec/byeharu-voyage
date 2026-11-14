import { useState } from 'react'
import { Note, Row } from '../../components/ui'
import type { FleetView } from '../../lib/rpc'
import { inBattle } from '../../domain/fleet'
import { FleetMore } from './FleetMore'
import { FleetShips } from './FleetShips'
import { RenameFleet } from './RenameFleet'
import { useT } from '../../lib/i18n'

// ONE FLEET'S PAGE: HER SHIPS, AND NOTHING ELSE — the owner, 2026-11-14: *"in fleets, when pressed a fleet, show only ships, then when
// i press the ship, show cargo and supplies."*
//
// ── WHAT THIS REPLACES ─────────────────────────────────────────────────────────────────────────
// Owner row 89 (2026-09-13) asked for "ships cargo supplies ... in one page with three columns", and until today this page stood them
// side by side under her totals, with the "If attacked" picker, a battle, Command and Rename under them. The newer order reverses the
// three columns: the page is TWO STEPS now.
//   1. Press a fleet: this page, her ships one row each (FleetShips.tsx).
//   2. Press a ship: her own page, her cargo and her supplies (FleetShipPage.tsx, mounted by FleetsScreen over this one).
//
// ── WHAT BELONGS TO THE FLEET AS A WHOLE ───────────────────────────────────────────────────────
// DECIDED BY DEFAULT (docs/dev-log/2026-11-14-fleet-ships.md): the voyage, the totals, "If attacked", a battle, Command, Rename and the
// ship places stay reachable from here, behind ONE plain row at the foot of the ships (`More`, FleetMore.tsx). The first thing seen is
// the ships; nothing a player could do before became impossible. While she is in a battle the row says so, so a fight is never hidden
// behind a word that does not name it.
//
// ── THE OWNER'S RULE, KEPT BY WHERE THIS IS MOUNTED ────────────────────────────────────────────
// Rows 6, 15, 25, 28, 45: pressing a control SELECTS; nothing at or above the press moves — and since 2026-10-31 nothing BELOW it
// moves either. This region stands on the fixed `DetailPage` overlay (FleetsScreen mounts it as `fleet-page`), and the ship's page and
// the More page are overlays over it in turn, so every list behind a press keeps its boxes. tests/fleets.ships.spec.ts walks the two
// steps; tests/layout.spec.ts and tests/wide.layout.spec.ts measure them.

export function FleetFold({ fleet, openShipId, onOpenShip }: { fleet: FleetView; openShipId: string | null; onOpenShip: (shipId: string) => void }) {
  const t = useT()
  const [more, setMore] = useState(false)

  return (
    // `flex flex-col` so the first row's margin cannot collapse through this box.
    <div role="region" aria-label={t('fleets.unfolded', { name: fleet.name })} className="flex flex-col pb-4" data-testid="fleet-fold">
      {fleet.ships.length === 0 ? (
        <>
          <Row label={t('fleets.noShips')} tone="muted" hairline={false} data-testid="fleet-no-ships" />
          {/* F5: the server leaves an empty fleet unable to sail; say so, and say how a ship comes to it */}
          <Note tone="neutral" data-testid="fleet-empty-how">
            {t('fleets.emptyFleet')}
          </Note>
          {/* 0354: an empty fleet keeps her name, and may take a new one */}
          <RenameFleet fleet={fleet} className="mt-4 w-full" />
        </>
      ) : (
        <>
          <FleetShips fleet={fleet} openShipId={openShipId} onOpenShip={onOpenShip} />
          {/* THE ONE DOOR to everything that is the fleet's as a whole (FleetMore.tsx): a plain row under the ships, parted from them by a rule. */}
          <Row
            label={t('fleets.more')}
            value={inBattle(fleet) ? <span className="text-t-caption text-warning">{t('fight.battle')}</span> : undefined}
            chevron
            tone={more ? 'accent' : 'muted'}
            onClick={() => setMore(true)}
            hairline={false}
            className="mt-2 border-t border-edge"
            data-testid="fleet-more"
          />
          {more && <FleetMore fleet={fleet} onClose={() => setMore(false)} />}
        </>
      )}
    </div>
  )
}
