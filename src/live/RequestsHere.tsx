import { useMemo, useState } from 'react'
import { Field } from '../components/ui'
import { FulfilTray } from './FulfilTray'
import { RequestBoard } from './RequestBoard'
import { fleetCargoByCode } from '../domain/fleet'
import { useRequests } from './useRequests'
import { fold, foldedMatch } from '../lib/text'
import type { FleetView, SnapshotPort, TradeRequest } from '../lib/rpc'
import { useT } from '../lib/i18n'

// A CITY'S REQUESTS, FOR HER FLEET LYING THERE (2026-11-24, H3 `desk-into-hq`): the list, its filter, and the Fulfil tray. It was
// the Requests face of PortTrade, the Office's market, whose Buy / Sell list, basket and haggle went with the Office: the one
// trade list is HQ's Market plate and the one trade sheet is TradePanel (src/app/HqSheet.tsx).

export function RequestsHere({ fleet, port }: { fleet: FleetView; port: SnapshotPort }) {
  const t = useT()
  const [filter, setFilter] = useState('')
  const [open, setOpen] = useState<TradeRequest | null>(null)
  const aboard = useMemo(() => fleetCargoByCode(fleet), [fleet])
  const board = useRequests(port.id)
  const q = fold(filter.trim())
  const requests = useMemo(
    () => (board.view ? board.view.contracts.filter((r) => foldedMatch(q, r.name, r.good, r.category)) : null),
    [board.view, q],
  )
  // the open request as the board serves it now (its filled count moves), else as pressed
  const request = open ? (board.view?.contracts.find((r) => r.id === open.id) ?? open) : null
  return (
    <>
      <Field
        value={filter}
        onChange={(e) => setFilter(e.target.value)}
        onClear={() => setFilter('')}
        aria-label={t('trade.filterGoods')}
        placeholder={t('trade.filterGoods')}
        spellCheck={false}
        autoCorrect="off"
      />
      <RequestBoard requests={requests} loading={board.loading} aboard={aboard} docked pick={open?.id ?? null} onPick={setOpen} at={port.code} />
      {request && <FulfilTray fleet={fleet} request={request} aboard={aboard[request.good] ?? 0} onClose={() => setOpen(null)} onSettled={() => setOpen(null)} />}
    </>
  )
}
