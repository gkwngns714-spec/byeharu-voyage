import { useMemo, useState } from 'react'
import {
  Button,
  Clip,
  Empty,
  FactsLine,
  FilterBar,
  Figure,
  GoodKind,
  ListPanel,
  Note,
  Row,
  Skeleton,
  Sparkline,
  StatCell,
  StatRun,
  StockGauge,
  categoryLabel,
  deltaTone,
  goodClassRow,
  oneOf,
  rarityLabel,
  RARITY_TIERS,
  useFilterChoice,
} from '../../components/ui'
import { formatInt, formatPctChange, formatPriceFigure } from '../../lib/format'
import { t as tNow, useT } from '../../lib/i18n'
import { worldStatsMarkets, type StatsGood, type StatsMarkets } from '../../lib/rpc'
import { useWorld } from '../../live/worldStore'
import { goodName, movePct } from './statsFaces'
import { useLiveRead } from './statsLive'
import { ALL } from './statsFilters'
import { Block } from './StatsBlock'

// MARKETS — every good as a stock-market table, ALL ON THE FACE (owner, 2026-11-01, row 260). It was a day's four
// figures and three summary rows (Filter · Movers · Every good) with the filters, the movers and the 629
// goods on three pages. It is now the day's four figures and the movers over ONE list panel: the goods,
// with the filters (kind · rarity · sort) in the panel's own header and the window on the day it sets. A press on a good was never
// anything — the row is its own detail (its price, its move, what sold and bought, its stock).

const SORTS = ['movers', 'rose', 'fell', 'traded', 'price', 'class', 'name'] as const
type Window = '1h' | '1d' | '7d'
const FIRST = 60

interface GoodRank {
  g: StatsGood
  move: number | null
  traded: number
}

export function MarketsFace() {
  const t = useT()
  const read = useLiveRead<StatsMarkets>('stats:markets', () => worldStatsMarkets())
  const v = read.view
  const [choice, choose] = useFilterChoice('stats.markets', { kind: ALL, rarity: ALL, sort: 'movers' })
  const goodByCode = useWorld((s) => s.goodByCode)
  const [win, setWin] = useState<Window>('1d')
  const [all, setAll] = useState(false)
  const sort = oneOf(choice.sort, SORTS, 'movers')
  const kinds = useMemo(() => [...new Set((v?.goods ?? []).map((g) => g.category))].sort(), [v])
  const kind = oneOf(choice.kind, [ALL, ...kinds], ALL)
  const rarity = oneOf(choice.rarity, [ALL, ...RARITY_TIERS], ALL)

  const rows = useMemo<GoodRank[]>(() => {
    if (!v) return []
    const before = (g: StatsGood) => (win === '1h' ? g.mid_1h : win === '1d' ? g.mid_1d : g.mid_7d)
    const list = v.goods
      .filter((g) => (kind === ALL || g.category === kind) && (rarity === ALL || goodByCode[g.code]?.rarity === rarity))
      .map((g) => ({ g, move: movePct(g.mid, before(g)), traded: g.sold_1d + g.bought_1d }))
    const byName = (a: GoodRank, b: GoodRank) => a.g.name.localeCompare(b.g.name)
    // THE PREMIUM CLASS (0294) is the catalogue's served number, read by code; a good it has none for sorts last
    const classOf = (r: GoodRank) => goodByCode[r.g.code]?.class ?? 0
    if (sort === 'name') return list.sort(byName)
    if (sort === 'class') return list.sort((a, b) => classOf(b) - classOf(a) || (b.g.mid ?? -1) - (a.g.mid ?? -1) || byName(a, b))
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

  const above = (
    <>
      <Block
        title={t('stats.dayMarket')}
        // THE WINDOW IS THE DAY'S: it sets the rose and fell counts, the movers and every row's move, so it stands
        // on the block those figures are in, not among the list's filters (which then fit one line of a phone).
        aside={
          <FilterBar
            compact
            className="ml-auto"
            data-testid="stats-markets-window"
            picks={[
              {
                id: 'window',
                label: t('stats.windowLabel'),
                options: [
                  { id: '1h', label: t('stats.h1') },
                  { id: '1d', label: t('stats.d1') },
                  { id: '7d', label: t('stats.d7') },
                ],
                value: win,
                onChange: (id) => setWin(id as Window),
              },
            ]}
          />
        }
        data-testid="stats-markets-day"
      >
        <StatRun>
          <StatCell inline label={t('stats.goodsTraded')} value={rows.filter((r) => r.traded > 0).length} format={formatInt} size="body" />
          <StatCell inline label={t('stats.unitsTraded')} value={unitsTraded} format={formatInt} size="body" />
          <StatCell inline label={t('stats.rose', { window: windowWord(win) })} value={moved.filter((r) => (r.move ?? 0) > 0).length} format={formatInt} size="body" tone="success" />
          <StatCell inline label={t('stats.fell', { window: windowWord(win) })} value={moved.filter((r) => (r.move ?? 0) < 0).length} format={formatInt} size="body" tone="danger" />
        </StatRun>
      </Block>
      <Block title={t('stats.movers')} data-testid="stats-movers">
        <div className="grid grid-cols-3 gap-x-3 lg:grid-cols-1">
          <Board
            title={t('stats.risers')}
            testid="stats-risers"
            empty={t('stats.nothingRose')}
            rows={risers.map((r) => ({ id: r.g.code, label: goodName(r.g), text: formatPctChange(r.move ?? 0), tone: 'success' as const }))}
          />
          <Board
            title={t('stats.fallers')}
            testid="stats-fallers"
            empty={t('stats.nothingFell')}
            rows={fallers.map((r) => ({ id: r.g.code, label: goodName(r.g), text: formatPctChange(r.move ?? 0), tone: 'danger' as const }))}
          />
          <Board
            title={t('stats.mostTraded24')}
            testid="stats-most-traded"
            empty={t('stats.nothingTraded')}
            rows={traded.map((r) => ({ id: r.g.code, label: goodName(r.g), text: formatInt(r.traded), tone: 'ink' as const }))}
          />
        </div>
      </Block>
    </>
  )

  return (
    <ListPanel
      above={above}
      face={{ 'data-testid': 'stats-markets' }}
      title={t('stats.everyGood')}
      count={formatInt(rows.length)}
      trailing={
        <FilterBar
          compact
          data-testid="stats-markets-sort"
          sort={{
            id: 'sort',
            label: t('stats.sortLabel'),
            options: SORTS.map((id) => ({
              id,
              label: t(
                id === 'movers' ? 'stats.movers' : id === 'rose' ? 'stats.roseMost' : id === 'fell' ? 'stats.fellMost' : id === 'traded' ? 'stats.mostTraded' : id === 'price' ? 'stats.dearest' : id === 'class' ? 'stats.topClass' : 'stats.name',
              ),
            })),
            value: sort,
            onChange: (id) => choose({ sort: id }),
          }}
        />
      }
      controls={
        <FilterBar
          compact
          data-testid="stats-markets-filters"
          picks={[
            {
              id: 'kind',
              label: t('stats.kind'),
              options: [{ id: ALL, label: t('stats.allKinds') }, ...kinds.map((k) => ({ id: k, label: categoryLabel(k) }))],
              value: kind,
              onChange: (id) => choose({ kind: id }),
            },
            {
              id: 'rarity',
              label: t('stats.rarity'),
              options: [{ id: ALL, label: t('stats.anyRarity') }, ...RARITY_TIERS.map((r) => ({ id: r, label: rarityLabel(r) }))],
              value: rarity,
              onChange: (id) => choose({ rarity: id }),
            },
          ]}
        />
      }
      data-testid="stats-goods"
    >
      {rows.length === 0 && <Empty className="my-1" data-testid="stats-no-match">{t('stats.noMatch')}</Empty>}
      {shown.map((r, i) => (
        <GoodRow key={r.g.code} g={r.g} move={r.move} goodClass={goodByCode[r.g.code]?.class} last={i === shown.length - 1 && (all || rows.length <= FIRST)} />
      ))}
      {!all && rows.length > FIRST && (
        <div className="py-2">
          <Button variant="secondary" onClick={() => setAll(true)} data-testid="stats-show-all">
            {t('stats.showAll')}
          </Button>
        </div>
      )}
    </ListPanel>
  )
}

function windowWord(win: Window): string {
  return win === '1h' ? tNow('stats.wHour') : win === '1d' ? tNow('stats.wDay') : tNow('stats.wWeek')
}

interface BoardRow {
  id: string
  label: string
  text: string
  tone: 'success' | 'danger' | 'ink'
}

const BOARD_TONE = { success: 'text-success', danger: 'text-danger', ink: 'text-ink-muted' } as const

/** A MOVERS BOARD: three goods and their figures, a column of the face (the page it used to open held exactly
 *  these rows). Each entry is two lines — the good over its figure — so a column a third of the glass wide
 *  still reads a whole name; one that does not fit is cut with `Clip`, which carries the full name (a press on
 *  a glass with no hover reads it in place). */
function Board({ title, rows, empty, testid }: { title: string; rows: readonly BoardRow[]; empty: string; testid: string }) {
  return (
    <div className="min-w-0" data-testid={testid}>
      <span className="block text-t-caption text-ink-faint">{title}</span>
      {rows.length === 0 ? (
        <span className="block text-t-label text-ink-faint">{empty}</span>
      ) : (
        rows.map((r) => (
          <div key={r.id} className="min-w-0 pt-0.5">
            <Clip className="text-t-label text-ink">{r.label}</Clip>
            <span className={`block text-t-caption tabular-nums ${BOARD_TONE[r.tone]}`}>{r.text}</span>
          </div>
        ))
      )}
    </div>
  )
}

function GoodRow({ g, move, goodClass, last }: { g: StatsGood; move: number | null; goodClass: number | undefined; last: boolean }) {
  const t = useT()
  const tone = move === null || move === 0 ? 'even' : move > 0 ? 'dear' : 'cheap'
  return (
    <Row
      {...goodClassRow(goodClass)}
      label={
        <span className="flex min-w-0 items-center gap-2">
          <span className="min-w-0 break-words text-ink">{goodName(g)}</span>
          <span className="shrink-0 text-t-caption text-ink-faint">{categoryLabel(g.category)}</span>
          <GoodKind compact goodClass={goodClass} className="shrink-0" />
        </span>
      }
      // THE FIGURES FOLLOW THEIR NAME (owner, 2026-11-01, row 260: label and figure close): the line, the price and
      // the move stand 12 px behind the good, not in fixed columns at the row's edge — the alignment law now reads
      // a value's distance from its own label, so these are not `Col`s. A price or a move the server does not have
      // is not drawn (the absence is an absence, never a dash where a figure is owed — consistency law 5): a good no
      // city sells has no price, a record younger than the window has no move.
      value={
        <span className="flex items-center gap-3">
          {/* THE LINE WANTS ROOM: it stands only where the list is at least 24 rem wide. The PANEL's width decides, not
              the window's — a desktop's list stands beside the figures and is not as wide as the window. */}
          <span className="hidden @[24rem]:block">
            <Sparkline values={g.spark} tone={tone} width={48} height={18} label={t('stats.readings', { name: goodName(g), n: g.spark.length })} />
          </span>
          {g.mid !== null && <Figure value={formatPriceFigure(g.mid)} />}
          {move !== null && <Figure value={formatPctChange(move)} tone={deltaTone(move)} />}
        </span>
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
