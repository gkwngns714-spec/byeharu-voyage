import { useEffect, useMemo, type ReactNode } from 'react'
import { Clip, Note, Segmented, Sheet, scrollRegionClass, useWide } from '../../components/ui'
import { WorldFailed, WorldLoading } from '../../live/WorldGate'
import { useCommandDraft } from '../../domain/order'
import { useWorld } from '../../live/worldStore'
import type { FleetView } from '../../lib/rpc'
import { DeskPanes, DeskStack, type DeskLayout } from './DeskFrame'
import { FleetStrip } from './FleetStrip'
import { TradeStatus } from './buysell/TradeStatus'
import { useT } from '../../lib/i18n'

// THE DESK'S SHELL — ONE FOR THE TRADE TAB AND THE OFFICE TAB (2026-11-16). Until then this was CommandScreen's own body,
// and the Office's faces (City · Invest · Report) were the desk's faces. The owner moved them to their own tab; both tabs
// keep the same shell — the title, the fleet in hand (FleetStrip: which fleet, where she is), the faces when there are
// several, and the face's parts laid out by the desk (DeskFrame.tsx: the terminal's three panes from 1024 px, one under
// the other on a phone). Written once here, so the two tabs cannot drift.
//
// TWO SHAPES, ONE STATE (docs/COMMAND_DESK.md §3.9): on a wide glass the fleet and the faces stand on one header line and
// the face fills the three panes; on a phone a title line, then ONE scroll box with the strip, the faces and the face.

export interface DeskFaces<F extends string> {
  segments: readonly { id: F; label: string }[]
  value: F
  onChange: (face: F) => void
  /** The strip's accessible name. */
  label: string
}

export function DeskShell<F extends string>({
  testid,
  title,
  faces,
  board = false,
  above,
  body,
}: {
  /** The root's test id ('command', 'office'). */
  testid: string
  title: string
  faces?: DeskFaces<F>
  /** The fleet strip's status line says when the board is another city's (the Trade board). */
  board?: boolean
  /** A line between the strip and the face (the Trade tab's goal card). */
  above?: ReactNode
  body: (fleet: FleetView, layout: DeskLayout) => ReactNode
}) {
  const t = useT()
  const phase = useWorld((s) => s.phase)
  const fatal = useWorld((s) => s.fatal)
  const snapshot = useWorld((s) => s.snapshot)
  // 0321: an empty fleet takes no order, so the desk does not offer her (the Fleets tab does).
  const allFleets = useWorld((s) => s.fleets)
  const fleets = useMemo(() => allFleets.filter((f) => f.ships.length > 0), [allFleets])
  const open = useWorld((s) => s.open)

  // `useCommandDraft` holds WHICH FLEET is in hand (the map's tap and FLEETS' "Command her" point it here) — one fleet in
  // hand for both tabs.
  const fleetId = useCommandDraft((s) => s.fleetId)
  const selectFleet = useCommandDraft((s) => s.selectFleet)

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
    // THE WORLD'S TWO NON-READY DOORS are written once (live/WorldGate.tsx), on the page grid — not a third copy here
    return <WorldFailed title={title} refusal={fatal} />
  }
  if (!snapshot) {
    return <WorldLoading title={title} />
  }
  if (fleets.length === 0) {
    return (
      <Sheet title={title} layout="page">
        <Note tone="neutral">{t('command.noFleets')}</Note>
      </Sheet>
    )
  }

  // EVERY FACE IN THE ONE FRAME (DeskFrame.tsx; the owner, 2026-10-19: "no pop ups or no new screen, but
  // reloading on the same page"). A face hands its parts to the layout; the desk decides the shape.
  const faceId = faces?.value ?? testid
  const layout: DeskLayout = wide ? (parts) => <DeskPanes face={faceId} {...parts} /> : (parts) => <DeskStack {...parts} />

  if (wide) {
    return (
      <div className="flex h-full min-h-0 flex-col" data-testid={testid} data-desk="terminal">
        {/* THE HEADER spans the glass, the same on every face: pressing a face changes the panes below
            it, never the header or the frame. */}
        {/* 2026-11-11 (S9): from `lg` the nav is a rail at the left and takes 96 px of this line; where the title, the fleet strip and the
            faces no longer fit one line (1,024-1,069 px with one fleet), the faces step to a second line at the right instead of the
            strip being cut — the strip's basis is its own content (`flex-[1_1_auto]`), so the line breaks before anything is clipped. */}
        <header className="flex shrink-0 flex-wrap items-center gap-x-6 gap-y-2 px-3 py-3 min-[90rem]:px-6" data-testid="desk-header">
          <div className="flex min-w-0 flex-[1_1_auto] items-center gap-6">
            {/* THE PAGE'S CARD-TITLE VOICE (18 px; it was 14) — row 267, tests/command.design.spec.ts */}
            <h1 className="shrink-0 text-t-card text-ink">{title}</h1>
            <FleetStrip fleets={fleets} onSelect={selectFleet} fleet={fleet ?? null} inline />
          </div>
          {faces && (
            <Segmented<F> segments={faces.segments} value={faces.value} onChange={faces.onChange} label={faces.label} className="ml-auto shrink-0" />
          )}
        </header>
        {fleet && above}
        {fleet && body(fleet, layout)}
      </div>
    )
  }

  return (
    // THE PHONE DESK IS ITS OWN ROOT, as the wide desk is (it is not a Sheet): a title line, then ONE scroll box that takes the glass the title
    // leaves, so a face that is ONE board (the City's building face) takes what the strip, the faces and its own header leave free instead of a
    // 12-rem cap — for EVERY face, so pressing one never moves the title (the press law). A face taller than the glass scrolls this box.
    <div className="flex h-full min-h-0 flex-col" data-testid={testid}>
      <header className="flex shrink-0 items-center px-gutter pb-1 pt-2" data-testid="desk-header">
        <h1 className="min-w-0 text-t-figure">
          <Clip>{title}</Clip>
        </h1>
      </header>
      <div className={`flex flex-col ${scrollRegionClass}`} data-testid="desk-scroll" data-sheet-layout={board ? 'page' : undefined}>
        {/* WHERE SHE IS stands beside her name (2026-11-11, the trade-flow slice): in port, or under way to where and until
            when. In the picker's own row, on every face, so turning a face moves nothing; on Trade its second line also says
            when the board is another city's. */}
        <FleetStrip
          fleets={fleets}
          onSelect={selectFleet}
          fleet={fleet ?? null}
          trailing={fleet ? <TradeStatus fleet={fleet} compact board={board} /> : undefined}
        />
        {/* THE FACES: one row in the body, not in the title line — a 44-px control there makes the bar taller, and a taller
            bar covers what a press lands on below it. */}
        {faces && <Segmented<F> segments={faces.segments} value={faces.value} onChange={faces.onChange} label={faces.label} fill className="mb-2 mt-1" />}
        {/* the goal card stands 4 px under the strip and 4 px over the board, so the Trade face is not a pixel taller (under way it
            must not scroll its sheet, tests/trade.flow.spec.ts T3) */}
        {fleet && above}
        {fleet && body(fleet, layout)}
      </div>
    </div>
  )
}
