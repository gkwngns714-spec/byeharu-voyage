import { useEffect, useRef, useState } from 'react'
import { Icon, MasteryRing, glassBesideRailClass, goodIcon, masteredTone } from '../components/ui'
import { useT } from '../lib/i18n'
import type { LedgerEvent, MasterySale } from '../lib/rpc'
import { str } from '../lib/json'
import { goodWordOf, useWorld } from './worldStore'
import { saleMasteryOf, useMasteryLevels } from './goodsMastery'

// A GOOD'S MASTERY ROSE (0479, roadmap 2026-11-23 slice 11). The server says it on the SOLD event (`mastery.up`); this draws it:
//   THE CHIP under an arrival card's sale line (ArrivalCard.tsx): the good's mark in its level ring, popping, and "Mastery 3";
//   THE TOAST for a sale with no arrival card (a press of Sell at the quay): the same chip, low on the glass, gone by itself.
// Nothing is worked out here: the level is the server's. Dark the event carries no mastery and nothing is drawn.

/** The ring's top: the served ladder's, else (the read not yet landed) the level itself at the top, or one past it. */
function topOf(levelsTop: number, m: MasterySale): number {
  if (levelsTop > 0) return levelsTop
  return m.next === null ? m.level : m.level + 1
}

/** A sale that raised a good's mastery: its mark in the level ring (popping), and the level's word. */
export function MasteryUpChip({ m, className = '' }: { m: MasterySale; className?: string }) {
  const t = useT()
  const levels = useMasteryLevels()
  const goodByCode = useWorld((s) => s.goodByCode)
  const g = goodByCode[m.good]
  const name = g?.name ?? m.good
  const top = topOf(levels.top, m)
  const at = m.next === null
  return (
    <span className={`inline-flex items-center gap-1.5 text-t-caption text-accent ${className}`} data-testid="mastery-up" data-good={m.good} data-level={m.level}>
      <MasteryRing level={m.level} top={top} size={26} label={t('mastery.ring', { good: name, n: m.level, top })} className="bv-level-pop">
        <Icon name={goodIcon(m.good, g?.category ?? '')} size={14} />
      </MasteryRing>
      <span className={`font-semibold ${masteredTone(at, '')}`}>{t('mastery.up', { n: m.level })}</span>
    </span>
  )
}

const SHOWN_MS = 4000

/** THE LEVEL-UP TOAST: a SOLD event new since the shell's first read whose mastery rose, when it is not one of an arrival's sales (the
 *  arrival card says those: a VOYAGE_REPORT of the same fleet to the same harbour on the same read). One at a time, the newest. */
export function MasteryToast() {
  const t = useT()
  const seen = useRef<Set<string> | null>(null)
  const [up, setUp] = useState<MasterySale | null>(null)

  useEffect(() => {
    const read = (s: ReturnType<typeof useWorld.getState>) => {
      if (s.phase !== 'ready') return
      if (seen.current === null) {
        seen.current = new Set(s.events.map((e) => e.id))
        return
      }
      const fresh: LedgerEvent[] = s.events.filter((e) => !seen.current!.has(e.id))
      fresh.forEach((e) => seen.current!.add(e.id))
      const arrived = fresh.filter((e) => e.kind === 'VOYAGE_REPORT')
      const rose = fresh
        .filter((e) => !arrived.some((r) => str(r.payload, 'fleet') === str(e.payload, 'fleet') && str(r.payload, 'to') === str(e.payload, 'port')))
        .flatMap((e) => {
          const m = saleMasteryOf(e)
          return m && m.up ? [m] : []
        })
      if (rose.length > 0) setUp(rose[rose.length - 1])
    }
    read(useWorld.getState())
    return useWorld.subscribe(read)
  }, [])

  useEffect(() => {
    if (up === null) return
    const id = window.setTimeout(() => setUp(null), SHOWN_MS)
    return () => window.clearTimeout(id)
  }, [up])

  if (up === null) return null
  return (
    <div className={`pointer-events-none ${glassBesideRailClass()} bottom-40 z-60 flex justify-center px-4 lg:bottom-24`} role="status" aria-live="polite">
      <span
        className="bv-fade-in flex max-w-full items-center gap-2 rounded-control bg-surface-2 px-3 py-2 shadow-float"
        data-testid="mastery-toast"
        aria-label={t('mastery.toast', { good: goodWordOf(up.good), n: up.level })}
      >
        <MasteryUpChip m={up} className="text-t-label" />
        <span className={`text-t-label ${masteredTone(up.next === null, 'text-ink')}`}>{goodWordOf(up.good)}</span>
      </span>
    </div>
  )
}
