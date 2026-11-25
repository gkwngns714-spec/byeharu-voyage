import { useState } from 'react'
import { Button } from '../../../components/ui'
import { formatInt, formatPctPoints } from '../../../lib/format'
import { useT } from '../../../lib/i18n'
import { useHaggleState } from '../../../live/useHaggleState'
import { useWorld } from '../../../live/worldStore'

// THE BARGAIN ON THE TRADE SHEET (0506; the owner, 2026-11-25: ten tries, each less likely, 5 % of the total a win). One line and one
// press: the tries left and the next chance as served (`world.haggle_state`), what she holds, and Bargain (`cmd.haggle`). The total
// under it is the dry run's, so a win is seen there. Her answer (the server's own sentence) has a line held for it: a press moves
// nothing. Drawn only while the server serves the `bargain` key (bargain_total_enabled); dark: nothing.

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
  const spent = quay.attempts_left <= 0
  return (
    <div className="border-t border-edge py-2" data-testid="bargain" data-left={quay.attempts_left} data-held={deal.held_pct}>
      <div className="flex items-center justify-between gap-3">
        <span className="min-w-0 text-t-caption tabular-nums text-ink-muted">
          <span className="block text-t-label text-ink">{deal.held_pct > 0 ? t(side === 'buy' ? 'desk.bargainOff' : 'desk.bargainUp', { n: formatPctPoints(deal.held_pct, 0) }) : t('trade.bargain')}</span>
          <span data-testid="bargain-tries">{t('desk.bargainTries', { n: formatInt(quay.attempts_left), of: formatInt(quay.attempts_max), odds: formatPctPoints(quay.next_odds_pct, quay.next_odds_pct < 10 ? 1 : 0) })}</span>
        </span>
        <Button variant="secondary" className="min-h-11 shrink-0" busy={busy} busyLabel="…" disabled={busy || spent} onClick={press} data-testid="bargain-press">
          {t('trade.bargain')}
        </Button>
      </div>
      <p className={`min-h-[2.25rem] text-t-caption ${said?.tone === 'won' ? 'text-success' : said?.tone === 'refused' ? 'text-danger' : 'text-ink-muted'}`} role="status" data-testid="bargain-said">
        {said?.words}
      </p>
    </div>
  )
}
