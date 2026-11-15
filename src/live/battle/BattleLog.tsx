import type { BattleTicksRead, TickTimeline } from '../../lib/rpc'
import { formatInt } from '../../lib/format'
import { useT } from '../../lib/i18n'
import { tickClock, type BattleEvent } from './timeline'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE LOG (0435, docs/design/tick-combat.md 11: "the log, every event in words"). One line an event, newest on top, up to
// the tick being played: each shot (who, which gun or ability, at whom, hit or miss, the damage, a crit, the hull left),
// each ability used (with the side's Fury after), a Patch, each run's roll with its chance, a ship coming up, a ship
// struck, the break-off, the boarding, and the end with how it ended and, once closed, the loot and the crew lost.
// The words are `battle.*`; the numbers are the timeline's.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const SEP = ' · '

export function BattleLog({
  tl,
  events,
  tick,
  sideNames,
  result,
}: {
  tl: TickTimeline
  events: BattleEvent[]
  tick: number
  sideNames: [string, string]
  result: BattleTicksRead['result']
}) {
  const t = useT()
  const ship = (s: number, i: number) => (s === 0 ? tl.a : tl.b)[i]?.n ?? '?'
  const sideName = (s: number) => (s === 0 || s === 1 ? sideNames[s] : '')
  const shown = events.filter((e) => e.t <= tick).reverse()

  const words = (ev: BattleEvent): { tone: string; parts: string[] } => {
    switch (ev.kind) {
      case 'shot':
        return {
          tone: ev.dmg > 0 ? (ev.crit ? 'text-accent' : 'text-ink') : 'text-ink-muted',
          parts: [
            ship(ev.s, ev.i),
            `${t(`battle.ab_${ev.code}`)} → ${ship(1 - ev.s, ev.j)}`,
            ev.dmg > 0 ? t('battle.hit', { n: formatInt(Math.round(ev.dmg)) }) : t('battle.miss'),
            ...(ev.crit ? [t('battle.crit')] : []),
            t('battle.hullLeft', { n: formatInt(Math.round(ev.left)) }),
          ],
        }
      case 'use':
        return { tone: 'text-accent', parts: [sideName(ev.s), t(`battle.ab_${ev.code}` as never), t('battle.furyAt', { n: Math.round(ev.fury) })] }
      case 'patch':
        return {
          tone: 'text-success',
          parts: [ship(ev.s, ev.i), t('battle.ab_PT'), t('battle.repaired', { n: formatInt(Math.round(ev.amount)) }), t('battle.hullLeft', { n: formatInt(Math.round(ev.hull)) })],
        }
      case 'roll':
        return { tone: ev.away ? 'text-success' : 'text-warning', parts: [sideName(ev.s), t('battle.roll', { n: Math.round(ev.chance) }), t(ev.away ? 'battle.away' : 'battle.caught')] }
      case 'join': {
        const fl = (ev.s === 0 ? tl.a : tl.b)[ev.i]?.fl
        return { tone: 'text-info', parts: [ship(ev.s, ev.i), ...(fl && fl !== ship(ev.s, ev.i) ? [fl] : []), t('battle.joins'), sideName(ev.s)] }
      }
      case 'struck':
        return { tone: 'text-danger', parts: [ship(ev.s, ev.i), t('battle.struck')] }
      case 'breakOff':
        return { tone: 'text-warning', parts: [sideName(1), t('battle.brokeOff')] }
      case 'slipped':
        return { tone: 'text-success', parts: [sideName(0), t('battle.slipped')] }
      case 'noFight':
        return { tone: 'text-ink-muted', parts: [t('battle.noFight')] }
      case 'boarding':
        return {
          tone: 'text-warning',
          parts: [t('battle.boarding'), t('battle.strength', { n: ev.ratio.toFixed(2) }), t(ev.surrender ? 'battle.surrendered' : 'battle.held')],
        }
      case 'end': {
        const out = ev.outcome || tl.out
        const extra: string[] = []
        if (result?.loot) extra.push(t('battle.loot', { n: formatInt(result.loot) }))
        else if (result?.taken) extra.push(t('battle.loot', { n: formatInt(result.taken) }))
        if (result?.crew_lost) extra.push(t('battle.crewLost', { n: formatInt(result.crew_lost) }))
        return { tone: 'text-ink', parts: [t('battle.end'), t(`battle.out_${out}` as never), ...extra] }
      }
    }
  }

  return (
    <ol className="flex flex-col gap-1 text-t-label" data-testid="battle-log" aria-live="polite">
      {shown.map((ev) => {
        const w = words(ev)
        return (
          <li key={ev.id} className="flex gap-2" data-testid="battle-log-line" data-kind={ev.kind}>
            <span className="shrink-0 tabular-nums text-ink-faint">{tickClock(ev.t, tl.ms)}</span>
            <span className={`min-w-0 break-words ${w.tone}`}>{w.parts.filter((p) => p !== '').join(SEP)}</span>
          </li>
        )
      })}
    </ol>
  )
}
