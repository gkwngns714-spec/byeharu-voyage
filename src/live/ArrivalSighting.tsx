import { formatInt, formatPriceDelta } from '../lib/format'
import { useT, type TKey } from '../lib/i18n'
import type { Sighting } from './sightingOf'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE EARLY SIGHTING ON THE ARRIVAL CARD (0477, roadmap 2026-11-23 slice 7): what happened, and what insurance and guns would have done.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// It prints the server's EARLY_SIGHTING event (sightingOf.ts) and adds nothing: the pirate and the raid's end, the loss (the ransom that
// left her purse), what the insurer paid back (insured) or would have paid back ((1 - keep) of the loss), and, when she had no guns, the
// same fight's end with her hulls armed like the pirate's (the server ran it). Three short lines at most.

export function ArrivalSighting({ s }: { s: Sighting }) {
  const t = useT()
  const end = (o: string) => (o === 'NO_FIGHT' ? t('battle.noFight') : t(`battle.out_${o}` as TKey))
  return (
    <div className="mt-1" data-testid="arrival-sighting" data-outcome={s.outcome} data-lost={s.lost}>
      <p className="flex justify-between gap-3 text-t-body">
        <span className="min-w-0 break-words">{t('battle.sighted', { pirate: s.pirate, end: end(s.outcome) })}</span>
        {s.lost > 0 && (
          <span className="flex shrink-0 items-baseline gap-2">
            <span className="text-t-caption text-ink-muted">{t('battle.sightLost')}</span>
            <span className="font-semibold tabular-nums text-danger">{formatPriceDelta(-s.lost)}</span>
          </span>
        )}
      </p>
      {s.lost > 0 && (
        <p className="text-t-caption text-ink-muted" data-testid="arrival-sighting-insurance" data-insured={s.insured}>
          {s.insured ? t('battle.insPaid', { n: formatInt(s.paid) }) : t('battle.insWould', { n: formatInt(s.back) })}
        </p>
      )}
      {!s.guns && s.gunsOutcome && (
        <p className="text-t-caption text-ink-muted" data-testid="arrival-sighting-guns" data-outcome={s.gunsOutcome}>
          {t('battle.gunsWould', { end: end(s.gunsOutcome) })}
        </p>
      )}
    </div>
  )
}
