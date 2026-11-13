import { useMemo, useState, type ReactNode } from 'react'
import { Card, DeskTraySlot, type TraySlot } from '../../components/ui'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE DESK'S FRAME — ONE FRAME FOR EVERY FACE (2026-10-19)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, 2026-10-19: *"at top right, when pressing plans, city, invest, i want the screen of the
// original command tab to stay same, meaning no pop ups or no new screen, but reloading on the same
// page. get it?"* Until then only the Markets face (gone with row 218) stood in the terminal's three panes; the other faces swapped
// the whole glass for a phone column (the header re-flowed into it), and their acts rose as side
// trays over the right of the glass.
//
// So every face hands the desk its PARTS, and the desk lays them out — the face never chooses a shape:
//   · WIDE (≥ 1024 px): the terminal's three panes, the same grid, the same widths, the same borders,
//     on every face. `list` stands in the left pane, `main` in the centre, `side` in the right (the
//     ticket pane). A face with nothing of its own for the right pane leaves it to THE SLOT: any tray
//     its buildings open (a trade, a hire, an investment) is portalled there (trayContext.ts), and a
//     one-line hint stands in it until one does.
//   · PHONE: the desk's own scroll box; the parts stand one under the other in the face's
//     `order`, in the same screen (the plan builder too, in flow on Plans). Pressing a face raises no
//     tray. A press INSIDE a face on a price, a room or a job still raises the bottom tray that moves
//     nothing: the owner's own rule for that press (rows 6/15/25/28/45, tests/layout.spec.ts).
// A press on a face changes what is in the panes. Nothing about the frame moves.

export interface DeskParts {
  /** The face's test id (desk-plans, desk-city…), on its frame. */
  testid: string
  list: ReactNode
  main: ReactNode
  /** The right pane's own content; omitted → the slot, with `sideHint` until a tray stands in it. */
  side?: ReactNode
  sideHint?: string
  /** On a phone, the order the parts stand in (default list, main, side). */
  order?: readonly ('list' | 'main' | 'side')[]
  /** The centre pane scrolls by itself (default); the chart fills its pane instead. */
  mainScroll?: boolean
  /** ON A PHONE the centre part is a BOARD that takes the glass left under the list part (the City's building face): it stands on a flex column
   *  that gives it the rest of the scroll box and scrolls inside itself, instead of its own height under a fixed cap. The wide desk lays it out in its pane
   *  as always. */
  mainFill?: boolean
  /** `data-*` marks on the frame element, for a read the face makes that DRAWS NOTHING while pending (the
   *  quay's fair, src/live/PortFair.tsx: its quiet state is no element, so no Skeleton says it is still
   *  being read). A spec waits on the mark; nothing is painted by it. */
  marks?: Record<`data-${string}`, string>
}

/** How the desk lays a face out — the one decision a face does not make. */
export type DeskLayout = (parts: DeskParts) => ReactNode

/** The three panes of a wide glass. Their grid is THE terminal's, for every face. */
export function DeskPanes({
  face,
  testid,
  list,
  main,
  side,
  sideHint,
  mainScroll = true,
  marks,
}: DeskParts & {
  face: string
}) {
  // The right pane's slot element: trays opened inside the face stand in it. It is set in the commit
  // that mounts it, before paint. A face whose right pane is its own (the ticket, the plan builder)
  // provides no slot; its other panes open no trays.
  const [slot, setSlot] = useState<HTMLElement | null>(null)
  const own = side !== undefined && side !== null
  const pane = useMemo<TraySlot | null>(() => (slot ? { el: slot } : null), [slot])
  const value = own ? null : pane
  return (
    // THE MIDDLE PANE KEEPS 16 REM (2026-11-11, S9): with `minmax(0,1fr)` the two side panes grew to their 22-rem caps first and the
    // middle took what was left — 272 px at 1,024 before the rail, 176 after it, where "Your cargo" and the small map were cut. A
    // 16-rem floor makes the sides give way first (down to their own 19 / 20 rem).
    // FROM 1,280 THE MIDDLE KEEPS 34 REM (2026-11-13, owner row 318): at 1,280 × 800 the sides stood at their 22-rem caps and the
    // middle had 432 px: Trade's ten goods cards stood two to a line, five lines, 934 px in a 626-px pane. With 544 px the cards
    // stand four to a line (TradeBoard.tsx) and the pane does not scroll. The left pane gives the room (17 rem at 1,280, its
    // words grid keeps every name whole at any width); the right keeps its 20 rem, a phone's width, for the trade panel. From
    // 1,440 the three panes are as they were (352 / 560 / 352).
    <div
      className="grid min-h-0 flex-1 grid-cols-[minmax(19rem,22rem)_minmax(16rem,1fr)_minmax(20rem,22rem)] xl:grid-cols-[minmax(17rem,22rem)_minmax(34rem,1fr)_minmax(20rem,22rem)] gap-3 px-3 pb-3 min-[90rem]:gap-4 min-[90rem]:px-6 min-[90rem]:pb-4"
      data-testid={testid}
      data-desk-frame=""
      data-face={face}
      {...marks}
    >
      <DeskTraySlot.Provider value={value}>
        <Card flush className="min-h-0 overflow-hidden">
          <section className="bv-scroll h-full min-h-0 overflow-y-auto p-4 min-[90rem]:p-5" data-testid="desk-pane-list">
            {list}
          </section>
        </Card>
        <DeskMainPane scroll={mainScroll}>{main}</DeskMainPane>
      </DeskTraySlot.Provider>
      <DeskSidePane>
        {own ? (
          side
        ) : (
          <div className="flex h-full min-h-0 flex-col">
            {/* THE SLOT: a tray opened in this face is portalled here. Empty → the hint below shows. */}
            <div ref={setSlot} className="peer bv-scroll min-h-0 flex-1 overflow-y-auto empty:hidden" data-testid="desk-slot" />
            {sideHint && (
              <p className="hidden px-4 pt-4 text-t-caption text-ink-faint peer-empty:block" data-testid="desk-slot-hint">
                {sideHint}
              </p>
            )}
          </div>
        )}
      </DeskSidePane>
    </div>
  )
}

/** The centre pane: scrolls by itself, or (the chart) is filled by its content. */
export function DeskMainPane({ scroll = true, children }: { scroll?: boolean; children?: ReactNode }) {
  return (
    <Card flush className="min-h-0 overflow-hidden">
      <section
        className={scroll ? 'bv-scroll h-full min-h-0 overflow-y-auto p-5 min-[90rem]:p-6' : 'flex h-full min-h-0 flex-col p-5 min-[90rem]:p-6'}
        data-testid="desk-pane-chart"
      >
        {children}
      </section>
    </Card>
  )
}

/** The right pane — the ticket pane, the desk's slot. Always the grid's third column. */
export function DeskSidePane({ children }: { children?: ReactNode }) {
  return (
    <Card flush className="col-start-3 row-start-1 min-h-0 overflow-hidden">
      <section className="h-full min-h-0" data-testid="desk-pane-ticket">
        {children}
      </section>
    </Card>
  )
}

/** The phone: the parts one under the other, in the desk's scroll box. */
export function DeskStack({ testid, list, main, side, order = ['list', 'main', 'side'], mainFill = false, marks }: DeskParts) {
  const parts = { list, main, side }
  return (
    <div data-testid={testid} className={mainFill ? 'flex min-h-0 flex-1 flex-col' : undefined} {...marks}>
      {order.map((k) => (
        <div key={k} className={mainFill ? (k === 'main' ? 'flex min-h-0 flex-1 flex-col' : 'shrink-0') : undefined}>
          {parts[k]}
        </div>
      ))}
    </div>
  )
}
