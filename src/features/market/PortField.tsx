import { useState } from 'react'
import { Chip, Field } from '../../components/ui'
import type { SnapshotPort } from '../../lib/rpc'

// THE PORT FIELD — one line that names the harbour being read, and the ten nearest under it while
// you type. docs/UI_DIRECTION.md §6: `[🔍 Lisbon ▾]  Porto · Cádiz · Seville`.
//
// ── WHAT IT REPLACES ───────────────────────────────────────────────────────────────────────────
// A "PORT Lisbon ▾" button that opened a search field, a count line ("All 238 ports — IBE first."),
// a "YOUR FLEET" label with its own chip, and 238 chips in a wrap — the wall §2 item 8 measured at
// 5,566px. The search field was already the picker; the wall was what it fell back to when nobody
// typed. This keeps the field and deletes the fallback: what stands under it is never more than
// `NEAR_PORTS` chips, and which ten is `nearbyHarbours`' decision, not this file's.
//
// ── AT REST IT READS THE HARBOUR; FOCUSED, IT IS A SEARCH ──────────────────────────────────────
// One control, two states, one piece of state (`open`). Closed, the field's value is the harbour's
// name and nothing hangs under it. Focus empties it — the placeholder says what to do — and the
// chips appear. A pick, Escape, or focus leaving the pair closes it and the name comes back. The
// chips cancel `pointerdown` so that pressing one does not blur the field a beat before the click
// lands: on a touch screen a button takes no focus, so `relatedTarget` would be null, the field
// would close, and the chip would be gone before it was pressed. Enter takes the first chip.

export function PortField({
  current,
  offer,
  onPick,
}: {
  /** The harbour being read. Null only when the world served no ports. */
  current: SnapshotPort | null
  /** Which harbours to offer for a query — at most ten, nearest first (`nearbyHarbours`). */
  offer: (query: string) => readonly SnapshotPort[]
  onPick: (code: string) => void
}) {
  const [open, setOpen] = useState(false)
  const [query, setQuery] = useState('')
  const listed = open ? offer(query) : []

  const close = () => {
    setOpen(false)
    setQuery('')
  }
  const pick = (code: string) => {
    onPick(code)
    close()
  }

  return (
    <div
      onBlur={(e) => {
        if (!e.currentTarget.contains(e.relatedTarget)) close()
      }}
    >
      <Field
        value={open ? query : (current?.name ?? '')}
        onChange={(e) => setQuery(e.target.value)}
        onFocus={() => {
          setQuery('')
          setOpen(true)
        }}
        onKeyDown={(e) => {
          if (e.key === 'Escape') {
            close()
            e.currentTarget.blur()
          } else if (e.key === 'Enter' && listed[0]) {
            pick(listed[0].code)
            e.currentTarget.blur()
          }
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
        <div className="mt-2 flex flex-wrap gap-2" onPointerDown={(e) => e.preventDefault()}>
          {listed.map((p) => (
            <Chip key={p.id} on={p.code === current?.code} onClick={() => pick(p.code)} data-testid="port-chip">
              {p.name}
            </Chip>
          ))}
        </div>
      )}
    </div>
  )
}
