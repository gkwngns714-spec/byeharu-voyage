import { Chip, Figure, Row } from '../../components/ui'
import { formatDucats } from '../../lib/format'
import type { FleetView } from '../../lib/rpc'
import type { SendFlow } from './useSendFleet'
import { useT } from '../../lib/i18n'

// UNDER THE PICKED FLEET — the one choice left before the send (0213): insure her cargo on this passage.
//
// This was KeepAndSend: the keep level (how many days of stores she sails under), a bar of what she
// carries against it, two presses and the book's preset chips. Owner row 203 (2026-10-25: *"what is
// this 'keep supply at'? this is useless"*) and 0225 made supplies automatic — every SAIL buys what its
// leg needs through `public.supply_need` — so nothing about stores is asked here any more.
//
// INSURE THE CARGO: one press, only when the dry run quoted a price — the server's figure for THIS
// passage and the cargo on board (`sailEstimate(...).insurance`). Off by default; on, the send writes
// `SAIL <dest> INSURED` and the port she sails from is paid the price at departure.

export function SendInsurance({ fleet: f, flow }: { fleet: FleetView; flow: SendFlow }) {
  const t = useT()
  const insurance = flow.insuranceOf(f)
  const insure = flow.insureOf(f)
  return (
    <div className="pb-2" data-testid="map-send-options">
      {insurance && (
        <Row
          hairline={false}
          label={
            <span className="flex items-baseline gap-2">
              {t('map.insurance')}
              <Figure value={<span data-testid="map-send-insurance-price">{formatDucats(insurance.price)}</span>} size="figure" />
            </span>
          }
          value={
            <Chip on={insure} onClick={() => flow.setInsure(f, !insure)} data-testid="map-send-insure">
              {t(insure ? 'map.insured' : 'map.insure')}
            </Chip>
          }
          data-testid="map-send-insurance"
        >
          <span className="block text-t-caption text-ink-faint">
            {insure
              ? t('map.insuredLine', { value: formatDucats(insurance.value) })
              : t('map.uninsuredLine', { value: formatDucats(insurance.value) })}
          </span>
        </Row>
      )}
    </div>
  )
}
