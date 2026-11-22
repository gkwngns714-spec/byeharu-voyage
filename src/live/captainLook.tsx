import { Icon, Portrait, Ring } from '../components/ui'
import { formatInt } from '../lib/format'
import { t as tNow } from '../lib/i18n'
import type { CaptainCard, CaptainLevel, CaptainTrait } from '../lib/rpc'
import { focusWord, jobWord, roleOf, traitLine, traitLines, traitWorks } from './captainWords'
import { captainTint, effectIcon, levelsThatMatter } from './captainMarks'
import { Mark } from './LevelTiles'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// HOW A CAPTAIN LOOKS (2026-11-23, the visual overhaul's slice 6: You > Captains, the Inn, the captain sheet).
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// ONE PLACE for the three pictures a captain is drawn with, so the Inn, You and the Codex draw her the same (their rules are
// captainMarks.ts'):
//   * HER PLATE   `CaptainPortrait`: the hat of her role (roleOf), her grade in the corner, on a disc in her home tongue's tint.
//   * HER RINGS   `LevelRings`: the two levels that matter, each its track's mark (levelWords.ts) in a ring filled by her points
//                 toward the next level, the level beside it.
//   * HER TRAITS  `TraitChips`: a chip a trait, a glyph a line of what it does and the line's figure; a trait that does nothing is
//                 not drawn (`traitWorks`, X7). Its name is the chip's accessible name and tooltip.

/** Her plate. `label` when it stands for her without her name beside it. */
export function CaptainPortrait({ captain, size = 36, label }: { captain: CaptainCard & { code: string }; size?: number; label?: string }) {
  return (
    <Portrait
      role={roleOf(captain)}
      tint={captainTint(captain)}
      seed={captain.code}
      grade={captain.grade ?? null}
      top={(captain.grade_ord ?? 0) >= 4}
      size={size}
      label={label}
    />
  )
}

/** One level as its mark in a ring, and the level beside it. */
export function LevelRing({ level, size = 30 }: { level: CaptainLevel; size?: number }) {
  const word = focusWord(level.track) ?? level.word
  const pct = level.next_at > 0 ? Math.min(1, level.points / level.next_at) * 100 : 0
  return (
    <span className="inline-flex items-center gap-1" data-testid={`captain-ring-${level.track}`} data-level={level.level}>
      <Ring pct={pct} size={size} label={tNow('books.levelRing', { track: word, n: formatInt(level.level) })}>
        <span className="text-accent">
          <Mark code={level.track} size={Math.round(size * (size < 28 ? 0.6 : 0.5))} />
        </span>
      </Ring>
      <span className={`tabular-nums ${size < 28 ? 'text-t-caption text-ink-muted' : 'text-t-body'}`} aria-hidden="true">
        {formatInt(level.level)}
      </span>
    </span>
  )
}

/** The two rings that matter, side by side. */
export function LevelRings({ captain, size }: { captain: CaptainCard & { levels: readonly CaptainLevel[] }; size?: number }) {
  return (
    <span className="inline-flex items-center gap-3" data-testid="captain-rings">
      {levelsThatMatter(captain).map((l) => (
        <LevelRing key={l.track} level={l} size={size} />
      ))}
    </span>
  )
}

/** One trait: a glyph and a figure a line. A button when `onPress` is given (her sheet, where she chooses), else a plain chip. */
function TraitChip({ trait, on, onPress, testId }: { trait: CaptainTrait; on: boolean; onPress?: () => void; testId: string }) {
  const name = `${jobWord(trait.word) ?? trait.word}: ${traitLines(trait.lines)}`
  const look = on ? 'border-accent bg-accent-soft text-ink' : 'border-transparent bg-surface-2 text-ink-muted'
  const body = trait.lines.map((l) => (
    <span key={l} className="inline-flex min-w-0 items-center gap-1.5">
      <Icon name={effectIcon(l)} size={16} className={on ? 'shrink-0 text-accent' : 'shrink-0'} />
      <span className="min-w-0 break-words">{traitLine(l)}</span>
    </span>
  ))
  const shape = `inline-flex max-w-full flex-wrap items-center gap-x-3 gap-y-1 rounded-chip border px-3 text-left text-t-label ${look}`
  return onPress ? (
    <button type="button" onClick={onPress} aria-pressed={on} aria-label={name} title={name} className={`${shape} min-h-11 py-2`} data-testid={testId}>
      {body}
    </button>
  ) : (
    <span role="img" aria-label={name} title={name} className={`${shape} min-h-8 py-1.5`} data-testid={testId}>
      {body}
    </span>
  )
}

/** Her traits that work, as chips. `chosen` lights the ones she uses; `onToggle` makes them presses. */
export function TraitChips({
  traits,
  chosen,
  onToggle,
  testPrefix,
}: {
  traits: readonly CaptainTrait[] | undefined
  chosen?: readonly string[]
  onToggle?: (code: string) => void
  /** `captain-trait` on her sheet, `inn-trait` at the Inn: the chip's test id is `<prefix>-<code>`. */
  testPrefix: string
}) {
  const shown = (traits ?? []).filter(traitWorks)
  if (shown.length === 0) return null
  return (
    <div className="flex flex-wrap gap-2 py-2" data-testid={`${testPrefix}s`}>
      {shown.map((t) => (
        <TraitChip
          key={t.code}
          trait={t}
          on={chosen ? chosen.includes(t.code) : false}
          onPress={onToggle ? () => onToggle(t.code) : undefined}
          testId={`${testPrefix}-${t.code}`}
        />
      ))}
    </div>
  )
}
