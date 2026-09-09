import { useEffect } from 'react'
import { Figure, Icon, Row } from '../../components/ui'
import { formatPctPoints, formatRelative } from '../../lib/format'
import { useWorld } from '../../live/worldStore'
import { useShellState } from '../../app/shellState'
import type { BuffsView } from '../../lib/rpc'

// WHAT IS ON AT THE QUAY — the visible half of 0026, in one row.
//
// ── WHY A FAIR HAD TO BECOME VISIBLE ───────────────────────────────────────────────────────────
// 0026 shaves 30 per cent off the port's published cut for a few days, through `world.spread()`,
// which every quote and every executed trade already composes. So before this file the fair was
// REAL and INVISIBLE: the price simply differed and nothing on the screen said why.
//
// ── AND WHY "NOTHING IS ON" IS NOT NEWS (docs/UI_DIRECTION.md §2 item 9) ───────────────────────
// It used to print `The quay is quiet — nothing is on.` with a ⓘ carrying the whole catalogue of
// what CAN be on — a line a player reads 98 visits out of 100 (0026 measured a fair at ~1.6% of
// port-days) saying that nothing happened. §6: *"a running fair is one accent `Row` at the top,
// only when true"*. So the quiet state renders NOTHING, and the catalogue of what can happen goes
// with it: it was a paragraph about a mechanic, and the mechanic announces itself when it fires.
//
// ── THERE IS ONE SPREAD NUMBER, AND THIS ROW IS NOT IT ─────────────────────────────────────────
// `world.buffs()` serves `spread_published`, and it is the same figure `world.market()` serves as
// `port.spread` — 0026's self-assert (d) requires the two to be equal. The Town face prints that
// one. What this row prints is `buff_pct`: served, already capped, and the one figure that is
// ABOUT the fair rather than about the port. Two printings of one number are two authorities the
// moment their payloads are fetched a second apart (docs/NO_SPAGHETTI.md §1).
//
// ── THE CLIENT NEVER DECIDES WHETHER A FAIR IS ON ──────────────────────────────────────────────
// `live` is the server's own reading of the window at the payload's `now`. This file filters on
// that flag and never recomputes it from `starts_at`/`ends_at`. Staleness is answered by ASKING
// AGAIN (`quayEdgeMs` below), never by flipping the flag.

/**
 * WHAT IS ON AT THIS QUAY RIGHT NOW, or nothing at all.
 *
 * IT OWNS ITS OWN READ, the way every face does: the component that renders a payload is the one
 * that asks for it, so there is nowhere for a caller to render this and forget. The read also
 * settles the calendar (0026 §6: "the read IS the catch-up") — though since 0028 it is no longer
 * the only caller that winds it, so a fair now happens because the game is being played.
 */
export function QuayFair({ portId }: { portId: string | null }) {
  const buffs = useWorld((s) => (portId ? s.buffs[portId] : undefined))
  const loadBuffs = useWorld((s) => s.loadBuffs)
  // THE ONE CLOCK (app/shellState). A timer of this row's own would be the second one, and two
  // countdowns in this app would then disagree by a second.
  const { nowMs } = useShellState()

  // RE-ASK AT THE EDGE, NEVER RE-REASON. A fair opens and closes on served instants; when the clock
  // crosses one, the payload in hand has stopped being true. The `buffsAt < edge` term is what
  // makes this terminate: after the re-read the payload's own `now` is past that edge.
  const edge = buffs ? quayEdgeMs(buffs) : null
  const buffsAt = buffs ? Date.parse(buffs.now) : null
  useEffect(() => {
    if (!portId) return
    if (!buffs) {
      void loadBuffs(portId)
      return
    }
    if (edge !== null && nowMs >= edge && buffsAt !== null && buffsAt < edge) {
      void loadBuffs(portId)
    }
  }, [portId, buffs, edge, buffsAt, nowMs, loadBuffs])

  const live = buffs?.port ? buffs.port.running.filter((r) => r.live) : []
  if (!buffs || !buffs.port || live.length === 0) return null

  return (
    <Row
      tone="accent"
      mark={<Icon name="wreath" size={20} />}
      label={`${live.map((r) => r.name).join(' · ')} — ends ${formatRelative(Date.parse(live[0].ends_at), nowMs)}`}
      value={
        <Figure value={formatPctPoints(buffs.port.buff_pct)} unit="off the cut" tone="accent" />
      }
      data-testid="quay-fair"
    />
  )
}

/**
 * THE INSTANT THIS PAYLOAD STOPS BEING TRUE, or null when nothing at this quay turns on a clock.
 *
 * NULL IS NOT "NOTHING WILL EVER HAPPEN HERE": a season that has drawn no fair for this port has
 * no row to edge on, and the next season's draw arrives with the next read.
 */
function quayEdgeMs(buffs: BuffsView): number | null {
  const edges = (buffs.port?.running ?? [])
    .map((r) => Date.parse(r.live ? r.ends_at : r.starts_at))
    .filter((ms) => Number.isFinite(ms))
  return edges.length === 0 ? null : Math.min(...edges)
}
