import { useState } from 'react'
import { Button, DetailRow, RefusalNote, SectionLabel, fineClass } from '../../components/ui'
import { useWorkstation } from '../../live/useWorkstation'
import { useWorld } from '../../live/worldStore'
import { formatInt } from '../../lib/format'
import type { FleetView, Refusal, WorkstationItem } from '../../lib/rpc'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE WORKSTATION — where trade goods become a fitting (0068).
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner: *"a workstation where you can create ship related items - sail etc."*
//
// ── WHAT THIS FILE DOES NOT KNOW ───────────────────────────────────────────────────────────────
// Whether a fitting can be made here. Whether her hold carries the materials. What a suit of sails
// is made of. All three come down the wire from `world.workstation(port, fleet)`, because all three
// are rules `cmd.do_make` enforces — and a screen that worked them out separately would be a second
// implementation that disagrees with the server the first day either changes.
//
// So this file owns NO recipe arithmetic and NO legality check. It shows what the server said, and
// sends one line through the one door (`cmd.issue`) when the player presses.
//
// ── WHY EVERY FITTING IS LISTED, INCLUDING THE ONES THIS CITY CANNOT MAKE ──────────────────────
// Hiding them would make the catalogue look smaller than it is and leave a player wondering where
// copper sheathing went. A fitting this city is not good enough for says so, with the tier it
// wants — which is how a player learns that a workstation has a size at all, and starts looking for
// a better one. That is the same rule the market face follows: show the fact, let them find the
// answer.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/** What is missing from her hold for one of these, in the server's own numbers. */
function shortfall(item: WorkstationItem): string | null {
  const short = item.recipe.filter((r) => r.aboard !== null && r.aboard < r.qty)
  if (short.length === 0) return null
  return short.map((r) => `${r.name} ${formatInt(r.aboard ?? 0)}/${formatInt(r.qty)}`).join(' · ')
}

export function PortWorkstation({
  portId,
  fleet,
  tier,
}: {
  portId: string
  /** A fleet of yours lying here, or null — her hold is what a fitting is made from. */
  fleet: FleetView | null
  /** This city's workstation tier, from the port's own building row. */
  tier: number
}) {
  const { view, loading } = useWorkstation(portId, fleet?.id ?? null)
  const [sending, setSending] = useState<string | null>(null)
  const [refusal, setRefusal] = useState<Refusal | null>(null)
  const [made, setMade] = useState<string | null>(null)
  const issue = useWorld((s) => s.issue)

  const make = (item: WorkstationItem) => {
    if (!fleet || sending) return
    setSending(item.code)
    setRefusal(null)
    setMade(null)
    void (async () => {
      // The line the server will read, in the player's own grammar — the same door every other
      // order goes through. There is no second way an order comes into being.
      const okay = await issue(fleet.id, `MAKE ${item.code}`, null)
      setSending(null)
      if (okay) setMade(item.name)
      else setRefusal(useWorld.getState().refusal)
    })()
  }

  if (loading && !view) {
    return <p className={fineClass()}>Asking the workstation what it can do…</p>
  }
  if (!view) {
    return <p className={fineClass()}>This city keeps no workstation.</p>
  }

  return (
    <div className="space-y-3" data-testid="port-workstation">
      <p className={fineClass()}>
        A tier {formatInt(tier)} workstation. What it makes comes out of the hold of a ship lying
        here, and stays in this city.
      </p>

      {!fleet && (
        <p className="text-sm text-ink-muted">
          No fleet of yours lies here, so there is nothing to make a fitting out of.
        </p>
      )}

      {view.items.map((item) => {
        const short = fleet ? shortfall(item) : null
        // The button appears only when the SERVER says this city can make it and her hold holds
        // it. Everything else states the reason instead — a control that always refuses is worse
        // than no control.
        const ready = item.makeable && fleet !== null && short === null
        return (
          <div key={item.code} className="border-t border-line pt-2">
            <div className="flex items-baseline justify-between gap-2">
              <SectionLabel>{item.name}</SectionLabel>
              {item.owned_here > 0 && (
                <span className={fineClass()}>{formatInt(item.owned_here)} here</span>
              )}
            </div>

            {/* DESIGN 1.3 on the row where a player reads it: every fitting buys one stat and
                spends another, so the choice is a choice and not a shopping list. */}
            <dl className="mt-1 space-y-1">
              <DetailRow label="Buys" value={item.buys} />
              <DetailRow label="Spends" value={item.spends} />
              <DetailRow
                label="Made of"
                value={item.recipe.map((r) => `${r.name} ${formatInt(r.qty)}`).join(' · ')}
              />
            </dl>

            <div className="mt-1.5">
              {!item.makeable ? (
                <p className={fineClass()}>
                  Needs a tier {formatInt(item.ws_tier)} workstation. This one is tier{' '}
                  {formatInt(tier)}.
                </p>
              ) : short !== null ? (
                <p className={fineClass()}>Short of {short}.</p>
              ) : ready ? (
                <Button
                  variant="primary"
                  onClick={() => make(item)}
                  disabled={sending !== null}
                  data-testid={`make-${item.code}`}
                >
                  {sending === item.code ? 'Making…' : `Make ${item.name}`}
                </Button>
              ) : null}
            </div>
          </div>
        )
      })}

      {made && (
        <p className="font-mono text-xs text-sea" data-testid="port-workstation-made">
          made: {made}
        </p>
      )}
      {/* A refusal is the server's, drawn by the ONE renderer every other surface uses (0050). */}
      {refusal && <RefusalNote refusal={refusal} />}
    </div>
  )
}
