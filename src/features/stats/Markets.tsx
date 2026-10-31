import { useMemo, useState } from 'react'
import {
  Button,
  Col,
  Cols,
  DetailPage,
  Empty,
  FactsLine,
  FilterBar,
  Figure,
  Note,
  RankBars,
  Row,
  SectionColumns,
  Segmented,
  SheetSection,
  Skeleton,
  Sparkline,
  StatCell,
  StockGauge,
  SummaryRow,
  categoryLabel,
  deltaTone,
  oneOf,
  rarityLabel,
  RARITY_TIERS,
  useFilterChoice,
  type RankRow,
} from '../../components/ui'
import { formatInt, formatPctChange, formatPriceFigure } from '../../lib/format'
import { t as tNow, useT } from '../../lib/i18n'
import { worldStatsMarkets, type StatsGood, type StatsMarkets } from '../../lib/rpc'
import { useWorld } from '../../live/worldStore'
import { goodName, movePct } from './statsFaces'
import { useLiveRead } from './statsLive'
import { ALL } from './statsFilters'

// MARKETS — every good as a stock-market table. THE COMPACT SCREEN (owner, 2026-10-31): the day's
// four figures stand; Filters, Movers and Every good are summary rows with their key figures, each
// opening its own full-screen page. The filter grids and the good list are whole on their pages.

const SORTS = ['movers', 'rose', 'fell', 'traded', 'price', 'name'] as const
type Window = '1h' | '1d' | '7d'
const FIRST = 60

interface GoodRank {
  g: StatsGood
  move: number | null
  traded: number
}

type Page = 'filters' | 'movers' | 'goods' | null

export function MarketsFace() {
  const t = useT()
  const read = useLiveRead<StatsMarkets>('stats:markets', () => worldStatsMarkets())
  const v = read.view
  const [choice, choose] = useFilterChoice('stats.markets', { kind: ALL, rarity: ALL, sort: 'movers' })
  const goodByCode = useWorld((s) => s.goodByCode)
  const [win, setWin] = useState<Window>('1d')
  const [all, setAll] = useState(false)
  const [page, setPage] = useState<Page>(null)
  const sort = oneOf(choice.sort, SORTS, 'movers')
  const kinds = useMemo(() => [...new Set((v?.goods ?? []).map((g) => g.category))].sort(), [v])
  const kind = oneOf(choice.kind, [ALL, ...kinds], ALL)
  const rarity = oneOf(choice.rarity, [ALL, ...RARITY_TIERS], ALL)
  const kindWord = kind === ALL ? t('stats.allKinds') : categoryLabel(kind)

  const rows = useMemo<GoodRank[]>(() => {
    if (!v) return []
    const before = (g: StatsGood) => (win === '1h' ? g.mid_1h : win === '1d' ? g.mid_1d : g.mid_7d)
    const list = v.goods
      .filter((g) => (kind === ALL || g.category === kind) && (rarity === ALL || goodByCode[g.code]?.rarity === rarity))
      .map((g) => ({ g, move: movePct(g.mid, before(g)), traded: g.sold_1d + g.bought_1d }))
    const byName = (a: GoodRank, b: GoodRank) => a.g.name.localeCompare(b.g.name)
    if (sort === 'name') return list.sort(byName)
    if (sort === 'traded') return list.sort((a, b) => b.traded - a.traded || byName(a, b))
    if (sort === 'price') return list.sort((a, b) => (b.g.mid ?? -1) - (a.g.mid ?? -1) || byName(a, b))
    if (sort === 'rose') return list.sort((a, b) => (b.move ?? -Infinity) - (a.move ?? -Infinity) || byName(a, b))
    if (sort === 'fell') return list.sort((a, b) => (a.move ?? Infinity) - (b.move ?? Infinity) || byName(a, b))
    return list.sort((a, b) => Math.abs(b.move ?? -1) - Math.abs(a.move ?? -1) || byName(a, b))
  }, [v, sort, win, kind, rarity, goodByCode])

  if (read.loading && !v) return <Skeleton className="h-64 w-full" data-testid="stats-waiting" />
  if (!v) return <Note tone="danger">{t('stats.marketsFailed')}</Note>
  if (v.goods.length === 0) return <Empty data-testid="stats-empty">{t('stats.noFigures')}</Empty>

  const moved = rows.filter((r) => r.move !== null)
  const risers = moved.filter((r) => (r.move ?? 0) > 0).sort((a, b) => (b.move ?? 0) - (a.move ?? 0)).slice(0, 3)
  const fallers = moved.filter((r) => (r.move ?? 0) < 0).sort((a, b) => (a.move ?? 0) - (b.move ?? 0)).slice(0, 3)
  const traded = rows.filter((r) => r.traded > 0).sort((a, b) => b.traded - a.traded).slice(0, 3)
  const shown = all ? rows : rows.slice(0, FIRST)
  const unitsTraded = rows.reduce((n, r) => n + r.traded, 0)

  return (
    <div data-testid="stats-markets">
      <SheetSection heading={t('stats.dayMarket')}>
        <div className="grid grid-cols-2 gap-x-4 gap-y-3 lg:grid-cols-4">
          <StatCell label={t('stats.goodsTraded')} value={rows.filter((r) => r.traded > 0).length} format={formatInt} />
          <StatCell label={t('stats.unitsTraded')} value={unitsTraded} format={formatInt} />
          <StatCell label={t('stats.rose', { window: windowWord(win) })} value={moved.filter((r) => (r.move ?? 0) > 0).length} format={formatInt} tone="success" />
          <StatCell label={t('stats.fell', { window: windowWord(win) })} value={moved.filter((r) => (r.move ?? 0) < 0).length} format={formatInt} tone="danger" />
        </div>
      </SheetSection>

      <div className="mt-2 flex flex-col gap-2">
        <SummaryRow title={t('stats.filterLabel')} figure={kindWord} word={t('common.open')} onClick={() => setPage('filters')} data-testid="stats-markets-filters" />
        <SummaryRow title={t('stats.movers')} figure={formatInt(moved.length)} word={t('common.open')} onClick={() => setPage('movers')} data-testid="stats-movers" />
        <SummaryRow title={t('stats.everyGood')} figure={formatInt(rows.length)} word={t('common.open')} onClick={() => setPage('goods')} data-testid="stats-goods" />
      </div>

      {page === 'filters' && (
        <DetailPage title={t('stats.filterLabel')} figure={kindWord} onClose={() => setPage(null)} data-testid="stats-markets-filters-page">
          <FilterBar
            data-testid="stats-markets-filters-bar"
            chips={{
              label: t('stats.kind'),
              options: [{ id: ALL, label: t('stats.allKinds') }, ...kinds.map((k) => ({ id: k, label: categoryLabel(k) }))],
              value: kind,
              onChange: (id) => choose({ kind: id }),
            }}
            picks={[
              {
                id: 'rarity',
                label: t('stats.rarity'),
                options: [{ id: ALL, label: t('stats.anyRarity') }, ...RARITY_TIERS.map((r) => ({ id: r, label: rarityLabel(r) }))],
                value: rarity,
                onChange: (id) => choose({ rarity: id }),
              },
            ]}
            sort={{
              id: 'sort',
              label: t('stats.sortLabel'),
              options: SORTS.map((id) => ({
                id,
                label: t(
                  id === 'movers' ? 'stats.movers' : id === 'rose' ? 'stats.roseMost' : id === 'fell' ? 'stats.fellMost' : id === 'traded' ? 'stats.mostTraded' : id === 'price' ? 'stats.dearest' : 'stats.name',
                ),
              })),
              value: sort,
              onChange: (id) => choose({ sort: id }),
            }}
          />
          <div className="mt-3 flex flex-wrap items-center gap-2">
            <Segmented
              segments={[
                { id: '1h', label: t('stats.h1') },
                { id: '1d', label: t('stats.d1') },
                { id: '7d', label: t('stats.d7') },
              ]}
              value={win}
              onChange={setWin}
              label={t('stats.windowLabel')}
            />
          </div>
        </DetailPage>
      )}

      {page === 'movers' && (
        <DetailPage title={t('stats.movers')} figure={formatInt(moved.length)} onClose={() => setPage(null)} data-testid="stats-movers-page">
          <SectionColumns count={3}>
            <SheetSection heading={t('stats.risers')} surface data-testid="stats-risers">
              <RankBars rows={movers(risers, 'success')} format={formatPctChange} empty={t('stats.nothingRose')} />
            </SheetSection>
            <SheetSection heading={t('stats.fallers')} surface data-testid="stats-fallers">
              <RankBars rows={movers(fallers, 'danger')} format={formatPctChange} empty={t('stats.nothingFell')} />
            </SheetSection>
            <SheetSection heading={t('stats.mostTraded24')} surface data-testid="stats-most-traded">
              <RankBars
                rows={traded.map((r) => ({ id: r.g.code, label: goodName(r.g), value: r.traded, text: t('format.units', { n: formatInt(r.traded), count: r.traded }) }))}
                format={formatInt}
                empty={t('stats.nothingTraded')}
              />
            </SheetSection>
          </SectionColumns>
        </DetailPage>
      )}

      {page === 'goods' && (
        <DetailPage title={t('stats.everyGood')} figure={formatInt(rows.length)} onClose={() => setPage(null)} data-testid="stats-goods-page">
          {rows.length === 0 && <Empty data-testid="stats-no-match">{t('stats.noMatch')}</Empty>}
          {shown.map((r, i) => (
            <GoodRow key={r.g.code} g={r.g} move={r.move} last={i === shown.length - 1} />
          ))}
          {!all && rows.length > FIRST && (
            <div className="pt-3">
              <Button variant="secondary" onClick={() => setAll(true)} data-testid="stats-show-all">
                {t('stats.showAll')}
              </Button>
            </div>
          )}
        </DetailPage>
      )}
    </div>
  )
}

function windowWord(win: Window): string {
  return win === '1h' ? tNow('stats.wHour') : win === '1d' ? tNow('stats.wDay') : tNow('stats.wWeek')
}

function movers(rows: readonly GoodRank[], tone: 'success' | 'danger'): RankRow[] {
  return rows.map((r) => ({ id: r.g.code, label: goodName(r.g), value: r.move ?? 0, tone }))
}

function GoodRow({ g, move, last }: { g: StatsGood; move: number | null; last: boolean }) {
  const t = useT()
  const tone = move === null || move === 0 ? 'even' : move > 0 ? 'dear' : 'cheap'
  return (
    <Row
      label={
        <span className="flex min-w-0 items-center gap-2">
          <span className="min-w-0 break-words text-ink">{goodName(g)}</span>
          <span className="shrink-0 text-t-caption text-ink-faint">{categoryLabel(g.category)}</span>
        </span>
      }
      value={
        <Cols>
          <Col w="md" phone="hide">
            <Sparkline values={g.spark} tone={tone} width={48} height={18} label={t('stats.readings', { name: goodName(g), n: g.spark.length })} />
          </Col>
          <Col w="sm">
            <Figure value={g.mid === null ? '—' : formatPriceFigure(g.mid)} />
          </Col>
          <Col w="sm">
            <Figure value={move === null ? '—' : formatPctChange(move)} tone={move === null ? 'faint' : deltaTone(move)} />
          </Col>
        </Cols>
      }
      hairline={!last}
      data-testid="stats-good"
    >
      <FactsLine>
        <span>{t('stats.sold', { n: formatInt(g.sold_1d) })}</span>
        <span>{t('stats.bought', { n: formatInt(g.bought_1d) })}</span>
        {g.markets > 0 && <StockGauge stock={g.stock} target={g.stock_target} label={t('stats.everyMarket', { name: goodName(g) })} className="shrink-0" />}
        {g.markets === 0 && <span>{t('stats.noCitySells')}</span>}
      </FactsLine>
    </Row>
  )
}
