import { useEffect, useState } from 'react'
import { Chip } from '../components/ui'
import { useT } from '../lib/i18n'
import { cmdRaidOrder, worldEarlySighting, worldRaidRead, type EarlySighting, type RaidOrderWord } from '../lib/rpc'
import { useServedRead } from './useServedRead'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// "IF ATTACKED" — the Buy & sell sheet's one line for her standing order (0477, roadmap 2026-11-23 slice 7).
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// Beside the insurance tick, the order a fleet sails under when raiders close: Fight / Flee / Pay, one press each. It is THE standing order
// (0353: `cmd.raid_order`, read by `world.raid_read`; the fleet page's picker, RaidOrder.tsx, is the same order): the server freezes it
// on the voyage as she leaves, so pressed here it holds for this trip. Drawn only while the early sighting is lit (`world.early_sighting`
// on) and orders are in use (`world.raid_read` on): dark, the sheet is exactly as before. Nothing here judges a chance.

const ORDERS: readonly RaidOrderWord[] = ['FIGHT', 'FLEE', 'PAY']

export function IfAttacked({ fleetId }: { fleetId: string }) {
  const t = useT()
  const lit = useServedRead<EarlySighting>('early-sighting', worldEarlySighting, { name: 'worldEarlySighting', trigger: 0, freshMs: 300_000 })
  const on = lit.view?.on === true
  const [order, setOrder] = useState<{ fleet: string; order: RaidOrderWord | null } | null>(null)
  const [busy, setBusy] = useState(false)

  useEffect(() => {
    if (!on) return
    let live = true
    void worldRaidRead(fleetId).then((r) => {
      if (live && r.ok) setOrder({ fleet: fleetId, order: r.value.on ? (r.value.order ?? null) : null })
    })
    return () => {
      live = false
    }
  }, [fleetId, on])

  const now = on && order?.fleet === fleetId ? order.order : null
  if (!now) return null

  const press = (next: RaidOrderWord) => {
    if (busy || next === now) return
    setBusy(true)
    void cmdRaidOrder(fleetId, next).then((r) => {
      if (r.ok) setOrder({ fleet: fleetId, order: next })
      setBusy(false)
    })
  }

  return (
    <div className="mt-2 flex flex-wrap items-center gap-x-3 gap-y-1" data-testid="plan-if-attacked" data-order={now}>
      <span className="shrink-0 text-t-caption text-ink-muted">{t('desk.ifAttacked')}</span>
      <span className="flex gap-2">
        {ORDERS.map((o) => (
          <Chip key={o} on={now === o} onClick={() => press(o)} className="shrink-0 whitespace-nowrap" data-testid={`plan-if-attacked-${o}`}>
            {t(o === 'FLEE' ? 'fight.orderFlee' : o === 'PAY' ? 'fight.orderPay' : 'fight.orderFight')}
          </Chip>
        ))}
      </span>
    </div>
  )
}
