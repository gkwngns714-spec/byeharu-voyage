import { useCallback, useEffect, useState } from 'react'
import { Button, Dot, Figure, Icon, Popover, Row, Tray, useWide, type DotTone } from '../../components/ui'
import {
  fleetHoldTotal,
  fleetHoldUsed,
  fleetPortCode,
  fleetSignal,
  whereabouts,
  whereLine,
  type FleetSignal,
} from '../../domain/fleet'
import { PortFlag } from '../../live/PortFlag'
import { portNameOf, useWorld } from '../../live/worldStore'
import { formatOfTotal, tonsWord } from '../../lib/format'
import type { FleetView } from '../../lib/rpc'

// THE FLEET PICKER — which fleet the desk acts for, as ONE button (the owner, 2026-10-20: "in the
// command, right now i see my fleet name on left top. when i have multiple fleets, how should this
// change?" — and of this design, "good. we need that").
//
// WHAT IT SHOWS: only the selected fleet — her flag, her name, a dot for her one-word signal
// (domain/fleet's `fleetSignal`: green sailing · grey waiting · red stuck) and ▾. The header stays
// one line however many fleets there are, where a chip per fleet (the strip before this) ran out of
// glass at three. If any OTHER fleet is stuck, a red dot after the ▾ says so, so a refused order on
// the fleet you are not looking at is never silent. With ONE fleet it is her flag and her name,
// nothing to press: no dot, no ▾, no list.
//
// WHAT A PRESS DOES: opens the list of your fleets, one row each — flag · name · where she is (the
// one where-rule, `whereLine`, with the countdown off the last read) · cargo used / total. A press
// on a row SELECTS that fleet and closes the list; it moves nothing on the page (the owner's rule,
// rows 6/15/25/28/45). On a wide glass the list is a `Popover` hung under the button; on a phone it
// is the bottom `Tray` — the two shapes the design system already has, decided here once by
// `useWide()`. Outside press or Escape closes the popover (`useDismiss`, inside Popover); the tray
// closes by its ✕, a drag, or a pick.
//
// ← / → SWITCH FLEETS on a wide glass, in the served order, wrapping — never while the player is
// typing (an input, a textarea, a select, anything editable), and never with a modifier held.
//
// ONE SELECTION. This writes `useCommandDraft`'s `selectFleet` through `onSelect` and reads the
// fleet the desk already resolved from it — the same authority the map's tap and FLEETS' "Command
// her" point at. There is no second fleet selection here, and no second where-rule or stuck-rule:
// the dot's word is `fleetSignal`, which composes the queue's refused row and the status tone.

const SIGNAL_TONE: Record<FleetSignal, DotTone> = {
  sailing: 'success',
  waiting: 'neutral',
  stuck: 'danger',
}
const SIGNAL_WORD: Record<FleetSignal, string> = {
  sailing: 'sailing',
  waiting: 'waiting for orders',
  stuck: 'stuck',
}

/** Is this key press happening where typing belongs? Then the arrows are the field's, not ours. */
function typing(target: EventTarget | null): boolean {
  return (
    target instanceof HTMLElement &&
    target.closest('input, textarea, select, [contenteditable=""], [contenteditable="true"]') !== null
  )
}

export function FleetPicker({
  fleets,
  fleet,
  onSelect,
}: {
  fleets: readonly FleetView[]
  /** The fleet in hand, as the desk resolved it from the command draft. */
  fleet: FleetView | null
  /** `useCommandDraft`'s `selectFleet` — the one selection. */
  onSelect: (id: string) => void
}) {
  const wide = useWide()
  const [open, setOpen] = useState(false)
  const close = useCallback(() => setOpen(false), [])
  const many = fleets.length > 1

  // ← / → on a wide glass: the previous / next fleet in the served order, wrapping.
  useEffect(() => {
    if (!wide || !many) return
    const onKey = (e: KeyboardEvent) => {
      if (e.key !== 'ArrowLeft' && e.key !== 'ArrowRight') return
      if (e.altKey || e.ctrlKey || e.metaKey || e.shiftKey) return
      if (typing(e.target)) return
      const n = fleets.length
      const i = fleets.findIndex((f) => f.id === fleet?.id)
      const next = e.key === 'ArrowRight' ? (i + 1) % n : (i - 1 + n) % n
      onSelect(fleets[next].id)
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [wide, many, fleets, fleet, onSelect])

  if (!fleet) return null

  const flag = fleetPortCode(fleet)
  const name = (
    <>
      {flag && <PortFlag code={flag} />}
      <span className="truncate text-t-body font-semibold text-ink">{fleet.name}</span>
    </>
  )

  if (!many) {
    return (
      <span className="inline-flex min-h-11 min-w-0 items-center gap-2 px-4" data-testid="fleet-picker" data-fleets={fleets.length}>
        {name}
      </span>
    )
  }

  const signal = fleetSignal(fleet)
  const othersStuck = fleets.filter((f) => f.id !== fleet.id && fleetSignal(f) === 'stuck').length
  const trigger = (
    <Button
      variant="quiet"
      className="min-w-0"
      aria-haspopup="dialog"
      aria-expanded={open}
      onClick={() => setOpen((o) => !o)}
      data-testid="fleet-picker"
      data-fleets={fleets.length}
    >
      {name}
      <Dot tone={SIGNAL_TONE[signal]} label={SIGNAL_WORD[signal]} data-testid="fleet-picker-dot" />
      <Icon name="chevron" size={16} className="shrink-0 rotate-90 text-ink-faint" />
      {othersStuck > 0 && (
        <Dot
          tone="danger"
          label={othersStuck === 1 ? 'another fleet is stuck' : `${othersStuck} other fleets are stuck`}
          data-testid="fleet-picker-alert"
        />
      )}
    </Button>
  )
  const rows = (
    <FleetRows
      fleets={fleets}
      fleetId={fleet.id}
      onPick={(id) => {
        onSelect(id)
        close()
      }}
    />
  )

  if (wide) {
    return (
      <Popover open={open} onClose={close} trigger={trigger} label="Fleets" className="w-80 px-4" data-testid="fleet-list">
        {rows}
      </Popover>
    )
  }
  return (
    <>
      {trigger}
      <Tray detent={open ? 'half' : 'closed'} onDetentChange={(d) => setOpen(d !== 'closed')} title="Fleets" data-testid="fleet-list">
        {rows}
      </Tray>
    </>
  )
}

/** The list: one row per fleet — flag · dot · name, where she is under it, her cargo at the right. */
function FleetRows({
  fleets,
  fleetId,
  onPick,
}: {
  fleets: readonly FleetView[]
  fleetId: string
  onPick: (id: string) => void
}) {
  const portByCode = useWorld((s) => s.portByCode)
  // THE CLOCK a sailing row counts down against is the last read's instant — the queue's own
  // (plans/Queue.tsx), so the two never show two different arrivals.
  const readAt = useWorld((s) => s.readAt)
  return (
    <>
      {fleets.map((f, i) => {
        const flag = fleetPortCode(f)
        const signal = fleetSignal(f)
        const used = fleetHoldUsed(f)
        const total = fleetHoldTotal(f)
        return (
          <Row
            key={f.id}
            mark={flag ? <PortFlag code={flag} /> : undefined}
            label={
              <span className="flex items-center gap-2">
                <Dot tone={SIGNAL_TONE[signal]} label={SIGNAL_WORD[signal]} />
                <span className="truncate">{f.name}</span>
              </span>
            }
            value={<Figure value={formatOfTotal(used, total)} unit={tonsWord(total)} />}
            tone={f.id === fleetId ? 'accent' : 'default'}
            hairline={i < fleets.length - 1}
            onClick={() => onPick(f.id)}
            data-testid="fleet-row"
          >
            <span className="block text-t-caption text-ink-faint">
              {whereLine(whereabouts(f), (c) => portNameOf(portByCode, c), readAt ?? undefined)}
            </span>
          </Row>
        )
      })}
    </>
  )
}
