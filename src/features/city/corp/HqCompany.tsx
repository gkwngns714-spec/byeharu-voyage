import { HeldRoom } from '../../../components/ui'
import type { SnapshotPort } from '../../../lib/rpc'
import { litAway, useAwayReport } from '../../../live/useAwayReport'
import { litRace, useNationRace } from '../../../live/useNationRace'
import { litSea, useSeaChoices } from '../../../live/useSeaChoices'
import { Bridge } from '../board/Bridge'
import { HqBoard } from '../board/HqBoard'
import { JobsAway } from '../board/JobsAway'
import { RaceBridge } from '../board/RaceBridge'
import { SeaChoiceCard } from '../board/SeaChoiceCard'
import { useBoard } from '../board/useBoard'
import { LedgerArea } from './LedgerArea'
import { WarehouseArea } from './WarehouseArea'
import { WorkerList } from './WorkerList'
import { FirstVoyageLine } from '../../../live/FirstVoyageLine'
import { GoalCard } from '../../../live/GoalCard'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE COMPANY ON HQ, IN ONE ORDER (docs/design/hq-corp-2026-11-24.md C1; the join of H1 and H2, 2026-11-24)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
//   RANK STRIP    her Rank and a bar to the next, what the next level opens, NET PER HOUR and its causes (board/Bridge.tsx)
//   (when there)  a choice at sea that waits for her (0486), and WHILE AWAY (0481): what her standing jobs did since she last pressed OK
//   WORKERS       every fleet and the land party, one row each on one action, the idle ones first with Assign (WorkerList.tsx)
//   BEST MOVES    the served board's cards (board/HqBoard.tsx)
//   STORAGE       the home warehouse (WarehouseArea.tsx)
//   LEDGER        the money by line (LedgerArea.tsx)
//   (when lit)    the country race (0484)
// The city's plates stand under it (CityScreen.tsx).
//
// EVERYTHING IS SAID ONCE. The board is read ONCE, here (useBoard: one world.hq_board question), and handed to the strip, the moves
// and the Ledger: no area asks it again. One per-hour figure (the strip's). One While away. A fleet is one row of the worker list;
// no second Fleets section.

/** `port`: HQ's city in hand, for the home warehouse; null while no city is in hand (the warehouse is then not drawn). */
export function HqCompany({ port }: { port: SnapshotPort | null }) {
  const board = useBoard()
  // 0481: her fleets' standing jobs (world.away_report; dark: null, and nothing of them is drawn)
  const awayRead = useAwayReport()
  const away = litAway(awayRead.view)
  // 0484: the country race (world.nation_race; dark: null, and nothing of it is drawn)
  const raceRead = useNationRace()
  const race = litRace(raceRead.view)
  // 0486: her choices at sea (world.sea_choices; dark: null, and nothing of them is drawn)
  const seaRead = useSeaChoices()
  const sea = litSea(seaRead.view)
  // NOTHING HERE MOVES BY ITSELF (2026-11-25). Best moves, the Storage and the Ledger are FIXED SHAPES: the same boxes before their read,
  // after it, and whatever it says. Three blocks cannot be: a choice at sea, the news from away and the country race are there only
  // when something happened or a switch is lit, which only their own read knows. Those hold the room they had last time while that
  // read is asked (HeldRoom.tsx); so does the worker list, for the rows only the Land's read knows. `asking` is the first answer still
  // on the wire, never the silent re-ask.
  const asking = (r: { view: unknown; loading: boolean }) => r.view === null && r.loading
  return (
    <div className="flex flex-col gap-6" data-testid="hq-company">
      <Bridge board={board} />
      {/* H3 (simplify S3): the goal card (the second ship, the ladder's step and its one press) and the starter chain's step stood over
          the Trade desk, which is gone; they stand under the Rank strip */}
      <div className="flex flex-col gap-2" data-testid="hq-goal">
        <GoalCard />
        <FirstVoyageLine />
      </div>
      <HeldRoom name="hq-sea" asking={asking(seaRead)} className="gap-6">
        {sea?.open.map((c) => <SeaChoiceCard key={c.id} c={c} />)}
      </HeldRoom>
      {/* the away block reads the sea's settled choices too, so its room is held until both have answered */}
      <HeldRoom name="hq-away" asking={asking(awayRead) || asking(seaRead)}>
        {away && <JobsAway report={away} sea={sea?.recent ?? []} />}
      </HeldRoom>
      <WorkerList />
      <HqBoard board={board} />
      {port && <WarehouseArea port={port} />}
      <LedgerArea rate={board.rate} asking={board.asking} />
      <HeldRoom name="hq-race" asking={asking(raceRead)}>
        {race && <RaceBridge race={race} />}
      </HeldRoom>
    </div>
  )
}
