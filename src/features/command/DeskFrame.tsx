import { useMemo, useState, type ReactNode } from 'react'
import { DeskTraySlot, type TraySlot } from '../../components/ui'

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
//   · PHONE: the Sheet the desk already is; the parts stand one under the other in the face's
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
    <div
      className="grid min-h-0 flex-1 grid-cols-[minmax(19rem,23rem)_minmax(0,1fr)_minmax(20rem,24rem)]"
      data-testid={testid}
      data-desk-frame=""
      data-face={face}
    >
      <DeskTraySlot.Provider value={value}>
        <section className="bv-scroll min-h-0 overflow-y-auto border-r border-edge px-4 pb-6 pt-3" data-testid="desk-pane-list">
          {list}
        </section>
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
    <section
      className={scroll ? 'bv-scroll min-h-0 overflow-y-auto px-6 pb-6 pt-4' : 'flex min-h-0 flex-col px-6 pb-3 pt-4'}
      data-testid="desk-pane-chart"
    >
      {children}
    </section>
  )
}

/** The right pane — the ticket pane, the desk's slot. Always the grid's third column. */
export function DeskSidePane({ children }: { children?: ReactNode }) {
  return (
    <section className="col-start-3 row-start-1 min-h-0 border-l border-edge" data-testid="desk-pane-ticket">
      {children}
    </section>
  )
}

/** The phone: the parts one under the other, in the Sheet. */
export function DeskStack({ testid, list, main, side, order = ['list', 'main', 'side'] }: DeskParts) {
  const parts = { list, main, side }
  return (
    <div data-testid={testid}>
      {order.map((k) => (
        <div key={k}>{parts[k]}</div>
      ))}
    </div>
  )
}
