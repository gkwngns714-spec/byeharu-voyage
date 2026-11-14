import { useNavigate } from 'react-router-dom'
import { Bar, Button, DetailPage, Figure, Row, SheetSection } from '../../components/ui'
import { formatOfTotal } from '../../lib/format'
import { portNameOf, useWorld } from '../../live/worldStore'
import { useShellState } from '../../app/shellState'
import type { FleetView } from '../../lib/rpc'
import { useCommandDraft, type CommandIntent } from '../../domain/order'
import { inBattle, voyageFraction, whereabouts, whereLine } from '../../domain/fleet'
import { FleetPlaces } from './FleetShips'
import { FleetTotals } from './FleetTotals'
import { RenameFleet } from './RenameFleet'
import { fleetDue } from './fleetLine'
import { RaidOrder } from '../../live/RaidOrder'
import { BattleCard } from '../../live/BattleCard'
import { useT } from '../../lib/i18n'

// THE FLEET AS A WHOLE, ONE PRESS BEHIND HER SHIPS — the owner, 2026-11-14: *"in fleets, when pressed a fleet, show only ships"*.
//
// Everything a pressed fleet showed that is NOT a ship and is not one ship's cargo or supplies stands here, behind the one `More` row at
// the foot of her ships (FleetFold.tsx). DECIDED BY DEFAULT (docs/dev-log/2026-11-14-fleet-ships.md): nothing a player could do on the
// fleet's page was dropped; it is one press further, so the first thing seen is the ships and nothing else.
//
//   · the voyage, while there is one: where she is bound, how far along, and when (the server's ETA and its closed-form position);
//   · her totals (0354, served): attack, hull, crew, wages, wave resistance, the slowest ship, a ship short of hands;
//   · "If attacked" (0353, live/RaidOrder): Fight, Flee, Pay. Draws nothing while orders are dark;
//   · a battle she is in (0357, live/BattleCard), mounted only while she is in one;
//   · Command, the hand-off to the Trade tab this page has always had, and Rename (0354);
//   · her places (F5): the empty ones and the locked ones, with the one Buy.
export function FleetMore({ fleet, onClose }: { fleet: FleetView; onClose: () => void }) {
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
    <DetailPage title={fleet.name} word={t('fleets.more')} onClose={onClose} data-testid="fleet-more-page">
      <div className="flex flex-col pb-4">
        {/* THE VOYAGE, only while there is one: where it is heading, how far along, and when. The
            ETA is the server's and the position its closed form — nothing here interpolates. */}
        {fleet.voyage && fraction !== null && (
          <Row label={where} value={fleetDue(fleet, nowMs)} hairline={false} data-testid="fleet-passage">
            <Bar
              pct={fraction * 100}
              tone="info"
              label={t('fleets.howFar')}
              figure={<Figure value={formatOfTotal(fleet.voyage.nm_done, fleet.voyage.total_nm)} unit={t('fleets.unitMiles')} />}
              className="mt-1"
            />
          </Row>
        )}

        {/* 0354: what the fleet adds up to */}
        <FleetTotals fleet={fleet} />

        {/* 0353: her standing order when raiders close (Fight, Flee, Pay). Draws nothing while orders are dark. */}
        <RaidOrder fleetId={fleet.id} className="mt-4" />

        {/* 0357: a battle she is in, round by round. Mounted (and its read asked) only while she is in one. */}
        {inBattle(fleet) && <BattleCard fleetId={fleet.id} className="mt-6" />}

        {/* 0354: Rename stands beside the hand-off, on its line */}
        <div className="mt-6 flex flex-wrap gap-3">
          <Button variant="primary" className="flex-1" onClick={() => command({ fleetId: fleet.id })} data-testid="fleet-command">
            {t('fleets.command', { name: fleet.name })}
          </Button>
          <RenameFleet fleet={fleet} />
        </div>

        {/* F5: the places she has not filled, and how the locked ones open */}
        <SheetSection heading={t('fleets.room')} data-testid="fleet-more-room">
          <FleetPlaces fleet={fleet} />
        </SheetSection>
      </div>
    </DetailPage>
  )
}
