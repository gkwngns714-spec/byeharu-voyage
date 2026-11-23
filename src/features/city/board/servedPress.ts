import { create } from 'zustand'
import { cmdInvest, cmdLandCollect, cmdOrderHull, type FleetView, type HqMove, type Refusal, type RpcResult } from '../../../lib/rpc'
import { t } from '../../../lib/i18n'
import { useWorld } from '../../../live/worldStore'
import { planLines } from '../../command/plans/planLines'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// ONE PRESS, THE SERVED ACT (0480, docs/design/hq-command-2026-11-23.md v2): lit, every card on HQ's board names the command that commits
// it (`act`), and its press sends it, through the door the building's own press sends it by:
//   cmd.issue_lines   the desk's trip: planLines over the served plan (the course from the chart, as the desk's Go sends it), then the
//                     store's issueLines (the desk's own verb: the fleet's version, the read-back)
//   cmd.fulfil        the store's fulfil (the market's Requests press)
//   cmd.order_hull    the yard's Order (PortYard's call), then the world read back
//   cmd.hire_officer  the store's hireOfficer (the Inn's Hire), into her fleet: seated
//   cmd.invest        the Town Hall's Invest (CityTownHall's call), then the world read back
//   cmd.land_collect  the Land party's Collect (PartyFace's call), then the world read back
// A refusal is the server's own words, kept under the card until its next press; the card stays. Nothing here judges what the
// server judges.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

interface PressState {
  /** The move whose act is on the wire. */
  pending: string | null
  /** The server's refusal, by move id. */
  refused: Record<string, Refusal>
  set: (id: string, pending: boolean, refusal: Refusal | null) => void
}

export const useServedPress = create<PressState>()((set) => ({
  pending: null,
  refused: {},
  set: (id, pending, refusal) =>
    set((s) => {
      const refused = { ...s.refused }
      if (refusal) refused[id] = refusal
      else delete refused[id]
      return { pending: pending ? id : s.pending === id ? null : s.pending, refused }
    }),
}))

/** A store verb's refusal (the store keeps the last one), or a fault's words when it kept none. */
function storeRefusal(): Refusal {
  return useWorld.getState().refusal ?? { code: 'E_REFUSED', sentence: t('desk.tryAgain'), fixes: [], source: 'fault' }
}

async function readBack<T>(r: Promise<RpcResult<T>>): Promise<Refusal | null> {
  const done = await r
  if (!done.ok) return done.refusal
  await useWorld.getState().refresh()
  return null
}

/** Send the move's act. Null when it committed; else the server's refusal. */
async function commit(move: HqMove, fleet: FleetView | null): Promise<Refusal | null> {
  const w = useWorld.getState()
  const act = move.act
  switch (act.rpc) {
    case 'cmd.issue_lines': {
      if (!fleet || !w.seaNav) return storeRefusal()
      const p = act.args.plan
      const text = planLines(
        { good: p.good, buyAt: p.buy_at, sellAt: p.sell_at, units: p.units, max: null, min: null, insure: false },
        fleet,
        w.seaNav,
        w.portByCode,
        { toBuy: [], toSell: p.stops },
      )
      if (!text.ok) {
        const port = w.portByCode[text.noCourseTo]?.name ?? text.noCourseTo
        return { code: 'E_NO_COURSE', sentence: t('desk.noWater', { port }), fixes: [], source: 'server' }
      }
      return (await w.issueLines(fleet.id, text.lines)) ? null : storeRefusal()
    }
    case 'cmd.fulfil':
      return (await w.fulfil(act.args.fleet, act.args.contract)) !== null ? null : storeRefusal()
    case 'cmd.order_hull':
      return readBack(cmdOrderHull(act.args.port, act.args.class))
    case 'cmd.hire_officer':
      return (await w.hireOfficer(act.args.code, act.args.fleet)) ? null : storeRefusal()
    case 'cmd.invest':
      return readBack(cmdInvest(act.args.port, act.args.kind, act.args.shares))
    case 'cmd.land_collect':
      return readBack(cmdLandCollect())
  }
}

/** Press a served card: one act at a time; the refusal kept under the card, cleared by a press that commits. */
export async function pressServed(move: HqMove, fleet: FleetView | null): Promise<void> {
  const s = useServedPress.getState()
  if (s.pending !== null) return
  s.set(move.id, true, null)
  let refusal: Refusal | null
  try {
    refusal = await commit(move, fleet)
  } catch {
    refusal = storeRefusal()
  }
  useServedPress.getState().set(move.id, false, refusal)
}
