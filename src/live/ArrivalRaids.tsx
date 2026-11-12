import { useEffect, useState } from 'react'
import { Button } from '../components/ui'
import { payloadFights } from '../features/ledger/headline'
import { useT } from '../lib/i18n'
import { FightLog } from './FightLog'
import { fightHull } from './fightLines'
import { useWorld } from './worldStore'

// THE RAIDS OF AN ARRIVAL, on the arrival card (0353, owner row 315; docs/COMBAT_LOG.md 1.5): one line a raid the
// voyage fought (`Raid: Fled · Hull −30%`) and a Log press that unfolds the one log component inside the card,
// scrolling within it, its lines coming one at a time. It reads the arrivals' own VOYAGE_REPORT events (by id, from
// the ledger the world store already holds) and the logs the server kept in them; a report with no log (an old one, a
// quiet passage) draws nothing here. `onOpen` tells the card a log is open, so its timer waits.

export function ArrivalRaids({ ids, onOpen }: { ids: readonly string[]; onOpen: (open: boolean) => void }) {
  const t = useT()
  const events = useWorld((s) => s.events)
  const [open, setOpen] = useState<string | null>(null)
  const raids = ids.flatMap((id) => {
    const e = events.find((x) => x.id === id)
    return e ? payloadFights(e.payload).flatMap((f, i) => (f.log ? [{ key: `${id}:${i}`, log: f.log, loss: f.loss }] : [])) : []
  })
  useEffect(() => {
    onOpen(open !== null)
  }, [open, onOpen])
  if (raids.length === 0) return null
  return (
    <div className="mt-1" data-testid="arrival-raids">
      {raids.map((r) => (
        <div key={r.key}>
          <p className="flex items-center justify-between gap-3 text-t-body" data-testid="arrival-raid" data-end={r.log.end}>
            <span className="min-w-0 break-words">{t('fight.raidLine', { end: t(`fight.end_${r.log.end}`), pct: fightHull(r.log).lostPct })}</span>
            <Button variant="secondary" size="sm" aria-expanded={open === r.key} data-testid="arrival-raid-log" onClick={() => setOpen(open === r.key ? null : r.key)}>
              {t('fight.log')}
            </Button>
          </p>
          {open === r.key && <FightLog log={r.log} loss={r.loss} dense paced />}
        </div>
      ))}
    </div>
  )
}
