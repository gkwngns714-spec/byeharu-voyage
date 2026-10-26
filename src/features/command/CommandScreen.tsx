import { useEffect, useMemo } from 'react'
import { Note, Row, Segmented, Sheet, useWide } from '../../components/ui'
import { useCommandDraft } from '../../domain/order'
import { useWorld } from '../../live/worldStore'
import type { FleetView } from '../../lib/rpc'
import { useDeskGood } from '../../store/deskGood'
import { DeskPanes, DeskStack, type DeskLayout } from './DeskFrame'
import { DESK_FACES, useDeskView, type DeskFace } from './deskView'
import { FleetStrip } from './FleetStrip'
import { BuySell } from './buysell/BuySell'
import { City } from './city/City'
import { Invest } from './invest/Invest'
import { Profit } from './profit/Profit'
import { useT } from '../../lib/i18n'

// COMMAND — THE DESK (docs/COMMAND_DESK.md, 2026-10-18). TWO SHAPES, ONE STATE (§3.9): on a wide glass
// (≥ 1024 px, WIDE_QUERY) the desk is a TRADING TERMINAL — the fleet and the faces on one header line,
// and every face in the three panes (DeskFrame.tsx) using the whole glass; on a phone it is the Sheet
// below, the parts one under the other. Which city and good are in hand and which face is up are the
// same state in both.
// The owner, 2026-10-17: *"i want you to delete
// port tab, and focus on command tab. it will be like stock trading screen, with buy and sell plans,
// seeing charts of each trade goods that i click, setting up trade routes for my fleet, investing, and
// all … stylish - modern - sophisticated yet concise simple."*
//
// THE SHELL: the fleet strip (which fleet — the picker, FleetPicker.tsx — and its two figures), the faces (deskView.ts — the
// ones built: Buy · Sell · City · Invest · Profit; owner row 218 replaced Markets and Trade with Buy and Sell,
// buysell/BuySell.tsx), and the face.
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
  const phase = useWorld((s) => s.phase)
  const fatal = useWorld((s) => s.fatal)
  const snapshot = useWorld((s) => s.snapshot)
  const fleets = useWorld((s) => s.fleets)
  const open = useWorld((s) => s.open)

  const fleetId = useCommandDraft((s) => s.fleetId)
  const selectFleet = useCommandDraft((s) => s.selectFleet)
  const face = useDeskView((s) => s.face)
  const turnTo = useDeskView((s) => s.turnTo)
  // A HAND-OVER FROM THE MAP (live/PriceTray.tsx, "Open in Command"): the city and the good are in hand; the desk
  // turns to Buy once to show them.
  const handed = useDeskGood((s) => s.handed)
  const spendHand = useDeskGood((s) => s.spendHand)
  useEffect(() => {
    if (!handed) return
    turnTo('buy')
    spendHand()
  }, [handed, turnTo, spendHand])

  useEffect(() => {
    void open()
  }, [open])

  const fleet = useMemo(() => fleets.find((f) => f.id === fleetId), [fleets, fleetId])
  useEffect(() => {
    if (fleet) return
    const first = fleets.find((f) => f.status === 'DOCKED') ?? fleets[0]
    if (first) selectFleet(first.id)
  }, [fleet, fleets, selectFleet])

  const wide = useWide()

  if (phase === 'failed' && fatal) {
    return (
      <Sheet title={t('command.title')}>
        <Note tone="danger" code={fatal.code} figures={fatal.figures}>
          {fatal.sentence}
        </Note>
      </Sheet>
    )
  }
  if (!snapshot) {
    return (
      <Sheet title={t('command.title')}>
        <Row label={t('command.loading')} tone="muted" hairline={false} />
      </Sheet>
    )
  }
  if (fleets.length === 0) {
    return (
      <Sheet title={t('command.title')}>
        <Note tone="neutral">{t('command.noFleets')}</Note>
      </Sheet>
    )
  }

  // EVERY FACE IN THE ONE FRAME (DeskFrame.tsx; the owner, 2026-10-19: "no pop ups or no new screen, but
  // reloading on the same page"). A face hands its parts to the layout; the desk decides the shape: the
  // terminal's three panes on a wide glass, one under the other on a phone.
  const layout: DeskLayout = wide ? (parts) => <DeskPanes face={face} {...parts} /> : (parts) => <DeskStack {...parts} />
  const faceBody = (f: FleetView) =>
    face === 'buy' || face === 'sell' ? (
      <BuySell key={face} side={face} fleet={f} layout={layout} />
    ) : face === 'city' ? (
      <City fleet={f} layout={layout} />
    ) : face === 'invest' ? (
      <Invest fleet={f} layout={layout} />
    ) : (
      <Profit layout={layout} />
    )

  if (wide) {
    return (
      <div className="flex h-full min-h-0 flex-col" data-testid="command" data-desk="terminal">
        {/* THE HEADER spans the glass, the same on every face: pressing a face changes the panes below
            it, never the header or the frame. */}
        <header className="flex shrink-0 items-center gap-6 border-b border-edge px-6 py-2" data-testid="desk-header">
          <div className="flex min-w-0 flex-1 items-center gap-6">
            <h1 className="shrink-0 text-t-body font-semibold text-ink">{t('command.title')}</h1>
            <FleetStrip fleets={fleets} onSelect={selectFleet} fleet={fleet ?? null} inline />
          </div>
          <Segmented<DeskFace> segments={DESK_FACES} value={face} onChange={turnTo} label={t('command.deskFaces')} className="shrink-0" />
        </header>
        {fleet && faceBody(fleet)}
      </div>
    )
  }

  return (
    <Sheet title={t('command.title')} data-testid="command">
      <FleetStrip fleets={fleets} onSelect={selectFleet} fleet={fleet ?? null} />
      {/* THE FACES (deskView.ts): one row in the body, not in the sticky title bar — a 44-px control
          there makes the bar taller, and a taller sticky bar covers what a press lands on below it. */}
      <Segmented<DeskFace>
        segments={DESK_FACES}
        value={face}
        onChange={turnTo}
        label={t('command.deskFaces')}
        fill
        className="mb-3 mt-2"
      />
      {fleet && faceBody(fleet)}
    </Sheet>
  )
}
