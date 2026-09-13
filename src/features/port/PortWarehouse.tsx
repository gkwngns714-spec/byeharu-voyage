import { useState } from 'react'
import {
  Bar,
  Button,
  Figure,
  Note,
  Row,
  SheetSection,
  Tray,
  type TrayDetent,
} from '../../components/ui'
import { useWarehouse } from '../../live/useWarehouse'
import { useWorld } from '../../live/worldStore'
import { formatInt, formatOfTotal, formatTons } from '../../lib/format'
import type { FleetView, Refusal, StoredGood } from '../../lib/rpc'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE STORE — what this city is keeping for you (0070), as rows.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner: *"make a storage, where i can buy trade goods and then store it. The storage is not
// shared between cities, an independeant building."*
//
// Both lists come from ONE read, deliberately: they can disagree if asked separately, and a screen
// that offers to store cargo she no longer carries is a screen that refuses when pressed.
//
// ── §6: A ROW GROUP, AND THE ACT IN A TRAY ─────────────────────────────────────────────────────
// It was two `dl`s of `DetailRow` with a `Button` sitting beside each one — a control inside a
// definition list, and a row whose tap target was 40 % of its own width. A `Row` IS the tap target
// now and the act opens in the tray every other act on this screen opens in. The three-line
// paragraph under the room meter went with it: a bar that is nearly full says "nearly full", and
// "it costs nothing to keep" is a rule, not a reading.
//
// ── WHAT THIS FILE DOES NOT KNOW ───────────────────────────────────────────────────────────────
// How big the shed is, how full it is, whether a cargo fits. All three are `cmd.do_store`'s rules
// and all three arrive answered. `tuns` is the server's own number.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

type Held = { good: StoredGood; where: 'ashore' | 'aboard' }

export function PortWarehouse({
  portId,
  fleet,
}: {
  portId: string
  /** A fleet of yours lying here, or null — a shed is only reachable from alongside. */
  fleet: FleetView | null
}) {
  const { view, loading } = useWarehouse(portId, fleet?.id ?? null)
  const [held, setHeld] = useState<Held | null>(null)
  const [detent, setDetent] = useState<TrayDetent>('half')
  const [sending, setSending] = useState(false)
  const [refusal, setRefusal] = useState<Refusal | null>(null)
  const issue = useWorld((s) => s.issue)

  const send = (line: string) => {
    if (!fleet || sending) return
    setSending(true)
    setRefusal(null)
    void (async () => {
      const okay = await issue(fleet.id, line, null)
      setSending(false)
      if (okay) setHeld(null)
      else setRefusal(useWorld.getState().refusal)
    })()
  }

  if (loading && !view) return <Note tone="neutral">Loading…</Note>
  if (!view) return <Note tone="neutral">No warehouse in this port.</Note>

  const free = Math.max(0, view.cap - view.used)
  const open = (good: StoredGood, where: Held['where']) => {
    setRefusal(null)
    setDetent('half')
    setHeld({ good, where })
  }

  return (
    <div data-testid="port-warehouse">
      {/* HOW FULL, AS A BAR. A warehouse's limit is SPACE, and space is the one thing a number
          alone reads badly — 340 of 450 means nothing until you see how much of the bar is left.
          The figure is the share WITH its whole (docs/WORDS.md law 2): "0 / 450 tons". */}
      <Row
        label="Space"
        value={<Figure value={formatOfTotal(view.used, view.cap)} unit="tons" size="figure" />}
        hairline={false}
      />
      {/* THE BAR IS ITS OWN LINE, not the row's second line: an empty warehouse draws an empty
          track, and an empty track tucked under a one-word label reads as a rule through the word. */}
      <Bar
        pct={view.cap > 0 ? (view.used / view.cap) * 100 : 0}
        tone={free > 0 ? 'accent' : 'warning'}
        label="how full the warehouse is"
        figure={<Figure value={formatInt(free)} unit="tons free" />}
      />

      <SheetSection heading="In the warehouse">
        {view.stored.length === 0 ? (
          <Row label="Nothing of yours is stored here." tone="muted" hairline={false} />
        ) : (
          view.stored.map((g, i) => (
            <Row
              key={g.good}
              label={g.name}
              value={<Figure value={formatTons(g.tuns ?? g.qty * g.bulk)} />}
              chevron={fleet !== null}
              onClick={fleet ? () => open(g, 'ashore') : undefined}
              hairline={i < view.stored.length - 1}
              data-testid={`ashore-${g.good}`}
            />
          ))
        )}
      </SheetSection>

      <SheetSection heading="On your ship">
        {!fleet ? (
          <Row label="None of your fleets are here." tone="muted" hairline={false} />
        ) : view.aboard.length === 0 ? (
          <Row label="No cargo on board." tone="muted" hairline={false} />
        ) : (
          view.aboard.map((g, i) => (
            <Row
              key={g.good}
              label={g.name}
              value={<Figure value={formatTons(g.qty * g.bulk)} />}
              chevron
              onClick={() => open(g, 'aboard')}
              hairline={i < view.aboard.length - 1}
              data-testid={`aboard-${g.good}`}
            />
          ))
        )}
      </SheetSection>

      {held && (
        <Tray
          detent={detent}
          onDetentChange={(next) => (next === 'closed' ? setHeld(null) : setDetent(next))}
          title={held.good.name}
          data-testid="warehouse-tray"
          action={
            <Button
              variant="primary"
              className="w-full"
              busy={sending}
              busyLabel="Sending…"
              onClick={() =>
                send(
                  held.where === 'ashore'
                    ? `TAKE ${held.good.good} ALL`
                    : `STORE ${held.good.good} ALL`,
                )
              }
              data-testid="warehouse-act"
            >
              {held.where === 'ashore' ? 'Load onto ship' : 'Store here'}
            </Button>
          }
        >
          <Row
            label={held.where === 'ashore' ? 'In the warehouse' : 'On your ship'}
            value={<Figure value={formatTons(held.good.tuns ?? held.good.qty * held.good.bulk)} size="figure" />}
            hairline={false}
          />
          {/* The one rule a player must know about a shed, said where it applies and nowhere
              else: what is left here is left HERE. */}
          <Row label="Stored goods can only be picked up at this port." tone="muted" hairline={false} />
          {refusal && (
            <Note tone="danger" code={refusal.code}>
              {refusal.sentence}
            </Note>
          )}
        </Tray>
      )}
    </div>
  )
}
