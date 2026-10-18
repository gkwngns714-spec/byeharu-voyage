import { useEffect, useMemo, useState } from 'react'
import { Note, Row, Segmented, Sheet } from '../../components/ui'
import { useCommandDraft } from '../../domain/order'
import { useWorld } from '../../live/worldStore'
import { useDeskGood } from '../../store/deskGood'
import { DESK_FACES, useDeskView, type DeskFace } from './deskView'
import { FleetStrip } from './FleetStrip'
import { DeskTrade } from './markets/DeskTrade'
import { GoodPage } from './markets/GoodPage'
import { Markets } from './markets/Markets'
import { Plans } from './plans/Plans'

// COMMAND — THE DESK (docs/COMMAND_DESK.md, 2026-10-18). The owner, 2026-10-17: *"i want you to delete
// port tab, and focus on command tab. it will be like stock trading screen, with buy and sell plans,
// seeing charts of each trade goods that i click, setting up trade routes for my fleet, investing, and
// all … stylish - modern - sophisticated yet concise simple."*
//
// THE SHELL: the fleet strip (which fleet, where it is, its two figures), the faces (deskView.ts — the
// ones built: Markets · Plans), and the face. A good pressed on Markets opens its page in ONE slot (a
// tray; beside the column on a wide glass); the page's Buy / Sell cell turns that slot over to THE trade
// tray, and closing it returns to the page. One state says which stands, as PORT's board keeps its own.
//
// What follows is this screen's history before the desk. The rule it records still holds: a verb that
// happens at a place is offered only where the fleet is docked (§2.1).
//
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
// question moved to PORT with the two faces that ask it (live/StepQuestion.tsx, moved out of features/port 2026-10-16 when the map city panel composed the Inn).
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
  const goodByCode = useWorld((s) => s.goodByCode)
  const open = useWorld((s) => s.open)

  const fleetId = useCommandDraft((s) => s.fleetId)
  const selectFleet = useCommandDraft((s) => s.selectFleet)
  const face = useDeskView((s) => s.face)
  const turnTo = useDeskView((s) => s.turnTo)
  const goodCode = useDeskGood((s) => s.code)
  // WHICH TRAY STANDS IN THE SLOT: the good's page, or the trade tray it handed over to.
  const [trading, setTrading] = useState<{
    code: string
    intent: 'buy' | 'sell'
  } | null>(null)

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
        <Note tone="danger" code={fatal.code}>
          {fatal.sentence}
        </Note>
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

  const good = goodCode ? (goodByCode[goodCode] ?? null) : null
  const tradingHere = trading && fleet && fleet.status === 'DOCKED' && trading.code === goodCode ? trading : null

  return (
    <Sheet title="Command" data-testid="command">
      <FleetStrip fleets={fleets} fleetId={fleetId} onSelect={selectFleet} fleet={fleet ?? null} />
      {/* THE FACES (deskView.ts): one row in the body, not in the sticky title bar — a 44-px control
          there makes the bar taller, and a taller sticky bar covers what a press lands on below it. */}
      <Segmented<DeskFace>
        segments={DESK_FACES}
        value={face}
        onChange={turnTo}
        label="Desk faces"
        fill
        className="mb-3 mt-2"
      />
      {fleet && (face === 'plans' ? <Plans fleet={fleet} /> : <Markets fleet={fleet} />)}

      {fleet && good && !tradingHere && (
        <GoodPage
          key={`${good.code}:${fleet.id}`}
          fleet={fleet}
          good={good}
          onTrade={(intent) => setTrading({ code: good.code, intent })}
        />
      )}
      {fleet && tradingHere && (
        <DeskTrade fleet={fleet} code={tradingHere.code} intent={tradingHere.intent} onClose={() => setTrading(null)} />
      )}
    </Sheet>
  )
}
