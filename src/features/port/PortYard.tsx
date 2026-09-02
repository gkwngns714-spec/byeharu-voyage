import { useState } from 'react'
import { Button, DetailRow, RefusalNote, SectionLabel, fineClass } from '../../components/ui'
import { useBuildingYard } from '../../live/useBuildingYard'
import { useWorld } from '../../live/worldStore'
import { formatDucats, formatInt } from '../../lib/format'
import type { FleetView, HullMaterial, Refusal, YardHull } from '../../lib/rpc'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE BUILDING YARD — where a hull is laid down (0072).
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner: *"i want another building - a 건조소 in korean, where you can create ships. Building
// ships will require not only some of the trading goods, but some items."*
//
// ── THE ONE THING THIS SCREEN HAS TO MAKE OBVIOUS ──────────────────────────────────────────────
// The materials come out of THIS CITY — the warehouse for timber, your store for fittings — and
// never out of her hold. A player who does not understand that will carry 40 tuns of timber to the
// yard, watch the order refuse, and conclude the game is broken. So every material line prints
// what is ashore HERE against what she wants, and the shortfall says "ashore" in words.
//
// ── WHAT THIS FILE DOES NOT KNOW ───────────────────────────────────────────────────────────────
// Whether a hull can be built here. All of that is `cmd.do_build`'s and arrives answered. This
// file owns no recipe arithmetic and no legality check; it shows what the server said and sends
// one line through the one door.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/** What is missing, in the server's own numbers, or null when everything is to hand. */
function shortfall(hull: YardHull): string | null {
  const short = [...hull.goods, ...hull.items].filter((m) => m.have < m.qty)
  if (short.length === 0) return null
  return short.map((m) => `${m.name} ${formatInt(m.have)}/${formatInt(m.qty)}`).join(' · ')
}

function materials(list: readonly HullMaterial[]): string {
  return list.map((m) => `${m.name} ${formatInt(m.qty)}`).join(' · ')
}

export function PortYard({
  portId,
  fleet,
  tier,
}: {
  portId: string
  /** A fleet of yours lying here, or null — a new hull joins the fleet that ordered her. */
  fleet: FleetView | null
  /** This city's building-yard tier, from the port's own building row. */
  tier: number
}) {
  const { view, loading } = useBuildingYard(portId)
  const [naming, setNaming] = useState<string | null>(null)
  const [name, setName] = useState('')
  const [sending, setSending] = useState(false)
  const [refusal, setRefusal] = useState<Refusal | null>(null)
  const [launched, setLaunched] = useState<string | null>(null)
  const issue = useWorld((s) => s.issue)

  const build = (hull: YardHull) => {
    if (!fleet || sending || name.trim().length < 3) return
    setSending(true)
    setRefusal(null)
    setLaunched(null)
    void (async () => {
      const okay = await issue(fleet.id, `BUILD ${hull.class} ${name.trim()}`, null)
      setSending(false)
      if (okay) {
        setLaunched(name.trim())
        setNaming(null)
        setName('')
      } else {
        setRefusal(useWorld.getState().refusal)
      }
    })()
  }

  if (loading && !view) return <p className={fineClass()}>Asking the yard what it can lay down…</p>
  if (!view) return <p className={fineClass()}>This city lays down no hulls.</p>

  return (
    <div className="space-y-3" data-testid="port-yard">
      <p className={fineClass()}>
        A tier {formatInt(tier)} yard. What she is built from comes out of this city — timber from
        the warehouse here, fittings from your store here — and never out of a hold.
      </p>

      {!fleet && (
        <p className="text-sm text-ink-muted">
          No fleet of yours lies here, and a new hull joins the fleet that ordered her.
        </p>
      )}

      {view.hulls.map((hull) => {
        const short = shortfall(hull)
        const ready = hull.buildable && fleet !== null && short === null
        return (
          <div key={hull.class} className="border-t border-line pt-2">
            <div className="flex items-baseline justify-between gap-2">
              <SectionLabel>{hull.name}</SectionLabel>
              <span className={fineClass()}>{formatDucats(hull.ducats)} for the work</span>
            </div>
            <p className={fineClass('mt-0.5')}>{hull.note}</p>

            <dl className="mt-1 space-y-1">
              <DetailRow
                label="She is"
                value={`${formatInt(hull.hold)} tuns · ${hull.speed_kn} kn · ${formatInt(hull.crew_required)} hands · draft ${formatInt(hull.draft)}`}
              />
              <DetailRow label="Timber" value={materials(hull.goods)} />
              <DetailRow label="Fittings" value={materials(hull.items)} />
            </dl>

            <div className="mt-1.5">
              {!hull.buildable ? (
                <p className={fineClass()}>
                  Wants a tier {formatInt(hull.yard_tier)} yard. This one is tier {formatInt(tier)}.
                </p>
              ) : short !== null ? (
                <p className={fineClass()}>Ashore here: {short}.</p>
              ) : naming === hull.class ? (
                // THE NAME IS THE PLAYER'S, and it is asked for before the order is sent rather
                // than invented — a ship you did not name is not yours.
                <div className="flex flex-wrap items-center gap-2">
                  <input
                    className="rounded border border-line bg-surface px-2 py-1 font-mono text-sm text-ink"
                    placeholder="Name her"
                    value={name}
                    maxLength={24}
                    onChange={(e) => setName(e.target.value)}
                    data-testid="yard-name"
                  />
                  <Button
                    variant="primary"
                    onClick={() => build(hull)}
                    disabled={sending || name.trim().length < 3}
                    data-testid={`lay-down-${hull.class}`}
                  >
                    {sending ? 'Laying down…' : 'Lay her down'}
                  </Button>
                </div>
              ) : ready ? (
                <Button onClick={() => setNaming(hull.class)} data-testid={`name-${hull.class}`}>
                  Build a {hull.name}
                </Button>
              ) : null}
            </div>
          </div>
        )
      })}

      {launched && (
        <p className="font-mono text-xs text-sea" data-testid="port-yard-launched">
          laid down: {launched}
        </p>
      )}
      {refusal && <RefusalNote refusal={refusal} />}
    </div>
  )
}
