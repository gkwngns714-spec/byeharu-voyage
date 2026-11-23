import { Icon } from '../components/ui'
import { formatDucatsDelta } from '../lib/format'
import { useT } from '../lib/i18n'
import { SEA_KIND_ICON, SEA_KIND_WORD, seaOptionWord, type SeaEnd } from './seaChoiceOf'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A CHOICE AT SEA ON THE ARRIVAL CARD (0486, roadmap 2026-11-23 slice 16): the event she met, the option taken (hers, or the safe default),
// and the coin it moved. One line; it prints the server's SEA_CHOICE event (seaChoiceOf.ts) and adds nothing.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

export function ArrivalChoice({ s }: { s: SeaEnd }) {
  const t = useT()
  const word = seaOptionWord(s.option)
  return (
    <p className="mt-1 flex justify-between gap-3 text-t-body" data-testid="arrival-sea" data-kind={s.kind} data-by={s.by} data-amount={s.amount}>
      <span className="flex min-w-0 items-center gap-1.5 break-words">
        <Icon name={SEA_KIND_ICON[s.kind]} size={16} aria-hidden />
        {t(SEA_KIND_WORD[s.kind])} · {word ? t(word) : s.option}
        {s.by === 'default' && <span className="text-t-caption text-ink-muted">({t('hq.seaDefault')})</span>}
      </span>
      {s.amount !== 0 && (
        <span className={`shrink-0 font-semibold tabular-nums ${s.amount < 0 ? 'text-danger' : 'text-success'}`}>{formatDucatsDelta(s.amount)}</span>
      )}
    </p>
  )
}
