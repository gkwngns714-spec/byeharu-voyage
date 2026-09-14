import { useCallback, useEffect, useRef, useState } from 'react'
import { Chip, Field } from '../../components/ui'
import type { SnapshotPort } from '../../lib/rpc'
import { useWorld } from '../../live/worldStore'
import { harbourPick, useHarbour } from '../../store/harbour'
import { nearbyHarbours } from './nearby'

// THE PORT FIELD — one line that names the harbour being read, and the ten nearest under it while
// you type. docs/UI_DIRECTION.md §6: `[🔍 Lisbon ▾]  Porto · Cádiz · Seville`.
//
// MOVED 2026-09-11 from features/market/ onto PORT with the MARKET tab it belonged to (owner row
// 76). It is a LEAF that reads the store itself (worldStore.ts rule 4; UI_DIRECTION §5's ≤6 props):
// which harbours exist, how far each is from where she lies, and the one harbour choice
// (`src/store/harbour.ts`). PortScreen hands it two facts it already derived — the harbour on
// screen and the harbour her orders would run at — and nothing else.
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
// ── THE CLEAR IS "BACK TO HER QUAY", AND SO IS HER OWN CHIP ────────────────────────────────────
// While a harbour is PICKED, the closed field's ✕ clears the pick, and `null` follows the fleet
// (`harbourCode`): the board goes back to the quay she lies at, and stays with her when she sails.
// That is the RESUME.md defect driven on 2026-09-09 — reading a distant market moved PORT off her
// quay with only a PIN to get back — answered the way it asked: a pick is undone, not re-pinned.
// Tapping the chip of the quay she is at must do the same, or one tap re-creates the strand; the
// store's `harbourPick` decides that once. While no harbour is picked there is nothing to clear,
// so no ✕ is drawn.
//
// ── LEAVING IS ONE ACT, AND IT INCLUDES THE BLUR (2026-09-09) ──────────────────────────────────
// Found on production, four times: pick a chip and the field worked exactly once per page load —
// three exits, three spellings, one of them did not blur, so `onFocus` could never fire again.
// There is ONE exit now, `leave()`, and it always gives the focus back.

export function PortField({
  current,
  anchor,
}: {
  /** The harbour being read. Null only when the world served no ports. */
  current: SnapshotPort | null
  /** The harbour she is in or bound for, by CODE — pinned first in the chips, and where the sailed
   *  distances are measured from. Null when the house has no fleet. */
  anchor: string | null
}) {
  const ports = useWorld((s) => s.snapshot?.ports)
  const fleets = useWorld((s) => s.fleets)
  const portByCode = useWorld((s) => s.portByCode)
  const reaches = useWorld((s) => s.reaches)
  const loadReach = useWorld((s) => s.loadReach)
  const picked = useHarbour((s) => s.picked)
  const pick = useHarbour((s) => s.pick)

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

  // A press that lands OUTSIDE the pair closes the picker — after it has landed. `click` is the
  // event that says a press completed on one element; a blur says only that focus moved, and it
  // says so on the mousedown, with the mouseup still to come (see the head of this file). Escape
  // is the keyboard's press-outside, and it works from wherever the focus has gone.
  useEffect(() => {
    if (!open) return
    const onClick = (e: MouseEvent) => {
      if (box.current && !box.current.contains(e.target as Node)) leave()
    }
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') leave()
    }
    document.addEventListener('click', onClick)
    document.addEventListener('keydown', onKey)
    return () => {
      document.removeEventListener('click', onClick)
      document.removeEventListener('keydown', onKey)
    }
  }, [open, leave])
  // A chip that names the quay she is at stores NULL (follow her), any other a pick — one rule,
  // spelt in the store (`harbourPick`), shared with PORT's "Read X" button.
  const choose = (code: string) => {
    pick(harbourPick(code, fleets, ports ?? []))
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
        onClear={open ? () => setQuery('') : picked !== null ? () => pick(null) : undefined}
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
