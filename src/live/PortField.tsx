import { useCallback, useEffect, useRef, useState } from 'react'
import { Chip, Field, useDismiss } from '../components/ui'
import type { SnapshotPort } from '../lib/rpc'
import { nearbyHarbours } from '../domain/port'
import { useWorld } from './worldStore'

// THE PORT FIELD — one line that names the harbour being read, and the ten nearest under it while
// you type. docs/UI_DIRECTION.md §6: `[🔍 Lisbon ▾]  Porto · Cádiz · Seville`.
//
// MOVED 2026-09-11 from features/market/ onto PORT with the MARKET tab it belonged to (owner row
// 76). It is a LEAF that reads the store itself (worldStore.ts rule 4; UI_DIRECTION §5's ≤6 props):
// which harbours exist and how far each is from where she lies. Its caller hands it the harbour on
// screen, the harbour distances are measured from, and what to do with a pick.
//
// ── WHAT IT REPLACES ───────────────────────────────────────────────────────────────────────────
// A "PORT Lisbon ▾" button that opened a search field, a count line ("All 238 ports — IBE first."),
// a "YOUR FLEET" label with its own chip, and 238 chips in a wrap — the wall §2 item 8 measured at
// 5,566px. What stands under the field is never more than `NEAR_PORTS` chips, and which ten is
// `nearbyHarbours`' decision, not this file's.
//
// ── AT REST IT READS THE HARBOUR; FOCUSED, IT IS A SEARCH ──────────────────────────────────────
// One control, two states, one piece of state (`open`). Closed, the field's value is the harbour's
// name. Focus empties it — the placeholder says what to do — and the chips appear. A pick, Escape,
// or a press that LANDS somewhere else closes it and the name comes back. Enter takes the first
// chip.
//
// ── IT NEVER FOLDS ON A BLUR (2026-09-14, owner: "i can't seem to press anything else") ────────
// The chips stand IN FLOW under the field — the inline unfold of Tray.tsx's rule: what is below
// moves down, and nothing moves at or above. The exit used to be "focus leaving the pair", and a
// blur is fired by the MOUSEDOWN of whatever the player presses next — so the chips unmounted and
// the whole board jumped back up between that mousedown and its mouseup. Chrome fires no click
// when the two land on different elements, and the press died: measured at 1545 px, a drag in
// this field (to copy the harbour's name) then a press on the first live buy cell — the cell had
// stood 104 px lower while the field was open, and the press opened nothing. That is the owner's
// collapse rule broken under a press in progress: "pressing a control SELECTS. It never collapses,
// re-flows … the surface it was pressed on."
//
// So the fold is tied to the press LANDING, not to the focus leaving: a `click` anywhere outside
// the pair closes the picker AFTER the pressed control has answered it. Mouse and touch now agree
// (a touch press never blurred the field at all, so on a phone the chips simply stayed). The
// chips no longer need to cancel `pointerdown` — that existed only to stop a blur closing the
// field a beat before a chip's own click. tests/selection.lock.spec.ts holds the line.
//
// ── LEAVING IS ONE ACT, AND IT INCLUDES THE BLUR (2026-09-09) ──────────────────────────────────
// Found on production, four times: pick a chip and the field worked exactly once per page load —
// three exits, three spellings, one of them did not blur, so `onFocus` could never fire again.
// There is ONE exit now, `leave()`, and it always gives the focus back.
//
// ── A SECOND CALLER: THE ROUTE EDITOR (0092, 2026-09-30) ───────────────────────────────────────
// COMMAND's route editor needs "pick a harbour" and nothing else, and this is the one port picker
// the client has. A screen may not import another screen (tests/sections.spec.ts), and a copy is
// the silent spaghetti that rule warns about — so the field MOVED from features/port/ to src/live/
// (beside WorldGate: a leaf that reads the store, for any screen), and its pure ranking
// (`nearbyHarbours`) moved to src/domain/port. It is COMPOSED: the pick goes to the caller.
//
// ── ONE CALLER SINCE PORT WENT (2026-10-18, docs/COMMAND_DESK.md D8) ───────────────────────────
// PORT read any harbour through this field and kept the pick in `src/store/harbour.ts` (with "back to
// her quay" on the ✕). PORT is gone — a distant city's prices are read on the desk's good page and on
// the map — so the store and that path went with it. The ✕ now only empties the search.

export function PortField({
  current,
  anchor,
  onPick,
}: {
  /** The harbour being read. Null only when the world served no ports. */
  current: SnapshotPort | null
  /** The harbour she is in or bound for, by CODE — pinned first in the chips, and where the sailed
   *  distances are measured from. Null when the house has no fleet. */
  anchor: string | null
  /** The pick is the caller's (the route editor's stop). */
  onPick: (code: string) => void
}) {
  const ports = useWorld((s) => s.snapshot?.ports)
  const portByCode = useWorld((s) => s.portByCode)
  const reaches = useWorld((s) => s.reaches)
  const loadReach = useWorld((s) => s.loadReach)

  const anchorPort = anchor ? (portByCode[anchor] ?? null) : null
  const reach = anchorPort ? reaches[anchorPort.id] : undefined
  useEffect(() => {
    if (anchorPort) void loadReach(anchorPort.id)
  }, [anchorPort, loadReach])
  const offer = useCallback(
    (query: string) => nearbyHarbours(ports ?? [], reach, anchor, query),
    [ports, reach, anchor],
  )

  const [open, setOpen] = useState(false)
  const [query, setQuery] = useState('')
  const box = useRef<HTMLDivElement>(null)
  const listed = open ? offer(query) : []

  /** THE ONE EXIT from the open state: the field closes and gives the focus back, whichever of the
   *  three roads (a pick, Escape, a press landing outside the pair) was taken. */
  const leave = useCallback(() => {
    setOpen(false)
    setQuery('')
    const input = box.current?.querySelector('input')
    if (input && document.activeElement === input) input.blur()
  }, [])

  // A press that lands OUTSIDE the pair closes the picker — after it has landed — and Escape is the
  // keyboard's press-outside, from wherever the focus has gone. The one dismissal, `useDismiss`
  // (design system, 2026-10-20: the fleet picker's dropdown was its second caller); its header
  // carries the click-not-blur reasoning the head of this file records.
  useDismiss(open, box, leave)
  const choose = (code: string) => {
    onPick(code)
    leave()
  }

  return (
    <div ref={box} className="mt-3">
      <Field
        value={open ? query : (current?.name ?? '')}
        onChange={(e) => setQuery(e.target.value)}
        onFocus={() => {
          setQuery('')
          setOpen(true)
        }}
        onKeyDown={(e) => {
          if (e.key === 'Enter' && listed[0]) choose(listed[0].code)
        }}
        onClear={open ? () => setQuery('') : undefined}
        aria-label="Find a port"
        aria-expanded={open}
        placeholder="Find a port"
        spellCheck={false}
        autoCorrect="off"
        autoComplete="off"
        data-testid="port-field"
      />
      {open && (
        <div className="mt-2 flex flex-wrap gap-2">
          {listed.map((p) => (
            <Chip key={p.id} on={p.code === current?.code} onClick={() => choose(p.code)} data-testid="port-chip">
              {p.name}
            </Chip>
          ))}
        </div>
      )}
    </div>
  )
}
