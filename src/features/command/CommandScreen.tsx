import { DeskShell } from './DeskShell'
import { Trade } from './buysell/Trade'
import { GoalCard } from './GoalCard'
import { useT } from '../../lib/i18n'

// COMMAND — THE DESK (docs/COMMAND_DESK.md, 2026-10-18). TWO SHAPES, ONE STATE (§3.9): on a wide glass
// (≥ 1024 px, WIDE_QUERY) the desk is a TRADING TERMINAL — the fleet and the faces on one header line,
// and every face in the three panes (DeskFrame.tsx) using the whole glass; on a phone it is a titled scroll box
// below, the parts one under the other. Which city and good are in hand and which face is up are the
// same state in both.
// The owner, 2026-10-17: *"i want you to delete
// port tab, and focus on command tab. it will be like stock trading screen, with buy and sell plans,
// seeing charts of each trade goods that i click, setting up trade routes for my fleet, investing, and
// all … stylish - modern - sophisticated yet concise simple."*
//
// THE SHELL (DeskShell.tsx, shared with the Office tab): the fleet strip (which fleet — the picker, FleetPicker.tsx — and its
// two figures), and the one face, Trade. ONE FACE SINCE 2026-11-16 (owner: *"in trade, there are city invest report and
// levels, which aren't that related to trade. they should have separate tab like map you stats etc."*): City, Invest and
// Report are the OFFICE tab's faces (features/command/OfficeScreen.tsx), Levels stand on the YOU page.
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
  const t = useT()
  return (
    <DeskShell
      testid="command"
      title={t('shell.tab_Trade')}
      board
      above={<GoalCard />}
      body={(fleet, layout) => <Trade fleet={fleet} layout={layout} />}
    />
  )
}
