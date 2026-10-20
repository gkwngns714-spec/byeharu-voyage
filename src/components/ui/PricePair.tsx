import { Figure, type FigureSize } from './Figure'
import { COIN, formatPriceFigure } from '../../lib/format'
import { useT } from '../../lib/i18n'

// BOTH SIDES OF ONE PRICE, EACH UNDER ITS OWN WORD — what you pay here, what you get here.
//
// THE OWNER, 2026-10-20 (request 178): *"I press a city and it shows buying price, and selling price.
// But it is not known until I press it. I don't know if the city I press will show selling price, or
// buying price. Therefore, I want both for all cities."* A bare figure beside a city's name was the
// whole defect: the desk drew the ASK on the Buy at rows and the BID on the Sell at rows, in the same
// ink, in the same slot, and the chart's head drew the MIDDLE price — three meanings, one voice, and
// no word to tell them apart. This primitive exists so a price on this screen never stands without
// the side it is.
//
// IT PRINTS SERVED FIGURES AND DERIVES NOTHING. The two sides of a price are the server's and only
// the server's (`world.price_sides`, composed by `world.price` and by `world.quote_priced` — the
// spread, the tax and the city's bid factor; 0211's law that a round trip never pays). A caller hands
// over what was served; `null` means "the server did not price this side here" and prints as a dash,
// never as the other side with a sign flipped.
//
// WHEN NEITHER SIDE IS SERVED, `mid` — the market's MIDDLE price — stands in its place, dim and under
// its own word, so it is never read as a price one trader gets. A board prices the dearest
// `good_board_quoted` cities in full and serves the middle price for the rest (0171), so that is the
// ordinary state of a long sell ladder, not a fault.
//
// IN `block` FORM BOTH CELLS ARE ALWAYS DRAWN, dashed where nothing is served yet. A block head is
// measured: the desk's law is that pressing a city changes the chart IN PLACE and moves nothing below
// it (tests/desk.layout.spec.ts), and a pair that collapsed to one cell — or a skeleton of some other
// height standing in for it while the new city's price is on the wire — would move the page by those
// few pixels. The dash IS the waiting state, in the very markup the figure will take.

/** The dash a figure the server did not price prints as — the one the ticket's rows already use. */
const NO_FIGURE = '—'

export function PricePair({
  pay,
  get,
  mid = null,
  size = 'body',
  block = false,
  className = '',
}: {
  /** What ONE unit costs you here, served. Null: this city does not sell the good. */
  pay: number | null
  /** What ONE unit pays you here, served. Null: the server did not price this side here. */
  get: number | null
  /** The market's middle price here, served — stands in only when neither side was. */
  mid?: number | null
  size?: FigureSize
  /** Two cells with the word ABOVE each figure (a block's head), rather than two lines with it beside
   *  (a list row, where the figures stand in one narrow column). */
  block?: boolean
  className?: string
}) {
  const t = useT()
  const sides: { key: string; word: string; value: number | null; faint: boolean }[] =
    !block && pay === null && get === null
      ? [{ key: 'mid', word: t('ui.marketWord'), value: mid, faint: true }]
      : [
          { key: 'pay', word: t('ui.youPay'), value: pay, faint: false },
          { key: 'get', word: t('ui.youGet'), value: get, faint: false },
        ]

  return (
    <span
      className={[block ? 'flex flex-wrap items-end gap-x-6 gap-y-1' : 'flex flex-col items-end', className].join(' ')}
      data-testid="price-pair"
    >
      {sides.map((s) => (
        <span
          key={s.key}
          className={block ? 'flex min-w-0 flex-col' : 'flex items-baseline gap-1.5 whitespace-nowrap'}
          data-testid={`price-${s.key}`}
        >
          <span className="text-t-caption text-ink-faint">{s.word}</span>
          <Figure
            value={s.value === null ? NO_FIGURE : formatPriceFigure(s.value)}
            unit={COIN}
            size={size}
            tone={s.value === null || s.faint ? 'faint' : 'ink'}
          />
        </span>
      ))}
    </span>
  )
}
