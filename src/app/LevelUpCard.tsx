import { useEffect, useRef, useState } from 'react'
import { Icon, Ring, glassBesideRailClass } from '../components/ui'
import { formatInt } from '../lib/format'
import { useLocale, useT } from '../lib/i18n'
import { worldLevels, type LevelsView } from '../lib/rpc'
import { Mark } from '../live/LevelTiles'
import { levelName, levelOpens } from '../live/levelWords'
import { useServedRead } from '../live/useServedRead'
import { useWorld } from '../live/worldStore'
import { levelLines, type LevelLine } from './levelLines'

// THE LEVEL-UP CARD (roadmap 2026-11-23, slice 10: "loud level-ups"; RS3's level-up, Melvor's). A level crossed was one line on the
// arrival card, held until the next arrival when it came at the quay. Now it is a MOMENT of its own, the instant the ledger says it:
// a full card over the middle of the glass with the level's mark in a gold ring (slice 9's pop and rising chevron, bigger), the
// level, its name, and WHAT IT OPENED (the served benefits of every level crossed, `levelOpens`) and the Reputation it gave, each as
// a mark and its phrase. The arrival card keeps its level line and gift (its trip's sum reads it); the "Opens:" line moved here.
//
// IT READS FACTS THE SERVER ALREADY REPORTS: a LEVEL_UP event (0356) new since the first read of this page (the baseline, as the
// arrival card's: a page load announces nothing it already had). What a level opens is the cached levels read every levels reader
// shares (`worldLevels`), asked only while the card is up.
//
// IT TAKES NO PRESS: the card lets every touch through (pointer-events none) and goes by itself after SHOWN_MS, so it never stands
// between a player and the button under it; the Levels page has the whole of it. Several levels at once are one card, one row each.

const SHOWN_MS = 6_000

export function LevelUpCard() {
  const [lines, setLines] = useState<LevelLine[] | null>(null)
  // each new batch restarts the clock and the moment
  const [beat, setBeat] = useState(0)
  const seen = useRef<Set<string> | null>(null)

  useEffect(() => {
    const read = (s: ReturnType<typeof useWorld.getState>) => {
      if (s.phase !== 'ready') return
      if (seen.current === null) {
        seen.current = new Set(s.events.map((e) => e.id))
        return
      }
      const fresh = s.events.filter((e) => !seen.current!.has(e.id))
      if (fresh.length === 0) return
      fresh.forEach((e) => seen.current!.add(e.id))
      const found = levelLines(fresh)
      if (found.length === 0) return
      setLines((held) => levelLines(fresh, held ?? []))
      setBeat((b) => b + 1)
    }
    read(useWorld.getState())
    return useWorld.subscribe(read)
  }, [])

  useEffect(() => {
    if (lines === null) return
    const id = window.setTimeout(() => setLines(null), SHOWN_MS)
    return () => window.clearTimeout(id)
  }, [lines, beat])

  if (lines === null) return null
  return (
    <div className={`pointer-events-none ${glassBesideRailClass()} top-1/2 z-60 flex -translate-y-1/2 justify-center px-4`} data-testid="level-up-wrap">
      <div
        key={beat}
        role="status"
        aria-live="polite"
        data-testid="level-up-card"
        className="bv-level-card pointer-events-none relative w-full max-w-sm overflow-hidden rounded-card bg-surface-2 p-5 text-ink shadow-float ring-2 ring-accent"
      >
        <span aria-hidden="true" className="bv-level-rays pointer-events-none absolute" />
        <div className="relative flex flex-col gap-4">
          {lines.map((l) => (
            <LevelUpRow key={l.track} line={l} beat={beat} />
          ))}
        </div>
      </div>
    </div>
  )
}

function LevelUpRow({ line, beat }: { line: LevelLine; beat: number }) {
  const t = useT()
  const locale = useLocale()
  const read = useServedRead<LevelsView>('levels', () => worldLevels(), { name: 'worldLevels' })
  const v = read.view
  const skill = v && v.company ? (v.level_skills.skills.find((s) => s.code === line.track) ?? null) : null
  const name = levelName(locale, line.track, skill?.word)
  const crossed = Array.from({ length: line.level - line.low + 1 }, (_, i) => line.low + i)
  const opened = skill ? [...new Set(crossed.flatMap((n) => levelOpens(locale, n, skill.benefits)))] : []
  return (
    <div className="flex flex-col items-center gap-2 text-center" data-testid="level-up-row" data-track={line.track} data-level={line.level}>
      <span className="relative inline-flex">
        <Ring pct={100} size={88} label={t('books.levelRing', { track: name, n: formatInt(line.level) })}>
          <span key={`mark-${beat}`} className="bv-level-pop inline-flex text-accent">
            <Mark code={line.track} size={44} />
          </span>
        </Ring>
        <span key={`up-${beat}`} aria-hidden="true" className="bv-level-up pointer-events-none absolute -top-2 left-1/2 -ml-3 text-accent">
          <Icon name="levelUp" size={24} />
        </span>
      </span>
      <span className="flex items-baseline gap-2">
        <span className="text-t-card text-ink">{name}</span>
        <span key={`n-${beat}`} className="bv-level-pop text-t-hero font-semibold tabular-nums text-accent" data-testid="level-up-level">
          {formatInt(line.level)}
        </span>
      </span>
      {(opened.length > 0 || line.reputation > 0) && (
        <ul className="flex flex-wrap justify-center gap-2" data-testid="level-up-opened">
          {opened.map((what) => (
            <li key={what} className="flex items-center gap-1.5 rounded-control bg-accent-soft px-2 py-1 text-t-label text-ink" data-testid="level-up-opens">
              <Icon name="levelUp" size={14} className="shrink-0 text-accent" />
              <span className="break-words">{what}</span>
            </li>
          ))}
          {line.reputation > 0 && (
            <li className="flex items-center gap-1.5 rounded-control bg-accent-soft px-2 py-1 text-t-label tabular-nums text-ink" data-testid="level-up-gift" data-reputation={line.reputation}>
              <Icon name="laurel" size={14} className="shrink-0 text-accent" />
              {t('command.lvGiftAt', { n: formatInt(line.reputation) })}
            </li>
          )}
        </ul>
      )}
    </div>
  )
}
