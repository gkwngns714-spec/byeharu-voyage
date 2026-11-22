import { formatRelative, instantMs } from '../lib/format'
import type { WorldEvent } from '../lib/rpc'
import type { useT } from '../lib/i18n'

// THE WORDS OF A WORLD EVENT (0469), from what the server served: its effect and its time. Used by ./WorldEventLine.tsx.

type T = ReturnType<typeof useT>

/** What the event does, in one short line: "Food ×2", "Luxuries ×1.75", "Fees +20%". */
export function eventEffectWords(e: WorldEvent, t: T): string {
  if (e.effect === 'TOLL') return t('events.toll', { pct: String(Number(e.toll_pct ?? 0)) })
  const mult = String(Number(e.mult ?? 1))
  return e.categories.includes('food') || e.categories.includes('grain') ? t('events.wantFood', { mult }) : t('events.wantLuxury', { mult })
}

/** "ends in 3 h" while it is on, "starts in 40 min" while it is announced. */
export function eventWhenWords(e: WorldEvent, nowMs: number, t: T): string {
  const at = instantMs(e.live ? e.ends_at : e.starts_at) ?? nowMs
  return t(e.live ? 'events.endsIn' : 'events.startsIn', { when: formatRelative(at, nowMs) })
}

