import { Hint, Note, Row, SheetSection, Skeleton } from '../../../components/ui'
import { formatPrice } from '../../../lib/format'
import type { PriceWhy } from '../../../lib/rpc'
import { stakeLine, tariffLine, volumeLine, whyLines } from './whyLines'

// WHY THIS PRICE — the good page's breakdown (docs/PRICE_FACTORS.md §5, slice P1; migration 0185). The
// server (world.price_why) serves the market price at the focus city and every term it is made of, each as
// its multiplier; this face only NAMES them. It multiplies nothing and ranks by the served multipliers
// alone (whyLines.ts): the terms that move the price, largest effect first, and nothing for a term that is 1.

export function WhyThisPrice({ why, loading }: { why: PriceWhy | null; loading: boolean }) {
  const lines = why ? whyLines(why) : []
  const volume = why ? volumeLine(why) : null
  const tariff = why ? tariffLine(why) : null
  return (
    <SheetSection
      heading="Why this price"
      trailing={why ? <span className="text-t-caption text-ink-faint">base {formatPrice(why.base)}</span> : undefined}
      data-testid="why-price"
    >
      {why && stakeLine(why) && (
        <Hint className="mb-1" data-testid="why-stake">
          {stakeLine(why)}
        </Hint>
      )}
      {!why ? (
        loading ? (
          <Skeleton className="h-16 w-full" />
        ) : (
          <Note tone="neutral">No price for this city.</Note>
        )
      ) : lines.length === 0 ? (
        <Note tone="neutral">Nothing moves it: it sells at its base.</Note>
      ) : (
        lines.map((l) => (
          <Row
            key={l.key}
            label={l.label}
            value={<span className="whitespace-nowrap tabular-nums">{l.effect}</span>}
            data-testid="why-line"
          />
        ))
      )}
      {tariff && (
        <Row
          label={tariff.label}
          value={<span className="whitespace-nowrap tabular-nums">{tariff.value}</span>}
          data-testid="why-tariff"
        />
      )}
      {volume && (
        <Hint className="mt-1" data-testid="why-volume">
          {volume}
        </Hint>
      )}
    </SheetSection>
  )
}
