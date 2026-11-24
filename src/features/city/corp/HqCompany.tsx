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
  const away = litAway(useAwayReport().view)
  // 0484: the country race (world.nation_race; dark: null, and nothing of it is drawn)
  const race = litRace(useNationRace().view)
  // 0486: her choices at sea (world.sea_choices; dark: null, and nothing of them is drawn)
  const sea = litSea(useSeaChoices().view)
  return (
    <div className="flex flex-col gap-6" data-testid="hq-company">
      <Bridge board={board} />
      {sea?.open.map((c) => <SeaChoiceCard key={c.id} c={c} />)}
      {away && <JobsAway report={away} sea={sea?.recent ?? []} />}
      <WorkerList />
      <HqBoard board={board} />
      {port && <WarehouseArea port={port} />}
      <LedgerArea rate={board.rate} />
      {race && <RaceBridge race={race} />}
    </div>
  )
}
