import type { ReactNode } from 'react'
import { Icon } from './Icon'
import type { IconName } from './icons'

// A NEED, AS A MARK AND A FIGURE (HQ's command board, docs/design/hq-command-2026-11-23.md): what a move asks — the fleet that does it,
// the coin it costs, the time it takes, the pirate risk — as a small glyph-led pill, never a sentence. Not a control: it presses
// nothing (a card around it is the press). Its words are the glyph's accessible name when the figure alone would not say it.

export type NeedTone = 'muted' | 'accent' | 'success' | 'warning' | 'danger' | 'info'

const TONE: Record<NeedTone, string> = {
  muted: 'text-ink-muted',
  accent: 'text-accent',
  success: 'text-success',
  warning: 'text-warning',
  danger: 'text-danger',
  info: 'text-info',
}

export function NeedChip({ icon, label, tone = 'muted', children }: { icon: IconName; label?: string; tone?: NeedTone; children?: ReactNode }) {
  return (
    <span className={`inline-flex min-w-0 items-center gap-1 rounded-chip bg-surface-2 px-2 py-0.5 text-t-caption tabular-nums ${TONE[tone]}`} data-need={icon}>
      <Icon name={icon} size={14} className="shrink-0" aria-label={label} role={label ? 'img' : undefined} aria-hidden={label ? undefined : true} />
      {children !== undefined && <span className="min-w-0 break-words text-ink">{children}</span>}
    </span>
  )
}
