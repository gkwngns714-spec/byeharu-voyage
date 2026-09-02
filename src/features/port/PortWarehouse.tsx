import { useState } from 'react'
import { Button, DetailRow, Meter, RefusalNote, SectionLabel, fineClass } from '../../components/ui'
import { useWarehouse } from '../../live/useWarehouse'
import { useWorld } from '../../live/worldStore'
import { formatInt } from '../../lib/format'
import type { FleetView, Refusal, StoredGood } from '../../lib/rpc'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE WAREHOUSE — what this city is keeping for you (0070).
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner: *"make a storage, where i can buy trade goods and then store it. The storage is not
// shared between cities, an independeant building."*
//
// ── WHY THE TWO LISTS SIT SIDE BY SIDE ─────────────────────────────────────────────────────────
// This screen does exactly one thing: move a cargo between a hold and a shed. So it shows the two
// places and a button on each line, and nothing else. A player never has to hold "what am I
// carrying" in their head while looking at "what is ashore" — the whole decision is on one page,
// which is rows 15/20/25/28/45/46/51 (*do not send me to another screen*) applied to storage.
//
// Both lists come from ONE read, deliberately: they can disagree if asked separately, and a screen
// that offers to store cargo she no longer carries is a screen that refuses when pressed.
//
// ── WHAT THIS FILE DOES NOT KNOW ───────────────────────────────────────────────────────────────
// How big the shed is, how full it is, whether a cargo fits. All three are `cmd.do_store`'s rules
// and all three arrive answered. This file owns no volume arithmetic — `tuns` is the server's own
// number, folded by the same `goods.bulk` a hold is folded by.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

export function PortWarehouse({
  portId,
  fleet,
}: {
  portId: string
  /** A fleet of yours lying here, or null — a shed is only reachable from alongside. */
  fleet: FleetView | null
}) {
  const { view, loading } = useWarehouse(portId, fleet?.id ?? null)
  const [sending, setSending] = useState<string | null>(null)
  const [refusal, setRefusal] = useState<Refusal | null>(null)
  const issue = useWorld((s) => s.issue)

  const send = (line: string, tag: string) => {
    if (!fleet || sending) return
    setSending(tag)
    setRefusal(null)
    void (async () => {
      const okay = await issue(fleet.id, line, null)
      setSending(null)
      if (!okay) setRefusal(useWorld.getState().refusal)
    })()
  }

  if (loading && !view) return <p className={fineClass()}>Asking the shed what it holds…</p>
  if (!view) return <p className={fineClass()}>This city keeps no warehouse.</p>

  const free = Math.max(0, view.cap - view.used)

  return (
    <div className="space-y-3" data-testid="port-warehouse">
      {/* HOW FULL, AS A BAR. A shed's limit is SPACE, and space is the one thing a number alone
          reads badly — 340 of 450 means nothing until you see how much of the bar is left. */}
      <div>
        <SectionLabel className="mb-1">Room</SectionLabel>
        <Meter pct={view.cap > 0 ? (view.used / view.cap) * 100 : 0} />
        <p className={fineClass('mt-1')}>
          {formatInt(view.used)} of {formatInt(view.cap)} tuns used · {formatInt(free)} free. It
          costs nothing to keep. What is left here stays here — a shed cannot be reached from
          another city.
        </p>
      </div>

      <div>
        <SectionLabel className="mb-1">Ashore in this city</SectionLabel>
        {view.stored.length === 0 ? (
          <p className={fineClass()}>Nothing of yours is ashore here.</p>
        ) : (
          <dl className="space-y-1">
            {view.stored.map((g: StoredGood) => (
              <div key={g.good} className="flex items-baseline justify-between gap-2">
                <DetailRow
                  label={g.name}
                  value={`${formatInt(g.qty)} · ${formatInt(g.tuns ?? g.qty * g.bulk)} t`}
                />
                {fleet && (
                  <Button
                    onClick={() => send(`TAKE ${g.good} ALL`, `take-${g.good}`)}
                    disabled={sending !== null}
                    data-testid={`take-${g.good}`}
                  >
                    {sending === `take-${g.good}` ? '…' : 'Take aboard'}
                  </Button>
                )}
              </div>
            ))}
          </dl>
        )}
      </div>

      <div>
        <SectionLabel className="mb-1">Aboard</SectionLabel>
        {!fleet ? (
          <p className="text-sm text-ink-muted">
            No fleet of yours lies here, so there is nothing to land and nowhere to take anything.
          </p>
        ) : view.aboard.length === 0 ? (
          <p className={fineClass()}>Her hold is empty.</p>
        ) : (
          <dl className="space-y-1">
            {view.aboard.map((g: StoredGood) => (
              <div key={g.good} className="flex items-baseline justify-between gap-2">
                <DetailRow
                  label={g.name}
                  value={`${formatInt(g.qty)} · ${formatInt(g.qty * g.bulk)} t`}
                />
                <Button
                  onClick={() => send(`STORE ${g.good} ALL`, `store-${g.good}`)}
                  disabled={sending !== null}
                  data-testid={`store-${g.good}`}
                >
                  {sending === `store-${g.good}` ? '…' : 'Land it here'}
                </Button>
              </div>
            ))}
          </dl>
        )}
      </div>

      {/* A refusal is the server's, drawn by the ONE renderer every other surface uses (0050) —
          including "the shed here holds 12 more tuns", which is why no arithmetic lives above. */}
      {refusal && <RefusalNote refusal={refusal} />}
    </div>
  )
}
