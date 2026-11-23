import { useLayoutEffect, useMemo, useRef } from 'react'
import { Icon, KEEP_WORDS_CLASS, goodIcon, tileToneClass, useWide } from '../../../components/ui'
import { PortFlag } from '../../../live/PortFlag'
import { portNameOf, useWorld } from '../../../live/worldStore'
import { formatPriceDelta } from '../../../lib/format'
import { properName, useT } from '../../../lib/i18n'
import type { BestSale } from '../../../lib/rpc'
import { fromHere } from './fromHereSales'

// THE "FROM HERE" LINE (roadmap 2026-11-23 slice 4, the client half; X3: the Routes tab folds into it). Where her fleet lies, the
// best sale to each of up to three harbours, as flag tiles: the flag and the harbour's name, the good's mark and the served profit.
// A tile pressed is that card pressed (Trade.tsx's `pressBest`): the trip, bought here and sold there, at the card's units.
// Every figure is a card's own (world.best_sales, fromHereSales.ts); nothing stands while no card pays.
//
// FEW WORDS (docs/design/visual-overhaul-2026-11-23.md, principle 1): on a phone the line is led by an anchor (where she lies) whose
// accessible name is the line's two words, and the tiles stand on ONE line of the glass, 44 px: the desk's face fits the glass with
// about 55 px in hand (tests/onepage.spec.ts), so a second line, or a tile three lines tall, would make it scroll. Each tile is as
// wide as its whole name on one line (never cut, never turned), and WHAT DOES NOT FIT GIVES WAY WHOLE, LAST FIRST (the goods card's
// own rule, live/TradeCard.tsx): the tiles run nearest first, so a long name leaves the farthest harbour to its card. A tile that
// gave way is hidden from sight and from the keyboard. In the wide desk's left pane, which is narrow and tall, the tiles stand one
// under another, under the anchor and the words, and a long name turns at its spaces.

export function FromHere({
  sales,
  open,
  onBest,
}: {
  /** The board's best sales, by good CODE (null until the read lands). */
  sales: ReadonlyMap<string, BestSale> | null
  /** The trip open on the desk (its good and the harbour it sells at), to light its tile. */
  open: { good: string; sellAt: string } | null
  onBest: (sale: BestSale) => void
}) {
  const t = useT()
  const wide = useWide()
  const portByCode = useWorld((s) => s.portByCode)
  const goodByCode = useWorld((s) => s.goodByCode)
  const best = useMemo(() => fromHere(sales), [sales])
  const row = useRef<HTMLDivElement>(null)
  useGiveWay(row, wide, best)
  if (best.length === 0) return null
  const label = t('desk.fromHere')

  const tiles = best.map((s) => {
    const port = s.port as string
    const city = portNameOf(portByCode, port)
    const good = goodByCode[s.good]
    const profit = formatPriceDelta(s.profit ?? 0)
    return {
      key: port,
      on: open !== null && open.good === s.good && open.sellAt === port,
      press: () => onBest(s),
      data: { 'data-testid': 'from-here-tile', 'data-port': port, 'data-good': s.good, 'data-profit': String(s.profit ?? '') },
      title: `${city} · ${properName('good', s.good, good?.name ?? s.good)} ${profit}`,
      city: (
        // the flag beside the name, never over it (a line of its own would make the tile a line taller); a long name turns at its
        // spaces beside the flag and is never cut
        <span className="flex items-center gap-1 leading-tight" data-testid="from-here-city">
          <PortFlag code={port} />
          <span className={wide ? KEEP_WORDS_CLASS : 'whitespace-nowrap'}>{city}</span>
        </span>
      ),
      profit: (
        <span className={`flex shrink-0 items-center gap-0.5 font-semibold tabular-nums text-success ${wide ? 'justify-end' : ''}`} data-testid="from-here-profit">
          <Icon name={goodIcon(s.good, good?.category ?? '')} size={14} className="shrink-0 text-ink-muted" />
          {profit}
        </span>
      ),
    }
  })

  if (wide)
    return (
      <div className="mb-2" data-testid="from-here" role="group" aria-label={label}>
        <span className="mb-1 flex items-center gap-1 text-t-caption text-ink-faint">
          <Icon name="anchor" size={14} className="text-accent" />
          {label}
        </span>
        <div className="flex flex-col gap-1.5">
          {tiles.map((x) => (
            <button
              key={x.key}
              type="button"
              aria-pressed={x.on}
              title={x.title}
              onClick={x.press}
              // two columns on fixed lines, so every tile's profit starts where the others' do (tests/align.spec.ts COLUMN)
              className={`grid min-h-11 w-full grid-cols-[minmax(0,1fr)_5.75rem] items-center gap-2 rounded-lg px-2 py-1 text-left text-t-caption transition ${tileToneClass(x.on)}`}
              {...x.data}
            >
              {x.city}
              {x.profit}
            </button>
          ))}
        </div>
      </div>
    )

  return (
    <div className="mb-2 flex items-center gap-1.5" data-testid="from-here" role="group" aria-label={label}>
      <Icon name="anchor" size={18} className="shrink-0 text-accent" />
      {/* one line, 44 px: a tile that wraps stands a whole row (gap-y-4) under the cut and is hidden (useGiveWay) */}
      <div ref={row} className="flex h-11 min-w-0 flex-1 flex-wrap gap-x-1.5 gap-y-4 overflow-hidden" data-testid="from-here-tiles">
        {tiles.map((x) => (
          <button
            key={x.key}
            type="button"
            aria-pressed={x.on}
            title={x.title}
            onClick={x.press}
            className={`flex h-11 flex-auto flex-col items-center justify-center rounded-lg px-2 text-t-caption transition ${tileToneClass(x.on)}${x.on ? ' ring-inset' : ''}`}
            {...x.data}
          >
            {x.city}
            {x.profit}
          </button>
        ))}
      </div>
    </div>
  )
}

/** WHAT DOES NOT FIT GIVES WAY WHOLE: a tile that wrapped below the line's first row is hidden (`visibility`), so it is neither seen
 *  nor reached by the keyboard. Re-read when the line is resized or the tiles change. Nothing on the wide desk's stack. */
function useGiveWay(row: { current: HTMLDivElement | null }, wide: boolean, tiles: readonly BestSale[]) {
  useLayoutEffect(() => {
    const el = row.current
    if (wide || !el) return
    const lay = () => {
      const cells = [...el.children].filter((c): c is HTMLElement => c instanceof HTMLElement)
      const top = cells[0]?.offsetTop ?? 0
      for (const c of cells) {
        const out = c.offsetTop > top
        c.style.visibility = out ? 'hidden' : ''
        c.toggleAttribute('data-gave-way', out)
      }
    }
    lay()
    const seen = new ResizeObserver(lay)
    seen.observe(el)
    return () => seen.disconnect()
  }, [row, wide, tiles])
}
