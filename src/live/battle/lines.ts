import type { BattleTicksRead, TickTimeline } from '../../lib/rpc'
import { formatInt } from '../../lib/format'
import type { useT } from '../../lib/i18n'
import type { BattleEvent, BattleState } from './timeline'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE BATTLE'S WORDS (owner 2026-11-15: "what is this? it is too hard to tell. too much words. simplify all").
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// The ONE place an event becomes words. Two readers: the screen's status line (the newest event, said short: "Black Gull
// hits 42", "Miss", "Flees 35%") and the log behind Log ("Black Gull → Santa Rosa 42", "Miss", "Brace"). No sentences, no
// labels round the numbers. The end is one line: "Plundered · 1,200 gold", "Escaped", "Driven off", "Sunk".

type T = ReturnType<typeof useT>

export interface LineCtx {
  t: T
  tl: TickTimeline
  events: readonly BattleEvent[]
}

const shipName = (tl: TickTimeline, s: number, i: number) => (s === 0 ? tl.a : tl.b)[i]?.n ?? '?'

/** The chance of the run a side began at `from`: its roll's, which the timeline already holds. */
function runChance(events: readonly BattleEvent[], s: number, from: number): number | null {
  const roll = events.find((e) => e.kind === 'roll' && e.s === s && e.t >= from)
  return roll && roll.kind === 'roll' ? Math.round(roll.chance) : null
}

/** How the fight ended, in one line. `state` (the playback's) says whether every raider is down: then it is "Sunk". */
export function resultLine(t: T, outcome: string, result: BattleTicksRead['result'], state?: BattleState): string {
  const raiders = state ? state.ships[1].filter((x) => x.up) : []
  const sunk = outcome === 'DRIVEN_OFF' && raiders.length > 0 && raiders.every((x) => x.struck)
  const word = sunk ? t('battle.sunk') : t(`battle.out_${outcome}` as never) || outcome
  const gold = result?.loot || result?.taken || 0
  return gold > 0 ? `${word} · ${t('battle.gold', { n: formatInt(gold) })}` : word
}

/** One event in words. `short`: the status line's wording (a hit names only who fired). */
export function eventLine(ev: BattleEvent, ctx: LineCtx, short: boolean, result: BattleTicksRead['result'] = null, state?: BattleState): string {
  const { t, tl, events } = ctx
  switch (ev.kind) {
    case 'shot': {
      if (!(ev.dmg > 0)) return t('battle.miss')
      const n = `${formatInt(Math.round(ev.dmg))}${ev.crit ? '!' : ''}`
      return short ? t('battle.hits', { name: shipName(tl, ev.s, ev.i), n }) : `${shipName(tl, ev.s, ev.i)} → ${shipName(tl, 1 - ev.s, ev.j)} ${n}`
    }
    case 'use': {
      if (ev.code === 'RN') {
        const chance = runChance(events, ev.s, ev.t)
        if (chance !== null) return t('battle.flees', { n: chance })
      }
      return t(`battle.ab_${ev.code}` as never)
    }
    case 'patch':
      return `${t('battle.ab_PT')} +${formatInt(Math.round(ev.amount))}`
    case 'roll':
      return t(ev.away ? 'battle.away' : 'battle.caught')
    case 'join':
      return t('battle.joins', { name: shipName(tl, ev.s, ev.i) })
    case 'struck':
      return t('battle.sunkShip', { name: shipName(tl, ev.s, ev.i) })
    case 'breakOff':
      return t('battle.brokeOff')
    case 'slipped':
      return t('battle.away')
    case 'noFight':
      return t('battle.noFight')
    case 'boarding':
      return t(ev.surrender ? 'battle.surrendered' : 'battle.boarding')
    case 'end':
      return resultLine(t, ev.outcome || tl.out, result, state)
  }
}
