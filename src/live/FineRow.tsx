import { useState } from 'react'
import { Button, Figure, Note, Row } from '../components/ui'
import { formatDucats } from '../lib/format'
import { cmdPayFine } from '../lib/rpc'
import type { Refusal, SnapshotPort, TownHallView } from '../lib/rpc'
import { useT } from '../lib/i18n'
import { useWorld } from './worldStore'

/** 0318 (docs/WORLD_POWERS.md §2.1, §4.5): "Fine": what this capital asks of your company, and one button, only while a fleet of yours lies here.
 *  Served only while one is owed, so a hall with none draws nothing. The server holds the coin to what is owed and to your purse. */
export function FineRow({ port, hall }: { port: SnapshotPort; hall: TownHallView }) {
  const t = useT()
  const [paying, setPaying] = useState(false)
  const [refusal, setRefusal] = useState<Refusal | null>(null)
  const refresh = useWorld((s) => s.refresh)
  const fine = hall.dues?.regard?.fine ?? 0
  if (fine <= 0) return null

  const pay = () => {
    if (paying) return
    setPaying(true)
    setRefusal(null)
    void (async () => {
      const r = await cmdPayFine(port.id, fine)
      setPaying(false)
      if (r.ok) await refresh()
      else setRefusal(r.refusal)
    })()
  }

  return (
    <>
      <Row label={t('town.fine')} value={<Figure value={formatDucats(fine)} />} data-testid="townhall-fine">
        {hall.you.docked && (
          <div className="pt-2">
            <Button size="sm" busy={paying} busyLabel={t('town.payingFine')} onClick={pay} data-testid="townhall-pay-fine">
              {t('town.payFine')}
            </Button>
          </div>
        )}
      </Row>
      {refusal && (
        <Note tone="danger" code={refusal.code} figures={refusal.figures}>
          {refusal.sentence}
        </Note>
      )}
    </>
  )
}
