import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Figure, PriceRows, Row, Tray, type PriceTrend, type TrayDetent, type TrayMode } from '../components/ui'
import { formatMiles, formatPriceFigure } from '../lib/format'
import type { MarketGood } from '../lib/rpc'
import { useDeskGood } from '../store/deskGood'
import { useT } from '../lib/i18n'
import { CityGoodTrades } from './CityGoodTrades'
import { useWorld } from './worldStore'

// A GOOD, READ ON A QUAY SHE IS NOT ON — the tray a price cell opens when nobody of yours is
// alongside. MOVED 2026-09-11 from features/market/ with the MARKET tab, which folded into PORT
// (owner row 76, docs/QUAY_LEDGER.md §6 slice 1; RESUME.md had carried the fold as owed).
//
// The two prices, then the same Trend, Range and On-the-quay rows the trade tray draws —
// `PriceRows`, the design system's, composed from the one entrance and never retyped here — then
// how far this quay is from where she lies, as a figure. This file is not a third trade tray: it
// steps nothing, prices nothing and issues nothing.
//
// ── `Sail here` IS GONE (2026-09-09) ───────────────────────────────────────────────────────────
// It was a button that handed a SAIL intent to COMMAND's composer. The owner: *"they should be
// located accordingly at different locations"* — and SAIL's location is the MAP, where the owner
// drove it on production (docs/OWNER_REQUESTS.md rows 45/46). The passage stays as the figure it
// always was, and the act is one tab over, where every other passage is ordered from.

export function PriceTray({
  portId,
  good,
  trend,
  passage,
  mode,
  onClose,
}: {
  /** The quay being read — whose trades of this good the tray lists (0227). */
  portId: string
  good: MarketGood
  /** The good's price here over the chosen span, both sides — `usePriceSeries`'s one reading. */
  trend: PriceTrend
  /** The sailed distance from where she lies to this quay, or null when there is no figure. */
  passage: number | null
  /** Where the tray stands — PORT's docked default; the MAP's city panel slides it out beside
   *  itself (`side-next`), the pattern its ship panel uses. */
  mode?: TrayMode
  onClose: () => void
}) {
  const t = useT()
  const [detent, setDetent] = useState<TrayDetent>('half')
  // THE HAND-OFF (docs/COMMAND_DESK.md §3.3, D8; row 218): the map reads a place; the desk is where you act. A
  // good read here opens on COMMAND's Buy face — this city on its mini map, this good pressed on its list.
  const openOnDesk = useDeskGood((s) => s.open)
  const portCode = useWorld((s) => s.snapshot?.ports.find((p) => p.id === portId)?.code ?? null)
  const navigate = useNavigate()
  return (
    <Tray
      detent={detent}
      onDetentChange={(next) => (next === 'closed' ? onClose() : setDetent(next))}
      title={good.name}
      mode={mode}
      data-testid="price-tray"
    >
      <Row label={t('trade.buy')} value={<Figure value={formatPriceFigure(good.buy)} size="figure" />} />
      <Row label={t('trade.sell')} value={<Figure value={formatPriceFigure(good.sell)} size="figure" />} />
      <PriceRows good={good} trend={trend} />
      <Row
        label={t('trade.openInCommand')}
        chevron
        onClick={() => {
          openOnDesk(good.code, portCode)
          navigate('/command')
        }}
        data-testid="price-tray-desk"
      />
      {passage !== null && (
        <Row
          label={t('trade.distance')}
          value={<Figure value={formatMiles(passage)} />}
          hairline={false}
          data-testid="price-tray-passage"
        />
      )}
      <CityGoodTrades portId={portId} goodId={good.good_id} />
    </Tray>
  )
}
