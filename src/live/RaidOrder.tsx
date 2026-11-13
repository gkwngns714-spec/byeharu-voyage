import { useEffect, useState } from 'react'
import { dangerLabel, Figure, Note, Row, Segmented, type SegmentSpec } from '../components/ui'
import { formatDucats } from '../lib/format'
import { cmdRaidOrder, worldRaidRead } from '../lib/rpc'
import type { RaidOrderWord, RaidRead, Refusal } from '../lib/rpc'
import { useT } from '../lib/i18n'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A FLEET'S STANDING ORDER WHEN RAIDERS CLOSE: Fight / Flee / Pay (0353, owner row 315: "action that i choose to do
// such as when pressed fight, it keeps on fighting, when flee, it tries to flee"; docs/COMBAT_LOG.md 2.1, 6.2).
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE SERVER JUDGES EVERYTHING. `world.raid_read` says whether orders are in use at all (`on`: while the switch is off
// this draws NOTHING), which order she holds, and the three facts a player chooses by: the raiders' word against her,
// her chance to slip as a word, and what Pay would cost now. `cmd.raid_order` judges the press. Nothing here computes
// a chance or an outcome, and nothing is a forecast: no day's roll is shown.
// The order takes hold at her NEXT departure (the server freezes it on the voyage as she leaves), which the caption
// says. Two mounts: the Send tray under the picked fleet, beside insurance, and the fleet's page.
// THE RAIDERS' ROW names the water it speaks of: `danger` when the caller knows the course's worst water, otherwise
// the most dangerous water on the chart now, by its own tier word (the read takes no course).

// THE PICKER NEVER MOVES THE PAGE UNDER IT (found when the five lights were tested as one tree: on a fleet's page the picker landed after its read and pushed the foot down
// 351 px, under a press on Move). While the read is on its way the SAME rows stand with no figures (`RaidOrderWaiting`), so the answer fills them and nothing shifts; the last
// line (No guns) keeps its place whether or not it has words. Only a world where orders are off draws nothing, and it is remembered for the session (`ordersOff`), so there the
// rows are held open on the first mount alone.

const ORDERS: readonly RaidOrderWord[] = ['FIGHT', 'FLEE', 'PAY']
/** Orders answered `on: false` this session: later mounts hold no room open while their read is on its way. */
let ordersOff = false

export function RaidOrder({ fleetId, danger = null, className = '' }: { fleetId: string; danger?: number | null; className?: string }) {
  const t = useT()
  const [read, setRead] = useState<{ fleet: string; value: RaidRead } | null>(null)
  const [refusal, setRefusal] = useState<Refusal | null>(null)
  const [busy, setBusy] = useState(false)

  useEffect(() => {
    let live = true
    void worldRaidRead(fleetId).then((r) => {
      if (r.ok) ordersOff = !r.value.on
      if (live && r.ok) setRead({ fleet: fleetId, value: r.value })
    })
    return () => {
      live = false
    }
  }, [fleetId])

  const now = read?.fleet === fleetId ? read.value : null
  if (!now) return ordersOff ? null : <RaidOrderWaiting className={className} />
  if (!now.on || !now.order) return null

  const press = (order: RaidOrderWord) => {
    if (busy || order === now.order) return
    setBusy(true)
    setRefusal(null)
    void (async () => {
      const r = await cmdRaidOrder(fleetId, order)
      if (r.ok) {
        const again = await worldRaidRead(fleetId)
        if (again.ok) setRead({ fleet: fleetId, value: again.value })
      } else {
        setRefusal(r.refusal)
      }
      setBusy(false)
    })()
  }

  const segments: SegmentSpec<RaidOrderWord>[] = ORDERS.map((id) => ({
    id,
    label: <span data-testid={`raid-order-${id}`}>{t(id === 'FLEE' ? 'fight.orderFlee' : id === 'PAY' ? 'fight.orderPay' : 'fight.orderFight')}</span>,
  }))
  const foes = now.foes ?? []
  const foe = (danger !== null ? foes.find((f) => f.danger === danger) : undefined) ?? foes[foes.length - 1]

  return (
    <div className={`pb-2 ${className}`} data-testid="raid-order" data-order={now.order}>
      <Row hairline={false} label={t('fight.orders')} value={<span className="text-t-caption text-ink-faint">{t('fight.nextSail')}</span>} />
      <Segmented segments={segments} value={now.order} onChange={press} label={t('fight.orders')} fill columns={3} />
      {refusal && (
        <Note tone="danger" code={refusal.code} data-testid="raid-order-refusal">
          {refusal.sentence}
        </Note>
      )}
      {foe && (
        <Row
          label={t('fight.oddsFoe')}
          value={<Figure value={<span data-testid="raid-order-foe" data-word={foe.word}>{t(`map.attackWord_${foe.word}`)}</span>} />}
          data-testid="raid-order-foe-row"
        >
          <span className="block text-t-caption text-ink-faint">{dangerLabel(foe.danger)}</span>
        </Row>
      )}
      {now.slip && (
        <Row label={t('fight.oddsSlip')} value={<Figure value={<span data-testid="raid-order-slip" data-word={now.slip}>{t(`fight.oddsSlip_${now.slip}`)}</span>} />} />
      )}
      <Row
        label={t('fight.orderPay')}
        value={
          <Figure
            value={
              <span data-testid="raid-order-pay" data-pay={now.pay ?? 0}>
                {(now.pay ?? 0) > 0 ? formatDucats(now.pay ?? 0) : t('fight.noPay_EMPTY')}
              </span>
            }
          />
        }
        hairline={now.guns === false}
      />
      {now.guns === false ? (
        <Row tone="muted" hairline={false} label={t('fight.noGuns')} data-testid="raid-order-noguns" />
      ) : (
        <Row hairline={false} label={BLANK} aria-hidden data-testid="raid-order-guns-line" />
      )}
    </div>
  )
}

/** A line's worth of nothing: a row that keeps its height and says no word. */
const BLANK = '\u00a0'

/** THE PICKER'S ROWS WITH NO FIGURES, while `world.raid_read` is on its way: the same primitives in the same order, so the answer lands in place. No order is marked and no
 *  press is taken. */
function RaidOrderWaiting({ className }: { className: string }) {
  const t = useT()
  const segments: SegmentSpec<RaidOrderWord>[] = ORDERS.map((id) => ({
    id,
    label: <span>{t(id === 'FLEE' ? 'fight.orderFlee' : id === 'PAY' ? 'fight.orderPay' : 'fight.orderFight')}</span>,
  }))
  return (
    <div className={`pb-2 ${className}`} data-testid="raid-order-waiting" aria-busy="true">
      <Row hairline={false} label={t('fight.orders')} value={<span className="text-t-caption text-ink-faint">{t('fight.nextSail')}</span>} />
      <Segmented segments={segments} value={'' as RaidOrderWord} onChange={() => {}} label={t('fight.orders')} fill columns={3} />
      <Row label={t('fight.oddsFoe')} value={<Figure value={BLANK} />}>
        <span className="block text-t-caption text-ink-faint">{BLANK}</span>
      </Row>
      <Row label={t('fight.oddsSlip')} value={<Figure value={BLANK} />} />
      <Row label={t('fight.orderPay')} value={<Figure value={BLANK} />} hairline={false} />
      <Row hairline={false} label={BLANK} aria-hidden />
    </div>
  )
}
