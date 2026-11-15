import type { BattleTicksRead, TickTimeline } from '../../lib/rpc'
import { useT } from '../../lib/i18n'
import { eventLine } from './lines'
import { tickClock, type BattleEvent, type BattleState } from './timeline'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE LOG (0435; shortened 2026-11-15, the owner: "too much words"). Behind the screen's Log button. One SHORT line an
// event, newest on top, up to the tick being played: "0:12 Black Gull → Santa Rosa 42", "0:13 Miss", "0:20 Brace". The
// words are ./lines.ts's (the one place an event becomes words); a line is tinted by the side that acted.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const SIDE_TONE = ['text-info', 'text-danger'] as const

export function BattleLog({
  tl,
  events,
  tick,
  result,
  state,
}: {
  tl: TickTimeline
  events: BattleEvent[]
  tick: number
  result: BattleTicksRead['result']
  state: BattleState
}) {
  const t = useT()
  // a Patch is said once, by its mend ("Patch +24"), not twice
  const shown = events.filter((e) => e.t <= tick && !(e.kind === 'use' && e.code === 'PT')).reverse()
  const ctx = { t, tl, events }
  const tone = (ev: BattleEvent) => (ev.kind === 'end' ? 'text-ink' : ev.kind === 'shot' && !(ev.dmg > 0) ? 'text-ink-muted' : (SIDE_TONE[ev.s] ?? 'text-ink'))
  return (
    <ol className="flex flex-col gap-1 text-t-label" data-testid="battle-log" aria-live="polite">
      {shown.map((ev) => (
        <li key={ev.id} className="flex gap-2" data-testid="battle-log-line" data-kind={ev.kind}>
          <span className="shrink-0 tabular-nums text-ink-faint">{tickClock(ev.t, tl.ms)}</span>
          <span className={`min-w-0 break-words ${tone(ev)}`}>{eventLine(ev, ctx, false, result, state)}</span>
        </li>
      ))}
    </ol>
  )
}
