import { instantMs } from '../lib/format'
import type { FightCard, RosterFleet } from '../lib/rpc'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A SHIP SAILS ON WHEN HER FIGHT ENDS (owner 2026-11-15: every ship of a fight stands still to its end, then resumes).
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// WHAT PROD DID (read 2026-11-15): a battle's open holds a ship under sail for `battle_seconds` (600 s) and moves her eta
// by that much; the fight itself is 1 to 73 s, and at its close the server cuts the hold to the fight's own length and
// moves the eta back (`voyage.hold_cut`). The roster (`world.sea_roster`) serves her again while she is held and NOT when
// the hold is cut, so the map kept the ten-minute hold: she lay still for ten minutes after a fight of one, then jumped.
// (Or, read too late to see the hold at all, she was placed on the eta from before the fight.)
// UNTIL THE ROSTER SERVES THE CUT ITSELF (migration 0444, `world.sea_roster` serves a fleet whose battle just closed),
// this applies the server's own arithmetic to the kept row, from the battle's card: the hold that began at the battle's
// open ends at the battle's end, and the eta moves by exactly the difference. A row the server has already cut is left
// as served, so once 0444 is live this changes nothing and can be deleted.

interface Cut {
  readonly fromMs: number
  readonly untilMs: number
}

/** A cut is kept this long: past it the roster's own full read (every 10 minutes) has replaced the row. */
const KEEP_MS = 15 * 60_000
/** Two instants this near are the same instant (the wire prints microseconds, a Date keeps milliseconds). */
const SAME_MS = 1_000

const cuts = new Map<string, Cut>()

// A CUT IS DRAWN THE MOMENT IT IS KNOWN (main's Acceptance, 2026-11-22: tests/map.fightStill.spec.ts, "the ship set upon sails on",
// 0 px in 8 s on about half the runs, whatever the dice). The map's ships are placed from the kept roster only on the world's beat
// (15 s at 192), so a cut noted between two beats left her on the uncut ten-minute hold, still, for up to a beat after her ring had
// gone. The store listens here and places the kept roster again at once when a cut is new or moved.
let onCut: (() => void) | null = null

/** The one listener a new or moved cut calls (the world store's roster placing). */
export function onFightCut(listener: (() => void) | null): void {
  onCut = listener
}

/** The battles that are over on the last answer of `world.fights()`: each fleet in one was held from its open to its end. */
export function noteFightCuts(cards: readonly FightCard[], nowMs: number): void {
  let moved = false
  for (const c of cards) {
    if ((c.kind ?? 'BATTLE') !== 'BATTLE' || c.status === 'FIGHTING') continue
    const fromMs = instantMs(c.started_at)
    const untilMs = instantMs(c.resolves_at)
    if (fromMs === null || untilMs === null || untilMs < fromMs) continue
    for (const s of c.sides) {
      const was = cuts.get(s.fleet)
      if (!was || was.fromMs !== fromMs || was.untilMs !== untilMs) moved = true
      cuts.set(s.fleet, { fromMs, untilMs })
    }
  }
  for (const [id, cut] of cuts) if (nowMs - cut.untilMs > KEEP_MS) cuts.delete(id)
  if (moved) onCut?.()
}

/** PURE: one roster row with the hold of a battle that ran `fromMs`..`untilMs` as the server leaves it at the close. */
export function withHoldCut(f: RosterFleet, cut: Cut): RosterFleet {
  const v = f.voyage
  if (!v) return f
  const dep = instantMs(v.departed_at)
  const eta = instantMs(v.eta)
  if (dep === null || eta === null || dep > cut.fromMs) return f
  const holds = v.holds ?? []
  const i = holds.findIndex((h) => Math.abs((instantMs(h.from) ?? Number.NaN) - cut.fromMs) < SAME_MS)
  const until = new Date(cut.untilMs).toISOString()
  if (i >= 0) {
    const was = instantMs(holds[i].until)
    if (was === null || was <= cut.untilMs + SAME_MS) return f
    const next = holds.slice()
    next[i] = { ...holds[i], until }
    return { ...f, voyage: { ...v, holds: next, eta: new Date(eta - (was - cut.untilMs)).toISOString() } }
  }
  // a row from before the fight: it has no hold at all, and its eta is the one from before the fight
  if (eta <= cut.fromMs) return f
  return { ...f, voyage: { ...v, holds: [...holds, { from: new Date(cut.fromMs).toISOString(), until }], eta: new Date(eta + (cut.untilMs - cut.fromMs)).toISOString() } }
}

/** A kept roster row as the map places it: with her last fight's hold cut, when a fight of hers has just ended. */
export function cutRosterRow(f: RosterFleet): RosterFleet {
  const cut = cuts.get(f.id)
  return cut ? withHoldCut(f, cut) : f
}
