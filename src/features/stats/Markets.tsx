import { useEffect, useMemo, useState } from 'react'
import { Button, Empty, FactsLine, Figure, Hint, Note, Row, Segmented, SheetSection, Skeleton, Sparkline, StockGauge, categoryLabel, deltaTone } from '../../components/ui'
import { formatInt, formatPctChange, formatPriceFigure } from '../../lib/format'
import { worldStatsMarkets, type StatsGood, type StatsMarkets } from '../../lib/rpc'
import { useServedRead } from '../../live/useServedRead'
import type { FaceProps } from './StatsScreen'
import { movePct } from './statsFaces'

// MARKETS — every good as a stock-market table: price, its move, what was bought and sold, stock against
// normal, a line. Risers, fallers and the most traded on top. The figures are sums over EVERY market that
// sells a good (public), so no city can be read out of them; a city's own rows are the Cities face's, at
// your tier. Sorting is a view the player changes three times in ten seconds, so it is done here.

type Sort = 'movers' | 'traded' | 'name'
type Window = '1h' | '1d' | '7d'
const FIRST = 60

export function MarketsFace({ beat, onAge }: FaceProps) {
  const read = useServedRead<StatsMarkets>('stats:markets', () => worldStatsMarkets(), { trigger: beat })
  const v = read.view
  useEffect(() => onAge(v?.age_seconds ?? null), [v, onAge])
  const [sort, setSort] = useState<Sort>('movers')
  const [win, setWin] = useState<Window>('1d')
  const [all, setAll] = useState(false)

  const rows = useMemo(() => {
    if (!v) return []
    const before = (g: StatsGood) => (win === '1h' ? g.mid_1h : win === '1d' ? g.mid_1d : g.mid_7d)
    const list = v.goods.map((g) => ({ g, move: movePct(g.mid, before(g)), traded: g.sold_1d + g.bought_1d }))
    if (sort === 'name') return list.sort((a, b) => a.g.name.localeCompare(b.g.name))
    if (sort === 'traded') return list.sort((a, b) => b.traded - a.traded || a.g.name.localeCompare(b.g.name))
    return list.sort((a, b) => Math.abs(b.move ?? -1) - Math.abs(a.move ?? -1) || a.g.name.localeCompare(b.g.name))
  }, [v, sort, win])

  if (read.loading && !v) return <Skeleton className="h-64 w-full" data-testid="stats-waiting" />
  if (!v) return <Note tone="danger">The markets' figures could not be read.</Note>
  if (v.goods.length === 0) return <Empty data-testid="stats-empty">No figures yet. The first count is written within fifteen minutes.</Empty>

  const moved = rows.filter((r) => r.move !== null)
  const risers = [...moved].sort((a, b) => (b.move ?? 0) - (a.move ?? 0)).slice(0, 3)
  const fallers = [...moved].sort((a, b) => (a.move ?? 0) - (b.move ?? 0)).slice(0, 3)
  const traded = [...rows].sort((a, b) => b.traded - a.traded).slice(0, 3)
  const shown = all ? rows : rows.slice(0, FIRST)

  return (
    <div data-testid="stats-markets">
      <div className="flex flex-wrap items-center gap-2">
        <Segmented
          segments={[
            { id: 'movers', label: 'Movers' },
            { id: 'traded', label: 'Most traded' },
            { id: 'name', label: 'Name' },
          ]}
          value={sort}
          onChange={setSort}
          label="Sort the goods"
        />
        <Segmented
          segments={[
            { id: '1h', label: '1 h' },
            { id: '1d', label: '1 day' },
            { id: '7d', label: '7 days' },
          ]}
          value={win}
          onChange={setWin}
          label="The move's window"
        />
      </div>

      <div className="mt-4 grid grid-cols-1 gap-4 lg:grid-cols-3">
        <Top heading="Risers" rows={risers} testid="stats-risers" />
        <Top heading="Fallers" rows={fallers} testid="stats-fallers" />
        <Top heading="Most traded, 24 h" rows={traded} testid="stats-most-traded" units />
      </div>

      <SheetSection heading={`Every good · ${formatInt(v.goods.length)}`} surface data-testid="stats-goods">
        <Hint className="mb-2">Price is the mean where the good is sold. Sold and bought are the last 24 hours, every market. Stock against its normal level.</Hint>
        {shown.map((r, i) => (
          <GoodRow key={r.g.code} g={r.g} move={r.move} last={i === shown.length - 1} />
        ))}
        {!all && rows.length > FIRST && (
          <div className="pt-3">
            <Button variant="secondary" onClick={() => setAll(true)} data-testid="stats-show-all">
              {`Show all ${formatInt(rows.length)}`}
            </Button>
          </div>
        )}
      </SheetSection>
    </div>
  )
}

function Top({ heading, rows, testid, units = false }: { heading: string; rows: { g: StatsGood; move: number | null; traded: number }[]; testid: string; units?: boolean }) {
  return (
    <SheetSection heading={heading} surface data-testid={testid} className="mt-0 first:mt-0">
      {rows.length === 0 ? (
        <Row label="Nothing yet" tone="muted" hairline={false} />
      ) : (
        rows.map((r, i) => (
          <Row
            key={r.g.code}
            label={r.g.name}
            value={
              units ? (
                <Figure value={formatInt(r.traded)} unit="units" />
              ) : (
                <Figure value={formatPctChange(r.move ?? 0)} tone={deltaTone(r.move ?? 0)} />
              )
            }
            hairline={i < rows.length - 1}
          />
        ))
      )}
    </SheetSection>
  )
}

function GoodRow({ g, move, last }: { g: StatsGood; move: number | null; last: boolean }) {
  const tone = move === null || move === 0 ? 'even' : move > 0 ? 'dear' : 'cheap'
  return (
    <Row
      label={
        <span className="flex min-w-0 items-center gap-2">
          <span className="min-w-0 truncate text-ink">{g.name}</span>
          <span className="shrink-0 text-t-caption text-ink-faint">{categoryLabel(g.category)}</span>
        </span>
      }
      value={
        <span className="flex items-center gap-3">
          <Sparkline values={g.spark} tone={tone} width={48} height={18} label={`${g.name}, ${g.spark.length} readings`} />
          <span className="flex w-24 flex-col items-end">
            <Figure value={g.mid === null ? '—' : formatPriceFigure(g.mid)} />
            <Figure value={move === null ? '—' : formatPctChange(move)} tone={move === null ? 'faint' : deltaTone(move)} />
          </span>
        </span>
      }
      hairline={!last}
      data-testid="stats-good"
    >
      <FactsLine>
        <span>{`sold ${formatInt(g.sold_1d)}`}</span>
        <span>{`bought ${formatInt(g.bought_1d)}`}</span>
        {g.markets > 0 && <StockGauge stock={g.stock} target={g.stock_target} label={`${g.name}, every market`} className="shrink-0" />}
        {g.markets === 0 && <span>no city sells it</span>}
      </FactsLine>
    </Row>
  )
}
