import { useState } from 'react'
import { Button } from '../../../components/ui'
import { formatInt, formatPctPoints } from '../../../lib/format'
import { useT } from '../../../lib/i18n'
import { useHaggleState } from '../../../live/useHaggleState'
import { useWorld } from '../../../live/worldStore'

// THE BARGAIN ON THE TRADE SHEET (0506; the owner, 2026-11-25: ten tries, each less likely, 5 % of the total a win). ONE LINE, pinned with
// the money and the big button, so a half-raised sheet on a phone shows it: what she holds, the last try's answer, the tries left and
// the next chance as served (`world.haggle_state`), and the press (`cmd.haggle`). The total under it is the dry run's, so a win is seen
// there. The line is as high before a try as after it. The server's own sentence is the line's title; a refusal is printed whole.
// Drawn only while the server serves the `bargain` key (bargain_total_enabled); dark: nothing.

/** The next chance in whole per cent; null under one (the server serves 0.05 for a tenth try: never "0%"). */
const oddsWord = (n: number): string | null => (n < 1 ? null : formatPctPoints(n, 0))

export function BargainPress({ fleet, goodId, code, side }: { fleet: string; goodId: string; code: string; side: 'buy' | 'sell' }) {
  const t = useT()
  const haggle = useWorld((s) => s.haggle)
  const read = useHaggleState(fleet, code)
  const [busy, setBusy] = useState(false)
  const [said, setSaid] = useState<{ words: string; tone: 'won' | 'lost' | 'refused' } | null>(null)
  const quay = read.state?.docked === true ? read.state : null
  const deal = quay?.bargain
  if (!quay || !deal) return null
  const press = () => {
    if (busy) return
    setBusy(true)
    void haggle(fleet, goodId, side).then((r) => {
      setBusy(false)
      if (r) setSaid({ words: r.message, tone: r.won ? 'won' : 'lost' })
      else setSaid({ words: useWorld.getState().refusal?.sentence ?? '', tone: 'refused' })
    })
  }
  const held = deal.held_pct > 0 && (deal.side === null || deal.side === side) ? t(side === 'buy' ? 'desk.bargainOff' : 'desk.bargainUp', { n: formatPctPoints(deal.held_pct, 0) }) : null
  const odds = oddsWord(quay.next_odds_pct) ?? t('desk.bargainUnder')
  return (
    <div className="flex min-h-11 items-center justify-between gap-3" data-testid="bargain" data-left={quay.attempts_left} data-held={deal.held_pct}>
      <span className="min-w-0 text-t-caption tabular-nums" role="status" title={said?.words} data-testid="bargain-said" data-tone={said?.tone}>
        {said?.tone === 'refused' ? (
          <span className="text-danger">{said.words}</span>
        ) : (
          <>
            {(said || held) && (
              <span className={`block font-semibold ${said?.tone === 'lost' ? 'text-ink-muted' : 'text-success'}`} data-testid="bargain-held">
                {[said ? t(said.tone === 'won' ? 'desk.bargainWon' : 'desk.bargainNo') : null, held].filter(Boolean).join(' · ')}
              </span>
            )}
            <span className="text-ink-muted" data-testid="bargain-tries">
              {t('desk.bargainTries', { n: formatInt(quay.attempts_left), of: formatInt(quay.attempts_max), odds })}
            </span>
          </>
        )}
      </span>
      <Button variant="secondary" className="min-h-11 shrink-0" busy={busy} busyLabel="…" disabled={busy || quay.attempts_left <= 0} onClick={press} data-testid="bargain-press">
        {t('trade.bargain')}
      </Button>
    </div>
  )
}
