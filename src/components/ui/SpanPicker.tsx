import { Segmented } from './Chip'
import { PRICE_SPANS, type PriceSpan } from '../../lib/rpc'
import { useT } from '../../lib/i18n'

// HOW FAR BACK A PRICE CHART LOOKS — five plain words, one press each (0226, owner row 205: "i want to
// see them in weeks, years even"). The spans are the server's (`PRICE_SPANS`: what world.price_series
// answers), the words are the dictionary's, and the choice is the caller's (`useChartSpan`, one for
// every chart). A press SELECTS: this bar keeps its height and the chart changes in place; nothing
// under it moves (the desk's law, tests/desk.layout.spec.ts). Composed by `PriceRows` (both trays) and
// the COMMAND desk's good page — one picker, every chart.

export function SpanPicker({ value, onChange, className = '' }: { value: PriceSpan; onChange: (span: PriceSpan) => void; className?: string }) {
  const t = useT()
  const word: Record<PriceSpan, string> = {
    '1d': t('ui.span1d'),
    '1w': t('ui.span1w'),
    '1m': t('ui.span1m'),
    '1y': t('ui.span1y'),
    all: t('ui.spanAll'),
  }
  return (
    <div data-testid="span-picker" className={className}>
      <Segmented<PriceSpan>
        segments={PRICE_SPANS.map((s) => ({ id: s, label: word[s] }))}
        value={value}
        onChange={onChange}
        label={t('ui.chartSpan')}
        // EACH SPAN ON ONE LINE (owner, 2026-11-12: "1 / week", "1 / month" stood on two lines at 390 and 320). Five equal
        // columns gave "1 month" 33 px at 320. The strip is a wrapping line instead: a cell is as wide as its own word and they
        // share what is left, so all five stand on one line where they fit (267 px of the Market card's 280) and the last ones
        // go to a second line where they do not (a tray inside the City's panel is 218 px). No word is broken or cut.
        className="flex! flex-wrap [&>button]:flex-auto [&>button]:whitespace-nowrap [&>button]:px-1.5"
      />
    </div>
  )
}
