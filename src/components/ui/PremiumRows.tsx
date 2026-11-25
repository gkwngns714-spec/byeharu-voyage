import { Figure } from './Figure'
import { Row } from './Row'
import { formatInt } from '../../lib/format'
import type { PremiumCity } from '../../lib/rpc'
import { useT } from '../../lib/i18n'

/**
 * 0517: A PREMIUM GOOD'S ONE CITY AND ITS PAY, as served (world.market's row, world.goods_forge's recipe): nothing is worked out here. The
 * city's name stands on its own row and is never shortened; under it what it pays and the units she may sell it at that now (nothing made: to make it first, and the day's limit). Nothing while dark.
 */
export function PremiumRows({ premium }: { premium: PremiumCity | undefined }) {
  const t = useT()
  if (premium === undefined) return null
  return (
    <>
      <Row label={t('ui.premiumCity')} value={<span className="text-t-body text-ink">{premium.name}</span>} data-testid="premium-city" />
      <Row
        label={t('ui.premiumPays')}
        value={<Figure value={`×${String(Number(premium.mult))}`} unit={Number(premium.made) <= 0 ? t('ui.premiumMake', { n: formatInt(Number(premium.per_day)) }) : t('ui.premiumLeft', { n: formatInt(Number(premium.mine)) })} />}
        data-testid="premium-pays"
      />
    </>
  )
}
