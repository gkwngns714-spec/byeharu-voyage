import { useState } from 'react'
import { Button, Figure, Row } from '../../components/ui'
import { useHaggleState } from './useHaggleState'
import { formatInt, formatPctPoints } from '../../lib/format'
import { useWorld } from '../../live/worldStore'
import type { MarketGood } from '../../lib/rpc'

// THE BARGAIN, AS ONE ROW inside the buy tray (§6: "Bargain · 3 left · 45 % [Try]").
//
// It rode in COMMAND's trade question until 2026-09-09 — the one thing PORT's tray did not draw.
// BUY's doorway is the quay now (the owner: *"Buy and sell should be in port - market"*), so the
// bargain came with it: `TradeTray` takes it as `children`, under the stock line, and nothing else
// about the tray changed. The act is never disabled by a client rule (the server owns
// E_HAGGLE_SPENT and its sentence); a lost bargain is `ok, won:false`, not an error.
// `useHaggleState` re-asks when the world is read, so a struck concession shows up on the next read.

export function HaggleRow({ fleetId, good }: { fleetId: string; good: MarketGood }) {
  const haggle = useWorld((s) => s.haggle)
  const read = useHaggleState(fleetId, good.code)
  const [busy, setBusy] = useState(false)
  const quay = read.state?.docked === true ? read.state : null
  if (!quay) return null

  return (
    <Row
      label="Haggle"
      data-testid="haggle-row"
      value={
        <span className="flex items-center gap-3">
          <Figure value={formatInt(quay.attempts_left)} unit="tries left" tone="muted" />
          <Figure value={formatPctPoints(quay.next_odds_pct, 0)} tone={quay.next_odds_pct >= 45 ? 'success' : 'warning'} />
          <Button
            variant="secondary"
            size="sm"
            busy={busy}
            busyLabel="…"
            onClick={() => {
              setBusy(true)
              void haggle(fleetId, good.good_id, 'buy').finally(() => setBusy(false))
            }}
          >
            Try
          </Button>
        </span>
      }
    >
      {quay.concession > 0 && (
        <span className="block text-t-caption text-success">
          {formatPctPoints(quay.concession_pct, 1)} off his cut, held
        </span>
      )}
    </Row>
  )
}
